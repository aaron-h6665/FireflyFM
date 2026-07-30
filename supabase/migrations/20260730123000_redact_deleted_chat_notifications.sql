BEGIN;

CREATE OR REPLACE FUNCTION public.redact_deleted_chat_message_notification()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF (COALESCE(NEW.is_deleted, FALSE) OR NEW.deleted_at IS NOT NULL)
       AND NOT (COALESCE(OLD.is_deleted, FALSE) OR OLD.deleted_at IS NOT NULL) THEN
        UPDATE public.notifications
        SET body = 'Message deleted'
        WHERE category = 'chat_message'
          AND dedupe_key = 'chat:message:' || NEW.id::TEXT
          AND body IS DISTINCT FROM 'Message deleted';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS redact_deleted_chat_message_notification_trigger ON public.messages;
CREATE TRIGGER redact_deleted_chat_message_notification_trigger
    AFTER UPDATE OF is_deleted, deleted_at ON public.messages
    FOR EACH ROW EXECUTE FUNCTION public.redact_deleted_chat_message_notification();

-- Redact previews for messages that were deleted before this trigger existed.
UPDATE public.notifications notification
SET body = 'Message deleted'
FROM public.messages message
WHERE (COALESCE(message.is_deleted, FALSE) OR message.deleted_at IS NOT NULL)
  AND notification.category = 'chat_message'
  AND notification.dedupe_key = 'chat:message:' || message.id::TEXT
  AND notification.body IS DISTINCT FROM 'Message deleted';

REVOKE ALL ON FUNCTION public.redact_deleted_chat_message_notification() FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260730123000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
COMMIT;
