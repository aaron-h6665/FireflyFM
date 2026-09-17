-- School directors can continue to manage existing school custom chats, but
-- only HQ directors may create new chats through a client-facing RPC.
REVOKE ALL ON FUNCTION public.create_director_chat_room(UUID, TEXT, TEXT, TEXT, UUID[], TEXT)
FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT 20260917180000::BIGINT;
$$;

NOTIFY pgrst, 'reload schema';
