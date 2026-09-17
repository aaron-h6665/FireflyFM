-- Guardian QR attendance beta.
-- A location code is an onsite signal, not an authentication credential. The
-- authenticated guardian relationship remains the authorization boundary.

CREATE TABLE IF NOT EXISTS public.attendance_location_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    classroom_id UUID REFERENCES public.classrooms(id) ON DELETE CASCADE,
    token TEXT NOT NULL UNIQUE,
    created_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    revoked_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    revoked_at TIMESTAMPTZ,
    CHECK (length(token) = 64),
    CHECK ((revoked_at IS NULL) = (revoked_by IS NULL))
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_location_codes_active_school
    ON public.attendance_location_codes(school_id)
    WHERE classroom_id IS NULL AND revoked_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_location_codes_active_classroom
    ON public.attendance_location_codes(school_id, classroom_id)
    WHERE classroom_id IS NOT NULL AND revoked_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_attendance_location_codes_token
    ON public.attendance_location_codes(token) WHERE revoked_at IS NULL;

ALTER TABLE public.attendance_location_codes ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON TABLE public.attendance_location_codes FROM PUBLIC, anon, authenticated;

ALTER TABLE public.attendance_sessions
    ADD COLUMN IF NOT EXISTS checked_in_method TEXT,
    ADD COLUMN IF NOT EXISTS checked_out_method TEXT,
    ADD COLUMN IF NOT EXISTS checked_in_location_code_id UUID REFERENCES public.attendance_location_codes(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS checked_out_location_code_id UUID REFERENCES public.attendance_location_codes(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS checked_in_actor_role TEXT,
    ADD COLUMN IF NOT EXISTS checked_out_actor_role TEXT,
    ADD COLUMN IF NOT EXISTS checked_in_actor_name TEXT,
    ADD COLUMN IF NOT EXISTS checked_out_actor_name TEXT,
    ADD COLUMN IF NOT EXISTS checked_in_idempotency_key TEXT,
    ADD COLUMN IF NOT EXISTS checked_out_idempotency_key TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_sessions_check_in_idempotency
    ON public.attendance_sessions(school_id, checked_in_idempotency_key)
    WHERE checked_in_idempotency_key IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_sessions_check_out_idempotency
    ON public.attendance_sessions(school_id, checked_out_idempotency_key)
    WHERE checked_out_idempotency_key IS NOT NULL;

ALTER TABLE public.attendance_sessions
    DROP CONSTRAINT IF EXISTS attendance_sessions_checked_in_method_check,
    DROP CONSTRAINT IF EXISTS attendance_sessions_checked_out_method_check;
ALTER TABLE public.attendance_sessions
    ADD CONSTRAINT attendance_sessions_checked_in_method_check
        CHECK (checked_in_method IS NULL OR checked_in_method IN ('staff_manual', 'guardian_qr', 'system')),
    ADD CONSTRAINT attendance_sessions_checked_out_method_check
        CHECK (checked_out_method IS NULL OR checked_out_method IN ('staff_manual', 'guardian_qr', 'system'));

CREATE OR REPLACE FUNCTION public.record_attendance_core(
    input_child_id UUID,
    input_action TEXT,
    input_occurred_at TIMESTAMPTZ,
    input_notes TEXT,
    input_idempotency_key TEXT,
    input_actor UUID,
    input_method TEXT,
    input_location_code_id UUID,
    input_actor_role TEXT
)
RETURNS SETOF public.attendance_sessions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    child_record public.children%ROWTYPE;
    session_record public.attendance_sessions%ROWTYPE;
    guardian_ids UUID[];
    daily_summary TEXT;
    target_date DATE;
    latest_state TEXT;
    actor_name TEXT;
BEGIN
    IF input_actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    IF input_action NOT IN ('check_in', 'check_out', 'expected', 'absent', 'needs_attention') THEN
        RAISE EXCEPTION 'Invalid attendance action';
    END IF;
    IF input_method NOT IN ('staff_manual', 'guardian_qr', 'system') THEN
        RAISE EXCEPTION 'Invalid attendance method';
    END IF;
    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NULL THEN
        RAISE EXCEPTION 'An idempotency key is required';
    END IF;

    SELECT * INTO child_record FROM public.children WHERE id = input_child_id AND active = TRUE;
    IF NOT FOUND THEN RAISE EXCEPTION 'This child is unavailable'; END IF;
    SELECT NULLIF(btrim(profile.display_name), '') INTO actor_name
    FROM public.profiles profile WHERE profile.id = input_actor;

    target_date := (input_occurred_at AT TIME ZONE 'America/New_York')::DATE;
    PERFORM pg_advisory_xact_lock(hashtextextended(input_child_id::TEXT || ':attendance', 0));

    SELECT * INTO session_record
    FROM public.attendance_sessions
    WHERE school_id = child_record.school_id
      AND (
          (input_action = 'check_in' AND checked_in_idempotency_key = btrim(input_idempotency_key))
          OR (input_action = 'check_out' AND checked_out_idempotency_key = btrim(input_idempotency_key))
          OR (input_action NOT IN ('check_in', 'check_out') AND idempotency_key = btrim(input_idempotency_key))
      );
    IF session_record.id IS NOT NULL THEN
        RETURN QUERY SELECT * FROM public.attendance_sessions WHERE id = session_record.id;
        RETURN;
    END IF;

    UPDATE public.attendance_sessions
    SET state = CASE WHEN state = 'present' THEN 'checked_out' ELSE state END,
        checked_out_at = COALESCE(checked_out_at, (attendance_date + TIME '18:00') AT TIME ZONE 'America/New_York'),
        checked_out_method = COALESCE(checked_out_method, 'system'),
        checked_out_actor_role = COALESCE(checked_out_actor_role, 'system'),
        notes = COALESCE(NULLIF(btrim(COALESCE(notes, '')), '') || ' | Auto-closed prior day session', 'Auto-closed prior day session'),
        updated_at = NOW()
    WHERE child_id = input_child_id
      AND attendance_date < target_date
      AND checked_in_at IS NOT NULL
      AND checked_out_at IS NULL;

    IF input_action = 'check_in' THEN
        SELECT state INTO latest_state
        FROM public.attendance_sessions
        WHERE child_id = input_child_id AND attendance_date = target_date
        ORDER BY COALESCE(checked_in_at, created_at) DESC LIMIT 1;

        IF latest_state = 'absent' THEN
            UPDATE public.attendance_sessions
            SET state = 'checked_out', checked_out_at = input_occurred_at,
                checked_out_by = input_actor, checked_out_method = input_method,
                checked_out_location_code_id = input_location_code_id,
                checked_out_actor_role = input_actor_role, checked_out_actor_name = actor_name,
                notes = COALESCE(NULLIF(btrim(COALESCE(notes, '')), '') || ' | Closed upon check-in from absence', 'Closed upon check-in from absence'),
                updated_at = NOW()
            WHERE child_id = input_child_id
              AND checked_in_at IS NOT NULL AND checked_out_at IS NULL;
        END IF;

        UPDATE public.attendance_sessions
        SET checked_out_at = input_occurred_at, checked_out_by = input_actor,
            checked_out_method = input_method, checked_out_location_code_id = input_location_code_id,
            checked_out_actor_role = input_actor_role, checked_out_actor_name = actor_name,
            updated_at = NOW()
        WHERE child_id = input_child_id AND state = 'absent'
          AND checked_in_at IS NOT NULL AND checked_out_at IS NULL;

        IF EXISTS (
            SELECT 1 FROM public.attendance_sessions
            WHERE child_id = input_child_id AND checked_in_at IS NOT NULL
              AND checked_out_at IS NULL AND state = 'present'
        ) THEN RAISE EXCEPTION 'This child already has an open attendance session'; END IF;

        INSERT INTO public.attendance_sessions (
            school_id, child_id, attendance_date, state, checked_in_at,
            checked_in_by, checked_in_method, checked_in_location_code_id,
            checked_in_actor_role, checked_in_actor_name, checked_in_idempotency_key,
            notes, idempotency_key
        ) VALUES (
            child_record.school_id, input_child_id, target_date, 'present', input_occurred_at,
            input_actor, input_method, input_location_code_id,
            input_actor_role, actor_name, btrim(input_idempotency_key),
            NULLIF(btrim(COALESCE(input_notes, '')), ''),
            btrim(input_idempotency_key)
        ) RETURNING * INTO session_record;
    ELSIF input_action = 'check_out' THEN
        SELECT * INTO session_record
        FROM public.attendance_sessions
        WHERE child_id = input_child_id AND checked_in_at IS NOT NULL AND checked_out_at IS NULL
        ORDER BY checked_in_at DESC LIMIT 1 FOR UPDATE;
        IF NOT FOUND THEN RAISE EXCEPTION 'No open attendance session exists'; END IF;
        IF input_occurred_at < session_record.checked_in_at THEN
            RAISE EXCEPTION 'Checkout cannot occur before check-in';
        END IF;
        UPDATE public.attendance_sessions
        SET state = 'checked_out', checked_out_at = input_occurred_at,
            checked_out_by = input_actor, checked_out_method = input_method,
            checked_out_location_code_id = input_location_code_id,
            checked_out_actor_role = input_actor_role, checked_out_actor_name = actor_name,
            checked_out_idempotency_key = btrim(input_idempotency_key),
            notes = COALESCE(NULLIF(btrim(COALESCE(input_notes, '')), ''), notes),
            idempotency_key = btrim(input_idempotency_key), updated_at = NOW()
        WHERE id = session_record.id RETURNING * INTO session_record;
    ELSE
        IF input_action = 'absent' THEN
            UPDATE public.attendance_sessions
            SET state = 'checked_out', checked_out_at = input_occurred_at,
                checked_out_by = input_actor, checked_out_method = input_method,
                checked_out_location_code_id = input_location_code_id,
                checked_out_actor_role = input_actor_role, checked_out_actor_name = actor_name,
                notes = COALESCE(NULLIF(btrim(COALESCE(notes, '')), '') || ' | Closed upon marking absent', 'Closed upon marking absent'),
                updated_at = NOW()
            WHERE child_id = input_child_id AND checked_in_at IS NOT NULL AND checked_out_at IS NULL;
        END IF;
        INSERT INTO public.attendance_sessions (
            school_id, child_id, attendance_date, state, notes, idempotency_key
        ) VALUES (
            child_record.school_id, input_child_id, target_date, input_action,
            NULLIF(btrim(COALESCE(input_notes, '')), ''), btrim(input_idempotency_key)
        ) RETURNING * INTO session_record;
    END IF;

    SELECT array_agg(guardian.guardian_id) INTO guardian_ids
    FROM public.child_guardians guardian
    WHERE guardian.child_id = input_child_id
      AND guardian.verification_status = 'verified' AND guardian.ended_at IS NULL;

    IF input_action IN ('check_in', 'check_out') THEN
        PERFORM public.enqueue_workflow_notification(
            child_record.school_id,
            child_record.first_name || CASE WHEN input_action = 'check_in' THEN ' checked in' ELSE ' checked out' END,
            to_char(input_occurred_at AT TIME ZONE 'America/New_York', 'Mon FMDD at FMHH12:MI AM'),
            'attendance_' || input_action, 'attendance_session', session_record.id,
            guardian_ids, 'attendance:' || input_action || ':' || btrim(input_idempotency_key),
            'routine', jsonb_build_object('type', 'attendance_session', 'id', session_record.id, 'child_id', input_child_id), input_actor
        );
        IF input_action = 'check_out' THEN
            SELECT string_agg(summary.event_count::TEXT || ' ' || replace(summary.event_type, '_', ' '), ', ' ORDER BY summary.event_type)
            INTO daily_summary
            FROM (
                SELECT event.event_type, COUNT(*) AS event_count
                FROM public.child_care_events event
                WHERE event.child_id = input_child_id AND event.visibility = 'parent'
                  AND (event.occurred_at AT TIME ZONE 'America/New_York')::DATE = session_record.attendance_date
                GROUP BY event.event_type
            ) summary;
            PERFORM public.enqueue_workflow_notification(
                child_record.school_id, child_record.first_name || '''s daily summary',
                COALESCE(daily_summary, 'No routine care updates were recorded today.'),
                'daily_care_summary', 'attendance_session', session_record.id,
                guardian_ids, 'daily-summary:' || session_record.id::TEXT,
                'routine', jsonb_build_object(
                    'type', 'child_feed', 'id', input_child_id, 'child_id', input_child_id,
                    'attendance_session_id', session_record.id, 'date', session_record.attendance_date
                ), input_actor
            );
        END IF;
    ELSIF input_action = 'needs_attention' THEN
        PERFORM public.enqueue_workflow_notification(
            child_record.school_id, 'Attendance needs attention',
            child_record.first_name || ' has an attendance record that needs review.',
            'attendance_exception', 'attendance_session', session_record.id,
            ARRAY(
                SELECT membership.user_id FROM public.school_memberships membership
                WHERE membership.school_id = child_record.school_id
                  AND membership.active = TRUE AND membership.role = 'school_director'
            ), 'attendance:exception:' || session_record.id::TEXT,
            'important', jsonb_build_object('type', 'attendance_session', 'id', session_record.id), input_actor
        );
    END IF;

    INSERT INTO public.workflow_audit_events (
        school_id, actor_id, event_type, source_type, source_id, metadata
    ) VALUES (
        child_record.school_id, input_actor, input_action, 'attendance_session', session_record.id,
        jsonb_build_object(
            'method', input_method,
            'location_code_id', input_location_code_id,
            'actor_role', input_actor_role,
            'occurred_at', input_occurred_at
        )
    );
    RETURN QUERY SELECT * FROM public.attendance_sessions WHERE id = session_record.id;
END;
$$;

REVOKE ALL ON FUNCTION public.record_attendance_core(UUID, TEXT, TIMESTAMPTZ, TEXT, TEXT, UUID, TEXT, UUID, TEXT)
FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.record_school_attendance(
    input_child_id UUID,
    input_action TEXT,
    input_occurred_at TIMESTAMPTZ DEFAULT NOW(),
    input_notes TEXT DEFAULT NULL,
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.attendance_sessions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    child_school_id UUID;
    actor_role TEXT;
BEGIN
    SELECT child.school_id INTO child_school_id
    FROM public.children child WHERE child.id = input_child_id AND child.active = TRUE;
    IF child_school_id IS NULL OR NOT (
        public.can_staff_access_child(input_child_id, actor, ARRAY['teacher', 'school_director'])
        OR public.is_hq_director(actor)
    ) THEN RAISE EXCEPTION 'You cannot record attendance for this child'; END IF;

    IF public.is_hq_director(actor) THEN
        actor_role := 'hq_director';
    ELSE
        SELECT membership.role INTO actor_role
        FROM public.school_memberships membership
        WHERE membership.school_id = child_school_id AND membership.user_id = actor
          AND membership.active = TRUE AND membership.role IN ('teacher', 'school_director')
        ORDER BY CASE membership.role WHEN 'school_director' THEN 0 ELSE 1 END LIMIT 1;
    END IF;

    RETURN QUERY SELECT * FROM public.record_attendance_core(
        input_child_id, input_action, input_occurred_at, input_notes,
        input_idempotency_key, actor, 'staff_manual', NULL, actor_role
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.fetch_attendance_location_code(input_school_id UUID)
RETURNS TABLE (
    id UUID,
    school_id UUID,
    classroom_id UUID,
    qr_payload TEXT,
    created_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT (
        public.has_school_role(input_school_id, auth.uid(), ARRAY['school_director'])
        OR public.is_hq_director(auth.uid())
    ) THEN RAISE EXCEPTION 'Only an authorized director can manage attendance codes'; END IF;
    RETURN QUERY
    SELECT code.id, code.school_id, code.classroom_id,
           'fireflyfm://attendance/v1?token=' || code.token,
           code.created_at, code.revoked_at
    FROM public.attendance_location_codes code
    WHERE code.school_id = input_school_id
      AND code.classroom_id IS NULL AND code.revoked_at IS NULL
    ORDER BY code.created_at DESC LIMIT 1;
END;
$$;

CREATE OR REPLACE FUNCTION public.rotate_attendance_location_code(
    input_school_id UUID,
    input_classroom_id UUID DEFAULT NULL
)
RETURNS TABLE (
    id UUID,
    school_id UUID,
    classroom_id UUID,
    qr_payload TEXT,
    created_at TIMESTAMPTZ,
    revoked_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
    actor UUID := auth.uid();
    saved_code public.attendance_location_codes%ROWTYPE;
    raw_token TEXT := encode(extensions.gen_random_bytes(32), 'hex');
BEGIN
    IF NOT (
        public.has_school_role(input_school_id, actor, ARRAY['school_director'])
        OR public.is_hq_director(actor)
    ) THEN RAISE EXCEPTION 'Only an authorized director can manage attendance codes'; END IF;
    IF input_classroom_id IS NOT NULL AND NOT EXISTS (
        SELECT 1 FROM public.classrooms classroom
        WHERE classroom.id = input_classroom_id AND classroom.school_id = input_school_id
    ) THEN RAISE EXCEPTION 'The classroom does not belong to this school'; END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(input_school_id::TEXT || ':attendance-location-code:' || COALESCE(input_classroom_id::TEXT, 'school'), 0));
    UPDATE public.attendance_location_codes code
    SET revoked_at = NOW(), revoked_by = actor
    WHERE code.school_id = input_school_id
      AND code.classroom_id IS NOT DISTINCT FROM input_classroom_id
      AND code.revoked_at IS NULL;

    INSERT INTO public.attendance_location_codes (
        school_id, classroom_id, token, created_by
    ) VALUES (
        input_school_id, input_classroom_id, raw_token, actor
    ) RETURNING * INTO saved_code;

    INSERT INTO public.workflow_audit_events (
        school_id, actor_id, event_type, source_type, source_id, metadata
    ) VALUES (
        input_school_id, actor, 'attendance_location_code_rotated',
        'attendance_location_code', saved_code.id,
        jsonb_build_object('scope', CASE WHEN input_classroom_id IS NULL THEN 'school' ELSE 'classroom' END,
                           'classroom_id', input_classroom_id)
    );

    RETURN QUERY SELECT saved_code.id, saved_code.school_id, saved_code.classroom_id,
        'fireflyfm://attendance/v1?token=' || saved_code.token,
        saved_code.created_at, saved_code.revoked_at;
END;
$$;

CREATE OR REPLACE FUNCTION public.revoke_attendance_location_code(input_code_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    saved_code public.attendance_location_codes%ROWTYPE;
BEGIN
    SELECT * INTO saved_code FROM public.attendance_location_codes WHERE id = input_code_id FOR UPDATE;
    IF NOT FOUND OR NOT (
        public.has_school_role(saved_code.school_id, actor, ARRAY['school_director'])
        OR public.is_hq_director(actor)
    ) THEN RAISE EXCEPTION 'Only an authorized director can manage attendance codes'; END IF;
    UPDATE public.attendance_location_codes
    SET revoked_at = COALESCE(revoked_at, NOW()), revoked_by = COALESCE(revoked_by, actor)
    WHERE id = input_code_id;
    INSERT INTO public.workflow_audit_events (
        school_id, actor_id, event_type, source_type, source_id
    ) VALUES (
        saved_code.school_id, actor, 'attendance_location_code_revoked',
        'attendance_location_code', saved_code.id
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.preview_guardian_qr_attendance(input_token TEXT)
RETURNS TABLE (
    code_id UUID,
    school_id UUID,
    school_name TEXT,
    child_id UUID,
    child_first_name TEXT,
    child_last_name TEXT,
    state TEXT,
    checked_in_at TIMESTAMPTZ,
    checked_out_at TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    code_record public.attendance_location_codes%ROWTYPE;
BEGIN
    SELECT * INTO code_record
    FROM public.attendance_location_codes code
    WHERE code.token = NULLIF(btrim(input_token), '') AND code.revoked_at IS NULL;
    IF code_record.id IS NULL OR NOT EXISTS (
        SELECT 1
        FROM public.school_memberships membership
        JOIN public.child_guardians guardian ON guardian.guardian_id = membership.user_id
        JOIN public.children child ON child.id = guardian.child_id AND child.school_id = membership.school_id
        WHERE membership.school_id = code_record.school_id
          AND membership.user_id = actor AND membership.role = 'parent'
          AND membership.active = TRUE AND membership.access_state = 'full'
          AND guardian.verification_status = 'verified' AND guardian.ended_at IS NULL
          AND child.active = TRUE
          AND (code_record.classroom_id IS NULL OR EXISTS (
              SELECT 1 FROM public.classroom_children classroom_child
              WHERE classroom_child.classroom_id = code_record.classroom_id
                AND classroom_child.child_id = child.id
          ))
    ) THEN RAISE EXCEPTION 'This check-in code is unavailable for your account'; END IF;

    RETURN QUERY
    SELECT code_record.id, child.school_id, school.name,
           child.id, child.first_name, child.last_name,
           COALESCE(latest.state, 'expected'), latest.checked_in_at, latest.checked_out_at
    FROM public.child_guardians guardian
    JOIN public.children child ON child.id = guardian.child_id AND child.active = TRUE
    JOIN public.schools school ON school.id = child.school_id
    JOIN public.school_memberships membership
      ON membership.school_id = child.school_id AND membership.user_id = guardian.guardian_id
    LEFT JOIN LATERAL (
        SELECT session.state, session.checked_in_at, session.checked_out_at
        FROM public.attendance_sessions session
        WHERE session.child_id = child.id
          AND session.attendance_date = (NOW() AT TIME ZONE 'America/New_York')::DATE
        ORDER BY COALESCE(session.checked_in_at, session.created_at) DESC LIMIT 1
    ) latest ON TRUE
    WHERE guardian.guardian_id = actor
      AND guardian.verification_status = 'verified' AND guardian.ended_at IS NULL
      AND membership.role = 'parent' AND membership.active = TRUE
      AND membership.access_state = 'full' AND child.school_id = code_record.school_id
      AND (code_record.classroom_id IS NULL OR EXISTS (
          SELECT 1 FROM public.classroom_children classroom_child
          WHERE classroom_child.classroom_id = code_record.classroom_id
            AND classroom_child.child_id = child.id
      ))
    ORDER BY child.first_name, child.last_name;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_guardian_qr_attendance(
    input_token TEXT,
    input_child_ids UUID[],
    input_action TEXT,
    input_idempotency_key TEXT
)
RETURNS TABLE (
    child_id UUID,
    success BOOLEAN,
    session_id UUID,
    action TEXT,
    occurred_at TIMESTAMPTZ,
    error_code TEXT,
    error_message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    code_record public.attendance_location_codes%ROWTYPE;
    target_child_id UUID;
    saved_session public.attendance_sessions%ROWTYPE;
    caught_state TEXT;
    caught_message TEXT;
BEGIN
    IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    IF input_action NOT IN ('check_in', 'check_out') THEN RAISE EXCEPTION 'Invalid QR attendance action'; END IF;
    IF COALESCE(array_length(input_child_ids, 1), 0) = 0 THEN RAISE EXCEPTION 'Select at least one child'; END IF;
    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NULL THEN
        RAISE EXCEPTION 'An idempotency key is required';
    END IF;

    SELECT * INTO code_record FROM public.attendance_location_codes code
    WHERE code.token = NULLIF(btrim(input_token), '') AND code.revoked_at IS NULL;
    IF code_record.id IS NULL THEN RAISE EXCEPTION 'This check-in code is unavailable for your account'; END IF;

    FOREACH target_child_id IN ARRAY input_child_ids LOOP
        BEGIN
            IF NOT EXISTS (
                SELECT 1
                FROM public.children child
                JOIN public.child_guardians guardian ON guardian.child_id = child.id
                JOIN public.school_memberships membership
                  ON membership.school_id = child.school_id AND membership.user_id = guardian.guardian_id
                WHERE child.id = target_child_id AND child.active = TRUE
                  AND child.school_id = code_record.school_id
                  AND guardian.guardian_id = actor
                  AND guardian.verification_status = 'verified' AND guardian.ended_at IS NULL
                  AND membership.role = 'parent' AND membership.active = TRUE
                  AND membership.access_state = 'full'
                  AND (code_record.classroom_id IS NULL OR EXISTS (
                      SELECT 1 FROM public.classroom_children classroom_child
                      WHERE classroom_child.classroom_id = code_record.classroom_id
                        AND classroom_child.child_id = child.id
                  ))
            ) THEN RAISE EXCEPTION 'This child is unavailable for QR attendance'; END IF;

            SELECT * INTO saved_session FROM public.record_attendance_core(
                target_child_id, input_action, NOW(), NULL,
                btrim(input_idempotency_key) || ':' || target_child_id::TEXT,
                actor, 'guardian_qr', code_record.id, 'parent'
            ) LIMIT 1;

            child_id := target_child_id;
            success := saved_session.id IS NOT NULL;
            session_id := saved_session.id;
            action := input_action;
            occurred_at := CASE WHEN input_action = 'check_in'
                THEN saved_session.checked_in_at ELSE saved_session.checked_out_at END;
            error_code := NULL;
            error_message := NULL;
            RETURN NEXT;
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS caught_state = RETURNED_SQLSTATE, caught_message = MESSAGE_TEXT;
            child_id := target_child_id;
            success := FALSE;
            session_id := NULL;
            action := input_action;
            occurred_at := NULL;
            error_code := caught_state;
            error_message := caught_message;
            RETURN NEXT;
        END;
    END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.fetch_attendance_location_code(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.rotate_attendance_location_code(UUID, UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.revoke_attendance_location_code(UUID) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.preview_guardian_qr_attendance(TEXT) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.record_guardian_qr_attendance(TEXT, UUID[], TEXT, TEXT) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.fetch_attendance_location_code(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.rotate_attendance_location_code(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_attendance_location_code(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.preview_guardian_qr_attendance(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_guardian_qr_attendance(TEXT, UUID[], TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ SELECT 20260917210000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
