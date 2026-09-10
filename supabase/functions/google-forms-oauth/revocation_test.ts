import assert from "node:assert/strict"
import test from "node:test"
import {
  GoogleTokenRevocationError,
  revokeGoogleRefreshToken,
} from "./revocation.ts"

test("successful Google revocation is accepted", async () => {
  const result = await revokeGoogleRefreshToken("refresh-token", async () => new Response(null, { status: 200 }))
  assert.equal(result, "revoked")
})

test("Google invalid_token is treated as already disconnected", async () => {
  const result = await revokeGoogleRefreshToken(
    "expired-token",
    async () => Response.json({ error: "invalid_token" }, { status: 400 }),
  )
  assert.equal(result, "already_disconnected")
})

test("other Google revocation failures remain retryable", async () => {
  await assert.rejects(
    revokeGoogleRefreshToken(
      "refresh-token",
      async () => Response.json({ error: "temporarily_unavailable" }, { status: 503 }),
    ),
    GoogleTokenRevocationError,
  )
})

test("network failures remain retryable", async () => {
  await assert.rejects(
    revokeGoogleRefreshToken("refresh-token", async () => { throw new Error("offline") }),
    GoogleTokenRevocationError,
  )
})
