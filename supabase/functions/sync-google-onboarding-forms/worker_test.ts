import assert from "node:assert/strict"
import test from "node:test"

test("scheduled worker selects stale interrupted runs but excludes disconnected Forms", async () => {
  let handler: (request: Request) => Promise<Response>
  const originalFetch = globalThis.fetch
  const runtime = globalThis as typeof globalThis & { Deno?: unknown }
  const originalDeno = runtime.Deno
  const requested: URL[] = []
  runtime.Deno = {
    serve: (callback: typeof handler) => { handler = callback },
    env: { get: (name: string) => ({
      GOOGLE_FORMS_WORKER_SECRET: "test-worker",
      SUPABASE_URL: "https://test.invalid",
      SUPABASE_SERVICE_ROLE_KEY: "test-key",
    }[name]) },
  }
  globalThis.fetch = async (input) => {
    requested.push(new URL(String(input)))
    return Response.json([])
  }
  try {
    await import("./index.ts")
    const response = await handler!(new Request("https://test.invalid/sync", {
      method: "POST", headers: { "x-google-forms-worker-secret": "test-worker" }, body: "{}",
    }))
    assert.equal(response.status, 200)
    assert.deepEqual(await response.json(), { synced: 0, outcomes: [] })
    assert.equal(requested.length, 1)
    const filter = requested[0].searchParams.get("or")!
    assert.match(filter, /^\(status.in.\(connected,error\),and\(status.eq.syncing,updated_at.lt./)
    assert.ok(!filter.includes("disconnected"))
    const cutoff = filter.match(/updated_at.lt.(.+)\)\)$/)![1]
    assert.ok(Math.abs(Date.now() - Date.parse(cutoff) - 600_000) < 5000)
  } finally {
    globalThis.fetch = originalFetch
    runtime.Deno = originalDeno
  }
})
