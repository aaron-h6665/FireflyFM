export type JsonRecord = Record<string, unknown>

type BillingEnvironment = {
  supabaseURL: string
  serviceRoleKey: string
  stripeSecretKey: string
  webhookSecret?: string
  connectReturnURL?: string
  connectRefreshURL?: string
}

export type AuthenticatedUser = {
  id: string
  email?: string
  aal?: string
}

export class BillingError extends Error {
  constructor(message: string, readonly status = 400) {
    super(message)
  }
}

export function environment(): BillingEnvironment {
  const supabaseURL = requiredEnvironment("SUPABASE_URL")
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")
    ?? Deno.env.get("SUPABASE_SECRET_KEY")
  if (!serviceRoleKey) throw new Error("SUPABASE_SERVICE_ROLE_KEY is required")
  return {
    supabaseURL,
    serviceRoleKey,
    stripeSecretKey: requiredEnvironment("STRIPE_SECRET_KEY"),
    webhookSecret: Deno.env.get("STRIPE_CONNECT_WEBHOOK_SECRET"),
    connectReturnURL: Deno.env.get("STRIPE_CONNECT_RETURN_URL"),
    connectRefreshURL: Deno.env.get("STRIPE_CONNECT_REFRESH_URL"),
  }
}

export function json(payload: unknown, status = 200): Response {
  return new Response(JSON.stringify(payload), {
    status,
    headers: { "content-type": "application/json" },
  })
}

export function errorResponse(error: unknown): Response {
  if (error instanceof BillingError) return json({ error: error.message }, error.status)
  console.error(error instanceof Error ? error.message : String(error))
  return json({ error: "The billing service could not complete this request." }, 500)
}

export function requirePost(request: Request) {
  if (request.method !== "POST") throw new BillingError("Method not allowed", 405)
  const contentLength = Number(request.headers.get("content-length") ?? "0")
  if (contentLength > 64 * 1024) throw new BillingError("Request is too large", 413)
}

export async function authenticatedUser(request: Request): Promise<AuthenticatedUser> {
  const authorization = request.headers.get("authorization")
  if (!authorization?.match(/^Bearer\s+\S+/i)) throw new BillingError("Unauthorized", 401)
  const env = environment()
  const response = await fetch(`${env.supabaseURL}/auth/v1/user`, {
    headers: { apikey: env.serviceRoleKey, authorization },
  })
  if (!response.ok) throw new BillingError("Unauthorized", 401)
  const user = await response.json() as { id?: string; email?: string }
  if (!user.id) throw new BillingError("Unauthorized", 401)
  return { id: user.id, email: user.email, aal: decodeJWTPayload(authorization)?.aal as string | undefined }
}

export async function requireSchoolDirector(schoolID: string, userID: string) {
  assertUUID(schoolID, "schoolId")
  const rows = await adminRows<{ id: string }>(
    `school_memberships?select=id&school_id=eq.${schoolID}&user_id=eq.${userID}`
      + "&role=eq.school_director&active=eq.true&access_state=eq.full&limit=1",
  )
  if (rows.length === 0) throw new BillingError("A school director is required", 403)
}

export async function requireHQDirector(userID: string) {
  const rows = await adminRows<{ id: string }>(
    `school_memberships?select=id&user_id=eq.${userID}`
      + "&role=eq.hq_director&active=eq.true&access_state=eq.full&limit=1",
  )
  if (rows.length === 0) throw new BillingError("An HQ director is required", 403)
}

export async function requireLiveBillingAssurance(user: AuthenticatedUser) {
  const env = environment()
  const explicit = (Deno.env.get("BILLING_REQUIRE_AAL2") ?? "").toLowerCase()
  // A configuration flag may tighten test mode, but it can never weaken the
  // assurance requirement when a live Stripe key is present.
  const required = explicit === "true" || env.stripeSecretKey.startsWith("sk_live_")
  if (required && user.aal !== "aal2") {
    throw new BillingError("Multi-factor authentication is required for live billing", 403)
  }
}

export async function adminRows<T>(path: string, init: RequestInit = {}): Promise<T[]> {
  const value = await adminRequest<T[]>(path, init)
  return value ?? []
}

