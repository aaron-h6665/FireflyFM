Deno.serve((request) => {
  if (request.method !== "GET") return new Response("Method not allowed", { status: 405 })
  const mode = new URL(request.url).searchParams.get("state")
  const needsRetry = mode === "refresh"
  const title = needsRetry ? "Stripe setup link expired" : "Stripe setup saved"
  const message = needsRetry
    ? "Return to FireflyFM and tap Continue Stripe setup to create a new secure link."
    : "Return to FireflyFM and refresh Payments. Stripe verification updates can take a moment."
  const html = `<!doctype html>
  <html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
  <title>${title}</title><style>
  body{font-family:-apple-system,BlinkMacSystemFont,sans-serif;background:#f5f8fb;color:#28276f;display:grid;place-items:center;min-height:100vh;margin:0}
  main{max-width:32rem;background:white;border-radius:16px;padding:2rem;box-shadow:0 8px 30px #0001;text-align:center}
  a{display:inline-block;margin-top:1rem;background:#28276f;color:white;padding:.8rem 1.2rem;border-radius:10px;text-decoration:none;font-weight:600}
  </style></head><body><main><h1>${title}</h1><p>${message}</p><a href="fireflyfm://payments">Return to FireflyFM</a></main></body></html>`
  return new Response(html, {
    headers: {
      "content-type": "text/html; charset=utf-8",
      "cache-control": "no-store",
      "content-security-policy": "default-src 'none'; style-src 'unsafe-inline'; base-uri 'none'; frame-ancestors 'none'",
    },
  })
})
