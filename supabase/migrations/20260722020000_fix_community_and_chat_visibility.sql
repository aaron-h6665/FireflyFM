-- Restore school-wide Community visibility for active adult members and make
-- managed chat discovery atomic. This is intentionally a follow-up migration:
-- 20260722010000 may already be applied on hosted projects.

DROP POLICY IF EXISTS "School members can view community posts" ON public.community_posts;
CREATE POLICY "Active school members can view community posts"
    ON public.community_posts FOR SELECT
    USING (public.has_school_membership(school_id, auth.uid()));

DROP POLICY IF EXISTS "School members can view community albums" ON public.community_albums;
CREATE POLICY "Active school members can view community albums"
    ON public.community_albums FOR SELECT
    USING (public.has_school_membership(school_id, auth.uid()));

DROP POLICY IF EXISTS "School members can view community album media" ON public.community_album_media;
CREATE POLICY "Active school members can view community album media"
    ON public.community_album_media FOR SELECT
    USING (public.has_school_membership(school_id, auth.uid()));

CREATE OR REPLACE FUNCTION public.fetch_my_managed_chat_rooms(input_school_id UUID)
RETURNS TABLE (
    id UUID,
    name TEXT,
    description TEXT,
    profile_image_url TEXT,
    profile_image_path TEXT,
    school_id UUID,
    room_type TEXT,
    created_at TIMESTAMPTZ,
    created_by UUID,
    updated_at TIMESTAMPTZ,
    archived_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    participant_joined_at TIMESTAMPTZ,
    participant_last_read_at TIMESTAMPTZ,
    participant_notifications_enabled BOOLEAN,
    participant_role TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
BEGIN
    IF actor IS NULL OR NOT public.has_school_membership(input_school_id, actor) THEN
        RAISE EXCEPTION 'School chat access denied';
    END IF;

    RETURN QUERY
    SELECT
        room.id,
        room.name,
        room.description,
        room.profile_image_url,
        room.profile_image_path,
        room.school_id,
        room.room_type,
        room.created_at,
        room.created_by,
        room.updated_at,
        room.archived_at,
        room.deleted_at,
        participant.joined_at,
        participant.last_read_at,
        participant.notifications_enabled,
        participant.role
    FROM public.chat_rooms room
    LEFT JOIN public.chat_participants participant
      ON participant.room_id = room.id
     AND participant.user_id = actor
    WHERE room.school_id = input_school_id
      AND room.deleted_at IS NULL
      AND (
          participant.user_id IS NOT NULL
          OR public.has_direct_school_role(
              input_school_id,
              actor,
              ARRAY['school_director']
          )
      )
    ORDER BY COALESCE(room.updated_at, room.created_at) DESC, room.id;
END;
$$;

REVOKE ALL ON FUNCTION public.fetch_my_managed_chat_rooms(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.fetch_my_managed_chat_rooms(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ SELECT 20260722020000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
