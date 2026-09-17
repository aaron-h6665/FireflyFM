// Per-selection Google Drive Picker flow for assignment materials and submissions.
// The mobile app receives selected file bytes, never Google access or refresh tokens.

import {
  AssignmentDriveFile,
  AssignmentDriveValidationError,
  DRIVE_FILE_SCOPE,
  googleDownloadURL,
  normalizeDriveFile,
  normalizePickedFileIds,
  readLimitedBody,
} from "./picker.ts"

type ContextKind = "material_create" | "material_manage" | "submission"

type RequestBody = {
  action?: "start" | "complete" | "download" | "finish"
  contextKind?: ContextKind
  schoolId?: string
  assignmentId?: string
  state?: string
  code?: string
  pickedFileIds?: string[] | string
  allowsMultiple?: boolean
  operationId?: string
  fileId?: string
}

type PickerOperation = {
  id: string
  user_id: string
  school_id: string
  assignment_id: string | null
  context_kind: ContextKind
  allows_multiple: boolean
  state_hash: string
  pkce_verifier_ciphertext: string | null
  pkce_verifier_iv: string | null
  access_token_ciphertext: string | null
  access_token_iv: string | null
  selected_files: AssignmentDriveFile[]
  oauth_completed_at: string | null
  expires_at: string
  consumed_at: string | null
}

const json = (payload: unknown, status = 200) => new Response(JSON.stringify(payload), {
  status,
  headers: { "content-type": "application/json", "cache-control": "no-store" },
})

class AssignmentDriveError extends Error {
  constructor(message: string, readonly status = 400) { super(message) }
}

export async function handleRequest(request: Request): Promise<Response> {
  try {
    if (request.method !== "POST") throw new AssignmentDriveError("Method not allowed", 405)
    const body = await request.json() as RequestBody
    const authorization = request.headers.get("authorization") ?? ""
    const user = await authenticatedUser(authorization)

    switch (body.action) {
      case "start":
        return json(await startPicker(authorization, user.id, body))
      case "complete":
        return json(await completePicker(authorization, user.id, body))
      case "download":
        return await downloadFile(authorization, user.id, body)
      case "finish":
        await finishPicker(user.id, requiredUUID(body.operationId, "operationId"))
        return json({ finished: true })
      default:
        throw new AssignmentDriveError("Unknown Google Drive picker action")
    }
  } catch (error) {
    const known = error instanceof AssignmentDriveError || error instanceof AssignmentDriveValidationError
    if (!known) console.error(error instanceof Error ? error.message : String(error))
    return json(
      { error: known ? error.message : "Google Drive could not complete this request." },
      error instanceof AssignmentDriveError ? error.status : known ? 422 : 500,
    )
  }
}

if (import.meta.main) Deno.serve(handleRequest)

async function startPicker(authorization: string, userId: string, body: RequestBody) {
  const contextKind = requiredContextKind(body.contextKind)
  const schoolId = requiredUUID(body.schoolId, "schoolId")
  const assignmentId = contextKind === "material_create"
    ? undefined
    : requiredUUID(body.assignmentId, "assignmentId")
  await requireContextAuthorization(authorization, contextKind, schoolId, assignmentId)

  await admin(`google_drive_assignment_operations?expires_at=lt.${encodeURIComponent(new Date().toISOString())}`, {
    method: "DELETE",
    headers: { prefer: "return=minimal" },
  })

  const state = base64URL(randomBytes(32))
  const verifier = base64URL(randomBytes(64))
  const challenge = await sha256Base64URL(verifier)
  const encryptedVerifier = await encrypt(verifier)
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString()
  const rows = await admin<PickerOperation[]>("google_drive_assignment_operations", {
    method: "POST",
    body: JSON.stringify({
      user_id: userId,
      school_id: schoolId,
      assignment_id: assignmentId ?? null,
      context_kind: contextKind,
      allows_multiple: body.allowsMultiple !== false,
      state_hash: await sha256Hex(state),
      pkce_verifier_ciphertext: encryptedVerifier.ciphertext,
      pkce_verifier_iv: encryptedVerifier.iv,
      expires_at: expiresAt,
    }),
  })
  const operation = rows[0]
  if (!operation) throw new Error("Google Drive picker operation was not saved")

  const redirect = googleOAuthRedirect()
  const parameters = new URLSearchParams({
    client_id: requiredEnvironment("GOOGLE_DRIVE_PICKER_OAUTH_CLIENT_ID"),
    redirect_uri: redirect.uri,
    response_type: "code",
    scope: DRIVE_FILE_SCOPE,
    state,
    code_challenge: challenge,
    code_challenge_method: "S256",
    access_type: "online",
    prompt: "consent",
    trigger_onepick: "true",
    allow_multiple: body.allowsMultiple === false ? "false" : "true",
    include_granted_scopes: "false",
  })
  return {
    operationId: operation.id,
    authorizationURL: `https://accounts.google.com/o/oauth2/v2/auth?${parameters}`,
    callbackScheme: redirect.callbackScheme,
    expiresAt,
  }
}

