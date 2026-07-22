-- Let each recipient remove notifications from only their own inbox. Deleting
-- the receipt keeps the underlying school notification intact for everyone
-- else and avoids granting direct DELETE access through RLS.

CREATE OR REPLACE FUNCTION public.dismiss_notification(input_notification_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    DELETE FROM public.notification_recipients
    WHERE notification_id = input_notification_id
      AND user_id = auth.uid();

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Notification was not found for this user';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.clear_my_notifications()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    DELETE FROM public.notification_recipients
    WHERE user_id = auth.uid();

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

REVOKE ALL ON FUNCTION public.dismiss_notification(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.clear_my_notifications() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dismiss_notification(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.clear_my_notifications() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ SELECT 20260721040000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
