// Forms API question IDs are hexadecimal; responder entry parameters are decimal.
// Keep question_id unchanged for response answers and store the URL key separately.
export function prefillParameter(questionId: string): string {
  if (!/^[0-9a-f]{1,8}$/i.test(questionId)) throw new Error("Google returned an unsupported routing question ID")
  return `entry.${Number.parseInt(questionId, 16)}`
}
