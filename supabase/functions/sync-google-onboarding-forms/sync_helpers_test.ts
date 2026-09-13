import assert from "node:assert/strict"
import test from "node:test"
import { exchangeRefreshToken, fetchResponsePages, GoogleAuthorizationError, uploadQuarantinedFile } from "./sync_helpers.ts"

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

test("quarantine upload is idempotent so a partial sync can retry", async () => {
  let request: Request | undefined
  const bytes = new Uint8Array([1, 2, 3])
  await uploadQuarantinedFile(
    "https://test.invalid",
    "service-key",
    "schools/school id/google_form_imports/import/file/report name.pdf",
    bytes,
    "application/pdf",
    async (input, init) => {
      request = new Request(input, init)
      return Response.json({ Key: "stored" })
    },
  )

  assert.equal(
    request!.url,
    "https://test.invalid/storage/v1/object/school_private_files/schools/school%20id/google_form_imports/import/file/report%20name.pdf",
  )
  assert.equal(request!.method, "POST")
  assert.equal(request!.headers.get("x-upsert"), "true")
  assert.equal(request!.headers.get("content-type"), "application/pdf")
  assert.deepEqual(new Uint8Array(await request!.arrayBuffer()), bytes)
})

test("quarantine upload still reports a failed storage write", async () => {
  await assert.rejects(
    uploadQuarantinedFile("https://test.invalid", "service-key", "path", new Uint8Array(), "text/plain", async () =>
      Response.json({ message: "offline" }, { status: 503 })),
    /could not be quarantined/,
  )
})
