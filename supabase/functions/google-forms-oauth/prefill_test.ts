import assert from "node:assert/strict"
import test from "node:test"
import { prefillParameter } from "./prefill.ts"

test("the configured Form reference maps to its observed responder entry", () => {
  assert.equal(prefillParameter("7181a7e3"), "entry.1904322531")
})
test("numeric-looking API question IDs are still hexadecimal", () => {
  assert.equal(prefillParameter("12345678"), "entry.305419896")
  assert.equal(prefillParameter("ffffffff"), "entry.4294967295")
})
test("malformed question IDs are not silently used in a launch link", () => {
  for (const id of ["", "routing-question", "123456789", "12&entry.3"]) {
    assert.throws(() => prefillParameter(id))
  }
})
