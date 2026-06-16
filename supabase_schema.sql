-- Create chat_rooms table
CREATE TABLE chat_rooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name TEXT NOT NULL,
    invite_hash TEXT UNIQUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Create chat_participants table
CREATE TABLE chat_participants (
    room_id UUID REFERENCES chat_rooms(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    joined_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (room_id, user_id)
);

-- Create messages table
CREATE TABLE messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID REFERENCES chat_rooms(id) ON DELETE CASCADE,
    sender_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    text TEXT,
    media_url TEXT,
    file_url TEXT,
    audio_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

-- Enable Realtime for the required tables
alter publication supabase_realtime add table chat_rooms;
alter publication supabase_realtime add table messages;

-- Setup Row Level Security (RLS)
-- Enable RLS
ALTER TABLE chat_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE messages ENABLE ROW LEVEL SECURITY;

-- Policies for chat_rooms
CREATE POLICY "Users can view rooms they are in"
    ON chat_rooms FOR SELECT
    USING (id IN (SELECT room_id FROM chat_participants WHERE user_id = auth.uid()));

CREATE POLICY "Authenticated users can create rooms"
    ON chat_rooms FOR INSERT
    WITH CHECK (auth.uid() IS NOT NULL);

-- Policies for chat_participants
CREATE POLICY "Users can view participants in their rooms"
    ON chat_participants FOR SELECT
    USING (room_id IN (SELECT room_id FROM chat_participants WHERE user_id = auth.uid()));

CREATE POLICY "Users can insert themselves"
    ON chat_participants FOR INSERT
    WITH CHECK (auth.uid() = user_id);

-- Policies for messages
CREATE POLICY "Users can view messages in their rooms"
    ON messages FOR SELECT
    USING (room_id IN (SELECT room_id FROM chat_participants WHERE user_id = auth.uid()));

CREATE POLICY "Users can insert messages in their rooms"
    ON messages FOR INSERT
    WITH CHECK (auth.uid() = sender_id AND room_id IN (SELECT room_id FROM chat_participants WHERE user_id = auth.uid()));

-- Create storage bucket for chat attachments
insert into storage.buckets (id, name, public) values ('chat_attachments', 'chat_attachments', true);

-- Storage policies
CREATE POLICY "Public Access"
    ON storage.objects FOR SELECT
    USING (bucket_id = 'chat_attachments');

CREATE POLICY "Authenticated users can upload"
    ON storage.objects FOR INSERT
    WITH CHECK (bucket_id = 'chat_attachments' AND auth.uid() IS NOT NULL);

-- NEW ADDITIONS FOR CHAT ROOM CREATION
ALTER TABLE chat_rooms 
ADD COLUMN description TEXT,
ADD COLUMN profile_image_url TEXT;

-- NEW POLICIES FOR MESSAGES
CREATE POLICY "Users can update their own messages"
    ON messages FOR UPDATE
    USING (auth.uid() = sender_id)
    WITH CHECK (auth.uid() = sender_id);

CREATE POLICY "Users can delete their own messages"
    ON messages FOR DELETE
    USING (auth.uid() = sender_id);

-- NEW ADDITIONS FOR EDITING AND SOFT DELETES
ALTER TABLE messages ADD COLUMN updated_at TIMESTAMPTZ;
ALTER TABLE messages ADD COLUMN is_deleted BOOLEAN DEFAULT FALSE;


