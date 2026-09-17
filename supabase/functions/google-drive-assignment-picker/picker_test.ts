import { assertEquals, assertRejects, assertThrows } from "jsr:@std/assert"
import {
  AssignmentDriveValidationError,
  googleDownloadURL,
  MAX_FILE_BYTES,
  normalizeDriveFile,
  normalizePickedFileIds,
  readLimitedBody,
} from "./picker.ts"

Deno.test("normalizes unique picker file ids", () => {
  assertEquals(normalizePickedFileIds("first,second,first"), ["first", "second"])
})

Deno.test("rejects empty, forged, and excessive picker selections", () => {
  assertThrows(() => normalizePickedFileIds(""), AssignmentDriveValidationError)
  assertThrows(() => normalizePickedFileIds("valid,not valid"), AssignmentDriveValidationError)
  assertThrows(
    () => normalizePickedFileIds(Array.from({ length: 11 }, (_, index) => `file_${index}`)),
    AssignmentDriveValidationError,
  )
})

Deno.test("converts Google workspace files to fixed Office snapshots", () => {
  const document = normalizeDriveFile({
    id: "document-id",
    name: "Lesson plan.gdoc",
    mimeType: "application/vnd.google-apps.document",
    capabilities: { canDownload: true },
  })
  assertEquals(document.name, "Lesson plan.docx")
  assertEquals(document.mimeType, "application/vnd.openxmlformats-officedocument.wordprocessingml.document")
  assertEquals(
    googleDownloadURL(document),
    "https://www.googleapis.com/drive/v3/files/document-id/export?mimeType=application%2Fvnd.openxmlformats-officedocument.wordprocessingml.document",
  )

  const spreadsheet = normalizeDriveFile({
    id: "spreadsheet-id",
    name: "Class list",
    mimeType: "application/vnd.google-apps.spreadsheet",
  })
  assertEquals(spreadsheet.name, "Class list.xlsx")
  assertEquals(spreadsheet.mimeType, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet")

  const presentation = normalizeDriveFile({
    id: "presentation-id",
    name: "Orientation.gslides",
    mimeType: "application/vnd.google-apps.presentation",
  })
  assertEquals(presentation.name, "Orientation.pptx")
  assertEquals(presentation.mimeType, "application/vnd.openxmlformats-officedocument.presentationml.presentation")
})

Deno.test("preserves uploaded files and rejects folders and oversized files", () => {
  const pdf = normalizeDriveFile({ id: "pdf-id", name: "report.pdf", mimeType: "application/pdf", size: "42" })
  assertEquals(pdf.name, "report.pdf")
  assertEquals(pdf.size, 42)
  assertEquals(googleDownloadURL(pdf), "https://www.googleapis.com/drive/v3/files/pdf-id?alt=media")

  assertThrows(
    () => normalizeDriveFile({ id: "folder-id", name: "Folder", mimeType: "application/vnd.google-apps.folder" }),
    AssignmentDriveValidationError,
  )
  assertThrows(
    () => normalizeDriveFile({ id: "large-id", name: "large.pdf", mimeType: "application/pdf", size: String(MAX_FILE_BYTES + 1) }),
    AssignmentDriveValidationError,
  )
  assertThrows(
    () => normalizeDriveFile({ id: "drawing-id", name: "Drawing", mimeType: "application/vnd.google-apps.drawing" }),
    AssignmentDriveValidationError,
  )
})

Deno.test("limits exported response bodies when size is not declared", async () => {
  const stream = new ReadableStream<Uint8Array>({
    start(controller) {
      controller.enqueue(new Uint8Array([1, 2, 3]))
      controller.enqueue(new Uint8Array([4, 5, 6]))
      controller.close()
    },
  })
  await assertRejects(
    () => readLimitedBody(new Response(stream), 5),
    AssignmentDriveValidationError,
  )
})
