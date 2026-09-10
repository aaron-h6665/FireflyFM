export type GoogleTokenRevocationResult = "revoked" | "already_disconnected"

export class GoogleTokenRevocationError extends Error {}

type Fetcher = (input: string | URL | Request, init?: RequestInit) => Promise<Response>

export async function revokeGoogleRefreshToken(
  refreshToken: string,
  fetcher: Fetcher = fetch,
): Promise<GoogleTokenRevocationResult> {
  let response: Response
  try {
    response = await fetcher("https://oauth2.googleapis.com/revoke", {
      method: "POST",
      headers: { "content-type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams({ token: refreshToken }),
    })
  } catch {
    throw new GoogleTokenRevocationError("Google token revocation could not be reached")
  }

  if (response.ok) return "revoked"

  const payload = await response.json().catch(() => ({})) as { error?: string }
  if (response.status === 400 && payload.error === "invalid_token") {
    return "already_disconnected"
  }
  throw new GoogleTokenRevocationError("Google rejected token revocation")
}
