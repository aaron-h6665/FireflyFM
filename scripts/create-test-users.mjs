#!/usr/bin/env node

/**
 * Creates the FireflyFM role-interaction test matrix:
 * - 1 HQ director
 * - 2 schools
 * - 1 school director per school
 * - 1 teacher per school
 * - 2 parents per school
 * - 2 children per school, one child per parent for privacy checks
 *
 * Required environment:
 *   SUPABASE_URL="https://YOUR_PROJECT.supabase.co"
 *   SUPABASE_SERVICE_ROLE_KEY="YOUR_LEGACY_SERVICE_ROLE_JWT"
 *
 *   TEST_PASSWORD must be supplied securely (no default).
 *
 * Optional environment:
 *   TEST_EMAIL_DOMAIN="test.fireflyfm.local"
 *
 * Run:
 *   SUPABASE_URL="..." SUPABASE_SERVICE_ROLE_KEY="..." node scripts/create-test-users.mjs
 */

const SUPABASE_URL = requiredEnv("SUPABASE_URL").replace(/\/+$/, "");
const SERVICE_ROLE_KEY = requiredEnv("SUPABASE_SERVICE_ROLE_KEY");
const TEST_PASSWORD = requiredEnv("TEST_PASSWORD");
const TEST_EMAIL_DOMAIN = process.env.TEST_EMAIL_DOMAIN || "test.fireflyfm.local";
const LEGACY_DEFAULT_SCHOOL_ID = "00000000-0000-0000-0000-000000000001";

validateServiceRoleKey(SERVICE_ROLE_KEY);

const authHeaders = {
  apikey: SERVICE_ROLE_KEY,
  Authorization: `Bearer ${SERVICE_ROLE_KEY}`,
};

const jsonHeaders = {
  ...authHeaders,
  "Content-Type": "application/json",
};

const matrix = {
  hqSchoolName: "FireflyFM Test HQ",
  hqDirector: person("hq.director", "HQ", "Test Director"),
  schools: [
    {
      name: "FireflyFM Test School Alpha",
      slug: "alpha",
      director: person("alpha.director", "Alice", "Alpha Director"),
      teacher: person("alpha.teacher", "Theo", "Alpha Teacher"),
      parents: [
        person("alpha.parent1", "Pat", "Alpha Parent One"),
        person("alpha.parent2", "Parker", "Alpha Parent Two"),
      ],
      children: [
        child("Avery", "Alpha Child", "2021-09-10", "alpha.parent1"),
        child("Amelia", "Alpha Child", "2022-02-14", "alpha.parent2"),
      ],
    },
    {
      name: "FireflyFM Test School Beta",
      slug: "beta",
      director: person("beta.director", "Blake", "Beta Director"),
      teacher: person("beta.teacher", "Taylor", "Beta Teacher"),
      parents: [
        person("beta.parent1", "Perry", "Beta Parent One"),
        person("beta.parent2", "Jordan", "Beta Parent Two"),
      ],
      children: [
        child("Bennett", "Beta Child", "2021-11-03", "beta.parent1"),
        child("Bella", "Beta Child", "2022-06-22", "beta.parent2"),
      ],
    },
  ],
};

const created = {
  users: new Map(),
  schools: new Map(),
  classrooms: new Map(),
  children: [],
};

main().catch((error) => {
  console.error("\nFailed to create test matrix:");
  console.error(error.message || error);
  process.exitCode = 1;
});

