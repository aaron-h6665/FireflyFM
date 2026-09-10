// Synchronizes director-authorized Google Forms.  This function may be called
// by a director for an immediate sync or by the protected scheduled worker.
// It never accepts a Google access token from the client.

type SyncRequest = { schoolId?: string; formRole?: "parent" | "teacher"; connectionId?: string }
type Connection = {
  id: string; school_id: string; form_id: string; credential_id: string | null
  status: string; last_synced_at: string | null; response_min_created_at: string | null
}
type Credential = {
  id: string; refresh_token_ciphertext: string | null; refresh_token_iv: string | null; status: string
}
type FormResponse = {
  responseId: string; createTime?: string; lastSubmittedTime?: string; respondentEmail?: string
  answers?: Record<string, {
    textAnswers?: { answers?: { value?: string }[] }
    fileUploadAnswers?: { answers?: { fileId?: string; fileName?: string; mimeType?: string }[] }
  }>
}

const json = (payload: unknown, status = 200) => new Response(JSON.stringify(payload), {
  status, headers: { "content-type": "application/json", "cache-control": "no-store" },
})

Deno.serve(async (request) => {
  try {
    if (request.method !== "POST") return json({ error: "Method not allowed" }, 405)
    const body = await request.json().catch(() => ({})) as SyncRequest
    const worker = isWorker(request)
    if (!worker) {
      const userId = await authenticate(request)
      if (!body.schoolId || !isUUID(body.schoolId)) return json({ error: "A valid schoolId is required" }, 400)
      if (body.connectionId) {
        await requireConnectionSyncAccess(body.schoolId, body.connectionId, userId)
      } else {
        await requireDirector(body.schoolId, userId)
      }
    }
    const connections = await selectConnections(body, worker)
    const outcomes = [] as { connectionId: string; imported: number; received: number; error?: string }[]
    for (const connection of connections) {
      try {
        const outcome = await syncConnection(connection)
        outcomes.push({ connectionId: connection.id, ...outcome })
      } catch (error) {
        const message = error instanceof Error ? error.message : "Google Form sync failed"
        await updateConnection(connection.id, { status: "error", last_error: message, updated_at: new Date().toISOString() }).catch(() => undefined)
        outcomes.push({ connectionId: connection.id, imported: 0, received: 0, error: message })
      }
    }
    return json({ synced: outcomes.filter((item) => !item.error).length, outcomes })
  } catch (error) {
    const message = error instanceof Error ? error.message : "Google Form sync failed"
    const status = message === "Unauthorized" ? 401 : message.includes("director") ? 403 : 500
    return json({ error: message }, status)
  }
})

async function selectConnections(body: SyncRequest, worker: boolean) {
  const filters = ["select=id,school_id,form_id,credential_id,status,last_synced_at,response_min_created_at", "status=in.(connected,error)"]
  if (body.schoolId) {
    if (!isUUID(body.schoolId)) throw new Error("A valid schoolId is required")
    filters.push(`school_id=eq.${encodeURIComponent(body.schoolId)}`)
  } else if (!worker) {
    throw new Error("A valid schoolId is required")
  }
  if (body.connectionId) {
    if (!isUUID(body.connectionId)) throw new Error("A valid connectionId is required")
    filters.push(`id=eq.${encodeURIComponent(body.connectionId)}`)
  } else if (body.formRole) {
    filters.push(`form_role=eq.${encodeURIComponent(body.formRole)}`)
  }
  return await admin<Connection[]>(`google_form_connections?${filters.join("&")}`)
}

