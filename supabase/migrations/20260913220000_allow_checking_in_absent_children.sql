-- Migration: 20260913220000_allow_checking_in_absent_children.sql
-- Allow absent children to check in cleanly without "This child already has an open attendance session" error.

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
    child_record public.children%ROWTYPE;
    session_record public.attendance_sessions%ROWTYPE;
    guardian_ids UUID[];
    daily_summary TEXT;
    target_date DATE;
    latest_state TEXT;
BEGIN
    SELECT * INTO child_record FROM public.children WHERE id = input_child_id AND active = TRUE;
    IF NOT FOUND OR NOT (
        public.can_staff_access_child(input_child_id, actor, ARRAY['teacher', 'school_director'])
        OR public.is_hq_director(actor)
    ) THEN
        RAISE EXCEPTION 'You cannot record attendance for this child';
    END IF;
    IF input_action NOT IN ('check_in', 'check_out', 'expected', 'absent', 'needs_attention') THEN
        RAISE EXCEPTION 'Invalid attendance action';
    END IF;
    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NULL THEN
        RAISE EXCEPTION 'An idempotency key is required';
    END IF;

    target_date := (input_occurred_at AT TIME ZONE 'America/New_York')::DATE;

    PERFORM pg_advisory_xact_lock(hashtextextended(actor::TEXT || ':attendance:' || btrim(input_idempotency_key), 0));
    SELECT * INTO session_record
    FROM public.attendance_sessions
    WHERE school_id = child_record.school_id AND idempotency_key = btrim(input_idempotency_key);
    IF session_record.id IS NOT NULL THEN
        RETURN QUERY SELECT * FROM public.attendance_sessions WHERE id = session_record.id;
        RETURN;
    END IF;

    -- 1. Auto-close any stale open session from a prior date so it never blocks today's operations
    --    or violates the unique index idx_attendance_one_open_session.
    UPDATE public.attendance_sessions
    SET state = CASE WHEN state = 'present' THEN 'checked_out' ELSE state END,
        checked_out_at = COALESCE(checked_out_at, (attendance_date + TIME '18:00') AT TIME ZONE 'America/New_York'),
        notes = COALESCE(NULLIF(btrim(COALESCE(notes, '')), '') || ' | Auto-closed prior day session', 'Auto-closed prior day session'),
        updated_at = NOW()
    WHERE child_id = input_child_id
      AND attendance_date < target_date
      AND checked_in_at IS NOT NULL
      AND checked_out_at IS NULL;

    IF input_action = 'check_in' THEN
        -- Check if child was marked absent today
        SELECT state INTO latest_state
        FROM public.attendance_sessions
        WHERE child_id = input_child_id
          AND attendance_date = target_date
        ORDER BY COALESCE(checked_in_at, created_at) DESC
        LIMIT 1;

        -- If child was marked absent today, close any open session from earlier today
        -- so the child can be checked in when they arrive late.
        IF latest_state = 'absent' THEN
            UPDATE public.attendance_sessions
            SET state = 'checked_out',
                checked_out_at = input_occurred_at,
                checked_out_by = actor,
                notes = COALESCE(NULLIF(btrim(COALESCE(notes, '')), '') || ' | Closed upon check-in from absence', 'Closed upon check-in from absence'),
                updated_at = NOW()
            WHERE child_id = input_child_id
              AND checked_in_at IS NOT NULL
              AND checked_out_at IS NULL;
        END IF;

        -- If there is any leftover session with state = 'absent' that still has checked_in_at set, close it.
        UPDATE public.attendance_sessions
        SET checked_out_at = input_occurred_at,
            updated_at = NOW()
        WHERE child_id = input_child_id
          AND state = 'absent'
          AND checked_in_at IS NOT NULL
          AND checked_out_at IS NULL;

        -- Only raise exception if an active session is still open with state = 'present'
        IF EXISTS (
            SELECT 1 FROM public.attendance_sessions
            WHERE child_id = input_child_id
              AND checked_in_at IS NOT NULL
              AND checked_out_at IS NULL
              AND state = 'present'
        ) THEN
            RAISE EXCEPTION 'This child already has an open attendance session';
        END IF;

        INSERT INTO public.attendance_sessions (
            school_id, child_id, attendance_date, state, checked_in_at,
            checked_in_by, notes, idempotency_key
        ) VALUES (
            child_record.school_id, input_child_id,
            target_date,
            'present', input_occurred_at, actor, NULLIF(btrim(COALESCE(input_notes, '')), ''),
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
            checked_out_by = actor,
            notes = COALESCE(NULLIF(btrim(COALESCE(input_notes, '')), ''), notes),
            idempotency_key = btrim(input_idempotency_key), updated_at = NOW()
        WHERE id = session_record.id RETURNING * INTO session_record;
    ELSE
        -- If marking absent (or expected/needs_attention), close any open session so child
        -- doesn't remain simultaneously checked-in and absent.
        IF input_action = 'absent' THEN
            UPDATE public.attendance_sessions
            SET state = 'checked_out',
                checked_out_at = input_occurred_at,
                checked_out_by = actor,
                notes = COALESCE(NULLIF(btrim(COALESCE(notes, '')), '') || ' | Closed upon marking absent', 'Closed upon marking absent'),
                updated_at = NOW()
            WHERE child_id = input_child_id
              AND checked_in_at IS NOT NULL
              AND checked_out_at IS NULL;
        END IF;

        INSERT INTO public.attendance_sessions (
            school_id, child_id, attendance_date, state, notes, idempotency_key
        ) VALUES (
            child_record.school_id, input_child_id,
            target_date,
            input_action, NULLIF(btrim(COALESCE(input_notes, '')), ''), btrim(input_idempotency_key)
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
            'routine', jsonb_build_object('type', 'attendance_session', 'id', session_record.id, 'child_id', input_child_id), actor
        );
        IF input_action = 'check_out' THEN
            SELECT string_agg(summary.event_count::TEXT || ' ' || replace(summary.event_type, '_', ' '), ', ' ORDER BY summary.event_type)
            INTO daily_summary
            FROM (
                SELECT event.event_type, COUNT(*) AS event_count
                FROM public.child_care_events event
                WHERE event.child_id = input_child_id
                  AND event.visibility = 'parent'
                  AND (event.occurred_at AT TIME ZONE 'America/New_York')::DATE = session_record.attendance_date
                GROUP BY event.event_type
            ) summary;
            PERFORM public.enqueue_workflow_notification(
                child_record.school_id,
                child_record.first_name || '''s daily summary',
                COALESCE(daily_summary, 'No routine care updates were recorded today.'),
                'daily_care_summary', 'attendance_session', session_record.id,
                guardian_ids, 'daily-summary:' || session_record.id::TEXT,
                'routine', jsonb_build_object(
                    'type', 'child_feed', 'id', input_child_id, 'child_id', input_child_id,
                    'attendance_session_id', session_record.id, 'date', session_record.attendance_date
                ), actor
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
            'important', jsonb_build_object('type', 'attendance_session', 'id', session_record.id), actor
        );
    END IF;

    INSERT INTO public.workflow_audit_events (school_id, actor_id, event_type, source_type, source_id)
    VALUES (child_record.school_id, actor, input_action, 'attendance_session', session_record.id);
    RETURN QUERY SELECT * FROM public.attendance_sessions WHERE id = session_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.correct_attendance_session(
    input_session_id UUID,
    input_checked_in_at TIMESTAMPTZ,
    input_checked_out_at TIMESTAMPTZ,
    input_state TEXT,
    input_notes TEXT,
    input_reason TEXT
)
RETURNS SETOF public.attendance_sessions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    session_record public.attendance_sessions%ROWTYPE;
    before_record JSONB;
    effective_checked_in_at TIMESTAMPTZ := input_checked_in_at;
BEGIN
    SELECT * INTO session_record FROM public.attendance_sessions WHERE id = input_session_id FOR UPDATE;
    IF NOT FOUND OR NOT (
        public.has_school_role(session_record.school_id, actor, ARRAY['school_director'])
        OR public.is_hq_director(actor)
    ) THEN RAISE EXCEPTION 'Only a director can correct attendance'; END IF;
    IF NULLIF(btrim(COALESCE(input_reason, '')), '') IS NULL THEN RAISE EXCEPTION 'A correction reason is required'; END IF;
    IF input_state NOT IN ('expected', 'present', 'checked_out', 'absent', 'needs_attention') THEN
        RAISE EXCEPTION 'Invalid attendance state';
    END IF;

    -- If correcting state to absent without checkout, do not leave an open check-in timestamp
    IF input_state = 'absent' AND input_checked_out_at IS NULL THEN
        effective_checked_in_at := NULL;
    END IF;

    before_record := to_jsonb(session_record);
    UPDATE public.attendance_sessions
    SET checked_in_at = effective_checked_in_at, checked_out_at = input_checked_out_at,
        state = input_state, notes = NULLIF(btrim(COALESCE(input_notes, '')), ''), updated_at = NOW()
    WHERE id = input_session_id RETURNING * INTO session_record;
    INSERT INTO public.attendance_corrections (
        attendance_session_id, school_id, corrected_by, reason, before_values, after_values
    ) VALUES (
        input_session_id, session_record.school_id, actor, btrim(input_reason),
        before_record, to_jsonb(session_record)
    );
    RETURN QUERY SELECT * FROM public.attendance_sessions WHERE id = input_session_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.record_school_attendance(UUID, TEXT, TIMESTAMPTZ, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.correct_attendance_session(UUID, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT) TO authenticated;
