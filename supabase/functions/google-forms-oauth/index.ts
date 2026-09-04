// Director-owned Google OAuth for onboarding Forms.  Refresh tokens never
// cross the client boundary and are AES-GCM encrypted before persistence.

type RequestBody = {
  action?: "start" | "complete" | "forms" | "inspect" | "connect"
  schoolId?: string
  credentialId?: string
  code?: string
  state?: string
  formId?: string
  formKey?: string
  formRole?: "parent" | "teacher"
  isRequired?: boolean
  displayOrder?: number
  mappings?: unknown[]
  templateRequirementId?: string | null
}

type OAuthOperation = {
  id: string
  school_id: string
  director_id: string
  pkce_verifier_ciphertext: string
  pkce_verifier_iv: string
  expires_at: string
  consumed_at: string | null
}

type Credential = {
  id: string
  school_id: string
  director_id: string
  google_account_email: string
  refresh_token_ciphertext: string
  refresh_token_iv: string
  status: string
}

const json = (payload: unknown, status = 200) => new Response(JSON.stringify(payload), {
  status,
  headers: { "content-type": "application/json", "cache-control": "no-store" },
})

class GoogleFormsError extends Error {
  constructor(message: string, readonly status = 400) { super(message) }
}

Deno.serve(async (request) => {
  try {
    if (request.method !== "POST") throw new GoogleFormsError("Method not allowed", 405)
    const body = await request.json() as RequestBody
    const user = await authenticatedUser(request)
    const schoolId = requiredUUID(body.schoolId, "schoolId")
    await requireDirector(schoolId, user.id)

    switch (body.action) {
      case "start":
        return json(await startOAuth(schoolId, user.id))
      case "complete":
        return json(await completeOAuth(schoolId, user.id, body.state, body.code))
      case "forms":
        return json({ forms: await listForms(schoolId, user.id, requiredUUID(body.credentialId, "credentialId")) })
      case "inspect":
        return json(await inspectForm(schoolId, user.id, requiredUUID(body.credentialId, "credentialId"), requireText(body.formId, "formId")))
      case "connect":
        return json(await connectForm(request, body, schoolId, user.id))
      default:
        throw new GoogleFormsError("Unknown Google Forms action")
    }
  } catch (error) {
    const known = error instanceof GoogleFormsError
    if (!known) console.error(error instanceof Error ? error.message : String(error))
    return json({ error: known ? error.message : "Google Forms could not complete this request." }, known ? error.status : 500)
  }
})

async function startOAuth(schoolId: string, directorId: string) {
  const redirect = googleOAuthRedirect()
  const state = base64URL(randomBytes(32))
  const verifier = base64URL(randomBytes(64))
  const challenge = await sha256Base64URL(verifier)
  const encrypted = await encrypt(verifier)
  await admin("google_oauth_operations", {
    method: "POST",
    body: JSON.stringify({
      school_id: schoolId,
      director_id: directorId,
      state_hash: await sha256Hex(state),
      pkce_verifier_ciphertext: encrypted.ciphertext,
      pkce_verifier_iv: encrypted.iv,
      expires_at: new Date(Date.now() + 10 * 60 * 1000).toISOString(),
    }),
  })
  const parameters = new URLSearchParams({
    client_id: requiredEnvironment("GOOGLE_FORMS_OAUTH_CLIENT_ID"),
    redirect_uri: redirect.uri,
    response_type: "code",
    scope: [
      "https://www.googleapis.com/auth/forms.body.readonly",
      "https://www.googleapis.com/auth/forms.responses.readonly",
      "https://www.googleapis.com/auth/drive.readonly",
      "openid", "email",
    ].join(" "),
    state,
    code_challenge: challenge,
    code_challenge_method: "S256",
    access_type: "offline",
    prompt: "consent",
  })
  return {
    authorizationURL: `https://accounts.google.com/o/oauth2/v2/auth?${parameters}`,
    callbackScheme: redirect.callbackScheme,
  }
}

