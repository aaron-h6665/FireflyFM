type RequestBody = { schoolId?: string }
type Connection = {
  id: string
  school_id: string
  form_id: string
  status: string
  last_synced_at: string | null
}
type FormResponse = {
  responseId: string
  createTime?: string
  lastSubmittedTime?: string
  respondentEmail?: string
  answers?: Record<string, {
    textAnswers?: { answers?: { value?: string }[] }
    fileUploadAnswers?: { answers?: { fileId?: string; fileName?: string; mimeType?: string }[] }
  }>
}

const json = (body: unknown, status = 200) => new Response(JSON.stringify(body), {
  status,
  headers: { "content-type": "application/json" },
})

const errorResponse = (message: string, status = 400) => json({ error: message }, status)

function env(name: string): string {
  const value = Deno.env.get(name)?.trim()
  if (!value) throw new Error(`${name} is not configured`)
  return value
}

async function admin<T>(path: string, init: RequestInit = {}): Promise<T> {
  const base = env("SUPABASE_URL")
  const key = env("SUPABASE_SERVICE_ROLE_KEY")
  const response = await fetch(`${base}/rest/v1/${path}`, {
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
  if (!response.ok) throw new Error(`Supabase request failed (${response.status})`)
  return (text ? JSON.parse(text) : undefined) as T
}

async function authenticate(request: Request): Promise<string> {
  const authorization = request.headers.get("authorization")
  if (!authorization?.match(/^Bearer\s+\S+/i)) throw new Error("Unauthorized")
  const response = await fetch(`${env("SUPABASE_URL")}/auth/v1/user`, {
    headers: { apikey: env("SUPABASE_SERVICE_ROLE_KEY"), authorization },
  })
  if (!response.ok) throw new Error("Unauthorized")
  const user = await response.json() as { id?: string }
  if (!user.id) throw new Error("Unauthorized")
  return user.id
}

async function requireDirector(schoolId: string, userId: string) {
  const rows = await admin<{ id: string }[]>(
    `school_memberships?select=id&school_id=eq.${encodeURIComponent(schoolId)}`
      + `&user_id=eq.${encodeURIComponent(userId)}&role=eq.school_director&active=eq.true&limit=1`,
  )
  if (!rows?.length) throw new Error("A school director is required")
}

function responsePayload(response: FormResponse) {
  const values: Record<string, unknown> = {}
  for (const [questionId, answer] of Object.entries(response.answers ?? {})) {
    const texts = answer.textAnswers?.answers?.map((item) => item.value ?? "") ?? []
    const files = answer.fileUploadAnswers?.answers?.map((item) => ({
      fileId: item.fileId ?? "", fileName: item.fileName ?? "", mimeType: item.mimeType ?? null,
    })) ?? []
    values[questionId] = files.length ? { files } : texts.length === 1 ? texts[0] : texts
  }
  return values
}

Deno.serve(async (request) => {
  try {
    if (request.method !== "POST") return errorResponse("Method not allowed", 405)
    const userId = await authenticate(request)
    const body = await request.json() as RequestBody
    const schoolId = body.schoolId?.trim()
    if (!schoolId || !/^[0-9a-f-]{36}$/i.test(schoolId)) return errorResponse("A valid schoolId is required")
    await requireDirector(schoolId, userId)

    const connections = await admin<Connection[]>(
      `google_form_connections?select=id,school_id,form_id,status,last_synced_at`
        + `&school_id=eq.${encodeURIComponent(schoolId)}&form_role=eq.parent&status=neq.disconnected&limit=1`,
    )
    const connection = connections?.[0]
    if (!connection) return errorResponse("No parent Google Form is connected", 409)

    const token = Deno.env.get("GOOGLE_FORMS_ACCESS_TOKEN")?.trim()
    if (!token) return errorResponse("Google Forms OAuth is not configured for this deployment", 503)
    const after = connection.last_synced_at ? `?filter=timestamp%20%3E%20${encodeURIComponent(connection.last_synced_at)}` : ""
    const googleResponse = await fetch(`https://forms.googleapis.com/v1/forms/${encodeURIComponent(connection.form_id)}/responses${after}`, {
      headers: { authorization: `Bearer ${token}` },
    })
    if (!googleResponse.ok) return errorResponse("Google Forms could not be read; reconnect the director account", 502)
    const payload = await googleResponse.json() as { responses?: FormResponse[] }
    let imported = 0
    for (const response of payload.responses ?? []) {
      const rows = await admin<{ id: string }[]>("google_form_imports?on_conflict=connection_id,google_response_id", {
        method: "POST",
        headers: { prefer: "resolution=ignore-duplicates,return=representation" },
        body: JSON.stringify({
          connection_id: connection.id,
          school_id: schoolId,
          google_response_id: response.responseId,
          response_created_at: response.createTime ?? null,
          response_submitted_at: response.lastSubmittedTime ?? null,
          respondent_email: response.respondentEmail ?? null,
          submitted_payload: responsePayload(response),
          status: "pending_review",
        }),
      })
      if (rows?.length) imported += 1
    }
    await admin(`google_form_connections?id=eq.${encodeURIComponent(connection.id)}`, {
      method: "PATCH",
      body: JSON.stringify({ last_synced_at: new Date().toISOString(), status: "connected", last_error: null, updated_at: new Date().toISOString() }),
    })
    return json({ imported, received: payload.responses?.length ?? 0 })
  } catch (error) {
    const message = error instanceof Error ? error.message : "Google Form sync failed"
    const status = message === "Unauthorized" ? 401 : message.includes("director") ? 403 : 500
    return errorResponse(message, status)
  }
})