async function completePicker(authorization: string, userId: string, body: RequestBody) {
  const state = requireText(body.state, "state")
  const code = requireText(body.code, "authorization code")
  const selectedIds = normalizePickedFileIds(body.pickedFileIds)
  const operations = await admin<PickerOperation[]>(
    `google_drive_assignment_operations?select=*&user_id=eq.${encodeURIComponent(userId)}`
      + `&state_hash=eq.${await sha256Hex(state)}&limit=1`,
  )
  const operation = requireActiveOperation(operations[0])
  if (operation.oauth_completed_at) throw new AssignmentDriveError("This Google Drive selection was already completed.", 409)
  if (!operation.allows_multiple && selectedIds.length !== 1) {
    throw new AssignmentDriveError("Choose one Google Drive file for this replacement.", 422)
  }
  await requireContextAuthorization(
    authorization,
    operation.context_kind,
    operation.school_id,
    operation.assignment_id ?? undefined,
  )

  if (!operation.pkce_verifier_ciphertext || !operation.pkce_verifier_iv) {
    throw new AssignmentDriveError("This Google Drive selection was already completed.", 409)
  }
  const verifier = await decrypt(operation.pkce_verifier_ciphertext, operation.pkce_verifier_iv)
  const token = await exchangeCode(code, verifier)
  const grantedScopes = new Set(String(token.scope ?? "").split(" ").filter(Boolean))
  if (grantedScopes.size !== 1 || !grantedScopes.has(DRIVE_FILE_SCOPE)) {
    throw new AssignmentDriveError("Google returned unexpected Drive permissions. Start the selection again.", 422)
  }

  const files: AssignmentDriveFile[] = []
  for (const fileId of selectedIds) {
    const metadata = await googleJSON<{
      id: string
      name: string
      mimeType: string
      size?: string
      capabilities?: { canDownload?: boolean }
    }>(
      `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(fileId)}`
        + "?fields=id,name,mimeType,size,capabilities(canDownload)&supportsAllDrives=true",
      token.access_token,
    )
    files.push(normalizeDriveFile(metadata))
  }

  const encryptedToken = await encrypt(token.access_token)
  const expiresAt = new Date(Date.now() + 10 * 60 * 1000).toISOString()
  await admin(`google_drive_assignment_operations?id=eq.${encodeURIComponent(operation.id)}&oauth_completed_at=is.null`, {
    method: "PATCH",
    body: JSON.stringify({
      access_token_ciphertext: encryptedToken.ciphertext,
      access_token_iv: encryptedToken.iv,
      pkce_verifier_ciphertext: null,
      pkce_verifier_iv: null,
      selected_files: files,
      oauth_completed_at: new Date().toISOString(),
      expires_at: expiresAt,
    }),
  })
  return { operationId: operation.id, files, expiresAt }
}