async function completeOAuth(schoolId: string, directorId: string, suppliedState: unknown, suppliedCode: unknown) {
  const state = requireText(suppliedState, "state")
  const code = requireText(suppliedCode, "authorization code")
  const operations = await admin<OAuthOperation[]>(
    `google_oauth_operations?select=*&school_id=eq.${encodeURIComponent(schoolId)}`
      + `&director_id=eq.${encodeURIComponent(directorId)}&state_hash=eq.${await sha256Hex(state)}&limit=1`,
  )
  const operation = operations[0]
  if (!operation || operation.consumed_at || new Date(operation.expires_at).getTime() <= Date.now()) {
    throw new GoogleFormsError("This Google connection link has expired. Start again from FireflyFM.", 422)
  }
  const verifier = await decrypt(operation.pkce_verifier_ciphertext, operation.pkce_verifier_iv)
  const tokens = await exchangeCode(code, verifier)
  if (!tokens.refresh_token) throw new GoogleFormsError("Google did not return an offline refresh token. Try connecting again and approve access.", 422)
  const profile = await googleJSON<{ email?: string }>("https://openidconnect.googleapis.com/v1/userinfo", tokens.access_token)
  const email = profile.email?.trim().toLowerCase()
  if (!email) throw new GoogleFormsError("Google did not provide the connected account email.", 422)
  const encrypted = await encrypt(tokens.refresh_token)
  const credentialRows = await admin<Credential[]>("google_oauth_credentials?on_conflict=school_id,google_account_email", {
    method: "POST",
    headers: { prefer: "resolution=merge-duplicates,return=representation" },
    body: JSON.stringify({
      school_id: schoolId,
      director_id: directorId,
      google_account_email: email,
      refresh_token_ciphertext: encrypted.ciphertext,
      refresh_token_iv: encrypted.iv,
      granted_scopes: String(tokens.scope ?? "").split(" ").filter(Boolean),
      status: "connected",
      last_error: null,
      last_used_at: new Date().toISOString(),
      updated_at: new Date().toISOString(),
    }),
  })
  const credential = credentialRows[0]
  if (!credential) throw new Error("Google credential was not saved")
  await admin(`google_oauth_operations?id=eq.${encodeURIComponent(operation.id)}&consumed_at=is.null`, {
    method: "PATCH",
    body: JSON.stringify({ consumed_at: new Date().toISOString() }),
  })
  return { credentialId: credential.id, accountEmail: credential.google_account_email }
}

async function listForms(schoolId: string, directorId: string, credentialId: string) {
  const { credential, accessToken } = await accessForCredential(schoolId, directorId, credentialId)
  const query = new URLSearchParams({
    q: "mimeType = 'application/vnd.google-apps.form' and trashed = false",
    pageSize: "100",
    orderBy: "modifiedTime desc",
    fields: "files(id,name,webViewLink,modifiedTime),nextPageToken",
  })
  const drive = await googleJSON<{ files?: { id: string; name?: string; webViewLink?: string; modifiedTime?: string }[] }>(
    `https://www.googleapis.com/drive/v3/files?${query}`, accessToken,
  )
  return (drive.files ?? []).map((form) => ({
    id: form.id,
    title: form.name ?? "Untitled Form",
    editURL: form.webViewLink ?? null,
    accountEmail: credential.google_account_email,
  }))
}

async function inspectForm(schoolId: string, directorId: string, credentialId: string, formId: string) {
  const { credential, accessToken } = await accessForCredential(schoolId, directorId, credentialId)
  const form = await googleJSON<GoogleForm>(`https://forms.googleapis.com/v1/forms/${encodeURIComponent(formId)}`, accessToken)
  return normalizeForm(form, credential.google_account_email)
}

async function connectForm(request: Request, body: RequestBody, schoolId: string, directorId: string) {
  const credentialId = requiredUUID(body.credentialId, "credentialId")
  const formId = requireText(body.formId, "formId")
  const { credential, accessToken } = await accessForCredential(schoolId, directorId, credentialId)
  const form = normalizeForm(await googleJSON<GoogleForm>(`https://forms.googleapis.com/v1/forms/${encodeURIComponent(formId)}`, accessToken), credential.google_account_email)
  const role = body.formRole ?? inferRole(body.mappings)
  if (role !== "parent" && role !== "teacher") throw new GoogleFormsError("Choose a parent or teacher onboarding form.")
  if (!Array.isArray(body.mappings)) throw new GoogleFormsError("Map the Form questions before connecting it.")
  const auth = request.headers.get("authorization")!
  const rows = await userRPC<GoogleFormConnection[]>("upsert_google_form_connection_v2", auth, {
    input_school_id: schoolId,
    input_credential_id: credentialId,
    input_form_role: role,
    input_form_key: body.formKey?.trim() || form.id,
    input_form_id: form.id,
    input_form_url: form.responderURL,
    input_form_title: form.title,
    input_google_account_email: credential.google_account_email,
    input_is_required: body.isRequired ?? true,
    input_display_order: Math.max(0, Math.floor(body.displayOrder ?? 0)),
    input_form_snapshot: form.snapshot,
    input_mappings: body.mappings,
    input_template_requirement_id: body.templateRequirementId ?? null,
  })
  return rows[0]
}

function inferRole(mappings: unknown[] | undefined) {
  const keys = (mappings ?? []).map((value) => isRecord(value) ? value.field_key : undefined)
  return keys.includes("child_first_name") || keys.includes("submission_reference") ? "parent" : "teacher"
}

type GoogleForm = {
  formId?: string
  info?: { title?: string }
  responderUri?: string
  items?: { title?: string; questionItem?: { question?: { questionId?: string; required?: boolean } } }[]
}