async function syncConnection(connection: Connection) {
  if (!connection.credential_id) throw new Error("Reconnect Google before syncing this Form")
  await updateConnection(connection.id, { status: "syncing", last_error: null, updated_at: new Date().toISOString() })
  const credentialRows = await admin<Credential[]>(
    `google_oauth_credentials?select=id,refresh_token_ciphertext,refresh_token_iv,status&id=eq.${encodeURIComponent(connection.credential_id)}&limit=1`,
  )
  const credential = credentialRows[0]
  if (!credential || credential.status !== "connected") throw new Error("Reconnect Google before syncing this Form")
  if (!credential.refresh_token_ciphertext || !credential.refresh_token_iv) {
    throw new Error("Reconnect Google before syncing this Form")
  }
  let accessToken: string
  try {
    accessToken = await refreshAccessToken(await decrypt(credential.refresh_token_ciphertext, credential.refresh_token_iv))
  } catch (error) {
    await admin(`google_oauth_credentials?id=eq.${encodeURIComponent(credential.id)}`, {
      method: "PATCH",
      body: JSON.stringify({ status: "needs_reconnect", last_error: "Google authorization needs to be reconnected.", updated_at: new Date().toISOString() }),
    }).catch(() => undefined)
    throw error
  }
  const responses = await listResponses(connection, accessToken)
  let imported = 0
  for (const response of responses) {
    const rows = await admin<{ id: string }[]>("google_form_imports?on_conflict=connection_id,google_response_id", {
      method: "POST",
      headers: { prefer: "resolution=ignore-duplicates,return=representation" },
      body: JSON.stringify({
        connection_id: connection.id,
        school_id: connection.school_id,
        google_response_id: response.responseId,
        response_created_at: response.createTime ?? null,
        response_submitted_at: response.lastSubmittedTime ?? null,
        respondent_email: response.respondentEmail ?? null,
        submitted_payload: responsePayload(response),
        status: "pending_review",
      }),
    })
    let formImport = rows[0]
    if (formImport) {
      imported += 1
    } else {
      const existing = await admin<{ id: string }[]>(
        `google_form_imports?select=id&connection_id=eq.${encodeURIComponent(connection.id)}`
          + `&google_response_id=eq.${encodeURIComponent(response.responseId)}&limit=1`,
      )
      formImport = existing[0]
    }
    if (!formImport) throw new Error("A Google Form response could not be recovered for processing")
    await quarantineAttachments(connection, formImport.id, response, accessToken)
    await rpc("ingest_google_form_import", { input_import_id: formImport.id })
  }
  // Version 17 and earlier skipped duplicate rows entirely. Recover any raw
  // responses that were saved before ingestion finished so they cannot remain
  // permanently absent from both the recipient timeline and director inbox.
  const stranded = await admin<{ id: string }[]>(
    `google_form_imports?select=id&connection_id=eq.${encodeURIComponent(connection.id)}`
      + "&submission_session_id=is.null&status=eq.pending_review&order=created_at.asc&limit=200",
  )
  for (const formImport of stranded) {
    await rpc("ingest_google_form_import", { input_import_id: formImport.id })
  }
  const now = new Date().toISOString()
  await updateConnection(connection.id, {
    status: "connected", last_synced_at: now,
    next_sync_after: new Date(Date.now() + 5 * 60 * 1000).toISOString(), last_error: null, updated_at: now,
  })
  await admin(`google_oauth_credentials?id=eq.${encodeURIComponent(credential.id)}`, {
    method: "PATCH", body: JSON.stringify({ last_used_at: now, last_error: null, updated_at: now }),
  })
  return { imported, received: responses.length }
}

async function listResponses(connection: Connection, accessToken: string) {
  const responses: FormResponse[] = []
  let pageToken: string | undefined
  // A timeline copy starts at its own boundary, so historic answers in the
  // same Google Form cannot be attached to a future parent cohort. Established
  // connections retain a short overlap for delayed Google responses.
  const timelineStart = connection.response_min_created_at ? new Date(connection.response_min_created_at) : undefined
  const overlapStart = connection.last_synced_at
    ? new Date(new Date(connection.last_synced_at).getTime() - 5 * 60 * 1000)
    : undefined
  const openSessions = await admin<{ created_at: string }[]>(
    `google_form_submission_sessions?select=created_at&connection_id=eq.${encodeURIComponent(connection.id)}`
      + `&consumed_at=is.null&expires_at=gt.${encodeURIComponent(new Date().toISOString())}`
      + "&order=created_at.asc&limit=1",
  )
  const sessionStart = openSessions[0] ? new Date(openSessions[0].created_at) : undefined
  const recoveryStart = overlapStart && sessionStart
    ? new Date(Math.min(overlapStart.getTime(), sessionStart.getTime()))
    : overlapStart ?? sessionStart
  const since = timelineStart && recoveryStart
    ? new Date(Math.max(timelineStart.getTime(), recoveryStart.getTime()))
    : timelineStart ?? recoveryStart
  for (let page = 0; page < 20; page++) {
    const parameters = new URLSearchParams({ pageSize: "200" })
    if (pageToken) parameters.set("pageToken", pageToken)
    if (since && !Number.isNaN(since.getTime())) parameters.set("filter", `timestamp > ${since.toISOString()}`)
    const payload = await googleJSON<{ responses?: FormResponse[]; nextPageToken?: string }>(
      `https://forms.googleapis.com/v1/forms/${encodeURIComponent(connection.form_id)}/responses?${parameters}`,
      accessToken,
    )
    responses.push(...(payload.responses ?? []))
    pageToken = payload.nextPageToken
    if (!pageToken) break
  }
  return responses
}

