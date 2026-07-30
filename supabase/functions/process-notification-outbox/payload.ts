export type NotificationPayloadRecord = {
  id: string
  title: string
  subtitle: string | null
  body: string
  safe_body: string | null
  category: string
  priority: "routine" | "important" | "urgent"
  thread_key: string | null
  interruption_level: "passive" | "active" | "time_sensitive"
  route: Record<string, unknown>
}

export type NotificationPayloadSettings = {
  message_preview_mode: "sender_only" | "full"
}

export function buildAPNSPayload(input: {
  notification: NotificationPayloadRecord
  settings?: NotificationPayloadSettings
  unreadCount: number
}) {
  const { notification, settings, unreadCount } = input
  const isChat = notification.category === "chat_message"
  const isPrivateWorkflow = notification.category.startsWith("medication_") ||
    notification.category.startsWith("care_") ||
    ["health", "medicine_instruction", "medication"].includes(notification.category)
  const permitsFullChatPreview = isChat && settings?.message_preview_mode === "full"
  const preferredBody = isPrivateWorkflow
    ? (notification.safe_body ?? "Open FireflyFM to view this private update.")
    : permitsFullChatPreview
    ? notification.body
    : (notification.safe_body ?? notification.body)

  const alert: Record<string, string> = {
    title: truncate(preferred(notification.title, "FireflyFM"), 160),
    body: truncate(preferred(preferredBody, "Open FireflyFM to view this update."), 640),
  }
  if (notification.subtitle?.trim()) alert.subtitle = truncate(notification.subtitle.trim(), 160)

  const aps: Record<string, unknown> = {
    alert,
    badge: Math.max(0, unreadCount),
    category: notificationCategoryIdentifier(notification.category),
    "interruption-level": notification.interruption_level.replace("_", "-"),
  }
  if (notification.thread_key) aps["thread-id"] = notification.thread_key
  if (notification.interruption_level !== "passive") aps.sound = "default"

  return {
    aps,
    notification_id: notification.id,
    route: identifierOnlyRoute(notification.route),
  }
}

export function buildAPNSHeaders(input: {
  authorization: string
  bundleID: string
  interruptionLevel: NotificationPayloadRecord["interruption_level"]
  expirationTimestamp: number
}) {
  return {
    authorization: `bearer ${input.authorization}`,
    "apns-topic": input.bundleID,
    "apns-push-type": "alert",
    "apns-priority": input.interruptionLevel === "passive" ? "5" : "10",
    "apns-expiration": `${input.expirationTimestamp}`,
    "content-type": "application/json",
  }
}

export function apnsHost(environment: string) {
  return environment === "production"
    ? "https://api.push.apple.com"
    : "https://api.sandbox.push.apple.com"
}

function notificationCategoryIdentifier(category: string) {
  if (category === "chat_message") return "FIREFLY_CHAT_MESSAGE"
  if (category === "community_album" || category === "community_album_batch") return "FIREFLY_COMMUNITY_ALBUM"
  if (category === "community_post") return "FIREFLY_COMMUNITY_POST"
  if (category === "newsletter") return "FIREFLY_NEWSLETTER"
  return "FIREFLY_ACTIVITY"
}

function identifierOnlyRoute(route: Record<string, unknown>) {
  const permitted = ["type", "id", "child_id", "school_id", "message_id"]
  return Object.fromEntries(permitted.flatMap((key) => {
    const value = route?.[key]
    return typeof value === "string" ? [[key, value]] : []
  }))
}

function truncate(value: string, limit: number) {
  return value.length <= limit ? value : `${value.slice(0, Math.max(0, limit - 1))}…`
}

function preferred(value: string | null | undefined, fallback: string) {
  return value?.trim() || fallback
}