function normalizeForm(form: GoogleForm, accountEmail: string) {
  const id = form.formId
  const responderURL = form.responderUri
  if (!id || !responderURL) throw new GoogleFormsError("Google did not return a usable responder link for this Form.", 422)
  const questions = (form.items ?? []).flatMap((item) => {
    const question = item.questionItem?.question
    return question?.questionId ? [{
      id: question.questionId,
      title: item.title ?? "Untitled question",
      required: question.required ?? false,
    }] : []
  })
  return {
    id,
    title: form.info?.title ?? "Untitled Form",
    responderURL,
    accountEmail,
    questions,
    snapshot: { id, title: form.info?.title ?? "Untitled Form", responderURL, questions },
  }
}

async function accessForCredential(schoolId: string, directorId: string, credentialId: string) {
  const credentials = await admin<Credential[]>(
    `google_oauth_credentials?select=*&id=eq.${encodeURIComponent(credentialId)}`
      + `&school_id=eq.${encodeURIComponent(schoolId)}&director_id=eq.${encodeURIComponent(directorId)}&limit=1`,
  )
  const credential = credentials[0]
  if (!credential || credential.status !== "connected") throw new GoogleFormsError("Reconnect the Google account before selecting Forms.", 409)
  try {
    const refreshToken = await decrypt(credential.refresh_token_ciphertext, credential.refresh_token_iv)
    const token = await refreshAccessToken(refreshToken)
    await admin(`google_oauth_credentials?id=eq.${encodeURIComponent(credential.id)}`, {
      method: "PATCH",
      body: JSON.stringify({ last_used_at: new Date().toISOString(), last_error: null, updated_at: new Date().toISOString() }),
    })
    return { credential, accessToken: token.access_token }
  } catch (error) {
    await admin(`google_oauth_credentials?id=eq.${encodeURIComponent(credential.id)}`, {
      method: "PATCH",
      body: JSON.stringify({ status: "needs_reconnect", last_error: "Google authorization needs to be reconnected.", updated_at: new Date().toISOString() }),
    }).catch(() => undefined)
    throw error instanceof GoogleFormsError ? error : new GoogleFormsError("Google authorization needs to be reconnected.", 409)
  }
}

async function exchangeCode(code: string, verifier: string) {
  return await tokenRequest({
    grant_type: "authorization_code", code, code_verifier: verifier,
    redirect_uri: googleOAuthRedirect().uri,
  })
}

async function refreshAccessToken(refreshToken: string) {
  return await tokenRequest({ grant_type: "refresh_token", refresh_token: refreshToken })
}

async function tokenRequest(fields: Record<string, string>) {
  const parameters = new URLSearchParams({ client_id: requiredEnvironment("GOOGLE_FORMS_OAUTH_CLIENT_ID"), ...fields })
  const clientSecret = Deno.env.get("GOOGLE_FORMS_OAUTH_CLIENT_SECRET")?.trim()
  if (clientSecret) parameters.set("client_secret", clientSecret)
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: parameters,
  })
  const payload = await response.json().catch(() => ({})) as { access_token?: string; refresh_token?: string; scope?: string; error_description?: string }
  if (!response.ok || !payload.access_token) throw new GoogleFormsError(payload.error_description ?? "Google authorization failed.", 502)
  return payload as { access_token: string; refresh_token?: string; scope?: string }
}

async function googleJSON<T>(url: string, accessToken: string): Promise<T> {
  const response = await fetch(url, { headers: { authorization: `Bearer ${accessToken}` } })
  const payload = await response.json().catch(() => ({})) as T & { error?: { message?: string } }
  if (!response.ok) throw new GoogleFormsError(payload.error?.message ?? "Google Forms could not be read.", response.status === 401 ? 409 : 502)
  return payload
}

