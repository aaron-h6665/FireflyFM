#!/usr/bin/env node

/**
 * Creates three confirmed Auth identities for testing invitation-driven
 * onboarding. It deliberately creates no school, membership, invitation,
 * onboarding template, checklist, or assignment.
 *
 * Required environment:
 *   SUPABASE_URL="https://YOUR_PROJECT.supabase.co"
 *   SUPABASE_SERVICE_ROLE_KEY="YOUR_LEGACY_SERVICE_ROLE_JWT"
 *
 *   TEST_PASSWORD must be supplied securely (no default).
 *
 * Optional environment:
 *   TEST_EMAIL_DOMAIN="test.fireflyfm.local"
 *   TEST_RUN_ID="onboarding-001"
 *
 * Run:
 *   npm run test-users:onboarding
 *
 * Use only against local development or a dedicated staging project.
 */

const SUPABASE_URL = requiredEnv("SUPABASE_URL").replace(/\/+$/, "");
const SERVICE_ROLE_KEY = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
const TEST_PASSWORD = requiredEnv("TEST_PASSWORD");
const TEST_EMAIL_DOMAIN = process.env.TEST_EMAIL_DOMAIN || "test.fireflyfm.local";
const TEST_RUN_ID = normalizeRunId(process.env.TEST_RUN_ID || timestampRunId());

validateServiceRoleKey(SERVICE_ROLE_KEY);
validateConfiguration();

const authHeaders = {
  apikey: SERVICE_ROLE_KEY,
  Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
};
const jsonHeaders = {
  ...authHeaders,
  "Content-Type": "application/json",
};

const cohort = {
  director: person("director", "Test", "Director"),
  teacher: person("teacher", "Test", "Teacher"),
  parent: person("parent", "Test", "Parent"),
};

main().catch((error) => {
  console.error("\nFailed to create onboarding test identities:");
  console.error(error.message || error);
  process.exitCode = 1;
});

async function main() {
  console.log(`Creating invitation test identities: ${TEST_RUN_ID}`);
  console.log(`Email domain: ${TEST_EMAIL_DOMAIN}`);

  const users = {
    director: await ensureUser(cohort.director),
    teacher: await ensureUser(cohort.teacher),
    parent: await ensureUser(cohort.parent),
  };

  printSummary(users);
}

function person(role, firstName, lastName) {
  return {
    role,
    email: `${role}.onboarding.${TEST_RUN_ID}@${TEST_EMAIL_DOMAIN}`.toLowerCase(),
    firstName,
    lastName,
    displayName: `${firstName} ${lastName} (${TEST_RUN_ID})`,
  };
}

async function ensureUser(spec) {
  const existing = await findAuthUserByEmail(spec.email);
  if (existing) {
    await updateAuthUser(existing.id, spec);
    await upsertProfile(existing.id, spec.displayName);
    console.log(`Reused identity and reset password: ${spec.email}`);
    return { id: existing.id, ...spec };
  }

  const response = await supabaseFetch("/auth/v1/admin/users", {
    method: "POST",
    body: authUserBody(spec),
  });
  const id = response.user?.id || response.id;
  if (!id) {
    throw new Error(`Auth user response for ${spec.email} did not include an id.`);
  }

  await upsertProfile(id, spec.displayName);
  console.log(`Created identity: ${spec.email}`);
  return { id, ...spec };
}

async function updateAuthUser(id, spec) {
  await supabaseFetch(`/auth/v1/admin/users/${id}`, {
    method: "PUT",
    body: authUserBody(spec),
  });
}

function authUserBody(spec) {
  return {
    email: spec.email,
    password: TEST_PASSWORD,
    email_confirm: true,
    user_metadata: {
      first_name: spec.firstName,
      last_name: spec.lastName,
      display_name: spec.displayName,
    },
  };
}

async function findAuthUserByEmail(email) {
  for (let page = 1; page <= 20; page += 1) {
    const result = await supabaseFetch("/auth/v1/admin/users", {
      method: "GET",
      query: { page, per_page: 1000 },
    });
    const users = result.users || [];
    const match = users.find((user) => user.email?.toLowerCase() === email.toLowerCase());
    if (match) return match;
    if (users.length < 1000) return null;
  }
  throw new Error("Stopped while paging Auth users after 20,000 records.");
}