async function main() {
  console.log("Creating FireflyFM role-interaction test matrix...");
  console.log(`Email domain: ${TEST_EMAIL_DOMAIN}`);

  const hqUser = await ensureUser(matrix.hqDirector);
  const hqSchool = await ensureSchool(matrix.hqSchoolName, "Internal HQ test container for global director access.");
  await ensureMembership(hqSchool.id, hqUser.id, "hq_director");

  for (const schoolSpec of matrix.schools) {
    const school = await ensureSchool(
      schoolSpec.name,
      "Dedicated test school for role interaction and RLS checks."
    );
    const classroom = await ensureDefaultClassroom(school.id);

    const director = await ensureUser(schoolSpec.director);
    const teacher = await ensureUser(schoolSpec.teacher);
    const parents = [];

    await ensureMembership(school.id, director.id, "school_director");
    await ensurePaymentSetupRecord(school.id, director.id, "director_payment");
    await ensureMembership(school.id, teacher.id, "teacher");
    await ensureClassroomTeacher(classroom.id, teacher.id);

    for (const parentSpec of schoolSpec.parents) {
      const parent = await ensureUser(parentSpec);
      parents.push(parent);
      await ensureMembership(school.id, parent.id, "parent");
      await ensurePaymentSetupRecord(school.id, parent.id, "tuition");
    }

    const parentByKey = new Map(schoolSpec.parents.map((parentSpec, index) => [parentSpec.key, parents[index]]));
    for (const childSpec of schoolSpec.children) {
      const guardian = parentByKey.get(childSpec.guardianKey);
      if (!guardian) {
        throw new Error(`No guardian found for ${childSpec.firstName} ${childSpec.lastName}`);
      }
      const savedChild = await ensureChild(school.id, childSpec);
      await ensureChildGuardian(savedChild.id, guardian.id, "Parent");
      await ensureClassroomChild(classroom.id, savedChild.id);
      created.children.push({ ...savedChild, schoolName: school.name, guardianEmail: guardian.email });
    }
  }

  printSummary();
}

function person(key, firstName, lastName) {
  return {
    key,
    email: `${key}@${TEST_EMAIL_DOMAIN}`.toLowerCase(),
    firstName,
    lastName,
    displayName: `${firstName} ${lastName}`,
  };
}

function child(firstName, lastName, birthdate, guardianKey) {
  return { firstName, lastName, birthdate, guardianKey };
}

function requiredEnv(name) {
  const value = process.env[name];
  if (!value) {
    throw new Error(`${name} is required.`);
  }
  return value;
}

function validateServiceRoleKey(key) {
  if (key.includes("YOUR_") || key.includes("...")) {
    throw new Error("SUPABASE_SERVICE_ROLE_KEY still looks like a placeholder. Paste the real legacy service_role JWT from Supabase.");
  }

  if (key.startsWith("sb_publishable_")) {
    throw new Error("SUPABASE_SERVICE_ROLE_KEY is a publishable key. Use the legacy service_role JWT from Supabase Dashboard > Project Settings > API Keys > Legacy API Keys.");
  }

  if (key.startsWith("sb_secret_")) {
    throw new Error("SUPABASE_SERVICE_ROLE_KEY is a newer sb_secret key. This script calls Auth Admin REST endpoints directly, so use the legacy service_role JWT from Supabase Dashboard > Project Settings > API Keys > Legacy API Keys.");
  }

  const parts = key.split(".");
  if (parts.length !== 3) {
    throw new Error("SUPABASE_SERVICE_ROLE_KEY must be the legacy service_role JWT, which has three dot-separated parts.");
  }

  const payload = decodeJwtPayload(parts[1]);
  if (payload.role !== "service_role") {
    throw new Error(`SUPABASE_SERVICE_ROLE_KEY has JWT role "${payload.role || "unknown"}". Use the legacy service_role key, not the anon key.`);
  }
}

function decodeJwtPayload(encodedPayload) {
  try {
    const normalized = encodedPayload.replace(/-/g, "+").replace(/_/g, "/");
    const padded = normalized.padEnd(normalized.length + ((4 - (normalized.length % 4)) % 4), "=");
    return JSON.parse(Buffer.from(padded, "base64").toString("utf8"));
  } catch {
    throw new Error("Could not decode SUPABASE_SERVICE_ROLE_KEY as a JWT. Use the legacy service_role JWT from Supabase.");
  }
}

async function ensureUser(spec) {
  const existing = await findAuthUserByEmail(spec.email);
  if (existing) {
    await upsertProfile(existing.id, spec.displayName);
    const user = { id: existing.id, email: spec.email, displayName: spec.displayName };
    created.users.set(spec.key, user);
    console.log(`Reused user: ${spec.email}`);
    return user;
  }

  const response = await supabaseFetch("/auth/v1/admin/users", {
    method: "POST",
    body: {
      email: spec.email,
      password: TEST_PASSWORD,
      email_confirm: true,
      user_metadata: {
        first_name: spec.firstName,
        last_name: spec.lastName,
        display_name: spec.displayName,
      },
    },
  });

  const user = {
    id: response.user?.id || response.id,
    email: spec.email,
    displayName: spec.displayName,
  };

  if (!user.id) {
    throw new Error(`Auth user response for ${spec.email} did not include an id.`);
  }

  await upsertProfile(user.id, spec.displayName);
  created.users.set(spec.key, user);
  console.log(`Created user: ${spec.email}`);
  return user;
}

