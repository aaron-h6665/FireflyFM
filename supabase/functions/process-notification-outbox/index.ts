import { apnsHost, buildAPNSHeaders, buildAPNSPayload } from "./payload.ts"

type OutboxRow = {
  id: string
  notification_id: string
  user_id: string
  attempt_count: number
}

type NotificationRow = {
  id: string
  title: string
  subtitle: string | null
  body: string
  safe_body: string | null
  category: string
  priority: "routine" | "important" | "urgent"
  thread_key: string | null
  interruption_level: "passive" | "active" | "time_sensitive"
  route: Record<string, unknown>
}

type DeviceTokenRow = {
  id: string
  token: string
  bundle_id: string | null
  environment: string | null
}

type UserNotificationSettingsRow = {
  message_preview_mode: "sender_only" | "full"
}

const supabaseURL = requiredEnvironment("SUPABASE_URL")
const serviceRoleKey = requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY")
const workerSecret = Deno.env.get("OUTBOX_WORKER_SECRET")
const apnsTeamID = Deno.env.get("APNS_TEAM_ID")
const apnsKeyID = Deno.env.get("APNS_KEY_ID")
const apnsPrivateKey = Deno.env.get("APNS_PRIVATE_KEY")
const defaultBundleID = Deno.env.get("APNS_BUNDLE_ID")
const defaultEnvironment = Deno.env.get("APNS_ENVIRONMENT") ?? "development"

let cachedAPNSToken: { value: string; createdAt: number } | undefined

Deno.serve(async (request) => {
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405)
  if (!isAuthorized(request)) return json({ error: "Unauthorized" }, 401)

  const missingAPNS = [apnsTeamID, apnsKeyID, apnsPrivateKey, defaultBundleID]
    .some((value) => !value)
  if (missingAPNS) {
    return json({
      error: "APNs is not configured",
      required: ["APNS_TEAM_ID", "APNS_KEY_ID", "APNS_PRIVATE_KEY", "APNS_BUNDLE_ID"],
    }, 503)
  }

  try {
    const medication = await rpc<Record<string, number>>("process_due_medication_tasks", {})
    const outbox = await rpc<OutboxRow[]>("claim_notification_outbox", { input_limit: 100 })
    const results = await Promise.all(outbox.map(deliverOutboxItem))
    return json({
      claimed: outbox.length,
      delivered: results.filter((result) => result.succeeded).length,
      failed: results.filter((result) => !result.succeeded).length,
      medication,
    })
  } catch (error) {
    return json({ error: errorMessage(error) }, 500)
  }
})

async function deliverOutboxItem(item: OutboxRow) {
  try {
    const notifications = await rest<NotificationRow[]>(
      `notifications?id=eq.${encodeURIComponent(item.notification_id)}&select=id,title,subtitle,body,safe_body,category,priority,thread_key,interruption_level,route`,
    )
    const notification = notifications[0]
    if (!notification) throw new Error("Notification no longer exists")

    const tokens = await rest<DeviceTokenRow[]>(
      `device_tokens?user_id=eq.${encodeURIComponent(item.user_id)}&platform=eq.ios&select=id,token,bundle_id,environment`,
    )
    if (tokens.length === 0) throw new Error("No active iOS device token")

    const [settings, unreadCount] = await Promise.all([
      rest<UserNotificationSettingsRow[]>(
        `user_notification_settings?user_id=eq.${encodeURIComponent(item.user_id)}&select=message_preview_mode&limit=1`,
      ).then((rows) => rows[0]),
      rpc<number>("notification_unread_count", { input_user_id: item.user_id }),
    ])

    let delivered = false
    const failures: string[] = []
    for (const device of tokens) {
      const result = await sendAPNS(device, notification, settings, unreadCount)
      if (result.succeeded) delivered = true
      else if (result.invalidToken) await deleteDeviceToken(device.id)
      else failures.push(result.error ?? "Unknown APNs failure")
    }
    if (!delivered) throw new Error(failures.join("; ") || "No valid iOS device token")

    await rpc("complete_notification_delivery", {
      input_outbox_id: item.id,
      input_succeeded: true,
      input_error: null,
    })
    return { id: item.id, succeeded: true }
  } catch (error) {
    const message = errorMessage(error)
    await rpc("complete_notification_delivery", {
      input_outbox_id: item.id,
      input_succeeded: false,
      input_error: message,
    }).catch(() => undefined)
    return { id: item.id, succeeded: false, error: message }
  }
}