async function quarantineAttachments(connection: Connection, importId: string, response: FormResponse, accessToken: string) {
  for (const [questionId, answer] of Object.entries(response.answers ?? {})) {
    for (const file of answer.fileUploadAnswers?.answers ?? []) {
      if (!file.fileId) continue
      const metadata = await googleJSON<{ name?: string; mimeType?: string; size?: string }>(
        `https://www.googleapis.com/drive/v3/files/${encodeURIComponent(file.fileId)}?fields=id,name,mimeType,size`, accessToken,
      )
      const size = Number(metadata.size ?? 0)
      if (!Number.isFinite(size) || size > 10 * 1024 * 1024) {
        await admin("google_form_import_attachments", {
          method: "POST", headers: { prefer: "resolution=ignore-duplicates" },
          body: JSON.stringify({ import_id: importId, question_id: questionId, google_file_id: file.fileId,
            file_name: metadata.name ?? file.fileName ?? "Uploaded file", content_type: metadata.mimeType ?? file.mimeType ?? null,
            document_type: "other" }),
        })
        continue
      }
      const content = await fetch(`https://www.googleapis.com/drive/v3/files/${encodeURIComponent(file.fileId)}?alt=media`, {
        headers: { authorization: `Bearer ${accessToken}` },
      })
      if (!content.ok) throw new Error("An uploaded Form document could not be downloaded")
      const bytes = new Uint8Array(await content.arrayBuffer())
      if (bytes.byteLength > 10 * 1024 * 1024) throw new Error("An uploaded Form document exceeds the 10 MB limit")
      const fileName = safeFileName(metadata.name ?? file.fileName ?? "upload")
      const path = `schools/${connection.school_id}/google_form_imports/${importId}/${file.fileId}/${fileName}`
      await uploadPrivateFile(path, bytes, metadata.mimeType ?? file.mimeType ?? "application/octet-stream")
      await admin("google_form_import_attachments?on_conflict=import_id,google_file_id", {
        method: "POST", headers: { prefer: "resolution=merge-duplicates" },
        body: JSON.stringify({ import_id: importId, question_id: questionId, google_file_id: file.fileId,
          file_name: metadata.name ?? file.fileName ?? "Uploaded file", content_type: metadata.mimeType ?? file.mimeType ?? null,
          private_file_path: path, document_type: "other" }),
      })
    }
  }
}

function responsePayload(response: FormResponse) {
  const values: Record<string, unknown> = {}
  for (const [questionId, answer] of Object.entries(response.answers ?? {})) {
    const texts = answer.textAnswers?.answers?.map((item) => item.value ?? "") ?? []
    const files = answer.fileUploadAnswers?.answers?.map((item) => ({ fileId: item.fileId ?? "", fileName: item.fileName ?? "", mimeType: item.mimeType ?? null })) ?? []
    values[questionId] = files.length ? { files } : texts.length === 1 ? texts[0] : texts
  }
  return values
}

async function refreshAccessToken(refreshToken: string) {
  const fields = new URLSearchParams({ grant_type: "refresh_token", refresh_token: refreshToken, client_id: environment("GOOGLE_FORMS_OAUTH_CLIENT_ID") })
  const clientSecret = Deno.env.get("GOOGLE_FORMS_OAUTH_CLIENT_SECRET")?.trim()
  if (clientSecret) fields.set("client_secret", clientSecret)
  const response = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: fields,
  })
  const payload = await response.json().catch(() => ({})) as { access_token?: string; error_description?: string }
  if (!response.ok || !payload.access_token) {
    throw new Error(payload.error_description ?? "Google authorization needs to be reconnected")
  }
  return payload.access_token
}

async function googleJSON<T>(url: string, accessToken: string): Promise<T> {
  const response = await fetch(url, { headers: { authorization: `Bearer ${accessToken}` } })
  const body = await response.json().catch(() => ({})) as T & { error?: { message?: string } }
  if (!response.ok) throw new Error(body.error?.message ?? "Google Forms could not be read")
  return body
}

async function uploadPrivateFile(path: string, bytes: Uint8Array, contentType: string) {
  const response = await fetch(`${environment("SUPABASE_URL")}/storage/v1/object/school_private_files/${path.split("/").map(encodeURIComponent).join("/")}`, {
    method: "POST",
    headers: { apikey: environment("SUPABASE_SERVICE_ROLE_KEY"), authorization: `Bearer ${environment("SUPABASE_SERVICE_ROLE_KEY")}`,
      "content-type": contentType, "x-upsert": "false" },
    body: bytes,
  })
  if (!response.ok && response.status !== 409) throw new Error("The uploaded Form document could not be quarantined")
}

async function updateConnection(connectionId: string, values: Record<string, unknown>) {
  await admin(`google_form_connections?id=eq.${encodeURIComponent(connectionId)}`, { method: "PATCH", body: JSON.stringify(values) })
}

async function rpc(name: string, body: unknown) {
  await admin(`rpc/${name}`, { method: "POST", body: JSON.stringify(body) })
}