async function findAuthUserByEmail(email) {
  let page = 1;
  while (page < 20) {
    const result = await supabaseFetch("/auth/v1/admin/users", {
      method: "GET",
      query: { page, per_page: 1000 },
    });
    const users = result.users || [];
    const found = users.find((user) => user.email?.toLowerCase() === email.toLowerCase());
    if (found) {
      return found;
    }
    if (users.length < 1000) {
      return null;
    }
    page += 1;
  }
  throw new Error("Stopped while paging Auth users. Narrow the test project or increase the page cap.");
}

async function upsertProfile(id, displayName) {
  await postgrest("profiles", {
    method: "POST",
    query: { on_conflict: "id" },
    prefer: "resolution=merge-duplicates,return=representation",
    body: {
      id,
      display_name: displayName,
      updated_at: new Date().toISOString(),
    },
  });
}

async function ensureSchool(name, description) {
  const existing = await selectOne("schools", { name });
  if (existing) {
    created.schools.set(name, existing);
    console.log(`Reused school: ${name}`);
    return existing;
  }

  const [school] = await postgrest("schools", {
    method: "POST",
    prefer: "return=representation",
    body: { name, description },
  });
  created.schools.set(name, school);
  console.log(`Created school: ${name}`);
  return school;
}

async function ensureMembership(schoolId, userId, role) {
  const rows = await postgrest("school_memberships", {
    method: "POST",
    query: { on_conflict: "school_id,user_id" },
    prefer: "resolution=merge-duplicates,return=representation",
    body: {
      school_id: schoolId,
      user_id: userId,
      role,
      active: true,
      joined_at: new Date().toISOString(),
    },
  });

  const membership = rows?.[0];
  if (!membership || membership.school_id !== schoolId || membership.role !== role || membership.active !== true) {
    throw new Error(`Could not verify active ${role} membership for user ${userId} in school ${schoolId}.`);
  }

  if (schoolId !== LEGACY_DEFAULT_SCHOOL_ID) {
    await deactivateLegacyDefaultMembership(userId);
  }
}

async function deactivateLegacyDefaultMembership(userId) {
  const legacyMemberships = await postgrest("school_memberships", {
    method: "GET",
    query: {
      select: "id,user_id,school_id",
      school_id: `eq.${LEGACY_DEFAULT_SCHOOL_ID}`,
      user_id: `eq.${userId}`,
      active: "eq.true",
    },
  });

  for (const membership of legacyMemberships) {
    await postgrest("school_membership_repair_audit", {
      method: "POST",
      query: { on_conflict: "membership_id" },
      prefer: "resolution=ignore-duplicates,return=minimal",
      body: {
        membership_id: membership.id,
        user_id: membership.user_id,
        school_id: membership.school_id,
        reason: "Test seed deactivated legacy Default School membership after verifying a real active membership",
      },
    });
  }

  await postgrest("school_memberships", {
    method: "PATCH",
    query: {
      school_id: `eq.${LEGACY_DEFAULT_SCHOOL_ID}`,
      user_id: `eq.${userId}`,
      active: "eq.true",
    },
    prefer: "return=minimal",
    body: { active: false },
  });
}

async function ensurePaymentSetupRecord(schoolId, userId, paymentType) {
  await postgrest("payment_setup_records", {
    method: "POST",
    query: { on_conflict: "school_id,user_id,payment_type" },
    prefer: "resolution=merge-duplicates,return=minimal",
    body: {
      school_id: schoolId,
      user_id: userId,
      payment_type: paymentType,
      status: "waived",
      notes: "Payment-provider setup is waived for the MVP test matrix.",
      updated_at: new Date().toISOString(),
    },
  });
}