async function sendAPNS(
  device: DeviceTokenRow,
  notification: NotificationRow,
  settings: UserNotificationSettingsRow | undefined,
  unreadCount: number,
) {
  const authorization = await apnsAuthorizationToken()
  const host = apnsHost(device.environment ?? defaultEnvironment)
  const bundleID = device.bundle_id ?? defaultBundleID!
  const payload = buildAPNSPayload({ notification, settings, unreadCount })
  const response = await fetch(`${host}/3/device/${device.token}`, {
    method: "POST",
    headers: buildAPNSHeaders({
      authorization,
      bundleID,
      interruptionLevel: notification.interruption_level,
      expirationTimestamp: Math.floor(Date.now() / 1000) + 24 * 60 * 60,
    }),
    body: JSON.stringify(payload),
  })
  if (response.ok) return { succeeded: true, invalidToken: false }

  const responsePayload = await response.json().catch(() => ({})) as { reason?: string }
  const reason = responsePayload.reason ?? `APNs HTTP ${response.status}`
  const invalidToken = ["BadDeviceToken", "DeviceTokenNotForTopic", "Unregistered"].includes(reason)
  return { succeeded: false, invalidToken, error: reason }
}

async function apnsAuthorizationToken() {
  const now = Math.floor(Date.now() / 1000)
  if (cachedAPNSToken && now - cachedAPNSToken.createdAt < 50 * 60) return cachedAPNSToken.value

  const header = base64URL(JSON.stringify({ alg: "ES256", kid: apnsKeyID }))
  const claims = base64URL(JSON.stringify({ iss: apnsTeamID, iat: now }))
  const signingInput = `${header}.${claims}`
  const pem = apnsPrivateKey!.replace(/\\n/g, "\n")
  const keyBytes = Uint8Array.from(
    atob(pem.replace(/-----BEGIN PRIVATE KEY-----|-----END PRIVATE KEY-----|\s/g, "")),
    (character) => character.charCodeAt(0),
  )
  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyBytes,
    { name: "ECDSA", namedCurve: "P-256" },
    false,
    ["sign"],
  )
  const signature = await crypto.subtle.sign(
    { name: "ECDSA", hash: "SHA-256" },
    key,
    new TextEncoder().encode(signingInput),
  )
  const value = `${signingInput}.${base64URL(new Uint8Array(signature))}`
  cachedAPNSToken = { value, createdAt: now }
  return value
}

async function rpc<T = unknown>(name: string, parameters: Record<string, unknown>): Promise<T> {
  return await rest<T>(`rpc/${name}`, { method: "POST", body: JSON.stringify(parameters) })
}

async function deleteDeviceToken(id: string) {
  await rest(`device_tokens?id=eq.${encodeURIComponent(id)}`, { method: "DELETE" })
}

async function rest<T = unknown>(path: string, init: RequestInit = {}): Promise<T> {
  const response = await fetch(`${supabaseURL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: serviceRoleKey,
      authorization: `Bearer ${serviceRoleKey}`,
      "content-type": "application/json",
      prefer: "return=representation",
      ...init.headers,
    },
  })
  if (!response.ok) throw new Error(`${path}: ${await response.text()}`)
  const text = await response.text()
  return (text ? JSON.parse(text) : undefined) as T
}

function isAuthorized(request: Request) {
  const bearer = request.headers.get("authorization")?.replace(/^Bearer\s+/i, "")
  const suppliedSecret = request.headers.get("x-outbox-worker-secret")
  return bearer === serviceRoleKey || (!!workerSecret && suppliedSecret === workerSecret)
}

function requiredEnvironment(name: string) {
  const value = Deno.env.get(name)
  if (!value) throw new Error(`${name} is required`)
  return value
}

function base64URL(value: string | Uint8Array) {
  const bytes = typeof value === "string" ? new TextEncoder().encode(value) : value
  let binary = ""
  for (const byte of bytes) binary += String.fromCharCode(byte)
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "")
}

function errorMessage(error: unknown) {
  return error instanceof Error ? error.message : String(error)
}

function json(payload: unknown, status = 200) {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json" },
  })
}
