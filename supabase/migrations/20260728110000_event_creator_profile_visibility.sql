-- School members need the event creator's profile to attribute calendar entries,
-- including events created by an HQ director without a school membership row.
BEGIN;

DROP POLICY IF EXISTS "Users can view same-school adult profiles" ON public.profiles;
CREATE POLICY "Users can view same-school adult profiles"
    ON public.profiles FOR SELECT
    USING (
        id = auth.uid()
        OR public.is_hq_director(auth.uid())
        OR EXISTS (
            SELECT 1
            FROM public.school_memberships mine
            JOIN public.school_memberships theirs ON theirs.school_id = mine.school_id
            WHERE mine.user_id = auth.uid() AND mine.active = TRUE
              AND theirs.user_id = profiles.id AND theirs.active = TRUE
              AND theirs.role IN ('parent', 'teacher', 'school_director', 'hq_director')
        )
        OR EXISTS (
            SELECT 1
            FROM public.school_events event
            WHERE event.created_by = profiles.id
              AND public.is_school_member(event.school_id, auth.uid())
        )
    );

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260728110000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
COMMIT;
