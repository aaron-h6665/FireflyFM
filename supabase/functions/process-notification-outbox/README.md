# Notification outbox worker

Invoke this Edge Function whenever notification outbox work is inserted, with a one-minute Supabase Cron job as recovery. Authenticate with either the Supabase service-role bearer token or `x-outbox-worker-secret`. The worker first advances due/missed medication tasks, then claims and delivers notification outbox rows through APNs.

Required production secrets: `APNS_TEAM_ID`, `APNS_KEY_ID`, `APNS_PRIVATE_KEY` (the `.p8` contents), and `APNS_BUNDLE_ID`. Optional secrets are `APNS_ENVIRONMENT` (`development` by default) and `OUTBOX_WORKER_SECRET`.

Delivery failures use database-managed exponential backoff. After eight attempts the recipient delivery is marked `expired`; invalid APNs tokens are removed immediately.

Store the project URL and worker secret in Supabase Vault before configuring the recovery job. The hosted project can use `pg_cron` and `pg_net` to POST to `/functions/v1/process-notification-outbox` every minute. Do not commit the APNs `.p8` key, service-role key, or worker secret.

The checked-in app entitlement is `development`; App Store distribution signing replaces the APNs environment for production builds. Register both development and production devices and never deliver a token to the opposite APNs host.
