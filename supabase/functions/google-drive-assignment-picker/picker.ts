export const DRIVE_FILE_SCOPE = "https://www.googleapis.com/auth/drive.file"
export const MAX_FILE_BYTES = 10 * 1024 * 1024
export const MAX_PICKED_FILES = 10

export type GoogleDriveFile = {
  id: string
  name: string
  mimeType: string
  size?: string
  capabilities?: { canDownload?: boolean }
}

export type AssignmentDriveFile = {
  id: string
  name: string
  mimeType: string
  size: number | null
  exportMimeType: string | null
}

const GOOGLE_EXPORTS: Record<string, { extension: string; mimeType: string }> = {
  "application/vnd.google-apps.document": {
    extension: "docx",
    mimeType: "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
  },
  "application/vnd.google-apps.spreadsheet": {
    extension: "xlsx",
    mimeType: "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
  },
  "application/vnd.google-apps.presentation": {
    extension: "pptx",
    mimeType: "application/vnd.openxmlformats-officedocument.presentationml.presentation",
  },
}

export class AssignmentDriveValidationError extends Error {}

export function normalizePickedFileIds(value: unknown): string[] {
  const values = Array.isArray(value)
    ? value
    : typeof value === "string"
    ? value.split(",")
    : []
  const ids = [...new Set(values.map((item) => String(item).trim()).filter(Boolean))]
  if (ids.length === 0) throw new AssignmentDriveValidationError("Choose at least one Google Drive file.")
  if (ids.length > MAX_PICKED_FILES) {
    throw new AssignmentDriveValidationError(`Choose no more than ${MAX_PICKED_FILES} files at a time.`)
  }
  if (ids.some((id) => !/^[A-Za-z0-9_-]{3,256}$/.test(id))) {
    throw new AssignmentDriveValidationError("Google returned an invalid file selection.")
  }
  return ids
}

export function normalizeDriveFile(file: GoogleDriveFile): AssignmentDriveFile {
  if (!file.id || !file.name || !file.mimeType) {
    throw new AssignmentDriveValidationError("Google returned incomplete file information.")
  }
  if (file.mimeType === "application/vnd.google-apps.folder") {
    throw new AssignmentDriveValidationError("Folders cannot be attached. Choose individual files instead.")
  }
  if (file.mimeType === "application/vnd.google-apps.shortcut") {
    throw new AssignmentDriveValidationError("Google Drive shortcuts cannot be attached. Choose the original file instead.")
  }
  if (file.capabilities?.canDownload === false) {
    throw new AssignmentDriveValidationError(`${safeName(file.name)} cannot be downloaded from Google Drive.`)
  }

  const googleExport = GOOGLE_EXPORTS[file.mimeType]
  if (file.mimeType.startsWith("application/vnd.google-apps.") && !googleExport) {
    throw new AssignmentDriveValidationError(
      `${safeName(file.name)} is not a supported Google file. Choose a Doc, Sheet, Slide, or uploaded file.`,
    )
  }

  const parsedSize = file.size === undefined ? null : Number(file.size)
  if (parsedSize !== null && (!Number.isSafeInteger(parsedSize) || parsedSize < 0)) {
    throw new AssignmentDriveValidationError(`Google returned an invalid size for ${safeName(file.name)}.`)
  }
  if (parsedSize !== null && parsedSize > MAX_FILE_BYTES) {
    throw new AssignmentDriveValidationError(`${safeName(file.name)} is larger than FireflyFM's 10 MB limit.`)
  }

  return {
    id: file.id,
    name: googleExport ? replacingExtension(safeName(file.name), googleExport.extension) : safeName(file.name),
    mimeType: googleExport?.mimeType ?? file.mimeType,
    size: parsedSize,
    exportMimeType: googleExport?.mimeType ?? null,
  }
}

export function googleDownloadURL(file: AssignmentDriveFile): string {
  const id = encodeURIComponent(file.id)
  return file.exportMimeType
    ? `https://www.googleapis.com/drive/v3/files/${id}/export?mimeType=${encodeURIComponent(file.exportMimeType)}`
    : `https://www.googleapis.com/drive/v3/files/${id}?alt=media`
}

export async function readLimitedBody(response: Response, maximumBytes = MAX_FILE_BYTES): Promise<Uint8Array> {
  const declaredLength = Number(response.headers.get("content-length"))
  if (Number.isFinite(declaredLength) && declaredLength > maximumBytes) {
    throw new AssignmentDriveValidationError("This Google Drive file is larger than FireflyFM's 10 MB limit.")
  }
  if (!response.body) return new Uint8Array()

  const reader = response.body.getReader()
  const chunks: Uint8Array[] = []
  let length = 0
  while (true) {
    const { done, value } = await reader.read()
    if (done) break
    length += value.byteLength
    if (length > maximumBytes) {
      await reader.cancel()
      throw new AssignmentDriveValidationError("This Google Drive file is larger than FireflyFM's 10 MB limit.")
    }
    chunks.push(value)
  }
  const result = new Uint8Array(length)
  let offset = 0
  for (const chunk of chunks) {
    result.set(chunk, offset)
    offset += chunk.byteLength
  }
  return result
}

function safeName(value: string): string {
  const sanitized = value.replace(/[\\/\u0000-\u001f\u007f]/g, "-").trim()
  return sanitized.slice(0, 240) || "Google Drive file"
}

function replacingExtension(name: string, extension: string): string {
  const lastDot = name.lastIndexOf(".")
  const base = lastDot > 0 ? name.slice(0, lastDot) : name
  return `${base}.${extension}`
}
