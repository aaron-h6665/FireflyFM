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

CREATE POLICY "Public Access"
    ON storage.objects FOR SELECT
    USING (bucket_id = 'chat_attachments');

CREATE POLICY "Authenticated users can upload"
    ON storage.objects FOR INSERT
    WITH CHECK (bucket_id = 'chat_attachments' AND auth.uid() IS NOT NULL);

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