async function authenticatedUser(request: Request) {
  const authorization = request.headers.get("authorization")
  if (!authorization?.match(/^Bearer\s+\S+/i)) throw new GoogleFormsError("Unauthorized", 401)
  const response = await fetch(`${requiredEnvironment("SUPABASE_URL")}/auth/v1/user`, {
    headers: { apikey: requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY"), authorization },
  })
  const user = await response.json().catch(() => ({})) as { id?: string }
  if (!response.ok || !user.id) throw new GoogleFormsError("Unauthorized", 401)
  return user as { id: string }
}

async function requireDirector(schoolId: string, userId: string) {
  const rows = await admin<{ id: string }[]>(
    `school_memberships?select=id&school_id=eq.${encodeURIComponent(schoolId)}`
      + `&user_id=eq.${encodeURIComponent(userId)}&role=eq.school_director&active=eq.true&limit=1`,
  )
  if (rows.length === 0) throw new GoogleFormsError("A school director is required", 403)
}

async function userRPC<T>(name: string, authorization: string, body: unknown): Promise<T> {
  const response = await fetch(`${requiredEnvironment("SUPABASE_URL")}/rest/v1/rpc/${name}`, {
    method: "POST",
    headers: {
      apikey: requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY"), authorization,
      "content-type": "application/json", prefer: "return=representation",
    },
    body: JSON.stringify(body),
  })
  const text = await response.text()
  if (!response.ok) throw new GoogleFormsError("The Form could not be connected: " + (text || "request rejected"), 422)
  return (text ? JSON.parse(text) : undefined) as T
}

async function admin<T = unknown>(path: string, init: RequestInit = {}): Promise<T> {
  const key = requiredEnvironment("SUPABASE_SERVICE_ROLE_KEY")
  const response = await fetch(`${requiredEnvironment("SUPABASE_URL")}/rest/v1/${path}`, {
    ...init,
    headers: {
      apikey: key, authorization: `Bearer ${key}`, "content-type": "application/json",
      prefer: "return=representation", ...init.headers,
    },
  })
  const text = await response.text()
  if (!response.ok) throw new Error(`Supabase ${path}: ${response.status} ${text}`)
  return (text ? JSON.parse(text) : undefined) as T
}

async function encrypt(value: string) {
  const iv = randomBytes(12)
  const encrypted = await crypto.subtle.encrypt({ name: "AES-GCM", iv }, await encryptionKey(), new TextEncoder().encode(value))
  return { ciphertext: base64URL(new Uint8Array(encrypted)), iv: base64URL(iv) }
}

async function decrypt(ciphertext: string, iv: string) {
  const plaintext = await crypto.subtle.decrypt(
    { name: "AES-GCM", iv: base64URLBytes(iv) }, await encryptionKey(), base64URLBytes(ciphertext),
  )
  return new TextDecoder().decode(plaintext)
}

let cachedEncryptionKey: CryptoKey | undefined
async function encryptionKey() {
  if (cachedEncryptionKey) return cachedEncryptionKey
  const material = base64URLBytes(requiredEnvironment("GOOGLE_FORMS_TOKEN_ENCRYPTION_KEY"))
  if (material.byteLength !== 32) throw new GoogleFormsError("GOOGLE_FORMS_TOKEN_ENCRYPTION_KEY must be a base64url 32-byte key", 503)
  cachedEncryptionKey = await crypto.subtle.importKey("raw", material, "AES-GCM", false, ["encrypt", "decrypt"])
  return cachedEncryptionKey
}

function requiredEnvironment(name: string) {
  const value = Deno.env.get(name)?.trim()
  if (!value) throw new GoogleFormsError(`${name} is not configured`, 503)
  return value
}

function googleOAuthRedirect() {
  const uri = requiredEnvironment("GOOGLE_FORMS_OAUTH_REDIRECT_URI")
  let parsed: URL
  try {
    parsed = new URL(uri)
  } catch {
    throw new GoogleFormsError("GOOGLE_FORMS_OAUTH_REDIRECT_URI must be a valid iOS custom URI, such as firefly.fireflyfm:/oauth2redirect", 422)
  }
  const callbackScheme = parsed.protocol.replace(":", "")
  const validCustomScheme = /^[a-z][a-z0-9+.-]*$/i.test(callbackScheme) && callbackScheme.includes(".")
  if (!validCustomScheme || parsed.host || parsed.pathname !== "/oauth2redirect" || parsed.search || parsed.hash) {
    throw new GoogleFormsError("GOOGLE_FORMS_OAUTH_REDIRECT_URI must use a reverse-domain iOS custom scheme and be exactly like firefly.fireflyfm:/oauth2redirect", 422)
  }
  return { uri, callbackScheme }
}

function requiredUUID(value: unknown, label: string) {
  if (typeof value !== "string" || !/^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(value)) {
    throw new GoogleFormsError(`${label} must be a UUID`)
  }
  return value
}

function requireText(value: unknown, label: string) {
  if (typeof value !== "string" || value.trim().length === 0 || value.length > 4096) throw new GoogleFormsError(`A valid ${label} is required`)
  return value.trim()
}

function randomBytes(size: number) { const value = new Uint8Array(size); crypto.getRandomValues(value); return value }
function base64URL(value: Uint8Array) { let text = ""; for (const byte of value) text += String.fromCharCode(byte); return btoa(text).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/g, "") }
function base64URLBytes(value: string) { const padded = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "="); return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0)) }
async function sha256Hex(value: string) { const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)); return Array.from(new Uint8Array(hash)).map((byte) => byte.toString(16).padStart(2, "0")).join("") }
async function sha256Base64URL(value: string) { const hash = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value)); return base64URL(new Uint8Array(hash)) }
function isRecord(value: unknown): value is Record<string, unknown> { return typeof value === "object" && value !== null }