async function downloadFile(authorization: string, userId: string, body: RequestBody) {
  const operationId = requiredUUID(body.operationId, "operationId")
  const fileId = requireText(body.fileId, "fileId")
  const operations = await admin<PickerOperation[]>(
    `google_drive_assignment_operations?select=*&id=eq.${encodeURIComponent(operationId)}`
      + `&user_id=eq.${encodeURIComponent(userId)}&limit=1`,
  )
  const operation = requireActiveOperation(operations[0])
  await requireContextAuthorization(
    authorization,
    operation.context_kind,
    operation.school_id,
    operation.assignment_id ?? undefined,
  )
  if (!operation.access_token_ciphertext || !operation.access_token_iv || !operation.oauth_completed_at) {
    throw new AssignmentDriveError("Complete the Google Drive selection before downloading files.", 409)
  }
  const file = operation.selected_files.find((candidate) => candidate.id === fileId)
  if (!file) throw new AssignmentDriveError("This file was not selected in the active Google Drive picker.", 403)

  const accessToken = await decrypt(operation.access_token_ciphertext, operation.access_token_iv)
  const response = await fetch(googleDownloadURL(file), {
    headers: { authorization: `Bearer ${accessToken}` },
  })
  if (!response.ok) {
    const payload = await response.json().catch(() => ({})) as { error?: { message?: string } }
    throw new AssignmentDriveError(payload.error?.message ?? "Google Drive could not download the selected file.", 502)
  }
  const bytes = await readLimitedBody(response)
  return new Response(bytes, {
    status: 200,
    headers: {
      "content-type": file.mimeType || "application/octet-stream",
      "content-length": String(bytes.byteLength),
      "content-disposition": `attachment; filename*=UTF-8''${encodeURIComponent(file.name)}`,
      "cache-control": "no-store",
      "x-content-type-options": "nosniff",
    },
  })
}

async function finishPicker(userId: string, operationId: string) {
  await admin(
    `google_drive_assignment_operations?id=eq.${encodeURIComponent(operationId)}`
      + `&user_id=eq.${encodeURIComponent(userId)}&consumed_at=is.null`,
    {
      method: "PATCH",
      body: JSON.stringify({
        pkce_verifier_ciphertext: null,
        pkce_verifier_iv: null,
        access_token_ciphertext: null,
        access_token_iv: null,
        selected_files: [],
        consumed_at: new Date().toISOString(),
      }),
    },
  )
}

function requireActiveOperation(operation: PickerOperation | undefined): PickerOperation {
  if (!operation || operation.consumed_at || new Date(operation.expires_at).getTime() <= Date.now()) {
    throw new AssignmentDriveError("This Google Drive selection expired. Start again from FireflyFM.", 422)
  }
  return operation
}

async function requireContextAuthorization(
  authorization: string,
  contextKind: ContextKind,
  schoolId: string,
  assignmentId?: string,
) {
  const allowed = await userRPC<boolean>("authorize_google_drive_assignment_import", authorization, {
    input_context_kind: contextKind,
    input_school_id: schoolId,
    input_assignment_id: assignmentId ?? null,
  })
  if (allowed !== true) throw new AssignmentDriveError("You no longer have permission to attach files here.", 403)
}

async function exchangeCode(code: string, verifier: string) {
  const parameters = new URLSearchParams({
    client_id: requiredEnvironment("GOOGLE_DRIVE_PICKER_OAUTH_CLIENT_ID"),
    redirect_uri: googleOAuthRedirect().uri,
    grant_type: "authorization_code",
    code,
    code_verifier: verifier,
  })
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "content-type": "application/x-www-form-urlencoded" },
    body: parameters,
  })
  const payload = await response.json().catch(() => ({})) as {
    access_token?: string
    refresh_token?: string
    scope?: string
    error_description?: string
  }
  if (!response.ok || !payload.access_token) {
    throw new AssignmentDriveError(payload.error_description ?? "Google authorization failed.", 502)
  }
  // A refresh token is intentionally ignored and never persisted.
  return payload as { access_token: string; scope?: string }
}

async function googleJSON<T>(url: string, accessToken: string): Promise<T> {
  const response = await fetch(url, { headers: { authorization: `Bearer ${accessToken}` } })
  const payload = await response.json().catch(() => ({})) as T & { error?: { message?: string } }
  if (!response.ok) throw new AssignmentDriveError(payload.error?.message ?? "Google Drive could not inspect the selected file.", 502)
  return payload
}

async function authenticatedUser(authorization: string) {
  if (!authorization.match(/^Bearer\s+\S+/i)) throw new AssignmentDriveError("Unauthorized", 401)
  const response = await fetch(`${requiredEnvironment("SUPABASE_URL")}/auth/v1/user`, {
    headers: { apikey: requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY"), authorization },
  })
  const user = await response.json().catch(() => ({})) as { id?: string }
  if (!response.ok || !user.id) throw new AssignmentDriveError("Unauthorized", 401)
  return user as { id: string }
}

async function userRPC<T>(name: string, authorization: string, body: unknown): Promise<T> {
  const response = await fetch(`${requiredEnvironment("SUPABASE_URL")}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY"),
      authorization,
      "content-type": "application/json",
    },
    body: JSON.stringify(body),
  })
  const text = await response.text()
  if (!response.ok) throw new AssignmentDriveError(text || "Assignment authorization failed.", 403)
  return (text ? JSON.parse(text) : undefined) as T
}

async function admin<T = unknown>(path: string, init: RequestInit = {}): Promise<T> {
  const key = requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY")
  const response = await fetch(`${requiredEnvironment("SUPABASE_URL")}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: key,
      authorization: `Bearer ${key}`,
      "content-type": "application/json",
      prefer: "return=representation",
      ...init.headers,
    },
  })
  const text = await response.text()
  if (!response.ok) throw new Error(`Supabase ${path}: ${response.status} ${text}`)
  return (text ? JSON.parse(text) : undefined) as T
}

