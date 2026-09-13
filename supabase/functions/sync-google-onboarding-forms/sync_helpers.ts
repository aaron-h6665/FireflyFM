export class GoogleAuthorizationError extends Error {}

export async function exchangeRefreshToken(fields: URLSearchParams, fetcher: typeof fetch = fetch) {
  const response = await fetcher("https://oauth2.googleapis.com/token", {
    method: "POST", headers: { "content-type": "application/x-www-form-urlencoded" }, body: fields,
  })
  const payload = await response.json().catch(() => ({})) as { access_token?: string; error?: string }
  if (!response.ok || !payload.access_token) {
    if (response.status === 400 && payload.error === "invalid_grant") {
      throw new GoogleAuthorizationError("Google authorization needs to be reconnected")
    }
    throw new Error("Google authorization is temporarily unavailable. Try syncing again later.")
  }
  return payload.access_token
}

// Never return a partial page walk as success: the caller advances its sync
// watermark only after every response has been fetched and processed.
export async function fetchResponsePages<T>(
  fetchPage: (token?: string) => Promise<{ responses?: T[]; nextPageToken?: string }>,
): Promise<T[]> {
  const responses: T[] = []
  const seen = new Set<string>()
  let token: string | undefined
  do {
    const page = await fetchPage(token)
    responses.push(...(page.responses ?? []))
    token = page.nextPageToken
    if (token) {
      if (seen.has(token)) throw new Error("Google Forms returned a repeated response page. Try syncing again.")
      seen.add(token)
    }
  } while (token)
  return responses
}

// A sync may be retried after the object was stored but before its attachment
// row or import was committed. Use the deterministic object path as an
// idempotency key so an existing quarantine object cannot strand the import.
export async function uploadQuarantinedFile(
  supabaseURL: string,
  serviceRoleKey: string,
  path: string,
  bytes: Uint8Array,
  contentType: string,
  fetcher: typeof fetch = fetch,
) {
  const encodedPath = path.split("/").map(encodeURIComponent).join("/")
  const response = await fetcher(`${supabaseURL}/storage/v1/object/school_private_files/${encodedPath}`, {
    method: "POST",
    headers: {
      apikey: serviceRoleKey,
      authorization: `Bearer ${serviceRoleKey}`,
      "content-type": contentType,
      "x-upsert": "true",
    },
    body: bytes,
  })
  if (!response.ok) throw new Error("The uploaded Form document could not be quarantined")
}
