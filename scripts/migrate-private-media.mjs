#!/usr/bin/env node

import { createHash } from "node:crypto";
import { writeFile } from "node:fs/promises";

const baseUrl = required("SUPABASE_URL").replace(/\/$/, "");
const serviceKey = required("SUPABASE_SERVICE_ROLE_KEY");
const execute = process.argv.includes("--execute");
const deleteSource = process.argv.includes("--delete-source");
const manifestArg = process.argv.find((arg) => arg.startsWith("--manifest="));
const manifestPath = manifestArg?.slice("--manifest=".length) || "private-media-migration-manifest.json";

if (deleteSource && !execute) fail("--delete-source requires --execute");

const headers = {
  apikey: serviceKey,
  Authorization: `Bearer ${serviceKey}`,
};
const manifest = {
  mode: execute ? (deleteSource ? "execute-and-cutover" : "execute") : "dry-run",
  startedAt: new Date().toISOString(),
  entries: [],
  errors: [],
};

const [messages, rooms, profiles, schools] = await Promise.all([
  table("messages", "id,room_id,school_id,sender_id,media_url,file_url,audio_url,media_path,file_path,audio_path"),
  table("chat_rooms", "id,school_id,created_by,profile_image_url,profile_image_path"),
  table("profiles", "id,avatar_url,avatar_path"),
  table("schools", "id,profile_image_url,profile_image_path"),
]);
const roomsById = new Map(rooms.map((room) => [room.id, room]));
const jobs = [];

for (const message of messages) {
  const room = roomsById.get(message.room_id);
  const schoolId = message.school_id || room?.school_id;
  if (!schoolId) continue;
  for (const [kind, urlField, pathField] of [
    ["images", "media_url", "media_path"],
    ["files", "file_url", "file_path"],
    ["audio", "audio_url", "audio_path"],
  ]) {
    if (!message[urlField]) continue;
    const sourcePath = legacyPath(message[urlField]);
    if (!sourcePath) continue;
    jobs.push({
      table: "messages", id: message.id, urlField, pathField, sourcePath,
      destinationBucket: "school_private_files",
      destinationPath: message[pathField]
        || `schools/${schoolId}/chat_rooms/${message.room_id}/${message.sender_id}/${kind}/${fileName(sourcePath)}`,
    });
  }
}

for (const room of rooms) {
  if (!room.profile_image_url || !room.school_id || !room.created_by) continue;
  const sourcePath = legacyPath(room.profile_image_url);
  if (!sourcePath) continue;
  jobs.push({
    table: "chat_rooms", id: room.id, urlField: "profile_image_url", pathField: "profile_image_path", sourcePath,
    destinationBucket: "school_private_files",
    destinationPath: room.profile_image_path
      || `schools/${room.school_id}/chat_rooms/${room.id}/${room.created_by}/room-profile/${fileName(sourcePath)}`,
  });
}

for (const profile of profiles) {
  if (!profile.avatar_url) continue;
  const sourcePath = legacyPath(profile.avatar_url);
  if (!sourcePath) continue;
  jobs.push({
    table: "profiles", id: profile.id, urlField: "avatar_url", pathField: "avatar_path", sourcePath,
    destinationBucket: "profile_assets",
    destinationPath: profile.avatar_path || `users/${profile.id}/avatars/${fileName(sourcePath)}`,
  });
}

for (const school of schools) {
  if (!school.profile_image_url) continue;
  const sourcePath = legacyPath(school.profile_image_url);
  if (!sourcePath) continue;
  jobs.push({
    table: "schools", id: school.id, urlField: "profile_image_url", pathField: "profile_image_path", sourcePath,
    destinationBucket: "school_private_files",
    destinationPath: school.profile_image_path
      || `schools/${school.id}/school_assets/${school.id}/${fileName(sourcePath)}`,
  });
}

const sourceObjects = await listAllObjects("chat_attachments");
const sourceObjectSet = new Set(sourceObjects);
const referencedSourceObjects = [...new Set(jobs.map((job) => job.sourcePath))].sort();
const referencedSourceObjectSet = new Set(referencedSourceObjects);
const unreferencedSourceObjects = sourceObjects.filter((path) => !referencedSourceObjectSet.has(path));
const missingSourceObjects = referencedSourceObjects.filter((path) => !sourceObjectSet.has(path));

manifest.inventory = {
  sourceObjectCount: sourceObjects.length,
  referencedSourceObjectCount: referencedSourceObjects.length,
  databaseReferenceCount: jobs.length,
  unreferencedSourceObjects,
  missingSourceObjects,
};
if (unreferencedSourceObjects.length || missingSourceObjects.length) {
  manifest.errors.push({
    phase: "inventory",
    error: "Legacy bucket objects and database references do not reconcile",
    unreferencedSourceObjects,
    missingSourceObjects,
  });
}

for (const job of jobs) {
  if (!sourceObjectSet.has(job.sourcePath)) continue;
  try {
    const entry = await migrate(job);
    manifest.entries.push(entry);
  } catch (error) {
    manifest.errors.push({ ...job, error: error instanceof Error ? error.message : String(error) });
  }
}

