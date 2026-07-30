import {
  apnsHost,
  buildAPNSHeaders,
  buildAPNSPayload,
  type NotificationPayloadRecord,
} from "./payload.ts"

function notification(overrides: Partial<NotificationPayloadRecord> = {}): NotificationPayloadRecord {
  return {
    id: "10000000-0000-0000-0000-000000000001",
    title: "Maya Chen",
    subtitle: "Sunshine Room",
    body: "Lena had a great lunch today.",
    safe_body: "Sent a message",
    category: "chat_message",
    priority: "routine",
    thread_key: "chat:20000000-0000-0000-0000-000000000001",
    interruption_level: "active",
    route: {
      type: "chat_room",
      id: "20000000-0000-0000-0000-000000000001",
      message_id: "30000000-0000-0000-0000-000000000001",
      ignored_private_value: "do-not-send",
    },
    ...overrides,
  }
}

Deno.test("chat payload hides text by default and keeps identifiers", () => {
  const payload = buildAPNSPayload({ notification: notification(), unreadCount: 3 })
  const aps = payload.aps as Record<string, unknown>
  const alert = aps.alert as Record<string, string>
  if (alert.body !== "Sent a message") throw new Error("Expected privacy-safe chat body")
  if (alert.title !== "Maya Chen" || alert.subtitle !== "Sunshine Room") throw new Error("Missing sender context")
  if (aps.badge !== 3 || aps["thread-id"] == null) throw new Error("Missing badge or thread")
  if ("ignored_private_value" in payload.route) throw new Error("Route leaked a non-identifier field")
  if ("category" in payload) throw new Error("Payload leaked non-route metadata outside aps")
})

Deno.test("full preview is opt-in for chat only", () => {
  const payload = buildAPNSPayload({
    notification: notification(),
    settings: { message_preview_mode: "full" },
    unreadCount: 1,
  })
  const alert = (payload.aps.alert as Record<string, string>)
  if (alert.body !== "Lena had a great lunch today.") throw new Error("Expected full chat preview")
})

Deno.test("private care payload never exposes canonical body", () => {
  const payload = buildAPNSPayload({
    notification: notification({
      category: "care_health_check",
      body: "Temperature 102.4 F",
      safe_body: "Open FireflyFM to view this private update.",
      interruption_level: "time_sensitive",
    }),
    settings: { message_preview_mode: "full" },
    unreadCount: 1,
  })
  const alert = (payload.aps.alert as Record<string, string>)
  if (alert.body.includes("102.4")) throw new Error("Private care detail leaked")
})

Deno.test("passive and active APNs headers use the correct priorities", () => {
  const passive = buildAPNSHeaders({
    authorization: "token",
    bundleID: "com.fireflyfm.app",
    interruptionLevel: "passive",
    expirationTimestamp: 123,
  })
  const active = buildAPNSHeaders({
    authorization: "token",
    bundleID: "com.fireflyfm.app",
    interruptionLevel: "active",
    expirationTimestamp: 123,
  })
  if (passive["apns-priority"] !== "5") throw new Error("Passive pushes must use priority 5")
  if (active["apns-priority"] !== "10") throw new Error("Active pushes must use priority 10")
  if (passive["apns-push-type"] !== "alert") throw new Error("Expected APNs alert push type")
})

Deno.test("development and production device tokens use separate APNs hosts", () => {
  if (apnsHost("development") !== "https://api.sandbox.push.apple.com") {
    throw new Error("Development token was not routed to sandbox APNs")
  }
  if (apnsHost("production") !== "https://api.push.apple.com") {
    throw new Error("Production token was not routed to production APNs")
  }
})

Deno.test("payload remains below the APNs four kilobyte limit", () => {
  const payload = buildAPNSPayload({
    notification: notification({
      title: "T".repeat(5_000),
      subtitle: "S".repeat(5_000),
      body: "B".repeat(10_000),
      safe_body: "P".repeat(10_000),
    }),
    unreadCount: 999,
  })
  const byteCount = new TextEncoder().encode(JSON.stringify(payload)).byteLength
  if (byteCount >= 4_096) throw new Error(`Payload was ${byteCount} bytes`)
})
