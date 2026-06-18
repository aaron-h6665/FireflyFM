-- FireflyFM chat schema
-- Safe to run more than once in the Supabase SQL editor.

CREATE TABLE IF NOT EXISTS chat_rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    description TEXT,
    profile_image_url TEXT,
    invite_hash TEXT UNIQUE DEFAULT gen_random_uuid()::TEXT,
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

ALTER TABLE chat_rooms
    ADD COLUMN IF NOT EXISTS description TEXT,
    ADD COLUMN IF NOT EXISTS profile_image_url TEXT,
    ADD COLUMN IF NOT EXISTS invite_hash TEXT UNIQUE DEFAULT gen_random_uuid()::TEXT,
    ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

ALTER TABLE chat_participants
    ADD COLUMN IF NOT EXISTS last_read_at TIMESTAMPTZ DEFAULT NOW(),
    ADD COLUMN IF NOT EXISTS notifications_enabled BOOLEAN DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS role TEXT DEFAULT 'member';

ALTER TABLE messages
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS is_deleted BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS attachment_type TEXT,
    ADD COLUMN IF NOT EXISTS attachment_name TEXT,
    ADD COLUMN IF NOT EXISTS attachment_size INTEGER,
    ADD COLUMN IF NOT EXISTS reply_to_message_id UUID REFERENCES messages(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_chat_participants_user_id ON chat_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_chat_participants_room_id ON chat_participants(room_id);
CREATE INDEX IF NOT EXISTS idx_profiles_display_name ON profiles (lower(display_name));
CREATE INDEX IF NOT EXISTS idx_messages_room_created_at ON messages(room_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_reply_to ON messages(reply_to_message_id);

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

ALTER TABLE chat_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Users can view rooms they are in" ON chat_rooms;
DROP POLICY IF EXISTS "Authenticated users can create rooms" ON chat_rooms;
DROP POLICY IF EXISTS "Room members can update rooms" ON chat_rooms;
DROP POLICY IF EXISTS "Room owners can delete rooms" ON chat_rooms;

CREATE POLICY "Users can view rooms they are in"
    ON chat_rooms FOR SELECT
    USING (public.is_chat_room_member(id, auth.uid()));

CREATE POLICY "Authenticated users can create rooms"
    ON chat_rooms FOR INSERT
    WITH CHECK (auth.uid() IS NOT NULL AND (created_by IS NULL OR created_by = auth.uid()));

CREATE POLICY "Room members can update rooms"
    ON chat_rooms FOR UPDATE
    USING (public.is_chat_room_member(id, auth.uid()))
    WITH CHECK (public.is_chat_room_member(id, auth.uid()));

CREATE POLICY "Room owners can delete rooms"
    ON chat_rooms FOR DELETE
    USING (public.is_chat_room_owner(id, auth.uid()));

DROP POLICY IF EXISTS "Users can view participants in their rooms" ON chat_participants;
DROP POLICY IF EXISTS "Users can insert themselves" ON chat_participants;
DROP POLICY IF EXISTS "Room members can add participants" ON chat_participants;
DROP POLICY IF EXISTS "Users and owners can update participants" ON chat_participants;
DROP POLICY IF EXISTS "Users and owners can remove participants" ON chat_participants;

CREATE POLICY "Users can view participants in their rooms"
    ON chat_participants FOR SELECT
    USING (public.is_chat_room_member(room_id, auth.uid()));

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
    USING (public.is_chat_room_member(room_id, auth.uid()));

CREATE POLICY "Users can insert messages in their rooms"
    ON messages FOR INSERT
    WITH CHECK (
        auth.uid() = sender_id
        AND public.is_chat_room_member(room_id, auth.uid())
    );

CREATE POLICY "Users can update their own messages"
    ON messages FOR UPDATE
    USING (
        auth.uid() = sender_id
        AND public.is_chat_room_member(room_id, auth.uid())
    )
    WITH CHECK (
        auth.uid() = sender_id
        AND public.is_chat_room_member(room_id, auth.uid())
    );

CREATE POLICY "Users can delete their own messages"
    ON messages FOR DELETE
    USING (
        auth.uid() = sender_id
        AND public.is_chat_room_member(room_id, auth.uid())
    );

INSERT INTO storage.buckets (id, name, public)
VALUES ('chat_attachments', 'chat_attachments', TRUE)
ON CONFLICT (id) DO UPDATE SET public = TRUE;

DROP POLICY IF EXISTS "Public Access" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can update uploads" ON storage.objects;

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
