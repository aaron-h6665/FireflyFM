import {
  paymentStatusForInvoice,
  sha256,
  verifyStripeSignature,
} from "./billing.ts"

Deno.test("Stripe signatures accept the expected payload and reject tampering", async () => {
  const body = JSON.stringify({ id: "evt_beta", type: "invoice.paid" })
  const timestamp = 1_700_000_000
  const secret = "whsec_beta_test"
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  )
  const signatureBytes = await crypto.subtle.sign(
    "HMAC",
    key,
    new TextEncoder().encode(`${timestamp}.${body}`),
  )
  const signature = Array.from(new Uint8Array(signatureBytes))
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("")
  const header = `t=${timestamp},v1=${signature}`

  if (!await verifyStripeSignature(body, header, secret, timestamp)) {
    throw new Error("Expected valid signature")
  }
  if (await verifyStripeSignature(`${body}x`, header, secret, timestamp)) {
    throw new Error("Tampered payload should be rejected")
  }
  if (await verifyStripeSignature(body, header, secret, timestamp + 301)) {
    throw new Error("Stale signature should be rejected")
  }
})

Deno.test("invoice states map to safe payment projections", () => {
  if (paymentStatusForInvoice("paid", 1000) !== "succeeded") throw new Error("paid")
  if (paymentStatusForInvoice("open", 0) !== "pending") throw new Error("open")
  if (paymentStatusForInvoice("void", 0) !== "failed") throw new Error("void")
})

Deno.test("SHA-256 output is deterministic and contains no payload", async () => {
  const digest = await sha256("sensitive payload")
  if (digest.length !== 64 || digest.includes("sensitive")) throw new Error("Invalid digest")
  if (digest !== await sha256("sensitive payload")) throw new Error("Digest changed")
})
