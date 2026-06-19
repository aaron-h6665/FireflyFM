-- FireflyFM chat schema
-- Safe to run more than once in the Supabase SQL editor.

CREATE TABLE IF NOT EXISTS chat_rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    profile_image_url TEXT,
    invite_hash TEXT UNIQUE DEFAULT gen_random_uuid()::TEXT,
    room_type TEXT DEFAULT 'public' CHECK (room_type IN ('public', 'private')),
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS chat_participants (
    room_id UUID REFERENCES chat_rooms(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    last_read_at TIMESTAMPTZ DEFAULT NOW(),
    notifications_enabled BOOLEAN DEFAULT TRUE,
    role TEXT DEFAULT 'member',
    PRIMARY KEY (room_id, user_id)
);

CREATE TABLE IF NOT EXISTS profiles (
    id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
    display_name TEXT NOT NULL,
    avatar_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS schools (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    tour_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS school_memberships (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role TEXT NOT NULL CHECK (role IN ('parent', 'teacher', 'school_director', 'hq_director')),
    active BOOLEAN DEFAULT TRUE,
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (school_id, user_id)
);

CREATE TABLE IF NOT EXISTS school_invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    code TEXT UNIQUE NOT NULL DEFAULT upper(substr(replace(gen_random_uuid()::TEXT, '-', ''), 1, 10)),
    role TEXT NOT NULL CHECK (role IN ('parent', 'teacher', 'school_director')),
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    active BOOLEAN DEFAULT TRUE,
    max_uses INTEGER DEFAULT 1,
    use_count INTEGER DEFAULT 0,
    expires_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID REFERENCES chat_rooms(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    text TEXT,
    media_url TEXT,
    file_url TEXT,
    audio_url TEXT,
    attachment_type TEXT,
    attachment_name TEXT,
    attachment_size INTEGER,
    reply_to_message_id UUID REFERENCES messages(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    is_deleted BOOLEAN DEFAULT FALSE
);

CREATE TABLE IF NOT EXISTS newsletters (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS school_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    start_at TIMESTAMPTZ NOT NULL,
    end_at TIMESTAMPTZ,
    all_day BOOLEAN DEFAULT FALSE,
    repeat_rule TEXT,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS school_event_invites (
    event_id UUID NOT NULL REFERENCES school_events(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (event_id, user_id)
);

CREATE TABLE IF NOT EXISTS notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    category TEXT NOT NULL,
    source_type TEXT,
    source_id UUID,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS notification_recipients (
    notification_id UUID NOT NULL REFERENCES notifications(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    read_at TIMESTAMPTZ,
    delivered_at TIMESTAMPTZ,
    PRIMARY KEY (notification_id, user_id)
);

CREATE TABLE IF NOT EXISTS children (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    first_name TEXT NOT NULL,
    last_name TEXT NOT NULL,
    birthdate DATE,
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS child_guardians (
    child_id UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
    guardian_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    relationship TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (child_id, guardian_id)
);

CREATE TABLE IF NOT EXISTS child_attendance (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    child_id UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
    checked_in_at TIMESTAMPTZ,
    checked_out_at TIMESTAMPTZ,
    recorded_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS child_activity_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    child_id UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
    activity_type TEXT NOT NULL,
    notes TEXT,
    metadata JSONB DEFAULT '{}'::JSONB,
    recorded_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    recorded_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS paperwork_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    file_name TEXT,
    file_path TEXT,
    assigned_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    due_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS paperwork_assignment_recipients (
    assignment_id UUID NOT NULL REFERENCES paperwork_assignments(id) ON DELETE CASCADE,
    parent_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (assignment_id, parent_id)
);

CREATE TABLE IF NOT EXISTS paperwork_submissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id UUID NOT NULL REFERENCES paperwork_assignments(id) ON DELETE CASCADE,
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    submitted_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    file_name TEXT,
    file_path TEXT,
    status TEXT DEFAULT 'submitted' CHECK (status IN ('submitted', 'accepted', 'flagged')),
    flag_reason TEXT,
    reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,
    submitted_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS curriculum_resources (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    file_name TEXT,
    file_path TEXT,
    uploaded_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS training_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    file_name TEXT,
    file_path TEXT,
    assigned_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    due_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS training_assignment_recipients (
    assignment_id UUID NOT NULL REFERENCES training_assignments(id) ON DELETE CASCADE,
    teacher_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (assignment_id, teacher_id)
);

CREATE TABLE IF NOT EXISTS training_submissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id UUID NOT NULL REFERENCES training_assignments(id) ON DELETE CASCADE,
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    submitted_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    file_name TEXT,
    file_path TEXT,
    status TEXT DEFAULT 'submitted' CHECK (status IN ('submitted', 'accepted', 'flagged')),
    flag_reason TEXT,
    reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,
    submitted_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE chat_rooms
    ADD COLUMN IF NOT EXISTS description TEXT,
    ADD COLUMN IF NOT EXISTS profile_image_url TEXT,
    ADD COLUMN IF NOT EXISTS invite_hash TEXT UNIQUE DEFAULT gen_random_uuid()::TEXT,
    ADD COLUMN IF NOT EXISTS school_id UUID REFERENCES schools(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS room_type TEXT DEFAULT 'public',
    ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

ALTER TABLE chat_rooms
    DROP CONSTRAINT IF EXISTS chat_rooms_room_type_check,
    ADD CONSTRAINT chat_rooms_room_type_check CHECK (room_type IN ('public', 'private'));

ALTER TABLE school_events
    ADD COLUMN IF NOT EXISTS all_day BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS repeat_rule TEXT;

ALTER TABLE chat_participants
    ADD COLUMN IF NOT EXISTS last_read_at TIMESTAMPTZ DEFAULT NOW(),
    ADD COLUMN IF NOT EXISTS notifications_enabled BOOLEAN DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS role TEXT DEFAULT 'member';

ALTER TABLE messages
    ADD COLUMN IF NOT EXISTS school_id UUID REFERENCES schools(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS attachment_type TEXT,
    ADD COLUMN IF NOT EXISTS attachment_name TEXT,
    ADD COLUMN IF NOT EXISTS attachment_size INTEGER,
    ADD COLUMN IF NOT EXISTS reply_to_message_id UUID REFERENCES messages(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_chat_participants_user_id ON chat_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_chat_participants_room_id ON chat_participants(room_id);
CREATE INDEX IF NOT EXISTS idx_school_memberships_user_id ON school_memberships(user_id);
CREATE INDEX IF NOT EXISTS idx_school_memberships_school_id ON school_memberships(school_id);
CREATE INDEX IF NOT EXISTS idx_school_invites_code ON school_invites(code);
CREATE INDEX IF NOT EXISTS idx_chat_rooms_school_id ON chat_rooms(school_id);
CREATE INDEX IF NOT EXISTS idx_chat_rooms_room_type ON chat_rooms(room_type);
CREATE INDEX IF NOT EXISTS idx_profiles_display_name ON profiles (lower(display_name));
CREATE INDEX IF NOT EXISTS idx_messages_room_created_at ON messages(room_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_school_created_at ON messages(school_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_reply_to ON messages(reply_to_message_id);
CREATE INDEX IF NOT EXISTS idx_newsletters_school_created ON newsletters(school_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_school_events_school_start ON school_events(school_id, start_at);
CREATE INDEX IF NOT EXISTS idx_school_event_invites_user ON school_event_invites(user_id);
CREATE INDEX IF NOT EXISTS idx_notifications_school_created ON notifications(school_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_notification_recipients_user ON notification_recipients(user_id);
CREATE INDEX IF NOT EXISTS idx_children_school ON children(school_id);
CREATE INDEX IF NOT EXISTS idx_child_guardians_guardian ON child_guardians(guardian_id);
CREATE INDEX IF NOT EXISTS idx_child_attendance_child ON child_attendance(child_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_child_activity_logs_child ON child_activity_logs(child_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_paperwork_assignments_school ON paperwork_assignments(school_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_paperwork_recipients_parent ON paperwork_assignment_recipients(parent_id);
CREATE INDEX IF NOT EXISTS idx_paperwork_submissions_assignment ON paperwork_submissions(assignment_id);
CREATE INDEX IF NOT EXISTS idx_curriculum_resources_school ON curriculum_resources(school_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_training_assignments_school ON training_assignments(school_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_training_recipients_teacher ON training_assignment_recipients(teacher_id);
CREATE INDEX IF NOT EXISTS idx_training_submissions_assignment ON training_submissions(assignment_id);

CREATE OR REPLACE FUNCTION public.is_chat_room_member(room_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.chat_participants
        WHERE room_id = room_uuid
          AND user_id = user_uuid
    );
$$;

CREATE OR REPLACE FUNCTION public.is_chat_room_owner(room_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.chat_participants
        WHERE room_id = room_uuid
          AND user_id = user_uuid
          AND role = 'owner'
    )
    OR EXISTS (
        SELECT 1
        FROM public.chat_rooms
        WHERE id = room_uuid
          AND created_by = user_uuid
    );
$$;

GRANT EXECUTE ON FUNCTION public.is_chat_room_member(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_chat_room_owner(UUID, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.is_hq_director(user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.school_memberships
        WHERE user_id = user_uuid
          AND role = 'hq_director'
          AND active = TRUE
    );
$$;

CREATE OR REPLACE FUNCTION public.is_school_member(school_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.is_hq_director(user_uuid)
    OR EXISTS (
        SELECT 1
        FROM public.school_memberships
        WHERE school_id = school_uuid
          AND user_id = user_uuid
          AND active = TRUE
    );
$$;

CREATE OR REPLACE FUNCTION public.has_school_role(school_uuid UUID, user_uuid UUID, allowed_roles TEXT[])
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.is_hq_director(user_uuid)
    OR EXISTS (
        SELECT 1
        FROM public.school_memberships
        WHERE school_id = school_uuid
          AND user_id = user_uuid
          AND active = TRUE
          AND role = ANY(allowed_roles)
    );
$$;

GRANT EXECUTE ON FUNCTION public.is_hq_director(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_school_member(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_school_role(UUID, UUID, TEXT[]) TO authenticated;

CREATE OR REPLACE FUNCTION public.handle_new_user_profile()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    metadata_name TEXT;
    combined_name TEXT;
BEGIN
    metadata_name := NULLIF(TRIM(NEW.raw_user_meta_data->>'display_name'), '');
    combined_name := NULLIF(TRIM(CONCAT_WS(
        ' ',
        NULLIF(NEW.raw_user_meta_data->>'first_name', ''),
        NULLIF(NEW.raw_user_meta_data->>'last_name', '')
    )), '');

    INSERT INTO public.profiles (id, display_name, avatar_url)
    VALUES (
        NEW.id,
        COALESCE(metadata_name, combined_name, split_part(NEW.email, '@', 1), 'Firefly User'),
        NULLIF(NEW.raw_user_meta_data->>'avatar_url', '')
    )
    ON CONFLICT (id) DO NOTHING;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS on_auth_user_created_profile ON auth.users;
CREATE TRIGGER on_auth_user_created_profile
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION public.handle_new_user_profile();

CREATE OR REPLACE FUNCTION public.join_chat_room(invite_text TEXT)
RETURNS SETOF public.chat_rooms
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    code TEXT;
    room_record public.chat_rooms%ROWTYPE;
    joining_user UUID;
BEGIN
    joining_user := auth.uid();
    IF joining_user IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    code := NULLIF(TRIM(invite_text), '');
    IF code IS NULL THEN
        RAISE EXCEPTION 'Invite code is required';
    END IF;

    IF code ~ '[?&](code|invite)=' THEN
        code := regexp_replace(code, '^.*[?&](code|invite)=', '');
        code := regexp_replace(code, '&.*$', '');
    ELSE
        code := regexp_replace(code, '[?#].*$', '');
        code := regexp_replace(code, '^.*[/]', '');
    END IF;

    code := NULLIF(TRIM(code), '');
    IF code IS NULL THEN
        RAISE EXCEPTION 'Invite code is required';
    END IF;

    SELECT *
    INTO room_record
    FROM public.chat_rooms
    WHERE invite_hash = code OR id::TEXT = code
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Room not found';
    END IF;

    IF room_record.school_id IS NOT NULL
       AND NOT public.is_school_member(room_record.school_id, joining_user) THEN
        RAISE EXCEPTION 'Join the school before joining this room';
    END IF;

    INSERT INTO public.chat_participants (
        room_id,
        user_id,
        joined_at,
        last_read_at,
        notifications_enabled,
        role
    )
    VALUES (room_record.id, joining_user, NOW(), NOW(), TRUE, 'member')
    ON CONFLICT (room_id, user_id)
    DO UPDATE SET notifications_enabled = TRUE;

    RETURN QUERY
    SELECT *
    FROM public.chat_rooms
    WHERE id = room_record.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.join_chat_room(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.join_school(invite_text TEXT)
RETURNS SETOF public.school_memberships
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    normalized_code TEXT;
    invite_record public.school_invites%ROWTYPE;
    joining_user UUID;
BEGIN
    joining_user := auth.uid();
    IF joining_user IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    normalized_code := upper(NULLIF(TRIM(invite_text), ''));
    IF normalized_code IS NULL THEN
        RAISE EXCEPTION 'School code is required';
    END IF;

    SELECT *
    INTO invite_record
    FROM public.school_invites
    WHERE upper(code) = normalized_code
      AND active = TRUE
      AND (expires_at IS NULL OR expires_at > NOW())
      AND (max_uses IS NULL OR use_count < max_uses)
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid or expired school code';
    END IF;

    INSERT INTO public.school_memberships (school_id, user_id, role, active, joined_at)
    VALUES (invite_record.school_id, joining_user, invite_record.role, TRUE, NOW())
    ON CONFLICT (school_id, user_id)
    DO UPDATE SET active = TRUE, role = EXCLUDED.role;

    UPDATE public.school_invites
    SET
        use_count = use_count + 1,
        active = CASE
            WHEN max_uses IS NOT NULL AND use_count + 1 >= max_uses THEN FALSE
            ELSE active
        END
    WHERE id = invite_record.id;

    RETURN QUERY
    SELECT *
    FROM public.school_memberships
    WHERE school_id = invite_record.school_id
      AND user_id = joining_user;
END;
$$;

GRANT EXECUTE ON FUNCTION public.join_school(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.can_manage_chat_room(room_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.chat_rooms
        WHERE id = room_uuid
          AND public.has_school_role(school_id, user_uuid, ARRAY['school_director', 'hq_director'])
    );
$$;

CREATE OR REPLACE FUNCTION public.is_notification_recipient(notification_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.notification_recipients
        WHERE notification_id = notification_uuid
          AND user_id = user_uuid
    );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_notification(notification_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.notifications
        WHERE id = notification_uuid
          AND public.has_school_role(school_id, user_uuid, ARRAY['school_director', 'hq_director'])
    );
$$;

CREATE OR REPLACE FUNCTION public.can_create_notification_recipient(notification_uuid UUID, recipient_uuid UUID, actor_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.notifications
        WHERE id = notification_uuid
          AND public.has_school_role(school_id, actor_uuid, ARRAY['teacher', 'school_director', 'hq_director'])
          AND public.is_school_member(school_id, recipient_uuid)
    );
$$;

CREATE OR REPLACE FUNCTION public.is_child_guardian(child_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.child_guardians
        WHERE child_id = child_uuid
          AND guardian_id = user_uuid
    );
$$;

CREATE OR REPLACE FUNCTION public.can_staff_access_child(child_uuid UUID, user_uuid UUID, allowed_roles TEXT[])
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.children
        WHERE id = child_uuid
          AND public.has_school_role(school_id, user_uuid, allowed_roles)
    );
$$;

CREATE OR REPLACE FUNCTION public.is_paperwork_assignment_recipient(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.paperwork_assignment_recipients
        WHERE assignment_id = assignment_uuid
          AND parent_id = user_uuid
    );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_paperwork_assignment(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.paperwork_assignments
        WHERE id = assignment_uuid
          AND public.has_school_role(school_id, user_uuid, ARRAY['school_director', 'hq_director'])
    );
$$;

CREATE OR REPLACE FUNCTION public.can_submit_paperwork_assignment(assignment_uuid UUID, school_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.paperwork_assignments
        JOIN public.paperwork_assignment_recipients
          ON paperwork_assignment_recipients.assignment_id = paperwork_assignments.id
        WHERE paperwork_assignments.id = assignment_uuid
          AND paperwork_assignments.school_id = school_uuid
          AND paperwork_assignment_recipients.parent_id = user_uuid
    );
$$;

CREATE OR REPLACE FUNCTION public.is_training_assignment_recipient(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.training_assignment_recipients
        WHERE assignment_id = assignment_uuid
          AND teacher_id = user_uuid
    );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_training_assignment(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.training_assignments
        WHERE id = assignment_uuid
          AND public.has_school_role(school_id, user_uuid, ARRAY['school_director', 'hq_director'])
    );
$$;

CREATE OR REPLACE FUNCTION public.can_submit_training_assignment(assignment_uuid UUID, school_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.training_assignments
        JOIN public.training_assignment_recipients
          ON training_assignment_recipients.assignment_id = training_assignments.id
        WHERE training_assignments.id = assignment_uuid
          AND training_assignments.school_id = school_uuid
          AND training_assignment_recipients.teacher_id = user_uuid
    );
$$;

GRANT EXECUTE ON FUNCTION public.can_manage_chat_room(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_notification_recipient(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_notification(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_create_notification_recipient(UUID, UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_child_guardian(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_staff_access_child(UUID, UUID, TEXT[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_paperwork_assignment_recipient(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_paperwork_assignment(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_submit_paperwork_assignment(UUID, UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_training_assignment_recipient(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_training_assignment(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_submit_training_assignment(UUID, UUID, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.set_message_school_id()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    SELECT school_id
    INTO NEW.school_id
    FROM public.chat_rooms
    WHERE id = NEW.room_id;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS set_message_school_id_trigger ON messages;
CREATE TRIGGER set_message_school_id_trigger
    BEFORE INSERT OR UPDATE OF room_id ON messages
    FOR EACH ROW EXECUTE FUNCTION public.set_message_school_id();

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE chat_rooms;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE chat_participants;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE messages;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE newsletters;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE school_events;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE school_event_invites;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE notifications;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE chat_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE schools ENABLE ROW LEVEL SECURITY;
ALTER TABLE school_memberships ENABLE ROW LEVEL SECURITY;
ALTER TABLE school_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE newsletters ENABLE ROW LEVEL SECURITY;
ALTER TABLE school_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE school_event_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE notification_recipients ENABLE ROW LEVEL SECURITY;
ALTER TABLE children ENABLE ROW LEVEL SECURITY;
ALTER TABLE child_guardians ENABLE ROW LEVEL SECURITY;
ALTER TABLE child_attendance ENABLE ROW LEVEL SECURITY;
ALTER TABLE child_activity_logs ENABLE ROW LEVEL SECURITY;
ALTER TABLE paperwork_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE paperwork_assignment_recipients ENABLE ROW LEVEL SECURITY;
ALTER TABLE paperwork_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE curriculum_resources ENABLE ROW LEVEL SECURITY;
ALTER TABLE training_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE training_assignment_recipients ENABLE ROW LEVEL SECURITY;
ALTER TABLE training_submissions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "School members can view schools" ON schools;
DROP POLICY IF EXISTS "HQ directors can manage schools" ON schools;
DROP POLICY IF EXISTS "Users can view own memberships" ON school_memberships;
DROP POLICY IF EXISTS "Directors can view school memberships" ON school_memberships;
DROP POLICY IF EXISTS "Directors can manage memberships" ON school_memberships;
DROP POLICY IF EXISTS "Teachers can view parent memberships" ON school_memberships;
DROP POLICY IF EXISTS "Directors can view invites" ON school_invites;
DROP POLICY IF EXISTS "Directors can create invites" ON school_invites;
DROP POLICY IF EXISTS "Directors can update invites" ON school_invites;

CREATE POLICY "School members can view schools"
    ON schools FOR SELECT
    USING (public.is_school_member(id, auth.uid()));

CREATE POLICY "HQ directors can manage schools"
    ON schools FOR ALL
    USING (public.is_hq_director(auth.uid()))
    WITH CHECK (public.is_hq_director(auth.uid()));

CREATE POLICY "Users can view own memberships"
    ON school_memberships FOR SELECT
    USING (
        user_id = auth.uid()
        OR public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
    );

CREATE POLICY "Teachers can view parent memberships"
    ON school_memberships FOR SELECT
    USING (
        role = 'parent'
        AND public.has_school_role(school_id, auth.uid(), ARRAY['teacher'])
    );

CREATE POLICY "Directors can manage memberships"
    ON school_memberships FOR ALL
    USING (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']))
    WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']));

CREATE POLICY "Directors can view invites"
    ON school_invites FOR SELECT
    USING (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']));

CREATE POLICY "Directors can create invites"
    ON school_invites FOR INSERT
    WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']));

CREATE POLICY "Directors can update invites"
    ON school_invites FOR UPDATE
    USING (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']))
    WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']));

DROP POLICY IF EXISTS "Users can view rooms they are in" ON chat_rooms;
DROP POLICY IF EXISTS "Authenticated users can create rooms" ON chat_rooms;
DROP POLICY IF EXISTS "Room members can update rooms" ON chat_rooms;
DROP POLICY IF EXISTS "Room owners can delete rooms" ON chat_rooms;

CREATE POLICY "Users can view rooms they are in"
    ON chat_rooms FOR SELECT
    USING (
        public.is_chat_room_member(id, auth.uid())
        OR public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
    );

CREATE POLICY "Authenticated users can create rooms"
    ON chat_rooms FOR INSERT
    WITH CHECK (
        auth.uid() IS NOT NULL
        AND (created_by IS NULL OR created_by = auth.uid())
        AND public.is_school_member(school_id, auth.uid())
    );

CREATE POLICY "Room members can update rooms"
    ON chat_rooms FOR UPDATE
    USING (
        public.is_chat_room_member(id, auth.uid())
        OR public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
    )
    WITH CHECK (
        public.is_chat_room_member(id, auth.uid())
        OR public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
    );

CREATE POLICY "Room owners can delete rooms"
    ON chat_rooms FOR DELETE
    USING (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']));

DROP POLICY IF EXISTS "Users can view participants in their rooms" ON chat_participants;
DROP POLICY IF EXISTS "Users can insert themselves" ON chat_participants;
DROP POLICY IF EXISTS "Room members can add participants" ON chat_participants;
DROP POLICY IF EXISTS "Users and owners can update participants" ON chat_participants;
DROP POLICY IF EXISTS "Users and owners can remove participants" ON chat_participants;

CREATE POLICY "Users can view participants in their rooms"
    ON chat_participants FOR SELECT
    USING (
        public.is_chat_room_member(room_id, auth.uid())
        OR public.can_manage_chat_room(room_id, auth.uid())
    );

CREATE POLICY "Room members can add participants"
    ON chat_participants FOR INSERT
    WITH CHECK (
        auth.uid() IS NOT NULL
        AND (
            user_id = auth.uid()
            OR public.is_chat_room_member(room_id, auth.uid())
        )
    );

CREATE POLICY "Users and owners can update participants"
    ON chat_participants FOR UPDATE
    USING (
        user_id = auth.uid()
        OR public.is_chat_room_owner(room_id, auth.uid())
    )
    WITH CHECK (
        user_id = auth.uid()
        OR public.is_chat_room_owner(room_id, auth.uid())
    );

CREATE POLICY "Users and owners can remove participants"
    ON chat_participants FOR DELETE
    USING (
        user_id = auth.uid()
        OR public.is_chat_room_owner(room_id, auth.uid())
    );

DROP POLICY IF EXISTS "Authenticated users can view profiles" ON profiles;
DROP POLICY IF EXISTS "Users can insert own profile" ON profiles;
DROP POLICY IF EXISTS "Users can update own profile" ON profiles;

CREATE POLICY "Authenticated users can view profiles"
    ON profiles FOR SELECT
    USING (auth.uid() IS NOT NULL);

CREATE POLICY "Users can insert own profile"
    ON profiles FOR INSERT
    WITH CHECK (id = auth.uid());

CREATE POLICY "Users can update own profile"
    ON profiles FOR UPDATE
    USING (id = auth.uid())
    WITH CHECK (id = auth.uid());

DROP POLICY IF EXISTS "Users can view messages in their rooms" ON messages;
DROP POLICY IF EXISTS "Users can insert messages in their rooms" ON messages;
DROP POLICY IF EXISTS "Users can update their own messages" ON messages;
DROP POLICY IF EXISTS "Users can delete their own messages" ON messages;

CREATE POLICY "Users can view messages in their rooms"
    ON messages FOR SELECT
    USING (
        public.is_chat_room_member(room_id, auth.uid())
        OR public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
    );

CREATE POLICY "Users can insert messages in their rooms"
    ON messages FOR INSERT
    WITH CHECK (
        auth.uid() = sender_id
        AND public.is_chat_room_member(room_id, auth.uid())
        AND public.is_school_member(school_id, auth.uid())
    );

CREATE POLICY "Users can update their own messages"
    ON messages FOR UPDATE
    USING (
        auth.uid() = sender_id
        AND public.is_chat_room_member(room_id, auth.uid())
        AND public.is_school_member(school_id, auth.uid())
    )
    WITH CHECK (
        auth.uid() = sender_id
        AND public.is_chat_room_member(room_id, auth.uid())
        AND public.is_school_member(school_id, auth.uid())
    );

CREATE POLICY "Users can delete their own messages"
    ON messages FOR DELETE
    USING (
        auth.uid() = sender_id
        AND public.is_chat_room_member(room_id, auth.uid())
    );

DROP POLICY IF EXISTS "School members can view newsletters" ON newsletters;
DROP POLICY IF EXISTS "Directors can manage newsletters" ON newsletters;
DROP POLICY IF EXISTS "School members can view events" ON school_events;
DROP POLICY IF EXISTS "Teachers and directors can manage events" ON school_events;
DROP POLICY IF EXISTS "Users can view event invites" ON school_event_invites;
DROP POLICY IF EXISTS "Teachers and directors can manage event invites" ON school_event_invites;
DROP POLICY IF EXISTS "Users can view received notifications" ON notifications;
DROP POLICY IF EXISTS "School staff can create notifications" ON notifications;
DROP POLICY IF EXISTS "Users can view notification recipients" ON notification_recipients;
DROP POLICY IF EXISTS "Users can update own notification receipts" ON notification_recipients;
DROP POLICY IF EXISTS "School staff can create notification recipients" ON notification_recipients;

CREATE POLICY "School members can view newsletters"
    ON newsletters FOR SELECT
    USING (public.is_school_member(school_id, auth.uid()));

CREATE POLICY "Directors can manage newsletters"
    ON newsletters FOR ALL
    USING (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']))
    WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']));

CREATE POLICY "School members can view events"
    ON school_events FOR SELECT
    USING (public.is_school_member(school_id, auth.uid()));

CREATE POLICY "Teachers and directors can manage events"
    ON school_events FOR ALL
    USING (public.has_school_role(school_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director']))
    WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director']));

CREATE POLICY "Users can view event invites"
    ON school_event_invites FOR SELECT
    USING (
        user_id = auth.uid()
        OR EXISTS (
            SELECT 1
            FROM school_events
            WHERE school_events.id = school_event_invites.event_id
              AND public.has_school_role(school_events.school_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director'])
        )
    );

CREATE POLICY "Teachers and directors can manage event invites"
    ON school_event_invites FOR ALL
    USING (
        EXISTS (
            SELECT 1
            FROM school_events
            WHERE school_events.id = school_event_invites.event_id
              AND public.has_school_role(school_events.school_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director'])
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM school_events
            WHERE school_events.id = school_event_invites.event_id
              AND public.has_school_role(school_events.school_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director'])
              AND public.is_school_member(school_events.school_id, school_event_invites.user_id)
        )
    );

CREATE POLICY "Users can view received notifications"
    ON notifications FOR SELECT
    USING (
        public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
        OR public.is_notification_recipient(id, auth.uid())
    );

CREATE POLICY "School staff can create notifications"
    ON notifications FOR INSERT
    WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director']));

CREATE POLICY "Users can view notification recipients"
    ON notification_recipients FOR SELECT
    USING (
        user_id = auth.uid()
        OR public.can_manage_notification(notification_id, auth.uid())
    );

CREATE POLICY "Users can update own notification receipts"
    ON notification_recipients FOR UPDATE
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

CREATE POLICY "School staff can create notification recipients"
    ON notification_recipients FOR INSERT
    WITH CHECK (public.can_create_notification_recipient(notification_id, user_id, auth.uid()));

DROP POLICY IF EXISTS "Users can view scoped children" ON children;
DROP POLICY IF EXISTS "Teachers and directors can manage children" ON children;
DROP POLICY IF EXISTS "Users can view child guardians" ON child_guardians;
DROP POLICY IF EXISTS "Directors can manage child guardians" ON child_guardians;
DROP POLICY IF EXISTS "Users can view child attendance" ON child_attendance;
DROP POLICY IF EXISTS "Teachers and directors can manage child attendance" ON child_attendance;
DROP POLICY IF EXISTS "Users can view child activity logs" ON child_activity_logs;
DROP POLICY IF EXISTS "Teachers and directors can create child activity logs" ON child_activity_logs;

CREATE POLICY "Users can view scoped children"
    ON children FOR SELECT
    USING (
        public.has_school_role(school_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director'])
        OR public.is_child_guardian(id, auth.uid())
    );

CREATE POLICY "Teachers and directors can manage children"
    ON children FOR ALL
    USING (public.has_school_role(school_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director']))
    WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director']));

CREATE POLICY "Users can view child guardians"
    ON child_guardians FOR SELECT
    USING (
        guardian_id = auth.uid()
        OR public.can_staff_access_child(child_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director'])
    );

CREATE POLICY "Directors can manage child guardians"
    ON child_guardians FOR ALL
    USING (public.can_staff_access_child(child_id, auth.uid(), ARRAY['school_director', 'hq_director']))
    WITH CHECK (public.can_staff_access_child(child_id, auth.uid(), ARRAY['school_director', 'hq_director']));

CREATE POLICY "Users can view child attendance"
    ON child_attendance FOR SELECT
    USING (
        public.has_school_role(school_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director'])
        OR public.is_child_guardian(child_id, auth.uid())
    );

CREATE POLICY "Teachers and directors can manage child attendance"
    ON child_attendance FOR ALL
    USING (public.has_school_role(school_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director']))
    WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director']));

CREATE POLICY "Users can view child activity logs"
    ON child_activity_logs FOR SELECT
    USING (
        public.has_school_role(school_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director'])
        OR public.is_child_guardian(child_id, auth.uid())
    );

CREATE POLICY "Teachers and directors can create child activity logs"
    ON child_activity_logs FOR INSERT
    WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director']));

DROP POLICY IF EXISTS "Users can view paperwork assignments" ON paperwork_assignments;
DROP POLICY IF EXISTS "Directors can manage paperwork assignments" ON paperwork_assignments;
DROP POLICY IF EXISTS "Users can view paperwork recipients" ON paperwork_assignment_recipients;
DROP POLICY IF EXISTS "Directors can manage paperwork recipients" ON paperwork_assignment_recipients;
DROP POLICY IF EXISTS "Users can view paperwork submissions" ON paperwork_submissions;
DROP POLICY IF EXISTS "Parents can create paperwork submissions" ON paperwork_submissions;
DROP POLICY IF EXISTS "Directors can review paperwork submissions" ON paperwork_submissions;

CREATE POLICY "Users can view paperwork assignments"
    ON paperwork_assignments FOR SELECT
    USING (
        public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
        OR public.is_paperwork_assignment_recipient(id, auth.uid())
    );

CREATE POLICY "Directors can manage paperwork assignments"
    ON paperwork_assignments FOR ALL
    USING (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']))
    WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']));

CREATE POLICY "Users can view paperwork recipients"
    ON paperwork_assignment_recipients FOR SELECT
    USING (
        parent_id = auth.uid()
        OR public.can_manage_paperwork_assignment(assignment_id, auth.uid())
    );

CREATE POLICY "Directors can manage paperwork recipients"
    ON paperwork_assignment_recipients FOR ALL
    USING (public.can_manage_paperwork_assignment(assignment_id, auth.uid()))
    WITH CHECK (public.can_manage_paperwork_assignment(assignment_id, auth.uid()));

CREATE POLICY "Users can view paperwork submissions"
    ON paperwork_submissions FOR SELECT
    USING (
        submitted_by = auth.uid()
        OR public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
    );

CREATE POLICY "Parents can create paperwork submissions"
    ON paperwork_submissions FOR INSERT
    WITH CHECK (
        submitted_by = auth.uid()
        AND public.has_school_role(school_id, auth.uid(), ARRAY['parent'])
        AND public.can_submit_paperwork_assignment(assignment_id, school_id, auth.uid())
    );

CREATE POLICY "Directors can review paperwork submissions"
    ON paperwork_submissions FOR UPDATE
    USING (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']))
    WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']));

DROP POLICY IF EXISTS "Teachers and directors can view curriculum" ON curriculum_resources;
DROP POLICY IF EXISTS "Directors can manage curriculum" ON curriculum_resources;
DROP POLICY IF EXISTS "Users can view training assignments" ON training_assignments;
DROP POLICY IF EXISTS "Directors can manage training assignments" ON training_assignments;
DROP POLICY IF EXISTS "Users can view training recipients" ON training_assignment_recipients;
DROP POLICY IF EXISTS "Directors can manage training recipients" ON training_assignment_recipients;
DROP POLICY IF EXISTS "Users can view training submissions" ON training_submissions;
DROP POLICY IF EXISTS "Teachers can create training submissions" ON training_submissions;
DROP POLICY IF EXISTS "Directors can review training submissions" ON training_submissions;

CREATE POLICY "Teachers and directors can view curriculum"
    ON curriculum_resources FOR SELECT
    USING (public.has_school_role(school_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director']));

CREATE POLICY "Directors can manage curriculum"
    ON curriculum_resources FOR ALL
    USING (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']))
    WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']));

CREATE POLICY "Users can view training assignments"
    ON training_assignments FOR SELECT
    USING (
        public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
        OR public.is_training_assignment_recipient(id, auth.uid())
    );

CREATE POLICY "Directors can manage training assignments"
    ON training_assignments FOR ALL
    USING (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']))
    WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']));

CREATE POLICY "Users can view training recipients"
    ON training_assignment_recipients FOR SELECT
    USING (
        teacher_id = auth.uid()
        OR public.can_manage_training_assignment(assignment_id, auth.uid())
    );

CREATE POLICY "Directors can manage training recipients"
    ON training_assignment_recipients FOR ALL
    USING (public.can_manage_training_assignment(assignment_id, auth.uid()))
    WITH CHECK (public.can_manage_training_assignment(assignment_id, auth.uid()));

CREATE POLICY "Users can view training submissions"
    ON training_submissions FOR SELECT
    USING (
        submitted_by = auth.uid()
        OR public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
    );

CREATE POLICY "Teachers can create training submissions"
    ON training_submissions FOR INSERT
    WITH CHECK (
        submitted_by = auth.uid()
        AND public.has_school_role(school_id, auth.uid(), ARRAY['teacher'])
        AND public.can_submit_training_assignment(assignment_id, school_id, auth.uid())
    );

CREATE POLICY "Directors can review training submissions"
    ON training_submissions FOR UPDATE
    USING (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']))
    WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']));

CREATE OR REPLACE FUNCTION public.can_access_school_private_file(object_name TEXT, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    parts TEXT[];
    school_uuid UUID;
    category TEXT;
    record_uuid UUID;
    owner_uuid UUID;
BEGIN
    IF object_name IS NULL OR user_uuid IS NULL THEN
        RETURN FALSE;
    END IF;

    parts := string_to_array(object_name, '/');
    IF array_length(parts, 1) < 4 OR parts[1] <> 'schools' THEN
        RETURN FALSE;
    END IF;

    school_uuid := parts[2]::UUID;
    category := parts[3];

    IF public.has_school_role(school_uuid, user_uuid, ARRAY['school_director', 'hq_director']) THEN
        RETURN TRUE;
    END IF;

    IF category = 'paperwork_assignments' THEN
        record_uuid := parts[4]::UUID;
        RETURN EXISTS (
            SELECT 1
            FROM paperwork_assignment_recipients
            WHERE assignment_id = record_uuid
              AND parent_id = user_uuid
        );
    ELSIF category = 'paperwork_submissions' THEN
        owner_uuid := parts[4]::UUID;
        RETURN owner_uuid = user_uuid
            AND public.has_school_role(school_uuid, user_uuid, ARRAY['parent']);
    ELSIF category IN ('curriculum_resources', 'training_assignments') THEN
        RETURN public.has_school_role(school_uuid, user_uuid, ARRAY['teacher']);
    ELSIF category = 'training_submissions' THEN
        owner_uuid := parts[4]::UUID;
        RETURN owner_uuid = user_uuid
            AND public.has_school_role(school_uuid, user_uuid, ARRAY['teacher']);
    END IF;

    RETURN FALSE;
EXCEPTION WHEN invalid_text_representation THEN
    RETURN FALSE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.can_access_school_private_file(TEXT, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.can_write_school_private_file(object_name TEXT, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    parts TEXT[];
    school_uuid UUID;
    category TEXT;
    owner_uuid UUID;
BEGIN
    IF object_name IS NULL OR user_uuid IS NULL THEN
        RETURN FALSE;
    END IF;

    parts := string_to_array(object_name, '/');
    IF array_length(parts, 1) < 4 OR parts[1] <> 'schools' THEN
        RETURN FALSE;
    END IF;

    school_uuid := parts[2]::UUID;
    category := parts[3];

    IF category IN ('paperwork_assignments', 'curriculum_resources', 'training_assignments') THEN
        RETURN public.has_school_role(school_uuid, user_uuid, ARRAY['school_director', 'hq_director']);
    END IF;

    IF array_length(parts, 1) < 5 THEN
        RETURN FALSE;
    END IF;

    owner_uuid := parts[4]::UUID;

    IF category = 'paperwork_submissions' THEN
        RETURN owner_uuid = user_uuid
            AND public.has_school_role(school_uuid, user_uuid, ARRAY['parent']);
    ELSIF category = 'training_submissions' THEN
        RETURN owner_uuid = user_uuid
            AND public.has_school_role(school_uuid, user_uuid, ARRAY['teacher']);
    END IF;

    RETURN FALSE;
EXCEPTION WHEN invalid_text_representation THEN
    RETURN FALSE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.can_write_school_private_file(TEXT, UUID) TO authenticated;

INSERT INTO storage.buckets (id, name, public)
VALUES ('chat_attachments', 'chat_attachments', TRUE)
ON CONFLICT (id) DO UPDATE SET public = TRUE;

INSERT INTO storage.buckets (id, name, public)
VALUES ('school_private_files', 'school_private_files', FALSE)
ON CONFLICT (id) DO UPDATE SET public = FALSE;

DROP POLICY IF EXISTS "Public Access" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can update uploads" ON storage.objects;
DROP POLICY IF EXISTS "School private files are restricted" ON storage.objects;
DROP POLICY IF EXISTS "School members can upload private files" ON storage.objects;
DROP POLICY IF EXISTS "School members can update private files" ON storage.objects;

CREATE POLICY "Public Access"
    ON storage.objects FOR SELECT
    USING (bucket_id = 'chat_attachments');

CREATE POLICY "Authenticated users can upload"
    ON storage.objects FOR INSERT
    WITH CHECK (bucket_id = 'chat_attachments' AND auth.uid() IS NOT NULL);

CREATE POLICY "Authenticated users can update uploads"
    ON storage.objects FOR UPDATE
    USING (bucket_id = 'chat_attachments' AND auth.uid() IS NOT NULL)
    WITH CHECK (bucket_id = 'chat_attachments' AND auth.uid() IS NOT NULL);

CREATE POLICY "School private files are restricted"
    ON storage.objects FOR SELECT
    USING (
        bucket_id = 'school_private_files'
        AND public.can_access_school_private_file(name, auth.uid())
    );

CREATE POLICY "School members can upload private files"
    ON storage.objects FOR INSERT
    WITH CHECK (
        bucket_id = 'school_private_files'
        AND public.can_write_school_private_file(name, auth.uid())
    );

CREATE POLICY "School members can update private files"
    ON storage.objects FOR UPDATE
    USING (
        bucket_id = 'school_private_files'
        AND public.can_write_school_private_file(name, auth.uid())
    )
    WITH CHECK (
        bucket_id = 'school_private_files'
        AND public.can_write_school_private_file(name, auth.uid())
    );

-- Backfill profiles for existing users.
INSERT INTO profiles (id, display_name, avatar_url)
SELECT
    id,
    COALESCE(
        NULLIF(TRIM(raw_user_meta_data->>'display_name'), ''),
        NULLIF(TRIM(CONCAT_WS(
            ' ',
            NULLIF(raw_user_meta_data->>'first_name', ''),
            NULLIF(raw_user_meta_data->>'last_name', '')
        )), ''),
        split_part(email, '@', 1),
        'Firefly User'
    ),
    NULLIF(raw_user_meta_data->>'avatar_url', '')
FROM auth.users
ON CONFLICT (id) DO NOTHING;

-- Backfill existing chat data into a default school so older rooms remain reachable.
INSERT INTO schools (id, name, description)
VALUES (
    '00000000-0000-0000-0000-000000000001'::UUID,
    'Default School',
    'Migrated school for existing FireflyFM data.'
)
ON CONFLICT (id) DO NOTHING;

UPDATE chat_rooms
SET school_id = '00000000-0000-0000-0000-000000000001'::UUID
WHERE school_id IS NULL;

UPDATE chat_rooms
SET room_type = 'public'
WHERE room_type IS NULL;

UPDATE messages
SET school_id = chat_rooms.school_id
FROM chat_rooms
WHERE messages.room_id = chat_rooms.id
  AND messages.school_id IS NULL;

INSERT INTO school_memberships (school_id, user_id, role, active, joined_at)
SELECT DISTINCT
    '00000000-0000-0000-0000-000000000001'::UUID,
    chat_participants.user_id,
    CASE
        WHEN chat_participants.role = 'owner' THEN 'school_director'
        WHEN auth.users.raw_user_meta_data->>'role' = 'teacher' THEN 'teacher'
        ELSE 'parent'
    END,
    TRUE,
    COALESCE(chat_participants.joined_at, NOW())
FROM chat_participants
JOIN auth.users ON auth.users.id = chat_participants.user_id
ON CONFLICT (school_id, user_id) DO NOTHING;

-- Repair rooms created before participant insertion succeeded.
INSERT INTO chat_participants (room_id, user_id, joined_at, last_read_at, notifications_enabled, role)
SELECT id, created_by, NOW(), NOW(), TRUE, 'owner'
FROM chat_rooms
WHERE created_by IS NOT NULL
  AND NOT EXISTS (
      SELECT 1
      FROM chat_participants
      WHERE chat_participants.room_id = chat_rooms.id
  )
ON CONFLICT (room_id, user_id) DO NOTHING;

-- Make newly created/updated RPC functions visible to PostgREST immediately.
NOTIFY pgrst, 'reload schema';
