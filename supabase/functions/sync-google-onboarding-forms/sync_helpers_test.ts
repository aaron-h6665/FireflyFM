import assert from "node:assert/strict"
import test from "node:test"
import { exchangeRefreshToken, fetchResponsePages, GoogleAuthorizationError } from "./sync_helpers.ts"

test("response pagination includes pages beyond the former 20-page limit", async () => {
  const rows = await fetchResponsePages<number>(async (token) => {
    const page = Number(token ?? 0)
    return { responses: [page], nextPageToken: page < 24 ? String(page + 1) : undefined }
  })
  assert.deepEqual(rows, Array.from({ length: 25 }, (_, i) => i))
})

test("later page failure cannot return partial success", async () => {
  await assert.rejects(fetchResponsePages(async (token) => {
    if (token) throw new Error("offline")
    return { responses: [1], nextPageToken: "next" }
  }), /offline/)
})

test("repeated page tokens fail instead of looping forever", async () => {
  await assert.rejects(fetchResponsePages(async () => ({ nextPageToken: "same" })), /repeated/)
})

test("revoked refresh grant requires reconnection", async () => {
  await assert.rejects(exchangeRefreshToken(new URLSearchParams(), async () =>
    Response.json({ error: "invalid_grant" }, { status: 400 })), GoogleAuthorizationError)
})

test("temporary failures preserve the connected credential", async () => {
  for (const status of [429, 500, 503]) {
    await assert.rejects(exchangeRefreshToken(new URLSearchParams(), async () =>
      Response.json({ error: "temporarily_unavailable" }, { status })),
    (error: Error) => !(error instanceof GoogleAuthorizationError))
  }
  await assert.rejects(exchangeRefreshToken(new URLSearchParams(), async () => { throw new Error("offline") }),
    (error: Error) => !(error instanceof GoogleAuthorizationError))
})

test("valid refresh returns access token", async () => {
  assert.equal(await exchangeRefreshToken(new URLSearchParams(), async () =>
    Response.json({ access_token: "test-token" })), "test-token")
})
