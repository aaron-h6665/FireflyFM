# Notification outbox worker

Invoke this Edge Function every minute with either the Supabase service-role bearer token or `x-outbox-worker-secret`. It first advances due/missed medication tasks, then claims and delivers notification outbox rows through APNs.

Required production secrets: `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_PRIVATE_KEY` (the `.p8` contents), and `APNS_BUNDLE_ID`. Optional secrets are `APNS_ENVIRONMENT` (`development` by default) and `OUTBOX_WORKER_SECRET`.

Delivery failures use database-managed exponential backoff. After eight attempts the recipient delivery is marked `expired`; invalid APNs tokens are removed immediately.