async function ensureDefaultClassroom(schoolId) {
  const existing = await selectOne("classrooms", { school_id: schoolId, is_default: true });
  if (existing) {
    created.classrooms.set(schoolId, existing);
    return existing;
  }

  const [classroom] = await postgrest("classrooms", {
    method: "POST",
    query: { on_conflict: "school_id,name" },
    prefer: "resolution=merge-duplicates,return=representation",
    body: {
      school_id: schoolId,
      name: "Default Classroom",
      is_default: true,
    },
  });
  created.classrooms.set(schoolId, classroom);
  return classroom;
}

async function ensureClassroomTeacher(classroomId, teacherId) {
  await postgrest("classroom_teachers", {
    method: "POST",
    query: { on_conflict: "classroom_id,teacher_id" },
    prefer: "resolution=ignore-duplicates,return=minimal",
    body: {
      classroom_id: classroomId,
      teacher_id: teacherId,
    },
  });
}

async function ensureChild(schoolId, childSpec) {
  const existing = await selectOne("children", {
    school_id: schoolId,
    first_name: childSpec.firstName,
    last_name: childSpec.lastName,
    birthdate: childSpec.birthdate,
  });
  if (existing) {
    return existing;
  }

  const [savedChild] = await postgrest("children", {
    method: "POST",
    prefer: "return=representation",
    body: {
      school_id: schoolId,
      first_name: childSpec.firstName,
      last_name: childSpec.lastName,
      birthdate: childSpec.birthdate,
      active: true,
    },
  });
  return savedChild;
}

async function ensureChildGuardian(childId, guardianId, relationship) {
  await postgrest("child_guardians", {
    method: "POST",
    query: { on_conflict: "child_id,guardian_id" },
    prefer: "resolution=merge-duplicates,return=minimal",
    body: {
      child_id: childId,
      guardian_id: guardianId,
      relationship,
    },
  });
}

async function ensureClassroomChild(classroomId, childId) {
  await postgrest("classroom_children", {
    method: "POST",
    query: { on_conflict: "classroom_id,child_id" },
    prefer: "resolution=ignore-duplicates,return=minimal",
    body: {
      classroom_id: classroomId,
      child_id: childId,
    },
  });
}

async function selectOne(table, eqFilters) {
  const rows = await postgrest(table, {
    method: "GET",
    query: {
      select: "*",
      limit: "1",
      ...Object.fromEntries(
        Object.entries(eqFilters).map(([key, value]) => [key, `eq.${value}`])
      ),
    },
  });
  return rows[0] || null;
}

async function postgrest(table, options) {
  return supabaseFetch(`/rest/v1/${table}`, options);
}

async function supabaseFetch(path, options = {}) {
  const url = new URL(`${SUPABASE_URL}${path}`);
  for (const [key, value] of Object.entries(options.query || {})) {
    url.searchParams.set(key, value);
  }

  const headers = {
    ...(options.body ? jsonHeaders : authHeaders),
  };
  if (options.prefer) {
    headers.Prefer = options.prefer;
  }

  const response = await fetch(url, {
    method: options.method || "GET",
    headers,
    body: options.body ? JSON.stringify(options.body) : undefined,
  });

  const text = await response.text();
  let payload = null;
  if (text) {
    try { payload = JSON.parse(text); }
    catch { throw new Error(`Invalid JSON from ${url.pathname}. Response body omitted for privacy.`); }
  }
  if (!response.ok) {
    throw new Error(`${options.method || "GET"} ${url.pathname} failed (${response.status}). Response body omitted for privacy.`);
  }
  return payload;
}

function printSummary() {
  console.log("\nRole matrix ready.");

  const rows = [];
  rows.push({ Role: "HQ Director", School: "All / HQ", Email: matrix.hqDirector.email });
  for (const schoolSpec of matrix.schools) {
    rows.push({ Role: "School Director", School: schoolSpec.name, Email: schoolSpec.director.email });
    rows.push({ Role: "Teacher", School: schoolSpec.name, Email: schoolSpec.teacher.email });
    for (const parent of schoolSpec.parents) {
      rows.push({ Role: "Parent", School: schoolSpec.name, Email: parent.email });
    }
  }
  console.table(rows);

  console.log("Children:");
  console.table(
    created.children.map((savedChild) => ({
      School: savedChild.schoolName,
      Child: `${savedChild.first_name} ${savedChild.last_name}`,
      Guardian: savedChild.guardianEmail,
    }))
  );
}
