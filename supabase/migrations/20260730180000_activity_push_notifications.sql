-- Finish the APNs notification pipeline, add privacy-aware payload metadata,
-- and make community album notifications transactional and idempotent.

BEGIN;

ALTER TABLE public.notifications
    ADD COLUMN IF NOT EXISTS subtitle TEXT,
    ADD COLUMN IF NOT EXISTS safe_body TEXT,
    ADD COLUMN IF NOT EXISTS thread_key TEXT,
    ADD COLUMN IF NOT EXISTS interruption_level TEXT NOT NULL DEFAULT 'active';

UPDATE public.notifications
SET safe_body = CASE
        WHEN category = 'chat_message' THEN 'Sent a message'
        WHEN category LIKE 'medication_%'
          OR category LIKE 'care_%'
          OR category IN ('health', 'medicine_instruction', 'medication')
            THEN 'Open FireflyFM to view this private update.'
        ELSE body
    END
WHERE safe_body IS NULL;

UPDATE public.notifications
SET thread_key = CASE
        WHEN category LIKE 'chat_%' AND route->>'id' IS NOT NULL
            THEN 'chat:' || (route->>'id')
        WHEN source_type = 'community_album' AND source_id IS NOT NULL
            THEN 'album:' || source_id::TEXT
        ELSE NULL
    END
WHERE thread_key IS NULL;

UPDATE public.notifications
SET interruption_level = CASE
        WHEN category IN ('medication_missed', 'care_health_check') THEN 'time_sensitive'
        WHEN category IN ('community_post', 'community_album', 'community_album_batch', 'newsletter') THEN 'passive'
        ELSE 'active'
    END;

ALTER TABLE public.notifications
    DROP CONSTRAINT IF EXISTS notifications_interruption_level_check;
ALTER TABLE public.notifications
    ADD CONSTRAINT notifications_interruption_level_check
    CHECK (interruption_level IN ('passive', 'active', 'time_sensitive'));

