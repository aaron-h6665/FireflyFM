import { assertEquals, assertStringIncludes } from "jsr:@std/assert"
import { handleRequest } from "./index.ts"

const originalFetch = globalThis.fetch

function jsonResponse(value: unknown, status = 200) {
  return new Response(JSON.stringify(value), {
    status,
    headers: { "content-type": "application/json" },
  })
}

function request(body: unknown, authenticated = true) {
  return new Request("http://localhost/functions/v1/google-drive-assignment-picker", {
    method: "POST",
    headers: authenticated ? { authorization: "Bearer user-jwt" } : {},
    body: JSON.stringify(body),
  })
}

function operation(overrides: Record<string, unknown> = {}) {
  return {
    id: "40000000-0000-0000-0000-000000000001",
    user_id: "10000000-0000-0000-0000-000000000001",
    school_id: "20000000-0000-0000-0000-000000000001",
    assignment_id: "60000000-0000-0000-0000-000000000001",
    context_kind: "submission",
    allows_multiple: true,
    state_hash: "hash",
    pkce_verifier_ciphertext: "ciphertext",
    pkce_verifier_iv: "iv",
    access_token_ciphertext: null,
    access_token_iv: null,
    selected_files: [],
    oauth_completed_at: null,
    expires_at: new Date(Date.now() + 60_000).toISOString(),
    consumed_at: null,
    ...overrides,
  }
}

function installEnvironment() {
  Deno.env.set("SUPABASE_URL", "https://project.supabase.co")
  Deno.env.set("SUPABASE_SERVICE_ROLE_KEY", "service-role-key")
}

Deno.test("rejects unauthenticated and invalid user sessions", async () => {
  installEnvironment()
  const missing = await handleRequest(request({ action: "finish" }, false))
  assertEquals(missing.status, 401)

  globalThis.fetch = () => Promise.resolve(jsonResponse({ message: "invalid" }, 401))
  try {
    const invalid = await handleRequest(request({ action: "finish" }))
    assertEquals(invalid.status, 401)
  } finally {
    globalThis.fetch = originalFetch
  }
})

Deno.test("rejects cross-user state lookup, expired operations, and completed replay", async () => {
  installEnvironment()
  for (const row of [
    undefined,
    operation({ expires_at: new Date(Date.now() - 1_000).toISOString() }),
    operation({ oauth_completed_at: new Date().toISOString() }),
  ]) {
    let call = 0
    globalThis.fetch = () => {
      call += 1
      if (call === 1) return Promise.resolve(jsonResponse({ id: "10000000-0000-0000-0000-000000000001" }))
      return Promise.resolve(jsonResponse(row ? [row] : []))
    }
    try {
      const response = await handleRequest(request({
        action: "complete",
        state: "picker-state",
        code: "authorization-code",
        pickedFileIds: ["selected-file"],
      }))
      assertEquals(response.status, row?.oauth_completed_at ? 409 : 422)
    } finally {
      globalThis.fetch = originalFetch
    }
  }
})

Deno.test("rejects forged picker file ids before operation completion", async () => {
  installEnvironment()
  globalThis.fetch = () => Promise.resolve(jsonResponse({ id: "10000000-0000-0000-0000-000000000001" }))
  try {
    const response = await handleRequest(request({
      action: "complete",
      state: "picker-state",
      code: "authorization-code",
      pickedFileIds: ["not a Drive id"],
    }))
    assertEquals(response.status, 422)
  } finally {
    globalThis.fetch = originalFetch
  }
})

Deno.test("finish clears token material and selected manifest for the owning user", async () => {
  installEnvironment()
  let patchBody = ""
  let call = 0
  globalThis.fetch = (_input, init) => {
    call += 1
    if (call === 1) return Promise.resolve(jsonResponse({ id: "10000000-0000-0000-0000-000000000001" }))
    patchBody = String(init?.body ?? "")
    return Promise.resolve(jsonResponse([operation()]))
  }
  try {
    const response = await handleRequest(request({
      action: "finish",
      operationId: "40000000-0000-0000-0000-000000000001",
    }))
    assertEquals(response.status, 200)
    assertStringIncludes(patchBody, '"pkce_verifier_ciphertext":null')
    assertStringIncludes(patchBody, '"access_token_ciphertext":null')
    assertStringIncludes(patchBody, '"selected_files":[]')
  } finally {
    globalThis.fetch = originalFetch
  }
})

Deno.test("download rechecks assignment access before decrypting tokens or fetching bytes", async () => {
  installEnvironment()
  let call = 0
  globalThis.fetch = (_input) => {
    call += 1
    if (call === 1) return Promise.resolve(jsonResponse({ id: "10000000-0000-0000-0000-000000000001" }))
    if (call === 2) return Promise.resolve(jsonResponse([operation()]))
    if (call === 3) return Promise.resolve(jsonResponse(false))
    throw new Error("Revoked access must stop before any Google request")
  }
  try {
    const response = await handleRequest(request({ action: "download", operationId: "40000000-0000-0000-0000-000000000001", fileId: "selected-file" }))
    assertEquals(response.status, 403)
    assertEquals(call, 3)
  } finally {
    globalThis.fetch = originalFetch
  }
})
