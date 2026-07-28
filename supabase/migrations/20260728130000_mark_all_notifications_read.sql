-- Mark every visible inbox notification read without dismissing it.
BEGIN;

CREATE OR REPLACE FUNCTION public.mark_all_notifications_read()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    affected_count INTEGER;
BEGIN
    UPDATE public.notification_recipients
    SET read_at = COALESCE(read_at, NOW()),
        opened_at = COALESCE(opened_at, NOW()),
        delivery_state = CASE
            WHEN delivery_state IN ('acknowledged', 'failed') THEN delivery_state
            ELSE 'opened'
        END
    WHERE user_id = auth.uid()
      AND read_at IS NULL
      AND delivery_state NOT IN ('dismissed', 'expired');

    GET DIAGNOSTICS affected_count = ROW_COUNT;
    RETURN affected_count;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_all_notifications_read() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_all_notifications_read() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260728130000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
COMMIT;