CREATE INDEX IF NOT EXISTS idx_notifications_thread_created
    ON public.notifications(thread_key, created_at DESC)
    WHERE thread_key IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.user_notification_settings (
    user_id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    message_preview_mode TEXT NOT NULL DEFAULT 'sender_only'
        CHECK (message_preview_mode IN ('sender_only', 'full')),
    quiet_hours_start TIME,
    quiet_hours_end TIME,
    time_zone TEXT NOT NULL DEFAULT 'America/New_York',
    permission_prompt_deferred BOOLEAN NOT NULL DEFAULT FALSE,
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.user_notification_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users manage their notification settings" ON public.user_notification_settings;
CREATE POLICY "Users manage their notification settings"
    ON public.user_notification_settings FOR ALL TO authenticated
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

INSERT INTO public.user_notification_settings (
    user_id, quiet_hours_start, quiet_hours_end, time_zone
)
SELECT
    preference.user_id,
    (array_agg(preference.quiet_hours_start) FILTER (WHERE preference.quiet_hours_start IS NOT NULL))[1],
    (array_agg(preference.quiet_hours_end) FILTER (WHERE preference.quiet_hours_end IS NOT NULL))[1],
    COALESCE(
        (array_agg(preference.time_zone) FILTER (WHERE preference.time_zone IS NOT NULL))[1],
        'America/New_York'
    )
FROM public.notification_preferences preference
GROUP BY preference.user_id
ON CONFLICT (user_id) DO NOTHING;

INSERT INTO public.user_notification_settings (user_id)
SELECT users.id FROM auth.users users
ON CONFLICT (user_id) DO NOTHING;

CREATE OR REPLACE FUNCTION public.handle_new_user_notification_settings()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.user_notification_settings (user_id)
    VALUES (NEW.id)
    ON CONFLICT (user_id) DO NOTHING;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_notification_settings ON auth.users;
CREATE TRIGGER on_auth_user_created_notification_settings
AFTER INSERT ON auth.users
FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_notification_settings();

CREATE OR REPLACE FUNCTION public.notification_delivery_available_at(
    input_user_id UUID,
    input_category TEXT,
    input_priority TEXT
)
RETURNS TIMESTAMPTZ
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    preference public.notification_preferences%ROWTYPE;
    settings public.user_notification_settings%ROWTYPE;
    preference_category TEXT;
    quiet_start TIME;
    quiet_end TIME;
    delivery_zone TEXT;
    local_now TIMESTAMP;
    local_date DATE;
    local_time TIME;
    next_delivery_local TIMESTAMP;
BEGIN
    preference_category := CASE
        WHEN input_category LIKE 'assignment_%' OR input_category LIKE 'onboarding_%' THEN 'assignments'
        WHEN input_category LIKE 'attendance_%' OR input_category = 'daily_care_summary' THEN 'attendance'
        WHEN input_category LIKE 'chat_%' THEN 'chat'
        WHEN input_category LIKE 'child_connection_%' THEN 'connections'
        WHEN input_category LIKE 'family_request%' THEN 'family_requests'
        WHEN input_category IN ('announcement', 'school_announcement') THEN 'announcements'
        WHEN input_category IN ('community_post', 'community_album', 'community_album_batch') THEN 'community'
        WHEN input_category = 'newsletter' THEN 'newsletters'
        WHEN input_category LIKE 'event_%' THEN 'events'
        WHEN input_category LIKE 'paperwork_%' OR input_category LIKE 'training_%' THEN 'workflows'
        WHEN input_category LIKE 'medication_%' OR input_category = 'care_medication' THEN 'medication'
        WHEN input_category = 'care_health_check' THEN 'health'
        ELSE input_category
    END;

    SELECT * INTO preference
    FROM public.notification_preferences
    WHERE user_id = input_user_id AND category IN (input_category, preference_category)
    ORDER BY (category = input_category) DESC
    LIMIT 1;

    SELECT * INTO settings
    FROM public.user_notification_settings
    WHERE user_id = input_user_id;

    IF input_priority = 'urgent' OR input_category IN ('medication_missed', 'care_health_check') THEN
        RETURN NOW();
    END IF;
    IF preference.user_id IS NOT NULL AND preference.enabled = FALSE THEN RETURN NULL; END IF;

    quiet_start := COALESCE(settings.quiet_hours_start, preference.quiet_hours_start);
    quiet_end := COALESCE(settings.quiet_hours_end, preference.quiet_hours_end);
    delivery_zone := COALESCE(settings.time_zone, preference.time_zone, 'America/New_York');
    IF quiet_start IS NULL OR quiet_end IS NULL THEN RETURN NOW(); END IF;

    local_now := NOW() AT TIME ZONE delivery_zone;
    local_date := local_now::DATE;
    local_time := local_now::TIME;
    IF quiet_start < quiet_end THEN
        IF local_time >= quiet_start AND local_time < quiet_end THEN
            next_delivery_local := local_date + quiet_end;
        ELSE RETURN NOW(); END IF;
    ELSE
        IF local_time >= quiet_start THEN
            next_delivery_local := (local_date + 1) + quiet_end;
        ELSIF local_time < quiet_end THEN
            next_delivery_local := local_date + quiet_end;
        ELSE RETURN NOW(); END IF;
    END IF;
    RETURN next_delivery_local AT TIME ZONE delivery_zone;
END;
$$;

CREATE OR REPLACE FUNCTION public.enqueue_workflow_notification_v2(
    input_school_id UUID,
    input_title TEXT,
    input_subtitle TEXT,
    input_body TEXT,
    input_safe_body TEXT,
    input_category TEXT,
    input_source_type TEXT,
    input_source_id UUID,
    input_recipient_ids UUID[],
    input_dedupe_key TEXT,
    input_priority TEXT DEFAULT 'routine',
    input_route JSONB DEFAULT '{}'::JSONB,
    input_actor_id UUID DEFAULT NULL,
    input_thread_key TEXT DEFAULT NULL,
    input_interruption_level TEXT DEFAULT 'active'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    notification_uuid UUID;
    valid_recipient_ids UUID[];
BEGIN
    IF input_priority NOT IN ('routine', 'important', 'urgent') THEN
        RAISE EXCEPTION 'Invalid notification priority';
    END IF;
    IF input_interruption_level NOT IN ('passive', 'active', 'time_sensitive') THEN
        RAISE EXCEPTION 'Invalid notification interruption level';
    END IF;
    IF NULLIF(btrim(COALESCE(input_dedupe_key, '')), '') IS NULL THEN
        RAISE EXCEPTION 'A notification deduplication key is required';
    END IF;

    SELECT array_agg(DISTINCT recipient.user_id) INTO valid_recipient_ids
    FROM unnest(COALESCE(input_recipient_ids, ARRAY[]::UUID[])) recipient(user_id)
    WHERE recipient.user_id IS NOT NULL
      AND EXISTS (
          SELECT 1 FROM public.school_memberships membership
          WHERE membership.school_id = input_school_id
            AND membership.user_id = recipient.user_id
            AND membership.active = TRUE
      );
    IF COALESCE(cardinality(valid_recipient_ids), 0) = 0 THEN RETURN NULL; END IF;

    INSERT INTO public.notifications (
        school_id, title, subtitle, body, safe_body, category, source_type,
        source_id, created_by, dedupe_key, priority, route, thread_key,
        interruption_level
    ) VALUES (
        input_school_id, btrim(input_title), NULLIF(btrim(COALESCE(input_subtitle, '')), ''),
        btrim(input_body), COALESCE(NULLIF(btrim(COALESCE(input_safe_body, '')), ''), btrim(input_body)),
        input_category, input_source_type, input_source_id, input_actor_id,
        input_dedupe_key, input_priority, COALESCE(input_route, '{}'::JSONB),
        NULLIF(btrim(COALESCE(input_thread_key, '')), ''), input_interruption_level
    )
    ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL
    DO UPDATE SET dedupe_key = EXCLUDED.dedupe_key
    RETURNING id INTO notification_uuid;

    INSERT INTO public.notification_recipients (notification_id, user_id, delivery_state)
    SELECT notification_uuid, recipient.user_id, 'queued'
    FROM unnest(valid_recipient_ids) recipient(user_id)
    ON CONFLICT (notification_id, user_id) DO NOTHING;

    RETURN notification_uuid;
END;
$$;

REVOKE ALL ON FUNCTION public.enqueue_workflow_notification_v2(
    UUID, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, UUID, UUID[], TEXT, TEXT, JSONB, UUID, TEXT, TEXT
) FROM PUBLIC, authenticated;

CREATE OR REPLACE FUNCTION public.create_transactional_notification(
    input_school_id UUID,
    input_title TEXT,
    input_body TEXT,
    input_category TEXT,
    input_source_type TEXT,
    input_source_id UUID,
    input_recipient_ids UUID[],
    input_idempotency_key TEXT
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    safe_text TEXT;
    presentation TEXT;
BEGIN
    IF actor IS NULL OR NOT (
        public.has_school_role(input_school_id, actor, ARRAY['teacher', 'school_director'])
        OR public.is_hq_director(actor)
    ) THEN RAISE EXCEPTION 'Only school staff can create workflow notifications'; END IF;

    safe_text := CASE
        WHEN input_category = 'chat_message' THEN 'Sent a message'
        WHEN input_category LIKE 'medication_%' OR input_category LIKE 'care_%'
            THEN 'Open FireflyFM to view this private update.'
        ELSE input_body
    END;
    presentation := CASE
        WHEN input_category IN ('community_post', 'community_album', 'community_album_batch', 'newsletter') THEN 'passive'
        WHEN input_category IN ('medication_missed', 'care_health_check') THEN 'time_sensitive'
        ELSE 'active'
    END;

    RETURN public.enqueue_workflow_notification_v2(
        input_school_id, input_title, NULL, input_body, safe_text, input_category,
        input_source_type, input_source_id, input_recipient_ids,
        'workflow:' || actor::TEXT || ':' || btrim(input_idempotency_key),
        'routine', jsonb_build_object(
            'type', COALESCE(input_source_type, 'notification'),
            'id', input_source_id,
            'school_id', input_school_id
        ), actor,
        CASE
            WHEN input_source_type = 'chat_room' THEN 'chat:' || input_source_id::TEXT
            WHEN input_source_type = 'community_album' THEN 'album:' || input_source_id::TEXT
            ELSE NULL
        END,
        presentation
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_chat_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    room_record public.chat_rooms%ROWTYPE;
    sender_name TEXT;
    message_preview TEXT;
BEGIN
    SELECT * INTO room_record FROM public.chat_rooms WHERE id = NEW.room_id;
    SELECT NULLIF(btrim(profile.display_name), '') INTO sender_name
    FROM public.profiles profile WHERE profile.id = NEW.sender_id;
    sender_name := COALESCE(sender_name, 'New message');
    message_preview := COALESCE(
        NULLIF(NEW.text, ''),
        CASE
            WHEN NEW.audio_path IS NOT NULL OR NEW.audio_url IS NOT NULL THEN 'Voice message'
            WHEN NEW.entry_kind = 'care_event' THEN 'New care update'
            WHEN NEW.entry_kind = 'family_request' THEN 'New family request'
            WHEN NEW.entry_kind = 'goal_update' THEN 'New goal update'
            WHEN NEW.media_path IS NOT NULL OR NEW.media_url IS NOT NULL THEN 'Photo'
            WHEN NEW.attachment_name IS NOT NULL THEN NEW.attachment_name
            ELSE 'New attachment'
        END
    );

    IF room_record.deleted_at IS NULL THEN
        PERFORM public.enqueue_workflow_notification_v2(
            room_record.school_id, sender_name, room_record.name, message_preview,
            'Sent a message', 'chat_message', 'chat_room', room_record.id,
            ARRAY(
                SELECT participant.user_id
                FROM public.chat_participants participant
                WHERE participant.room_id = room_record.id
                  AND participant.user_id <> NEW.sender_id
                  AND participant.notifications_enabled = TRUE
            ),
            'chat:message:' || NEW.id::TEXT, 'routine',
            jsonb_build_object(
                'type', 'chat_room', 'id', room_record.id,
                'message_id', NEW.id, 'school_id', room_record.school_id
            ), NEW.sender_id, 'chat:' || room_record.id::TEXT, 'active'
        );
    END IF;
    RETURN NEW;
END;
$$;

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
        SET body = 'Message deleted', safe_body = 'Message deleted'
        WHERE category = 'chat_message'
          AND dedupe_key = 'chat:message:' || NEW.id::TEXT
          AND (body IS DISTINCT FROM 'Message deleted' OR safe_body IS DISTINCT FROM 'Message deleted');
    END IF;
    RETURN NEW;
END;
$$;

CREATE TABLE IF NOT EXISTS public.community_media_mutations (
    actor_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    idempotency_key TEXT NOT NULL,
    album_id UUID NOT NULL REFERENCES public.community_albums(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (actor_id, idempotency_key)
);
ALTER TABLE public.community_media_mutations ENABLE ROW LEVEL SECURITY;

CREATE TABLE IF NOT EXISTS public.community_publication_mutations (
    actor_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    idempotency_key TEXT NOT NULL,
    source_type TEXT NOT NULL CHECK (source_type IN ('community_post', 'community_album', 'newsletter')),
    source_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (actor_id, idempotency_key)
);
ALTER TABLE public.community_publication_mutations ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.community_notification_recipients(
    input_school_id UUID,
    input_actor_id UUID
)
RETURNS UUID[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE(array_agg(membership.user_id), ARRAY[]::UUID[])
    FROM public.school_memberships membership
    WHERE membership.school_id = input_school_id
      AND membership.active = TRUE
      AND membership.role IN ('parent', 'teacher', 'school_director')
      AND membership.user_id <> input_actor_id;
$$;
REVOKE ALL ON FUNCTION public.community_notification_recipients(UUID, UUID) FROM PUBLIC, authenticated;

CREATE OR REPLACE FUNCTION public.publish_community_post(
    input_post_id UUID,
    input_school_id UUID,
    input_body TEXT,
    input_image_path TEXT DEFAULT NULL,
    input_attachment_path TEXT DEFAULT NULL,
    input_attachment_name TEXT DEFAULT NULL,
    input_attachment_type TEXT DEFAULT NULL,
    input_linked_event_id UUID DEFAULT NULL,
    input_poll_question TEXT DEFAULT NULL,
    input_poll_options JSONB DEFAULT NULL,
    input_scheduled_at TIMESTAMPTZ DEFAULT NULL,
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.community_posts
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    saved_post public.community_posts%ROWTYPE;
    previous_source_id UUID;
    preview TEXT;
BEGIN
    IF actor IS NULL OR NOT (
        public.has_school_role(input_school_id, actor, ARRAY['teacher', 'school_director'])
        OR public.is_hq_director(actor)
    ) THEN RAISE EXCEPTION 'Community publishing access denied'; END IF;
    IF NULLIF(btrim(COALESCE(input_body, '')), '') IS NULL
       OR NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Post body and idempotency key are required';
    END IF;
    IF (input_attachment_path IS NOT NULL AND input_attachment_path NOT LIKE
            'schools/' || input_school_id::TEXT || '/community_posts/' || input_post_id::TEXT || '/%')
       OR (input_image_path IS NOT NULL AND input_image_path IS DISTINCT FROM input_attachment_path) THEN
        RAISE EXCEPTION 'Post media path must belong to this school and post';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(actor::TEXT || ':community-publish:' || input_idempotency_key, 0));
    SELECT mutation.source_id INTO previous_source_id
    FROM public.community_publication_mutations mutation
    WHERE mutation.actor_id = actor AND mutation.idempotency_key = btrim(input_idempotency_key)
      AND mutation.source_type = 'community_post';
    IF previous_source_id IS NOT NULL THEN
        RETURN QUERY SELECT * FROM public.community_posts WHERE id = previous_source_id;
        RETURN;
    END IF;

    INSERT INTO public.community_posts (
        id, school_id, body, image_path, attachment_path, attachment_name,
        attachment_type, linked_event_id, poll_question, poll_options,
        scheduled_at, created_by
    ) VALUES (
        input_post_id, input_school_id, btrim(input_body), input_image_path,
        input_attachment_path, input_attachment_name, input_attachment_type,
        input_linked_event_id, NULLIF(btrim(COALESCE(input_poll_question, '')), ''),
        input_poll_options, input_scheduled_at, actor
    ) RETURNING * INTO saved_post;
    INSERT INTO public.community_publication_mutations (actor_id, idempotency_key, source_type, source_id)
    VALUES (actor, btrim(input_idempotency_key), 'community_post', saved_post.id);

    IF input_scheduled_at IS NULL OR input_scheduled_at <= NOW() THEN
        preview := btrim(input_body);
        PERFORM public.enqueue_workflow_notification_v2(
            input_school_id, 'New community post', NULL,
            CASE WHEN preview = '' THEN 'A new school post was shared.' ELSE left(preview, 140) END,
            'A new school post was shared.', 'community_post', 'community_post', saved_post.id,
            public.community_notification_recipients(input_school_id, actor),
            'community:post:published:' || saved_post.id::TEXT,
            'routine', jsonb_build_object(
                'type', 'community_post', 'id', saved_post.id, 'school_id', input_school_id
            ), actor, 'community:post:' || saved_post.id::TEXT, 'passive'
        );
    END IF;

    RETURN QUERY SELECT * FROM public.community_posts WHERE id = saved_post.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.publish_newsletter(
    input_newsletter_id UUID,
    input_school_id UUID,
    input_title TEXT,
    input_body TEXT,
    input_media JSONB,
    input_idempotency_key TEXT
)
RETURNS SETOF public.newsletters
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    saved_newsletter public.newsletters%ROWTYPE;
    previous_source_id UUID;
    preview TEXT;
BEGIN
    IF actor IS NULL OR NOT (
        public.has_school_role(input_school_id, actor, ARRAY['teacher', 'school_director'])
        OR public.is_hq_director(actor)
    ) THEN RAISE EXCEPTION 'Newsletter publishing access denied'; END IF;
    IF NULLIF(btrim(COALESCE(input_title, '')), '') IS NULL
       OR NULLIF(btrim(COALESCE(input_body, '')), '') IS NULL
       OR NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NULL
       OR jsonb_typeof(COALESCE(input_media, '[]'::JSONB)) <> 'array' THEN
        RAISE EXCEPTION 'Newsletter title, body, media array, and idempotency key are required';
    END IF;
    IF EXISTS (
        SELECT 1 FROM jsonb_array_elements(COALESCE(input_media, '[]'::JSONB)) item
        WHERE COALESCE(item->>'file_path', '') NOT LIKE
            'schools/' || input_school_id::TEXT || '/newsletters/' || input_newsletter_id::TEXT || '/%'
    ) THEN RAISE EXCEPTION 'Every newsletter media path must belong to this school and newsletter'; END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(actor::TEXT || ':community-publish:' || input_idempotency_key, 0));
    SELECT mutation.source_id INTO previous_source_id
    FROM public.community_publication_mutations mutation
    WHERE mutation.actor_id = actor AND mutation.idempotency_key = btrim(input_idempotency_key)
      AND mutation.source_type = 'newsletter';
    IF previous_source_id IS NOT NULL THEN
        RETURN QUERY SELECT * FROM public.newsletters WHERE id = previous_source_id;
        RETURN;
    END IF;

    INSERT INTO public.newsletters (id, school_id, title, body, created_by, media)
    VALUES (
        input_newsletter_id, input_school_id, btrim(input_title), input_body,
        actor, COALESCE(input_media, '[]'::JSONB)
    ) RETURNING * INTO saved_newsletter;
    INSERT INTO public.community_publication_mutations (actor_id, idempotency_key, source_type, source_id)
    VALUES (actor, btrim(input_idempotency_key), 'newsletter', saved_newsletter.id);

    preview := btrim(regexp_replace(input_body, '[#*_`]', '', 'g'));
    PERFORM public.enqueue_workflow_notification_v2(
        input_school_id, 'New newsletter: ' || saved_newsletter.title, NULL,
        CASE WHEN preview = '' THEN 'A new school newsletter was published.' ELSE left(preview, 160) END,
        'A new school newsletter was published.', 'newsletter', 'newsletter', saved_newsletter.id,
        public.community_notification_recipients(input_school_id, actor),
        'newsletter:published:' || saved_newsletter.id::TEXT,
        'routine', jsonb_build_object(
            'type', 'newsletter', 'id', saved_newsletter.id, 'school_id', input_school_id
        ), actor, 'newsletter:' || saved_newsletter.id::TEXT, 'passive'
    );

    RETURN QUERY SELECT * FROM public.newsletters WHERE id = saved_newsletter.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.publish_community_album(
    input_album_id UUID,
    input_school_id UUID,
    input_title TEXT,
    input_description TEXT DEFAULT NULL,
    input_cover_path TEXT DEFAULT NULL,
    input_media JSONB DEFAULT '[]'::JSONB,
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.community_albums
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    saved_album public.community_albums%ROWTYPE;
    previous_source_id UUID;
    media_count INTEGER;
    actor_name TEXT;
BEGIN
    IF actor IS NULL OR NOT (
        public.has_school_role(input_school_id, actor, ARRAY['teacher', 'school_director'])
        OR public.is_hq_director(actor)
    ) THEN RAISE EXCEPTION 'Community publishing access denied'; END IF;
    IF NULLIF(btrim(COALESCE(input_title, '')), '') IS NULL
       OR NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NULL
       OR jsonb_typeof(COALESCE(input_media, '[]'::JSONB)) <> 'array' THEN
        RAISE EXCEPTION 'Album title, idempotency key, and media array are required';
    END IF;
    IF input_cover_path IS NOT NULL AND input_cover_path NOT LIKE
        'schools/' || input_school_id::TEXT || '/community_albums/' || input_album_id::TEXT || '/%' THEN
        RAISE EXCEPTION 'Album cover path must belong to this school and album';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(actor::TEXT || ':album:' || input_idempotency_key, 0));
    SELECT mutation.source_id INTO previous_source_id
    FROM public.community_publication_mutations mutation
    WHERE mutation.actor_id = actor AND mutation.idempotency_key = btrim(input_idempotency_key)
      AND mutation.source_type = 'community_album';
    IF previous_source_id IS NOT NULL THEN
        RETURN QUERY SELECT * FROM public.community_albums WHERE id = previous_source_id;
        RETURN;
    END IF;
    SELECT * INTO saved_album FROM public.community_albums WHERE id = input_album_id;
    IF saved_album.id IS NOT NULL THEN
        RETURN QUERY SELECT * FROM public.community_albums WHERE id = saved_album.id;
        RETURN;
    END IF;

    INSERT INTO public.community_albums (id, school_id, title, description, cover_path, created_by)
    VALUES (
        input_album_id, input_school_id, btrim(input_title),
        NULLIF(btrim(COALESCE(input_description, '')), ''), input_cover_path, actor
    ) RETURNING * INTO saved_album;

    INSERT INTO public.community_album_media (
        album_id, school_id, file_name, file_path, content_type, uploaded_by
    )
    SELECT
        input_album_id, input_school_id, media.file_name, media.file_path,
        media.content_type, actor
    FROM jsonb_to_recordset(COALESCE(input_media, '[]'::JSONB)) AS media(
        file_name TEXT, file_path TEXT, content_type TEXT
    )
    WHERE media.file_path LIKE 'schools/' || input_school_id::TEXT || '/community_albums/' || input_album_id::TEXT || '/%';

    GET DIAGNOSTICS media_count = ROW_COUNT;
    IF media_count <> jsonb_array_length(COALESCE(input_media, '[]'::JSONB)) THEN
        RAISE EXCEPTION 'Every album media path must belong to this school and album';
    END IF;
    INSERT INTO public.community_publication_mutations (actor_id, idempotency_key, source_type, source_id)
    VALUES (actor, btrim(input_idempotency_key), 'community_album', saved_album.id);
    SELECT COALESCE(NULLIF(btrim(profile.display_name), ''), 'A staff member') INTO actor_name
    FROM public.profiles profile WHERE profile.id = actor;
    actor_name := COALESCE(actor_name, 'A staff member');

    PERFORM public.enqueue_workflow_notification_v2(
        input_school_id, 'New album: ' || saved_album.title, NULL,
        actor_name || CASE
            WHEN media_count = 1 THEN ' shared 1 photo or video.'
            WHEN media_count > 1 THEN ' shared ' || media_count::TEXT || ' photos and videos.'
            ELSE ' shared a new album.'
        END,
        actor_name || ' shared a new school album.',
        'community_album', 'community_album', saved_album.id,
        public.community_notification_recipients(input_school_id, actor),
        'community:album:published:' || saved_album.id::TEXT,
        'routine', jsonb_build_object(
            'type', 'community_album', 'id', saved_album.id, 'school_id', input_school_id
        ), actor, 'album:' || saved_album.id::TEXT, 'passive'
    );

    RETURN QUERY SELECT * FROM public.community_albums WHERE id = saved_album.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.append_community_album_media(
    input_album_id UUID,
    input_media JSONB,
    input_idempotency_key TEXT
)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    album_record public.community_albums%ROWTYPE;
    media_count INTEGER;
    actor_name TEXT;
BEGIN
    SELECT * INTO album_record FROM public.community_albums WHERE id = input_album_id;
    IF album_record.id IS NULL OR actor IS NULL OR NOT (
        public.has_school_role(album_record.school_id, actor, ARRAY['teacher', 'school_director'])
        OR public.is_hq_director(actor)
    ) THEN RAISE EXCEPTION 'Album update access denied'; END IF;
    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NULL
       OR jsonb_typeof(COALESCE(input_media, '[]'::JSONB)) <> 'array'
       OR jsonb_array_length(COALESCE(input_media, '[]'::JSONB)) = 0 THEN
        RAISE EXCEPTION 'A non-empty media array and idempotency key are required';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(actor::TEXT || ':album-media:' || input_idempotency_key, 0));
    IF EXISTS (
        SELECT 1 FROM public.community_media_mutations mutation
        WHERE mutation.actor_id = actor AND mutation.idempotency_key = btrim(input_idempotency_key)
    ) THEN RETURN 0; END IF;

    INSERT INTO public.community_album_media (
        album_id, school_id, file_name, file_path, content_type, uploaded_by
    )
    SELECT
        album_record.id, album_record.school_id, media.file_name, media.file_path,
        media.content_type, actor
    FROM jsonb_to_recordset(input_media) AS media(file_name TEXT, file_path TEXT, content_type TEXT)
    WHERE media.file_path LIKE 'schools/' || album_record.school_id::TEXT || '/community_albums/' || album_record.id::TEXT || '/%';
    GET DIAGNOSTICS media_count = ROW_COUNT;
    IF media_count <> jsonb_array_length(input_media) THEN
        RAISE EXCEPTION 'Every album media path must belong to this school and album';
    END IF;

    INSERT INTO public.community_media_mutations (actor_id, idempotency_key, album_id)
    VALUES (actor, btrim(input_idempotency_key), album_record.id);
    SELECT COALESCE(NULLIF(btrim(profile.display_name), ''), 'A staff member') INTO actor_name
    FROM public.profiles profile WHERE profile.id = actor;
    actor_name := COALESCE(actor_name, 'A staff member');

    PERFORM public.enqueue_workflow_notification_v2(
        album_record.school_id, album_record.title, NULL,
        actor_name || ' added ' || media_count::TEXT || CASE WHEN media_count = 1 THEN ' photo or video.' ELSE ' photos and videos.' END,
        actor_name || ' added new media to a school album.',
        'community_album_batch', 'community_album', album_record.id,
        public.community_notification_recipients(album_record.school_id, actor),
        'community:album:batch:' || actor::TEXT || ':' || btrim(input_idempotency_key),
        'routine', jsonb_build_object(
            'type', 'community_album', 'id', album_record.id, 'school_id', album_record.school_id
        ), actor, 'album:' || album_record.id::TEXT, 'passive'
    );
    RETURN media_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.process_due_community_posts()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    post_record public.community_posts%ROWTYPE;
    processed_count INTEGER := 0;
    preview TEXT;
BEGIN
    FOR post_record IN
        SELECT post.*
        FROM public.community_posts post
        WHERE post.scheduled_at IS NOT NULL
          AND post.scheduled_at <= NOW()
          AND NOT EXISTS (
              SELECT 1 FROM public.notifications notification
              WHERE notification.dedupe_key = 'community:post:published:' || post.id::TEXT
          )
        ORDER BY post.scheduled_at
        FOR UPDATE SKIP LOCKED
    LOOP
        preview := btrim(post_record.body);
        PERFORM public.enqueue_workflow_notification_v2(
            post_record.school_id, 'New community post', NULL,
            CASE WHEN preview = '' THEN 'A new school post was shared.' ELSE left(preview, 140) END,
            'A new school post was shared.', 'community_post', 'community_post', post_record.id,
            public.community_notification_recipients(post_record.school_id, post_record.created_by),
            'community:post:published:' || post_record.id::TEXT,
            'routine', jsonb_build_object(
                'type', 'community_post', 'id', post_record.id, 'school_id', post_record.school_id
            ), post_record.created_by, 'community:post:' || post_record.id::TEXT, 'passive'
        );
        processed_count := processed_count + 1;
    END LOOP;
    RETURN processed_count;
END;
$$;

DROP FUNCTION IF EXISTS public.fetch_my_notifications(INTEGER);
CREATE FUNCTION public.fetch_my_notifications(input_limit INTEGER DEFAULT 100)
RETURNS TABLE (
    id UUID, school_id UUID, school_name TEXT, title TEXT, subtitle TEXT,
    body TEXT, safe_body TEXT, category TEXT, source_type TEXT, source_id UUID,
    created_by UUID, created_at TIMESTAMPTZ, read_at TIMESTAMPTZ, priority TEXT,
    route JSONB, thread_key TEXT, interruption_level TEXT, delivery_state TEXT,
    attempt_count INTEGER, last_error TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT notification.id, notification.school_id, school.name,
        notification.title, notification.subtitle, notification.body,
        COALESCE(notification.safe_body, notification.body), notification.category,
        notification.source_type, notification.source_id, notification.created_by,
        notification.created_at, recipient.read_at, notification.priority,
        notification.route, notification.thread_key, notification.interruption_level,
        recipient.delivery_state, recipient.attempt_count, recipient.last_error
    FROM public.notification_recipients recipient
    JOIN public.notifications notification ON notification.id = recipient.notification_id
    JOIN public.schools school ON school.id = notification.school_id
    WHERE recipient.user_id = auth.uid()
      AND recipient.delivery_state NOT IN ('dismissed', 'expired')
    ORDER BY notification.created_at DESC
    LIMIT LEAST(GREATEST(COALESCE(input_limit, 100), 1), 200);
$$;

CREATE OR REPLACE FUNCTION public.mark_notification_thread_read(input_thread_key TEXT)
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE changed_count INTEGER;
BEGIN
    UPDATE public.notification_recipients recipient
    SET read_at = COALESCE(recipient.read_at, NOW()),
        opened_at = COALESCE(recipient.opened_at, NOW()),
        delivery_state = CASE
            WHEN recipient.delivery_state IN ('dismissed', 'expired') THEN recipient.delivery_state
            ELSE 'opened'
        END
    FROM public.notifications notification
    WHERE recipient.notification_id = notification.id
      AND recipient.user_id = auth.uid()
      AND notification.thread_key = input_thread_key
      AND recipient.read_at IS NULL;
    GET DIAGNOSTICS changed_count = ROW_COUNT;
    RETURN changed_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.notification_unread_count(input_user_id UUID)
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COUNT(*)::INTEGER
    FROM public.notification_recipients recipient
    WHERE recipient.user_id = input_user_id
      AND recipient.read_at IS NULL
      AND recipient.delivery_state NOT IN ('dismissed', 'expired');
$$;
REVOKE ALL ON FUNCTION public.notification_unread_count(UUID) FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION public.notification_unread_count(UUID) TO service_role;

REVOKE ALL ON FUNCTION public.publish_community_album(UUID, UUID, TEXT, TEXT, TEXT, JSONB, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.append_community_album_media(UUID, JSONB, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.publish_community_post(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, UUID, TEXT, JSONB, TIMESTAMPTZ, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.publish_newsletter(UUID, UUID, TEXT, TEXT, JSONB, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.process_due_community_posts() FROM PUBLIC, authenticated;
REVOKE ALL ON FUNCTION public.mark_notification_thread_read(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.publish_community_album(UUID, UUID, TEXT, TEXT, TEXT, JSONB, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.append_community_album_media(UUID, JSONB, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.publish_community_post(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, UUID, TEXT, JSONB, TIMESTAMPTZ, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.publish_newsletter(UUID, UUID, TEXT, TEXT, JSONB, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.process_due_community_posts() TO service_role;
GRANT EXECUTE ON FUNCTION public.fetch_my_notifications(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_notification_thread_read(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_transactional_notification(UUID, TEXT, TEXT, TEXT, TEXT, UUID, UUID[], TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260730180000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
COMMIT;