async function upsertProfile(id, displayName) {
  await supabaseFetch("/rest/v1/profiles", {
    method: "POST",
    query: { on_conflict: "id" },
    prefer: "resolution=merge-duplicates,return=minimal",
    body: {
      id,
      display_name: displayName,
      updated_at: new Date().toISOString(),
    },
  });
}

function printSummary(users) {
  console.log("\nInvitation test identities ready.");

  console.table([
    { Account: "Director", Name: users.director.displayName, Email: users.director.email },
    { Account: "Teacher", Name: users.teacher.displayName, Email: users.teacher.email },
    { Account: "Parent", Name: users.parent.displayName, Email: users.parent.email },
  ]);
  console.log("\nNo school memberships or onboarding checklists were created.");
  console.log("Invite an identity from the app, then open and accept the generated invitation link while signed in as that identity.");
}

async function supabaseFetch(path, options = {}) {
  const url = new URL(`${SUPABASE_URL}${path}`);
  for (const [key, value] of Object.entries(options.query || {})) {
    url.searchParams.set(key, value);
  }

  const headers = { ...(options.body !== undefined ? jsonHeaders : authHeaders) };
  if (options.prefer) headers.Prefer = options.prefer;

  const response = await fetch(url, {
    method: options.method || "GET",
    headers,
    body: options.body !== undefined ? JSON.stringify(options.body) : undefined,
  });
  const text = await response.text();
  const payload = text ? parseJSON(text, url.pathname) : null;
  if (!response.ok) {
    throw new Error(`${options.method || "GET"} ${url.pathname} failed (${response.status}). Response body omitted for privacy.`);
  }
  return payload;
}

function parseJSON(text, path) {
  try {
    return JSON.parse(text);
  } catch {
    throw new Error(`Expected JSON from ${path}. Response body omitted for privacy.`);
  }
}

function requiredEnv(name) {
  const value = process.env[name];
  if (!value) throw new Error(`${name} is required.`);
  return value;
}

function validateConfiguration() {
  if (!SUPABASE_URL.startsWith("http://") && !SUPABASE_URL.startsWith("https://")) {
    throw new Error("SUPABASE_URL must begin with http:// or https://.");
  }
  if (!TEST_EMAIL_DOMAIN.includes(".")) {
    throw new Error("TEST_EMAIL_DOMAIN must be a valid test email domain.");
  }
  if (TEST_PASSWORD.length < 8) {
    throw new Error("TEST_PASSWORD must contain at least 8 characters.");
  }
  if (/\r|\n/.test(TEST_PASSWORD)) {
    throw new Error(
      "TEST_PASSWORD cannot contain a line break. Check that every shell export has a closing quote."
    );
  }
}

function validateServiceRoleKey(key) {
  if (key.includes("YOUR_") || key.includes("...")) {
    throw new Error("SUPABASE_SERVICE_ROLE_KEY still looks like a placeholder.");
  }
  if (key.startsWith("sb_publishable_") || key.startsWith("sb_secret_")) {
    throw new Error(
      "Use the legacy service_role JWT. This script calls Auth Admin REST endpoints directly."
    );
  }
  const parts = key.split(".");
  if (parts.length !== 3) {
    throw new Error("SUPABASE_SERVICE_ROLE_KEY must be a three-part service_role JWT.");
  }
  const payload = decodeJwtPayload(parts[1]);
  if (payload.role !== "service_role") {
    throw new Error(`The supplied JWT role is ${payload.role || "unknown"}, not service_role.`);
  }
}

function decodeJwtPayload(encodedPayload) {
  try {
    const normalized = encodedPayload.replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized.padEnd(
      normalized.length + ((4 - (normalized.length % 4)) % 4),
      "="
    );
    return JSON.parse(Buffer.from(padded, "base64").toString("utf8"));
  } catch {
    throw new Error("Could not decode SUPABASE_SERVICE_ROLE_KEY as a JWT.");
  }
}

function timestampRunId() {
  return new Date().toISOString().replace(/\D/g, "").slice(0, 14);
}

function normalizeRunId(value) {
  const normalized = value
    .toLowerCase()
    .replace(/[^a-z0-9-]+/g, "-")
    .replace(/^-+|-+$/g, "")
    .slice(0, 24);
  if (!normalized) throw new Error("TEST_RUN_ID must contain a letter or number.");
  return normalized;
}