async function authenticate(request: Request) {
  const authorization = request.headers.get("authorization")
  if (!authorization?.match(/^Bearer\s+\S+/i)) throw new Error("Unauthorized")
  const response = await fetch(`${environment("SUPABASE_URL")}/auth/v1/user`, {
    headers: { apikey: environment("SUPABASE_SERVICE_ROLE_KEY"), authorization },
  })
  const user = await response.json().catch(() => ({})) as { id?: string }
  if (!response.ok || !user.id) throw new Error("Unauthorized")
  return user.id
}

async function requireDirector(schoolId: string, userId: string) {
  const rows = await admin<{ id: string }[]>(
    `school_memberships?select=id&school_id=eq.${encodeURIComponent(schoolId)}`
      + `&user_id=eq.${encodeURIComponent(userId)}&role=eq.school_director&active=eq.true&limit=1`,
  )
  if (!rows.length) throw new Error("A school director is required")
}

async function requireConnectionSyncAccess(schoolId: string, connectionId: string, userId: string) {
  if (!isUUID(connectionId)) throw new Error("A valid connectionId is required")
  const director = await admin<{ id: string }[]>(
    `school_memberships?select=id&school_id=eq.${encodeURIComponent(schoolId)}`
      + `&user_id=eq.${encodeURIComponent(userId)}&role=eq.school_director&active=eq.true&limit=1`,
  )
  if (director.length) return

  const connections = await admin<{ id: string; form_role: string }[]>(
    `google_form_connections?select=id,form_role&id=eq.${encodeURIComponent(connectionId)}`
      + `&school_id=eq.${encodeURIComponent(schoolId)}&limit=1`,
  )
  const connection = connections[0]
  if (!connection) throw new Error("This Form is not assigned to your account")
  const memberships = await admin<{ id: string }[]>(
    `school_memberships?select=id&school_id=eq.${encodeURIComponent(schoolId)}`
      + `&user_id=eq.${encodeURIComponent(userId)}&role=eq.${encodeURIComponent(connection.form_role)}`
      + "&active=eq.true&limit=1",
  )
  const membership = memberships[0]
  if (!membership) throw new Error("This Form is not assigned to your account")
  const sessions = await admin<{ id: string }[]>(
    `google_form_submission_sessions?select=id&connection_id=eq.${encodeURIComponent(connectionId)}`
      + `&membership_id=eq.${encodeURIComponent(membership.id)}&consumed_at=is.null`
      + `&expires_at=gt.${encodeURIComponent(new Date().toISOString())}&limit=1`,
  )
  if (!sessions.length) throw new Error("Open this Form from your onboarding checklist before syncing it")
}

function isWorker(request: Request) {
  const secret = Deno.env.get("GOOGLE_FORMS_WORKER_SECRET")
  return !!secret && request.headers.get("x-google-forms-worker-secret") === secret
}

async function admin<T = unknown>(path: string, init: RequestInit = {}): Promise<T> {
  const key = environment("SUPABASE_SERVICE_ROLE_KEY")
  const response = await fetch(`${environment("SUPABASE_URL")}/rest/v1/${path}`, {
    ...init,
    headers: { apikey: key, authorization: `Bearer ${key}`, "content-type": "application/json", prefer: "return=representation", ...init.headers },
  })
  const text = await response.text()
  if (!response.ok) throw new Error(`Supabase ${path}: ${response.status} ${text}`)
  return (text ? JSON.parse(text) : undefined) as T
}

async function decrypt(ciphertext: string, iv: string) {
  const plaintext = await crypto.subtle.decrypt({ name: "AES-GCM", iv: base64URLBytes(iv) }, await encryptionKey(), base64URLBytes(ciphertext))
  return new TextDecoder().decode(plaintext)
}

let cachedKey: CryptoKey | undefined
async function encryptionKey() {
  if (cachedKey) return cachedKey
  const value = base64URLBytes(environment("GOOGLE_FORMS_TOKEN_ENCRYPTION_KEY"))
  if (value.byteLength !== 32) throw new Error("GOOGLE_FORMS_TOKEN_ENCRYPTION_KEY must be a base64url 32-byte key")
  cachedKey = await crypto.subtle.importKey("raw", value, "AES-GCM", false, ["decrypt"])
  return cachedKey
}

function environment(name: string) { const value = Deno.env.get(name)?.trim(); if (!value) throw new Error(`${name} is not configured`); return value }
function isUUID(value: string) {
  return /^[0-9a-f]{8}-(?:[0-9a-f]{4}-){3}[0-9a-f]{12}$/i.test(value)
}
function safeFileName(value: string) { return value.replace(/[^A-Za-z0-9._-]+/g, "_").replace(/^_+|_+$/g, "").slice(0, 160) || "upload" }
function base64URLBytes(value: string) { const padded = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "="); return Uint8Array.from(atob(padded), (character) => character.charCodeAt(0)) }