manifest.finishedAt = new Date().toISOString();
manifest.summary = {
  discovered: jobs.length,
  sourceObjects: sourceObjects.length,
  referencedSourceObjects: referencedSourceObjects.length,
  unreferencedSourceObjects: unreferencedSourceObjects.length,
  missingSourceObjects: missingSourceObjects.length,
  completed: manifest.entries.filter((entry) => entry.status === "verified").length,
  planned: manifest.entries.filter((entry) => entry.status === "planned").length,
  failed: manifest.errors.length,
};
await writeFile(manifestPath, `${JSON.stringify(manifest, null, 2)}\n`, { mode: 0o600 });
console.log(JSON.stringify(manifest.summary));
console.log(`Manifest: ${manifestPath}`);
if (manifest.errors.length) process.exitCode = 1;

async function migrate(job) {
  if (!execute) return { ...job, status: "planned" };
  const source = await download("chat_attachments", job.sourcePath);
  const checksum = sha256(source.bytes);
  const recoveryPath = `chat_attachments/${job.sourcePath}`;

  await upload("legacy_media_recovery", recoveryPath, source.bytes, source.contentType);
  await upload(job.destinationBucket, job.destinationPath, source.bytes, source.contentType);
  const recovered = await download("legacy_media_recovery", recoveryPath);
  const verified = await download(job.destinationBucket, job.destinationPath);
  const recoveryChecksum = sha256(recovered.bytes);
  const destinationChecksum = sha256(verified.bytes);
  if (recoveryChecksum !== checksum) throw new Error("recovery checksum mismatch");
  if (destinationChecksum !== checksum) throw new Error("destination checksum mismatch");

  await patch(job.table, job.id, { [job.pathField]: job.destinationPath });
  await validateReference(job);
  if (deleteSource) {
    await remove("chat_attachments", job.sourcePath);
    await patch(job.table, job.id, {
      [job.pathField]: job.destinationPath,
      [job.urlField]: null,
    });
  }
  return { ...job, checksum, recoveryPath, status: "verified", sourceDeleted: deleteSource };
}

async function table(name, select) {
  const rows = [];
  let offset = 0;
  const limit = 1000;
  while (true) {
    const response = await request(`/rest/v1/${name}?select=${encodeURIComponent(select)}`, {
      headers: { Range: `${offset}-${offset + limit - 1}` },
    });
    const page = await response.json();
    rows.push(...page);
    if (page.length < limit) break;
    offset += limit;
  }
  return rows;
}

async function listAllObjects(bucket, prefix = "") {
  const objects = [];
  let offset = 0;
  const limit = 1000;

  while (true) {
    const response = await request(`/storage/v1/object/list/${encodeURIComponent(bucket)}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        prefix,
        limit,
        offset,
        sortBy: { column: "name", order: "asc" },
      }),
    });
    const entries = await response.json();
    for (const entry of entries) {
      const path = prefix && !entry.name.startsWith(`${prefix}/`)
        ? `${prefix}/${entry.name}`
        : entry.name;
      if (entry.id == null && entry.metadata == null) {
        objects.push(...await listAllObjects(bucket, path));
      } else {
        objects.push(path);
      }
    }
    if (entries.length < limit) break;
    offset += limit;
  }

  return [...new Set(objects)].sort();
}

async function patch(name, id, body) {
  await request(`/rest/v1/${name}?id=eq.${encodeURIComponent(id)}`, {
    method: "PATCH",
    headers: { "Content-Type": "application/json", Prefer: "return=minimal" },
    body: JSON.stringify(body),
  });
}

async function validateReference(job) {
  const response = await request(
    `/rest/v1/${job.table}?id=eq.${encodeURIComponent(job.id)}&select=${encodeURIComponent(job.pathField)}`,
  );
  const rows = await response.json();
  if (rows.length !== 1 || rows[0][job.pathField] !== job.destinationPath) {
    throw new Error("database reference validation failed");
  }
}

async function download(bucket, path) {
  const response = await request(`/storage/v1/object/${bucket}/${encodePath(path)}`);
  return {
    bytes: new Uint8Array(await response.arrayBuffer()),
    contentType: response.headers.get("content-type") || "application/octet-stream",
  };
}

async function upload(bucket, path, bytes, contentType) {
  await request(`/storage/v1/object/${bucket}/${encodePath(path)}`, {
    method: "POST",
    headers: { "Content-Type": contentType, "x-upsert": "true" },
    body: bytes,
  });
}

async function remove(bucket, path) {
  await request(`/storage/v1/object/${bucket}/${encodePath(path)}`, { method: "DELETE" });
}

async function request(path, options = {}) {
  const response = await fetch(`${baseUrl}${path}`, {
    ...options,
    headers: { ...headers, ...options.headers },
  });
  if (!response.ok) throw new Error(`${options.method || "GET"} ${path} failed (${response.status})`);
  return response;
}

function legacyPath(value) {
  try {
    const url = new URL(value);
    const marker = "/storage/v1/object/";
    const index = url.pathname.indexOf(marker);
    if (index < 0) return null;
    const tail = url.pathname.slice(index + marker.length).replace(/^(public|sign|authenticated)\//, "");
    const prefix = "chat_attachments/";
    if (!tail.startsWith(prefix)) return null;
    return decodeURIComponent(tail.slice(prefix.length));
  } catch {
    return null;
  }
}

function fileName(path) {
  return path.split("/").at(-1) || "legacy-object";
}

function encodePath(path) {
  return path.split("/").map(encodeURIComponent).join("/");
}

function sha256(bytes) {
  return createHash("sha256").update(bytes).digest("hex");
}

function required(name) {
  const value = process.env[name];
  if (!value) fail(`${name} is required`);
  return value;
}

function fail(message) {
  console.error(message);
  process.exit(2);
}