export async function adminRequest<T = unknown>(path: string, init: RequestInit = {}): Promise<T> {
  const env = environment()
  const response = await fetch(`${env.supabaseURL}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: env.serviceRoleKey,
      authorization: `Bearer ${env.serviceRoleKey}`,
      "content-type": "application/json",
      prefer: "return=representation",
      ...init.headers,
    },
  })
  const responseText = await response.text()
  if (!response.ok) throw new Error(`Supabase ${path}: ${response.status} ${responseText}`)
  return (responseText ? JSON.parse(responseText) : undefined) as T
}

export async function authAdminUser(
  userID: string,
): Promise<{ id: string; email?: string; email_confirmed_at?: string | null }> {
  const env = environment()
  const response = await fetch(`${env.supabaseURL}/auth/v1/admin/users/${encodeURIComponent(userID)}`, {
    headers: {
      apikey: env.serviceRoleKey,
      authorization: `Bearer ${env.serviceRoleKey}`,
    },
  })
  if (!response.ok) throw new BillingError("The selected parent's verified email could not be loaded", 422)
  return await response.json()
}

export async function stripeRequest<T extends JsonRecord>(
  method: "GET" | "POST",
  path: string,
  fields: Record<string, string | number | boolean | null | undefined> = {},
  connectedAccount?: string,
  idempotencyKey?: string,
): Promise<T> {
  const env = environment()
  const headers: Record<string, string> = {
    authorization: `Bearer ${env.stripeSecretKey}`,
  }
  if (connectedAccount) headers["Stripe-Account"] = connectedAccount
  if (idempotencyKey) headers["Idempotency-Key"] = idempotencyKey
  let url = `https://api.stripe.com/v1/${path}`
  let body: string | undefined
  const parameters = new URLSearchParams()
  for (const [key, value] of Object.entries(fields)) {
    if (value !== undefined && value !== null) parameters.append(key, String(value))
  }
  if (method === "GET") {
    const query = parameters.toString()
    if (query) url += `?${query}`
  } else {
    headers["content-type"] = "application/x-www-form-urlencoded"
    body = parameters.toString()
  }
  const response = await fetch(url, { method, headers, body })
  const text = await response.text()
  const payload = (text ? JSON.parse(text) : {}) as T & { error?: { message?: string } }
  if (!response.ok) {
    throw new BillingError(payload.error?.message ?? "Stripe rejected the request", response.status < 500 ? 422 : 502)
  }
  return payload
}

export function assertUUID(value: unknown, name: string): asserts value is string {
  if (typeof value !== "string" || !/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) {
    throw new BillingError(`${name} must be a UUID`)
  }
}

export function assertIdempotencyKey(value: unknown): asserts value is string {
  if (typeof value !== "string" || value.length < 8 || value.length > 200 || !/^[A-Za-z0-9:_-]+$/.test(value)) {
    throw new BillingError("A valid idempotencyKey is required")
  }
}

export function unixDate(value: unknown): string | null {
  return typeof value === "number" && Number.isFinite(value)
    ? new Date(value * 1000).toISOString()
    : null
}

export async function sha256(value: string): Promise<string> {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value))
  return hex(new Uint8Array(digest))
}

export async function verifyStripeSignature(
  body: string,
  signatureHeader: string | null,
  secret: string,
  nowSeconds = Math.floor(Date.now() / 1000),
): Promise<boolean> {
  if (!signatureHeader) return false
  const parts = signatureHeader.split(",").map((part) => part.trim().split("=", 2))
  const timestamp = Number(parts.find(([key]) => key === "t")?.[1])
  const signatures = parts.filter(([key]) => key === "v1").map(([, value]) => value)
  if (!Number.isFinite(timestamp) || Math.abs(nowSeconds - timestamp) > 300 || signatures.length === 0) return false
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  )
  const signed = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(`${timestamp}.${body}`))
  const expected = hex(new Uint8Array(signed))
  return signatures.some((candidate) => timingSafeEqual(candidate, expected))
}

export function paymentStatusForInvoice(invoiceStatus: unknown, amountPaid: unknown): string {
  if (invoiceStatus === "paid" || (typeof amountPaid === "number" && amountPaid > 0)) return "succeeded"
  if (invoiceStatus === "void" || invoiceStatus === "uncollectible") return "failed"
  return "pending"
}

function decodeJWTPayload(authorization: string): JsonRecord | undefined {
  try {
    const token = authorization.replace(/^Bearer\s+/i, "")
    const payload = token.split(".")[1].replace(/-/g, "+").replace(/_/g, "/")
    const padded = payload.padEnd(Math.ceil(payload.length / 4) * 4, "=")
    return JSON.parse(atob(padded))
  } catch {
    return undefined
  }
}

function timingSafeEqual(left: string, right: string): boolean {
  if (left.length !== right.length) return false
  let mismatch = 0
  for (let index = 0; index < left.length; index++) mismatch |= left.charCodeAt(index) ^ right.charCodeAt(index)
  return mismatch === 0
}

function hex(bytes: Uint8Array): string {
  return Array.from(bytes).map((byte) => byte.toString(16).padStart(2, "0")).join("")
}

function requiredEnvironment(name: string): string {
  const value = Deno.env.get(name)
  if (!value) throw new Error(`${name} is required`)
  return value
}