async function encrypt(value: string) {
  const iv = randomBytes(12)
  const encrypted = await crypto.subtle.encrypt(
    { name: "AES-GCM", iv },
    await encryptionKey(),
    new TextEncoder().encode(value),
  )
  return { ciphertext: base64URL(new Uint8Array(encrypted)), iv: base64URL(iv) }
}

async function decrypt(ciphertext: string, iv: string) {
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: base64URLBytes(iv) },
    await encryptionKey(),
    base64URLBytes(ciphertext),
  )
  return new TextDecoder().decode(plaintext)
}

let cachedEncryptionKey: CryptoKey | undefined
async function encryptionKey() {
  if (cachedEncryptionKey) return cachedEncryptionKey
  const material = base64URLBytes(requiredEnvironment("GOOGLE_DRIVE_PICKER_TOKEN_ENCRYPTION_KEY"))
  if (material.byteLength !== 32) {
    throw new AssignmentDriveError("GOOGLE_DRIVE_PICKER_TOKEN_ENCRYPTION_KEY must be a base64url 32-byte key", 503)
  }
  cachedEncryptionKey = await crypto.subtle.importKey("raw", material, "AES-GCM", false, ["encrypt", "decrypt"])
  return cachedEncryptionKey
}

function googleOAuthRedirect() {
  const uri = requiredEnvironment("GOOGLE_DRIVE_PICKER_OAUTH_REDIRECT_URI")
  let parsed: URL
  try {
    parsed = new URL(uri)
  } catch {
    throw new AssignmentDriveError("GOOGLE_DRIVE_PICKER_OAUTH_REDIRECT_URI is invalid", 503)
  }
  const callbackScheme = parsed.protocol.replace(":", "")
  const validCustomScheme = /^[a-z][a-z0-9+.-]*$/i.test(callbackScheme) && callbackScheme.includes(".")
  if (!validCustomScheme || parsed.host || parsed.pathname !== "/oauth2redirect" || parsed.search || parsed.hash) {
    throw new AssignmentDriveError(
      "GOOGLE_DRIVE_PICKER_OAUTH_REDIRECT_URI must be a reverse-domain iOS callback ending in /oauth2redirect",
      503,
    )
  }
  return { uri, callbackScheme }
}

function requiredContextKind(value: unknown): ContextKind {
  if (value === "material_create" || value === "material_manage" || value === "submission") return value
  throw new AssignmentDriveError("A valid assignment import context is required")
}

function requiredUUID(value: unknown, label: string) {
  if (typeof value !== "string" || !/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(value)) {
    throw new AssignmentDriveError(`${label} must be a UUID`)
  }
  return value
}

function requireText(value: unknown, label: string) {
  if (typeof value !== "string" || value.trim().length === 0 || value.length > 4096) {
    throw new AssignmentDriveError(`A valid ${label} is required`)
  }
  return value.trim()
}

function requiredEnvironment(name: string) {
  const value = Deno.env.get(name)?.trim()
  if (!value) throw new AssignmentDriveError(`${name} is not configured`, 503)
  return value
}

function randomBytes(size: number) {
  const value = new Uint8Array(size)
  crypto.getRandomValues(value)
  return value
}
function base64URL(value: Uint8Array) {
  let text = ""
  for (const byte of value) text += String.fromCharCode(byte)
  return btoa(text).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "")
}
function base64URLBytes(value: string) {
  const padded = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=")
  return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0))
}
async function sha256Hex(value: string) {
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value))
  return Array.from(new Uint8Array(hash)).map((byte) => byte.toString(16).padStart(2, "0")).join("")
}
async function sha256Base64URL(value: string) {
  const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value))
  return base64URL(new Uint8Array(hash))
}
