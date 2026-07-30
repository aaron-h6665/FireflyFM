
-- Migration: 20260721000000_baseline.sql

-- FireflyFM chat schema
-- Safe to run more than once in the Supabase SQL editor.

CREATE SCHEMA IF NOT EXISTS extensions;
CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA extensions;

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
    profile_image_url TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS school_deletion_backups (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL,
    school_name TEXT NOT NULL,
    backup_payload JSONB NOT NULL,
    deleted_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    deleted_at TIMESTAMPTZ DEFAULT NOW()
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
    archived_at TIMESTAMPTZ,
    archived_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    archive_reason TEXT,
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
    attendance_date DATE NOT NULL DEFAULT CURRENT_DATE,
    checked_in_at TIMESTAMPTZ,
    checked_out_at TIMESTAMPTZ,
    recorded_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    checked_in_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    checked_out_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    check_in_confirmed_at TIMESTAMPTZ,
    check_out_confirmed_at TIMESTAMPTZ,
    notes TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
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
    material_url TEXT,
    material_type TEXT DEFAULT 'file' CHECK (material_type IN ('article', 'link', 'image', 'video', 'file', 'mixed')),
    uploaded_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS curriculum_read_receipts (
    resource_id UUID NOT NULL REFERENCES curriculum_resources(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    checked_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (resource_id, user_id)
);

CREATE TABLE IF NOT EXISTS training_assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    file_name TEXT,
    file_path TEXT,
    material_url TEXT,
    material_type TEXT DEFAULT 'file' CHECK (material_type IN ('article', 'link', 'image', 'video', 'file', 'mixed')),
    assigned_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    due_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS training_read_receipts (
    assignment_id UUID NOT NULL REFERENCES training_assignments(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    checked_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (assignment_id, user_id)
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

CREATE TABLE IF NOT EXISTS assignments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    child_id UUID REFERENCES children(id) ON DELETE SET NULL,
    title TEXT NOT NULL,
    description TEXT,
    category TEXT NOT NULL DEFAULT 'general' CHECK (category IN ('paperwork', 'training', 'curriculum', 'onboarding', 'child_record', 'compliance', 'general')),
    audience_role TEXT CHECK (audience_role IN ('parent', 'teacher', 'school_director', 'hq_director')),
    assigned_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    due_at TIMESTAMPTZ,
    publish_at TIMESTAMPTZ,
    close_at TIMESTAMPTZ,
    status TEXT DEFAULT 'published' CHECK (status IN ('draft', 'active', 'scheduled', 'published', 'closed', 'archived')),
    visibility TEXT DEFAULT 'assigned' CHECK (visibility IN ('assigned', 'school_staff', 'school')),
    requires_review BOOLEAN DEFAULT TRUE,
    allow_resubmission BOOLEAN DEFAULT TRUE,
    legacy_source_type TEXT,
    legacy_source_id UUID,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

ALTER TABLE public.assignments
    ADD COLUMN IF NOT EXISTS publish_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS close_at TIMESTAMPTZ;

-- The complete schema may be rerun after the Phase 2 constraint is already
-- installed. Temporarily accept both the legacy `active` value used by the
-- backfills below and the final lifecycle values. The Phase 2 block later
-- converts `active` to `published` and tightens this constraint again.
ALTER TABLE public.assignments
    DROP CONSTRAINT IF EXISTS assignments_status_check;

ALTER TABLE public.assignments
    ALTER COLUMN status SET DEFAULT 'published',
    ADD CONSTRAINT assignments_status_check
    CHECK (status IN ('draft', 'active', 'scheduled', 'published', 'closed', 'archived'));

CREATE TABLE IF NOT EXISTS assignment_recipients (
    assignment_id UUID NOT NULL REFERENCES assignments(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    role_at_assignment TEXT CHECK (role_at_assignment IN ('parent', 'teacher', 'school_director', 'hq_director')),
    child_id UUID REFERENCES children(id) ON DELETE SET NULL,
    completion_status TEXT DEFAULT 'not_started' CHECK (completion_status IN ('not_started', 'read', 'submitted', 'reviewed', 'accepted', 'flagged', 'overdue')),
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (assignment_id, user_id)
);

CREATE TABLE IF NOT EXISTS assignment_materials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id UUID NOT NULL REFERENCES assignments(id) ON DELETE CASCADE,
    material_type TEXT NOT NULL DEFAULT 'file' CHECK (material_type IN ('article', 'link', 'image', 'video', 'file', 'mixed')),
    title TEXT,
    url TEXT,
    private_file_path TEXT,
    file_name TEXT,
    content_type TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS assignment_submissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id UUID NOT NULL REFERENCES assignments(id) ON DELETE CASCADE,
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    submitted_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    status TEXT DEFAULT 'submitted' CHECK (status IN ('submitted', 'accepted', 'flagged')),
    reviewer_message TEXT,
    reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,
    submitted_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (assignment_id, submitted_by)
);

CREATE TABLE IF NOT EXISTS assignment_submission_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    submission_id UUID NOT NULL REFERENCES assignment_submissions(id) ON DELETE CASCADE,
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    private_file_path TEXT NOT NULL,
    file_name TEXT,
    content_type TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS assignment_read_receipts (
    assignment_id UUID NOT NULL REFERENCES assignments(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    checked_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (assignment_id, user_id)
);

CREATE TABLE IF NOT EXISTS assignment_feedback_messages (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id UUID NOT NULL REFERENCES assignments(id) ON DELETE CASCADE,
    submission_id UUID REFERENCES assignment_submissions(id) ON DELETE CASCADE,
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    sender_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    body TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS role_invites (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    email TEXT NOT NULL,
    display_name TEXT,
    role TEXT NOT NULL CHECK (role IN ('school_director', 'teacher', 'parent')),
    token TEXT UNIQUE,
    token_hash TEXT,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'revoked', 'expired')),
    invited_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    accepted_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    accepted_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '14 days'),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE public.role_invites
    ALTER COLUMN token DROP NOT NULL,
    ADD COLUMN IF NOT EXISTS token_hash TEXT;

UPDATE public.role_invites
SET token_hash = encode(extensions.digest(token, 'sha256'), 'hex')
WHERE token IS NOT NULL
  AND token_hash IS NULL;

-- Existing links remain valid because acceptance compares the submitted secret
-- by hash; remove recoverable copies after the one-way migration.
UPDATE public.role_invites
SET token = NULL
WHERE token_hash IS NOT NULL;

CREATE UNIQUE INDEX IF NOT EXISTS idx_role_invites_token_hash
    ON public.role_invites(token_hash)
    WHERE token_hash IS NOT NULL;

CREATE TABLE IF NOT EXISTS classrooms (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    is_default BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ,
    UNIQUE (school_id, name)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_classrooms_one_default
    ON classrooms(school_id)
    WHERE is_default = TRUE;

CREATE TABLE IF NOT EXISTS classroom_children (
    classroom_id UUID NOT NULL REFERENCES classrooms(id) ON DELETE CASCADE,
    child_id UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
    assigned_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (classroom_id, child_id)
);

CREATE TABLE IF NOT EXISTS classroom_teachers (
    classroom_id UUID NOT NULL REFERENCES classrooms(id) ON DELETE CASCADE,
    teacher_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    assigned_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (classroom_id, teacher_id)
);

CREATE TABLE IF NOT EXISTS child_medical_profiles (
    child_id UUID PRIMARY KEY REFERENCES children(id) ON DELETE CASCADE,
    allergies TEXT,
    immunization_status TEXT,
    physical_status TEXT,
    medical_notes TEXT,
    medication_instructions TEXT,
    sleep_habits TEXT,
    dietary_notes TEXT,
    emergency_notes TEXT,
    updated_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS child_emergency_contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    child_id UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
    name TEXT NOT NULL,
    relationship TEXT,
    phone TEXT,
    email TEXT,
    can_pickup BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS child_progress_reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    child_id UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    body TEXT,
    file_name TEXT,
    file_path TEXT,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS child_goals (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    child_id UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    notes TEXT,
    status TEXT DEFAULT 'active' CHECK (status IN ('active', 'completed', 'paused')),
    due_at TIMESTAMPTZ,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS child_documents (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    child_id UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    document_type TEXT NOT NULL DEFAULT 'other',
    file_name TEXT,
    file_path TEXT,
    uploaded_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    verification_status TEXT DEFAULT 'submitted' CHECK (verification_status IN ('submitted', 'verified', 'flagged')),
    reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,
    flag_reason TEXT,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS medication_instructions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    child_id UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    dosage TEXT,
    instructions TEXT,
    scheduled_at TIMESTAMPTZ NOT NULL,
    repeat_rule TEXT,
    starts_on DATE,
    ends_on DATE,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    active BOOLEAN DEFAULT TRUE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS medication_tasks (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    child_id UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
    instruction_id UUID NOT NULL REFERENCES medication_instructions(id) ON DELETE CASCADE,
    due_at TIMESTAMPTZ NOT NULL,
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'due', 'acknowledged', 'missed', 'cancelled')),
    assigned_to UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    escalated_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS medication_acknowledgements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id UUID NOT NULL REFERENCES medication_tasks(id) ON DELETE CASCADE,
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    child_id UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
    acknowledged_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    dosage_given TEXT,
    notes TEXT,
    given_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS medication_escalations (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    task_id UUID NOT NULL REFERENCES medication_tasks(id) ON DELETE CASCADE,
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    child_id UUID NOT NULL REFERENCES children(id) ON DELETE CASCADE,
    reason TEXT NOT NULL,
    status TEXT DEFAULT 'open' CHECK (status IN ('open', 'resolved')),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    resolved_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS onboarding_requirements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    requirement_type TEXT NOT NULL DEFAULT 'document',
    target_role TEXT CHECK (target_role IN ('parent', 'teacher', 'school_director', 'hq_director')),
    target_user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    file_name TEXT,
    file_path TEXT,
    assigned_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    due_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS document_submissions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requirement_id UUID NOT NULL REFERENCES onboarding_requirements(id) ON DELETE CASCADE,
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    submitted_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    file_name TEXT,
    file_path TEXT,
    status TEXT DEFAULT 'submitted' CHECK (status IN ('submitted', 'verified', 'flagged')),
    reviewer_message TEXT,
    reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,
    submitted_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (requirement_id, submitted_by)
);

CREATE TABLE IF NOT EXISTS payment_setup_records (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    payment_type TEXT NOT NULL DEFAULT 'tuition',
    status TEXT DEFAULT 'needs_setup' CHECK (status IN ('needs_setup', 'submitted', 'verified', 'flagged', 'waived', 'sandbox_verified')),
    notes TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (school_id, user_id, payment_type)
);

ALTER TABLE public.payment_setup_records
    DROP CONSTRAINT IF EXISTS payment_setup_records_status_check;
ALTER TABLE public.payment_setup_records
    ADD CONSTRAINT payment_setup_records_status_check
    CHECK (status IN ('needs_setup', 'submitted', 'verified', 'flagged', 'waived', 'sandbox_verified'));

CREATE TABLE IF NOT EXISTS community_posts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    body TEXT NOT NULL,
    image_path TEXT,
    attachment_path TEXT,
    attachment_name TEXT,
    attachment_type TEXT,
    linked_event_id UUID REFERENCES school_events(id) ON DELETE SET NULL,
    poll_question TEXT,
    poll_options JSONB,
    scheduled_at TIMESTAMPTZ,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS community_albums (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    description TEXT,
    cover_path TEXT,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS community_album_media (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    album_id UUID NOT NULL REFERENCES community_albums(id) ON DELETE CASCADE,
    school_id UUID NOT NULL REFERENCES schools(id) ON DELETE CASCADE,
    file_name TEXT,
    file_path TEXT NOT NULL,
    content_type TEXT,
    uploaded_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS device_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    token TEXT NOT NULL,
    platform TEXT DEFAULT 'ios',
    bundle_id TEXT,
    environment TEXT DEFAULT 'development',
    last_seen_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (user_id, token)
);

CREATE TABLE IF NOT EXISTS queued_notifications (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID REFERENCES schools(id) ON DELETE CASCADE,
    user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    category TEXT NOT NULL,
    deliver_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    delivered_at TIMESTAMPTZ,
    status TEXT DEFAULT 'queued' CHECK (status IN ('queued', 'delivered', 'failed', 'cancelled')),
    source_type TEXT,
    source_id UUID,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS firefly_reflections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID REFERENCES schools(id) ON DELETE CASCADE,
    title TEXT NOT NULL,
    body TEXT NOT NULL,
    weekday INTEGER CHECK (weekday BETWEEN 0 AND 6),
    active BOOLEAN DEFAULT TRUE,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

ALTER TABLE chat_rooms
    ADD COLUMN IF NOT EXISTS description TEXT,
    ADD COLUMN IF NOT EXISTS profile_image_url TEXT,
    ADD COLUMN IF NOT EXISTS invite_hash TEXT UNIQUE DEFAULT gen_random_uuid()::TEXT,
    ADD COLUMN IF NOT EXISTS school_id UUID REFERENCES schools(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS room_type TEXT DEFAULT 'public',
    ADD COLUMN IF NOT EXISTS created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ DEFAULT NOW();

ALTER TABLE schools
    ADD COLUMN IF NOT EXISTS profile_image_url TEXT;

ALTER TABLE chat_rooms
    DROP CONSTRAINT IF EXISTS chat_rooms_room_type_check,
    ADD CONSTRAINT chat_rooms_room_type_check CHECK (room_type IN ('public', 'private'));

ALTER TABLE school_events
    ADD COLUMN IF NOT EXISTS all_day BOOLEAN DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS repeat_rule TEXT;

ALTER TABLE curriculum_resources
    ADD COLUMN IF NOT EXISTS material_url TEXT,
    ADD COLUMN IF NOT EXISTS material_type TEXT DEFAULT 'file';

ALTER TABLE training_assignments
    ADD COLUMN IF NOT EXISTS material_url TEXT,
    ADD COLUMN IF NOT EXISTS material_type TEXT DEFAULT 'file';

ALTER TABLE community_posts
    ADD COLUMN IF NOT EXISTS attachment_path TEXT,
    ADD COLUMN IF NOT EXISTS attachment_name TEXT,
    ADD COLUMN IF NOT EXISTS attachment_type TEXT,
    ADD COLUMN IF NOT EXISTS linked_event_id UUID REFERENCES school_events(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS poll_question TEXT,
    ADD COLUMN IF NOT EXISTS poll_options JSONB,
    ADD COLUMN IF NOT EXISTS scheduled_at TIMESTAMPTZ;

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

ALTER TABLE children
    ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS archived_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS archive_reason TEXT;

ALTER TABLE child_attendance
    ADD COLUMN IF NOT EXISTS attendance_date DATE,
    ADD COLUMN IF NOT EXISTS checked_in_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS checked_out_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS check_in_confirmed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS check_out_confirmed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS updated_at TIMESTAMPTZ;

UPDATE child_attendance
SET attendance_date = COALESCE(
    attendance_date,
    (checked_in_at AT TIME ZONE 'UTC')::DATE,
    (checked_out_at AT TIME ZONE 'UTC')::DATE,
    (created_at AT TIME ZONE 'UTC')::DATE,
    CURRENT_DATE
);

ALTER TABLE child_attendance
    ALTER COLUMN attendance_date SET DEFAULT CURRENT_DATE,
    ALTER COLUMN attendance_date SET NOT NULL;

ALTER TABLE child_medical_profiles
    ADD COLUMN IF NOT EXISTS immunization_status TEXT,
    ADD COLUMN IF NOT EXISTS physical_status TEXT;

CREATE INDEX IF NOT EXISTS idx_chat_participants_user_id ON chat_participants(user_id);
CREATE INDEX IF NOT EXISTS idx_chat_participants_room_id ON chat_participants(room_id);
CREATE INDEX IF NOT EXISTS idx_school_memberships_user_id ON school_memberships(user_id);
CREATE INDEX IF NOT EXISTS idx_school_memberships_school_id ON school_memberships(school_id);
CREATE INDEX IF NOT EXISTS idx_school_invites_code ON school_invites(code);
CREATE INDEX IF NOT EXISTS idx_school_deletion_backups_school ON school_deletion_backups(school_id, deleted_at DESC);
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
CREATE INDEX IF NOT EXISTS idx_child_attendance_school_day ON child_attendance(school_id, attendance_date DESC);
CREATE INDEX IF NOT EXISTS idx_child_attendance_daily_lookup ON child_attendance(school_id, child_id, attendance_date);
CREATE INDEX IF NOT EXISTS idx_child_activity_logs_child ON child_activity_logs(child_id, recorded_at DESC);
CREATE INDEX IF NOT EXISTS idx_paperwork_assignments_school ON paperwork_assignments(school_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_paperwork_recipients_parent ON paperwork_assignment_recipients(parent_id);
CREATE INDEX IF NOT EXISTS idx_paperwork_submissions_assignment ON paperwork_submissions(assignment_id);
CREATE INDEX IF NOT EXISTS idx_curriculum_resources_school ON curriculum_resources(school_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_curriculum_read_receipts_user ON curriculum_read_receipts(user_id);
CREATE INDEX IF NOT EXISTS idx_training_assignments_school ON training_assignments(school_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_training_read_receipts_user ON training_read_receipts(user_id);
CREATE INDEX IF NOT EXISTS idx_training_recipients_teacher ON training_assignment_recipients(teacher_id);
CREATE INDEX IF NOT EXISTS idx_training_submissions_assignment ON training_submissions(assignment_id);
CREATE INDEX IF NOT EXISTS idx_assignments_school_created ON assignments(school_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_assignments_school_due ON assignments(school_id, due_at);
CREATE INDEX IF NOT EXISTS idx_assignments_category ON assignments(category);
CREATE INDEX IF NOT EXISTS idx_assignments_child ON assignments(child_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_assignments_legacy_unique ON assignments(legacy_source_type, legacy_source_id) WHERE legacy_source_type IS NOT NULL AND legacy_source_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_assignment_recipients_user ON assignment_recipients(user_id, completion_status);
CREATE INDEX IF NOT EXISTS idx_assignment_recipients_child ON assignment_recipients(child_id);
CREATE INDEX IF NOT EXISTS idx_assignment_materials_assignment ON assignment_materials(assignment_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_assignment_materials_unique_file ON assignment_materials(assignment_id, private_file_path) WHERE private_file_path IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_assignment_materials_unique_url ON assignment_materials(assignment_id, url) WHERE url IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_assignment_submissions_assignment ON assignment_submissions(assignment_id);
CREATE INDEX IF NOT EXISTS idx_assignment_submissions_school ON assignment_submissions(school_id, submitted_at DESC);
CREATE INDEX IF NOT EXISTS idx_assignment_submission_attachments_submission ON assignment_submission_attachments(submission_id);
CREATE UNIQUE INDEX IF NOT EXISTS idx_assignment_submission_attachments_unique_path ON assignment_submission_attachments(submission_id, private_file_path);
CREATE INDEX IF NOT EXISTS idx_assignment_read_receipts_user ON assignment_read_receipts(user_id);
CREATE INDEX IF NOT EXISTS idx_assignment_feedback_assignment ON assignment_feedback_messages(assignment_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_role_invites_token ON role_invites(token);
CREATE INDEX IF NOT EXISTS idx_role_invites_email ON role_invites (lower(email));
WITH ranked_pending_role_invites AS (
    SELECT
        id,
        ROW_NUMBER() OVER (
            PARTITION BY school_id, lower(email), role
            ORDER BY created_at DESC, id DESC
        ) AS duplicate_rank
    FROM public.role_invites
    WHERE status = 'pending'
)
UPDATE public.role_invites
SET status = 'revoked'
WHERE id IN (
    SELECT id
    FROM ranked_pending_role_invites
    WHERE duplicate_rank > 1
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_role_invites_one_pending_per_school_email_role
    ON role_invites (school_id, lower(email), role)
    WHERE status = 'pending';
CREATE INDEX IF NOT EXISTS idx_classrooms_school ON classrooms(school_id);
CREATE INDEX IF NOT EXISTS idx_classroom_children_child ON classroom_children(child_id);
CREATE INDEX IF NOT EXISTS idx_classroom_teachers_teacher ON classroom_teachers(teacher_id);
CREATE INDEX IF NOT EXISTS idx_child_progress_reports_child ON child_progress_reports(child_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_child_goals_child ON child_goals(child_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_child_documents_child ON child_documents(child_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_medication_instructions_child ON medication_instructions(child_id, scheduled_at);
CREATE INDEX IF NOT EXISTS idx_medication_tasks_due ON medication_tasks(school_id, due_at, status);
CREATE INDEX IF NOT EXISTS idx_medication_tasks_child ON medication_tasks(child_id, due_at);
CREATE INDEX IF NOT EXISTS idx_medication_ack_task ON medication_acknowledgements(task_id);
CREATE INDEX IF NOT EXISTS idx_medication_escalations_school ON medication_escalations(school_id, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS idx_medication_escalations_task_unique ON medication_escalations(task_id);
CREATE INDEX IF NOT EXISTS idx_onboarding_requirements_school ON onboarding_requirements(school_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_document_submissions_school ON document_submissions(school_id, submitted_at DESC);
CREATE INDEX IF NOT EXISTS idx_payment_setup_records_user ON payment_setup_records(user_id);
CREATE INDEX IF NOT EXISTS idx_community_posts_school ON community_posts(school_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_community_albums_school ON community_albums(school_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_queued_notifications_delivery ON queued_notifications(status, deliver_at);

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

-- Unlike has_school_role, this helper does not grant implicit access to every HQ
-- director. Use it for private surfaces (such as school chat rooms) where HQ must
-- be explicitly added as a participant instead of inheriting global visibility.
CREATE OR REPLACE FUNCTION public.has_direct_school_role(school_uuid UUID, user_uuid UUID, allowed_roles TEXT[])
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
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
GRANT EXECUTE ON FUNCTION public.has_direct_school_role(UUID, UUID, TEXT[]) TO authenticated;

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

CREATE OR REPLACE FUNCTION public.create_school_for_onboarding(input_school_name TEXT)
RETURNS SETOF public.schools
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    created_school public.schools%ROWTYPE;
BEGIN
    IF actor IS NULL OR NOT public.is_hq_director(actor) THEN
        RAISE EXCEPTION 'Only headquarter directors can create schools';
    END IF;
    IF NULLIF(BTRIM(COALESCE(input_school_name, '')), '') IS NULL THEN
        RAISE EXCEPTION 'School name is required';
    END IF;

    INSERT INTO public.schools (name)
    VALUES (BTRIM(input_school_name))
    RETURNING * INTO created_school;
    PERFORM public.default_classroom_for_school(created_school.id);

    RETURN QUERY SELECT * FROM public.schools WHERE id = created_school.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_school_for_onboarding(TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_school_with_director_invite(
    input_school_name TEXT,
    input_director_email TEXT,
    input_director_name TEXT DEFAULT NULL
)
RETURNS TABLE (
    school_id UUID,
    school_name TEXT,
    invite_token TEXT,
    invite_url TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID;
    created_school public.schools%ROWTYPE;
    created_invite public.role_invites%ROWTYPE;
    raw_invite_token TEXT := encode(extensions.gen_random_bytes(32), 'hex');
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF NOT public.is_hq_director(actor) THEN
        RAISE EXCEPTION 'Only headquarter directors can create schools';
    END IF;

    RAISE EXCEPTION 'Create the school first, publish Operations → Director Setup, then invite the director';

    IF NULLIF(TRIM(input_school_name), '') IS NULL THEN
        RAISE EXCEPTION 'School name is required';
    END IF;

    IF NULLIF(TRIM(input_director_email), '') IS NULL
       OR POSITION('@' IN TRIM(input_director_email)) <= 1 THEN
        RAISE EXCEPTION 'A valid director email is required';
    END IF;

    INSERT INTO public.schools (name)
    VALUES (TRIM(input_school_name))
    RETURNING * INTO created_school;

    PERFORM public.default_classroom_for_school(created_school.id);

    INSERT INTO public.role_invites (
        school_id,
        email,
        display_name,
        role,
        invited_by,
        token,
        token_hash
    )
    VALUES (
        created_school.id,
        lower(TRIM(input_director_email)),
        NULLIF(TRIM(input_director_name), ''),
        'school_director',
        actor,
        NULL,
        encode(extensions.digest(raw_invite_token, 'sha256'), 'hex')
    )
    RETURNING * INTO created_invite;

    school_id := created_school.id;
    school_name := created_school.name;
    invite_token := raw_invite_token;
    invite_url := 'fireflyfm://role-invite?token=' || raw_invite_token;
    RETURN NEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_school_with_director_invite(TEXT, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_school_director_invite(
    input_school_id UUID,
    input_director_email TEXT,
    input_director_name TEXT DEFAULT NULL
)
RETURNS TABLE (
    school_id UUID,
    school_name TEXT,
    invite_token TEXT,
    invite_url TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID;
    selected_school public.schools%ROWTYPE;
    normalized_email TEXT;
    existing_user_id UUID;
    created_invite public.role_invites%ROWTYPE;
    raw_invite_token TEXT := encode(extensions.gen_random_bytes(32), 'hex');
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF NOT public.is_hq_director(actor) THEN
        RAISE EXCEPTION 'Only headquarter directors can assign school directors';
    END IF;

    SELECT * INTO selected_school
    FROM public.schools
    WHERE id = input_school_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'School not found';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.onboarding_templates templates
        WHERE templates.school_id = input_school_id
          AND templates.target_role = 'school_director'
          AND templates.status = 'published'
    ) THEN
        RAISE EXCEPTION 'Publish the school director onboarding template before inviting a director';
    END IF;

    normalized_email := lower(NULLIF(TRIM(input_director_email), ''));
    IF normalized_email IS NULL OR POSITION('@' IN normalized_email) <= 1 THEN
        RAISE EXCEPTION 'A valid director email is required';
    END IF;

    UPDATE public.role_invites AS ri
    SET status = 'expired'
    WHERE ri.school_id = input_school_id
      AND lower(ri.email) = normalized_email
      AND ri.role = 'school_director'
      AND ri.status = 'pending'
      AND ri.expires_at IS NOT NULL
      AND ri.expires_at <= NOW();

    -- Raw tokens are returned only once. Reissuing deliberately revokes the
    -- previous pending link so HQ can recover if it was not delivered.
    UPDATE public.role_invites AS ri
    SET status = 'revoked', token = NULL
    WHERE ri.school_id = input_school_id
      AND lower(ri.email) = normalized_email
      AND ri.role = 'school_director'
      AND ri.status = 'pending';

    SELECT id INTO existing_user_id
    FROM auth.users AS au
    WHERE lower(au.email) = normalized_email
    LIMIT 1;

    IF existing_user_id IS NOT NULL AND EXISTS (
        SELECT 1
        FROM public.school_memberships AS sm
        WHERE sm.school_id = input_school_id
          AND sm.user_id = existing_user_id
          AND sm.role = 'school_director'
          AND sm.active = TRUE
    ) THEN
        RAISE EXCEPTION '% is already an active school director for this school', normalized_email;
    END IF;

    BEGIN
        INSERT INTO public.role_invites (
            school_id,
            email,
            display_name,
            role,
            invited_by,
            token,
            token_hash
        )
        VALUES (
            input_school_id,
            normalized_email,
            NULLIF(TRIM(input_director_name), ''),
            'school_director',
            actor,
            NULL,
            encode(extensions.digest(raw_invite_token, 'sha256'), 'hex')
        )
        RETURNING * INTO created_invite;
    EXCEPTION
        WHEN unique_violation THEN
            RAISE EXCEPTION 'A school director invitation for % is already pending', normalized_email;
    END;

    school_id := selected_school.id;
    school_name := selected_school.name;
    invite_token := raw_invite_token;
    invite_url := 'fireflyfm://role-invite?token=' || raw_invite_token;
    RETURN NEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_school_director_invite(UUID, TEXT, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.archive_and_delete_school(
    input_school_id UUID,
    confirmation_name TEXT
)
RETURNS TABLE (archive_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID;
    school_record public.schools%ROWTYPE;
    backup_id UUID;
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF NOT public.is_hq_director(actor) THEN
        RAISE EXCEPTION 'Only headquarter directors can delete schools';
    END IF;

    SELECT * INTO school_record
    FROM public.schools
    WHERE id = input_school_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'School not found';
    END IF;

    IF confirmation_name IS NULL OR confirmation_name <> school_record.name THEN
        RAISE EXCEPTION 'Type the exact school name to confirm deletion';
    END IF;

    INSERT INTO public.school_deletion_backups (
        school_id,
        school_name,
        deleted_by,
        backup_payload
    )
    VALUES (
        school_record.id,
        school_record.name,
        actor,
        jsonb_build_object(
            'school', to_jsonb(school_record),
            'memberships', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.school_memberships t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'invites', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.school_invites t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'role_invites', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.role_invites t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'chat_rooms', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.chat_rooms t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'chat_participants', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.chat_participants t WHERE t.room_id IN (SELECT r.id FROM public.chat_rooms r WHERE r.school_id = school_record.id)), '[]'::jsonb),
            'messages', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.messages t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'newsletters', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.newsletters t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'events', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.school_events t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'event_invites', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.school_event_invites t WHERE t.event_id IN (SELECT e.id FROM public.school_events e WHERE e.school_id = school_record.id)), '[]'::jsonb),
            'notifications', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.notifications t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'notification_recipients', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.notification_recipients t WHERE t.notification_id IN (SELECT n.id FROM public.notifications n WHERE n.school_id = school_record.id)), '[]'::jsonb),
            'children', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.children t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'child_guardians', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.child_guardians t WHERE t.child_id IN (SELECT c.id FROM public.children c WHERE c.school_id = school_record.id)), '[]'::jsonb),
            'child_attendance', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.child_attendance t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'child_activity_logs', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.child_activity_logs t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'child_medical_profiles', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.child_medical_profiles t WHERE t.child_id IN (SELECT c.id FROM public.children c WHERE c.school_id = school_record.id)), '[]'::jsonb),
            'child_emergency_contacts', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.child_emergency_contacts t WHERE t.child_id IN (SELECT c.id FROM public.children c WHERE c.school_id = school_record.id)), '[]'::jsonb),
            'child_progress_reports', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.child_progress_reports t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'child_goals', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.child_goals t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'child_documents', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.child_documents t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'classrooms', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.classrooms t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'classroom_children', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.classroom_children t WHERE t.classroom_id IN (SELECT c.id FROM public.classrooms c WHERE c.school_id = school_record.id)), '[]'::jsonb),
            'classroom_teachers', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.classroom_teachers t WHERE t.classroom_id IN (SELECT c.id FROM public.classrooms c WHERE c.school_id = school_record.id)), '[]'::jsonb),
            'paperwork_assignments', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.paperwork_assignments t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'paperwork_submissions', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.paperwork_submissions t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'curriculum_resources', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.curriculum_resources t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'training_assignments', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.training_assignments t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'assignments', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.assignments t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'assignment_recipients', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.assignment_recipients t WHERE t.assignment_id IN (SELECT a.id FROM public.assignments a WHERE a.school_id = school_record.id)), '[]'::jsonb),
            'assignment_materials', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.assignment_materials t WHERE t.assignment_id IN (SELECT a.id FROM public.assignments a WHERE a.school_id = school_record.id)), '[]'::jsonb),
            'assignment_submissions', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.assignment_submissions t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'assignment_submission_attachments', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.assignment_submission_attachments t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'assignment_feedback_messages', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.assignment_feedback_messages t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'onboarding_requirements', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.onboarding_requirements t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'document_submissions', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.document_submissions t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'payment_setup_records', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.payment_setup_records t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'medication_instructions', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.medication_instructions t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'medication_tasks', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.medication_tasks t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'medication_acknowledgements', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.medication_acknowledgements t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'medication_escalations', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.medication_escalations t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'community_posts', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.community_posts t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'community_albums', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.community_albums t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'community_album_media', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.community_album_media t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'queued_notifications', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.queued_notifications t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'firefly_reflections', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.firefly_reflections t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'backed_up_at', NOW()
        )
    )
    RETURNING id INTO backup_id;

    DELETE FROM public.schools
    WHERE id = school_record.id;

    archive_id := backup_id;
    RETURN NEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION public.archive_and_delete_school(UUID, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.accept_role_invite(invite_token TEXT)
RETURNS SETOF public.school_memberships
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    invite_record public.role_invites%ROWTYPE;
    joining_user UUID;
    joining_email TEXT;
BEGIN
    joining_user := auth.uid();
    IF joining_user IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    joining_email := lower(COALESCE(auth.jwt()->>'email', ''));
    IF joining_email = '' THEN
        RAISE EXCEPTION 'Your account email could not be verified';
    END IF;

    SELECT *
    INTO invite_record
    FROM public.role_invites
    WHERE (
            token_hash = encode(extensions.digest(NULLIF(TRIM(invite_token), ''), 'sha256'), 'hex')
            OR token = NULLIF(TRIM(invite_token), '')
          )
      AND status = 'pending'
      AND (expires_at IS NULL OR expires_at > NOW())
    LIMIT 1
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid or expired invite link';
    END IF;

    IF lower(invite_record.email) <> joining_email THEN
        RAISE EXCEPTION 'This invite was issued to %, but you are signed in as %', invite_record.email, joining_email;
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.onboarding_templates templates
        WHERE templates.school_id = invite_record.school_id
          AND templates.target_role = invite_record.role
          AND templates.status = 'published'
    ) THEN
        RAISE EXCEPTION 'The onboarding template for this invitation is not published yet';
    END IF;

    INSERT INTO public.school_memberships (school_id, user_id, role, active, joined_at)
    VALUES (invite_record.school_id, joining_user, invite_record.role, TRUE, NOW())
    ON CONFLICT (school_id, user_id)
    DO UPDATE SET active = TRUE, role = EXCLUDED.role, joined_at = NOW();

    UPDATE public.role_invites
    SET status = 'accepted',
        accepted_by = joining_user,
        accepted_at = NOW(),
        token = NULL
    WHERE id = invite_record.id;

    IF invite_record.display_name IS NOT NULL THEN
        INSERT INTO public.profiles (id, display_name)
        VALUES (joining_user, invite_record.display_name)
        ON CONFLICT (id) DO UPDATE
            SET display_name = COALESCE(NULLIF(public.profiles.display_name, ''), EXCLUDED.display_name),
                updated_at = NOW();
    END IF;

    RETURN QUERY
    SELECT *
    FROM public.school_memberships
    WHERE school_id = invite_record.school_id
      AND user_id = joining_user;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_school_with_director_invite(TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.accept_role_invite(TEXT) TO authenticated;

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
          AND public.has_direct_school_role(school_id, user_uuid, ARRAY['school_director'])
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
          AND public.is_school_member(school_id, recipient_uuid)
          AND (
              public.has_school_role(school_id, actor_uuid, ARRAY['school_director', 'hq_director'])
              OR (
                  public.has_school_role(school_id, actor_uuid, ARRAY['teacher'])
                  AND public.has_school_role(school_id, recipient_uuid, ARRAY['parent', 'school_director'])
              )
              OR (
                  public.has_school_role(school_id, actor_uuid, ARRAY['parent'])
                  AND public.has_school_role(school_id, recipient_uuid, ARRAY['teacher', 'school_director'])
              )
          )
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
        JOIN public.children
          ON children.id = child_guardians.child_id
        JOIN public.school_memberships
          ON school_memberships.school_id = children.school_id
         AND school_memberships.user_id = child_guardians.guardian_id
         AND school_memberships.active = TRUE
         AND school_memberships.role = 'parent'
        WHERE child_id = child_uuid
          AND guardian_id = user_uuid
    );
$$;

CREATE OR REPLACE FUNCTION public.default_classroom_for_school(school_uuid UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    classroom_uuid UUID;
BEGIN
    SELECT id
    INTO classroom_uuid
    FROM public.classrooms
    WHERE school_id = school_uuid
      AND is_default = TRUE
    LIMIT 1;

    IF classroom_uuid IS NULL THEN
        INSERT INTO public.classrooms (school_id, name, is_default)
        VALUES (school_uuid, 'Default Classroom', TRUE)
        ON CONFLICT (school_id, name) DO UPDATE SET is_default = TRUE
        RETURNING id INTO classroom_uuid;
    END IF;

    RETURN classroom_uuid;
END;
$$;

CREATE OR REPLACE FUNCTION public.is_classroom_teacher_for_child(child_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.classroom_children
        JOIN public.classroom_teachers
          ON classroom_teachers.classroom_id = classroom_children.classroom_id
        WHERE classroom_children.child_id = child_uuid
          AND classroom_teachers.teacher_id = user_uuid
    )
    OR EXISTS (
        SELECT 1
        FROM public.children
        WHERE children.id = child_uuid
          AND public.has_school_role(children.school_id, user_uuid, ARRAY['teacher'])
          AND NOT EXISTS (
              SELECT 1
              FROM public.classroom_teachers
              WHERE classroom_teachers.teacher_id = user_uuid
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.can_staff_access_child(child_uuid UUID, user_uuid UUID, allowed_roles TEXT[])
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.is_hq_director(user_uuid)
    OR EXISTS (
        SELECT 1
        FROM public.children
        WHERE id = child_uuid
          AND (
              (
                  'school_director' = ANY(allowed_roles)
                  AND public.has_school_role(school_id, user_uuid, ARRAY['school_director'])
              )
              OR (
                  'teacher' = ANY(allowed_roles)
                  AND public.is_classroom_teacher_for_child(child_uuid, user_uuid)
              )
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.can_access_child(child_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.is_child_guardian(child_uuid, user_uuid)
        OR public.can_staff_access_child(child_uuid, user_uuid, ARRAY['teacher', 'school_director', 'hq_director']);
$$;

CREATE OR REPLACE FUNCTION public.is_assignment_recipient(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.assignment_recipients
        WHERE assignment_id = assignment_uuid
          AND user_id = user_uuid
    );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_assignment(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.assignments
        WHERE id = assignment_uuid
          AND (
              public.has_school_role(school_id, user_uuid, ARRAY['hq_director'])
              OR assigned_by = user_uuid
              OR (
                  assigned_by IS NULL
                  AND public.has_school_role(school_id, user_uuid, ARRAY['school_director'])
              )
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.can_review_assignment(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.assignments
        WHERE id = assignment_uuid
          AND NOT EXISTS (
              SELECT 1
              FROM public.assignment_recipients
              WHERE assignment_recipients.assignment_id = assignments.id
                AND assignment_recipients.user_id = user_uuid
          )
          AND NOT EXISTS (
              SELECT 1
              FROM public.assignment_submissions
              WHERE assignment_submissions.assignment_id = assignments.id
                AND assignment_submissions.submitted_by = user_uuid
          )
          AND (
              public.has_school_role(school_id, user_uuid, ARRAY['hq_director'])
              OR (
                  assigned_by = user_uuid
                  AND public.has_school_role(school_id, user_uuid, ARRAY['school_director'])
              )
              OR (
                  assigned_by IS NULL
                  AND public.has_school_role(school_id, user_uuid, ARRAY['school_director'])
              )
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.can_view_assignment(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.assignments
        WHERE id = assignment_uuid
          AND (
              public.has_school_role(school_id, user_uuid, ARRAY['hq_director'])
              OR assigned_by = user_uuid
              OR public.can_review_assignment(id, user_uuid)
              OR public.is_assignment_recipient(id, user_uuid)
              OR (
                  child_id IS NOT NULL
                  AND public.is_child_guardian(child_id, user_uuid)
              )
              OR (
                  category = 'child_record'
                  AND child_id IS NOT NULL
                  AND public.can_staff_access_child(child_id, user_uuid, ARRAY['teacher', 'school_director', 'hq_director'])
              )
              OR (
                  visibility = 'school'
                  AND public.is_school_member(school_id, user_uuid)
              )
              OR (
                  visibility = 'school_staff'
                  AND public.has_school_role(school_id, user_uuid, ARRAY['teacher', 'school_director', 'hq_director'])
              )
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.can_submit_assignment(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.assignments
        WHERE id = assignment_uuid
          AND status = 'active'
          AND (
              public.is_assignment_recipient(id, user_uuid)
              OR (
                  child_id IS NOT NULL
                  AND public.is_child_guardian(child_id, user_uuid)
              )
          )
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
GRANT EXECUTE ON FUNCTION public.default_classroom_for_school(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_classroom_teacher_for_child(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_staff_access_child(UUID, UUID, TEXT[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_access_child(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_assignment_recipient(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_assignment(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_review_assignment(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_view_assignment(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_submit_assignment(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_paperwork_assignment_recipient(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_paperwork_assignment(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_submit_paperwork_assignment(UUID, UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_training_assignment_recipient(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_training_assignment(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_submit_training_assignment(UUID, UUID, UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.create_child_for_current_parent(
    school_id UUID,
    first_name TEXT,
    last_name TEXT,
    birthdate DATE DEFAULT NULL
)
RETURNS SETOF public.children
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID;
    created_child public.children%ROWTYPE;
    classroom_uuid UUID;
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF NOT public.has_school_role($1, actor, ARRAY['parent']) THEN
        RAISE EXCEPTION 'Only parents can add children to their active school';
    END IF;

    IF NULLIF(TRIM($2), '') IS NULL OR NULLIF(TRIM($3), '') IS NULL THEN
        RAISE EXCEPTION 'Child first and last name are required';
    END IF;

    INSERT INTO public.children (school_id, first_name, last_name, birthdate, active)
    VALUES ($1, TRIM($2), TRIM($3), $4, TRUE)
    RETURNING * INTO created_child;

    INSERT INTO public.child_guardians (child_id, guardian_id, relationship)
    VALUES (created_child.id, actor, 'Parent')
    ON CONFLICT (child_id, guardian_id) DO NOTHING;

    classroom_uuid := public.default_classroom_for_school($1);
    INSERT INTO public.classroom_children (classroom_id, child_id)
    VALUES (classroom_uuid, created_child.id)
    ON CONFLICT DO NOTHING;

    RETURN QUERY SELECT * FROM public.children WHERE id = created_child.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_child_attendance(
    input_school_id UUID,
    input_child_id UUID,
    checking_in BOOLEAN,
    recorded_at TIMESTAMPTZ DEFAULT NOW(),
    input_notes TEXT DEFAULT NULL
)
RETURNS SETOF public.child_attendance
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID;
    attendance_day DATE;
    saved_attendance public.child_attendance%ROWTYPE;
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF NOT public.can_staff_access_child(input_child_id, actor, ARRAY['teacher', 'school_director', 'hq_director']) THEN
        RAISE EXCEPTION 'Only assigned staff can record child attendance';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.children
        WHERE id = input_child_id
          AND school_id = input_school_id
          AND active = TRUE
    ) THEN
        RAISE EXCEPTION 'Child is not active in this school';
    END IF;

    attendance_day := COALESCE((recorded_at AT TIME ZONE 'UTC')::DATE, CURRENT_DATE);

    SELECT *
    INTO saved_attendance
    FROM public.child_attendance
    WHERE school_id = input_school_id
      AND child_id = input_child_id
      AND attendance_date = attendance_day
    ORDER BY COALESCE(updated_at, created_at) DESC
    LIMIT 1
    FOR UPDATE;

    IF FOUND THEN
        UPDATE public.child_attendance
        SET checked_in_at = CASE
                WHEN checking_in THEN recorded_at
                ELSE checked_in_at
            END,
            checked_out_at = CASE
                WHEN checking_in THEN checked_out_at
                ELSE recorded_at
            END,
            recorded_by = actor,
            checked_in_by = CASE
                WHEN checking_in THEN actor
                ELSE checked_in_by
            END,
            checked_out_by = CASE
                WHEN checking_in THEN checked_out_by
                ELSE actor
            END,
            check_in_confirmed_at = CASE
                WHEN checking_in THEN NOW()
                ELSE check_in_confirmed_at
            END,
            check_out_confirmed_at = CASE
                WHEN checking_in THEN check_out_confirmed_at
                ELSE NOW()
            END,
            notes = COALESCE(NULLIF(TRIM(input_notes), ''), notes),
            updated_at = NOW()
        WHERE id = saved_attendance.id
        RETURNING * INTO saved_attendance;
    ELSE
        INSERT INTO public.child_attendance (
            school_id,
            child_id,
            attendance_date,
            checked_in_at,
            checked_out_at,
            recorded_by,
            checked_in_by,
            checked_out_by,
            check_in_confirmed_at,
            check_out_confirmed_at,
            notes,
            updated_at
        )
        VALUES (
            input_school_id,
            input_child_id,
            attendance_day,
            CASE WHEN checking_in THEN recorded_at ELSE NULL END,
            CASE WHEN checking_in THEN NULL ELSE recorded_at END,
            actor,
            CASE WHEN checking_in THEN actor ELSE NULL END,
            CASE WHEN checking_in THEN NULL ELSE actor END,
            CASE WHEN checking_in THEN NOW() ELSE NULL END,
            CASE WHEN checking_in THEN NULL ELSE NOW() END,
            NULLIF(TRIM(input_notes), ''),
            NOW()
        )
        RETURNING * INTO saved_attendance;
    END IF;

    RETURN QUERY SELECT * FROM public.child_attendance WHERE id = saved_attendance.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.can_submit_onboarding_requirement(requirement_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.onboarding_requirements
        WHERE id = requirement_uuid
          AND (
              target_user_id = user_uuid
              OR (
                  target_user_id IS NULL
                  AND target_role IS NOT NULL
                  AND public.has_school_role(school_id, user_uuid, ARRAY[target_role])
              )
              OR (
                  target_user_id IS NULL
                  AND target_role IS NULL
                  AND public.is_school_member(school_id, user_uuid)
              )
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.can_manage_onboarding_requirement(requirement_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.onboarding_requirements
        WHERE id = requirement_uuid
          AND public.has_school_role(school_id, user_uuid, ARRAY['school_director', 'hq_director'])
    );
$$;

CREATE OR REPLACE FUNCTION public.submit_required_document(
    requirement_id UUID,
    file_name TEXT,
    file_path TEXT
)
RETURNS SETOF public.document_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID;
    requirement_record public.onboarding_requirements%ROWTYPE;
    saved_submission public.document_submissions%ROWTYPE;
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT *
    INTO requirement_record
    FROM public.onboarding_requirements
    WHERE id = $1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Required document was not found';
    END IF;

    IF NOT public.can_submit_onboarding_requirement($1, actor) THEN
        RAISE EXCEPTION 'You are not assigned to this required document';
    END IF;

    INSERT INTO public.document_submissions (
        requirement_id,
        school_id,
        submitted_by,
        file_name,
        file_path,
        status,
        reviewer_message,
        submitted_at
    )
    VALUES (
        requirement_record.id,
        requirement_record.school_id,
        actor,
        $2,
        $3,
        'submitted',
        NULL,
        NOW()
    )
    ON CONFLICT (requirement_id, submitted_by)
    DO UPDATE SET
        file_name = EXCLUDED.file_name,
        file_path = EXCLUDED.file_path,
        status = 'submitted',
        reviewer_message = NULL,
        reviewed_by = NULL,
        reviewed_at = NULL,
        submitted_at = NOW()
    RETURNING * INTO saved_submission;

    RETURN QUERY SELECT * FROM public.document_submissions WHERE id = saved_submission.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_required_document(
    submission_id UUID,
    status TEXT,
    reviewer_message TEXT DEFAULT NULL
)
RETURNS SETOF public.document_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID;
    submission_record public.document_submissions%ROWTYPE;
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF status NOT IN ('verified', 'flagged', 'submitted') THEN
        RAISE EXCEPTION 'Unsupported review status';
    END IF;

    SELECT *
    INTO submission_record
    FROM public.document_submissions
    WHERE id = $1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Document submission was not found';
    END IF;

    IF NOT public.has_school_role(submission_record.school_id, actor, ARRAY['school_director', 'hq_director']) THEN
        RAISE EXCEPTION 'Only directors can review document submissions';
    END IF;

    UPDATE public.document_submissions
    SET status = $2,
        reviewer_message = $3,
        reviewed_by = actor,
        reviewed_at = NOW()
    WHERE id = $1;

    RETURN QUERY SELECT * FROM public.document_submissions WHERE id = $1;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_paperwork_assignment(
    assignment_id UUID,
    file_name TEXT,
    file_path TEXT
)
RETURNS SETOF public.paperwork_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID;
    assignment_record public.paperwork_assignments%ROWTYPE;
    existing_submission_id UUID;
    expected_prefix TEXT;
    saved_submission public.paperwork_submissions%ROWTYPE;
    created_notification_id UUID;
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT *
    INTO assignment_record
    FROM public.paperwork_assignments
    WHERE id = $1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Paperwork assignment was not found';
    END IF;

    IF NOT public.can_submit_paperwork_assignment($1, assignment_record.school_id, actor) THEN
        RAISE EXCEPTION 'You are not assigned to this paperwork';
    END IF;

    expected_prefix := 'schools/'
        || assignment_record.school_id::TEXT
        || '/paperwork_submissions/'
        || actor::TEXT
        || '/';

    IF $3 IS NULL OR LOWER($3) NOT LIKE LOWER(expected_prefix) || '%' THEN
        RAISE EXCEPTION 'Paperwork upload path is invalid';
    END IF;

    SELECT id
    INTO existing_submission_id
    FROM public.paperwork_submissions
    WHERE assignment_id = assignment_record.id
      AND submitted_by = actor
    ORDER BY submitted_at DESC
    LIMIT 1;

    IF existing_submission_id IS NULL THEN
        INSERT INTO public.paperwork_submissions (
            assignment_id,
            school_id,
            submitted_by,
            file_name,
            file_path,
            status,
            flag_reason,
            reviewed_by,
            reviewed_at,
            submitted_at
        )
        VALUES (
            assignment_record.id,
            assignment_record.school_id,
            actor,
            $2,
            $3,
            'submitted',
            NULL,
            NULL,
            NULL,
            NOW()
        )
        RETURNING * INTO saved_submission;
    ELSE
        UPDATE public.paperwork_submissions
        SET file_name = $2,
            file_path = $3,
            status = 'submitted',
            flag_reason = NULL,
            reviewed_by = NULL,
            reviewed_at = NULL,
            submitted_at = NOW()
        WHERE id = existing_submission_id
        RETURNING * INTO saved_submission;
    END IF;

    INSERT INTO public.notifications (
        school_id,
        title,
        body,
        category,
        source_type,
        source_id,
        created_by
    )
    VALUES (
        assignment_record.school_id,
        'Paperwork submitted',
        'A parent uploaded paperwork for "' || assignment_record.title || '".',
        'paperwork_submission',
        'paperwork_submission',
        saved_submission.id,
        actor
    )
    RETURNING id INTO created_notification_id;

    INSERT INTO public.notification_recipients (notification_id, user_id)
    SELECT DISTINCT created_notification_id, school_memberships.user_id
    FROM public.school_memberships
    WHERE school_memberships.active = TRUE
      AND school_memberships.user_id <> actor
      AND (
          (
              school_memberships.school_id = assignment_record.school_id
              AND school_memberships.role = 'school_director'
          )
          OR school_memberships.role = 'hq_director'
      )
    ON CONFLICT DO NOTHING;

    RETURN QUERY SELECT * FROM public.paperwork_submissions WHERE id = saved_submission.id;
END;
$$;

DROP FUNCTION IF EXISTS public.create_assignment(UUID, TEXT, TEXT, TEXT, TEXT, UUID, TIMESTAMPTZ, BOOLEAN, UUID[], JSONB);

CREATE OR REPLACE FUNCTION public.create_assignment(
    input_school_id UUID,
    input_title TEXT,
    input_description TEXT DEFAULT NULL,
    input_category TEXT DEFAULT 'general',
    input_audience_role TEXT DEFAULT NULL,
    input_child_id UUID DEFAULT NULL,
    input_due_at TIMESTAMPTZ DEFAULT NULL,
    input_requires_review BOOLEAN DEFAULT TRUE,
    input_recipient_ids UUID[] DEFAULT '{}'::UUID[],
    input_materials JSONB DEFAULT '[]'::JSONB,
    input_status TEXT DEFAULT 'published',
    input_publish_at TIMESTAMPTZ DEFAULT NULL,
    input_close_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS SETOF public.assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID;
    created_assignment public.assignments%ROWTYPE;
    recipient_uuid UUID;
    material_item JSONB;
    created_notification_id UUID;
    notification_body TEXT;
    expected_recipient_count INTEGER;
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF input_title IS NULL OR btrim(input_title) = '' THEN
        RAISE EXCEPTION 'Assignment title is required';
    END IF;

    IF input_status NOT IN ('draft', 'scheduled', 'published') THEN
        RAISE EXCEPTION 'Assignment status must be draft, scheduled, or published';
    END IF;

    IF input_status = 'scheduled' AND (input_publish_at IS NULL OR input_publish_at <= NOW()) THEN
        RAISE EXCEPTION 'Scheduled assignments need a future publish date';
    END IF;

    IF NOT public.has_school_role(input_school_id, actor, ARRAY['school_director', 'hq_director']) THEN
        RAISE EXCEPTION 'Only directors can create assignments';
    END IF;

    IF input_child_id IS NOT NULL AND NOT EXISTS (
        SELECT 1
        FROM public.children
        WHERE id = input_child_id
          AND school_id = input_school_id
    ) THEN
        RAISE EXCEPTION 'Child does not belong to this school';
    END IF;

    IF input_recipient_ids IS NOT NULL AND EXISTS (
        SELECT 1
        FROM unnest(input_recipient_ids) requested(user_id)
        WHERE NOT EXISTS (
            SELECT 1
            FROM public.school_memberships memberships
            WHERE memberships.school_id = input_school_id
              AND memberships.user_id = requested.user_id
              AND memberships.active = TRUE
        )
    ) THEN
        RAISE EXCEPTION 'Every assignment recipient must be an active member of the selected school';
    END IF;

    expected_recipient_count := COALESCE(
        (SELECT COUNT(DISTINCT id) FROM unnest(input_recipient_ids) requested(id)),
        0
    );
    IF expected_recipient_count = 0 AND input_child_id IS NULL THEN
        RAISE EXCEPTION 'Select at least one assignment recipient';
    END IF;

    INSERT INTO public.assignments (
        school_id,
        child_id,
        title,
        description,
        category,
        audience_role,
        assigned_by,
        due_at,
        publish_at,
        close_at,
        status,
        visibility,
        requires_review,
        allow_resubmission,
        created_at
    )
    VALUES (
        input_school_id,
        input_child_id,
        btrim(input_title),
        NULLIF(btrim(COALESCE(input_description, '')), ''),
        input_category,
        input_audience_role,
        actor,
        input_due_at,
        input_publish_at,
        input_close_at,
        input_status,
        'assigned',
        input_requires_review,
        TRUE,
        NOW()
    )
    RETURNING * INTO created_assignment;

    IF input_child_id IS NOT NULL AND (input_recipient_ids IS NULL OR array_length(input_recipient_ids, 1) IS NULL) THEN
        INSERT INTO public.assignment_recipients (
            assignment_id,
            user_id,
            role_at_assignment,
            child_id,
            completion_status
        )
        SELECT
            created_assignment.id,
            child_guardians.guardian_id,
            school_memberships.role,
            input_child_id,
            'not_started'
        FROM public.child_guardians
        JOIN public.school_memberships
          ON school_memberships.user_id = child_guardians.guardian_id
         AND school_memberships.school_id = input_school_id
         AND school_memberships.active = TRUE
        WHERE child_guardians.child_id = input_child_id
        ON CONFLICT DO NOTHING;
    END IF;

    IF input_recipient_ids IS NOT NULL THEN
        FOREACH recipient_uuid IN ARRAY input_recipient_ids LOOP
            INSERT INTO public.assignment_recipients (
                assignment_id,
                user_id,
                role_at_assignment,
                child_id,
                completion_status
            )
            SELECT
                created_assignment.id,
                recipient_uuid,
                school_memberships.role,
                input_child_id,
                'not_started'
            FROM public.school_memberships
            WHERE school_memberships.school_id = input_school_id
              AND school_memberships.user_id = recipient_uuid
              AND school_memberships.active = TRUE
            ON CONFLICT DO NOTHING;
        END LOOP;
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.assignment_recipients
        WHERE assignment_id = created_assignment.id
    ) THEN
        RAISE EXCEPTION 'Assignment recipient creation failed';
    END IF;

    IF expected_recipient_count > 0 AND (
        SELECT COUNT(*) FROM public.assignment_recipients
        WHERE assignment_id = created_assignment.id
    ) <> expected_recipient_count THEN
        RAISE EXCEPTION 'Assignment recipient creation was incomplete';
    END IF;

    FOR material_item IN SELECT * FROM jsonb_array_elements(COALESCE(input_materials, '[]'::JSONB)) LOOP
        INSERT INTO public.assignment_materials (
            assignment_id,
            material_type,
            title,
            url,
            private_file_path,
            file_name,
            content_type
        )
        VALUES (
            created_assignment.id,
            COALESCE(material_item->>'material_type', 'file'),
            NULLIF(material_item->>'title', ''),
            NULLIF(material_item->>'url', ''),
            NULLIF(material_item->>'private_file_path', ''),
            NULLIF(material_item->>'file_name', ''),
            NULLIF(material_item->>'content_type', '')
        );
    END LOOP;

    IF input_status = 'published' THEN
        notification_body := CASE
            WHEN input_due_at IS NULL THEN 'No due date. Status: Not submitted.'
            ELSE 'Due ' || to_char(input_due_at AT TIME ZONE 'UTC', 'Mon DD, YYYY HH24:MI') || ' UTC. Status: Not submitted.'
        END;

        INSERT INTO public.notifications (
            school_id,
            title,
            body,
            category,
            source_type,
            source_id,
            created_by
        )
        VALUES (
            input_school_id,
            created_assignment.title,
            notification_body,
            'assignment_assigned',
            'assignment',
            created_assignment.id,
            actor
        )
        RETURNING id INTO created_notification_id;

        INSERT INTO public.notification_recipients (notification_id, user_id)
        SELECT DISTINCT created_notification_id, assignment_recipients.user_id
        FROM public.assignment_recipients
        WHERE assignment_recipients.assignment_id = created_assignment.id
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN QUERY SELECT * FROM public.assignments WHERE id = created_assignment.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_assignment_read(input_assignment_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID;
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF NOT public.can_view_assignment(input_assignment_id, actor) THEN
        RAISE EXCEPTION 'You cannot view this assignment';
    END IF;

    INSERT INTO public.assignment_read_receipts (assignment_id, user_id, checked_at)
    VALUES (input_assignment_id, actor, NOW())
    ON CONFLICT (assignment_id, user_id)
    DO UPDATE SET checked_at = NOW();

    UPDATE public.assignment_recipients
    SET completion_status = 'read'
    WHERE assignment_id = input_assignment_id
      AND user_id = actor
      AND completion_status IN ('not_started', 'overdue');
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_assignment(
    input_assignment_id UUID,
    input_file_name TEXT DEFAULT NULL,
    input_file_path TEXT DEFAULT NULL,
    input_content_type TEXT DEFAULT NULL,
    input_feedback_text TEXT DEFAULT NULL
)
RETURNS SETOF public.assignment_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID;
    assignment_record public.assignments%ROWTYPE;
    saved_submission public.assignment_submissions%ROWTYPE;
    expected_prefix TEXT;
    created_notification_id UUID;
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT *
    INTO assignment_record
    FROM public.assignments
    WHERE id = input_assignment_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Assignment was not found';
    END IF;

    IF NOT public.can_submit_assignment(input_assignment_id, actor) THEN
        RAISE EXCEPTION 'You are not assigned to this assignment';
    END IF;

    IF input_file_path IS NOT NULL THEN
        expected_prefix := 'schools/'
            || assignment_record.school_id::TEXT
            || '/assignments/'
            || assignment_record.id::TEXT
            || '/submissions/'
            || actor::TEXT
            || '/';

        IF LOWER(input_file_path) NOT LIKE LOWER(expected_prefix) || '%' THEN
            RAISE EXCEPTION 'Assignment upload path is invalid';
        END IF;
    END IF;

    INSERT INTO public.assignment_submissions (
        assignment_id,
        school_id,
        submitted_by,
        status,
        reviewer_message,
        reviewed_by,
        reviewed_at,
        submitted_at
    )
    VALUES (
        assignment_record.id,
        assignment_record.school_id,
        actor,
        'submitted',
        NULL,
        NULL,
        NULL,
        NOW()
    )
    ON CONFLICT (assignment_id, submitted_by)
    DO UPDATE SET
        status = 'submitted',
        reviewer_message = NULL,
        reviewed_by = NULL,
        reviewed_at = NULL,
        submitted_at = NOW()
    RETURNING * INTO saved_submission;

    IF input_file_path IS NOT NULL THEN
        INSERT INTO public.assignment_submission_attachments (
            submission_id,
            school_id,
            private_file_path,
            file_name,
            content_type
        )
        VALUES (
            saved_submission.id,
            assignment_record.school_id,
            input_file_path,
            input_file_name,
            input_content_type
        );
    END IF;

    IF input_feedback_text IS NOT NULL AND btrim(input_feedback_text) <> '' THEN
        INSERT INTO public.assignment_feedback_messages (
            assignment_id,
            submission_id,
            school_id,
            sender_id,
            body
        )
        VALUES (
            assignment_record.id,
            saved_submission.id,
            assignment_record.school_id,
            actor,
            btrim(input_feedback_text)
        );
    END IF;

    UPDATE public.assignment_recipients
    SET completion_status = 'submitted'
    WHERE assignment_id = assignment_record.id
      AND user_id = actor;

    INSERT INTO public.notifications (
        school_id,
        title,
        body,
        category,
        source_type,
        source_id,
        created_by
    )
    VALUES (
        assignment_record.school_id,
        assignment_record.title,
        'Status: Submitted. Waiting for review.',
        'assignment_submitted',
        'assignment',
        assignment_record.id,
        actor
    )
    RETURNING id INTO created_notification_id;

    INSERT INTO public.notification_recipients (notification_id, user_id)
    SELECT DISTINCT created_notification_id, recipient_id
    FROM (
        SELECT assignment_record.assigned_by AS recipient_id
        UNION
        SELECT school_memberships.user_id
        FROM public.school_memberships
        WHERE assignment_record.assigned_by IS NULL
          AND school_memberships.school_id = assignment_record.school_id
          AND school_memberships.active = TRUE
          AND school_memberships.role IN ('school_director', 'hq_director')
    ) recipients
    WHERE recipient_id IS NOT NULL
      AND recipient_id <> actor
    ON CONFLICT DO NOTHING;

    RETURN QUERY SELECT * FROM public.assignment_submissions WHERE id = saved_submission.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_assignment_submission(
    input_submission_id UUID,
    input_status TEXT,
    input_reviewer_message TEXT DEFAULT NULL
)
RETURNS SETOF public.assignment_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID;
    submission_record public.assignment_submissions%ROWTYPE;
    assignment_record public.assignments%ROWTYPE;
    created_notification_id UUID;
    recipient_status TEXT;
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF input_status NOT IN ('submitted', 'accepted', 'flagged') THEN
        RAISE EXCEPTION 'Unsupported review status';
    END IF;

    SELECT *
    INTO submission_record
    FROM public.assignment_submissions
    WHERE id = input_submission_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Assignment submission was not found';
    END IF;

    SELECT *
    INTO assignment_record
    FROM public.assignments
    WHERE id = submission_record.assignment_id;

    IF NOT public.can_review_assignment(assignment_record.id, actor) THEN
        RAISE EXCEPTION 'Only directors can review assignment submissions';
    END IF;

    UPDATE public.assignment_submissions
    SET status = input_status,
        reviewer_message = input_reviewer_message,
        reviewed_by = actor,
        reviewed_at = NOW()
    WHERE id = input_submission_id
    RETURNING * INTO submission_record;

    recipient_status := CASE
        WHEN input_status = 'accepted' THEN 'accepted'
        WHEN input_status = 'flagged' THEN 'flagged'
        ELSE 'reviewed'
    END;

    UPDATE public.assignment_recipients
    SET completion_status = recipient_status,
        completed_at = CASE WHEN input_status = 'accepted' THEN NOW() ELSE completed_at END
    WHERE assignment_id = assignment_record.id
      AND user_id = submission_record.submitted_by;

    INSERT INTO public.notifications (
        school_id,
        title,
        body,
        category,
        source_type,
        source_id,
        created_by
    )
    VALUES (
        assignment_record.school_id,
        assignment_record.title,
        'Status: ' || initcap(input_status) || COALESCE('. ' || NULLIF(input_reviewer_message, ''), '.'),
        'assignment_reviewed',
        'assignment',
        assignment_record.id,
        actor
    )
    RETURNING id INTO created_notification_id;

    INSERT INTO public.notification_recipients (notification_id, user_id)
    VALUES (created_notification_id, submission_record.submitted_by)
    ON CONFLICT DO NOTHING;

    RETURN QUERY SELECT * FROM public.assignment_submissions WHERE id = submission_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fetch_assignment_inbox(
    input_school_id UUID,
    input_categories TEXT[] DEFAULT NULL
)
RETURNS TABLE (
    assignment_id UUID,
    school_id UUID,
    child_id UUID,
    title TEXT,
    description TEXT,
    category TEXT,
    due_at TIMESTAMPTZ,
    assigned_by UUID,
    created_at TIMESTAMPTZ,
    completion_status TEXT,
    submitted_at TIMESTAMPTZ,
    review_status TEXT,
    reviewed_at TIMESTAMPTZ,
    reviewer_message TEXT,
    child_first_name TEXT,
    child_last_name TEXT,
    material_count BIGINT,
    submission_count BIGINT,
    recipient_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        assignments.id AS assignment_id,
        assignments.school_id,
        assignments.child_id,
        assignments.title,
        assignments.description,
        assignments.category,
        assignments.due_at,
        assignments.assigned_by,
        assignments.created_at,
        COALESCE(assignment_recipients.completion_status, 'not_started') AS completion_status,
        assignment_submissions.submitted_at,
        assignment_submissions.status AS review_status,
        assignment_submissions.reviewed_at,
        assignment_submissions.reviewer_message,
        children.first_name AS child_first_name,
        children.last_name AS child_last_name,
        (SELECT COUNT(*) FROM public.assignment_materials WHERE assignment_materials.assignment_id = assignments.id) AS material_count,
        (SELECT COUNT(*) FROM public.assignment_submissions WHERE assignment_submissions.assignment_id = assignments.id) AS submission_count,
        (SELECT COUNT(*) FROM public.assignment_recipients WHERE assignment_recipients.assignment_id = assignments.id) AS recipient_count
    FROM public.assignments
    LEFT JOIN public.assignment_recipients
      ON assignment_recipients.assignment_id = assignments.id
     AND assignment_recipients.user_id = auth.uid()
    LEFT JOIN public.assignment_submissions
      ON assignment_submissions.assignment_id = assignments.id
     AND assignment_submissions.submitted_by = auth.uid()
    LEFT JOIN public.children
      ON children.id = assignments.child_id
    WHERE assignments.school_id = input_school_id
      AND assignments.status = 'active'
      AND (input_categories IS NULL OR array_length(input_categories, 1) IS NULL OR assignments.category = ANY(input_categories))
      AND public.can_view_assignment(assignments.id, auth.uid())
    ORDER BY assignments.due_at NULLS LAST, assignments.created_at DESC;
$$;

-- PostgreSQL cannot replace a function when OUT parameters change its row type.
-- Keep this drop before the legacy/base definition as well as the Phase 2
-- definition below so the complete schema remains safe to rerun.
DROP FUNCTION IF EXISTS public.fetch_assignment_review_queue(UUID, TEXT[]);

CREATE FUNCTION public.fetch_assignment_review_queue(
    input_school_id UUID,
    input_categories TEXT[] DEFAULT NULL
)
RETURNS TABLE (
    assignment_id UUID,
    school_id UUID,
    child_id UUID,
    title TEXT,
    description TEXT,
    category TEXT,
    due_at TIMESTAMPTZ,
    assigned_by UUID,
    created_at TIMESTAMPTZ,
    completion_status TEXT,
    submitted_at TIMESTAMPTZ,
    review_status TEXT,
    reviewed_at TIMESTAMPTZ,
    reviewer_message TEXT,
    child_first_name TEXT,
    child_last_name TEXT,
    material_count BIGINT,
    submission_count BIGINT,
    recipient_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        assignments.id AS assignment_id,
        assignments.school_id,
        assignments.child_id,
        assignments.title,
        assignments.description,
        assignments.category,
        assignments.due_at,
        assignments.assigned_by,
        assignments.created_at,
        CASE
            WHEN COUNT(assignment_submissions.id) FILTER (WHERE assignment_submissions.status = 'flagged') > 0 THEN 'flagged'
            WHEN COUNT(assignment_submissions.id) FILTER (WHERE assignment_submissions.status = 'accepted') = COUNT(assignment_recipients.user_id)
                 AND COUNT(assignment_recipients.user_id) > 0 THEN 'accepted'
            WHEN COUNT(assignment_submissions.id) > 0 THEN 'submitted'
            ELSE 'not_started'
        END AS completion_status,
        MAX(assignment_submissions.submitted_at) AS submitted_at,
        NULL::TEXT AS review_status,
        MAX(assignment_submissions.reviewed_at) AS reviewed_at,
        NULL::TEXT AS reviewer_message,
        children.first_name AS child_first_name,
        children.last_name AS child_last_name,
        (SELECT COUNT(*) FROM public.assignment_materials WHERE assignment_materials.assignment_id = assignments.id) AS material_count,
        COUNT(DISTINCT assignment_submissions.id) AS submission_count,
        COUNT(DISTINCT assignment_recipients.user_id) AS recipient_count
    FROM public.assignments
    LEFT JOIN public.assignment_recipients
      ON assignment_recipients.assignment_id = assignments.id
    LEFT JOIN public.assignment_submissions
      ON assignment_submissions.assignment_id = assignments.id
    LEFT JOIN public.children
      ON children.id = assignments.child_id
    WHERE assignments.school_id = input_school_id
      AND assignments.status = 'active'
      AND (input_categories IS NULL OR array_length(input_categories, 1) IS NULL OR assignments.category = ANY(input_categories))
      AND public.can_review_assignment(assignments.id, auth.uid())
    GROUP BY assignments.id, children.first_name, children.last_name
    ORDER BY MAX(assignment_submissions.submitted_at) DESC NULLS LAST, assignments.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.create_medication_instruction(
    school_id UUID,
    child_id UUID,
    title TEXT,
    dosage TEXT DEFAULT NULL,
    instructions TEXT DEFAULT NULL,
    scheduled_at TIMESTAMPTZ DEFAULT NOW()
)
RETURNS SETOF public.medication_instructions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID;
    created_instruction public.medication_instructions%ROWTYPE;
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.children
        WHERE id = $2
          AND school_id = $1
          AND public.can_access_child(id, actor)
    ) THEN
        RAISE EXCEPTION 'You cannot create medication instructions for this child';
    END IF;

    IF NULLIF(TRIM($3), '') IS NULL THEN
        RAISE EXCEPTION 'Medication title is required';
    END IF;

    INSERT INTO public.medication_instructions (
        school_id,
        child_id,
        title,
        dosage,
        instructions,
        scheduled_at,
        created_by
    )
    VALUES ($1, $2, TRIM($3), NULLIF(TRIM($4), ''), NULLIF(TRIM($5), ''), $6, actor)
    RETURNING * INTO created_instruction;

    INSERT INTO public.medication_tasks (school_id, child_id, instruction_id, due_at, status)
    VALUES ($1, $2, created_instruction.id, $6, 'pending');

    INSERT INTO public.notifications (school_id, title, body, category, source_type, source_id, created_by)
    VALUES ($1, 'Medication instruction', TRIM($3), 'medicine_instruction', 'medication_instruction', created_instruction.id, actor);

    INSERT INTO public.notification_recipients (notification_id, user_id)
    SELECT notifications.id, school_memberships.user_id
    FROM public.notifications
    JOIN public.school_memberships
      ON school_memberships.school_id = notifications.school_id
     AND school_memberships.active = TRUE
     AND school_memberships.role IN ('teacher', 'school_director')
    WHERE notifications.source_id = created_instruction.id
      AND notifications.source_type = 'medication_instruction'
    ON CONFLICT DO NOTHING;

    RETURN QUERY SELECT * FROM public.medication_instructions WHERE id = created_instruction.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.acknowledge_medication_task(
    task_id UUID,
    dosage_given TEXT DEFAULT NULL,
    notes TEXT DEFAULT NULL,
    given_at TIMESTAMPTZ DEFAULT NOW()
)
RETURNS SETOF public.medication_acknowledgements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID;
    task_record public.medication_tasks%ROWTYPE;
    saved_ack public.medication_acknowledgements%ROWTYPE;
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT *
    INTO task_record
    FROM public.medication_tasks
    WHERE id = $1
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Medication task was not found';
    END IF;

    IF NOT public.has_school_role(task_record.school_id, actor, ARRAY['teacher', 'school_director', 'hq_director']) THEN
        RAISE EXCEPTION 'Only assigned school staff can acknowledge medication tasks';
    END IF;

    INSERT INTO public.medication_acknowledgements (
        task_id,
        school_id,
        child_id,
        acknowledged_by,
        dosage_given,
        notes,
        given_at
    )
    VALUES ($1, task_record.school_id, task_record.child_id, actor, NULLIF(TRIM($2), ''), NULLIF(TRIM($3), ''), $4)
    RETURNING * INTO saved_ack;

    UPDATE public.medication_tasks
    SET status = 'acknowledged'
    WHERE id = $1;

    INSERT INTO public.child_activity_logs (school_id, child_id, activity_type, notes, recorded_by, recorded_at)
    VALUES (
        task_record.school_id,
        task_record.child_id,
        'medication',
        CONCAT_WS(' ', 'Dosage:', NULLIF(TRIM($2), ''), NULLIF(TRIM($3), '')),
        actor,
        $4
    );

    RETURN QUERY SELECT * FROM public.medication_acknowledgements WHERE id = saved_ack.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.escalate_missed_medication_tasks()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    task_record RECORD;
    affected_count INTEGER := 0;
    created_notification UUID;
BEGIN
    FOR task_record IN
        SELECT *
        FROM public.medication_tasks
        WHERE status IN ('pending', 'due')
          AND due_at < NOW() - INTERVAL '15 minutes'
          AND NOT EXISTS (
              SELECT 1
              FROM public.medication_acknowledgements
              WHERE medication_acknowledgements.task_id = medication_tasks.id
          )
    LOOP
        UPDATE public.medication_tasks
        SET status = 'missed',
            escalated_at = NOW()
        WHERE id = task_record.id;

        INSERT INTO public.medication_escalations (task_id, school_id, child_id, reason)
        VALUES (task_record.id, task_record.school_id, task_record.child_id, 'Medication task was not acknowledged within 15 minutes')
        ON CONFLICT DO NOTHING;

        INSERT INTO public.notifications (school_id, title, body, category, source_type, source_id)
        VALUES (
            task_record.school_id,
            'Medication escalation',
            'A medication task was not acknowledged within 15 minutes.',
            'medication_escalation',
            'medication_task',
            task_record.id
        )
        RETURNING id INTO created_notification;

        INSERT INTO public.notification_recipients (notification_id, user_id)
        SELECT created_notification, user_id
        FROM public.school_memberships
        WHERE school_id = task_record.school_id
          AND active = TRUE
          AND role = 'school_director'
        ON CONFLICT DO NOTHING;

        affected_count := affected_count + 1;
    END LOOP;

    RETURN affected_count;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_child_for_current_parent(UUID, TEXT, TEXT, DATE) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_child_attendance(UUID, UUID, BOOLEAN, TIMESTAMPTZ, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_submit_onboarding_requirement(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_manage_onboarding_requirement(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_required_document(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_required_document(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_paperwork_assignment(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_assignment(UUID, TEXT, TEXT, TEXT, TEXT, UUID, TIMESTAMPTZ, BOOLEAN, UUID[], JSONB, TEXT, TIMESTAMPTZ, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_assignment_read(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_assignment(UUID, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_assignment_submission(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_assignment_inbox(UUID, TEXT[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_assignment_review_queue(UUID, TEXT[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_medication_instruction(UUID, UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.acknowledge_medication_task(UUID, TEXT, TEXT, TIMESTAMPTZ) TO authenticated;
GRANT EXECUTE ON FUNCTION public.escalate_missed_medication_tasks() TO authenticated;

CREATE OR REPLACE FUNCTION public.assign_child_to_default_classroom()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    classroom_uuid UUID;
BEGIN
    classroom_uuid := public.default_classroom_for_school(NEW.school_id);

    INSERT INTO public.classroom_children (classroom_id, child_id)
    VALUES (classroom_uuid, NEW.id)
    ON CONFLICT DO NOTHING;

    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS assign_child_to_default_classroom_trigger ON children;
CREATE TRIGGER assign_child_to_default_classroom_trigger
    AFTER INSERT ON children
    FOR EACH ROW EXECUTE FUNCTION public.assign_child_to_default_classroom();

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

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE community_posts;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE community_albums;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE medication_tasks;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

DO $$
BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE document_submissions;
EXCEPTION WHEN duplicate_object THEN NULL;
END $$;

ALTER TABLE chat_rooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE chat_participants ENABLE ROW LEVEL SECURITY;
ALTER TABLE profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE schools ENABLE ROW LEVEL SECURITY;
ALTER TABLE school_deletion_backups ENABLE ROW LEVEL SECURITY;
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
ALTER TABLE curriculum_read_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE training_assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE training_read_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE training_assignment_recipients ENABLE ROW LEVEL SECURITY;
ALTER TABLE training_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE assignments ENABLE ROW LEVEL SECURITY;
ALTER TABLE assignment_recipients ENABLE ROW LEVEL SECURITY;
ALTER TABLE assignment_materials ENABLE ROW LEVEL SECURITY;
ALTER TABLE assignment_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE assignment_submission_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE assignment_read_receipts ENABLE ROW LEVEL SECURITY;
ALTER TABLE assignment_feedback_messages ENABLE ROW LEVEL SECURITY;
ALTER TABLE role_invites ENABLE ROW LEVEL SECURITY;
ALTER TABLE classrooms ENABLE ROW LEVEL SECURITY;
ALTER TABLE classroom_children ENABLE ROW LEVEL SECURITY;
ALTER TABLE classroom_teachers ENABLE ROW LEVEL SECURITY;
ALTER TABLE child_medical_profiles ENABLE ROW LEVEL SECURITY;
ALTER TABLE child_emergency_contacts ENABLE ROW LEVEL SECURITY;
ALTER TABLE child_progress_reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE child_goals ENABLE ROW LEVEL SECURITY;
ALTER TABLE child_documents ENABLE ROW LEVEL SECURITY;
ALTER TABLE medication_instructions ENABLE ROW LEVEL SECURITY;
ALTER TABLE medication_tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE medication_acknowledgements ENABLE ROW LEVEL SECURITY;
ALTER TABLE medication_escalations ENABLE ROW LEVEL SECURITY;
ALTER TABLE onboarding_requirements ENABLE ROW LEVEL SECURITY;
ALTER TABLE document_submissions ENABLE ROW LEVEL SECURITY;
ALTER TABLE payment_setup_records ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_posts ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_albums ENABLE ROW LEVEL SECURITY;
ALTER TABLE community_album_media ENABLE ROW LEVEL SECURITY;
ALTER TABLE device_tokens ENABLE ROW LEVEL SECURITY;
ALTER TABLE queued_notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE firefly_reflections ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "School members can view schools" ON schools;
DROP POLICY IF EXISTS "HQ directors can manage schools" ON schools;
DROP POLICY IF EXISTS "HQ directors can view school deletion backups" ON school_deletion_backups;
DROP POLICY IF EXISTS "HQ directors can create school deletion backups" ON school_deletion_backups;
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

CREATE POLICY "HQ directors can view school deletion backups"
    ON school_deletion_backups FOR SELECT
    USING (public.is_hq_director(auth.uid()));

CREATE POLICY "HQ directors can create school deletion backups"
    ON school_deletion_backups FOR INSERT
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

DROP POLICY IF EXISTS "HQ can manage role invites" ON role_invites;
DROP POLICY IF EXISTS "Invitees can view own pending role invites" ON role_invites;

CREATE POLICY "HQ can manage role invites"
    ON role_invites FOR ALL
    USING (public.is_hq_director(auth.uid()))
    WITH CHECK (public.is_hq_director(auth.uid()));

CREATE POLICY "Invitees can view own pending role invites"
    ON role_invites FOR SELECT
    USING (
        lower(email) = lower(COALESCE(auth.jwt()->>'email', ''))
        AND status = 'pending'
    );

DROP POLICY IF EXISTS "Users can view rooms they are in" ON chat_rooms;
DROP POLICY IF EXISTS "Authenticated users can create rooms" ON chat_rooms;
DROP POLICY IF EXISTS "Room members can update rooms" ON chat_rooms;
DROP POLICY IF EXISTS "Room owners can delete rooms" ON chat_rooms;

CREATE POLICY "Users can view rooms they are in"
    ON chat_rooms FOR SELECT
    USING (
        public.is_chat_room_member(id, auth.uid())
        OR public.has_direct_school_role(school_id, auth.uid(), ARRAY['school_director'])
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
        OR public.has_direct_school_role(school_id, auth.uid(), ARRAY['school_director'])
    )
    WITH CHECK (
        public.is_chat_room_member(id, auth.uid())
        OR public.has_direct_school_role(school_id, auth.uid(), ARRAY['school_director'])
    );

CREATE POLICY "Room owners can delete rooms"
    ON chat_rooms FOR DELETE
    USING (
        public.is_chat_room_owner(id, auth.uid())
        OR public.has_direct_school_role(school_id, auth.uid(), ARRAY['school_director'])
    );

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
        OR public.has_direct_school_role(school_id, auth.uid(), ARRAY['school_director'])
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
    WITH CHECK (public.is_school_member(school_id, auth.uid()));

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
    USING (public.can_access_child(id, auth.uid()));

CREATE POLICY "Teachers and directors can manage children"
    ON children FOR ALL
    USING (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']))
    WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']));

CREATE POLICY "Users can view child guardians"
    ON child_guardians FOR SELECT
    USING (
        public.is_child_guardian(child_id, auth.uid())
        OR public.can_staff_access_child(child_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director'])
    );

CREATE POLICY "Directors can manage child guardians"
    ON child_guardians FOR ALL
    USING (public.can_staff_access_child(child_id, auth.uid(), ARRAY['school_director', 'hq_director']))
    WITH CHECK (public.can_staff_access_child(child_id, auth.uid(), ARRAY['school_director', 'hq_director']));

CREATE POLICY "Users can view child attendance"
    ON child_attendance FOR SELECT
    USING (public.can_access_child(child_id, auth.uid()));

CREATE POLICY "Teachers and directors can manage child attendance"
    ON child_attendance FOR ALL
    USING (public.can_staff_access_child(child_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director']))
    WITH CHECK (public.can_staff_access_child(child_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director']));

CREATE POLICY "Users can view child activity logs"
    ON child_activity_logs FOR SELECT
    USING (public.can_access_child(child_id, auth.uid()));

CREATE POLICY "Teachers and directors can create child activity logs"
    ON child_activity_logs FOR INSERT
    WITH CHECK (public.can_staff_access_child(child_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director']));

DROP POLICY IF EXISTS "School users can view classrooms" ON classrooms;
DROP POLICY IF EXISTS "Directors can manage classrooms" ON classrooms;
DROP POLICY IF EXISTS "School users can view classroom children" ON classroom_children;
DROP POLICY IF EXISTS "Directors can manage classroom children" ON classroom_children;
DROP POLICY IF EXISTS "School users can view classroom teachers" ON classroom_teachers;
DROP POLICY IF EXISTS "Directors can manage classroom teachers" ON classroom_teachers;

CREATE POLICY "School users can view classrooms"
    ON classrooms FOR SELECT
    USING (public.is_school_member(school_id, auth.uid()));

CREATE POLICY "Directors can manage classrooms"
    ON classrooms FOR ALL
    USING (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']))
    WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']));

CREATE POLICY "School users can view classroom children"
    ON classroom_children FOR SELECT
    USING (
        EXISTS (
            SELECT 1
            FROM classrooms
            WHERE classrooms.id = classroom_children.classroom_id
              AND public.is_school_member(classrooms.school_id, auth.uid())
        )
    );

CREATE POLICY "Directors can manage classroom children"
    ON classroom_children FOR ALL
    USING (
        EXISTS (
            SELECT 1
            FROM classrooms
            WHERE classrooms.id = classroom_children.classroom_id
              AND public.has_school_role(classrooms.school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM classrooms
            WHERE classrooms.id = classroom_children.classroom_id
              AND public.has_school_role(classrooms.school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
        )
    );

CREATE POLICY "School users can view classroom teachers"
    ON classroom_teachers FOR SELECT
    USING (
        teacher_id = auth.uid()
        OR EXISTS (
            SELECT 1
            FROM classrooms
            WHERE classrooms.id = classroom_teachers.classroom_id
              AND public.has_school_role(classrooms.school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
        )
    );

CREATE POLICY "Directors can manage classroom teachers"
    ON classroom_teachers FOR ALL
    USING (
        EXISTS (
            SELECT 1
            FROM classrooms
            WHERE classrooms.id = classroom_teachers.classroom_id
              AND public.has_school_role(classrooms.school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
        )
    )
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM classrooms
            WHERE classrooms.id = classroom_teachers.classroom_id
              AND public.has_school_role(classrooms.school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
        )
    );

DROP POLICY IF EXISTS "Users can view child medical profiles" ON child_medical_profiles;
DROP POLICY IF EXISTS "Users can update child medical profiles" ON child_medical_profiles;
DROP POLICY IF EXISTS "Users can view child emergency contacts" ON child_emergency_contacts;
DROP POLICY IF EXISTS "Users can manage child emergency contacts" ON child_emergency_contacts;
DROP POLICY IF EXISTS "Users can view child progress reports" ON child_progress_reports;
DROP POLICY IF EXISTS "Staff can manage child progress reports" ON child_progress_reports;
DROP POLICY IF EXISTS "Users can view child goals" ON child_goals;
DROP POLICY IF EXISTS "Staff can manage child goals" ON child_goals;
DROP POLICY IF EXISTS "Users can view child documents" ON child_documents;
DROP POLICY IF EXISTS "Users can upload child documents" ON child_documents;
DROP POLICY IF EXISTS "Directors can review child documents" ON child_documents;

CREATE POLICY "Users can view child medical profiles"
    ON child_medical_profiles FOR SELECT
    USING (public.can_access_child(child_id, auth.uid()));

CREATE POLICY "Users can update child medical profiles"
    ON child_medical_profiles FOR ALL
    USING (public.can_access_child(child_id, auth.uid()))
    WITH CHECK (public.can_access_child(child_id, auth.uid()));

CREATE POLICY "Users can view child emergency contacts"
    ON child_emergency_contacts FOR SELECT
    USING (public.can_access_child(child_id, auth.uid()));

CREATE POLICY "Users can manage child emergency contacts"
    ON child_emergency_contacts FOR ALL
    USING (
        public.is_child_guardian(child_id, auth.uid())
        OR public.can_staff_access_child(child_id, auth.uid(), ARRAY['school_director', 'hq_director'])
    )
    WITH CHECK (
        public.is_child_guardian(child_id, auth.uid())
        OR public.can_staff_access_child(child_id, auth.uid(), ARRAY['school_director', 'hq_director'])
    );

CREATE POLICY "Users can view child progress reports"
    ON child_progress_reports FOR SELECT
    USING (public.can_access_child(child_id, auth.uid()));

CREATE POLICY "Staff can manage child progress reports"
    ON child_progress_reports FOR ALL
    USING (public.can_staff_access_child(child_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director']))
    WITH CHECK (public.can_staff_access_child(child_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director']));

CREATE POLICY "Users can view child goals"
    ON child_goals FOR SELECT
    USING (public.can_access_child(child_id, auth.uid()));

CREATE POLICY "Staff can manage child goals"
    ON child_goals FOR ALL
    USING (public.can_staff_access_child(child_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director']))
    WITH CHECK (public.can_staff_access_child(child_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director']));

CREATE POLICY "Users can view child documents"
    ON child_documents FOR SELECT
    USING (public.can_access_child(child_id, auth.uid()));

CREATE POLICY "Users can upload child documents"
    ON child_documents FOR INSERT
    WITH CHECK (public.can_access_child(child_id, auth.uid()));

CREATE POLICY "Directors can review child documents"
    ON child_documents FOR UPDATE
    USING (public.can_staff_access_child(child_id, auth.uid(), ARRAY['school_director', 'hq_director']))
    WITH CHECK (public.can_staff_access_child(child_id, auth.uid(), ARRAY['school_director', 'hq_director']));

DROP POLICY IF EXISTS "Users can view medication instructions" ON medication_instructions;
DROP POLICY IF EXISTS "Users can manage medication instructions" ON medication_instructions;
DROP POLICY IF EXISTS "Users can view medication tasks" ON medication_tasks;
DROP POLICY IF EXISTS "Staff can update medication tasks" ON medication_tasks;
DROP POLICY IF EXISTS "Users can view medication acknowledgements" ON medication_acknowledgements;
DROP POLICY IF EXISTS "Staff can create medication acknowledgements" ON medication_acknowledgements;
DROP POLICY IF EXISTS "Directors can view medication escalations" ON medication_escalations;

CREATE POLICY "Users can view medication instructions"
    ON medication_instructions FOR SELECT
    USING (public.can_access_child(child_id, auth.uid()));

CREATE POLICY "Users can manage medication instructions"
    ON medication_instructions FOR ALL
    USING (public.can_access_child(child_id, auth.uid()))
    WITH CHECK (public.can_access_child(child_id, auth.uid()));

CREATE POLICY "Users can view medication tasks"
    ON medication_tasks FOR SELECT
    USING (public.can_access_child(child_id, auth.uid()));

CREATE POLICY "Staff can update medication tasks"
    ON medication_tasks FOR UPDATE
    USING (public.can_staff_access_child(child_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director']))
    WITH CHECK (public.can_staff_access_child(child_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director']));

CREATE POLICY "Users can view medication acknowledgements"
    ON medication_acknowledgements FOR SELECT
    USING (public.can_access_child(child_id, auth.uid()));

CREATE POLICY "Staff can create medication acknowledgements"
    ON medication_acknowledgements FOR INSERT
    WITH CHECK (public.can_staff_access_child(child_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director']));

CREATE POLICY "Directors can view medication escalations"
    ON medication_escalations FOR SELECT
    USING (
        public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
        OR public.is_child_guardian(child_id, auth.uid())
    );

DROP POLICY IF EXISTS "Users can view onboarding requirements" ON onboarding_requirements;
DROP POLICY IF EXISTS "Directors can manage onboarding requirements" ON onboarding_requirements;
DROP POLICY IF EXISTS "Users can view document submissions" ON document_submissions;
DROP POLICY IF EXISTS "Users can submit required documents" ON document_submissions;
DROP POLICY IF EXISTS "Directors can review required documents" ON document_submissions;

CREATE POLICY "Users can view onboarding requirements"
    ON onboarding_requirements FOR SELECT
    USING (
        public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
        OR public.can_submit_onboarding_requirement(id, auth.uid())
    );

CREATE POLICY "Directors can manage onboarding requirements"
    ON onboarding_requirements FOR ALL
    USING (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']))
    WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']));

CREATE POLICY "Users can view document submissions"
    ON document_submissions FOR SELECT
    USING (
        submitted_by = auth.uid()
        OR public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
    );

CREATE POLICY "Users can submit required documents"
    ON document_submissions FOR INSERT
    WITH CHECK (
        submitted_by = auth.uid()
        AND public.can_submit_onboarding_requirement(requirement_id, auth.uid())
    );

CREATE POLICY "Directors can review required documents"
    ON document_submissions FOR UPDATE
    USING (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']))
    WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']));

DROP POLICY IF EXISTS "Users can view payment setup records" ON payment_setup_records;
DROP POLICY IF EXISTS "Directors can manage payment setup records" ON payment_setup_records;

CREATE POLICY "Users can view payment setup records"
    ON payment_setup_records FOR SELECT
    USING (
        user_id = auth.uid()
        OR public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
    );

CREATE POLICY "Directors can manage payment setup records"
    ON payment_setup_records FOR ALL
    USING (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']))
    WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']));

DROP POLICY IF EXISTS "School members can view community posts" ON community_posts;
DROP POLICY IF EXISTS "Staff can manage community posts" ON community_posts;
DROP POLICY IF EXISTS "School members can view community albums" ON community_albums;
DROP POLICY IF EXISTS "Staff can manage community albums" ON community_albums;
DROP POLICY IF EXISTS "School members can view community album media" ON community_album_media;
DROP POLICY IF EXISTS "Staff can manage community album media" ON community_album_media;

CREATE POLICY "School members can view community posts"
    ON community_posts FOR SELECT
    USING (public.is_school_member(school_id, auth.uid()));

CREATE POLICY "Staff can manage community posts"
    ON community_posts FOR ALL
    USING (public.has_school_role(school_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director']))
    WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director']));

CREATE POLICY "School members can view community albums"
    ON community_albums FOR SELECT
    USING (public.is_school_member(school_id, auth.uid()));

CREATE POLICY "Staff can manage community albums"
    ON community_albums FOR ALL
    USING (public.has_school_role(school_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director']))
    WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director']));

CREATE POLICY "School members can view community album media"
    ON community_album_media FOR SELECT
    USING (public.is_school_member(school_id, auth.uid()));

CREATE POLICY "Staff can manage community album media"
    ON community_album_media FOR ALL
    USING (public.has_school_role(school_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director']))
    WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director']));

DROP POLICY IF EXISTS "Users can manage own device tokens" ON device_tokens;
DROP POLICY IF EXISTS "Users can view queued notifications" ON queued_notifications;
DROP POLICY IF EXISTS "Directors can manage queued notifications" ON queued_notifications;
DROP POLICY IF EXISTS "School users can view reflections" ON firefly_reflections;
DROP POLICY IF EXISTS "Directors can manage reflections" ON firefly_reflections;

CREATE POLICY "Users can manage own device tokens"
    ON device_tokens FOR ALL
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can view queued notifications"
    ON queued_notifications FOR SELECT
    USING (
        user_id = auth.uid()
        OR (school_id IS NOT NULL AND public.is_school_member(school_id, auth.uid()))
    );

CREATE POLICY "Directors can manage queued notifications"
    ON queued_notifications FOR ALL
    USING (
        school_id IS NOT NULL
        AND public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
    )
    WITH CHECK (
        school_id IS NOT NULL
        AND public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
    );

CREATE POLICY "School users can view reflections"
    ON firefly_reflections FOR SELECT
    USING (
        school_id IS NULL
        OR public.is_school_member(school_id, auth.uid())
    );

CREATE POLICY "Directors can manage reflections"
    ON firefly_reflections FOR ALL
    USING (
        school_id IS NULL
        OR public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
    )
    WITH CHECK (
        school_id IS NULL
        OR public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
    );

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
DROP POLICY IF EXISTS "Users can manage own curriculum read receipts" ON curriculum_read_receipts;
DROP POLICY IF EXISTS "Directors can view curriculum read receipts" ON curriculum_read_receipts;
DROP POLICY IF EXISTS "Users can view training assignments" ON training_assignments;
DROP POLICY IF EXISTS "Directors can manage training assignments" ON training_assignments;
DROP POLICY IF EXISTS "Users can manage own training read receipts" ON training_read_receipts;
DROP POLICY IF EXISTS "Directors can view training read receipts" ON training_read_receipts;
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

CREATE POLICY "Users can manage own curriculum read receipts"
    ON curriculum_read_receipts FOR ALL
    USING (user_id = auth.uid())
    WITH CHECK (
        user_id = auth.uid()
        AND EXISTS (
            SELECT 1
            FROM curriculum_resources
            WHERE curriculum_resources.id = curriculum_read_receipts.resource_id
              AND public.has_school_role(curriculum_resources.school_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director'])
        )
    );

CREATE POLICY "Directors can view curriculum read receipts"
    ON curriculum_read_receipts FOR SELECT
    USING (
        EXISTS (
            SELECT 1
            FROM curriculum_resources
            WHERE curriculum_resources.id = curriculum_read_receipts.resource_id
              AND public.has_school_role(curriculum_resources.school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
        )
    );

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

CREATE POLICY "Users can manage own training read receipts"
    ON training_read_receipts FOR ALL
    USING (user_id = auth.uid())
    WITH CHECK (
        user_id = auth.uid()
        AND EXISTS (
            SELECT 1
            FROM training_assignments
            WHERE training_assignments.id = training_read_receipts.assignment_id
              AND (
                  public.has_school_role(training_assignments.school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
                  OR public.is_training_assignment_recipient(training_assignments.id, auth.uid())
              )
        )
    );

CREATE POLICY "Directors can view training read receipts"
    ON training_read_receipts FOR SELECT
    USING (
        EXISTS (
            SELECT 1
            FROM training_assignments
            WHERE training_assignments.id = training_read_receipts.assignment_id
              AND public.has_school_role(training_assignments.school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
        )
    );

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

DROP POLICY IF EXISTS "Users can view assignments" ON assignments;
DROP POLICY IF EXISTS "Directors can manage assignments" ON assignments;
DROP POLICY IF EXISTS "Directors can create assignments" ON assignments;
DROP POLICY IF EXISTS "Assignment owners can update assignments" ON assignments;
DROP POLICY IF EXISTS "Assignment owners can delete assignments" ON assignments;
DROP POLICY IF EXISTS "Users can view assignment recipients" ON assignment_recipients;
DROP POLICY IF EXISTS "Directors can manage assignment recipients" ON assignment_recipients;
DROP POLICY IF EXISTS "Users can update own assignment recipient status" ON assignment_recipients;
DROP POLICY IF EXISTS "Users can view assignment materials" ON assignment_materials;
DROP POLICY IF EXISTS "Directors can manage assignment materials" ON assignment_materials;
DROP POLICY IF EXISTS "Users can view assignment submissions" ON assignment_submissions;
DROP POLICY IF EXISTS "Users can create assignment submissions" ON assignment_submissions;
DROP POLICY IF EXISTS "Directors can review assignment submissions" ON assignment_submissions;
DROP POLICY IF EXISTS "Users can view assignment submission attachments" ON assignment_submission_attachments;
DROP POLICY IF EXISTS "Users can create assignment submission attachments" ON assignment_submission_attachments;
DROP POLICY IF EXISTS "Users can manage own assignment read receipts" ON assignment_read_receipts;
DROP POLICY IF EXISTS "Directors can view assignment read receipts" ON assignment_read_receipts;
DROP POLICY IF EXISTS "Users can view assignment feedback" ON assignment_feedback_messages;
DROP POLICY IF EXISTS "Users can add assignment feedback" ON assignment_feedback_messages;

CREATE POLICY "Users can view assignments"
    ON assignments FOR SELECT
    USING (public.can_view_assignment(id, auth.uid()));

CREATE POLICY "Directors can create assignments"
    ON assignments FOR INSERT
    WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']));

CREATE POLICY "Assignment owners can update assignments"
    ON assignments FOR UPDATE
    USING (public.can_manage_assignment(id, auth.uid()))
    WITH CHECK (public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director']));

CREATE POLICY "Assignment owners can delete assignments"
    ON assignments FOR DELETE
    USING (public.can_manage_assignment(id, auth.uid()));

CREATE POLICY "Users can view assignment recipients"
    ON assignment_recipients FOR SELECT
    USING (
        user_id = auth.uid()
        OR public.can_manage_assignment(assignment_id, auth.uid())
        OR public.can_review_assignment(assignment_id, auth.uid())
        OR (
            child_id IS NOT NULL
            AND public.is_child_guardian(child_id, auth.uid())
        )
    );

CREATE POLICY "Directors can manage assignment recipients"
    ON assignment_recipients FOR ALL
    USING (public.can_manage_assignment(assignment_id, auth.uid()))
    WITH CHECK (public.can_manage_assignment(assignment_id, auth.uid()));

CREATE POLICY "Users can update own assignment recipient status"
    ON assignment_recipients FOR UPDATE
    USING (user_id = auth.uid())
    WITH CHECK (user_id = auth.uid());

CREATE POLICY "Users can view assignment materials"
    ON assignment_materials FOR SELECT
    USING (public.can_view_assignment(assignment_id, auth.uid()));

CREATE POLICY "Directors can manage assignment materials"
    ON assignment_materials FOR ALL
    USING (public.can_manage_assignment(assignment_id, auth.uid()))
    WITH CHECK (public.can_manage_assignment(assignment_id, auth.uid()));

CREATE POLICY "Users can view assignment submissions"
    ON assignment_submissions FOR SELECT
    USING (
        submitted_by = auth.uid()
        OR public.can_review_assignment(assignment_id, auth.uid())
    );

CREATE POLICY "Users can create assignment submissions"
    ON assignment_submissions FOR INSERT
    WITH CHECK (
        submitted_by = auth.uid()
        AND public.can_submit_assignment(assignment_id, auth.uid())
    );

CREATE POLICY "Directors can review assignment submissions"
    ON assignment_submissions FOR UPDATE
    USING (public.can_review_assignment(assignment_id, auth.uid()))
    WITH CHECK (public.can_review_assignment(assignment_id, auth.uid()));

CREATE POLICY "Users can view assignment submission attachments"
    ON assignment_submission_attachments FOR SELECT
    USING (
        EXISTS (
            SELECT 1
            FROM public.assignment_submissions
            WHERE assignment_submissions.id = assignment_submission_attachments.submission_id
              AND (
                  assignment_submissions.submitted_by = auth.uid()
                  OR public.can_review_assignment(assignment_submissions.assignment_id, auth.uid())
              )
        )
    );

CREATE POLICY "Users can create assignment submission attachments"
    ON assignment_submission_attachments FOR INSERT
    WITH CHECK (
        EXISTS (
            SELECT 1
            FROM public.assignment_submissions
            WHERE assignment_submissions.id = assignment_submission_attachments.submission_id
              AND assignment_submissions.submitted_by = auth.uid()
        )
    );

CREATE POLICY "Users can manage own assignment read receipts"
    ON assignment_read_receipts FOR ALL
    USING (user_id = auth.uid())
    WITH CHECK (
        user_id = auth.uid()
        AND public.can_view_assignment(assignment_id, auth.uid())
    );

CREATE POLICY "Directors can view assignment read receipts"
    ON assignment_read_receipts FOR SELECT
    USING (public.can_review_assignment(assignment_id, auth.uid()));

CREATE POLICY "Users can view assignment feedback"
    ON assignment_feedback_messages FOR SELECT
    USING (
        public.can_submit_assignment(assignment_id, auth.uid())
        OR public.can_review_assignment(assignment_id, auth.uid())
    );

CREATE POLICY "Users can add assignment feedback"
    ON assignment_feedback_messages FOR INSERT
    WITH CHECK (
        sender_id = auth.uid()
        AND (
            public.can_submit_assignment(assignment_id, auth.uid())
            OR public.can_manage_assignment(assignment_id, auth.uid())
        )
    );

INSERT INTO public.assignments (
    id,
    school_id,
    title,
    description,
    category,
    audience_role,
    assigned_by,
    due_at,
    status,
    visibility,
    requires_review,
    legacy_source_type,
    legacy_source_id,
    created_at
)
SELECT
    id,
    school_id,
    title,
    description,
    'paperwork',
    'parent',
    assigned_by,
    due_at,
    'active',
    'assigned',
    TRUE,
    'paperwork_assignment',
    id,
    created_at
FROM public.paperwork_assignments
ON CONFLICT DO NOTHING;

INSERT INTO public.assignments (
    id,
    school_id,
    title,
    description,
    category,
    audience_role,
    assigned_by,
    due_at,
    status,
    visibility,
    requires_review,
    legacy_source_type,
    legacy_source_id,
    created_at
)
SELECT
    id,
    school_id,
    title,
    description,
    'training',
    'teacher',
    assigned_by,
    due_at,
    'active',
    'assigned',
    TRUE,
    'training_assignment',
    id,
    created_at
FROM public.training_assignments
ON CONFLICT DO NOTHING;

INSERT INTO public.assignments (
    id,
    school_id,
    title,
    description,
    category,
    audience_role,
    assigned_by,
    due_at,
    status,
    visibility,
    requires_review,
    legacy_source_type,
    legacy_source_id,
    created_at,
    updated_at
)
SELECT
    id,
    school_id,
    title,
    description,
    'curriculum',
    'teacher',
    uploaded_by,
    NULL,
    'active',
    'assigned',
    TRUE,
    'curriculum_resource',
    id,
    created_at,
    updated_at
FROM public.curriculum_resources
ON CONFLICT DO NOTHING;

INSERT INTO public.assignments (
    id,
    school_id,
    title,
    description,
    category,
    audience_role,
    assigned_by,
    due_at,
    status,
    visibility,
    requires_review,
    legacy_source_type,
    legacy_source_id,
    created_at
)
SELECT
    id,
    school_id,
    title,
    description,
    CASE
        WHEN requirement_type IN ('contract', 'document') THEN 'onboarding'
        ELSE 'compliance'
    END,
    target_role,
    assigned_by,
    due_at,
    'active',
    'assigned',
    TRUE,
    'onboarding_requirement',
    id,
    created_at
FROM public.onboarding_requirements
ON CONFLICT DO NOTHING;

INSERT INTO public.assignment_recipients (
    assignment_id,
    user_id,
    role_at_assignment,
    completion_status,
    created_at
)
SELECT
    paperwork_assignment_recipients.assignment_id,
    paperwork_assignment_recipients.parent_id,
    school_memberships.role,
    'not_started',
    paperwork_assignment_recipients.created_at
FROM public.paperwork_assignment_recipients
JOIN public.paperwork_assignments
  ON paperwork_assignments.id = paperwork_assignment_recipients.assignment_id
LEFT JOIN public.school_memberships
  ON school_memberships.school_id = paperwork_assignments.school_id
 AND school_memberships.user_id = paperwork_assignment_recipients.parent_id
 AND school_memberships.active = TRUE
ON CONFLICT DO NOTHING;

INSERT INTO public.assignment_recipients (
    assignment_id,
    user_id,
    role_at_assignment,
    completion_status,
    created_at
)
SELECT
    training_assignment_recipients.assignment_id,
    training_assignment_recipients.teacher_id,
    school_memberships.role,
    'not_started',
    training_assignment_recipients.created_at
FROM public.training_assignment_recipients
JOIN public.training_assignments
  ON training_assignments.id = training_assignment_recipients.assignment_id
LEFT JOIN public.school_memberships
  ON school_memberships.school_id = training_assignments.school_id
 AND school_memberships.user_id = training_assignment_recipients.teacher_id
 AND school_memberships.active = TRUE
ON CONFLICT DO NOTHING;

INSERT INTO public.assignment_recipients (
    assignment_id,
    user_id,
    role_at_assignment,
    completion_status
)
SELECT
    curriculum_resources.id,
    school_memberships.user_id,
    school_memberships.role,
    CASE WHEN curriculum_read_receipts.user_id IS NULL THEN 'not_started' ELSE 'read' END
FROM public.curriculum_resources
JOIN public.school_memberships
  ON school_memberships.school_id = curriculum_resources.school_id
 AND school_memberships.active = TRUE
 AND school_memberships.role IN ('teacher', 'school_director')
LEFT JOIN public.curriculum_read_receipts
  ON curriculum_read_receipts.resource_id = curriculum_resources.id
 AND curriculum_read_receipts.user_id = school_memberships.user_id
ON CONFLICT DO NOTHING;

INSERT INTO public.assignment_recipients (
    assignment_id,
    user_id,
    role_at_assignment,
    completion_status
)
SELECT
    onboarding_requirements.id,
    school_memberships.user_id,
    school_memberships.role,
    'not_started'
FROM public.onboarding_requirements
JOIN public.school_memberships
  ON school_memberships.school_id = onboarding_requirements.school_id
 AND school_memberships.active = TRUE
 AND (
      onboarding_requirements.target_user_id = school_memberships.user_id
      OR (
          onboarding_requirements.target_user_id IS NULL
          AND onboarding_requirements.target_role = school_memberships.role
      )
 )
ON CONFLICT DO NOTHING;

INSERT INTO public.assignment_materials (
    assignment_id,
    material_type,
    title,
    private_file_path,
    file_name,
    content_type
)
SELECT id, 'file', file_name, file_path, file_name, NULL
FROM public.paperwork_assignments
WHERE file_path IS NOT NULL
ON CONFLICT DO NOTHING;

INSERT INTO public.assignment_materials (
    assignment_id,
    material_type,
    title,
    private_file_path,
    file_name,
    content_type
)
SELECT id, COALESCE(material_type, 'file'), file_name, file_path, file_name, NULL
FROM public.training_assignments
WHERE file_path IS NOT NULL
ON CONFLICT DO NOTHING;

INSERT INTO public.assignment_materials (
    assignment_id,
    material_type,
    title,
    url,
    private_file_path,
    file_name,
    content_type
)
SELECT id, COALESCE(material_type, 'file'), file_name, material_url, file_path, file_name, NULL
FROM public.curriculum_resources
WHERE file_path IS NOT NULL OR material_url IS NOT NULL
ON CONFLICT DO NOTHING;

INSERT INTO public.assignment_materials (
    assignment_id,
    material_type,
    title,
    private_file_path,
    file_name,
    content_type
)
SELECT id, 'file', file_name, file_path, file_name, NULL
FROM public.onboarding_requirements
WHERE file_path IS NOT NULL
ON CONFLICT DO NOTHING;

INSERT INTO public.assignment_submissions (
    id,
    assignment_id,
    school_id,
    submitted_by,
    status,
    reviewer_message,
    reviewed_by,
    reviewed_at,
    submitted_at
)
SELECT
    id,
    assignment_id,
    school_id,
    submitted_by,
    CASE WHEN status = 'accepted' THEN 'accepted' WHEN status = 'flagged' THEN 'flagged' ELSE 'submitted' END,
    flag_reason,
    reviewed_by,
    reviewed_at,
    submitted_at
FROM public.paperwork_submissions
ON CONFLICT DO NOTHING;

INSERT INTO public.assignment_submissions (
    id,
    assignment_id,
    school_id,
    submitted_by,
    status,
    reviewer_message,
    reviewed_by,
    reviewed_at,
    submitted_at
)
SELECT
    id,
    assignment_id,
    school_id,
    submitted_by,
    CASE WHEN status = 'accepted' THEN 'accepted' WHEN status = 'flagged' THEN 'flagged' ELSE 'submitted' END,
    flag_reason,
    reviewed_by,
    reviewed_at,
    submitted_at
FROM public.training_submissions
ON CONFLICT DO NOTHING;

INSERT INTO public.assignment_submissions (
    id,
    assignment_id,
    school_id,
    submitted_by,
    status,
    reviewer_message,
    reviewed_by,
    reviewed_at,
    submitted_at
)
SELECT
    id,
    requirement_id,
    school_id,
    submitted_by,
    CASE WHEN status = 'verified' THEN 'accepted' WHEN status = 'flagged' THEN 'flagged' ELSE 'submitted' END,
    reviewer_message,
    reviewed_by,
    reviewed_at,
    submitted_at
FROM public.document_submissions
ON CONFLICT DO NOTHING;

INSERT INTO public.assignment_submission_attachments (
    submission_id,
    school_id,
    private_file_path,
    file_name,
    content_type
)
SELECT id, school_id, file_path, file_name, NULL
FROM public.paperwork_submissions
WHERE file_path IS NOT NULL
ON CONFLICT DO NOTHING;

INSERT INTO public.assignment_submission_attachments (
    submission_id,
    school_id,
    private_file_path,
    file_name,
    content_type
)
SELECT id, school_id, file_path, file_name, NULL
FROM public.training_submissions
WHERE file_path IS NOT NULL
ON CONFLICT DO NOTHING;

INSERT INTO public.assignment_submission_attachments (
    submission_id,
    school_id,
    private_file_path,
    file_name,
    content_type
)
SELECT id, school_id, file_path, file_name, NULL
FROM public.document_submissions
WHERE file_path IS NOT NULL
ON CONFLICT DO NOTHING;

INSERT INTO public.assignment_read_receipts (assignment_id, user_id, checked_at)
SELECT resource_id, user_id, checked_at
FROM public.curriculum_read_receipts
ON CONFLICT (assignment_id, user_id) DO UPDATE SET checked_at = EXCLUDED.checked_at;

INSERT INTO public.assignment_read_receipts (assignment_id, user_id, checked_at)
SELECT assignment_id, user_id, checked_at
FROM public.training_read_receipts
ON CONFLICT (assignment_id, user_id) DO UPDATE SET checked_at = EXCLUDED.checked_at;

UPDATE public.assignment_recipients
SET completion_status = CASE
        WHEN latest.status = 'accepted' THEN 'accepted'
        WHEN latest.status = 'flagged' THEN 'flagged'
        ELSE 'submitted'
    END,
    completed_at = CASE WHEN latest.status = 'accepted' THEN latest.submitted_at ELSE assignment_recipients.completed_at END
FROM (
    SELECT DISTINCT ON (assignment_id, submitted_by)
        assignment_id,
        submitted_by,
        status,
        submitted_at
    FROM public.assignment_submissions
    ORDER BY assignment_id, submitted_by, submitted_at DESC
) latest
WHERE assignment_recipients.assignment_id = latest.assignment_id
  AND assignment_recipients.user_id = latest.submitted_by;

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

    IF category <> 'assignments'
       AND public.has_school_role(school_uuid, user_uuid, ARRAY['school_director', 'hq_director']) THEN
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
    ELSIF category = 'onboarding_requirements' THEN
        record_uuid := parts[4]::UUID;
        RETURN public.can_manage_onboarding_requirement(record_uuid, user_uuid)
            OR public.can_submit_onboarding_requirement(record_uuid, user_uuid);
    ELSIF category = 'document_submissions' THEN
        record_uuid := parts[4]::UUID;
        RETURN public.can_submit_onboarding_requirement(record_uuid, user_uuid)
            OR public.has_school_role(school_uuid, user_uuid, ARRAY['school_director', 'hq_director']);
    ELSIF category = 'child_documents' THEN
        record_uuid := parts[4]::UUID;
        RETURN public.can_access_child(record_uuid, user_uuid);
    ELSIF category = 'assignments' THEN
        IF array_length(parts, 1) < 5 THEN
            RETURN FALSE;
        END IF;
        record_uuid := parts[4]::UUID;
        IF parts[5] = 'submissions' THEN
            IF array_length(parts, 1) < 6 THEN
                RETURN FALSE;
            END IF;
            owner_uuid := parts[6]::UUID;
            RETURN owner_uuid = user_uuid
                OR public.can_manage_assignment(record_uuid, user_uuid);
        END IF;
        RETURN public.can_view_assignment(record_uuid, user_uuid);
    ELSIF category IN ('community_posts', 'community_albums') THEN
        RETURN public.is_school_member(school_uuid, user_uuid);
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

    IF category IN ('paperwork_assignments', 'curriculum_resources', 'training_assignments', 'onboarding_requirements') THEN
        RETURN public.has_school_role(school_uuid, user_uuid, ARRAY['school_director', 'hq_director']);
    END IF;

    IF category = 'assignments' THEN
        IF array_length(parts, 1) < 5 THEN
            RETURN FALSE;
        END IF;
        IF parts[5] = 'materials' THEN
            RETURN public.can_manage_assignment(parts[4]::UUID, user_uuid);
        ELSIF parts[5] = 'submissions' THEN
            IF array_length(parts, 1) < 6 THEN
                RETURN FALSE;
            END IF;
            owner_uuid := parts[6]::UUID;
            RETURN owner_uuid = user_uuid
                AND public.can_submit_assignment(parts[4]::UUID, user_uuid);
        END IF;
        RETURN FALSE;
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
    ELSIF category = 'document_submissions' THEN
        RETURN public.can_submit_onboarding_requirement(owner_uuid, user_uuid);
    ELSIF category = 'child_documents' THEN
        RETURN public.can_access_child(owner_uuid, user_uuid);
    ELSIF category IN ('community_posts', 'community_albums') THEN
        RETURN public.has_school_role(school_uuid, user_uuid, ARRAY['teacher', 'school_director', 'hq_director']);
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

INSERT INTO classrooms (school_id, name, is_default)
SELECT id, 'Default Classroom', TRUE
FROM schools
ON CONFLICT (school_id, name) DO UPDATE SET is_default = TRUE;

INSERT INTO classroom_children (classroom_id, child_id)
SELECT classrooms.id, children.id
FROM children
JOIN classrooms
  ON classrooms.school_id = children.school_id
 AND classrooms.is_default = TRUE
ON CONFLICT DO NOTHING;

INSERT INTO classroom_teachers (classroom_id, teacher_id)
SELECT classrooms.id, school_memberships.user_id
FROM school_memberships
JOIN classrooms
  ON classrooms.school_id = school_memberships.school_id
 AND classrooms.is_default = TRUE
WHERE school_memberships.role = 'teacher'
  AND school_memberships.active = TRUE
ON CONFLICT DO NOTHING;

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

-- Phase 2 unified work engine: lifecycle, immutable attempts, and persistent event history.
ALTER TABLE public.assignments
    ADD COLUMN IF NOT EXISTS publish_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS close_at TIMESTAMPTZ;

ALTER TABLE public.assignments
    DROP CONSTRAINT IF EXISTS assignments_status_check;

UPDATE public.assignments
SET status = 'published'
WHERE status = 'active';

ALTER TABLE public.assignments
    ALTER COLUMN status SET DEFAULT 'published',
    ADD CONSTRAINT assignments_status_check
    CHECK (status IN ('draft', 'scheduled', 'published', 'closed', 'archived'));

ALTER TABLE public.assignment_recipients
    DROP CONSTRAINT IF EXISTS assignment_recipients_completion_status_check;

ALTER TABLE public.assignment_recipients
    ADD CONSTRAINT assignment_recipients_completion_status_check
    CHECK (completion_status IN (
        'not_started', 'read', 'submitted', 'resubmitted', 'reviewed',
        'changes_requested', 'accepted', 'excused', 'flagged', 'overdue'
    ));

ALTER TABLE public.assignment_submissions
    ADD COLUMN IF NOT EXISTS attempt_number INTEGER,
    ADD COLUMN IF NOT EXISTS supersedes_submission_id UUID REFERENCES public.assignment_submissions(id) ON DELETE SET NULL;

UPDATE public.assignment_submissions
SET attempt_number = 1
WHERE attempt_number IS NULL;

ALTER TABLE public.assignment_submissions
    ALTER COLUMN attempt_number SET DEFAULT 1,
    ALTER COLUMN attempt_number SET NOT NULL,
    DROP CONSTRAINT IF EXISTS assignment_submissions_status_check,
    DROP CONSTRAINT IF EXISTS assignment_submissions_assignment_id_submitted_by_key;

ALTER TABLE public.assignment_submissions
    ADD CONSTRAINT assignment_submissions_status_check
    CHECK (status IN ('submitted', 'resubmitted', 'changes_requested', 'accepted', 'flagged'));

CREATE UNIQUE INDEX IF NOT EXISTS idx_assignment_submission_attempt
    ON public.assignment_submissions(assignment_id, submitted_by, attempt_number);

CREATE INDEX IF NOT EXISTS idx_assignment_submission_latest
    ON public.assignment_submissions(assignment_id, submitted_by, attempt_number DESC);

CREATE TABLE IF NOT EXISTS public.assignment_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id UUID NOT NULL REFERENCES public.assignments(id) ON DELETE CASCADE,
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    event_type TEXT NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_assignment_events_timeline
    ON public.assignment_events(assignment_id, created_at DESC);

CREATE OR REPLACE FUNCTION public.record_assignment_created_event()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    INSERT INTO public.assignment_events (assignment_id, school_id, actor_id, event_type)
    VALUES (NEW.id, NEW.school_id, COALESCE(NEW.assigned_by, auth.uid()), COALESCE(NEW.status, 'draft'));
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS assignment_created_event_trigger ON public.assignments;
CREATE TRIGGER assignment_created_event_trigger
    AFTER INSERT ON public.assignments
    FOR EACH ROW
    EXECUTE FUNCTION public.record_assignment_created_event();

ALTER TABLE public.assignment_events ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Assignment participants can view event history" ON public.assignment_events;
CREATE POLICY "Assignment participants can view event history"
    ON public.assignment_events FOR SELECT
    USING (public.can_view_assignment(assignment_id, auth.uid()));

CREATE OR REPLACE FUNCTION public.can_submit_assignment(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.assignments
        WHERE id = assignment_uuid
          AND (
              status = 'published'
              OR (status = 'scheduled' AND publish_at <= NOW())
          )
          AND (close_at IS NULL OR close_at >= NOW())
          AND (
              public.is_assignment_recipient(id, user_uuid)
              OR (
                  child_id IS NOT NULL
                  AND public.is_child_guardian(child_id, user_uuid)
              )
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.can_review_assignment(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.assignments
        WHERE id = assignment_uuid
          AND NOT EXISTS (
              SELECT 1
              FROM public.assignment_recipients
              WHERE assignment_recipients.assignment_id = assignments.id
                AND assignment_recipients.user_id = user_uuid
          )
          AND NOT EXISTS (
              SELECT 1
              FROM public.assignment_submissions
              WHERE assignment_submissions.assignment_id = assignments.id
                AND assignment_submissions.submitted_by = user_uuid
          )
          AND (
              public.has_school_role(school_id, user_uuid, ARRAY['hq_director'])
              OR public.has_school_role(school_id, user_uuid, ARRAY['school_director'])
          )
    );
$$;

-- Reviewers must also be able to open the assignment returned by the
-- SECURITY DEFINER review queue. Without this, an HQ-created assignment can
-- appear in a school director's queue but disappear when its detail view uses
-- the assignments RLS policy.
CREATE OR REPLACE FUNCTION public.can_view_assignment(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.assignments
        WHERE id = assignment_uuid
          AND (
              public.has_school_role(school_id, user_uuid, ARRAY['hq_director'])
              OR assigned_by = user_uuid
              OR public.can_review_assignment(id, user_uuid)
              OR public.is_assignment_recipient(id, user_uuid)
              OR (
                  child_id IS NOT NULL
                  AND public.is_child_guardian(child_id, user_uuid)
              )
              OR (
                  category = 'child_record'
                  AND child_id IS NOT NULL
                  AND public.can_staff_access_child(child_id, user_uuid, ARRAY['teacher', 'school_director', 'hq_director'])
              )
              OR (
                  visibility = 'school'
                  AND public.is_school_member(school_id, user_uuid)
              )
              OR (
                  visibility = 'school_staff'
                  AND public.has_school_role(school_id, user_uuid, ARRAY['teacher', 'school_director', 'hq_director'])
              )
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.submit_assignment(
    input_assignment_id UUID,
    input_file_name TEXT DEFAULT NULL,
    input_file_path TEXT DEFAULT NULL,
    input_content_type TEXT DEFAULT NULL,
    input_feedback_text TEXT DEFAULT NULL
)
RETURNS SETOF public.assignment_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID;
    assignment_record public.assignments%ROWTYPE;
    saved_submission public.assignment_submissions%ROWTYPE;
    previous_submission public.assignment_submissions%ROWTYPE;
    next_attempt INTEGER;
    submission_status TEXT;
    expected_prefix TEXT;
    created_notification_id UUID;
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT * INTO assignment_record
    FROM public.assignments
    WHERE id = input_assignment_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Assignment was not found';
    END IF;

    IF NOT public.can_submit_assignment(input_assignment_id, actor) THEN
        RAISE EXCEPTION 'You are not assigned to this published assignment';
    END IF;

    SELECT * INTO previous_submission
    FROM public.assignment_submissions
    WHERE assignment_id = input_assignment_id
      AND submitted_by = actor
    ORDER BY attempt_number DESC, submitted_at DESC
    LIMIT 1;

    next_attempt := COALESCE(previous_submission.attempt_number, 0) + 1;
    submission_status := CASE WHEN next_attempt > 1 THEN 'resubmitted' ELSE 'submitted' END;

    IF input_file_path IS NOT NULL THEN
        expected_prefix := 'schools/'
            || assignment_record.school_id::TEXT
            || '/assignments/'
            || assignment_record.id::TEXT
            || '/submissions/'
            || actor::TEXT
            || '/';

        IF LOWER(input_file_path) NOT LIKE LOWER(expected_prefix) || '%' THEN
            RAISE EXCEPTION 'Assignment upload path is invalid';
        END IF;
    END IF;

    INSERT INTO public.assignment_submissions (
        assignment_id,
        school_id,
        submitted_by,
        attempt_number,
        supersedes_submission_id,
        status,
        submitted_at
    )
    VALUES (
        assignment_record.id,
        assignment_record.school_id,
        actor,
        next_attempt,
        previous_submission.id,
        submission_status,
        NOW()
    )
    RETURNING * INTO saved_submission;

    IF input_file_path IS NOT NULL THEN
        INSERT INTO public.assignment_submission_attachments (
            submission_id,
            school_id,
            private_file_path,
            file_name,
            content_type
        )
        VALUES (
            saved_submission.id,
            assignment_record.school_id,
            input_file_path,
            input_file_name,
            input_content_type
        );
    END IF;

    IF input_feedback_text IS NOT NULL AND btrim(input_feedback_text) <> '' THEN
        INSERT INTO public.assignment_feedback_messages (
            assignment_id,
            submission_id,
            school_id,
            sender_id,
            body
        )
        VALUES (
            assignment_record.id,
            saved_submission.id,
            assignment_record.school_id,
            actor,
            btrim(input_feedback_text)
        );
    END IF;

    UPDATE public.assignment_recipients
    SET completion_status = submission_status,
        completed_at = NULL
    WHERE assignment_id = assignment_record.id
      AND user_id = actor;

    INSERT INTO public.assignment_events (assignment_id, school_id, actor_id, event_type, metadata)
    VALUES (
        assignment_record.id,
        assignment_record.school_id,
        actor,
        submission_status,
        jsonb_build_object('submission_id', saved_submission.id, 'attempt_number', next_attempt)
    );

    INSERT INTO public.notifications (
        school_id, title, body, category, source_type, source_id, created_by
    )
    VALUES (
        assignment_record.school_id,
        assignment_record.title,
        'Status: ' || initcap(submission_status) || '. Waiting for review.',
        'assignment_submitted',
        'assignment',
        assignment_record.id,
        actor
    )
    RETURNING id INTO created_notification_id;

    INSERT INTO public.notification_recipients (notification_id, user_id)
    SELECT DISTINCT created_notification_id, recipient_id
    FROM (
        SELECT assignment_record.assigned_by AS recipient_id
        UNION
        SELECT school_memberships.user_id
        FROM public.school_memberships
        WHERE school_memberships.school_id = assignment_record.school_id
          AND school_memberships.active = TRUE
          AND school_memberships.role IN ('school_director', 'hq_director')
    ) recipients
    WHERE recipient_id IS NOT NULL
      AND recipient_id <> actor
    ON CONFLICT DO NOTHING;

    RETURN QUERY SELECT * FROM public.assignment_submissions WHERE id = saved_submission.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_assignment_submission(
    input_submission_id UUID,
    input_status TEXT,
    input_reviewer_message TEXT DEFAULT NULL
)
RETURNS SETOF public.assignment_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID;
    submission_record public.assignment_submissions%ROWTYPE;
    assignment_record public.assignments%ROWTYPE;
    created_notification_id UUID;
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF input_status NOT IN ('accepted', 'changes_requested') THEN
        RAISE EXCEPTION 'Review status must be accepted or changes_requested';
    END IF;

    SELECT * INTO submission_record
    FROM public.assignment_submissions
    WHERE id = input_submission_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Assignment submission was not found';
    END IF;

    SELECT * INTO assignment_record
    FROM public.assignments
    WHERE id = submission_record.assignment_id;

    IF NOT public.can_review_assignment(assignment_record.id, actor) THEN
        RAISE EXCEPTION 'Only a non-recipient director can review this submission';
    END IF;

    UPDATE public.assignment_submissions
    SET status = input_status,
        reviewer_message = NULLIF(btrim(COALESCE(input_reviewer_message, '')), ''),
        reviewed_by = actor,
        reviewed_at = NOW()
    WHERE id = input_submission_id
    RETURNING * INTO submission_record;

    UPDATE public.assignment_recipients
    SET completion_status = input_status,
        completed_at = CASE WHEN input_status = 'accepted' THEN NOW() ELSE NULL END
    WHERE assignment_id = assignment_record.id
      AND user_id = submission_record.submitted_by;

    IF input_reviewer_message IS NOT NULL AND btrim(input_reviewer_message) <> '' THEN
        INSERT INTO public.assignment_feedback_messages (
            assignment_id, submission_id, school_id, sender_id, body
        )
        VALUES (
            assignment_record.id,
            submission_record.id,
            assignment_record.school_id,
            actor,
            btrim(input_reviewer_message)
        );
    END IF;

    INSERT INTO public.assignment_events (assignment_id, school_id, actor_id, event_type, metadata)
    VALUES (
        assignment_record.id,
        assignment_record.school_id,
        actor,
        input_status,
        jsonb_build_object(
            'submission_id', submission_record.id,
            'recipient_id', submission_record.submitted_by,
            'attempt_number', submission_record.attempt_number
        )
    );

    INSERT INTO public.notifications (
        school_id, title, body, category, source_type, source_id, created_by
    )
    VALUES (
        assignment_record.school_id,
        assignment_record.title,
        'Status: ' || initcap(replace(input_status, '_', ' '))
            || COALESCE('. ' || NULLIF(btrim(input_reviewer_message), ''), '.'),
        'assignment_reviewed',
        'assignment',
        assignment_record.id,
        actor
    )
    RETURNING id INTO created_notification_id;

    INSERT INTO public.notification_recipients (notification_id, user_id)
    VALUES (created_notification_id, submission_record.submitted_by)
    ON CONFLICT DO NOTHING;

    RETURN QUERY SELECT * FROM public.assignment_submissions WHERE id = submission_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fetch_assignment_inbox(
    input_school_id UUID,
    input_categories TEXT[] DEFAULT NULL
)
RETURNS TABLE (
    assignment_id UUID,
    school_id UUID,
    child_id UUID,
    title TEXT,
    description TEXT,
    category TEXT,
    due_at TIMESTAMPTZ,
    assigned_by UUID,
    created_at TIMESTAMPTZ,
    completion_status TEXT,
    submitted_at TIMESTAMPTZ,
    review_status TEXT,
    reviewed_at TIMESTAMPTZ,
    reviewer_message TEXT,
    child_first_name TEXT,
    child_last_name TEXT,
    material_count BIGINT,
    submission_count BIGINT,
    recipient_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        assignments.id,
        assignments.school_id,
        assignments.child_id,
        assignments.title,
        assignments.description,
        assignments.category,
        assignments.due_at,
        assignments.assigned_by,
        assignments.created_at,
        COALESCE(assignment_recipients.completion_status, 'not_started'),
        latest_submission.submitted_at,
        latest_submission.status,
        latest_submission.reviewed_at,
        latest_submission.reviewer_message,
        children.first_name,
        children.last_name,
        (SELECT COUNT(*) FROM public.assignment_materials WHERE assignment_materials.assignment_id = assignments.id),
        (SELECT COUNT(DISTINCT submitted_by) FROM public.assignment_submissions WHERE assignment_submissions.assignment_id = assignments.id),
        (SELECT COUNT(*) FROM public.assignment_recipients WHERE assignment_recipients.assignment_id = assignments.id)
    FROM public.assignments
    LEFT JOIN public.assignment_recipients
      ON assignment_recipients.assignment_id = assignments.id
     AND assignment_recipients.user_id = auth.uid()
    LEFT JOIN LATERAL (
        SELECT submission.submitted_at, submission.status, submission.reviewed_at, submission.reviewer_message
        FROM public.assignment_submissions submission
        WHERE submission.assignment_id = assignments.id
          AND submission.submitted_by = auth.uid()
        ORDER BY submission.attempt_number DESC, submission.submitted_at DESC
        LIMIT 1
    ) latest_submission ON TRUE
    LEFT JOIN public.children ON children.id = assignments.child_id
    WHERE assignments.school_id = input_school_id
      AND (
          assignments.status = 'published'
          OR (assignments.status = 'scheduled' AND assignments.publish_at <= NOW())
      )
      AND (input_categories IS NULL OR array_length(input_categories, 1) IS NULL OR assignments.category = ANY(input_categories))
      AND public.can_view_assignment(assignments.id, auth.uid())
    ORDER BY assignments.due_at NULLS LAST, assignments.created_at DESC;
$$;

DROP FUNCTION IF EXISTS public.fetch_assignment_review_queue(UUID, TEXT[]);

CREATE FUNCTION public.fetch_assignment_review_queue(
    input_school_id UUID,
    input_categories TEXT[] DEFAULT NULL
)
RETURNS TABLE (
    assignment_id UUID,
    school_id UUID,
    child_id UUID,
    title TEXT,
    description TEXT,
    category TEXT,
    due_at TIMESTAMPTZ,
    assigned_by UUID,
    created_at TIMESTAMPTZ,
    completion_status TEXT,
    submitted_at TIMESTAMPTZ,
    review_status TEXT,
    reviewed_at TIMESTAMPTZ,
    reviewer_message TEXT,
    child_first_name TEXT,
    child_last_name TEXT,
    material_count BIGINT,
    submission_count BIGINT,
    recipient_count BIGINT,
    needs_review_count BIGINT,
    changes_requested_count BIGINT,
    not_started_count BIGINT,
    overdue_count BIGINT,
    complete_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    WITH latest_submissions AS (
        SELECT DISTINCT ON (assignment_id, submitted_by)
            assignment_id,
            submitted_by,
            status,
            submitted_at,
            reviewed_at
        FROM public.assignment_submissions
        ORDER BY assignment_id, submitted_by, attempt_number DESC, submitted_at DESC
    )
    SELECT
        assignments.id,
        assignments.school_id,
        assignments.child_id,
        assignments.title,
        assignments.description,
        assignments.category,
        assignments.due_at,
        assignments.assigned_by,
        assignments.created_at,
        CASE
            WHEN COUNT(latest_submissions.submitted_by) FILTER (WHERE latest_submissions.status IN ('changes_requested', 'flagged')) > 0 THEN 'changes_requested'
            WHEN COUNT(latest_submissions.submitted_by) FILTER (WHERE latest_submissions.status IN ('submitted', 'resubmitted')) > 0 THEN 'submitted'
            WHEN COUNT(latest_submissions.submitted_by) FILTER (WHERE latest_submissions.status = 'accepted') = COUNT(DISTINCT assignment_recipients.user_id)
                 AND COUNT(DISTINCT assignment_recipients.user_id) > 0 THEN 'accepted'
            ELSE 'not_started'
        END,
        MAX(latest_submissions.submitted_at),
        CASE
            WHEN COUNT(latest_submissions.submitted_by) FILTER (WHERE latest_submissions.status IN ('changes_requested', 'flagged')) > 0 THEN 'changes_requested'
            WHEN COUNT(latest_submissions.submitted_by) FILTER (WHERE latest_submissions.status IN ('submitted', 'resubmitted')) > 0 THEN 'submitted'
            WHEN COUNT(latest_submissions.submitted_by) FILTER (WHERE latest_submissions.status = 'accepted') > 0 THEN 'accepted'
            ELSE NULL
        END,
        MAX(latest_submissions.reviewed_at),
        NULL::TEXT,
        children.first_name,
        children.last_name,
        (SELECT COUNT(*) FROM public.assignment_materials WHERE assignment_materials.assignment_id = assignments.id),
        COUNT(DISTINCT latest_submissions.submitted_by),
        COUNT(DISTINCT assignment_recipients.user_id),
        COUNT(DISTINCT latest_submissions.submitted_by) FILTER (
            WHERE latest_submissions.status IN ('submitted', 'resubmitted')
        ),
        COUNT(DISTINCT latest_submissions.submitted_by) FILTER (
            WHERE latest_submissions.status IN ('changes_requested', 'flagged')
        ),
        GREATEST(
            COUNT(DISTINCT assignment_recipients.user_id) - COUNT(DISTINCT latest_submissions.submitted_by),
            0
        ),
        CASE
            WHEN assignments.due_at < NOW() THEN GREATEST(
                COUNT(DISTINCT assignment_recipients.user_id)
                    - COUNT(DISTINCT latest_submissions.submitted_by) FILTER (WHERE latest_submissions.status = 'accepted'),
                0
            )
            ELSE 0
        END,
        COUNT(DISTINCT latest_submissions.submitted_by) FILTER (
            WHERE latest_submissions.status = 'accepted'
        )
    FROM public.assignments
    LEFT JOIN public.assignment_recipients ON assignment_recipients.assignment_id = assignments.id
    LEFT JOIN latest_submissions ON latest_submissions.assignment_id = assignments.id
    LEFT JOIN public.children ON children.id = assignments.child_id
    WHERE assignments.school_id = input_school_id
      AND assignments.status <> 'archived'
      AND (input_categories IS NULL OR array_length(input_categories, 1) IS NULL OR assignments.category = ANY(input_categories))
      AND public.can_review_assignment(assignments.id, auth.uid())
    GROUP BY assignments.id, children.first_name, children.last_name
    ORDER BY MAX(latest_submissions.submitted_at) DESC NULLS LAST, assignments.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.set_assignment_status(
    input_assignment_id UUID,
    input_status TEXT
)
RETURNS SETOF public.assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID;
    assignment_record public.assignments%ROWTYPE;
    created_notification_id UUID;
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF input_status NOT IN ('published', 'closed', 'archived') THEN
        RAISE EXCEPTION 'Status must be published, closed, or archived';
    END IF;

    IF NOT public.can_manage_assignment(input_assignment_id, actor) THEN
        RAISE EXCEPTION 'You cannot manage this assignment';
    END IF;

    UPDATE public.assignments
    SET status = input_status,
        publish_at = CASE WHEN input_status = 'published' THEN COALESCE(publish_at, NOW()) ELSE publish_at END,
        updated_at = NOW()
    WHERE id = input_assignment_id
    RETURNING * INTO assignment_record;

    INSERT INTO public.assignment_events (assignment_id, school_id, actor_id, event_type)
    VALUES (assignment_record.id, assignment_record.school_id, actor, input_status);

    IF input_status = 'published' THEN
        INSERT INTO public.notifications (
            school_id, title, body, category, source_type, source_id, created_by
        )
        VALUES (
            assignment_record.school_id,
            assignment_record.title,
            CASE
                WHEN assignment_record.due_at IS NULL THEN 'No due date. Status: Not submitted.'
                ELSE 'Due ' || to_char(assignment_record.due_at AT TIME ZONE 'UTC', 'Mon DD, YYYY HH24:MI') || ' UTC. Status: Not submitted.'
            END,
            'assignment_assigned',
            'assignment',
            assignment_record.id,
            actor
        )
        RETURNING id INTO created_notification_id;

        INSERT INTO public.notification_recipients (notification_id, user_id)
        SELECT created_notification_id, user_id
        FROM public.assignment_recipients
        WHERE assignment_id = assignment_record.id
          AND user_id <> actor
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN QUERY SELECT * FROM public.assignments WHERE id = assignment_record.id;
END;
$$;

CREATE TABLE IF NOT EXISTS public.assignment_publish_jobs (
    actor_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    idempotency_key TEXT NOT NULL,
    assignment_ids UUID[] NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (actor_id, idempotency_key)
);

ALTER TABLE public.assignment_publish_jobs ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Directors can view own assignment publish jobs" ON public.assignment_publish_jobs;
CREATE POLICY "Directors can view own assignment publish jobs"
    ON public.assignment_publish_jobs FOR SELECT
    USING (actor_id = auth.uid());

CREATE OR REPLACE FUNCTION public.publish_assignments_batch(
    input_idempotency_key TEXT,
    input_requests JSONB
)
RETURNS TABLE (assignment_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID;
    request JSONB;
    created_assignment public.assignments%ROWTYPE;
    created_ids UUID[] := '{}'::UUID[];
    existing_ids UUID[];
    recipient_ids UUID[];
BEGIN
    actor := auth.uid();
    IF actor IS NULL OR NOT public.is_hq_director(actor) THEN
        RAISE EXCEPTION 'Only the headquarter director can publish across schools';
    END IF;

    IF input_idempotency_key IS NULL OR btrim(input_idempotency_key) = '' THEN
        RAISE EXCEPTION 'An idempotency key is required';
    END IF;

    SELECT assignment_ids INTO existing_ids
    FROM public.assignment_publish_jobs
    WHERE actor_id = actor
      AND idempotency_key = btrim(input_idempotency_key);

    IF existing_ids IS NOT NULL THEN
        RETURN QUERY SELECT unnest(existing_ids);
        RETURN;
    END IF;

    IF jsonb_typeof(input_requests) <> 'array' OR jsonb_array_length(input_requests) = 0 THEN
        RAISE EXCEPTION 'At least one school publication request is required';
    END IF;

    FOR request IN SELECT * FROM jsonb_array_elements(input_requests) LOOP
        SELECT COALESCE(array_agg(value::UUID), '{}'::UUID[])
        INTO recipient_ids
        FROM jsonb_array_elements_text(COALESCE(request->'recipient_ids', '[]'::JSONB));

        SELECT * INTO created_assignment
        FROM public.create_assignment(
            (request->>'school_id')::UUID,
            request->>'title',
            request->>'description',
            COALESCE(request->>'category', 'general'),
            NULLIF(request->>'audience_role', ''),
            NULLIF(request->>'child_id', '')::UUID,
            NULLIF(request->>'due_at', '')::TIMESTAMPTZ,
            COALESCE((request->>'requires_review')::BOOLEAN, TRUE),
            recipient_ids,
            COALESCE(request->'materials', '[]'::JSONB),
            COALESCE(request->>'status', 'published'),
            NULLIF(request->>'publish_at', '')::TIMESTAMPTZ,
            NULLIF(request->>'close_at', '')::TIMESTAMPTZ
        )
        LIMIT 1;

        created_ids := array_append(created_ids, created_assignment.id);
    END LOOP;

    INSERT INTO public.assignment_publish_jobs (actor_id, idempotency_key, assignment_ids)
    VALUES (actor, btrim(input_idempotency_key), created_ids);

    RETURN QUERY SELECT unnest(created_ids);
END;
$$;

GRANT SELECT ON public.assignment_events TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_submit_assignment(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_review_assignment(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_assignment(UUID, TEXT, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_assignment_submission(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_assignment_inbox(UUID, TEXT[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_assignment_review_queue(UUID, TEXT[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_assignment_status(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.publish_assignments_batch(TEXT, JSONB) TO authenticated;

-- Make newly created/updated RPC functions visible to PostgREST immediately.
NOTIFY pgrst, 'reload schema';

-- Simplified role-onboarding templates and backend-owned access gate.
-- A template requirement becomes a normal assignment when a matching member
-- joins the school, so the established submission, feedback, and audit loop is
-- reused instead of maintained in a parallel document system.

ALTER TABLE public.school_memberships
    ADD COLUMN IF NOT EXISTS access_state TEXT NOT NULL DEFAULT 'full';

ALTER TABLE public.school_memberships
    DROP CONSTRAINT IF EXISTS school_memberships_access_state_check;
ALTER TABLE public.school_memberships
    ADD CONSTRAINT school_memberships_access_state_check
    CHECK (access_state IN ('onboarding', 'full'));

CREATE TABLE IF NOT EXISTS public.onboarding_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    target_role TEXT NOT NULL CHECK (target_role IN ('parent', 'teacher', 'school_director')),
    name TEXT NOT NULL,
    version INTEGER NOT NULL DEFAULT 1 CHECK (version > 0),
    status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published', 'archived')),
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    published_at TIMESTAMPTZ,
    archived_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (school_id, target_role, version)
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_onboarding_templates_one_draft
    ON public.onboarding_templates(school_id, target_role)
    WHERE status = 'draft';
CREATE UNIQUE INDEX IF NOT EXISTS idx_onboarding_templates_one_published
    ON public.onboarding_templates(school_id, target_role)
    WHERE status = 'published';

CREATE TABLE IF NOT EXISTS public.onboarding_template_requirements (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    template_id UUID NOT NULL REFERENCES public.onboarding_templates(id) ON DELETE CASCADE,
    requirement_key UUID NOT NULL DEFAULT gen_random_uuid(),
    position INTEGER NOT NULL DEFAULT 0 CHECK (position >= 0),
    requirement_type TEXT NOT NULL DEFAULT 'document' CHECK (requirement_type IN ('document', 'acknowledgement', 'payment')),
    title TEXT NOT NULL,
    description TEXT,
    subject_scope TEXT NOT NULL DEFAULT 'member' CHECK (subject_scope IN ('member', 'child')),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (template_id, position)
);

ALTER TABLE public.onboarding_template_requirements
    ADD COLUMN IF NOT EXISTS requirement_key UUID NOT NULL DEFAULT gen_random_uuid(),
    ADD COLUMN IF NOT EXISTS requirement_type TEXT NOT NULL DEFAULT 'document';
ALTER TABLE public.onboarding_template_requirements
    DROP CONSTRAINT IF EXISTS onboarding_template_requirements_requirement_type_check;
ALTER TABLE public.onboarding_template_requirements
    ADD CONSTRAINT onboarding_template_requirements_requirement_type_check
    CHECK (requirement_type IN ('document', 'acknowledgement', 'payment'));
CREATE UNIQUE INDEX IF NOT EXISTS idx_onboarding_template_requirement_key
    ON public.onboarding_template_requirements(template_id, requirement_key);

CREATE TABLE IF NOT EXISTS public.onboarding_template_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    requirement_id UUID NOT NULL REFERENCES public.onboarding_template_requirements(id) ON DELETE CASCADE,
    position INTEGER NOT NULL DEFAULT 0 CHECK (position >= 0),
    private_file_path TEXT NOT NULL,
    file_name TEXT NOT NULL,
    content_type TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (requirement_id, position)
);

CREATE TABLE IF NOT EXISTS public.onboarding_instances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    membership_id UUID NOT NULL REFERENCES public.school_memberships(id) ON DELETE CASCADE,
    template_id UUID NOT NULL REFERENCES public.onboarding_templates(id) ON DELETE RESTRICT,
    status TEXT NOT NULL DEFAULT 'in_progress' CHECK (status IN ('in_progress', 'complete')),
    started_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    completed_at TIMESTAMPTZ,
    UNIQUE (membership_id, template_id)
);

CREATE TABLE IF NOT EXISTS public.onboarding_requirement_instances (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    onboarding_instance_id UUID NOT NULL REFERENCES public.onboarding_instances(id) ON DELETE CASCADE,
    template_requirement_id UUID NOT NULL REFERENCES public.onboarding_template_requirements(id) ON DELETE RESTRICT,
    assignment_id UUID REFERENCES public.assignments(id) ON DELETE SET NULL,
    child_id UUID REFERENCES public.children(id) ON DELETE CASCADE,
    status TEXT NOT NULL DEFAULT 'not_started' CHECK (
        status IN ('not_started', 'in_progress', 'in_review', 'changes_requested', 'approved', 'waived', 'overdue')
    ),
    waived_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    waiver_reason TEXT,
    completed_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.onboarding_requirement_instances
    DROP CONSTRAINT IF EXISTS onboarding_requirement_instances_assignment_id_key;

CREATE UNIQUE INDEX IF NOT EXISTS idx_onboarding_requirement_instance_member
    ON public.onboarding_requirement_instances(onboarding_instance_id, template_requirement_id)
    WHERE child_id IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_onboarding_requirement_instance_child
    ON public.onboarding_requirement_instances(onboarding_instance_id, template_requirement_id, child_id)
    WHERE child_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_onboarding_requirement_instance_assignment
    ON public.onboarding_requirement_instances(assignment_id)
    WHERE assignment_id IS NOT NULL;

ALTER TABLE public.onboarding_templates ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.onboarding_template_requirements ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.onboarding_template_attachments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.onboarding_instances ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.onboarding_requirement_instances ENABLE ROW LEVEL SECURITY;

CREATE OR REPLACE FUNCTION public.has_school_membership(school_uuid UUID, user_uuid UUID)
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

CREATE OR REPLACE FUNCTION public.has_full_school_access(school_uuid UUID, user_uuid UUID)
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
          AND access_state = 'full'
    );
$$;

CREATE OR REPLACE FUNCTION public.is_school_member(school_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.has_full_school_access(school_uuid, user_uuid);
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
          AND access_state = 'full'
          AND role = ANY(allowed_roles)
    );
$$;

CREATE OR REPLACE FUNCTION public.has_direct_school_role(school_uuid UUID, user_uuid UUID, allowed_roles TEXT[])
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.school_memberships
        WHERE school_id = school_uuid
          AND user_id = user_uuid
          AND active = TRUE
          AND access_state = 'full'
          AND role = ANY(allowed_roles)
    );
$$;

CREATE OR REPLACE FUNCTION public.is_onboarding_template_manager(
    template_school_id UUID,
    template_target_role TEXT,
    user_uuid UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT CASE
        WHEN template_target_role = 'school_director' THEN public.is_hq_director(user_uuid)
        WHEN template_target_role IN ('parent', 'teacher') THEN
            public.has_direct_school_role(template_school_id, user_uuid, ARRAY['school_director'])
        ELSE FALSE
    END;
$$;

DROP POLICY IF EXISTS "Onboarding managers can view templates" ON public.onboarding_templates;
CREATE POLICY "Onboarding managers can view templates"
    ON public.onboarding_templates FOR SELECT
    USING (public.is_onboarding_template_manager(school_id, target_role, auth.uid()));

DROP POLICY IF EXISTS "Onboarding managers can view template requirements" ON public.onboarding_template_requirements;
CREATE POLICY "Onboarding managers can view template requirements"
    ON public.onboarding_template_requirements FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.onboarding_templates templates
            WHERE templates.id = onboarding_template_requirements.template_id
              AND public.is_onboarding_template_manager(templates.school_id, templates.target_role, auth.uid())
        )
    );

DROP POLICY IF EXISTS "Onboarding managers can view template attachments" ON public.onboarding_template_attachments;
CREATE POLICY "Onboarding managers can view template attachments"
    ON public.onboarding_template_attachments FOR SELECT
    USING (
        EXISTS (
            SELECT 1
            FROM public.onboarding_template_requirements requirements
            JOIN public.onboarding_templates templates ON templates.id = requirements.template_id
            WHERE requirements.id = onboarding_template_attachments.requirement_id
              AND public.is_onboarding_template_manager(templates.school_id, templates.target_role, auth.uid())
        )
    );

DROP POLICY IF EXISTS "Users can view own onboarding instances" ON public.onboarding_instances;
CREATE POLICY "Users can view own onboarding instances"
    ON public.onboarding_instances FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.school_memberships memberships
            WHERE memberships.id = onboarding_instances.membership_id
              AND memberships.user_id = auth.uid()
        )
        OR EXISTS (
            SELECT 1 FROM public.onboarding_templates templates
            WHERE templates.id = onboarding_instances.template_id
              AND public.is_onboarding_template_manager(templates.school_id, templates.target_role, auth.uid())
        )
    );

DROP POLICY IF EXISTS "Users can view scoped onboarding requirements" ON public.onboarding_requirement_instances;
CREATE POLICY "Users can view scoped onboarding requirements"
    ON public.onboarding_requirement_instances FOR SELECT
    USING (
        EXISTS (
            SELECT 1
            FROM public.onboarding_instances instances
            JOIN public.school_memberships memberships ON memberships.id = instances.membership_id
            WHERE instances.id = onboarding_requirement_instances.onboarding_instance_id
              AND memberships.user_id = auth.uid()
        )
        OR (child_id IS NOT NULL AND public.is_child_guardian(child_id, auth.uid()))
        OR EXISTS (
            SELECT 1
            FROM public.onboarding_instances instances
            JOIN public.onboarding_templates templates ON templates.id = instances.template_id
            WHERE instances.id = onboarding_requirement_instances.onboarding_instance_id
              AND public.is_onboarding_template_manager(templates.school_id, templates.target_role, auth.uid())
        )
    );

CREATE OR REPLACE FUNCTION public.ensure_onboarding_template_draft(
    input_school_id UUID,
    input_target_role TEXT
)
RETURNS SETOF public.onboarding_templates
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    existing_draft public.onboarding_templates%ROWTYPE;
    published_template public.onboarding_templates%ROWTYPE;
    created_draft public.onboarding_templates%ROWTYPE;
    old_requirement RECORD;
    new_requirement_id UUID;
BEGIN
    IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    IF input_target_role NOT IN ('parent', 'teacher', 'school_director') THEN
        RAISE EXCEPTION 'Unsupported onboarding role';
    END IF;
    IF NOT public.is_onboarding_template_manager(input_school_id, input_target_role, actor) THEN
        RAISE EXCEPTION 'You cannot manage this onboarding template';
    END IF;

    SELECT * INTO existing_draft
    FROM public.onboarding_templates
    WHERE school_id = input_school_id
      AND target_role = input_target_role
      AND status = 'draft'
    LIMIT 1;
    IF FOUND THEN
        RETURN QUERY SELECT * FROM public.onboarding_templates WHERE id = existing_draft.id;
        RETURN;
    END IF;

    SELECT * INTO published_template
    FROM public.onboarding_templates
    WHERE school_id = input_school_id
      AND target_role = input_target_role
      AND status = 'published'
    ORDER BY version DESC
    LIMIT 1;

    INSERT INTO public.onboarding_templates (
        school_id, target_role, name, version, status, created_by
    ) VALUES (
        input_school_id,
        input_target_role,
        CASE input_target_role
            WHEN 'school_director' THEN 'School Director Onboarding'
            WHEN 'parent' THEN 'Parent Onboarding'
            ELSE 'Teacher Onboarding'
        END,
        (
            SELECT COALESCE(MAX(existing.version), 0) + 1
            FROM public.onboarding_templates existing
            WHERE existing.school_id = input_school_id
              AND existing.target_role = input_target_role
        ),
        'draft',
        actor
    ) RETURNING * INTO created_draft;

    IF published_template.id IS NOT NULL THEN
        FOR old_requirement IN
            SELECT * FROM public.onboarding_template_requirements
            WHERE template_id = published_template.id
            ORDER BY position
        LOOP
            INSERT INTO public.onboarding_template_requirements (
                template_id, requirement_key, position, requirement_type, title, description, subject_scope
            ) VALUES (
                created_draft.id,
                old_requirement.requirement_key,
                old_requirement.position,
                old_requirement.requirement_type,
                old_requirement.title,
                old_requirement.description,
                old_requirement.subject_scope
            ) RETURNING id INTO new_requirement_id;

            INSERT INTO public.onboarding_template_attachments (
                requirement_id, position, private_file_path, file_name, content_type
            )
            SELECT new_requirement_id, position, private_file_path, file_name, content_type
            FROM public.onboarding_template_attachments
            WHERE requirement_id = old_requirement.id
            ORDER BY position;
        END LOOP;
    END IF;

    RETURN QUERY SELECT * FROM public.onboarding_templates WHERE id = created_draft.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_onboarding_template_draft(input_template_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    template_record public.onboarding_templates%ROWTYPE;
BEGIN
    SELECT * INTO template_record
    FROM public.onboarding_templates
    WHERE id = input_template_id;

    IF NOT FOUND
       OR template_record.status <> 'draft'
       OR NOT public.is_onboarding_template_manager(template_record.school_id, template_record.target_role, actor) THEN
        RAISE EXCEPTION 'Only an authorized manager can delete an unused draft';
    END IF;
    IF EXISTS (
        SELECT 1 FROM public.onboarding_instances
        WHERE template_id = input_template_id
    ) THEN
        RAISE EXCEPTION 'A template used for onboarding must remain in the audit history';
    END IF;

    DELETE FROM public.onboarding_templates WHERE id = input_template_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.save_onboarding_template_requirement(
    input_template_id UUID,
    input_requirement_id UUID DEFAULT NULL,
    input_title TEXT DEFAULT NULL,
    input_description TEXT DEFAULT NULL,
    input_subject_scope TEXT DEFAULT 'member',
    input_position INTEGER DEFAULT 0,
    input_attachments JSONB DEFAULT '[]'::JSONB
)
RETURNS SETOF public.onboarding_template_requirements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    template_record public.onboarding_templates%ROWTYPE;
    saved_requirement public.onboarding_template_requirements%ROWTYPE;
BEGIN
    SELECT * INTO template_record FROM public.onboarding_templates WHERE id = input_template_id;
    IF NOT FOUND OR template_record.status <> 'draft' THEN
        RAISE EXCEPTION 'Requirements can only be changed in a draft template';
    END IF;
    IF NOT public.is_onboarding_template_manager(template_record.school_id, template_record.target_role, actor) THEN
        RAISE EXCEPTION 'You cannot manage this onboarding template';
    END IF;
    IF NULLIF(BTRIM(COALESCE(input_title, '')), '') IS NULL THEN
        RAISE EXCEPTION 'A requirement title is required';
    END IF;
    IF input_subject_scope NOT IN ('member', 'child')
       OR (input_subject_scope = 'child' AND template_record.target_role <> 'parent') THEN
        RAISE EXCEPTION 'Child requirements are available only for parent templates';
    END IF;

    IF input_requirement_id IS NULL THEN
        INSERT INTO public.onboarding_template_requirements (
            template_id, position, title, description, subject_scope
        ) VALUES (
            template_record.id,
            GREATEST(COALESCE(input_position, 0), 0),
            BTRIM(input_title),
            NULLIF(BTRIM(COALESCE(input_description, '')), ''),
            input_subject_scope
        ) RETURNING * INTO saved_requirement;
    ELSE
        UPDATE public.onboarding_template_requirements
        SET title = BTRIM(input_title),
            description = NULLIF(BTRIM(COALESCE(input_description, '')), ''),
            subject_scope = input_subject_scope,
            updated_at = NOW()
        WHERE id = input_requirement_id
          AND template_id = template_record.id
        RETURNING * INTO saved_requirement;
        IF saved_requirement.id IS NULL THEN RAISE EXCEPTION 'Requirement not found in this draft'; END IF;
    END IF;

    DELETE FROM public.onboarding_template_attachments
    WHERE requirement_id = saved_requirement.id;

    INSERT INTO public.onboarding_template_attachments (
        requirement_id, position, private_file_path, file_name, content_type
    )
    SELECT
        saved_requirement.id,
        attachment.ordinality::INTEGER - 1,
        attachment.value->>'private_file_path',
        attachment.value->>'file_name',
        NULLIF(attachment.value->>'content_type', '')
    FROM jsonb_array_elements(COALESCE(input_attachments, '[]'::JSONB)) WITH ORDINALITY AS attachment(value, ordinality)
    WHERE NULLIF(attachment.value->>'private_file_path', '') IS NOT NULL
      AND NULLIF(attachment.value->>'file_name', '') IS NOT NULL;

    RETURN QUERY SELECT * FROM public.onboarding_template_requirements WHERE id = saved_requirement.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.remove_onboarding_template_requirement(input_requirement_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    requirement_record public.onboarding_template_requirements%ROWTYPE;
    template_record public.onboarding_templates%ROWTYPE;
BEGIN
    SELECT * INTO requirement_record FROM public.onboarding_template_requirements WHERE id = input_requirement_id;
    SELECT * INTO template_record FROM public.onboarding_templates WHERE id = requirement_record.template_id;
    IF requirement_record.id IS NULL OR template_record.status <> 'draft'
       OR NOT public.is_onboarding_template_manager(template_record.school_id, template_record.target_role, actor) THEN
        RAISE EXCEPTION 'You cannot remove this requirement';
    END IF;
    DELETE FROM public.onboarding_template_requirements WHERE id = input_requirement_id;
    WITH ordered AS (
        SELECT id, ROW_NUMBER() OVER (ORDER BY position, created_at)::INTEGER - 1 AS next_position
        FROM public.onboarding_template_requirements
        WHERE template_id = template_record.id
    )
    UPDATE public.onboarding_template_requirements requirements
    SET position = ordered.next_position
    FROM ordered
    WHERE requirements.id = ordered.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.reorder_onboarding_template_requirements(
    input_template_id UUID,
    input_requirement_ids UUID[]
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    template_record public.onboarding_templates%ROWTYPE;
BEGIN
    SELECT * INTO template_record FROM public.onboarding_templates WHERE id = input_template_id;
    IF NOT FOUND OR template_record.status <> 'draft'
       OR NOT public.is_onboarding_template_manager(template_record.school_id, template_record.target_role, actor) THEN
        RAISE EXCEPTION 'You cannot reorder this template';
    END IF;
    IF COALESCE(array_length(input_requirement_ids, 1), 0) <>
       (SELECT COUNT(*) FROM public.onboarding_template_requirements WHERE template_id = input_template_id) THEN
        RAISE EXCEPTION 'The reordered requirement list is incomplete';
    END IF;
    -- Offset first to avoid the unique position constraint while swapping rows.
    UPDATE public.onboarding_template_requirements SET position = position + 10000 WHERE template_id = input_template_id;
    UPDATE public.onboarding_template_requirements requirements
    SET position = ordered.ordinality::INTEGER - 1,
        updated_at = NOW()
    FROM unnest(input_requirement_ids) WITH ORDINALITY AS ordered(id, ordinality)
    WHERE requirements.id = ordered.id
      AND requirements.template_id = input_template_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.publish_onboarding_template(input_template_id UUID)
RETURNS SETOF public.onboarding_templates
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    template_record public.onboarding_templates%ROWTYPE;
BEGIN
    SELECT * INTO template_record FROM public.onboarding_templates WHERE id = input_template_id;
    IF NOT FOUND OR template_record.status <> 'draft'
       OR NOT public.is_onboarding_template_manager(template_record.school_id, template_record.target_role, actor) THEN
        RAISE EXCEPTION 'You cannot publish this template';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.onboarding_template_requirements
        WHERE template_id = input_template_id
    ) THEN
        RAISE EXCEPTION 'Add at least one requirement before publishing';
    END IF;

    UPDATE public.onboarding_templates
    SET status = 'archived', archived_at = NOW(), updated_at = NOW()
    WHERE school_id = template_record.school_id
      AND target_role = template_record.target_role
      AND status = 'published';
    UPDATE public.onboarding_templates
    SET status = 'published', published_at = NOW(), archived_at = NULL, updated_at = NOW()
    WHERE id = input_template_id
    RETURNING * INTO template_record;

    PERFORM public.instantiate_onboarding_for_membership(memberships.id)
    FROM public.school_memberships memberships
    WHERE memberships.school_id = template_record.school_id
      AND memberships.role = template_record.target_role
      AND memberships.active = TRUE
      AND memberships.access_state = 'onboarding'
      AND NOT EXISTS (
          SELECT 1 FROM public.onboarding_instances instances
          WHERE instances.membership_id = memberships.id
      );

    RETURN QUERY SELECT * FROM public.onboarding_templates WHERE id = template_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.archive_onboarding_template(input_template_id UUID)
RETURNS SETOF public.onboarding_templates
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    template_record public.onboarding_templates%ROWTYPE;
BEGIN
    SELECT * INTO template_record FROM public.onboarding_templates WHERE id = input_template_id;
    IF NOT FOUND
       OR template_record.status <> 'published'
       OR NOT public.is_onboarding_template_manager(template_record.school_id, template_record.target_role, actor) THEN
        RAISE EXCEPTION 'You cannot archive this template';
    END IF;
    UPDATE public.onboarding_templates
    SET status = 'archived', archived_at = NOW(), updated_at = NOW()
    WHERE id = input_template_id
    RETURNING * INTO template_record;
    RETURN QUERY SELECT * FROM public.onboarding_templates WHERE id = template_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_onboarding_assignment(
    input_instance_id UUID,
    input_template_requirement_id UUID,
    input_child_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    instance_record RECORD;
    requirement_record public.onboarding_template_requirements%ROWTYPE;
    assignment_uuid UUID;
    notification_uuid UUID;
    shared_status TEXT;
BEGIN
    SELECT instances.*, memberships.user_id, memberships.role, templates.created_by
    INTO instance_record
    FROM public.onboarding_instances instances
    JOIN public.school_memberships memberships ON memberships.id = instances.membership_id
    JOIN public.onboarding_templates templates ON templates.id = instances.template_id
    WHERE instances.id = input_instance_id;
    SELECT * INTO requirement_record
    FROM public.onboarding_template_requirements
    WHERE id = input_template_requirement_id
      AND template_id = instance_record.template_id;
    IF instance_record.id IS NULL OR requirement_record.id IS NULL THEN
        RAISE EXCEPTION 'Onboarding requirement could not be instantiated';
    END IF;

    -- A child-scoped item is shared by every authorized guardian. Reuse the
    -- assignment even when guardians received different versions of the same
    -- template requirement; requirement_key is preserved across versions.
    IF input_child_id IS NOT NULL THEN
        SELECT requirement_instances.assignment_id, requirement_instances.status
        INTO assignment_uuid, shared_status
        FROM public.onboarding_requirement_instances requirement_instances
        JOIN public.onboarding_instances existing_instances
          ON existing_instances.id = requirement_instances.onboarding_instance_id
        JOIN public.onboarding_template_requirements existing_requirements
          ON existing_requirements.id = requirement_instances.template_requirement_id
        WHERE existing_instances.school_id = instance_record.school_id
          AND existing_requirements.requirement_key = requirement_record.requirement_key
          AND requirement_instances.child_id = input_child_id
          AND requirement_instances.assignment_id IS NOT NULL
        ORDER BY requirement_instances.created_at
        LIMIT 1;

        IF assignment_uuid IS NOT NULL THEN
            INSERT INTO public.onboarding_requirement_instances (
                onboarding_instance_id, template_requirement_id, assignment_id, child_id, status,
                completed_at
            ) VALUES (
                input_instance_id,
                requirement_record.id,
                assignment_uuid,
                input_child_id,
                shared_status,
                CASE WHEN shared_status IN ('approved', 'waived') THEN NOW() ELSE NULL END
            )
            ON CONFLICT DO NOTHING;

            INSERT INTO public.assignment_recipients (
                assignment_id, user_id, role_at_assignment, child_id, completion_status
            ) VALUES (
                assignment_uuid,
                instance_record.user_id,
                instance_record.role,
                input_child_id,
                CASE shared_status
                    WHEN 'approved' THEN 'accepted'
                    WHEN 'waived' THEN 'excused'
                    WHEN 'in_review' THEN 'submitted'
                    WHEN 'changes_requested' THEN 'changes_requested'
                    WHEN 'overdue' THEN 'overdue'
                    WHEN 'in_progress' THEN 'read'
                    ELSE 'not_started'
                END
            )
            ON CONFLICT DO NOTHING;
            RETURN assignment_uuid;
        END IF;
    END IF;

    INSERT INTO public.assignments (
        school_id, child_id, title, description, category, audience_role,
        assigned_by, status, visibility, requires_review, allow_resubmission,
        publish_at
    ) VALUES (
        instance_record.school_id,
        input_child_id,
        requirement_record.title,
        requirement_record.description,
        'onboarding',
        instance_record.role,
        instance_record.created_by,
        'published',
        'assigned',
        TRUE,
        TRUE,
        NOW()
    ) RETURNING id INTO assignment_uuid;

    IF input_child_id IS NULL THEN
        INSERT INTO public.assignment_recipients (
            assignment_id, user_id, role_at_assignment, child_id, completion_status
        ) VALUES (
            assignment_uuid, instance_record.user_id, instance_record.role, NULL, 'not_started'
        );
    ELSE
        INSERT INTO public.assignment_recipients (
            assignment_id, user_id, role_at_assignment, child_id, completion_status
        )
        SELECT
            assignment_uuid,
            memberships.user_id,
            memberships.role,
            input_child_id,
            'not_started'
        FROM public.child_guardians guardians
        JOIN public.school_memberships memberships
          ON memberships.user_id = guardians.guardian_id
         AND memberships.school_id = instance_record.school_id
         AND memberships.role = 'parent'
         AND memberships.active = TRUE
        WHERE guardians.child_id = input_child_id
        ON CONFLICT DO NOTHING;
    END IF;
    INSERT INTO public.assignment_materials (
        assignment_id, material_type, title, private_file_path, file_name, content_type
    )
    SELECT assignment_uuid, 'file', file_name, private_file_path, file_name, content_type
    FROM public.onboarding_template_attachments
    WHERE requirement_id = requirement_record.id
    ORDER BY position;

    INSERT INTO public.onboarding_requirement_instances (
        onboarding_instance_id, template_requirement_id, assignment_id, child_id, status
    ) VALUES (
        input_instance_id, requirement_record.id, assignment_uuid, input_child_id, 'not_started'
    );

    INSERT INTO public.assignment_events (assignment_id, school_id, actor_id, event_type)
    VALUES (assignment_uuid, instance_record.school_id, instance_record.created_by, 'published');
    INSERT INTO public.notifications (
        school_id, title, body, category, source_type, source_id, created_by, dedupe_key
    ) VALUES (
        instance_record.school_id,
        requirement_record.title,
        COALESCE(requirement_record.description, 'A new onboarding requirement is ready.'),
        'assignment_assigned',
        'assignment',
        assignment_uuid,
        instance_record.created_by,
        'onboarding:assignment:' || assignment_uuid::TEXT
    ) RETURNING id INTO notification_uuid;
    INSERT INTO public.notification_recipients (notification_id, user_id)
    SELECT notification_uuid, recipients.user_id
    FROM public.assignment_recipients recipients
    WHERE recipients.assignment_id = assignment_uuid
    ON CONFLICT DO NOTHING;

    RETURN assignment_uuid;
END;
$$;

CREATE OR REPLACE FUNCTION public.refresh_onboarding_access(input_membership_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    instance_record public.onboarding_instances%ROWTYPE;
    next_state TEXT;
BEGIN
    SELECT * INTO instance_record
    FROM public.onboarding_instances
    WHERE membership_id = input_membership_id
      AND status = 'in_progress'
    ORDER BY started_at DESC
    LIMIT 1;
    IF NOT FOUND THEN
        RETURN (SELECT access_state FROM public.school_memberships WHERE id = input_membership_id);
    END IF;

    IF EXISTS (
        SELECT 1 FROM public.onboarding_requirement_instances
        WHERE onboarding_instance_id = instance_record.id
          AND status NOT IN ('approved', 'waived')
    ) THEN
        next_state := 'onboarding';
    ELSE
        next_state := 'full';
        UPDATE public.onboarding_instances
        SET status = 'complete', completed_at = COALESCE(completed_at, NOW())
        WHERE id = instance_record.id;
    END IF;
    UPDATE public.school_memberships SET access_state = next_state WHERE id = input_membership_id;
    RETURN next_state;
END;
$$;

CREATE OR REPLACE FUNCTION public.instantiate_onboarding_for_membership(input_membership_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    membership_record public.school_memberships%ROWTYPE;
    template_record public.onboarding_templates%ROWTYPE;
    instance_uuid UUID;
    requirement_record public.onboarding_template_requirements%ROWTYPE;
    child_record RECORD;
    has_child BOOLEAN;
BEGIN
    SELECT * INTO membership_record FROM public.school_memberships WHERE id = input_membership_id AND active = TRUE;
    IF NOT FOUND OR membership_record.role = 'hq_director' THEN RETURN NULL; END IF;
    SELECT * INTO template_record
    FROM public.onboarding_templates
    WHERE school_id = membership_record.school_id
      AND target_role = membership_record.role
      AND status = 'published'
    ORDER BY version DESC LIMIT 1;
    IF NOT FOUND THEN
        -- Missing or archived templates must never bypass setup. Managers can
        -- publish a template and re-run instantiation before inviting again.
        UPDATE public.school_memberships
        SET access_state = 'onboarding'
        WHERE id = membership_record.id;
        RETURN NULL;
    END IF;

    SELECT id INTO instance_uuid
    FROM public.onboarding_instances
    WHERE membership_id = membership_record.id AND template_id = template_record.id;
    IF instance_uuid IS NOT NULL THEN
        PERFORM public.refresh_onboarding_access(membership_record.id);
        RETURN instance_uuid;
    END IF;
    INSERT INTO public.onboarding_instances (school_id, membership_id, template_id)
    VALUES (membership_record.school_id, membership_record.id, template_record.id)
    RETURNING id INTO instance_uuid;
    UPDATE public.school_memberships SET access_state = 'onboarding' WHERE id = membership_record.id;

    FOR requirement_record IN
        SELECT * FROM public.onboarding_template_requirements
        WHERE template_id = template_record.id ORDER BY position
    LOOP
        IF requirement_record.subject_scope = 'member' THEN
            PERFORM public.create_onboarding_assignment(instance_uuid, requirement_record.id, NULL);
        ELSE
            has_child := FALSE;
            FOR child_record IN
                SELECT children.id
                FROM public.children
                JOIN public.child_guardians guardians ON guardians.child_id = children.id
                WHERE guardians.guardian_id = membership_record.user_id
                  AND children.school_id = membership_record.school_id
                  AND children.active = TRUE
            LOOP
                has_child := TRUE;
                PERFORM public.create_onboarding_assignment(instance_uuid, requirement_record.id, child_record.id);
            END LOOP;
            IF NOT has_child THEN
                INSERT INTO public.onboarding_requirement_instances (
                    onboarding_instance_id, template_requirement_id, status
                ) VALUES (instance_uuid, requirement_record.id, 'not_started');
            END IF;
        END IF;
    END LOOP;
    PERFORM public.refresh_onboarding_access(membership_record.id);
    RETURN instance_uuid;
END;
$$;

CREATE OR REPLACE FUNCTION public.instantiate_child_onboarding(input_child_id UUID, input_guardian_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    target RECORD;
BEGIN
    FOR target IN
        SELECT
            instances.id AS instance_id,
            instances.membership_id,
            requirements.id AS requirement_id
        FROM public.onboarding_instances instances
        JOIN public.school_memberships memberships ON memberships.id = instances.membership_id
        JOIN public.onboarding_template_requirements requirements ON requirements.template_id = instances.template_id
        JOIN public.children children ON children.school_id = instances.school_id
        WHERE memberships.user_id = input_guardian_id
          AND memberships.active = TRUE
          AND requirements.subject_scope = 'child'
          AND children.id = input_child_id
    LOOP
        DELETE FROM public.onboarding_requirement_instances
        WHERE onboarding_instance_id = target.instance_id
          AND template_requirement_id = target.requirement_id
          AND child_id IS NULL
          AND assignment_id IS NULL;
        IF NOT EXISTS (
            SELECT 1 FROM public.onboarding_requirement_instances
            WHERE onboarding_instance_id = target.instance_id
              AND template_requirement_id = target.requirement_id
              AND child_id = input_child_id
        ) THEN
            PERFORM public.create_onboarding_assignment(target.instance_id, target.requirement_id, input_child_id);
        END IF;
        PERFORM public.refresh_onboarding_access(target.membership_id);
    END LOOP;
END;
$$;

CREATE OR REPLACE FUNCTION public.onboarding_membership_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NEW.active = TRUE AND NEW.role IN ('parent', 'teacher', 'school_director') THEN
        PERFORM public.instantiate_onboarding_for_membership(NEW.id);
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS instantiate_onboarding_membership_trigger ON public.school_memberships;
CREATE TRIGGER instantiate_onboarding_membership_trigger
    AFTER INSERT OR UPDATE OF active, role ON public.school_memberships
    FOR EACH ROW EXECUTE FUNCTION public.onboarding_membership_trigger();

CREATE OR REPLACE FUNCTION public.onboarding_child_guardian_trigger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public.instantiate_child_onboarding(NEW.child_id, NEW.guardian_id);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS instantiate_child_onboarding_trigger ON public.child_guardians;
CREATE TRIGGER instantiate_child_onboarding_trigger
    AFTER INSERT ON public.child_guardians
    FOR EACH ROW EXECUTE FUNCTION public.onboarding_child_guardian_trigger();

CREATE OR REPLACE FUNCTION public.sync_onboarding_requirement_status()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    canonical_status TEXT;
    membership_uuid UUID;
BEGIN
    SELECT CASE
        WHEN EXISTS (
            SELECT 1 FROM public.assignment_recipients
            WHERE assignment_id = NEW.assignment_id AND completion_status = 'accepted'
        ) THEN 'approved'
        WHEN NOT EXISTS (
            SELECT 1 FROM public.assignment_recipients
            WHERE assignment_id = NEW.assignment_id AND completion_status <> 'excused'
        ) THEN 'waived'
        WHEN EXISTS (
            SELECT 1 FROM public.assignment_recipients
            WHERE assignment_id = NEW.assignment_id AND completion_status IN ('changes_requested', 'flagged')
        ) THEN 'changes_requested'
        WHEN EXISTS (
            SELECT 1 FROM public.assignment_recipients
            WHERE assignment_id = NEW.assignment_id AND completion_status IN ('submitted', 'resubmitted')
        ) THEN 'in_review'
        WHEN EXISTS (
            SELECT 1 FROM public.assignment_recipients
            WHERE assignment_id = NEW.assignment_id AND completion_status = 'overdue'
        ) THEN 'overdue'
        WHEN EXISTS (
            SELECT 1 FROM public.assignment_recipients
            WHERE assignment_id = NEW.assignment_id AND completion_status IN ('read', 'reviewed')
        ) THEN 'in_progress'
        ELSE 'not_started'
    END INTO canonical_status;

    UPDATE public.onboarding_requirement_instances requirement_instances
    SET status = canonical_status,
        completed_at = CASE
            WHEN canonical_status IN ('approved', 'waived') THEN COALESCE(completed_at, NOW())
            ELSE NULL
        END
    WHERE assignment_id = NEW.assignment_id;

    FOR membership_uuid IN
        SELECT DISTINCT instances.membership_id
        FROM public.onboarding_requirement_instances requirement_instances
        JOIN public.onboarding_instances instances
          ON instances.id = requirement_instances.onboarding_instance_id
        WHERE requirement_instances.assignment_id = NEW.assignment_id
    LOOP
        PERFORM public.refresh_onboarding_access(membership_uuid);
    END LOOP;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_onboarding_requirement_status_trigger ON public.assignment_recipients;
CREATE TRIGGER sync_onboarding_requirement_status_trigger
    AFTER UPDATE OF completion_status ON public.assignment_recipients
    FOR EACH ROW EXECUTE FUNCTION public.sync_onboarding_requirement_status();

CREATE OR REPLACE FUNCTION public.waive_onboarding_assignment(
    input_assignment_id UUID,
    input_reason TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    assignment_record public.assignments%ROWTYPE;
    reason_text TEXT := NULLIF(BTRIM(COALESCE(input_reason, '')), '');
    notification_uuid UUID;
BEGIN
    SELECT * INTO assignment_record
    FROM public.assignments
    WHERE id = input_assignment_id
      AND category = 'onboarding';

    IF NOT FOUND OR NOT public.can_review_assignment(input_assignment_id, actor) THEN
        RAISE EXCEPTION 'Only the authorized reviewer can waive this onboarding requirement';
    END IF;
    IF reason_text IS NULL THEN
        RAISE EXCEPTION 'A waiver reason is required';
    END IF;

    UPDATE public.onboarding_requirement_instances
    SET status = 'waived',
        waived_by = actor,
        waiver_reason = reason_text,
        completed_at = COALESCE(completed_at, NOW())
    WHERE assignment_id = input_assignment_id;

    UPDATE public.assignment_recipients
    SET completion_status = 'excused',
        completed_at = COALESCE(completed_at, NOW())
    WHERE assignment_id = input_assignment_id;

    INSERT INTO public.assignment_events (
        assignment_id, school_id, actor_id, event_type, metadata
    ) VALUES (
        input_assignment_id,
        assignment_record.school_id,
        actor,
        'waived',
        jsonb_build_object('reason', reason_text)
    );

    INSERT INTO public.notifications (
        school_id, title, body, category, source_type, source_id, created_by, dedupe_key
    ) VALUES (
        assignment_record.school_id,
        'Onboarding requirement waived',
        assignment_record.title || ': ' || reason_text,
        'assignment_feedback',
        'assignment',
        input_assignment_id,
        actor,
        'onboarding:waived:' || input_assignment_id::TEXT
    )
    ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL
    DO UPDATE SET body = EXCLUDED.body, created_by = EXCLUDED.created_by
    RETURNING id INTO notification_uuid;

    INSERT INTO public.notification_recipients (notification_id, user_id)
    SELECT notification_uuid, recipients.user_id
    FROM public.assignment_recipients recipients
    WHERE recipients.assignment_id = input_assignment_id
    ON CONFLICT DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION public.fetch_my_onboarding_dashboard(input_school_id UUID)
RETURNS TABLE (
    requirement_instance_id UUID,
    assignment_id UUID,
    child_id UUID,
    title TEXT,
    description TEXT,
    subject_scope TEXT,
    "position" INTEGER,
    status TEXT,
    material_count BIGINT,
    child_first_name TEXT,
    child_last_name TEXT,
    reviewer_label TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        requirement_instances.id,
        requirement_instances.assignment_id,
        requirement_instances.child_id,
        requirements.title,
        requirements.description,
        requirements.subject_scope,
        requirements.position,
        requirement_instances.status,
        COALESCE((SELECT COUNT(*) FROM public.assignment_materials materials WHERE materials.assignment_id = requirement_instances.assignment_id), 0),
        children.first_name,
        children.last_name,
        CASE templates.target_role
            WHEN 'school_director' THEN 'Reviewed by FireflyFM HQ'
            ELSE 'Reviewed by your school director'
        END
    FROM public.onboarding_instances instances
    JOIN public.school_memberships memberships ON memberships.id = instances.membership_id
    JOIN public.onboarding_templates templates ON templates.id = instances.template_id
    JOIN public.onboarding_requirement_instances requirement_instances ON requirement_instances.onboarding_instance_id = instances.id
    JOIN public.onboarding_template_requirements requirements ON requirements.id = requirement_instances.template_requirement_id
    LEFT JOIN public.children children ON children.id = requirement_instances.child_id
    WHERE memberships.user_id = auth.uid()
      AND memberships.school_id = input_school_id
      AND memberships.active = TRUE
      AND instances.status IN ('in_progress', 'complete')
    ORDER BY requirements.position, children.first_name, children.last_name;
$$;

CREATE OR REPLACE FUNCTION public.fetch_onboarding_role_progress(input_school_id UUID, input_target_role TEXT)
RETURNS TABLE (
    member_count BIGINT,
    onboarding_count BIGINT,
    full_count BIGINT,
    needs_review_count BIGINT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.is_onboarding_template_manager(input_school_id, input_target_role, auth.uid()) THEN
        RAISE EXCEPTION 'You cannot view onboarding progress for this role';
    END IF;
    RETURN QUERY
    SELECT
        COUNT(DISTINCT memberships.user_id) + (
            SELECT COUNT(*)
            FROM public.role_invites invites
            WHERE invites.school_id = input_school_id
              AND invites.role = input_target_role
              AND invites.status = 'pending'
              AND (invites.expires_at IS NULL OR invites.expires_at > NOW())
        ),
        COUNT(DISTINCT memberships.user_id) FILTER (WHERE memberships.access_state = 'onboarding'),
        COUNT(DISTINCT memberships.user_id) FILTER (WHERE memberships.access_state = 'full'),
        COUNT(DISTINCT submissions.id) FILTER (WHERE submissions.status IN ('submitted', 'resubmitted'))
    FROM public.school_memberships memberships
    LEFT JOIN public.onboarding_instances instances ON instances.membership_id = memberships.id
    LEFT JOIN public.onboarding_requirement_instances requirement_instances ON requirement_instances.onboarding_instance_id = instances.id
    LEFT JOIN public.assignment_submissions submissions ON submissions.assignment_id = requirement_instances.assignment_id
    WHERE memberships.school_id = input_school_id
      AND memberships.role = input_target_role
      AND memberships.active = TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_member_role_invite(
    input_school_id UUID,
    input_email TEXT,
    input_display_name TEXT,
    input_role TEXT
)
RETURNS SETOF public.role_invites
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    normalized_email TEXT := lower(NULLIF(BTRIM(input_email), ''));
    created_invite public.role_invites%ROWTYPE;
    raw_invite_token TEXT := encode(extensions.gen_random_bytes(32), 'hex');
BEGIN
    IF input_role NOT IN ('parent', 'teacher') THEN RAISE EXCEPTION 'Only parent and teacher invitations are supported here'; END IF;
    IF normalized_email IS NULL OR POSITION('@' IN normalized_email) <= 1 THEN RAISE EXCEPTION 'A valid email is required'; END IF;
    IF NOT public.has_direct_school_role(input_school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only an approved school director can invite parents or teachers';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.onboarding_templates
        WHERE school_id = input_school_id AND target_role = input_role AND status = 'published'
    ) THEN
        RAISE EXCEPTION 'Publish the % onboarding template before inviting people', input_role;
    END IF;
    UPDATE public.role_invites SET status = 'revoked'
    WHERE school_id = input_school_id AND lower(email) = normalized_email AND role = input_role AND status = 'pending';
    INSERT INTO public.role_invites (
        school_id, email, display_name, role, invited_by, token, token_hash
    ) VALUES (
        input_school_id,
        normalized_email,
        NULLIF(BTRIM(COALESCE(input_display_name, '')), ''),
        input_role,
        actor,
        NULL,
        encode(extensions.digest(raw_invite_token, 'sha256'), 'hex')
    )
    RETURNING * INTO created_invite;
    -- Return the secret once to the inviter; only its hash remains stored.
    created_invite.token := raw_invite_token;
    RETURN NEXT created_invite;
END;
$$;

-- Onboarding assignments use role authority rather than being permanently tied
-- to the employee who originally published the template.
CREATE OR REPLACE FUNCTION public.can_manage_assignment(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.assignments assignments
        WHERE assignments.id = assignment_uuid
          AND (
              assignments.assigned_by = user_uuid
              OR EXISTS (
                  SELECT 1
                  FROM public.onboarding_requirement_instances requirement_instances
                  JOIN public.onboarding_instances instances ON instances.id = requirement_instances.onboarding_instance_id
                  JOIN public.onboarding_templates templates ON templates.id = instances.template_id
                  WHERE requirement_instances.assignment_id = assignments.id
                    AND public.is_onboarding_template_manager(templates.school_id, templates.target_role, user_uuid)
              )
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.can_review_assignment(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.can_manage_assignment(assignment_uuid, user_uuid)
       AND NOT public.is_assignment_recipient(assignment_uuid, user_uuid);
$$;

CREATE OR REPLACE FUNCTION public.can_review_assignment_submission(submission_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.assignment_submissions submissions
        WHERE submissions.id = submission_uuid
          AND submissions.submitted_by <> user_uuid
          AND public.can_review_assignment(submissions.assignment_id, user_uuid)
    );
$$;

CREATE OR REPLACE FUNCTION public.can_view_assignment(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1 FROM public.assignments assignments
        WHERE assignments.id = assignment_uuid
          AND (
              assignments.assigned_by = user_uuid
              OR public.is_assignment_recipient(assignments.id, user_uuid)
              OR public.can_review_assignment(assignments.id, user_uuid)
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.is_chat_room_member(room_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.chat_participants participants
        JOIN public.chat_rooms rooms ON rooms.id = participants.room_id
        WHERE participants.room_id = room_uuid
          AND participants.user_id = user_uuid
          AND public.has_full_school_access(rooms.school_id, user_uuid)
    );
$$;

DROP POLICY IF EXISTS "School members can view schools" ON public.schools;
CREATE POLICY "School members can view schools"
    ON public.schools FOR SELECT
    USING (public.has_school_membership(id, auth.uid()));

DROP POLICY IF EXISTS "HQ can manage role invites" ON public.role_invites;
DROP POLICY IF EXISTS "Onboarding managers can manage role invites" ON public.role_invites;
CREATE POLICY "Onboarding managers can manage role invites"
    ON public.role_invites FOR ALL
    USING (
        (role = 'school_director' AND public.is_hq_director(auth.uid()))
        OR (
            role IN ('parent', 'teacher')
            AND public.has_direct_school_role(school_id, auth.uid(), ARRAY['school_director'])
        )
    )
    WITH CHECK (
        (role = 'school_director' AND public.is_hq_director(auth.uid()))
        OR (
            role IN ('parent', 'teacher')
            AND public.has_direct_school_role(school_id, auth.uid(), ARRAY['school_director'])
        )
    );

-- Extend private-file authorization for reusable template paperwork. Managers
-- can edit files; recipients gain read access only through a linked assignment.
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
    IF object_name IS NULL OR user_uuid IS NULL THEN RETURN FALSE; END IF;
    parts := string_to_array(object_name, '/');
    IF array_length(parts, 1) < 4 OR parts[1] <> 'schools' THEN RETURN FALSE; END IF;
    school_uuid := parts[2]::UUID;
    category := parts[3];
    IF category = 'onboarding_templates' THEN
        RETURN EXISTS (
            SELECT 1
            FROM public.onboarding_templates templates
            WHERE templates.id = parts[4]::UUID
              AND templates.school_id = school_uuid
              AND public.is_onboarding_template_manager(
                    templates.school_id,
                    templates.target_role,
                    user_uuid
                  )
        ) OR EXISTS (
            SELECT 1
            FROM public.onboarding_template_attachments attachments
            JOIN public.onboarding_template_requirements requirements ON requirements.id = attachments.requirement_id
            LEFT JOIN public.onboarding_requirement_instances requirement_instances ON requirement_instances.template_requirement_id = requirements.id
            WHERE attachments.private_file_path = object_name
              AND requirement_instances.assignment_id IS NOT NULL
              AND public.can_view_assignment(requirement_instances.assignment_id, user_uuid)
        );
    END IF;
    IF category <> 'assignments'
       AND public.has_school_role(school_uuid, user_uuid, ARRAY['school_director', 'hq_director']) THEN RETURN TRUE; END IF;
    IF category = 'paperwork_assignments' THEN
        record_uuid := parts[4]::UUID;
        RETURN EXISTS (SELECT 1 FROM public.paperwork_assignment_recipients WHERE assignment_id = record_uuid AND parent_id = user_uuid);
    ELSIF category = 'paperwork_submissions' THEN
        owner_uuid := parts[4]::UUID;
        RETURN owner_uuid = user_uuid AND public.has_school_membership(school_uuid, user_uuid);
    ELSIF category IN ('curriculum_resources', 'training_assignments') THEN
        RETURN public.has_school_role(school_uuid, user_uuid, ARRAY['teacher']);
    ELSIF category = 'training_submissions' THEN
        owner_uuid := parts[4]::UUID;
        RETURN owner_uuid = user_uuid AND public.has_school_role(school_uuid, user_uuid, ARRAY['teacher']);
    ELSIF category = 'onboarding_requirements' THEN
        record_uuid := parts[4]::UUID;
        RETURN public.can_manage_onboarding_requirement(record_uuid, user_uuid) OR public.can_submit_onboarding_requirement(record_uuid, user_uuid);
    ELSIF category = 'document_submissions' THEN
        record_uuid := parts[4]::UUID;
        RETURN public.can_submit_onboarding_requirement(record_uuid, user_uuid) OR public.has_school_role(school_uuid, user_uuid, ARRAY['school_director', 'hq_director']);
    ELSIF category = 'child_documents' THEN
        record_uuid := parts[4]::UUID;
        RETURN public.can_access_child(record_uuid, user_uuid);
    ELSIF category = 'assignments' THEN
        IF array_length(parts, 1) < 5 THEN RETURN FALSE; END IF;
        record_uuid := parts[4]::UUID;
        IF parts[5] = 'submissions' THEN
            IF array_length(parts, 1) < 6 THEN RETURN FALSE; END IF;
            owner_uuid := parts[6]::UUID;
            RETURN owner_uuid = user_uuid OR public.can_manage_assignment(record_uuid, user_uuid);
        END IF;
        RETURN public.can_view_assignment(record_uuid, user_uuid);
    ELSIF category IN ('community_posts', 'community_albums') THEN
        RETURN public.is_school_member(school_uuid, user_uuid);
    END IF;
    RETURN FALSE;
EXCEPTION WHEN invalid_text_representation THEN RETURN FALSE;
END;
$$;

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
    IF object_name IS NULL OR user_uuid IS NULL THEN RETURN FALSE; END IF;
    parts := string_to_array(object_name, '/');
    IF array_length(parts, 1) < 4 OR parts[1] <> 'schools' THEN RETURN FALSE; END IF;
    school_uuid := parts[2]::UUID;
    category := parts[3];
    IF category = 'onboarding_templates' THEN
        IF array_length(parts, 1) < 5 THEN RETURN FALSE; END IF;
        RETURN EXISTS (
            SELECT 1
            FROM public.onboarding_templates templates
            WHERE templates.id = parts[4]::UUID
              AND templates.school_id = school_uuid
              AND templates.status = 'draft'
              AND public.is_onboarding_template_manager(
                    templates.school_id,
                    templates.target_role,
                    user_uuid
                  )
        );
    END IF;
    IF category IN ('paperwork_assignments', 'curriculum_resources', 'training_assignments', 'onboarding_requirements') THEN
        RETURN public.has_school_role(school_uuid, user_uuid, ARRAY['school_director', 'hq_director']);
    END IF;
    IF category = 'assignments' THEN
        IF array_length(parts, 1) < 5 THEN RETURN FALSE; END IF;
        IF parts[5] = 'materials' THEN
            RETURN public.can_manage_assignment(parts[4]::UUID, user_uuid);
        ELSIF parts[5] = 'submissions' THEN
            IF array_length(parts, 1) < 6 THEN RETURN FALSE; END IF;
            owner_uuid := parts[6]::UUID;
            RETURN owner_uuid = user_uuid AND public.can_submit_assignment(parts[4]::UUID, user_uuid);
        END IF;
        RETURN FALSE;
    END IF;
    IF array_length(parts, 1) < 5 THEN RETURN FALSE; END IF;
    owner_uuid := parts[4]::UUID;
    IF category = 'paperwork_submissions' THEN
        RETURN owner_uuid = user_uuid AND public.has_school_membership(school_uuid, user_uuid);
    ELSIF category = 'training_submissions' THEN
        RETURN owner_uuid = user_uuid AND public.has_school_role(school_uuid, user_uuid, ARRAY['teacher']);
    ELSIF category = 'document_submissions' THEN
        RETURN public.can_submit_onboarding_requirement(owner_uuid, user_uuid);
    ELSIF category = 'child_documents' THEN
        RETURN public.can_access_child(owner_uuid, user_uuid);
    ELSIF category IN ('community_posts', 'community_albums') THEN
        RETURN public.has_school_role(school_uuid, user_uuid, ARRAY['teacher', 'school_director', 'hq_director']);
    END IF;
    RETURN FALSE;
EXCEPTION WHEN invalid_text_representation THEN RETURN FALSE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.has_school_membership(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.has_full_school_access(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.is_onboarding_template_manager(UUID, TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.ensure_onboarding_template_draft(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_onboarding_template_draft(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_onboarding_template_requirement(UUID, UUID, TEXT, TEXT, TEXT, INTEGER, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.remove_onboarding_template_requirement(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reorder_onboarding_template_requirements(UUID, UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.publish_onboarding_template(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.archive_onboarding_template(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.waive_onboarding_assignment(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_my_onboarding_dashboard(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_onboarding_role_progress(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_member_role_invite(UUID, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_access_school_private_file(TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_write_school_private_file(TEXT, UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- Phase 3 assignment feedback-loop hardening.
-- Assignment capabilities are relationship-based: recipients perform their own
-- work and the assignment creator manages/reviews it.

ALTER TABLE public.assignment_recipients
    ADD COLUMN IF NOT EXISTS viewed_at TIMESTAMPTZ;

ALTER TABLE public.assignment_feedback_messages
    ADD COLUMN IF NOT EXISTS recipient_id UUID REFERENCES auth.users(id) ON DELETE CASCADE;

UPDATE public.assignment_feedback_messages feedback
SET recipient_id = submissions.submitted_by
FROM public.assignment_submissions submissions
WHERE feedback.submission_id = submissions.id
  AND feedback.recipient_id IS NULL;

UPDATE public.assignment_recipients recipients
SET viewed_at = receipts.checked_at
FROM public.assignment_read_receipts receipts
WHERE receipts.assignment_id = recipients.assignment_id
  AND receipts.user_id = recipients.user_id
  AND recipients.viewed_at IS NULL;

ALTER TABLE public.notifications
    ADD COLUMN IF NOT EXISTS dedupe_key TEXT;

CREATE UNIQUE INDEX IF NOT EXISTS idx_notifications_dedupe_key
    ON public.notifications(dedupe_key)
    WHERE dedupe_key IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_assignment_recipients_user_viewed
    ON public.assignment_recipients(user_id, viewed_at);

CREATE INDEX IF NOT EXISTS idx_assignment_feedback_recipient
    ON public.assignment_feedback_messages(recipient_id, created_at DESC);

CREATE TABLE IF NOT EXISTS public.assignment_mutation_requests (
    actor_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    idempotency_key TEXT NOT NULL,
    operation TEXT NOT NULL,
    result_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (actor_id, idempotency_key, operation)
);

ALTER TABLE public.assignment_mutation_requests ENABLE ROW LEVEL SECURITY;

-- This is the well-known school used only by the legacy chat migration. Keep
-- the school and membership rows for audit history, but stop selecting that
-- membership when a user has since joined a real school.
CREATE TABLE IF NOT EXISTS public.school_membership_repair_audit (
    membership_id UUID PRIMARY KEY REFERENCES public.school_memberships(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    reason TEXT NOT NULL,
    repaired_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.school_membership_repair_audit ENABLE ROW LEVEL SECURITY;

INSERT INTO public.school_membership_repair_audit (membership_id, user_id, school_id, reason)
SELECT
    legacy_membership.id,
    legacy_membership.user_id,
    legacy_membership.school_id,
    'Deactivated legacy Default School membership after a real active membership was found'
FROM public.school_memberships legacy_membership
WHERE legacy_membership.school_id = '00000000-0000-0000-0000-000000000001'::UUID
  AND legacy_membership.active = TRUE
  AND EXISTS (
      SELECT 1
      FROM public.school_memberships real_membership
      WHERE real_membership.user_id = legacy_membership.user_id
        AND real_membership.school_id <> legacy_membership.school_id
        AND real_membership.active = TRUE
  )
ON CONFLICT (membership_id) DO NOTHING;

UPDATE public.school_memberships legacy_membership
SET active = FALSE
WHERE legacy_membership.school_id = '00000000-0000-0000-0000-000000000001'::UUID
  AND legacy_membership.active = TRUE
  AND EXISTS (
      SELECT 1
      FROM public.school_memberships real_membership
      WHERE real_membership.user_id = legacy_membership.user_id
        AND real_membership.school_id <> legacy_membership.school_id
        AND real_membership.active = TRUE
  );

CREATE OR REPLACE FUNCTION public.can_manage_assignment(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.assignments
        WHERE id = assignment_uuid
          AND assigned_by = user_uuid
    );
$$;

CREATE OR REPLACE FUNCTION public.can_review_assignment(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.can_manage_assignment(assignment_uuid, user_uuid);
$$;

CREATE OR REPLACE FUNCTION public.can_review_assignment_submission(submission_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.assignment_submissions submissions
        JOIN public.assignments assignments ON assignments.id = submissions.assignment_id
        WHERE submissions.id = submission_uuid
          AND assignments.assigned_by = user_uuid
          AND submissions.submitted_by <> user_uuid
    );
$$;

CREATE OR REPLACE FUNCTION public.can_view_assignment(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.assignments
        WHERE id = assignment_uuid
          AND (
              assigned_by = user_uuid
              OR public.is_assignment_recipient(id, user_uuid)
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.can_submit_assignment(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.assignments assignments
        WHERE assignments.id = assignment_uuid
          AND (
              assignments.status = 'published'
              OR (assignments.status = 'scheduled' AND assignments.publish_at <= NOW())
          )
          AND (assignments.close_at IS NULL OR assignments.close_at >= NOW())
          AND public.is_assignment_recipient(assignments.id, user_uuid)
          AND (
              NOT EXISTS (
                  SELECT 1
                  FROM public.assignment_submissions submissions
                  WHERE submissions.assignment_id = assignments.id
                    AND submissions.submitted_by = user_uuid
              )
              OR (
                  COALESCE(assignments.allow_resubmission, TRUE)
                  AND (
                      SELECT submissions.status
                      FROM public.assignment_submissions submissions
                      WHERE submissions.assignment_id = assignments.id
                        AND submissions.submitted_by = user_uuid
                      ORDER BY submissions.attempt_number DESC, submissions.submitted_at DESC
                      LIMIT 1
                  ) = 'changes_requested'
              )
          )
    );
$$;

DROP POLICY IF EXISTS "Users can view assignments" ON public.assignments;
DROP POLICY IF EXISTS "Directors can create assignments" ON public.assignments;
DROP POLICY IF EXISTS "Assignment owners can update assignments" ON public.assignments;
DROP POLICY IF EXISTS "Assignment owners can delete assignments" ON public.assignments;
CREATE POLICY "Users can view assignments"
    ON public.assignments FOR SELECT
    USING (public.can_view_assignment(id, auth.uid()));

DROP POLICY IF EXISTS "Users can view assignment recipients" ON public.assignment_recipients;
CREATE POLICY "Users can view assignment recipients"
    ON public.assignment_recipients FOR SELECT
    USING (
        user_id = auth.uid()
        OR public.can_manage_assignment(assignment_id, auth.uid())
    );

DROP POLICY IF EXISTS "Directors can manage assignment recipients" ON public.assignment_recipients;
DROP POLICY IF EXISTS "Users can update own assignment recipient status" ON public.assignment_recipients;
DROP POLICY IF EXISTS "Assignment owners can manage recipients" ON public.assignment_recipients;

DROP POLICY IF EXISTS "Users can view assignment submissions" ON public.assignment_submissions;
DROP POLICY IF EXISTS "Users can create assignment submissions" ON public.assignment_submissions;
CREATE POLICY "Users can view assignment submissions"
    ON public.assignment_submissions FOR SELECT
    USING (
        submitted_by = auth.uid()
        OR public.can_review_assignment_submission(id, auth.uid())
    );

DROP POLICY IF EXISTS "Directors can review assignment submissions" ON public.assignment_submissions;
DROP POLICY IF EXISTS "Assignment owners can review submissions" ON public.assignment_submissions;

DROP POLICY IF EXISTS "Users can view assignment submission attachments" ON public.assignment_submission_attachments;
DROP POLICY IF EXISTS "Users can create assignment submission attachments" ON public.assignment_submission_attachments;
CREATE POLICY "Users can view assignment submission attachments"
    ON public.assignment_submission_attachments FOR SELECT
    USING (
        EXISTS (
            SELECT 1
            FROM public.assignment_submissions submissions
            WHERE submissions.id = assignment_submission_attachments.submission_id
              AND (
                  submissions.submitted_by = auth.uid()
                  OR public.can_review_assignment_submission(submissions.id, auth.uid())
              )
        )
    );

DROP POLICY IF EXISTS "Directors can view assignment read receipts" ON public.assignment_read_receipts;
DROP POLICY IF EXISTS "Users can manage own assignment read receipts" ON public.assignment_read_receipts;
DROP POLICY IF EXISTS "Assignment owners can view assignment read receipts" ON public.assignment_read_receipts;
DROP POLICY IF EXISTS "Assignment participants can view assignment read receipts" ON public.assignment_read_receipts;
CREATE POLICY "Assignment participants can view assignment read receipts"
    ON public.assignment_read_receipts FOR SELECT
    USING (
        user_id = auth.uid()
        OR public.can_manage_assignment(assignment_id, auth.uid())
    );

DROP POLICY IF EXISTS "Users can view assignment feedback" ON public.assignment_feedback_messages;
DROP POLICY IF EXISTS "Assignment participants can view scoped feedback" ON public.assignment_feedback_messages;
CREATE POLICY "Assignment participants can view scoped feedback"
    ON public.assignment_feedback_messages FOR SELECT
    USING (
        recipient_id = auth.uid()
        OR public.can_manage_assignment(assignment_id, auth.uid())
    );

DROP POLICY IF EXISTS "Users can add assignment feedback" ON public.assignment_feedback_messages;
DROP POLICY IF EXISTS "Assignment participants can add scoped feedback" ON public.assignment_feedback_messages;

DROP POLICY IF EXISTS "Assignment participants can view event history" ON public.assignment_events;
DROP POLICY IF EXISTS "Assignment participants can view scoped event history" ON public.assignment_events;
CREATE POLICY "Assignment participants can view scoped event history"
    ON public.assignment_events FOR SELECT
    USING (
        public.can_manage_assignment(assignment_id, auth.uid())
        OR actor_id = auth.uid()
        OR NULLIF(metadata->>'recipient_id', '')::UUID = auth.uid()
        OR EXISTS (
            SELECT 1
            FROM public.assignment_submissions submissions
            WHERE submissions.id = NULLIF(metadata->>'submission_id', '')::UUID
              AND submissions.submitted_by = auth.uid()
        )
    );

DROP POLICY IF EXISTS "Users can view received notifications" ON public.notifications;
CREATE POLICY "Users can view received notifications"
    ON public.notifications FOR SELECT
    USING (
        public.is_notification_recipient(id, auth.uid())
        OR (
            COALESCE(source_type, '') <> 'assignment'
            AND public.has_school_role(school_id, auth.uid(), ARRAY['school_director', 'hq_director'])
        )
    );

CREATE OR REPLACE FUNCTION public.can_delete_school_private_file(object_name TEXT, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    parts TEXT[];
    owner_uuid UUID;
BEGIN
    parts := string_to_array(object_name, '/');
    IF array_length(parts, 1) >= 6
       AND parts[1] = 'schools'
       AND parts[3] = 'assignments'
       AND parts[5] = 'submissions' THEN
        owner_uuid := parts[6]::UUID;
        RETURN owner_uuid = user_uuid
            AND NOT EXISTS (
                SELECT 1
                FROM public.assignment_submission_attachments attachments
                WHERE attachments.private_file_path = object_name
            );
    END IF;

    RETURN public.can_write_school_private_file(object_name, user_uuid);
EXCEPTION WHEN invalid_text_representation THEN
    RETURN FALSE;
END;
$$;

GRANT EXECUTE ON FUNCTION public.can_delete_school_private_file(TEXT, UUID) TO authenticated;

DROP POLICY IF EXISTS "School members can delete own private uploads" ON storage.objects;
CREATE POLICY "School members can delete own private uploads"
    ON storage.objects FOR DELETE
    USING (
        bucket_id = 'school_private_files'
        AND public.can_delete_school_private_file(name, auth.uid())
    );

CREATE OR REPLACE FUNCTION public.mark_assignment_viewed(input_assignment_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
BEGIN
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF NOT public.is_assignment_recipient(input_assignment_id, actor) THEN
        RAISE EXCEPTION 'Only an assignment recipient can mark it viewed';
    END IF;

    UPDATE public.assignment_recipients
    SET viewed_at = NOW()
    WHERE assignment_id = input_assignment_id
      AND user_id = actor;

    UPDATE public.notification_recipients receipts
    SET read_at = COALESCE(receipts.read_at, NOW())
    FROM public.notifications notifications
    WHERE receipts.notification_id = notifications.id
      AND receipts.user_id = actor
      AND notifications.source_type = 'assignment'
      AND notifications.source_id = input_assignment_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.acknowledge_assignment(input_assignment_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
BEGIN
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF NOT public.is_assignment_recipient(input_assignment_id, actor) THEN
        RAISE EXCEPTION 'Only an assignment recipient can acknowledge it';
    END IF;

    INSERT INTO public.assignment_read_receipts (assignment_id, user_id, checked_at)
    VALUES (input_assignment_id, actor, NOW())
    ON CONFLICT (assignment_id, user_id)
    DO UPDATE SET checked_at = EXCLUDED.checked_at;

    UPDATE public.assignment_recipients
    SET completion_status = 'read',
        viewed_at = COALESCE(viewed_at, NOW())
    WHERE assignment_id = input_assignment_id
      AND user_id = actor
      AND completion_status IN ('not_started', 'overdue');
END;
$$;

CREATE OR REPLACE FUNCTION public.mark_assignment_read(input_assignment_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public.acknowledge_assignment(input_assignment_id);
END;
$$;

DROP FUNCTION IF EXISTS public.fetch_my_assignment_agenda(TEXT[]);
CREATE FUNCTION public.fetch_my_assignment_agenda(input_categories TEXT[] DEFAULT NULL)
RETURNS TABLE (
    assignment_id UUID,
    school_id UUID,
    school_name TEXT,
    child_id UUID,
    title TEXT,
    description TEXT,
    category TEXT,
    due_at TIMESTAMPTZ,
    assigned_by UUID,
    created_at TIMESTAMPTZ,
    completion_status TEXT,
    viewed_at TIMESTAMPTZ,
    acknowledged_at TIMESTAMPTZ,
    has_unread_feedback BOOLEAN,
    submitted_at TIMESTAMPTZ,
    review_status TEXT,
    reviewed_at TIMESTAMPTZ,
    reviewer_message TEXT,
    child_first_name TEXT,
    child_last_name TEXT,
    material_count BIGINT,
    submission_count BIGINT,
    recipient_count BIGINT,
    needs_review_count BIGINT,
    changes_requested_count BIGINT,
    not_started_count BIGINT,
    overdue_count BIGINT,
    complete_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        assignments.id,
        assignments.school_id,
        schools.name,
        assignments.child_id,
        assignments.title,
        assignments.description,
        assignments.category,
        assignments.due_at,
        assignments.assigned_by,
        assignments.created_at,
        recipients.completion_status,
        recipients.viewed_at,
        receipts.checked_at,
        EXISTS (
            SELECT 1
            FROM public.assignment_feedback_messages feedback
            WHERE feedback.assignment_id = assignments.id
              AND feedback.recipient_id = auth.uid()
              AND feedback.sender_id <> auth.uid()
              AND feedback.created_at > COALESCE(recipients.viewed_at, '-infinity'::TIMESTAMPTZ)
        ),
        latest_submission.submitted_at,
        latest_submission.status,
        latest_submission.reviewed_at,
        latest_submission.reviewer_message,
        children.first_name,
        children.last_name,
        (SELECT COUNT(*) FROM public.assignment_materials materials WHERE materials.assignment_id = assignments.id),
        (SELECT COUNT(*) FROM public.assignment_submissions submissions WHERE submissions.assignment_id = assignments.id AND submissions.submitted_by = auth.uid()),
        1::BIGINT,
        NULL::BIGINT,
        NULL::BIGINT,
        NULL::BIGINT,
        NULL::BIGINT,
        NULL::BIGINT
    FROM public.assignment_recipients recipients
    JOIN public.assignments assignments ON assignments.id = recipients.assignment_id
    JOIN public.schools schools ON schools.id = assignments.school_id
    LEFT JOIN public.assignment_read_receipts receipts
      ON receipts.assignment_id = assignments.id
     AND receipts.user_id = auth.uid()
    LEFT JOIN LATERAL (
        SELECT submissions.submitted_at, submissions.status, submissions.reviewed_at, submissions.reviewer_message
        FROM public.assignment_submissions submissions
        WHERE submissions.assignment_id = assignments.id
          AND submissions.submitted_by = auth.uid()
        ORDER BY submissions.attempt_number DESC, submissions.submitted_at DESC
        LIMIT 1
    ) latest_submission ON TRUE
    LEFT JOIN public.children children ON children.id = assignments.child_id
    WHERE recipients.user_id = auth.uid()
      AND assignments.status IN ('published', 'closed', 'scheduled')
      AND (assignments.status <> 'scheduled' OR assignments.publish_at <= NOW())
      AND (input_categories IS NULL OR cardinality(input_categories) = 0 OR assignments.category = ANY(input_categories))
    ORDER BY assignments.due_at NULLS LAST, assignments.created_at DESC;
$$;

DROP FUNCTION IF EXISTS public.fetch_my_assignment_review_queue(UUID, TEXT[]);
CREATE FUNCTION public.fetch_my_assignment_review_queue(
    input_school_id UUID,
    input_categories TEXT[] DEFAULT NULL
)
RETURNS TABLE (
    assignment_id UUID,
    school_id UUID,
    school_name TEXT,
    child_id UUID,
    title TEXT,
    description TEXT,
    category TEXT,
    due_at TIMESTAMPTZ,
    assigned_by UUID,
    created_at TIMESTAMPTZ,
    completion_status TEXT,
    viewed_at TIMESTAMPTZ,
    acknowledged_at TIMESTAMPTZ,
    has_unread_feedback BOOLEAN,
    submitted_at TIMESTAMPTZ,
    review_status TEXT,
    reviewed_at TIMESTAMPTZ,
    reviewer_message TEXT,
    child_first_name TEXT,
    child_last_name TEXT,
    material_count BIGINT,
    submission_count BIGINT,
    recipient_count BIGINT,
    needs_review_count BIGINT,
    changes_requested_count BIGINT,
    not_started_count BIGINT,
    overdue_count BIGINT,
    complete_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    WITH latest_submissions AS (
        SELECT DISTINCT ON (assignment_id, submitted_by)
            assignment_id,
            submitted_by,
            status,
            submitted_at,
            reviewed_at
        FROM public.assignment_submissions
        ORDER BY assignment_id, submitted_by, attempt_number DESC, submitted_at DESC
    )
    SELECT
        assignments.id,
        assignments.school_id,
        schools.name,
        assignments.child_id,
        assignments.title,
        assignments.description,
        assignments.category,
        assignments.due_at,
        assignments.assigned_by,
        assignments.created_at,
        CASE
            WHEN COUNT(latest.submitted_by) FILTER (WHERE latest.status = 'changes_requested') > 0 THEN 'changes_requested'
            WHEN COUNT(latest.submitted_by) FILTER (WHERE latest.status IN ('submitted', 'resubmitted')) > 0 THEN 'submitted'
            WHEN COUNT(latest.submitted_by) FILTER (WHERE latest.status = 'accepted') = COUNT(DISTINCT recipients.user_id)
                 AND COUNT(DISTINCT recipients.user_id) > 0 THEN 'accepted'
            ELSE 'not_started'
        END,
        NULL::TIMESTAMPTZ,
        NULL::TIMESTAMPTZ,
        FALSE,
        MAX(latest.submitted_at),
        CASE
            WHEN COUNT(latest.submitted_by) FILTER (WHERE latest.status = 'changes_requested') > 0 THEN 'changes_requested'
            WHEN COUNT(latest.submitted_by) FILTER (WHERE latest.status IN ('submitted', 'resubmitted')) > 0 THEN 'submitted'
            WHEN COUNT(latest.submitted_by) FILTER (WHERE latest.status = 'accepted') > 0 THEN 'accepted'
            ELSE NULL
        END,
        MAX(latest.reviewed_at),
        NULL::TEXT,
        children.first_name,
        children.last_name,
        (SELECT COUNT(*) FROM public.assignment_materials materials WHERE materials.assignment_id = assignments.id),
        COUNT(DISTINCT latest.submitted_by),
        COUNT(DISTINCT recipients.user_id),
        COUNT(DISTINCT latest.submitted_by) FILTER (WHERE latest.status IN ('submitted', 'resubmitted')),
        COUNT(DISTINCT latest.submitted_by) FILTER (WHERE latest.status = 'changes_requested'),
        COUNT(DISTINCT recipients.user_id) FILTER (
            WHERE NOT EXISTS (
                SELECT 1 FROM latest_submissions candidate
                WHERE candidate.assignment_id = assignments.id
                  AND candidate.submitted_by = recipients.user_id
            )
        ),
        COUNT(DISTINCT recipients.user_id) FILTER (
            WHERE assignments.due_at < NOW()
              AND (latest.submitted_by IS NULL OR latest.status = 'changes_requested')
        ),
        COUNT(DISTINCT latest.submitted_by) FILTER (WHERE latest.status = 'accepted')
    FROM public.assignments assignments
    JOIN public.schools schools ON schools.id = assignments.school_id
    LEFT JOIN public.assignment_recipients recipients ON recipients.assignment_id = assignments.id
    LEFT JOIN latest_submissions latest
      ON latest.assignment_id = assignments.id
     AND latest.submitted_by = recipients.user_id
    LEFT JOIN public.children children ON children.id = assignments.child_id
    WHERE assignments.school_id = input_school_id
      AND assignments.assigned_by = auth.uid()
      AND assignments.status <> 'archived'
      AND (input_categories IS NULL OR cardinality(input_categories) = 0 OR assignments.category = ANY(input_categories))
    GROUP BY assignments.id, schools.name, children.first_name, children.last_name
    ORDER BY MAX(latest.submitted_at) DESC NULLS LAST, assignments.created_at DESC;
$$;

DROP FUNCTION IF EXISTS public.fetch_assignment_viewer_capabilities(UUID);
CREATE FUNCTION public.fetch_assignment_viewer_capabilities(input_assignment_id UUID)
RETURNS TABLE (
    user_id UUID,
    is_recipient BOOLEAN,
    can_acknowledge BOOLEAN,
    can_submit BOOLEAN,
    can_review BOOLEAN,
    can_manage BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        auth.uid(),
        public.is_assignment_recipient(input_assignment_id, auth.uid()),
        public.is_assignment_recipient(input_assignment_id, auth.uid()),
        public.can_submit_assignment(input_assignment_id, auth.uid()),
        public.can_manage_assignment(input_assignment_id, auth.uid()),
        public.can_manage_assignment(input_assignment_id, auth.uid())
    WHERE auth.uid() IS NOT NULL
      AND public.can_view_assignment(input_assignment_id, auth.uid());
$$;

DROP FUNCTION IF EXISTS public.fetch_assignment_detail(UUID);
CREATE FUNCTION public.fetch_assignment_detail(input_assignment_id UUID)
RETURNS TABLE (
    assignment JSONB,
    capabilities JSONB,
    materials JSONB,
    recipients JSONB,
    submissions JSONB,
    attachments JSONB,
    read_receipts JSONB,
    feedback_messages JSONB,
    events JSONB
)
LANGUAGE sql
STABLE
SECURITY INVOKER
SET search_path = public
AS $$
    SELECT
        to_jsonb(assignment_row),
        to_jsonb(capability_row),
        COALESCE((
            SELECT jsonb_agg(to_jsonb(material_row) ORDER BY material_row.created_at)
            FROM public.assignment_materials material_row
            WHERE material_row.assignment_id = assignment_row.id
        ), '[]'::JSONB),
        COALESCE((
            SELECT jsonb_agg(to_jsonb(recipient_row) ORDER BY recipient_row.created_at)
            FROM public.assignment_recipients recipient_row
            WHERE recipient_row.assignment_id = assignment_row.id
        ), '[]'::JSONB),
        COALESCE((
            SELECT jsonb_agg(
                to_jsonb(submission_row)
                ORDER BY submission_row.attempt_number DESC, submission_row.submitted_at DESC
            )
            FROM public.assignment_submissions submission_row
            WHERE submission_row.assignment_id = assignment_row.id
        ), '[]'::JSONB),
        COALESCE((
            SELECT jsonb_agg(to_jsonb(attachment_row) ORDER BY attachment_row.created_at DESC)
            FROM public.assignment_submission_attachments attachment_row
            JOIN public.assignment_submissions attachment_submission
              ON attachment_submission.id = attachment_row.submission_id
            WHERE attachment_submission.assignment_id = assignment_row.id
        ), '[]'::JSONB),
        COALESCE((
            SELECT jsonb_agg(to_jsonb(receipt_row) ORDER BY receipt_row.checked_at DESC)
            FROM public.assignment_read_receipts receipt_row
            WHERE receipt_row.assignment_id = assignment_row.id
        ), '[]'::JSONB),
        COALESCE((
            SELECT jsonb_agg(to_jsonb(feedback_row) ORDER BY feedback_row.created_at)
            FROM public.assignment_feedback_messages feedback_row
            WHERE feedback_row.assignment_id = assignment_row.id
        ), '[]'::JSONB),
        COALESCE((
            SELECT jsonb_agg(to_jsonb(event_row) ORDER BY event_row.created_at DESC)
            FROM public.assignment_events event_row
            WHERE event_row.assignment_id = assignment_row.id
        ), '[]'::JSONB)
    FROM public.assignments assignment_row
    CROSS JOIN LATERAL public.fetch_assignment_viewer_capabilities(assignment_row.id) capability_row
    WHERE assignment_row.id = input_assignment_id;
$$;

-- Compatibility endpoint for clients that still pass a selected school. It
-- intentionally exposes only the caller's recipient row and latest attempt;
-- creators use the separate review queue.
CREATE OR REPLACE FUNCTION public.fetch_assignment_inbox(
    input_school_id UUID,
    input_categories TEXT[] DEFAULT NULL
)
RETURNS TABLE (
    assignment_id UUID,
    school_id UUID,
    child_id UUID,
    title TEXT,
    description TEXT,
    category TEXT,
    due_at TIMESTAMPTZ,
    assigned_by UUID,
    created_at TIMESTAMPTZ,
    completion_status TEXT,
    submitted_at TIMESTAMPTZ,
    review_status TEXT,
    reviewed_at TIMESTAMPTZ,
    reviewer_message TEXT,
    child_first_name TEXT,
    child_last_name TEXT,
    material_count BIGINT,
    submission_count BIGINT,
    recipient_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        assignments.id,
        assignments.school_id,
        assignments.child_id,
        assignments.title,
        assignments.description,
        assignments.category,
        assignments.due_at,
        assignments.assigned_by,
        assignments.created_at,
        recipients.completion_status,
        latest_submission.submitted_at,
        latest_submission.status,
        latest_submission.reviewed_at,
        latest_submission.reviewer_message,
        children.first_name,
        children.last_name,
        (SELECT COUNT(*) FROM public.assignment_materials materials WHERE materials.assignment_id = assignments.id),
        (SELECT COUNT(*) FROM public.assignment_submissions submissions WHERE submissions.assignment_id = assignments.id AND submissions.submitted_by = auth.uid()),
        1::BIGINT
    FROM public.assignment_recipients recipients
    JOIN public.assignments assignments ON assignments.id = recipients.assignment_id
    LEFT JOIN LATERAL (
        SELECT submissions.submitted_at, submissions.status, submissions.reviewed_at, submissions.reviewer_message
        FROM public.assignment_submissions submissions
        WHERE submissions.assignment_id = assignments.id
          AND submissions.submitted_by = auth.uid()
        ORDER BY submissions.attempt_number DESC, submissions.submitted_at DESC
        LIMIT 1
    ) latest_submission ON TRUE
    LEFT JOIN public.children children ON children.id = assignments.child_id
    WHERE recipients.user_id = auth.uid()
      AND assignments.school_id = input_school_id
      AND (
          assignments.status = 'published'
          OR (assignments.status = 'scheduled' AND assignments.publish_at <= NOW())
      )
      AND (input_categories IS NULL OR cardinality(input_categories) = 0 OR assignments.category = ANY(input_categories))
    ORDER BY assignments.due_at NULLS LAST, assignments.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.publish_due_assignments()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    assignment_record public.assignments%ROWTYPE;
    notification_id UUID;
    published_count INTEGER := 0;
BEGIN
    IF actor IS NULL AND COALESCE(auth.role(), '') <> 'service_role' THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    FOR assignment_record IN
        UPDATE public.assignments AS due_assignment
        SET status = 'published', updated_at = NOW()
        WHERE due_assignment.status = 'scheduled'
          AND due_assignment.publish_at <= NOW()
          AND (
              COALESCE(auth.role(), '') = 'service_role'
              OR due_assignment.assigned_by = actor
              OR EXISTS (
                  SELECT 1
                  FROM public.assignment_recipients recipients
                  WHERE recipients.assignment_id = due_assignment.id
                    AND recipients.user_id = actor
              )
          )
        RETURNING due_assignment.*
    LOOP
        INSERT INTO public.assignment_events (assignment_id, school_id, actor_id, event_type)
        VALUES (assignment_record.id, assignment_record.school_id, assignment_record.assigned_by, 'published');

        INSERT INTO public.notifications (
            school_id, title, body, category, source_type, source_id, created_by, dedupe_key
        )
        VALUES (
            assignment_record.school_id,
            assignment_record.title,
            CASE
                WHEN assignment_record.due_at IS NULL THEN 'No due date. Status: Not submitted.'
                ELSE 'Due ' || to_char(assignment_record.due_at AT TIME ZONE 'UTC', 'Mon DD, YYYY HH24:MI') || ' UTC. Status: Not submitted.'
            END,
            'assignment_assigned',
            'assignment',
            assignment_record.id,
            assignment_record.assigned_by,
            'assignment:published:' || assignment_record.id::TEXT
        )
        ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL
        DO UPDATE SET title = EXCLUDED.title
        RETURNING id INTO notification_id;

        INSERT INTO public.notification_recipients (notification_id, user_id)
        SELECT notification_id, recipients.user_id
        FROM public.assignment_recipients recipients
        WHERE recipients.assignment_id = assignment_record.id
        ON CONFLICT DO NOTHING;

        published_count := published_count + 1;
    END LOOP;

    RETURN published_count;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_assignment_v2(
    input_school_id UUID,
    input_title TEXT,
    input_description TEXT DEFAULT NULL,
    input_category TEXT DEFAULT 'general',
    input_audience_role TEXT DEFAULT NULL,
    input_child_id UUID DEFAULT NULL,
    input_due_at TIMESTAMPTZ DEFAULT NULL,
    input_requires_review BOOLEAN DEFAULT TRUE,
    input_recipient_ids UUID[] DEFAULT '{}'::UUID[],
    input_materials JSONB DEFAULT '[]'::JSONB,
    input_status TEXT DEFAULT 'published',
    input_publish_at TIMESTAMPTZ DEFAULT NULL,
    input_close_at TIMESTAMPTZ DEFAULT NULL,
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    existing_assignment_id UUID;
    created_assignment public.assignments%ROWTYPE;
    notification_id UUID;
    expected_count INTEGER;
    inserted_count INTEGER;
BEGIN
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(hashtextextended(
            actor::TEXT || ':create:' || btrim(input_idempotency_key), 0
        ));
        SELECT result_id INTO existing_assignment_id
        FROM public.assignment_mutation_requests
        WHERE actor_id = actor
          AND idempotency_key = btrim(input_idempotency_key)
          AND operation = 'create';

        IF existing_assignment_id IS NOT NULL THEN
            RETURN QUERY SELECT * FROM public.assignments WHERE id = existing_assignment_id;
            RETURN;
        END IF;
    END IF;

    IF input_recipient_ids IS NOT NULL AND EXISTS (
        SELECT 1
        FROM unnest(input_recipient_ids) requested(user_id)
        WHERE NOT EXISTS (
            SELECT 1
            FROM public.school_memberships memberships
            WHERE memberships.school_id = input_school_id
              AND memberships.user_id = requested.user_id
              AND memberships.active = TRUE
        )
    ) THEN
        RAISE EXCEPTION 'Every assignment recipient must be an active member of the selected school';
    END IF;

    expected_count := COALESCE((SELECT COUNT(DISTINCT id) FROM unnest(input_recipient_ids) ids(id)), 0);
    IF expected_count = 0 AND input_child_id IS NULL THEN
        RAISE EXCEPTION 'Select at least one assignment recipient';
    END IF;

    SELECT * INTO created_assignment
    FROM public.create_assignment(
        input_school_id,
        input_title,
        input_description,
        input_category,
        input_audience_role,
        input_child_id,
        input_due_at,
        input_requires_review,
        input_recipient_ids,
        input_materials,
        input_status,
        input_publish_at,
        input_close_at
    )
    LIMIT 1;

    SELECT COUNT(*) INTO inserted_count
    FROM public.assignment_recipients
    WHERE assignment_id = created_assignment.id;

    IF inserted_count = 0 OR (expected_count > 0 AND inserted_count <> expected_count) THEN
        RAISE EXCEPTION 'Assignment recipient creation failed: expected %, created %', expected_count, inserted_count;
    END IF;

    IF input_status = 'published' THEN
        UPDATE public.notifications
        SET dedupe_key = 'assignment:published:' || created_assignment.id::TEXT
        WHERE category = 'assignment_assigned'
          AND source_type = 'assignment'
          AND source_id = created_assignment.id
        RETURNING id INTO notification_id;

        IF notification_id IS NOT NULL THEN
            INSERT INTO public.notification_recipients (notification_id, user_id)
            SELECT notification_id, recipients.user_id
            FROM public.assignment_recipients recipients
            WHERE recipients.assignment_id = created_assignment.id
            ON CONFLICT DO NOTHING;
        END IF;
    END IF;

    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NOT NULL THEN
        INSERT INTO public.assignment_mutation_requests (actor_id, idempotency_key, operation, result_id)
        VALUES (actor, btrim(input_idempotency_key), 'create', created_assignment.id);
    END IF;

    RETURN QUERY SELECT * FROM public.assignments WHERE id = created_assignment.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_assignment_v2(
    input_assignment_id UUID,
    input_feedback_text TEXT DEFAULT NULL,
    input_attachments JSONB DEFAULT '[]'::JSONB,
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.assignment_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    assignment_record public.assignments%ROWTYPE;
    previous_submission public.assignment_submissions%ROWTYPE;
    saved_submission public.assignment_submissions%ROWTYPE;
    existing_submission_id UUID;
    attachment JSONB;
    attachment_path TEXT;
    expected_prefix TEXT;
    next_attempt INTEGER;
    next_status TEXT;
    notification_id UUID;
BEGIN
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(hashtextextended(
            actor::TEXT || ':submit:' || btrim(input_idempotency_key), 0
        ));
        SELECT result_id INTO existing_submission_id
        FROM public.assignment_mutation_requests
        WHERE actor_id = actor
          AND idempotency_key = btrim(input_idempotency_key)
          AND operation = 'submit';

        IF existing_submission_id IS NOT NULL THEN
            RETURN QUERY SELECT * FROM public.assignment_submissions WHERE id = existing_submission_id;
            RETURN;
        END IF;
    END IF;

    SELECT * INTO assignment_record FROM public.assignments WHERE id = input_assignment_id;
    IF NOT FOUND OR NOT public.can_submit_assignment(input_assignment_id, actor) THEN
        RAISE EXCEPTION 'You cannot submit this assignment in its current state';
    END IF;

    SELECT * INTO previous_submission
    FROM public.assignment_submissions
    WHERE assignment_id = input_assignment_id
      AND submitted_by = actor
    ORDER BY attempt_number DESC, submitted_at DESC
    LIMIT 1;

    next_attempt := COALESCE(previous_submission.attempt_number, 0) + 1;
    next_status := CASE WHEN next_attempt = 1 THEN 'submitted' ELSE 'resubmitted' END;
    expected_prefix := 'schools/' || assignment_record.school_id::TEXT
        || '/assignments/' || assignment_record.id::TEXT
        || '/submissions/' || actor::TEXT || '/';

    FOR attachment IN SELECT * FROM jsonb_array_elements(COALESCE(input_attachments, '[]'::JSONB)) LOOP
        attachment_path := NULLIF(attachment->>'private_file_path', '');
        IF attachment_path IS NULL OR LOWER(attachment_path) NOT LIKE LOWER(expected_prefix) || '%' THEN
            RAISE EXCEPTION 'Assignment upload path is invalid';
        END IF;
    END LOOP;

    INSERT INTO public.assignment_submissions (
        assignment_id, school_id, submitted_by, attempt_number,
        supersedes_submission_id, status, submitted_at
    ) VALUES (
        assignment_record.id, assignment_record.school_id, actor, next_attempt,
        previous_submission.id, next_status, NOW()
    ) RETURNING * INTO saved_submission;

    FOR attachment IN SELECT * FROM jsonb_array_elements(COALESCE(input_attachments, '[]'::JSONB)) LOOP
        INSERT INTO public.assignment_submission_attachments (
            submission_id, school_id, private_file_path, file_name, content_type
        ) VALUES (
            saved_submission.id,
            assignment_record.school_id,
            attachment->>'private_file_path',
            NULLIF(attachment->>'file_name', ''),
            NULLIF(attachment->>'content_type', '')
        );
    END LOOP;

    IF NULLIF(btrim(COALESCE(input_feedback_text, '')), '') IS NOT NULL THEN
        INSERT INTO public.assignment_feedback_messages (
            assignment_id, submission_id, school_id, sender_id, recipient_id, body
        ) VALUES (
            assignment_record.id, saved_submission.id, assignment_record.school_id,
            actor, actor, btrim(input_feedback_text)
        );
    END IF;

    UPDATE public.assignment_recipients
    SET completion_status = next_status,
        completed_at = NULL,
        viewed_at = COALESCE(viewed_at, NOW())
    WHERE assignment_id = assignment_record.id
      AND user_id = actor;

    INSERT INTO public.assignment_events (assignment_id, school_id, actor_id, event_type, metadata)
    VALUES (
        assignment_record.id, assignment_record.school_id, actor, next_status,
        jsonb_build_object('submission_id', saved_submission.id, 'recipient_id', actor, 'attempt_number', next_attempt)
    );

    IF assignment_record.assigned_by IS NOT NULL AND assignment_record.assigned_by <> actor THEN
        INSERT INTO public.notifications (
            school_id, title, body, category, source_type, source_id, created_by, dedupe_key
        ) VALUES (
            assignment_record.school_id,
            assignment_record.title,
            'Status: ' || initcap(next_status) || '. Waiting for review.',
            'assignment_submitted',
            'assignment',
            assignment_record.id,
            actor,
            'assignment:submission:' || saved_submission.id::TEXT
        ) RETURNING id INTO notification_id;

        INSERT INTO public.notification_recipients (notification_id, user_id)
        VALUES (notification_id, assignment_record.assigned_by)
        ON CONFLICT DO NOTHING;
    END IF;

    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NOT NULL THEN
        INSERT INTO public.assignment_mutation_requests (actor_id, idempotency_key, operation, result_id)
        VALUES (actor, btrim(input_idempotency_key), 'submit', saved_submission.id);
    END IF;

    RETURN QUERY SELECT * FROM public.assignment_submissions WHERE id = saved_submission.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fetch_assignment_submission_mutation(
    input_assignment_id UUID,
    input_idempotency_key TEXT
)
RETURNS SETOF public.assignment_submissions
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT submissions.*
    FROM public.assignment_mutation_requests requests
    JOIN public.assignment_submissions submissions ON submissions.id = requests.result_id
    WHERE requests.actor_id = auth.uid()
      AND requests.operation = 'submit'
      AND requests.idempotency_key = btrim(input_idempotency_key)
      AND submissions.assignment_id = input_assignment_id;
$$;

CREATE OR REPLACE FUNCTION public.review_assignment_submission_v2(
    input_submission_id UUID,
    input_status TEXT,
    input_reviewer_message TEXT DEFAULT NULL,
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.assignment_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    submission_record public.assignment_submissions%ROWTYPE;
    latest_submission_id UUID;
    assignment_record public.assignments%ROWTYPE;
    existing_result_id UUID;
    notification_id UUID;
BEGIN
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF input_status NOT IN ('accepted', 'changes_requested') THEN
        RAISE EXCEPTION 'Review status must be accepted or changes_requested';
    END IF;

    IF input_status = 'changes_requested'
       AND NULLIF(btrim(COALESCE(input_reviewer_message, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Feedback is required when requesting changes';
    END IF;

    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(hashtextextended(
            actor::TEXT || ':review:' || btrim(input_idempotency_key), 0
        ));
        SELECT result_id INTO existing_result_id
        FROM public.assignment_mutation_requests
        WHERE actor_id = actor
          AND idempotency_key = btrim(input_idempotency_key)
          AND operation = 'review';
        IF existing_result_id IS NOT NULL THEN
            RETURN QUERY SELECT * FROM public.assignment_submissions WHERE id = existing_result_id;
            RETURN;
        END IF;
    END IF;

    SELECT * INTO submission_record
    FROM public.assignment_submissions
    WHERE id = input_submission_id
    FOR UPDATE;

    IF NOT FOUND OR NOT public.can_review_assignment_submission(input_submission_id, actor) THEN
        RAISE EXCEPTION 'Only the assignment creator can review this submission';
    END IF;

    SELECT id INTO latest_submission_id
    FROM public.assignment_submissions
    WHERE assignment_id = submission_record.assignment_id
      AND submitted_by = submission_record.submitted_by
    ORDER BY attempt_number DESC, submitted_at DESC
    LIMIT 1;

    IF latest_submission_id <> submission_record.id
       OR submission_record.status NOT IN ('submitted', 'resubmitted') THEN
        RAISE EXCEPTION 'Only the latest pending attempt can be reviewed';
    END IF;

    SELECT * INTO assignment_record
    FROM public.assignments
    WHERE id = submission_record.assignment_id;

    UPDATE public.assignment_submissions
    SET status = input_status,
        reviewer_message = NULLIF(btrim(COALESCE(input_reviewer_message, '')), ''),
        reviewed_by = actor,
        reviewed_at = NOW()
    WHERE id = submission_record.id
    RETURNING * INTO submission_record;

    UPDATE public.assignment_recipients
    SET completion_status = input_status,
        completed_at = CASE WHEN input_status = 'accepted' THEN NOW() ELSE NULL END
    WHERE assignment_id = assignment_record.id
      AND user_id = submission_record.submitted_by;

    IF NULLIF(btrim(COALESCE(input_reviewer_message, '')), '') IS NOT NULL THEN
        INSERT INTO public.assignment_feedback_messages (
            assignment_id, submission_id, school_id, sender_id, recipient_id, body
        ) VALUES (
            assignment_record.id, submission_record.id, assignment_record.school_id,
            actor, submission_record.submitted_by, btrim(input_reviewer_message)
        );
    END IF;

    INSERT INTO public.assignment_events (assignment_id, school_id, actor_id, event_type, metadata)
    VALUES (
        assignment_record.id, assignment_record.school_id, actor, input_status,
        jsonb_build_object(
            'submission_id', submission_record.id,
            'recipient_id', submission_record.submitted_by,
            'attempt_number', submission_record.attempt_number
        )
    );

    INSERT INTO public.notifications (
        school_id, title, body, category, source_type, source_id, created_by, dedupe_key
    ) VALUES (
        assignment_record.school_id,
        assignment_record.title,
        'Status: ' || initcap(replace(input_status, '_', ' '))
            || COALESCE('. ' || NULLIF(btrim(input_reviewer_message), ''), '.'),
        'assignment_reviewed',
        'assignment',
        assignment_record.id,
        actor,
        'assignment:review:' || submission_record.id::TEXT || ':' || input_status
    ) RETURNING id INTO notification_id;

    INSERT INTO public.notification_recipients (notification_id, user_id)
    VALUES (notification_id, submission_record.submitted_by)
    ON CONFLICT DO NOTHING;

    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NOT NULL THEN
        INSERT INTO public.assignment_mutation_requests (actor_id, idempotency_key, operation, result_id)
        VALUES (actor, btrim(input_idempotency_key), 'review', submission_record.id);
    END IF;

    RETURN QUERY SELECT * FROM public.assignment_submissions WHERE id = submission_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.post_assignment_comment(
    input_submission_id UUID,
    input_body TEXT,
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.assignment_feedback_messages
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    submission_record public.assignment_submissions%ROWTYPE;
    assignment_record public.assignments%ROWTYPE;
    saved_message public.assignment_feedback_messages%ROWTYPE;
    existing_result_id UUID;
    target_user UUID;
    notification_id UUID;
BEGIN
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;
    IF NULLIF(btrim(COALESCE(input_body, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Comment cannot be empty';
    END IF;

    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(hashtextextended(
            actor::TEXT || ':comment:' || btrim(input_idempotency_key), 0
        ));
        SELECT result_id INTO existing_result_id
        FROM public.assignment_mutation_requests
        WHERE actor_id = actor
          AND idempotency_key = btrim(input_idempotency_key)
          AND operation = 'comment';
        IF existing_result_id IS NOT NULL THEN
            RETURN QUERY SELECT * FROM public.assignment_feedback_messages WHERE id = existing_result_id;
            RETURN;
        END IF;
    END IF;

    SELECT * INTO submission_record
    FROM public.assignment_submissions
    WHERE id = input_submission_id;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Assignment submission was not found';
    END IF;

    SELECT * INTO assignment_record
    FROM public.assignments
    WHERE id = submission_record.assignment_id;

    IF actor <> submission_record.submitted_by AND actor <> assignment_record.assigned_by THEN
        RAISE EXCEPTION 'Only the recipient and assignment creator can comment';
    END IF;

    INSERT INTO public.assignment_feedback_messages (
        assignment_id, submission_id, school_id, sender_id, recipient_id, body
    ) VALUES (
        assignment_record.id, submission_record.id, assignment_record.school_id,
        actor, submission_record.submitted_by, btrim(input_body)
    ) RETURNING * INTO saved_message;

    target_user := CASE
        WHEN actor = submission_record.submitted_by THEN assignment_record.assigned_by
        ELSE submission_record.submitted_by
    END;

    INSERT INTO public.assignment_events (assignment_id, school_id, actor_id, event_type, metadata)
    VALUES (
        assignment_record.id, assignment_record.school_id, actor, 'commented',
        jsonb_build_object('submission_id', submission_record.id, 'recipient_id', submission_record.submitted_by)
    );

    IF target_user IS NOT NULL AND target_user <> actor THEN
        INSERT INTO public.notifications (
            school_id, title, body, category, source_type, source_id, created_by, dedupe_key
        ) VALUES (
            assignment_record.school_id,
            assignment_record.title,
            btrim(input_body),
            'assignment_feedback',
            'assignment',
            assignment_record.id,
            actor,
            'assignment:comment:' || saved_message.id::TEXT
        ) RETURNING id INTO notification_id;

        INSERT INTO public.notification_recipients (notification_id, user_id)
        VALUES (notification_id, target_user)
        ON CONFLICT DO NOTHING;
    END IF;

    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NOT NULL THEN
        INSERT INTO public.assignment_mutation_requests (actor_id, idempotency_key, operation, result_id)
        VALUES (actor, btrim(input_idempotency_key), 'comment', saved_message.id);
    END IF;

    RETURN QUERY SELECT * FROM public.assignment_feedback_messages WHERE id = saved_message.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_assignment(
    input_assignment_id UUID,
    input_file_name TEXT DEFAULT NULL,
    input_file_path TEXT DEFAULT NULL,
    input_content_type TEXT DEFAULT NULL,
    input_feedback_text TEXT DEFAULT NULL
)
RETURNS SETOF public.assignment_submissions
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT *
    FROM public.submit_assignment_v2(
        input_assignment_id,
        input_feedback_text,
        CASE
            WHEN input_file_path IS NULL THEN '[]'::JSONB
            ELSE jsonb_build_array(jsonb_build_object(
                'private_file_path', input_file_path,
                'file_name', input_file_name,
                'content_type', input_content_type
            ))
        END,
        gen_random_uuid()::TEXT
    );
$$;

CREATE OR REPLACE FUNCTION public.review_assignment_submission(
    input_submission_id UUID,
    input_status TEXT,
    input_reviewer_message TEXT DEFAULT NULL
)
RETURNS SETOF public.assignment_submissions
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT *
    FROM public.review_assignment_submission_v2(
        input_submission_id,
        input_status,
        input_reviewer_message,
        gen_random_uuid()::TEXT
    );
$$;

DROP FUNCTION IF EXISTS public.fetch_my_notifications(INTEGER);
CREATE FUNCTION public.fetch_my_notifications(input_limit INTEGER DEFAULT 100)
RETURNS TABLE (
    id UUID,
    school_id UUID,
    school_name TEXT,
    title TEXT,
    body TEXT,
    category TEXT,
    source_type TEXT,
    source_id UUID,
    created_by UUID,
    created_at TIMESTAMPTZ,
    read_at TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT
        notifications.id,
        notifications.school_id,
        schools.name,
        notifications.title,
        notifications.body,
        notifications.category,
        notifications.source_type,
        notifications.source_id,
        notifications.created_by,
        notifications.created_at,
        recipients.read_at
    FROM public.notification_recipients recipients
    JOIN public.notifications notifications ON notifications.id = recipients.notification_id
    JOIN public.schools schools ON schools.id = notifications.school_id
    WHERE recipients.user_id = auth.uid()
    ORDER BY notifications.created_at DESC
    LIMIT LEAST(GREATEST(COALESCE(input_limit, 100), 1), 200);
$$;

CREATE OR REPLACE FUNCTION public.mark_notification_read(input_notification_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.notification_recipients
    SET read_at = COALESCE(read_at, NOW())
    WHERE notification_id = input_notification_id
      AND user_id = auth.uid();

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Notification was not found for this user';
    END IF;
END;
$$;

-- Keep lifecycle transitions creator-owned and make publishing retry-safe.
CREATE OR REPLACE FUNCTION public.set_assignment_status(
    input_assignment_id UUID,
    input_status TEXT
)
RETURNS SETOF public.assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    assignment_record public.assignments%ROWTYPE;
    notification_id UUID;
BEGIN
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;
    IF input_status NOT IN ('published', 'closed', 'archived') THEN
        RAISE EXCEPTION 'Status must be published, closed, or archived';
    END IF;

    SELECT * INTO assignment_record
    FROM public.assignments
    WHERE id = input_assignment_id;

    IF NOT FOUND OR NOT public.can_manage_assignment(input_assignment_id, actor) THEN
        RAISE EXCEPTION 'Only the assignment creator can change its lifecycle';
    END IF;

    IF assignment_record.status = input_status THEN
        RETURN QUERY SELECT * FROM public.assignments WHERE id = input_assignment_id;
        RETURN;
    END IF;

    UPDATE public.assignments
    SET status = input_status,
        publish_at = CASE WHEN input_status = 'published' THEN COALESCE(publish_at, NOW()) ELSE publish_at END,
        updated_at = NOW()
    WHERE id = input_assignment_id
    RETURNING * INTO assignment_record;

    INSERT INTO public.assignment_events (assignment_id, school_id, actor_id, event_type)
    VALUES (assignment_record.id, assignment_record.school_id, actor, input_status);

    IF input_status = 'published' THEN
        INSERT INTO public.notifications (
            school_id, title, body, category, source_type, source_id, created_by, dedupe_key
        ) VALUES (
            assignment_record.school_id,
            assignment_record.title,
            CASE
                WHEN assignment_record.due_at IS NULL THEN 'No due date. Status: Not submitted.'
                ELSE 'Due ' || to_char(assignment_record.due_at AT TIME ZONE 'UTC', 'Mon DD, YYYY HH24:MI') || ' UTC. Status: Not submitted.'
            END,
            'assignment_assigned',
            'assignment',
            assignment_record.id,
            actor,
            'assignment:published:' || assignment_record.id::TEXT
        )
        ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL
        DO UPDATE SET title = EXCLUDED.title, body = EXCLUDED.body
        RETURNING id INTO notification_id;

        INSERT INTO public.notification_recipients (notification_id, user_id)
        SELECT notification_id, recipients.user_id
        FROM public.assignment_recipients recipients
        WHERE recipients.assignment_id = assignment_record.id
        ON CONFLICT DO NOTHING;
    END IF;

    RETURN QUERY SELECT * FROM public.assignments WHERE id = assignment_record.id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.can_review_assignment_submission(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_assignment_viewed(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.acknowledge_assignment(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_my_assignment_agenda(TEXT[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_my_assignment_review_queue(UUID, TEXT[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_assignment_viewer_capabilities(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_assignment_detail(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.publish_due_assignments() TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_assignment_v2(UUID, TEXT, TEXT, TEXT, TEXT, UUID, TIMESTAMPTZ, BOOLEAN, UUID[], JSONB, TEXT, TIMESTAMPTZ, TIMESTAMPTZ, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_assignment_v2(UUID, TEXT, JSONB, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_assignment_submission_mutation(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_assignment_submission_v2(UUID, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.post_assignment_comment(UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_my_notifications(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_notification_read(UUID) TO authenticated;

-- Keep onboarding reviewer authority as the final assignment authorization
-- definition after the Phase 3 feedback-loop hardening above.
CREATE OR REPLACE FUNCTION public.can_manage_assignment(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.assignments assignments
        WHERE assignments.id = assignment_uuid
          AND (
              assignments.assigned_by = user_uuid
              OR EXISTS (
                  SELECT 1
                  FROM public.onboarding_requirement_instances requirement_instances
                  JOIN public.onboarding_instances instances ON instances.id = requirement_instances.onboarding_instance_id
                  JOIN public.onboarding_templates templates ON templates.id = instances.template_id
                  WHERE requirement_instances.assignment_id = assignments.id
                    AND public.is_onboarding_template_manager(templates.school_id, templates.target_role, user_uuid)
              )
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.can_review_assignment(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.can_manage_assignment(assignment_uuid, user_uuid)
       AND NOT public.is_assignment_recipient(assignment_uuid, user_uuid);
$$;

CREATE OR REPLACE FUNCTION public.can_review_assignment_submission(submission_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.assignment_submissions submissions
        WHERE submissions.id = submission_uuid
          AND submissions.submitted_by <> user_uuid
          AND public.can_review_assignment(submissions.assignment_id, user_uuid)
    );
$$;

CREATE OR REPLACE FUNCTION public.can_view_assignment(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.assignments assignments
        WHERE assignments.id = assignment_uuid
          AND (
              assignments.assigned_by = user_uuid
              OR public.is_assignment_recipient(assignments.id, user_uuid)
              OR public.can_review_assignment(assignments.id, user_uuid)
          )
    );
$$;

GRANT EXECUTE ON FUNCTION public.can_manage_assignment(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_review_assignment(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_review_assignment_submission(UUID, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_view_assignment(UUID, UUID) TO authenticated;

NOTIFY pgrst, 'reload schema';

-- Migration: 20260721010000_schema_compatibility_and_invites.sql

-- Compatibility contract and onboarding/invitation release blockers.

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ SELECT 20260721010000::BIGINT; $$;

REVOKE ALL ON FUNCTION public.get_firefly_schema_version() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_firefly_schema_version() TO authenticated;

CREATE OR REPLACE FUNCTION public.create_child_for_current_parent(
    school_id UUID,
    first_name TEXT,
    last_name TEXT,
    birthdate DATE DEFAULT NULL
)
RETURNS SETOF public.children
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID;
    created_child public.children%ROWTYPE;
    classroom_uuid UUID;
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

    -- A new parent needs this narrowly scoped action before full access.
    IF NOT EXISTS (
        SELECT 1 FROM public.school_memberships memberships
        WHERE memberships.school_id = $1
          AND memberships.user_id = actor
          AND memberships.active = TRUE
          AND memberships.role = 'parent'
    ) THEN
        RAISE EXCEPTION 'Only parents can add children to their active school';
    END IF;

    IF NULLIF(TRIM($2), '') IS NULL OR NULLIF(TRIM($3), '') IS NULL THEN
        RAISE EXCEPTION 'Child first and last name are required';
    END IF;

    INSERT INTO public.children (school_id, first_name, last_name, birthdate, active)
    VALUES ($1, TRIM($2), TRIM($3), $4, TRUE)
    RETURNING * INTO created_child;

    INSERT INTO public.child_guardians (child_id, guardian_id, relationship)
    VALUES (created_child.id, actor, 'Parent')
    ON CONFLICT (child_id, guardian_id) DO NOTHING;

    classroom_uuid := public.default_classroom_for_school($1);
    INSERT INTO public.classroom_children (classroom_id, child_id)
    VALUES (classroom_uuid, created_child.id)
    ON CONFLICT DO NOTHING;

    RETURN QUERY SELECT * FROM public.children WHERE id = created_child.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.preview_role_invite(invite_token TEXT)
RETURNS TABLE (
    invite_id UUID,
    school_id UUID,
    school_name TEXT,
    role TEXT,
    expires_at TIMESTAMPTZ
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    joining_email TEXT;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    joining_email := lower(COALESCE(auth.jwt()->>'email', ''));
    IF joining_email = '' THEN RAISE EXCEPTION 'Your account email could not be verified'; END IF;

    RETURN QUERY
    SELECT invites.id, schools.id, schools.name, invites.role, invites.expires_at
    FROM public.role_invites invites
    JOIN public.schools schools ON schools.id = invites.school_id
    WHERE (
            invites.token_hash = encode(extensions.digest(NULLIF(TRIM(invite_token), ''), 'sha256'), 'hex')
            OR invites.token = NULLIF(TRIM(invite_token), '')
          )
      AND invites.status = 'pending'
      AND (invites.expires_at IS NULL OR invites.expires_at > NOW())
      AND lower(invites.email) = joining_email
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'This invitation is invalid, expired, or belongs to another account';
    END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.preview_role_invite(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.preview_role_invite(TEXT) TO authenticated;

-- Migration: 20260721020000_private_media.sql

-- Deny-by-default media storage and path-based references.

ALTER TABLE public.profiles ADD COLUMN IF NOT EXISTS avatar_path TEXT;
ALTER TABLE public.schools ADD COLUMN IF NOT EXISTS profile_image_path TEXT;
ALTER TABLE public.chat_rooms ADD COLUMN IF NOT EXISTS profile_image_path TEXT;
ALTER TABLE public.messages
    ADD COLUMN IF NOT EXISTS media_path TEXT,
    ADD COLUMN IF NOT EXISTS file_path TEXT,
    ADD COLUMN IF NOT EXISTS audio_path TEXT;

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('profile_assets', 'profile_assets', FALSE, 10485760)
ON CONFLICT (id) DO UPDATE
SET public = FALSE, file_size_limit = EXCLUDED.file_size_limit;

INSERT INTO storage.buckets (id, name, public, file_size_limit)
VALUES ('legacy_media_recovery', 'legacy_media_recovery', FALSE, 10485760)
ON CONFLICT (id) DO UPDATE
SET public = FALSE, file_size_limit = EXCLUDED.file_size_limit;

-- Closing public access is intentionally part of the coordinated beta
-- deployment. Existing signed URLs remain a temporary read fallback while the
-- idempotent migration tool copies objects into their private destinations.
UPDATE storage.buckets SET public = FALSE WHERE id = 'chat_attachments';
DROP POLICY IF EXISTS "Public Access" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can upload" ON storage.objects;
DROP POLICY IF EXISTS "Authenticated users can update uploads" ON storage.objects;

CREATE OR REPLACE FUNCTION public.can_view_profile_asset(object_name TEXT, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    parts TEXT[];
    owner_uuid UUID;
BEGIN
    IF object_name IS NULL OR user_uuid IS NULL THEN RETURN FALSE; END IF;
    parts := string_to_array(object_name, '/');
    IF array_length(parts, 1) < 4 OR parts[1] <> 'users' OR parts[3] <> 'avatars' THEN RETURN FALSE; END IF;
    owner_uuid := parts[2]::UUID;

    RETURN owner_uuid = user_uuid
        OR public.is_hq_director(user_uuid)
        OR EXISTS (
            SELECT 1
            FROM public.school_memberships owner_membership
            JOIN public.school_memberships viewer_membership
              ON viewer_membership.school_id = owner_membership.school_id
             AND viewer_membership.user_id = user_uuid
             AND viewer_membership.active = TRUE
            WHERE owner_membership.user_id = owner_uuid
              AND owner_membership.active = TRUE
        )
        OR EXISTS (
            SELECT 1
            FROM public.chat_participants owner_participant
            JOIN public.chat_participants viewer_participant
              ON viewer_participant.room_id = owner_participant.room_id
             AND viewer_participant.user_id = user_uuid
            WHERE owner_participant.user_id = owner_uuid
        );
EXCEPTION WHEN invalid_text_representation THEN RETURN FALSE;
END;
$$;

CREATE OR REPLACE FUNCTION public.can_write_profile_asset(object_name TEXT, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    parts TEXT[];
BEGIN
    IF object_name IS NULL OR user_uuid IS NULL THEN RETURN FALSE; END IF;
    parts := string_to_array(object_name, '/');
    RETURN array_length(parts, 1) >= 4
       AND parts[1] = 'users'
       AND parts[2]::UUID = user_uuid
       AND parts[3] = 'avatars';
EXCEPTION WHEN invalid_text_representation THEN RETURN FALSE;
END;
$$;

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
    IF object_name IS NULL OR user_uuid IS NULL THEN RETURN FALSE; END IF;
    parts := string_to_array(object_name, '/');
    IF array_length(parts, 1) < 4 OR parts[1] <> 'schools' THEN RETURN FALSE; END IF;
    school_uuid := parts[2]::UUID;
    category := parts[3];

    IF category = 'chat_rooms' THEN
        record_uuid := parts[4]::UUID;
        RETURN EXISTS (
            SELECT 1
            FROM public.chat_rooms rooms
            JOIN public.chat_participants participants ON participants.room_id = rooms.id
            WHERE rooms.id = record_uuid
              AND rooms.school_id = school_uuid
              AND participants.user_id = user_uuid
        );
    ELSIF category = 'school_assets' THEN
        RETURN public.is_school_member(school_uuid, user_uuid);
    ELSIF category = 'onboarding_templates' THEN
        RETURN EXISTS (
            SELECT 1
            FROM public.onboarding_templates templates
            WHERE templates.id = parts[4]::UUID
              AND templates.school_id = school_uuid
              AND public.is_onboarding_template_manager(templates.school_id, templates.target_role, user_uuid)
        ) OR EXISTS (
            SELECT 1
            FROM public.onboarding_template_attachments attachments
            JOIN public.onboarding_template_requirements requirements ON requirements.id = attachments.requirement_id
            LEFT JOIN public.onboarding_requirement_instances requirement_instances ON requirement_instances.template_requirement_id = requirements.id
            WHERE attachments.private_file_path = object_name
              AND requirement_instances.assignment_id IS NOT NULL
              AND public.can_view_assignment(requirement_instances.assignment_id, user_uuid)
        );
    END IF;

    IF category <> 'assignments'
       AND public.has_school_role(school_uuid, user_uuid, ARRAY['school_director', 'hq_director']) THEN RETURN TRUE; END IF;
    IF category = 'paperwork_assignments' THEN
        record_uuid := parts[4]::UUID;
        RETURN EXISTS (SELECT 1 FROM public.paperwork_assignment_recipients WHERE assignment_id = record_uuid AND parent_id = user_uuid);
    ELSIF category = 'paperwork_submissions' THEN
        owner_uuid := parts[4]::UUID;
        RETURN owner_uuid = user_uuid AND public.has_school_membership(school_uuid, user_uuid);
    ELSIF category IN ('curriculum_resources', 'training_assignments') THEN
        RETURN public.has_school_role(school_uuid, user_uuid, ARRAY['teacher']);
    ELSIF category = 'training_submissions' THEN
        owner_uuid := parts[4]::UUID;
        RETURN owner_uuid = user_uuid AND public.has_school_role(school_uuid, user_uuid, ARRAY['teacher']);
    ELSIF category = 'onboarding_requirements' THEN
        record_uuid := parts[4]::UUID;
        RETURN public.can_manage_onboarding_requirement(record_uuid, user_uuid) OR public.can_submit_onboarding_requirement(record_uuid, user_uuid);
    ELSIF category = 'document_submissions' THEN
        record_uuid := parts[4]::UUID;
        RETURN public.can_submit_onboarding_requirement(record_uuid, user_uuid) OR public.has_school_role(school_uuid, user_uuid, ARRAY['school_director', 'hq_director']);
    ELSIF category = 'child_documents' THEN
        record_uuid := parts[4]::UUID;
        RETURN public.can_access_child(record_uuid, user_uuid);
    ELSIF category = 'assignments' THEN
        IF array_length(parts, 1) < 5 THEN RETURN FALSE; END IF;
        record_uuid := parts[4]::UUID;
        IF parts[5] = 'submissions' THEN
            IF array_length(parts, 1) < 6 THEN RETURN FALSE; END IF;
            owner_uuid := parts[6]::UUID;
            RETURN owner_uuid = user_uuid OR public.can_manage_assignment(record_uuid, user_uuid);
        END IF;
        RETURN public.can_view_assignment(record_uuid, user_uuid);
    ELSIF category IN ('community_posts', 'community_albums') THEN
        RETURN public.is_school_member(school_uuid, user_uuid);
    END IF;
    RETURN FALSE;
EXCEPTION WHEN invalid_text_representation THEN RETURN FALSE;
END;
$$;

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
    room_uuid UUID;
BEGIN
    IF object_name IS NULL OR user_uuid IS NULL THEN RETURN FALSE; END IF;
    parts := string_to_array(object_name, '/');
    IF array_length(parts, 1) < 4 OR parts[1] <> 'schools' THEN RETURN FALSE; END IF;
    school_uuid := parts[2]::UUID;
    category := parts[3];

    IF category = 'chat_rooms' THEN
        IF array_length(parts, 1) < 6 THEN RETURN FALSE; END IF;
        room_uuid := parts[4]::UUID;
        owner_uuid := parts[5]::UUID;
        RETURN owner_uuid = user_uuid AND EXISTS (
            SELECT 1
            FROM public.chat_rooms rooms
            JOIN public.chat_participants participants ON participants.room_id = rooms.id
            WHERE rooms.id = room_uuid
              AND rooms.school_id = school_uuid
              AND participants.user_id = user_uuid
        );
    ELSIF category = 'school_assets' THEN
        RETURN public.has_school_role(school_uuid, user_uuid, ARRAY['school_director', 'hq_director']);
    ELSIF category = 'onboarding_templates' THEN
        IF array_length(parts, 1) < 5 THEN RETURN FALSE; END IF;
        RETURN EXISTS (
            SELECT 1
            FROM public.onboarding_templates templates
            WHERE templates.id = parts[4]::UUID
              AND templates.school_id = school_uuid
              AND templates.status = 'draft'
              AND public.is_onboarding_template_manager(templates.school_id, templates.target_role, user_uuid)
        );
    END IF;

    IF category IN ('paperwork_assignments', 'curriculum_resources', 'training_assignments', 'onboarding_requirements') THEN
        RETURN public.has_school_role(school_uuid, user_uuid, ARRAY['school_director', 'hq_director']);
    END IF;
    IF category = 'assignments' THEN
        IF array_length(parts, 1) < 5 THEN RETURN FALSE; END IF;
        IF parts[5] = 'materials' THEN
            RETURN public.can_manage_assignment(parts[4]::UUID, user_uuid);
        ELSIF parts[5] = 'submissions' THEN
            IF array_length(parts, 1) < 6 THEN RETURN FALSE; END IF;
            owner_uuid := parts[6]::UUID;
            RETURN owner_uuid = user_uuid AND public.can_submit_assignment(parts[4]::UUID, user_uuid);
        END IF;
        RETURN FALSE;
    END IF;
    IF array_length(parts, 1) < 5 THEN RETURN FALSE; END IF;
    owner_uuid := parts[4]::UUID;
    IF category = 'paperwork_submissions' THEN
        RETURN owner_uuid = user_uuid AND public.has_school_membership(school_uuid, user_uuid);
    ELSIF category = 'training_submissions' THEN
        RETURN owner_uuid = user_uuid AND public.has_school_role(school_uuid, user_uuid, ARRAY['teacher']);
    ELSIF category = 'document_submissions' THEN
        RETURN public.can_submit_onboarding_requirement(owner_uuid, user_uuid);
    ELSIF category = 'child_documents' THEN
        RETURN public.can_access_child(owner_uuid, user_uuid);
    ELSIF category IN ('community_posts', 'community_albums') THEN
        RETURN public.has_school_role(school_uuid, user_uuid, ARRAY['teacher', 'school_director', 'hq_director']);
    END IF;
    RETURN FALSE;
EXCEPTION WHEN invalid_text_representation THEN RETURN FALSE;
END;
$$;

REVOKE ALL ON FUNCTION public.can_view_profile_asset(TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_write_profile_asset(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_view_profile_asset(TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_write_profile_asset(TEXT, UUID) TO authenticated;

DROP POLICY IF EXISTS "Profile assets are relationship private" ON storage.objects;
DROP POLICY IF EXISTS "Users can upload their profile assets" ON storage.objects;
DROP POLICY IF EXISTS "Users can update their profile assets" ON storage.objects;
DROP POLICY IF EXISTS "Users can delete their profile assets" ON storage.objects;

CREATE POLICY "Profile assets are relationship private"
    ON storage.objects FOR SELECT TO authenticated
    USING (bucket_id = 'profile_assets' AND public.can_view_profile_asset(name, auth.uid()));
CREATE POLICY "Users can upload their profile assets"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (bucket_id = 'profile_assets' AND public.can_write_profile_asset(name, auth.uid()));
CREATE POLICY "Users can update their profile assets"
    ON storage.objects FOR UPDATE TO authenticated
    USING (bucket_id = 'profile_assets' AND public.can_write_profile_asset(name, auth.uid()))
    WITH CHECK (bucket_id = 'profile_assets' AND public.can_write_profile_asset(name, auth.uid()));
CREATE POLICY "Users can delete their profile assets"
    ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'profile_assets' AND public.can_write_profile_asset(name, auth.uid()));

DROP POLICY IF EXISTS "School members can delete own private uploads" ON storage.objects;
DROP POLICY IF EXISTS "School members can delete private files" ON storage.objects;
DROP POLICY IF EXISTS "School private file deletes are owner scoped" ON storage.objects;
CREATE POLICY "School private file deletes are owner scoped"
    ON storage.objects FOR DELETE TO authenticated
    USING (bucket_id = 'school_private_files' AND public.can_delete_school_private_file(name, auth.uid()));

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ SELECT 20260721020000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';

-- Migration: 20260721030000_fix_function_lint_ambiguities.sql

-- Qualify PL/pgSQL references that can otherwise resolve to either a function
-- parameter or a table column. These definitions preserve existing behavior.

-- The legacy hosted project has the standard Supabase Data API DML grants,
-- with access constrained by RLS. Capture them so a clean rebuild behaves like
-- the hosted project. Every public table is verified to have RLS enabled.
GRANT SELECT, INSERT, UPDATE, DELETE ON ALL TABLES IN SCHEMA public
TO anon, authenticated, service_role;

ALTER DEFAULT PRIVILEGES FOR ROLE postgres IN SCHEMA public
GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES
TO anon, authenticated, service_role;

-- CREATE TABLE IF NOT EXISTS did not add these baseline constraints/defaults
-- to the pre-existing hosted tables. Reconcile them without weakening the
-- local baseline. Hosted values were checked before this migration was added.
DO $constraints$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'curriculum_resources_material_type_check'
          AND conrelid = 'public.curriculum_resources'::regclass
    ) THEN
        ALTER TABLE public.curriculum_resources
            ADD CONSTRAINT curriculum_resources_material_type_check
            CHECK (material_type IN ('article', 'link', 'image', 'video', 'file', 'mixed'));
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint
        WHERE conname = 'training_assignments_material_type_check'
          AND conrelid = 'public.training_assignments'::regclass
    ) THEN
        ALTER TABLE public.training_assignments
            ADD CONSTRAINT training_assignments_material_type_check
            CHECK (material_type IN ('article', 'link', 'image', 'video', 'file', 'mixed'));
    END IF;
END;
$constraints$;

ALTER TABLE public.chat_rooms
    ALTER COLUMN invite_hash SET DEFAULT gen_random_uuid()::TEXT;

DROP POLICY IF EXISTS "Users can view their own participant records"
    ON public.chat_participants;
CREATE POLICY "Users can view their own participant records"
    ON public.chat_participants FOR SELECT TO public
    USING (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.submit_required_document(
    requirement_id UUID,
    file_name TEXT,
    file_path TEXT
)
RETURNS SETOF public.document_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID;
    requirement_record public.onboarding_requirements%ROWTYPE;
    saved_submission public.document_submissions%ROWTYPE;
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT *
    INTO requirement_record
    FROM public.onboarding_requirements AS requirements
    WHERE requirements.id = $1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Required document was not found';
    END IF;

    IF NOT public.can_submit_onboarding_requirement($1, actor) THEN
        RAISE EXCEPTION 'You are not assigned to this required document';
    END IF;

    INSERT INTO public.document_submissions (
        requirement_id,
        school_id,
        submitted_by,
        file_name,
        file_path,
        status,
        reviewer_message,
        submitted_at
    )
    VALUES (
        requirement_record.id,
        requirement_record.school_id,
        actor,
        $2,
        $3,
        'submitted',
        NULL,
        NOW()
    )
    ON CONFLICT ON CONSTRAINT document_submissions_requirement_id_submitted_by_key
    DO UPDATE SET
        file_name = EXCLUDED.file_name,
        file_path = EXCLUDED.file_path,
        status = 'submitted',
        reviewer_message = NULL,
        reviewed_by = NULL,
        reviewed_at = NULL,
        submitted_at = NOW()
    RETURNING * INTO saved_submission;

    RETURN QUERY
    SELECT submissions.*
    FROM public.document_submissions AS submissions
    WHERE submissions.id = saved_submission.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_paperwork_assignment(
    assignment_id UUID,
    file_name TEXT,
    file_path TEXT
)
RETURNS SETOF public.paperwork_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID;
    assignment_record public.paperwork_assignments%ROWTYPE;
    existing_submission_id UUID;
    expected_prefix TEXT;
    saved_submission public.paperwork_submissions%ROWTYPE;
    created_notification_id UUID;
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT *
    INTO assignment_record
    FROM public.paperwork_assignments AS assignments
    WHERE assignments.id = $1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Paperwork assignment was not found';
    END IF;

    IF NOT public.can_submit_paperwork_assignment($1, assignment_record.school_id, actor) THEN
        RAISE EXCEPTION 'You are not assigned to this paperwork';
    END IF;

    expected_prefix := 'schools/'
        || assignment_record.school_id::TEXT
        || '/paperwork_submissions/'
        || actor::TEXT
        || '/';

    IF $3 IS NULL OR LOWER($3) NOT LIKE LOWER(expected_prefix) || '%' THEN
        RAISE EXCEPTION 'Paperwork upload path is invalid';
    END IF;

    SELECT submissions.id
    INTO existing_submission_id
    FROM public.paperwork_submissions AS submissions
    WHERE submissions.assignment_id = assignment_record.id
      AND submissions.submitted_by = actor
    ORDER BY submissions.submitted_at DESC
    LIMIT 1;

    IF existing_submission_id IS NULL THEN
        INSERT INTO public.paperwork_submissions (
            assignment_id,
            school_id,
            submitted_by,
            file_name,
            file_path,
            status,
            flag_reason,
            reviewed_by,
            reviewed_at,
            submitted_at
        )
        VALUES (
            assignment_record.id,
            assignment_record.school_id,
            actor,
            $2,
            $3,
            'submitted',
            NULL,
            NULL,
            NULL,
            NOW()
        )
        RETURNING * INTO saved_submission;
    ELSE
        UPDATE public.paperwork_submissions AS submissions
        SET file_name = $2,
            file_path = $3,
            status = 'submitted',
            flag_reason = NULL,
            reviewed_by = NULL,
            reviewed_at = NULL,
            submitted_at = NOW()
        WHERE submissions.id = existing_submission_id
        RETURNING * INTO saved_submission;
    END IF;

    INSERT INTO public.notifications (
        school_id,
        title,
        body,
        category,
        source_type,
        source_id,
        created_by
    )
    VALUES (
        assignment_record.school_id,
        'Paperwork submitted',
        'A parent uploaded paperwork for "' || assignment_record.title || '".',
        'paperwork_submission',
        'paperwork_submission',
        saved_submission.id,
        actor
    )
    RETURNING id INTO created_notification_id;

    INSERT INTO public.notification_recipients (notification_id, user_id)
    SELECT DISTINCT created_notification_id, memberships.user_id
    FROM public.school_memberships AS memberships
    WHERE memberships.active = TRUE
      AND memberships.user_id <> actor
      AND (
          (
              memberships.school_id = assignment_record.school_id
              AND memberships.role = 'school_director'
          )
          OR memberships.role = 'hq_director'
      )
    ON CONFLICT DO NOTHING;

    RETURN QUERY
    SELECT submissions.*
    FROM public.paperwork_submissions AS submissions
    WHERE submissions.id = saved_submission.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_medication_instruction(
    school_id UUID,
    child_id UUID,
    title TEXT,
    dosage TEXT DEFAULT NULL,
    instructions TEXT DEFAULT NULL,
    scheduled_at TIMESTAMPTZ DEFAULT NOW()
)
RETURNS SETOF public.medication_instructions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID;
    created_instruction public.medication_instructions%ROWTYPE;
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM public.children AS child_records
        WHERE child_records.id = $2
          AND child_records.school_id = $1
          AND public.can_access_child(child_records.id, actor)
    ) THEN
        RAISE EXCEPTION 'You cannot create medication instructions for this child';
    END IF;

    IF NULLIF(TRIM($3), '') IS NULL THEN
        RAISE EXCEPTION 'Medication title is required';
    END IF;

    INSERT INTO public.medication_instructions (
        school_id,
        child_id,
        title,
        dosage,
        instructions,
        scheduled_at,
        created_by
    )
    VALUES ($1, $2, TRIM($3), NULLIF(TRIM($4), ''), NULLIF(TRIM($5), ''), $6, actor)
    RETURNING * INTO created_instruction;

    INSERT INTO public.medication_tasks (school_id, child_id, instruction_id, due_at, status)
    VALUES ($1, $2, created_instruction.id, $6, 'pending');

    INSERT INTO public.notifications (school_id, title, body, category, source_type, source_id, created_by)
    VALUES ($1, 'Medication instruction', TRIM($3), 'medicine_instruction', 'medication_instruction', created_instruction.id, actor);

    INSERT INTO public.notification_recipients (notification_id, user_id)
    SELECT notifications.id, memberships.user_id
    FROM public.notifications AS notifications
    JOIN public.school_memberships AS memberships
      ON memberships.school_id = notifications.school_id
     AND memberships.active = TRUE
     AND memberships.role IN ('teacher', 'school_director')
    WHERE notifications.source_id = created_instruction.id
      AND notifications.source_type = 'medication_instruction'
    ON CONFLICT DO NOTHING;

    RETURN QUERY
    SELECT instructions.*
    FROM public.medication_instructions AS instructions
    WHERE instructions.id = created_instruction.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ SELECT 20260721030000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';

-- Migration: 20260721040000_notification_inbox_cleanup.sql

-- Let each recipient remove notifications from only their own inbox. Deleting
-- the receipt keeps the underlying school notification intact for everyone
-- else and avoids granting direct DELETE access through RLS.

CREATE OR REPLACE FUNCTION public.dismiss_notification(input_notification_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    DELETE FROM public.notification_recipients
    WHERE notification_id = input_notification_id
      AND user_id = auth.uid();

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Notification was not found for this user';
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.clear_my_notifications()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    deleted_count INTEGER;
BEGIN
    IF auth.uid() IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    DELETE FROM public.notification_recipients
    WHERE user_id = auth.uid();

    GET DIAGNOSTICS deleted_count = ROW_COUNT;
    RETURN deleted_count;
END;
$$;

REVOKE ALL ON FUNCTION public.dismiss_notification(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.clear_my_notifications() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.dismiss_notification(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.clear_my_notifications() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ SELECT 20260721040000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';

-- Migration: 20260722000000_newsletter_media.sql

-- Store a small, ordered media manifest with each newsletter. The underlying
-- files remain in the private school bucket and are delivered through signed
-- URLs, just like other school-scoped media.

ALTER TABLE public.newsletters
    ADD COLUMN IF NOT EXISTS media JSONB NOT NULL DEFAULT '[]'::JSONB;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_constraint
        WHERE conrelid = 'public.newsletters'::REGCLASS
          AND conname = 'newsletters_media_is_array'
    ) THEN
        ALTER TABLE public.newsletters
            ADD CONSTRAINT newsletters_media_is_array
            CHECK (jsonb_typeof(media) = 'array');
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.can_access_newsletter_private_file(object_name TEXT, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    parts TEXT[];
    school_uuid UUID;
    newsletter_uuid UUID;
BEGIN
    IF object_name IS NULL OR user_uuid IS NULL
       OR auth.uid() IS NULL OR user_uuid IS DISTINCT FROM auth.uid() THEN
        RETURN FALSE;
    END IF;

    parts := string_to_array(object_name, '/');
    IF array_length(parts, 1) < 5
       OR parts[1] <> 'schools'
       OR parts[3] <> 'newsletters' THEN
        RETURN FALSE;
    END IF;

    school_uuid := parts[2]::UUID;
    newsletter_uuid := parts[4]::UUID;

    RETURN public.is_school_member(school_uuid, user_uuid)
       AND EXISTS (
            SELECT 1
            FROM public.newsletters newsletters
            WHERE newsletters.id = newsletter_uuid
              AND newsletters.school_id = school_uuid
              AND EXISTS (
                    SELECT 1
                    FROM jsonb_array_elements(newsletters.media) item
                    WHERE item->>'file_path' = object_name
              )
       );
EXCEPTION WHEN invalid_text_representation THEN
    RETURN FALSE;
END;
$$;

CREATE OR REPLACE FUNCTION public.can_write_newsletter_private_file(object_name TEXT, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    parts TEXT[];
    school_uuid UUID;
    newsletter_uuid UUID;
BEGIN
    IF object_name IS NULL OR user_uuid IS NULL
       OR auth.uid() IS NULL OR user_uuid IS DISTINCT FROM auth.uid() THEN
        RETURN FALSE;
    END IF;

    parts := string_to_array(object_name, '/');
    IF array_length(parts, 1) < 5
       OR parts[1] <> 'schools'
       OR parts[3] <> 'newsletters' THEN
        RETURN FALSE;
    END IF;

    school_uuid := parts[2]::UUID;
    newsletter_uuid := parts[4]::UUID;

    RETURN newsletter_uuid IS NOT NULL
       AND public.has_school_role(
            school_uuid,
            user_uuid,
            ARRAY['school_director', 'hq_director']
       );
EXCEPTION WHEN invalid_text_representation THEN
    RETURN FALSE;
END;
$$;

REVOKE ALL ON FUNCTION public.can_access_newsletter_private_file(TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_write_newsletter_private_file(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_access_newsletter_private_file(TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_write_newsletter_private_file(TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_access_newsletter_private_file(TEXT, UUID) TO anon;
GRANT EXECUTE ON FUNCTION public.can_write_newsletter_private_file(TEXT, UUID) TO anon;

DROP POLICY IF EXISTS "School private files are restricted" ON storage.objects;
CREATE POLICY "School private files are restricted"
    ON storage.objects FOR SELECT
    USING (
        bucket_id = 'school_private_files'
        AND CASE
            WHEN auth.uid() IS NULL THEN FALSE
            ELSE (
                public.can_access_school_private_file(name, auth.uid())
                OR public.can_access_newsletter_private_file(name, auth.uid())
            )
        END
    );

DROP POLICY IF EXISTS "School members can upload private files" ON storage.objects;
CREATE POLICY "School members can upload private files"
    ON storage.objects FOR INSERT
    WITH CHECK (
        bucket_id = 'school_private_files'
        AND (
            public.can_write_school_private_file(name, auth.uid())
            OR public.can_write_newsletter_private_file(name, auth.uid())
        )
    );

DROP POLICY IF EXISTS "School members can update private files" ON storage.objects;
CREATE POLICY "School members can update private files"
    ON storage.objects FOR UPDATE
    USING (
        bucket_id = 'school_private_files'
        AND (
            public.can_write_school_private_file(name, auth.uid())
            OR public.can_write_newsletter_private_file(name, auth.uid())
        )
    )
    WITH CHECK (
        bucket_id = 'school_private_files'
        AND (
            public.can_write_school_private_file(name, auth.uid())
            OR public.can_write_newsletter_private_file(name, auth.uid())
        )
    );

DROP POLICY IF EXISTS "School members can delete own private uploads" ON storage.objects;
CREATE POLICY "School members can delete own private uploads"
    ON storage.objects FOR DELETE
    USING (
        bucket_id = 'school_private_files'
        AND (
            public.can_delete_school_private_file(name, auth.uid())
            OR public.can_write_newsletter_private_file(name, auth.uid())
        )
    );

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ SELECT 20260722000000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';

-- Migration: 20260722010000_school_level_child_operations.sql

-- School-level child access, verified guardian connections, structured care,
-- transactional notifications, and director-managed group chat.

ALTER TABLE public.children
    DROP CONSTRAINT IF EXISTS children_birthdate_required;
ALTER TABLE public.children
    ADD CONSTRAINT children_birthdate_required CHECK (birthdate IS NOT NULL) NOT VALID;

ALTER TABLE public.child_guardians
    ADD COLUMN IF NOT EXISTS verification_status TEXT NOT NULL DEFAULT 'verified',
    ADD COLUMN IF NOT EXISTS verified_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS ended_at TIMESTAMPTZ;
ALTER TABLE public.child_guardians
    DROP CONSTRAINT IF EXISTS child_guardians_verification_status_check;
ALTER TABLE public.child_guardians
    ADD CONSTRAINT child_guardians_verification_status_check
    CHECK (verification_status IN ('pending', 'verified', 'revoked'));
UPDATE public.child_guardians
SET verified_at = COALESCE(verified_at, created_at)
WHERE verification_status = 'verified';

ALTER TABLE public.role_invites
    ADD COLUMN IF NOT EXISTS child_id UUID REFERENCES public.children(id) ON DELETE CASCADE,
    ADD COLUMN IF NOT EXISTS guardian_relationship TEXT;

ALTER TABLE public.onboarding_template_requirements
    ADD COLUMN IF NOT EXISTS blocks_access BOOLEAN NOT NULL DEFAULT TRUE,
    ADD COLUMN IF NOT EXISTS child_record_binding TEXT NOT NULL DEFAULT 'none';
ALTER TABLE public.onboarding_template_requirements
    DROP CONSTRAINT IF EXISTS onboarding_template_requirements_child_record_binding_check;
ALTER TABLE public.onboarding_template_requirements
    ADD CONSTRAINT onboarding_template_requirements_child_record_binding_check
    CHECK (child_record_binding IN (
        'none', 'child_document', 'immunization_record', 'medical_clearance',
        'medication_authorization', 'emergency_information', 'consent'
    ));
ALTER TABLE public.onboarding_template_requirements
    DROP CONSTRAINT IF EXISTS onboarding_template_requirements_binding_scope_check;
ALTER TABLE public.onboarding_template_requirements
    ADD CONSTRAINT onboarding_template_requirements_binding_scope_check
    CHECK (child_record_binding = 'none' OR subject_scope = 'child');

CREATE OR REPLACE FUNCTION public.enforce_onboarding_requirement_rules()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
DECLARE source_requirement public.onboarding_template_requirements%ROWTYPE;
BEGIN
    IF TG_OP = 'INSERT' THEN
        SELECT * INTO source_requirement
        FROM public.onboarding_template_requirements existing
        WHERE existing.requirement_key = NEW.requirement_key
          AND existing.template_id <> NEW.template_id
        ORDER BY existing.created_at DESC LIMIT 1;
        IF FOUND THEN
            NEW.blocks_access := source_requirement.blocks_access;
            NEW.child_record_binding := source_requirement.child_record_binding;
        END IF;
    END IF;
    IF NEW.position = 0 THEN NEW.blocks_access := TRUE; END IF;
    IF NEW.subject_scope <> 'child' THEN NEW.child_record_binding := 'none'; END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS enforce_onboarding_requirement_rules_trigger ON public.onboarding_template_requirements;
CREATE TRIGGER enforce_onboarding_requirement_rules_trigger
    BEFORE INSERT OR UPDATE ON public.onboarding_template_requirements
    FOR EACH ROW EXECUTE FUNCTION public.enforce_onboarding_requirement_rules();

ALTER TABLE public.assignment_submissions
    ADD COLUMN IF NOT EXISTS structured_payload JSONB NOT NULL DEFAULT '{}'::JSONB;

ALTER TABLE public.child_documents
    ADD COLUMN IF NOT EXISTS source_assignment_submission_id UUID REFERENCES public.assignment_submissions(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS source_attachment_id UUID REFERENCES public.assignment_submission_attachments(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS expires_on DATE;
CREATE UNIQUE INDEX IF NOT EXISTS idx_child_documents_source_submission
    ON public.child_documents(source_assignment_submission_id)
    WHERE source_assignment_submission_id IS NOT NULL;

ALTER TABLE public.medication_instructions
    ADD COLUMN IF NOT EXISTS source_assignment_submission_id UUID REFERENCES public.assignment_submissions(id) ON DELETE RESTRICT,
    ADD COLUMN IF NOT EXISTS verified_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS verified_at TIMESTAMPTZ;
CREATE UNIQUE INDEX IF NOT EXISTS idx_medication_instructions_source_submission
    ON public.medication_instructions(source_assignment_submission_id)
    WHERE source_assignment_submission_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS public.child_connection_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    requested_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    legal_first_name TEXT NOT NULL CHECK (btrim(legal_first_name) <> ''),
    legal_last_name TEXT NOT NULL CHECK (btrim(legal_last_name) <> ''),
    birthdate DATE NOT NULL CHECK (birthdate <= CURRENT_DATE),
    relationship TEXT NOT NULL CHECK (btrim(relationship) <> ''),
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected')),
    matched_child_id UUID REFERENCES public.children(id) ON DELETE RESTRICT,
    reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,
    review_note TEXT,
    idempotency_key TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (requested_by, idempotency_key)
);
CREATE INDEX IF NOT EXISTS idx_child_connection_requests_school_status
    ON public.child_connection_requests(school_id, status, created_at);

CREATE TABLE IF NOT EXISTS public.child_profile_change_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    child_id UUID NOT NULL REFERENCES public.children(id) ON DELETE CASCADE,
    requested_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    proposed_changes JSONB NOT NULL CHECK (jsonb_typeof(proposed_changes) = 'object'),
    reason TEXT,
    status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'approved', 'rejected', 'withdrawn')),
    reviewed_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    reviewed_at TIMESTAMPTZ,
    review_note TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.attendance_sessions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    child_id UUID NOT NULL REFERENCES public.children(id) ON DELETE CASCADE,
    attendance_date DATE NOT NULL DEFAULT CURRENT_DATE,
    state TEXT NOT NULL DEFAULT 'present' CHECK (state IN ('expected', 'present', 'checked_out', 'absent', 'needs_attention')),
    checked_in_at TIMESTAMPTZ,
    checked_out_at TIMESTAMPTZ,
    checked_in_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    checked_out_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    notes TEXT,
    idempotency_key TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CHECK (checked_out_at IS NULL OR (checked_in_at IS NOT NULL AND checked_out_at >= checked_in_at))
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_one_open_session
    ON public.attendance_sessions(child_id) WHERE checked_in_at IS NOT NULL AND checked_out_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_attendance_idempotency
    ON public.attendance_sessions(school_id, idempotency_key) WHERE idempotency_key IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_attendance_school_date
    ON public.attendance_sessions(school_id, attendance_date, state);

CREATE TABLE IF NOT EXISTS public.attendance_corrections (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    attendance_session_id UUID NOT NULL REFERENCES public.attendance_sessions(id) ON DELETE RESTRICT,
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    corrected_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    reason TEXT NOT NULL CHECK (btrim(reason) <> ''),
    before_values JSONB NOT NULL,
    after_values JSONB NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.child_care_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    child_id UUID NOT NULL REFERENCES public.children(id) ON DELETE CASCADE,
    event_type TEXT NOT NULL CHECK (event_type IN (
        'meal', 'bottle', 'nap', 'potty', 'diaper', 'medication',
        'health_check', 'activity', 'note', 'photo'
    )),
    occurred_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    details JSONB NOT NULL DEFAULT '{}'::JSONB CHECK (jsonb_typeof(details) = 'object'),
    visibility TEXT NOT NULL DEFAULT 'parent' CHECK (visibility IN ('parent', 'staff_only')),
    recorded_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    source_medication_task_id UUID REFERENCES public.medication_tasks(id) ON DELETE RESTRICT,
    idempotency_key TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (recorded_by, idempotency_key)
);
CREATE INDEX IF NOT EXISTS idx_child_care_events_child_occurred
    ON public.child_care_events(child_id, occurred_at DESC);

CREATE TABLE IF NOT EXISTS public.family_requests (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    child_id UUID NOT NULL REFERENCES public.children(id) ON DELETE CASCADE,
    requested_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    request_type TEXT NOT NULL CHECK (request_type IN ('absence', 'pickup_change', 'medication', 'general')),
    details JSONB NOT NULL DEFAULT '{}'::JSONB CHECK (jsonb_typeof(details) = 'object'),
    status TEXT NOT NULL DEFAULT 'open' CHECK (status IN ('open', 'acknowledged', 'completed', 'cancelled')),
    handled_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    handled_at TIMESTAMPTZ,
    idempotency_key TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (requested_by, idempotency_key)
);

ALTER TABLE public.notifications
    ADD COLUMN IF NOT EXISTS priority TEXT NOT NULL DEFAULT 'routine',
    ADD COLUMN IF NOT EXISTS route JSONB NOT NULL DEFAULT '{}'::JSONB;
ALTER TABLE public.notifications
    DROP CONSTRAINT IF EXISTS notifications_priority_check;
ALTER TABLE public.notifications
    ADD CONSTRAINT notifications_priority_check CHECK (priority IN ('routine', 'important', 'urgent'));

ALTER TABLE public.notification_recipients
    ADD COLUMN IF NOT EXISTS delivery_state TEXT NOT NULL DEFAULT 'queued',
    ADD COLUMN IF NOT EXISTS attempt_count INTEGER NOT NULL DEFAULT 0,
    ADD COLUMN IF NOT EXISTS last_error TEXT,
    ADD COLUMN IF NOT EXISTS opened_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS acknowledged_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS dismissed_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS expired_at TIMESTAMPTZ;
ALTER TABLE public.notification_recipients
    DROP CONSTRAINT IF EXISTS notification_recipients_delivery_state_check;
ALTER TABLE public.notification_recipients
    ADD CONSTRAINT notification_recipients_delivery_state_check
    CHECK (delivery_state IN ('queued', 'delivered', 'opened', 'acknowledged', 'failed', 'dismissed', 'expired'));

CREATE TABLE IF NOT EXISTS public.notification_outbox (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    notification_id UUID NOT NULL REFERENCES public.notifications(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    available_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    locked_at TIMESTAMPTZ,
    completed_at TIMESTAMPTZ,
    attempt_count INTEGER NOT NULL DEFAULT 0,
    last_error TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (notification_id, user_id)
);

CREATE TABLE IF NOT EXISTS public.workflow_audit_events (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    actor_id UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    event_type TEXT NOT NULL,
    source_type TEXT NOT NULL,
    source_id UUID NOT NULL,
    metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.chat_rooms
    ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS deleted_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS deleted_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;
ALTER TABLE public.chat_rooms DROP CONSTRAINT IF EXISTS chat_rooms_room_type_check;
UPDATE public.chat_rooms SET room_type = 'director_managed' WHERE room_type IN ('public', 'private');
ALTER TABLE public.chat_rooms
    ADD CONSTRAINT chat_rooms_room_type_check CHECK (room_type = 'director_managed');
ALTER TABLE public.chat_rooms ALTER COLUMN room_type SET DEFAULT 'director_managed';
UPDATE public.chat_rooms SET invite_hash = NULL;

CREATE TABLE IF NOT EXISTS public.chat_participant_audit (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    room_id UUID NOT NULL REFERENCES public.chat_rooms(id) ON DELETE RESTRICT,
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    action TEXT NOT NULL CHECK (action IN ('added', 'removed')),
    acted_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS public.school_workflow_mutations (
    actor_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    operation TEXT NOT NULL,
    idempotency_key TEXT NOT NULL,
    result_id UUID NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (actor_id, operation, idempotency_key)
);

ALTER TABLE public.child_connection_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.child_profile_change_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_sessions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.attendance_corrections ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.child_care_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.family_requests ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_outbox ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.workflow_audit_events ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.chat_participant_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.school_workflow_mutations ENABLE ROW LEVEL SECURITY;

-- Classroom records remain for migration compatibility, but application access
-- is now based only on active school membership.
DROP TRIGGER IF EXISTS assign_child_to_default_classroom_trigger ON public.children;
REVOKE ALL ON FUNCTION public.create_child_for_current_parent(UUID, TEXT, TEXT, DATE) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_child_for_current_parent(UUID, TEXT, TEXT, DATE) FROM authenticated;
REVOKE ALL ON FUNCTION public.join_chat_room(TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.join_chat_room(TEXT) FROM authenticated;
REVOKE ALL ON FUNCTION public.create_medication_instruction(UUID, UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_medication_instruction(UUID, UUID, TEXT, TEXT, TEXT, TIMESTAMPTZ) FROM authenticated;
REVOKE ALL ON FUNCTION public.acknowledge_medication_task(UUID, TEXT, TEXT, TIMESTAMPTZ) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.acknowledge_medication_task(UUID, TEXT, TEXT, TIMESTAMPTZ) FROM authenticated;
REVOKE ALL ON FUNCTION public.escalate_missed_medication_tasks() FROM PUBLIC;
REVOKE ALL ON FUNCTION public.escalate_missed_medication_tasks() FROM authenticated;

CREATE OR REPLACE FUNCTION public.is_classroom_teacher_for_child(child_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.children child
        JOIN public.school_memberships membership
          ON membership.school_id = child.school_id
         AND membership.user_id = user_uuid
         AND membership.active = TRUE
         AND membership.role = 'teacher'
        WHERE child.id = child_uuid
          AND child.active = TRUE
    );
$$;

CREATE OR REPLACE FUNCTION public.can_staff_access_child(child_uuid UUID, user_uuid UUID, allowed_roles TEXT[])
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT public.is_hq_director(user_uuid)
        OR EXISTS (
            SELECT 1
            FROM public.children child
            JOIN public.school_memberships membership
              ON membership.school_id = child.school_id
             AND membership.user_id = user_uuid
             AND membership.active = TRUE
            WHERE child.id = child_uuid
              AND membership.role = ANY(allowed_roles)
              AND membership.role IN ('teacher', 'school_director')
        );
$$;

-- Care photos use a purpose-specific private path so guardians can see only
-- parent-visible media and only school staff can upload it.
CREATE OR REPLACE FUNCTION public.can_access_child_care_file(object_name TEXT, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    parts TEXT[];
    school_uuid UUID;
    child_uuid UUID;
    file_visibility TEXT;
BEGIN
    IF object_name IS NULL OR user_uuid IS NULL THEN RETURN FALSE; END IF;
    parts := string_to_array(object_name, '/');
    IF array_length(parts, 1) < 7 OR parts[1] <> 'schools' OR parts[3] <> 'care_events' THEN RETURN FALSE; END IF;
    school_uuid := parts[2]::UUID;
    child_uuid := parts[4]::UUID;
    file_visibility := parts[5];
    IF file_visibility NOT IN ('parent', 'staff_only') THEN RETURN FALSE; END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.children child
        WHERE child.id = child_uuid AND child.school_id = school_uuid AND child.active = TRUE
    ) THEN RETURN FALSE; END IF;
    RETURN public.can_staff_access_child(child_uuid, user_uuid, ARRAY['teacher', 'school_director'])
        OR (file_visibility = 'parent' AND public.is_child_guardian(child_uuid, user_uuid));
EXCEPTION WHEN invalid_text_representation THEN RETURN FALSE;
END;
$$;

CREATE OR REPLACE FUNCTION public.can_write_child_care_file(object_name TEXT, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    parts TEXT[];
    school_uuid UUID;
    child_uuid UUID;
    owner_uuid UUID;
BEGIN
    IF object_name IS NULL OR user_uuid IS NULL THEN RETURN FALSE; END IF;
    parts := string_to_array(object_name, '/');
    IF array_length(parts, 1) < 7 OR parts[1] <> 'schools' OR parts[3] <> 'care_events'
       OR parts[5] NOT IN ('parent', 'staff_only') THEN RETURN FALSE; END IF;
    school_uuid := parts[2]::UUID;
    child_uuid := parts[4]::UUID;
    owner_uuid := parts[6]::UUID;
    RETURN owner_uuid = user_uuid
       AND EXISTS (
            SELECT 1 FROM public.children child
            WHERE child.id = child_uuid AND child.school_id = school_uuid AND child.active = TRUE
       )
       AND public.can_staff_access_child(child_uuid, user_uuid, ARRAY['teacher', 'school_director']);
EXCEPTION WHEN invalid_text_representation THEN RETURN FALSE;
END;
$$;

REVOKE ALL ON FUNCTION public.can_access_child_care_file(TEXT, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.can_write_child_care_file(TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.can_access_child_care_file(TEXT, UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.can_write_child_care_file(TEXT, UUID) TO authenticated;

DROP POLICY IF EXISTS "School private files are restricted" ON storage.objects;
CREATE POLICY "School private files are restricted"
    ON storage.objects FOR SELECT TO authenticated
    USING (
        bucket_id = 'school_private_files'
        AND (
            public.can_access_school_private_file(name, auth.uid())
            OR public.can_access_child_care_file(name, auth.uid())
        )
    );
DROP POLICY IF EXISTS "School members can upload private files" ON storage.objects;
CREATE POLICY "School members can upload private files"
    ON storage.objects FOR INSERT TO authenticated
    WITH CHECK (
        bucket_id = 'school_private_files'
        AND (
            public.can_write_school_private_file(name, auth.uid())
            OR public.can_write_child_care_file(name, auth.uid())
        )
    );
DROP POLICY IF EXISTS "School members can update private files" ON storage.objects;
CREATE POLICY "School members can update private files"
    ON storage.objects FOR UPDATE TO authenticated
    USING (
        bucket_id = 'school_private_files'
        AND (
            public.can_write_school_private_file(name, auth.uid())
            OR public.can_write_child_care_file(name, auth.uid())
        )
    )
    WITH CHECK (
        bucket_id = 'school_private_files'
        AND (
            public.can_write_school_private_file(name, auth.uid())
            OR public.can_write_child_care_file(name, auth.uid())
        )
    );
DROP POLICY IF EXISTS "School private file deletes are owner scoped" ON storage.objects;
CREATE POLICY "School private file deletes are owner scoped"
    ON storage.objects FOR DELETE TO authenticated
    USING (
        bucket_id = 'school_private_files'
        AND (
            public.can_delete_school_private_file(name, auth.uid())
            OR public.can_write_child_care_file(name, auth.uid())
        )
    );

CREATE OR REPLACE FUNCTION public.is_child_guardian(child_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.child_guardians guardian
        JOIN public.children child ON child.id = guardian.child_id
        JOIN public.school_memberships membership
          ON membership.school_id = child.school_id
         AND membership.user_id = guardian.guardian_id
         AND membership.active = TRUE
         AND membership.role = 'parent'
        WHERE guardian.child_id = child_uuid
          AND guardian.guardian_id = user_uuid
          AND guardian.verification_status = 'verified'
          AND guardian.ended_at IS NULL
    );
$$;

CREATE OR REPLACE FUNCTION public.enqueue_workflow_notification(
    input_school_id UUID,
    input_title TEXT,
    input_body TEXT,
    input_category TEXT,
    input_source_type TEXT,
    input_source_id UUID,
    input_recipient_ids UUID[],
    input_dedupe_key TEXT,
    input_priority TEXT DEFAULT 'routine',
    input_route JSONB DEFAULT '{}'::JSONB,
    input_actor_id UUID DEFAULT NULL
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
    IF NULLIF(btrim(COALESCE(input_dedupe_key, '')), '') IS NULL THEN
        RAISE EXCEPTION 'A notification deduplication key is required';
    END IF;

    SELECT array_agg(DISTINCT recipients.user_id) INTO valid_recipient_ids
    FROM unnest(COALESCE(input_recipient_ids, ARRAY[]::UUID[])) recipients(user_id)
    WHERE recipients.user_id IS NOT NULL
      AND EXISTS (
          SELECT 1 FROM public.school_memberships membership
          WHERE membership.school_id = input_school_id
            AND membership.user_id = recipients.user_id
            AND membership.active = TRUE
      );
    IF COALESCE(cardinality(valid_recipient_ids), 0) = 0 THEN RETURN NULL; END IF;

    INSERT INTO public.notifications (
        school_id, title, body, category, source_type, source_id,
        created_by, dedupe_key, priority, route
    ) VALUES (
        input_school_id, btrim(input_title), btrim(input_body), input_category,
        input_source_type, input_source_id, input_actor_id, input_dedupe_key,
        input_priority, COALESCE(input_route, '{}'::JSONB)
    )
    ON CONFLICT (dedupe_key) WHERE dedupe_key IS NOT NULL
    DO UPDATE SET dedupe_key = EXCLUDED.dedupe_key
    RETURNING id INTO notification_uuid;

    INSERT INTO public.notification_recipients (notification_id, user_id, delivery_state)
    SELECT notification_uuid, recipients.user_id, 'queued'
    FROM unnest(valid_recipient_ids) recipients(user_id)
    ON CONFLICT (notification_id, user_id) DO NOTHING;

    INSERT INTO public.notification_outbox (notification_id, user_id, available_at)
    SELECT notification_uuid, recipients.user_id, availability.available_at
    FROM public.notification_recipients recipients
    CROSS JOIN LATERAL (
        SELECT public.notification_delivery_available_at(
            recipients.user_id, input_category, input_priority
        ) AS available_at
    ) availability
    WHERE recipients.notification_id = notification_uuid
      AND availability.available_at IS NOT NULL
    ON CONFLICT (notification_id, user_id) DO NOTHING;

    RETURN notification_uuid;
END;
$$;
REVOKE ALL ON FUNCTION public.enqueue_workflow_notification(UUID, TEXT, TEXT, TEXT, TEXT, UUID, UUID[], TEXT, TEXT, JSONB, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.enqueue_workflow_notification(UUID, TEXT, TEXT, TEXT, TEXT, UUID, UUID[], TEXT, TEXT, JSONB, UUID) FROM authenticated;

CREATE OR REPLACE FUNCTION public.fetch_school_directory(input_school_id UUID)
RETURNS TABLE (
    user_id UUID,
    display_name TEXT,
    avatar_url TEXT,
    school_role TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF auth.uid() IS NULL OR NOT (
        public.is_school_member(input_school_id, auth.uid())
        OR public.is_hq_director(auth.uid())
    ) THEN
        RAISE EXCEPTION 'School directory access denied';
    END IF;

    RETURN QUERY
    SELECT membership.user_id, profile.display_name, profile.avatar_url, membership.role
    FROM public.school_memberships membership
    JOIN public.profiles profile ON profile.id = membership.user_id
    WHERE membership.school_id = input_school_id
      AND membership.active = TRUE
      AND membership.role IN ('parent', 'teacher', 'school_director')
    ORDER BY
        CASE membership.role WHEN 'school_director' THEN 0 WHEN 'teacher' THEN 1 ELSE 2 END,
        lower(profile.display_name), membership.user_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_child_connection_request(
    input_school_id UUID,
    input_legal_first_name TEXT,
    input_legal_last_name TEXT,
    input_birthdate DATE,
    input_relationship TEXT,
    input_idempotency_key TEXT
)
RETURNS SETOF public.child_connection_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    saved_request public.child_connection_requests%ROWTYPE;
    recipient_ids UUID[];
BEGIN
    IF actor IS NULL OR NOT EXISTS (
        SELECT 1
        FROM public.school_memberships membership
        WHERE membership.school_id = input_school_id
          AND membership.user_id = actor
          AND membership.active = TRUE
          AND membership.role = 'parent'
    ) THEN
        RAISE EXCEPTION 'Only active parents can request a child connection';
    END IF;
    IF input_birthdate IS NULL OR input_birthdate > CURRENT_DATE THEN
        RAISE EXCEPTION 'A valid birthdate is required';
    END IF;
    IF NULLIF(btrim(input_legal_first_name), '') IS NULL
       OR NULLIF(btrim(input_legal_last_name), '') IS NULL
       OR NULLIF(btrim(input_relationship), '') IS NULL
       OR NULLIF(btrim(input_idempotency_key), '') IS NULL THEN
        RAISE EXCEPTION 'Legal name, relationship, and idempotency key are required';
    END IF;

    PERFORM pg_advisory_xact_lock(hashtextextended(actor::TEXT || ':child-connection:' || btrim(input_idempotency_key), 0));
    SELECT * INTO saved_request
    FROM public.child_connection_requests
    WHERE requested_by = actor AND idempotency_key = btrim(input_idempotency_key);

    IF saved_request.id IS NULL THEN
        INSERT INTO public.child_connection_requests (
            school_id, requested_by, legal_first_name, legal_last_name,
            birthdate, relationship, idempotency_key
        ) VALUES (
            input_school_id, actor, btrim(input_legal_first_name), btrim(input_legal_last_name),
            input_birthdate, btrim(input_relationship), btrim(input_idempotency_key)
        ) RETURNING * INTO saved_request;

        SELECT array_agg(membership.user_id) INTO recipient_ids
        FROM public.school_memberships membership
        WHERE membership.school_id = input_school_id
          AND membership.active = TRUE
          AND membership.role = 'school_director';

        PERFORM public.enqueue_workflow_notification(
            input_school_id,
            'Child connection request',
            btrim(input_legal_first_name) || ' ' || btrim(input_legal_last_name) || ' needs review.',
            'child_connection_request', 'child_connection_request', saved_request.id,
            recipient_ids, 'child-connection:requested:' || saved_request.id::TEXT,
            'important', jsonb_build_object('type', 'child_connection_request', 'id', saved_request.id), actor
        );
        INSERT INTO public.workflow_audit_events (school_id, actor_id, event_type, source_type, source_id)
        VALUES (input_school_id, actor, 'requested', 'child_connection_request', saved_request.id);
    END IF;

    RETURN QUERY SELECT * FROM public.child_connection_requests WHERE id = saved_request.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.review_child_connection_request(
    input_request_id UUID,
    input_decision TEXT,
    input_matched_child_id UUID DEFAULT NULL,
    input_review_note TEXT DEFAULT NULL,
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.child_connection_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    request_record public.child_connection_requests%ROWTYPE;
    child_uuid UUID;
BEGIN
    SELECT * INTO request_record
    FROM public.child_connection_requests
    WHERE id = input_request_id
    FOR UPDATE;
    IF NOT FOUND OR NOT (
        public.has_school_role(request_record.school_id, actor, ARRAY['school_director'])
        OR public.is_hq_director(actor)
    ) THEN
        RAISE EXCEPTION 'Only a director can review this request';
    END IF;
    IF input_decision NOT IN ('approved', 'rejected') THEN
        RAISE EXCEPTION 'Decision must be approved or rejected';
    END IF;
    IF request_record.status <> 'pending' THEN
        RETURN QUERY SELECT * FROM public.child_connection_requests WHERE id = request_record.id;
        RETURN;
    END IF;

    IF input_decision = 'approved' THEN
        IF input_matched_child_id IS NOT NULL THEN
            SELECT child.id INTO child_uuid
            FROM public.children child
            WHERE child.id = input_matched_child_id
              AND child.school_id = request_record.school_id
              AND child.active = TRUE;
            IF child_uuid IS NULL THEN RAISE EXCEPTION 'The selected child is not active at this school'; END IF;
        ELSE
            INSERT INTO public.children (school_id, first_name, last_name, birthdate, active)
            VALUES (
                request_record.school_id, request_record.legal_first_name,
                request_record.legal_last_name, request_record.birthdate, TRUE
            ) RETURNING id INTO child_uuid;
        END IF;

        INSERT INTO public.child_guardians (
            child_id, guardian_id, relationship, verification_status, verified_by, verified_at, ended_at
        ) VALUES (
            child_uuid, request_record.requested_by, request_record.relationship,
            'verified', actor, NOW(), NULL
        )
        ON CONFLICT (child_id, guardian_id) DO UPDATE
        SET relationship = EXCLUDED.relationship,
            verification_status = 'verified', verified_by = actor,
            verified_at = NOW(), ended_at = NULL;

        PERFORM public.instantiate_child_onboarding(child_uuid, request_record.requested_by);
    END IF;

    UPDATE public.child_connection_requests
    SET status = input_decision,
        matched_child_id = CASE WHEN input_decision = 'approved' THEN child_uuid ELSE NULL END,
        reviewed_by = actor,
        reviewed_at = NOW(),
        review_note = NULLIF(btrim(COALESCE(input_review_note, '')), ''),
        updated_at = NOW()
    WHERE id = request_record.id
    RETURNING * INTO request_record;

    PERFORM public.enqueue_workflow_notification(
        request_record.school_id,
        CASE WHEN input_decision = 'approved' THEN 'Child connection approved' ELSE 'Child connection update' END,
        CASE WHEN input_decision = 'approved'
            THEN request_record.legal_first_name || ' is now connected to your account.'
            ELSE 'Your child connection request was not approved.' END,
        'child_connection_decision', 'child_connection_request', request_record.id,
        ARRAY[request_record.requested_by],
        'child-connection:' || input_decision || ':' || request_record.id::TEXT,
        'important', jsonb_build_object('type', 'child_connection_request', 'id', request_record.id), actor
    );
    INSERT INTO public.workflow_audit_events (school_id, actor_id, event_type, source_type, source_id, metadata)
    VALUES (
        request_record.school_id, actor, input_decision, 'child_connection_request', request_record.id,
        jsonb_build_object('child_id', child_uuid, 'note', input_review_note)
    );

    RETURN QUERY SELECT * FROM public.child_connection_requests WHERE id = request_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.revoke_child_guardian(input_child_id UUID, input_guardian_id UUID, input_reason TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE actor UUID := auth.uid(); child_record public.children%ROWTYPE;
BEGIN
    SELECT * INTO child_record FROM public.children WHERE id = input_child_id;
    IF NOT FOUND OR NOT public.has_school_role(child_record.school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can revoke a guardian link';
    END IF;
    UPDATE public.child_guardians
    SET verification_status = 'revoked', ended_at = NOW()
    WHERE child_id = input_child_id AND guardian_id = input_guardian_id
      AND verification_status = 'verified' AND ended_at IS NULL;
    IF NOT FOUND THEN RAISE EXCEPTION 'Active guardian link not found'; END IF;
    INSERT INTO public.workflow_audit_events (school_id, actor_id, event_type, source_type, source_id, metadata)
    VALUES (
        child_record.school_id, actor, 'guardian_revoked', 'child', input_child_id,
        jsonb_build_object('guardian_id', input_guardian_id, 'reason', input_reason)
    );
    PERFORM public.enqueue_workflow_notification(
        child_record.school_id, 'Child access removed',
        'A school director removed your access to ' || child_record.first_name || '''s profile.',
        'child_connection_removed', 'child', input_child_id, ARRAY[input_guardian_id],
        'guardian:revoked:' || input_child_id::TEXT || ':' || input_guardian_id::TEXT || ':' || extract(epoch from NOW())::BIGINT,
        'important', jsonb_build_object('type', 'child', 'id', input_child_id), actor
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.refresh_onboarding_access(input_membership_id UUID)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    instance_record public.onboarding_instances%ROWTYPE;
    next_state TEXT;
BEGIN
    SELECT * INTO instance_record
    FROM public.onboarding_instances
    WHERE membership_id = input_membership_id
    ORDER BY started_at DESC
    LIMIT 1;
    IF NOT FOUND THEN
        RETURN (SELECT access_state FROM public.school_memberships WHERE id = input_membership_id);
    END IF;

    IF EXISTS (
        SELECT 1
        FROM public.onboarding_requirement_instances requirement_instance
        JOIN public.onboarding_template_requirements requirement
          ON requirement.id = requirement_instance.template_requirement_id
        WHERE requirement_instance.onboarding_instance_id = instance_record.id
          AND requirement.blocks_access = TRUE
          AND requirement_instance.status NOT IN ('approved', 'waived')
    ) THEN
        next_state := 'onboarding';
    ELSE
        next_state := 'full';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.onboarding_requirement_instances
        WHERE onboarding_instance_id = instance_record.id
          AND status NOT IN ('approved', 'waived')
    ) THEN
        UPDATE public.onboarding_instances
        SET status = 'complete', completed_at = COALESCE(completed_at, NOW())
        WHERE id = instance_record.id;
    END IF;

    UPDATE public.school_memberships SET access_state = next_state WHERE id = input_membership_id;
    RETURN next_state;
END;
$$;

CREATE OR REPLACE FUNCTION public.create_child_guardian_invite(
    input_child_id UUID,
    input_email TEXT,
    input_display_name TEXT DEFAULT NULL,
    input_relationship TEXT DEFAULT 'Parent'
)
RETURNS TABLE (invite_id UUID, invite_token TEXT, expires_at TIMESTAMPTZ)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    child_record public.children%ROWTYPE;
    raw_token TEXT := encode(extensions.gen_random_bytes(32), 'hex');
    saved_invite public.role_invites%ROWTYPE;
BEGIN
    SELECT * INTO child_record FROM public.children WHERE id = input_child_id AND active = TRUE;
    IF NOT FOUND OR NOT public.has_school_role(child_record.school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only the school director can invite a guardian';
    END IF;
    IF NULLIF(btrim(COALESCE(input_email, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Guardian email is required';
    END IF;

    INSERT INTO public.role_invites (
        school_id, email, display_name, role, token_hash, status, invited_by,
        expires_at, child_id, guardian_relationship
    ) VALUES (
        child_record.school_id, lower(btrim(input_email)), NULLIF(btrim(COALESCE(input_display_name, '')), ''),
        'parent', encode(extensions.digest(raw_token, 'sha256'), 'hex'), 'pending', actor,
        NOW() + INTERVAL '14 days', child_record.id, COALESCE(NULLIF(btrim(input_relationship), ''), 'Parent')
    ) RETURNING * INTO saved_invite;

    invite_id := saved_invite.id;
    invite_token := raw_token;
    expires_at := saved_invite.expires_at;
    RETURN NEXT;
END;
$$;

CREATE OR REPLACE FUNCTION public.accept_role_invite(invite_token TEXT)
RETURNS SETOF public.school_memberships
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    invite_record public.role_invites%ROWTYPE;
    joining_user UUID := auth.uid();
    joining_email TEXT := lower(COALESCE(auth.jwt()->>'email', ''));
BEGIN
    IF joining_user IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    IF joining_email = '' THEN RAISE EXCEPTION 'Your account email could not be verified'; END IF;

    SELECT * INTO invite_record
    FROM public.role_invites
    WHERE token_hash = encode(extensions.digest(NULLIF(btrim(invite_token), ''), 'sha256'), 'hex')
      AND status = 'pending'
      AND (expires_at IS NULL OR expires_at > NOW())
    LIMIT 1 FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Invalid or expired invite link'; END IF;
    IF lower(invite_record.email) <> joining_email THEN
        RAISE EXCEPTION 'This invite belongs to a different email account';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.onboarding_templates template
        WHERE template.school_id = invite_record.school_id
          AND template.target_role = invite_record.role
          AND template.status = 'published'
    ) THEN
        RAISE EXCEPTION 'The onboarding template for this invitation is not published yet';
    END IF;

    INSERT INTO public.school_memberships (school_id, user_id, role, active, joined_at)
    VALUES (invite_record.school_id, joining_user, invite_record.role, TRUE, NOW())
    ON CONFLICT (school_id, user_id)
    DO UPDATE SET active = TRUE, role = EXCLUDED.role, joined_at = NOW();

    IF invite_record.child_id IS NOT NULL THEN
        IF NOT EXISTS (
            SELECT 1 FROM public.children child
            WHERE child.id = invite_record.child_id AND child.school_id = invite_record.school_id AND child.active = TRUE
        ) THEN
            RAISE EXCEPTION 'The invited child is no longer active';
        END IF;
        INSERT INTO public.child_guardians (
            child_id, guardian_id, relationship, verification_status,
            verified_by, verified_at, ended_at
        ) VALUES (
            invite_record.child_id, joining_user,
            COALESCE(invite_record.guardian_relationship, 'Parent'),
            'verified', invite_record.invited_by, NOW(), NULL
        )
        ON CONFLICT (child_id, guardian_id) DO UPDATE
        SET relationship = EXCLUDED.relationship,
            verification_status = 'verified', verified_by = EXCLUDED.verified_by,
            verified_at = NOW(), ended_at = NULL;
        PERFORM public.instantiate_child_onboarding(invite_record.child_id, joining_user);
    END IF;

    UPDATE public.role_invites
    SET status = 'accepted', accepted_by = joining_user, accepted_at = NOW(), token = NULL
    WHERE id = invite_record.id;

    IF invite_record.display_name IS NOT NULL THEN
        INSERT INTO public.profiles (id, display_name)
        VALUES (joining_user, invite_record.display_name)
        ON CONFLICT (id) DO UPDATE
        SET display_name = COALESCE(NULLIF(public.profiles.display_name, ''), EXCLUDED.display_name),
            updated_at = NOW();
    END IF;

    RETURN QUERY SELECT * FROM public.school_memberships
    WHERE school_id = invite_record.school_id AND user_id = joining_user;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_assignment_with_payload(
    input_assignment_id UUID,
    input_structured_payload JSONB DEFAULT '{}'::JSONB,
    input_feedback_text TEXT DEFAULT NULL,
    input_attachments JSONB DEFAULT '[]'::JSONB,
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.assignment_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    saved_submission public.assignment_submissions%ROWTYPE;
BEGIN
    IF jsonb_typeof(COALESCE(input_structured_payload, '{}'::JSONB)) <> 'object' THEN
        RAISE EXCEPTION 'Structured answers must be a JSON object';
    END IF;
    SELECT * INTO saved_submission
    FROM public.submit_assignment_v2(
        input_assignment_id, input_feedback_text, input_attachments, input_idempotency_key
    );
    UPDATE public.assignment_submissions
    SET structured_payload = CASE
        WHEN structured_payload = '{}'::JSONB THEN COALESCE(input_structured_payload, '{}'::JSONB)
        ELSE structured_payload
    END
    WHERE id = saved_submission.id
    RETURNING * INTO saved_submission;
    RETURN QUERY SELECT * FROM public.assignment_submissions WHERE id = saved_submission.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fetch_assignment_child_binding(input_assignment_id UUID)
RETURNS TEXT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT COALESCE((
        SELECT requirement.child_record_binding
        FROM public.onboarding_requirement_instances instance
        JOIN public.onboarding_template_requirements requirement
          ON requirement.id = instance.template_requirement_id
        WHERE instance.assignment_id = input_assignment_id
          AND (
              public.is_assignment_recipient(input_assignment_id, auth.uid())
              OR public.can_review_assignment(input_assignment_id, auth.uid())
          )
        LIMIT 1
    ), 'none');
$$;

CREATE OR REPLACE FUNCTION public.save_onboarding_template_requirement_v2(
    input_template_id UUID,
    input_requirement_id UUID DEFAULT NULL,
    input_title TEXT DEFAULT NULL,
    input_description TEXT DEFAULT NULL,
    input_subject_scope TEXT DEFAULT 'member',
    input_position INTEGER DEFAULT 0,
    input_attachments JSONB DEFAULT '[]'::JSONB,
    input_blocks_access BOOLEAN DEFAULT TRUE,
    input_child_record_binding TEXT DEFAULT 'none'
)
RETURNS SETOF public.onboarding_template_requirements
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    template_record public.onboarding_templates%ROWTYPE;
    saved_requirement public.onboarding_template_requirements%ROWTYPE;
BEGIN
    SELECT * INTO template_record FROM public.onboarding_templates WHERE id = input_template_id;
    IF NOT FOUND OR template_record.status <> 'draft'
       OR NOT public.is_onboarding_template_manager(template_record.school_id, template_record.target_role, actor) THEN
        RAISE EXCEPTION 'Requirements can only be changed by a manager in a draft template';
    END IF;
    IF NULLIF(btrim(COALESCE(input_title, '')), '') IS NULL THEN RAISE EXCEPTION 'A requirement title is required'; END IF;
    IF input_subject_scope NOT IN ('member', 'child')
       OR (input_subject_scope = 'child' AND template_record.target_role <> 'parent') THEN
        RAISE EXCEPTION 'Child requirements are available only for parent templates';
    END IF;
    IF input_child_record_binding NOT IN (
        'none', 'child_document', 'immunization_record', 'medical_clearance',
        'medication_authorization', 'emergency_information', 'consent'
    ) OR (input_child_record_binding <> 'none' AND input_subject_scope <> 'child') THEN
        RAISE EXCEPTION 'The child record binding is invalid for this requirement';
    END IF;

    IF input_requirement_id IS NULL THEN
        INSERT INTO public.onboarding_template_requirements (
            template_id, position, title, description, subject_scope, blocks_access, child_record_binding
        ) VALUES (
            template_record.id, GREATEST(COALESCE(input_position, 0), 0), btrim(input_title),
            NULLIF(btrim(COALESCE(input_description, '')), ''), input_subject_scope,
            COALESCE(input_blocks_access, TRUE), input_child_record_binding
        ) RETURNING * INTO saved_requirement;
    ELSE
        UPDATE public.onboarding_template_requirements
        SET title = btrim(input_title), description = NULLIF(btrim(COALESCE(input_description, '')), ''),
            subject_scope = input_subject_scope, blocks_access = COALESCE(input_blocks_access, TRUE),
            child_record_binding = input_child_record_binding, updated_at = NOW()
        WHERE id = input_requirement_id AND template_id = template_record.id
        RETURNING * INTO saved_requirement;
        IF saved_requirement.id IS NULL THEN RAISE EXCEPTION 'Requirement not found in this draft'; END IF;
    END IF;

    DELETE FROM public.onboarding_template_attachments WHERE requirement_id = saved_requirement.id;
    INSERT INTO public.onboarding_template_attachments (
        requirement_id, position, private_file_path, file_name, content_type
    )
    SELECT saved_requirement.id, attachment.ordinality::INTEGER - 1,
        attachment.value->>'private_file_path', attachment.value->>'file_name',
        NULLIF(attachment.value->>'content_type', '')
    FROM jsonb_array_elements(COALESCE(input_attachments, '[]'::JSONB))
      WITH ORDINALITY AS attachment(value, ordinality)
    WHERE NULLIF(attachment.value->>'private_file_path', '') IS NOT NULL
      AND NULLIF(attachment.value->>'file_name', '') IS NOT NULL;
    RETURN QUERY SELECT * FROM public.onboarding_template_requirements WHERE id = saved_requirement.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.bind_approved_child_submission()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    binding TEXT;
    child_uuid UUID;
    assignment_record public.assignments%ROWTYPE;
    attachment_record public.assignment_submission_attachments%ROWTYPE;
    instruction_uuid UUID;
    scheduled_timestamp TIMESTAMPTZ;
BEGIN
    IF NEW.status <> 'accepted' OR OLD.status = 'accepted' THEN RETURN NEW; END IF;

    SELECT requirement.child_record_binding, requirement_instance.child_id
    INTO binding, child_uuid
    FROM public.onboarding_requirement_instances requirement_instance
    JOIN public.onboarding_template_requirements requirement
      ON requirement.id = requirement_instance.template_requirement_id
    WHERE requirement_instance.assignment_id = NEW.assignment_id
      AND requirement_instance.child_id IS NOT NULL
    LIMIT 1;
    IF binding IS NULL OR binding = 'none' THEN RETURN NEW; END IF;

    SELECT * INTO assignment_record FROM public.assignments WHERE id = NEW.assignment_id;
    SELECT * INTO attachment_record
    FROM public.assignment_submission_attachments
    WHERE submission_id = NEW.id
    ORDER BY created_at, id LIMIT 1;
    IF attachment_record.id IS NULL THEN
        RAISE EXCEPTION 'An approved child record submission must include evidence';
    END IF;

    IF binding = 'medication_authorization' THEN
        IF NULLIF(btrim(NEW.structured_payload->>'medication_name'), '') IS NULL
           OR NULLIF(btrim(NEW.structured_payload->>'scheduled_at'), '') IS NULL THEN
            RAISE EXCEPTION 'Medication name and schedule are required';
        END IF;
        scheduled_timestamp := (NEW.structured_payload->>'scheduled_at')::TIMESTAMPTZ;
        INSERT INTO public.medication_instructions (
            school_id, child_id, title, dosage, instructions, scheduled_at,
            repeat_rule, starts_on, ends_on, created_by, active,
            source_assignment_submission_id, verified_by, verified_at
        ) VALUES (
            NEW.school_id, child_uuid, btrim(NEW.structured_payload->>'medication_name'),
            NULLIF(btrim(NEW.structured_payload->>'dosage'), ''),
            NULLIF(btrim(NEW.structured_payload->>'instructions'), ''), scheduled_timestamp,
            NULLIF(btrim(NEW.structured_payload->>'repeat_rule'), ''),
            NULLIF(NEW.structured_payload->>'starts_on', '')::DATE,
            NULLIF(NEW.structured_payload->>'ends_on', '')::DATE,
            NEW.submitted_by, TRUE, NEW.id, NEW.reviewed_by, NEW.reviewed_at
        )
        ON CONFLICT (source_assignment_submission_id) WHERE source_assignment_submission_id IS NOT NULL
        DO UPDATE SET active = TRUE, verified_by = EXCLUDED.verified_by, verified_at = EXCLUDED.verified_at
        RETURNING id INTO instruction_uuid;

        INSERT INTO public.medication_tasks (school_id, child_id, instruction_id, due_at, status)
        SELECT NEW.school_id, child_uuid, instruction_uuid, scheduled_timestamp, 'pending'
        WHERE NOT EXISTS (
            SELECT 1 FROM public.medication_tasks task
            WHERE task.instruction_id = instruction_uuid AND task.due_at = scheduled_timestamp
        );
    ELSE
        INSERT INTO public.child_documents (
            school_id, child_id, title, document_type, file_name, file_path,
            uploaded_by, verification_status, reviewed_by, reviewed_at,
            source_assignment_submission_id, source_attachment_id, expires_on
        ) VALUES (
            NEW.school_id, child_uuid, assignment_record.title, binding,
            attachment_record.file_name, attachment_record.private_file_path,
            NEW.submitted_by, 'verified', NEW.reviewed_by, NEW.reviewed_at,
            NEW.id, attachment_record.id, NULLIF(NEW.structured_payload->>'expires_on', '')::DATE
        )
        ON CONFLICT (source_assignment_submission_id) WHERE source_assignment_submission_id IS NOT NULL
        DO UPDATE SET verification_status = 'verified', reviewed_by = EXCLUDED.reviewed_by,
            reviewed_at = EXCLUDED.reviewed_at, expires_on = EXCLUDED.expires_on;
    END IF;

    INSERT INTO public.workflow_audit_events (
        school_id, actor_id, event_type, source_type, source_id, metadata
    ) VALUES (
        NEW.school_id, NEW.reviewed_by, 'bound_record_created', 'assignment_submission', NEW.id,
        jsonb_build_object('binding', binding, 'child_id', child_uuid)
    );
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS bind_approved_child_submission_trigger ON public.assignment_submissions;
CREATE TRIGGER bind_approved_child_submission_trigger
    AFTER UPDATE OF status ON public.assignment_submissions
    FOR EACH ROW EXECUTE FUNCTION public.bind_approved_child_submission();

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

    PERFORM pg_advisory_xact_lock(hashtextextended(actor::TEXT || ':attendance:' || btrim(input_idempotency_key), 0));
    SELECT * INTO session_record
    FROM public.attendance_sessions
    WHERE school_id = child_record.school_id AND idempotency_key = btrim(input_idempotency_key);
    IF session_record.id IS NOT NULL THEN
        RETURN QUERY SELECT * FROM public.attendance_sessions WHERE id = session_record.id;
        RETURN;
    END IF;

    IF input_action = 'check_in' THEN
        IF EXISTS (
            SELECT 1 FROM public.attendance_sessions
            WHERE child_id = input_child_id AND checked_in_at IS NOT NULL AND checked_out_at IS NULL
        ) THEN RAISE EXCEPTION 'This child already has an open attendance session'; END IF;
        INSERT INTO public.attendance_sessions (
            school_id, child_id, attendance_date, state, checked_in_at,
            checked_in_by, notes, idempotency_key
        ) VALUES (
            child_record.school_id, input_child_id,
            (input_occurred_at AT TIME ZONE 'America/New_York')::DATE,
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
        INSERT INTO public.attendance_sessions (
            school_id, child_id, attendance_date, state, notes, idempotency_key
        ) VALUES (
            child_record.school_id, input_child_id,
            (input_occurred_at AT TIME ZONE 'America/New_York')::DATE,
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
    before_record := to_jsonb(session_record);
    UPDATE public.attendance_sessions
    SET checked_in_at = input_checked_in_at, checked_out_at = input_checked_out_at,
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

CREATE OR REPLACE FUNCTION public.record_child_care_event(
    input_child_id UUID,
    input_event_type TEXT,
    input_occurred_at TIMESTAMPTZ,
    input_details JSONB,
    input_visibility TEXT,
    input_medication_task_id UUID DEFAULT NULL,
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.child_care_events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    child_record public.children%ROWTYPE;
    saved_event public.child_care_events%ROWTYPE;
    guardian_ids UUID[];
BEGIN
    SELECT * INTO child_record FROM public.children WHERE id = input_child_id AND active = TRUE;
    IF NOT FOUND OR NOT public.can_staff_access_child(input_child_id, actor, ARRAY['teacher', 'school_director']) THEN
        RAISE EXCEPTION 'You cannot record care for this child';
    END IF;
    IF input_event_type NOT IN ('meal', 'bottle', 'nap', 'potty', 'diaper', 'medication', 'health_check', 'activity', 'note', 'photo') THEN
        RAISE EXCEPTION 'Invalid care event type';
    END IF;
    IF input_visibility NOT IN ('parent', 'staff_only') THEN RAISE EXCEPTION 'Invalid visibility'; END IF;
    IF jsonb_typeof(COALESCE(input_details, '{}'::JSONB)) <> 'object' THEN RAISE EXCEPTION 'Details must be an object'; END IF;
    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NULL THEN RAISE EXCEPTION 'An idempotency key is required'; END IF;
    IF input_event_type = 'photo' AND (
        NULLIF(btrim(COALESCE(input_details->>'photo_path', '')), '') IS NULL
        OR input_details->>'photo_path' NOT LIKE (
            'schools/' || child_record.school_id::TEXT || '/care_events/' || input_child_id::TEXT
            || '/' || input_visibility || '/' || actor::TEXT || '/%'
        )
    ) THEN RAISE EXCEPTION 'Photo care events require a private photo uploaded by the recording staff member'; END IF;

    INSERT INTO public.child_care_events (
        school_id, child_id, event_type, occurred_at, details, visibility,
        recorded_by, source_medication_task_id, idempotency_key
    ) VALUES (
        child_record.school_id, input_child_id, input_event_type,
        COALESCE(input_occurred_at, NOW()), COALESCE(input_details, '{}'::JSONB),
        input_visibility, actor, input_medication_task_id, btrim(input_idempotency_key)
    )
    ON CONFLICT (recorded_by, idempotency_key) DO UPDATE SET idempotency_key = EXCLUDED.idempotency_key
    RETURNING * INTO saved_event;

    IF input_event_type = 'medication' THEN
        IF input_medication_task_id IS NULL OR NOT EXISTS (
            SELECT 1 FROM public.medication_tasks task
            JOIN public.medication_instructions instruction ON instruction.id = task.instruction_id
            WHERE task.id = input_medication_task_id
              AND task.child_id = input_child_id
              AND instruction.source_assignment_submission_id IS NOT NULL
        ) THEN RAISE EXCEPTION 'Medication care requires an approved authorization task'; END IF;
        UPDATE public.medication_tasks SET status = 'acknowledged' WHERE id = input_medication_task_id;
        INSERT INTO public.medication_acknowledgements (
            task_id, school_id, child_id, acknowledged_by, dosage_given, notes, given_at
        )
        SELECT input_medication_task_id, child_record.school_id, input_child_id, actor,
            NULLIF(input_details->>'dosage_given', ''), NULLIF(input_details->>'notes', ''), saved_event.occurred_at
        WHERE NOT EXISTS (
            SELECT 1 FROM public.medication_acknowledgements WHERE task_id = input_medication_task_id
        );
    END IF;

    IF input_visibility = 'parent' AND input_event_type IN ('medication', 'health_check') THEN
        SELECT array_agg(guardian.guardian_id) INTO guardian_ids
        FROM public.child_guardians guardian
        WHERE guardian.child_id = input_child_id
          AND guardian.verification_status = 'verified' AND guardian.ended_at IS NULL;
        PERFORM public.enqueue_workflow_notification(
            child_record.school_id,
            CASE WHEN input_event_type = 'medication' THEN 'Medication administered' ELSE 'Health update' END,
            child_record.first_name || ' has a new ' || replace(input_event_type, '_', ' ') || ' update.',
            'care_' || input_event_type, 'child_care_event', saved_event.id,
            guardian_ids, 'care:' || input_event_type || ':' || saved_event.id::TEXT,
            CASE WHEN input_event_type = 'health_check' THEN 'urgent' ELSE 'important' END,
            jsonb_build_object('type', 'child_care_event', 'id', saved_event.id, 'child_id', input_child_id), actor
        );
    END IF;
    INSERT INTO public.workflow_audit_events (school_id, actor_id, event_type, source_type, source_id)
    VALUES (child_record.school_id, actor, 'recorded', 'child_care_event', saved_event.id);
    RETURN QUERY SELECT * FROM public.child_care_events WHERE id = saved_event.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_family_request(
    input_child_id UUID,
    input_request_type TEXT,
    input_details JSONB,
    input_idempotency_key TEXT
)
RETURNS SETOF public.family_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    child_record public.children%ROWTYPE;
    saved_request public.family_requests%ROWTYPE;
BEGIN
    SELECT * INTO child_record FROM public.children WHERE id = input_child_id AND active = TRUE;
    IF NOT FOUND OR NOT public.is_child_guardian(input_child_id, actor) THEN
        RAISE EXCEPTION 'Only a verified guardian can submit a family request';
    END IF;
    IF input_request_type NOT IN ('absence', 'pickup_change', 'medication', 'general') THEN RAISE EXCEPTION 'Invalid request type'; END IF;
    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NULL THEN RAISE EXCEPTION 'An idempotency key is required'; END IF;

    INSERT INTO public.family_requests (
        school_id, child_id, requested_by, request_type, details, idempotency_key
    ) VALUES (
        child_record.school_id, input_child_id, actor, input_request_type,
        COALESCE(input_details, '{}'::JSONB), btrim(input_idempotency_key)
    )
    ON CONFLICT (requested_by, idempotency_key) DO UPDATE SET idempotency_key = EXCLUDED.idempotency_key
    RETURNING * INTO saved_request;

    PERFORM public.enqueue_workflow_notification(
        child_record.school_id, 'Family request: ' || replace(input_request_type, '_', ' '),
        child_record.first_name || ' has a new family request.',
        'family_request', 'family_request', saved_request.id,
        ARRAY(
            SELECT membership.user_id FROM public.school_memberships membership
            WHERE membership.school_id = child_record.school_id AND membership.active = TRUE
              AND membership.role IN ('teacher', 'school_director')
        ), 'family-request:' || saved_request.id::TEXT,
        CASE WHEN input_request_type IN ('pickup_change', 'medication') THEN 'important' ELSE 'routine' END,
        jsonb_build_object('type', 'family_request', 'id', saved_request.id, 'child_id', input_child_id), actor
    );
    INSERT INTO public.workflow_audit_events (school_id, actor_id, event_type, source_type, source_id)
    VALUES (child_record.school_id, actor, 'submitted', 'family_request', saved_request.id);
    RETURN QUERY SELECT * FROM public.family_requests WHERE id = saved_request.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_family_request_status(
    input_request_id UUID,
    input_status TEXT
)
RETURNS SETOF public.family_requests
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE actor UUID := auth.uid(); saved_request public.family_requests%ROWTYPE;
BEGIN
    SELECT * INTO saved_request FROM public.family_requests WHERE id = input_request_id FOR UPDATE;
    IF NOT FOUND OR NOT public.can_staff_access_child(saved_request.child_id, actor, ARRAY['teacher', 'school_director']) THEN
        RAISE EXCEPTION 'Only school staff can update a family request';
    END IF;
    IF input_status NOT IN ('acknowledged', 'completed') THEN RAISE EXCEPTION 'Invalid family request status'; END IF;
    UPDATE public.family_requests
    SET status = input_status, handled_by = actor, handled_at = NOW(), updated_at = NOW()
    WHERE id = input_request_id RETURNING * INTO saved_request;
    PERFORM public.enqueue_workflow_notification(
        saved_request.school_id, 'Family request ' || input_status,
        'Your ' || replace(saved_request.request_type, '_', ' ') || ' request was ' || input_status || '.',
        'family_request_' || input_status, 'family_request', saved_request.id,
        ARRAY[saved_request.requested_by], 'family-request:' || input_status || ':' || saved_request.id::TEXT,
        'routine', jsonb_build_object('type', 'family_request', 'id', saved_request.id, 'child_id', saved_request.child_id), actor
    );
    RETURN QUERY SELECT * FROM public.family_requests WHERE id = saved_request.id;
END;
$$;

CREATE TABLE IF NOT EXISTS public.notification_preferences (
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    category TEXT NOT NULL,
    enabled BOOLEAN NOT NULL DEFAULT TRUE,
    quiet_hours_start TIME,
    quiet_hours_end TIME,
    time_zone TEXT NOT NULL DEFAULT 'America/New_York',
    updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    PRIMARY KEY (user_id, category),
    CHECK (category NOT IN ('medication', 'health', 'medication_missed', 'care_health_check') OR enabled = TRUE)
);
ALTER TABLE public.notification_preferences ENABLE ROW LEVEL SECURITY;

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
    preference_category TEXT;
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
        WHEN input_category = 'school_announcement' THEN 'announcements'
        WHEN input_category LIKE 'medication_%' OR input_category = 'care_medication' THEN 'medication'
        WHEN input_category = 'care_health_check' THEN 'health'
        ELSE input_category
    END;
    SELECT * INTO preference FROM public.notification_preferences
    WHERE user_id = input_user_id AND category IN (input_category, preference_category)
    ORDER BY (category = input_category) DESC
    LIMIT 1;
    IF input_priority = 'urgent' OR input_category IN ('medication_missed', 'care_health_check') THEN RETURN NOW(); END IF;
    IF FOUND AND preference.enabled = FALSE THEN RETURN NULL; END IF;
    IF NOT FOUND OR preference.quiet_hours_start IS NULL OR preference.quiet_hours_end IS NULL THEN RETURN NOW(); END IF;

    local_now := NOW() AT TIME ZONE preference.time_zone;
    local_date := local_now::DATE;
    local_time := local_now::TIME;
    IF preference.quiet_hours_start < preference.quiet_hours_end THEN
        IF local_time >= preference.quiet_hours_start AND local_time < preference.quiet_hours_end THEN
            next_delivery_local := local_date + preference.quiet_hours_end;
        ELSE RETURN NOW(); END IF;
    ELSE
        IF local_time >= preference.quiet_hours_start THEN
            next_delivery_local := (local_date + 1) + preference.quiet_hours_end;
        ELSIF local_time < preference.quiet_hours_end THEN
            next_delivery_local := local_date + preference.quiet_hours_end;
        ELSE RETURN NOW(); END IF;
    END IF;
    RETURN next_delivery_local AT TIME ZONE preference.time_zone;
END;
$$;
REVOKE ALL ON FUNCTION public.notification_delivery_available_at(UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.notification_delivery_available_at(UUID, TEXT, TEXT) FROM authenticated;

CREATE OR REPLACE FUNCTION public.route_notification_recipient_to_outbox()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    notification_record public.notifications%ROWTYPE;
    delivery_time TIMESTAMPTZ;
BEGIN
    SELECT * INTO notification_record FROM public.notifications WHERE id = NEW.notification_id;
    delivery_time := public.notification_delivery_available_at(
        NEW.user_id, notification_record.category, notification_record.priority
    );
    IF delivery_time IS NULL THEN
        UPDATE public.notification_recipients
        SET delivery_state = 'expired', expired_at = NOW()
        WHERE notification_id = NEW.notification_id AND user_id = NEW.user_id;
    ELSE
        INSERT INTO public.notification_outbox (notification_id, user_id, available_at)
        VALUES (NEW.notification_id, NEW.user_id, delivery_time)
        ON CONFLICT (notification_id, user_id) DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS route_notification_recipient_to_outbox_trigger ON public.notification_recipients;
CREATE TRIGGER route_notification_recipient_to_outbox_trigger
    AFTER INSERT ON public.notification_recipients
    FOR EACH ROW EXECUTE FUNCTION public.route_notification_recipient_to_outbox();
REVOKE ALL ON FUNCTION public.route_notification_recipient_to_outbox() FROM PUBLIC, authenticated;

CREATE OR REPLACE FUNCTION public.process_due_medication_tasks()
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    task_record RECORD;
    due_count INTEGER := 0;
    missed_count INTEGER := 0;
    staff_ids UUID[];
BEGIN
    IF COALESCE(auth.jwt()->>'role', '') <> 'service_role' THEN RAISE EXCEPTION 'Service role required'; END IF;

    FOR task_record IN
        UPDATE public.medication_tasks task
        SET status = 'due'
        FROM public.children child
        WHERE task.child_id = child.id
          AND task.status = 'pending'
          AND task.due_at <= NOW()
        RETURNING task.*, child.first_name
    LOOP
        SELECT array_agg(membership.user_id) INTO staff_ids
        FROM public.school_memberships membership
        WHERE membership.school_id = task_record.school_id
          AND membership.active = TRUE
          AND membership.role IN ('teacher', 'school_director');
        PERFORM public.enqueue_workflow_notification(
            task_record.school_id, 'Medication due',
            task_record.first_name || ' has medication due now.',
            'medication_due', 'medication_task', task_record.id, staff_ids,
            'medication:due:' || task_record.id::TEXT, 'important',
            jsonb_build_object('type', 'medication_task', 'id', task_record.id, 'child_id', task_record.child_id), NULL
        );
        due_count := due_count + 1;
    END LOOP;

    FOR task_record IN
        UPDATE public.medication_tasks task
        SET status = 'missed', escalated_at = NOW()
        FROM public.children child
        WHERE task.child_id = child.id
          AND task.status = 'due'
          AND task.due_at < NOW() - INTERVAL '15 minutes'
          AND NOT EXISTS (
              SELECT 1 FROM public.medication_acknowledgements acknowledgement
              WHERE acknowledgement.task_id = task.id
          )
        RETURNING task.*, child.first_name
    LOOP
        INSERT INTO public.medication_escalations (task_id, school_id, child_id, reason)
        VALUES (
            task_record.id, task_record.school_id, task_record.child_id,
            'Medication task was not acknowledged within 15 minutes'
        ) ON CONFLICT (task_id) DO NOTHING;
        SELECT array_agg(membership.user_id) INTO staff_ids
        FROM public.school_memberships membership
        WHERE membership.school_id = task_record.school_id
          AND membership.active = TRUE
          AND membership.role IN ('teacher', 'school_director');
        PERFORM public.enqueue_workflow_notification(
            task_record.school_id, 'Medication missed',
            task_record.first_name || '''s medication was not recorded within 15 minutes.',
            'medication_missed', 'medication_task', task_record.id, staff_ids,
            'medication:missed:' || task_record.id::TEXT, 'urgent',
            jsonb_build_object('type', 'medication_task', 'id', task_record.id, 'child_id', task_record.child_id), NULL
        );
        missed_count := missed_count + 1;
    END LOOP;
    RETURN jsonb_build_object('due', due_count, 'missed', missed_count);
END;
$$;
REVOKE ALL ON FUNCTION public.process_due_medication_tasks() FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION public.process_due_medication_tasks() TO service_role;

CREATE OR REPLACE FUNCTION public.claim_notification_outbox(input_limit INTEGER DEFAULT 100)
RETURNS SETOF public.notification_outbox
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF COALESCE(auth.jwt()->>'role', '') <> 'service_role' THEN RAISE EXCEPTION 'Service role required'; END IF;
    RETURN QUERY
    WITH candidates AS (
        SELECT outbox.id FROM public.notification_outbox outbox
        WHERE outbox.completed_at IS NULL AND outbox.available_at <= NOW()
          AND (outbox.locked_at IS NULL OR outbox.locked_at < NOW() - INTERVAL '5 minutes')
        ORDER BY outbox.available_at LIMIT LEAST(GREATEST(input_limit, 1), 500)
        FOR UPDATE SKIP LOCKED
    )
    UPDATE public.notification_outbox outbox
    SET locked_at = NOW(), attempt_count = outbox.attempt_count + 1
    FROM candidates WHERE outbox.id = candidates.id
    RETURNING outbox.*;
END;
$$;

CREATE OR REPLACE FUNCTION public.complete_notification_delivery(
    input_outbox_id UUID,
    input_succeeded BOOLEAN,
    input_error TEXT DEFAULT NULL
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE outbox_record public.notification_outbox%ROWTYPE; next_delay INTERVAL;
BEGIN
    IF COALESCE(auth.jwt()->>'role', '') <> 'service_role' THEN RAISE EXCEPTION 'Service role required'; END IF;
    SELECT * INTO outbox_record FROM public.notification_outbox WHERE id = input_outbox_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Outbox item not found'; END IF;
    IF input_succeeded THEN
        UPDATE public.notification_outbox SET completed_at = NOW(), locked_at = NULL, last_error = NULL WHERE id = input_outbox_id;
        UPDATE public.notification_recipients
        SET delivered_at = COALESCE(delivered_at, NOW()), delivery_state = 'delivered',
            attempt_count = outbox_record.attempt_count, last_error = NULL
        WHERE notification_id = outbox_record.notification_id AND user_id = outbox_record.user_id;
    ELSIF outbox_record.attempt_count >= 8 THEN
        UPDATE public.notification_outbox
        SET completed_at = NOW(), locked_at = NULL, last_error = left(input_error, 1000)
        WHERE id = input_outbox_id;
        UPDATE public.notification_recipients
        SET delivery_state = 'expired', attempt_count = outbox_record.attempt_count,
            last_error = left(input_error, 1000), expired_at = NOW()
        WHERE notification_id = outbox_record.notification_id AND user_id = outbox_record.user_id;
    ELSE
        next_delay := make_interval(secs => LEAST(POWER(2, outbox_record.attempt_count)::INTEGER * 30, 21600));
        UPDATE public.notification_outbox
        SET locked_at = NULL, available_at = NOW() + next_delay, last_error = left(input_error, 1000)
        WHERE id = input_outbox_id;
        UPDATE public.notification_recipients
        SET delivery_state = 'failed', attempt_count = outbox_record.attempt_count, last_error = left(input_error, 1000)
        WHERE notification_id = outbox_record.notification_id AND user_id = outbox_record.user_id;
    END IF;
END;
$$;
REVOKE ALL ON FUNCTION public.claim_notification_outbox(INTEGER) FROM PUBLIC, authenticated;
REVOKE ALL ON FUNCTION public.complete_notification_delivery(UUID, BOOLEAN, TEXT) FROM PUBLIC, authenticated;
GRANT EXECUTE ON FUNCTION public.claim_notification_outbox(INTEGER) TO service_role;
GRANT EXECUTE ON FUNCTION public.complete_notification_delivery(UUID, BOOLEAN, TEXT) TO service_role;

CREATE OR REPLACE FUNCTION public.create_school_announcement(
    input_school_id UUID,
    input_title TEXT,
    input_body TEXT,
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
    sanitized_recipients UUID[];
    notification_uuid UUID;
BEGIN
    IF NOT public.has_school_role(input_school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can send announcements';
    END IF;
    IF NULLIF(btrim(COALESCE(input_title, '')), '') IS NULL
       OR NULLIF(btrim(COALESCE(input_body, '')), '') IS NULL
       OR NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Title, message, and idempotency key are required';
    END IF;
    SELECT array_agg(membership.user_id) INTO sanitized_recipients
    FROM public.school_memberships membership
    WHERE membership.school_id = input_school_id
      AND membership.active = TRUE
      AND membership.role IN ('parent', 'teacher', 'school_director')
      AND membership.user_id = ANY(COALESCE(input_recipient_ids, ARRAY[]::UUID[]));
    notification_uuid := public.enqueue_workflow_notification(
        input_school_id, input_title, input_body, 'announcement', 'school', input_school_id,
        sanitized_recipients, 'announcement:' || actor::TEXT || ':' || btrim(input_idempotency_key),
        'important', jsonb_build_object('type', 'school_announcement', 'school_id', input_school_id), actor
    );
    INSERT INTO public.workflow_audit_events (school_id, actor_id, event_type, source_type, source_id)
    VALUES (input_school_id, actor, 'announced', 'notification', notification_uuid);
    RETURN notification_uuid;
END;
$$;

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
DECLARE actor UUID := auth.uid();
BEGIN
    IF actor IS NULL OR NOT (
        public.has_school_role(input_school_id, actor, ARRAY['teacher', 'school_director'])
        OR public.is_hq_director(actor)
    ) THEN RAISE EXCEPTION 'Only school staff can create workflow notifications'; END IF;
    RETURN public.enqueue_workflow_notification(
        input_school_id, input_title, input_body, input_category,
        input_source_type, input_source_id, input_recipient_ids,
        'workflow:' || actor::TEXT || ':' || btrim(input_idempotency_key),
        'routine', jsonb_build_object('type', COALESCE(input_source_type, 'notification'), 'id', input_source_id), actor
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_director_chat_room(
    input_school_id UUID,
    input_name TEXT,
    input_description TEXT DEFAULT NULL,
    input_profile_image_url TEXT DEFAULT NULL,
    input_participant_ids UUID[] DEFAULT ARRAY[]::UUID[],
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.chat_rooms
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    room_record public.chat_rooms%ROWTYPE;
    existing_result UUID;
    participant UUID;
BEGIN
    IF NOT public.has_school_role(input_school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can create rooms';
    END IF;
    IF NULLIF(btrim(COALESCE(input_name, '')), '') IS NULL
       OR NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Room name and idempotency key are required';
    END IF;
    PERFORM pg_advisory_xact_lock(hashtextextended(actor::TEXT || ':chat-create:' || btrim(input_idempotency_key), 0));
    SELECT result_id INTO existing_result FROM public.school_workflow_mutations
    WHERE actor_id = actor AND operation = 'create_chat_room' AND idempotency_key = btrim(input_idempotency_key);
    IF existing_result IS NOT NULL THEN
        RETURN QUERY SELECT * FROM public.chat_rooms WHERE id = existing_result;
        RETURN;
    END IF;

    IF EXISTS (
        SELECT selected.user_id
        FROM unnest(COALESCE(input_participant_ids, ARRAY[]::UUID[])) selected(user_id)
        WHERE NOT EXISTS (
            SELECT 1 FROM public.school_memberships membership
            WHERE membership.school_id = input_school_id
              AND membership.user_id = selected.user_id
              AND membership.active = TRUE
              AND membership.role IN ('parent', 'teacher', 'school_director')
        )
    ) THEN RAISE EXCEPTION 'Every participant must be an active adult school member'; END IF;

    INSERT INTO public.chat_rooms (
        name, description, profile_image_url, invite_hash, room_type,
        created_by, school_id, created_at, updated_at
    ) VALUES (
        btrim(input_name), NULLIF(btrim(COALESCE(input_description, '')), ''),
        NULLIF(btrim(COALESCE(input_profile_image_url, '')), ''), NULL,
        'director_managed', actor, input_school_id, NOW(), NOW()
    ) RETURNING * INTO room_record;

    INSERT INTO public.chat_participants (room_id, user_id, role)
    VALUES (room_record.id, actor, 'owner')
    ON CONFLICT (room_id, user_id) DO UPDATE SET role = 'owner';
    INSERT INTO public.chat_participants (room_id, user_id, role)
    SELECT room_record.id, selected.user_id, CASE WHEN selected.user_id = actor THEN 'owner' ELSE 'member' END
    FROM (SELECT DISTINCT unnest(COALESCE(input_participant_ids, ARRAY[]::UUID[])) AS user_id) selected
    ON CONFLICT (room_id, user_id) DO NOTHING;

    INSERT INTO public.chat_participant_audit (room_id, school_id, user_id, action, acted_by)
    SELECT room_record.id, input_school_id, participant_row.user_id, 'added', actor
    FROM public.chat_participants participant_row WHERE participant_row.room_id = room_record.id;

    PERFORM public.enqueue_workflow_notification(
        input_school_id, 'Added to ' || room_record.name,
        'A school director added you to a group chat.',
        'chat_invitation', 'chat_room', room_record.id,
        ARRAY(
            SELECT row.user_id FROM public.chat_participants row
            WHERE row.room_id = room_record.id AND row.user_id <> actor
        ), 'chat:created:' || room_record.id::TEXT,
        'routine', jsonb_build_object('type', 'chat_room', 'id', room_record.id), actor
    );
    INSERT INTO public.school_workflow_mutations (actor_id, operation, idempotency_key, result_id)
    VALUES (actor, 'create_chat_room', btrim(input_idempotency_key), room_record.id);
    INSERT INTO public.workflow_audit_events (school_id, actor_id, event_type, source_type, source_id)
    VALUES (input_school_id, actor, 'created', 'chat_room', room_record.id);
    RETURN QUERY SELECT * FROM public.chat_rooms WHERE id = room_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_director_chat_room(
    input_room_id UUID,
    input_name TEXT,
    input_description TEXT DEFAULT NULL,
    input_profile_image_url TEXT DEFAULT NULL,
    input_archived BOOLEAN DEFAULT FALSE
)
RETURNS SETOF public.chat_rooms
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE room_record public.chat_rooms%ROWTYPE;
BEGIN
    SELECT * INTO room_record FROM public.chat_rooms WHERE id = input_room_id AND deleted_at IS NULL FOR UPDATE;
    IF NOT FOUND OR NOT public.has_school_role(room_record.school_id, auth.uid(), ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can update this room';
    END IF;
    IF NULLIF(btrim(COALESCE(input_name, '')), '') IS NULL THEN RAISE EXCEPTION 'Room name is required'; END IF;
    UPDATE public.chat_rooms
    SET name = btrim(input_name), description = NULLIF(btrim(COALESCE(input_description, '')), ''),
        profile_image_url = NULLIF(btrim(COALESCE(input_profile_image_url, '')), ''),
        archived_at = CASE WHEN input_archived THEN COALESCE(archived_at, NOW()) ELSE NULL END,
        updated_at = NOW()
    WHERE id = input_room_id RETURNING * INTO room_record;
    RETURN QUERY SELECT * FROM public.chat_rooms WHERE id = room_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_director_chat_room_image_path(
    input_room_id UUID,
    input_profile_image_path TEXT
)
RETURNS SETOF public.chat_rooms
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE room_record public.chat_rooms%ROWTYPE;
BEGIN
    SELECT * INTO room_record FROM public.chat_rooms WHERE id = input_room_id AND deleted_at IS NULL FOR UPDATE;
    IF NOT FOUND OR NOT public.has_school_role(room_record.school_id, auth.uid(), ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can update this room image';
    END IF;
    UPDATE public.chat_rooms
    SET profile_image_path = NULLIF(btrim(COALESCE(input_profile_image_path, '')), ''), updated_at = NOW()
    WHERE id = input_room_id RETURNING * INTO room_record;
    RETURN QUERY SELECT * FROM public.chat_rooms WHERE id = room_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_director_chat_participants(
    input_room_id UUID,
    input_participant_ids UUID[]
)
RETURNS TABLE (room_id UUID, user_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    room_record public.chat_rooms%ROWTYPE;
    added_ids UUID[];
    removed_ids UUID[];
BEGIN
    SELECT * INTO room_record FROM public.chat_rooms WHERE id = input_room_id AND deleted_at IS NULL FOR UPDATE;
    IF NOT FOUND OR NOT public.has_school_role(room_record.school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can manage room membership';
    END IF;
    IF EXISTS (
        SELECT selected.user_id FROM unnest(COALESCE(input_participant_ids, ARRAY[]::UUID[])) selected(user_id)
        WHERE NOT EXISTS (
            SELECT 1 FROM public.school_memberships membership
            WHERE membership.school_id = room_record.school_id
              AND membership.user_id = selected.user_id AND membership.active = TRUE
              AND membership.role IN ('parent', 'teacher', 'school_director')
        )
    ) THEN RAISE EXCEPTION 'Every participant must be an active adult school member'; END IF;

    INSERT INTO public.chat_participants (room_id, user_id, role)
    VALUES (input_room_id, actor, 'owner')
    ON CONFLICT ON CONSTRAINT chat_participants_pkey DO UPDATE SET role = 'owner';

    SELECT array_agg(existing.user_id) INTO removed_ids
    FROM public.chat_participants existing
    WHERE existing.room_id = input_room_id AND existing.user_id <> actor
      AND NOT (existing.user_id = ANY(COALESCE(input_participant_ids, ARRAY[]::UUID[])));
    SELECT array_agg(selected.user_id) INTO added_ids
    FROM (SELECT DISTINCT unnest(COALESCE(input_participant_ids, ARRAY[]::UUID[])) AS user_id) selected
    WHERE selected.user_id <> actor AND NOT EXISTS (
        SELECT 1 FROM public.chat_participants existing
        WHERE existing.room_id = input_room_id AND existing.user_id = selected.user_id
    );

    INSERT INTO public.chat_participant_audit (room_id, school_id, user_id, action, acted_by)
    SELECT input_room_id, room_record.school_id, removed.user_id, 'removed', actor
    FROM unnest(COALESCE(removed_ids, ARRAY[]::UUID[])) removed(user_id);
    DELETE FROM public.chat_participants existing
    WHERE existing.room_id = input_room_id AND existing.user_id <> actor
      AND existing.user_id = ANY(COALESCE(removed_ids, ARRAY[]::UUID[]));

    INSERT INTO public.chat_participants (room_id, user_id, role)
    SELECT input_room_id, added.user_id, 'member'
    FROM unnest(COALESCE(added_ids, ARRAY[]::UUID[])) added(user_id)
    ON CONFLICT ON CONSTRAINT chat_participants_pkey DO NOTHING;
    INSERT INTO public.chat_participant_audit (room_id, school_id, user_id, action, acted_by)
    SELECT input_room_id, room_record.school_id, added.user_id, 'added', actor
    FROM unnest(COALESCE(added_ids, ARRAY[]::UUID[])) added(user_id);

    PERFORM public.enqueue_workflow_notification(
        room_record.school_id, 'Added to ' || room_record.name,
        'A school director added you to a group chat.', 'chat_invitation', 'chat_room', input_room_id,
        added_ids, 'chat:participants:added:' || input_room_id::TEXT || ':' || md5(COALESCE(array_to_string(added_ids, ','), 'none')),
        'routine', jsonb_build_object('type', 'chat_room', 'id', input_room_id), actor
    );
    PERFORM public.enqueue_workflow_notification(
        room_record.school_id, 'Removed from ' || room_record.name,
        'A school director removed you from a group chat.', 'chat_removal', 'chat_room', input_room_id,
        removed_ids, 'chat:participants:removed:' || input_room_id::TEXT || ':' || md5(COALESCE(array_to_string(removed_ids, ','), 'none')),
        'routine', jsonb_build_object('type', 'chat_room', 'id', input_room_id), actor
    );
    RETURN QUERY SELECT participant.room_id, participant.user_id
    FROM public.chat_participants participant WHERE participant.room_id = input_room_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_director_chat_room(input_room_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE room_record public.chat_rooms%ROWTYPE;
BEGIN
    SELECT * INTO room_record FROM public.chat_rooms WHERE id = input_room_id AND deleted_at IS NULL FOR UPDATE;
    IF NOT FOUND OR NOT public.has_school_role(room_record.school_id, auth.uid(), ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can delete this room';
    END IF;
    UPDATE public.chat_rooms SET deleted_at = NOW(), deleted_by = auth.uid(), archived_at = COALESCE(archived_at, NOW()), updated_at = NOW()
    WHERE id = input_room_id;
    INSERT INTO public.chat_participant_audit (room_id, school_id, user_id, action, acted_by)
    SELECT input_room_id, room_record.school_id, participant.user_id, 'removed', auth.uid()
    FROM public.chat_participants participant WHERE participant.room_id = input_room_id;
    DELETE FROM public.chat_participants WHERE room_id = input_room_id;
    INSERT INTO public.workflow_audit_events (school_id, actor_id, event_type, source_type, source_id)
    VALUES (room_record.school_id, auth.uid(), 'soft_deleted', 'chat_room', input_room_id);
END;
$$;

CREATE OR REPLACE FUNCTION public.notify_chat_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE room_record public.chat_rooms%ROWTYPE;
BEGIN
    SELECT * INTO room_record FROM public.chat_rooms WHERE id = NEW.room_id;
    IF room_record.deleted_at IS NULL THEN
        PERFORM public.enqueue_workflow_notification(
            room_record.school_id, room_record.name, COALESCE(NULLIF(NEW.text, ''), 'New attachment'),
            'chat_message', 'chat_room', room_record.id,
            ARRAY(
                SELECT participant.user_id FROM public.chat_participants participant
                WHERE participant.room_id = room_record.id AND participant.user_id <> NEW.sender_id
                  AND participant.notifications_enabled = TRUE
            ), 'chat:message:' || NEW.id::TEXT,
            'routine', jsonb_build_object('type', 'chat_room', 'id', room_record.id, 'message_id', NEW.id), NEW.sender_id
        );
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS notify_chat_message_trigger ON public.messages;
CREATE TRIGGER notify_chat_message_trigger
    AFTER INSERT ON public.messages FOR EACH ROW EXECUTE FUNCTION public.notify_chat_message();

CREATE OR REPLACE FUNCTION public.guard_chat_participant_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF NOT public.can_manage_chat_room(OLD.room_id, auth.uid()) AND (
        NEW.room_id <> OLD.room_id OR NEW.user_id <> OLD.user_id OR NEW.role <> OLD.role
    ) THEN
        RAISE EXCEPTION 'Members can only change their room notification setting';
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS guard_chat_participant_update_trigger ON public.chat_participants;
CREATE TRIGGER guard_chat_participant_update_trigger
    BEFORE UPDATE ON public.chat_participants FOR EACH ROW EXECUTE FUNCTION public.guard_chat_participant_update();

DROP POLICY IF EXISTS "Authenticated users can view profiles" ON public.profiles;
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
              AND theirs.role IN ('parent', 'teacher', 'school_director')
        )
    );

DROP POLICY IF EXISTS "Users can view rooms they are in" ON public.chat_rooms;
DROP POLICY IF EXISTS "Authenticated users can create rooms" ON public.chat_rooms;
DROP POLICY IF EXISTS "Room members can update rooms" ON public.chat_rooms;
DROP POLICY IF EXISTS "Room owners can delete rooms" ON public.chat_rooms;
CREATE POLICY "Participants can view active managed rooms"
    ON public.chat_rooms FOR SELECT
    USING (
        deleted_at IS NULL AND (
            public.is_chat_room_member(id, auth.uid())
            OR public.has_school_role(school_id, auth.uid(), ARRAY['school_director'])
        )
    );

DROP POLICY IF EXISTS "Users can view participants in their rooms" ON public.chat_participants;
DROP POLICY IF EXISTS "Room members can add participants" ON public.chat_participants;
DROP POLICY IF EXISTS "Users and owners can update participants" ON public.chat_participants;
DROP POLICY IF EXISTS "Users and owners can remove participants" ON public.chat_participants;
CREATE POLICY "Participants can view managed room membership"
    ON public.chat_participants FOR SELECT
    USING (public.is_chat_room_member(room_id, auth.uid()) OR public.can_manage_chat_room(room_id, auth.uid()));
CREATE POLICY "Participants can update their own mute setting"
    ON public.chat_participants FOR UPDATE
    USING (user_id = auth.uid() AND public.is_chat_room_member(room_id, auth.uid()))
    WITH CHECK (user_id = auth.uid() AND public.is_chat_room_member(room_id, auth.uid()));

DROP POLICY IF EXISTS "Users can view messages in their rooms" ON public.messages;
DROP POLICY IF EXISTS "Users can insert messages in their rooms" ON public.messages;
DROP POLICY IF EXISTS "Users can update their own messages" ON public.messages;
DROP POLICY IF EXISTS "Users can delete their own messages" ON public.messages;
CREATE POLICY "Managed room participants can view messages"
    ON public.messages FOR SELECT
    USING (
        (public.is_chat_room_member(room_id, auth.uid())
         OR public.has_school_role(school_id, auth.uid(), ARRAY['school_director']))
        AND EXISTS (SELECT 1 FROM public.chat_rooms room WHERE room.id = messages.room_id AND room.deleted_at IS NULL)
    );
CREATE POLICY "Managed room participants can send messages"
    ON public.messages FOR INSERT
    WITH CHECK (
        sender_id = auth.uid() AND public.is_chat_room_member(room_id, auth.uid())
        AND EXISTS (
            SELECT 1 FROM public.chat_rooms room
            WHERE room.id = messages.room_id AND room.deleted_at IS NULL AND room.archived_at IS NULL
        )
    );
CREATE POLICY "Senders can edit managed room messages"
    ON public.messages FOR UPDATE
    USING (sender_id = auth.uid() AND public.is_chat_room_member(room_id, auth.uid()))
    WITH CHECK (sender_id = auth.uid() AND public.is_chat_room_member(room_id, auth.uid()));
CREATE POLICY "Senders can delete managed room messages"
    ON public.messages FOR DELETE
    USING (sender_id = auth.uid() AND public.is_chat_room_member(room_id, auth.uid()));

CREATE POLICY "Users can view relevant connection requests"
    ON public.child_connection_requests FOR SELECT
    USING (
        requested_by = auth.uid()
        OR public.has_school_role(school_id, auth.uid(), ARRAY['school_director'])
        OR public.is_hq_director(auth.uid())
    );
DROP POLICY IF EXISTS "Directors can manage child guardians" ON public.child_guardians;
DROP POLICY IF EXISTS "Users can upload child documents" ON public.child_documents;
DROP POLICY IF EXISTS "Directors can review child documents" ON public.child_documents;
DROP POLICY IF EXISTS "Users can manage medication instructions" ON public.medication_instructions;
DROP POLICY IF EXISTS "Staff can update medication tasks" ON public.medication_tasks;
DROP POLICY IF EXISTS "Staff can create medication acknowledgements" ON public.medication_acknowledgements;
CREATE POLICY "Users can view relevant child profile changes"
    ON public.child_profile_change_requests FOR SELECT
    USING (
        requested_by = auth.uid() OR public.can_access_child(child_id, auth.uid())
    );
CREATE POLICY "Authorized adults can view attendance sessions"
    ON public.attendance_sessions FOR SELECT
    USING (public.can_access_child(child_id, auth.uid()));
CREATE POLICY "Directors can view attendance corrections"
    ON public.attendance_corrections FOR SELECT
    USING (
        public.has_school_role(school_id, auth.uid(), ARRAY['school_director'])
        OR public.is_hq_director(auth.uid())
    );
CREATE POLICY "Authorized adults can view care events"
    ON public.child_care_events FOR SELECT
    USING (
        public.can_staff_access_child(child_id, auth.uid(), ARRAY['teacher', 'school_director'])
        OR (visibility = 'parent' AND public.is_child_guardian(child_id, auth.uid()))
    );
CREATE POLICY "Families and staff can view family requests"
    ON public.family_requests FOR SELECT
    USING (
        requested_by = auth.uid()
        OR public.can_staff_access_child(child_id, auth.uid(), ARRAY['teacher', 'school_director'])
        OR public.is_hq_director(auth.uid())
    );
CREATE POLICY "Users manage their notification preferences"
    ON public.notification_preferences FOR ALL
    USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());
CREATE POLICY "Directors can view workflow audit"
    ON public.workflow_audit_events FOR SELECT
    USING (
        public.has_school_role(school_id, auth.uid(), ARRAY['school_director'])
        OR public.is_hq_director(auth.uid())
    );
CREATE POLICY "Directors can view chat participant audit"
    ON public.chat_participant_audit FOR SELECT
    USING (
        public.has_school_role(school_id, auth.uid(), ARRAY['school_director'])
        OR public.is_hq_director(auth.uid())
    );

-- Notifications are created only inside trusted workflow functions.
DROP POLICY IF EXISTS "School staff can create notifications" ON public.notifications;
DROP POLICY IF EXISTS "Users can create notification recipients" ON public.notification_recipients;

DROP FUNCTION IF EXISTS public.fetch_my_notifications(INTEGER);
CREATE FUNCTION public.fetch_my_notifications(input_limit INTEGER DEFAULT 100)
RETURNS TABLE (
    id UUID,
    school_id UUID,
    school_name TEXT,
    title TEXT,
    body TEXT,
    category TEXT,
    source_type TEXT,
    source_id UUID,
    created_by UUID,
    created_at TIMESTAMPTZ,
    read_at TIMESTAMPTZ,
    priority TEXT,
    route JSONB,
    delivery_state TEXT,
    attempt_count INTEGER,
    last_error TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT notification.id, notification.school_id, school.name,
        notification.title, notification.body, notification.category,
        notification.source_type, notification.source_id, notification.created_by,
        notification.created_at, recipient.read_at, notification.priority,
        notification.route, recipient.delivery_state, recipient.attempt_count, recipient.last_error
    FROM public.notification_recipients recipient
    JOIN public.notifications notification ON notification.id = recipient.notification_id
    JOIN public.schools school ON school.id = notification.school_id
    WHERE recipient.user_id = auth.uid()
      AND recipient.delivery_state NOT IN ('dismissed', 'expired')
    ORDER BY notification.created_at DESC
    LIMIT LEAST(GREATEST(COALESCE(input_limit, 100), 1), 200);
$$;

CREATE OR REPLACE FUNCTION public.mark_notification_read(input_notification_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.notification_recipients
    SET read_at = COALESCE(read_at, NOW()), opened_at = COALESCE(opened_at, NOW()),
        delivery_state = CASE WHEN delivery_state IN ('acknowledged', 'failed') THEN delivery_state ELSE 'opened' END
    WHERE notification_id = input_notification_id AND user_id = auth.uid()
      AND delivery_state NOT IN ('dismissed', 'expired');
    IF NOT FOUND THEN RAISE EXCEPTION 'Notification was not found for this user'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.acknowledge_notification(input_notification_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.notification_recipients
    SET acknowledged_at = COALESCE(acknowledged_at, NOW()), opened_at = COALESCE(opened_at, NOW()),
        read_at = COALESCE(read_at, NOW()), delivery_state = 'acknowledged'
    WHERE notification_id = input_notification_id AND user_id = auth.uid();
    IF NOT FOUND THEN RAISE EXCEPTION 'Notification was not found for this user'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.dismiss_notification(input_notification_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    UPDATE public.notification_recipients
    SET dismissed_at = COALESCE(dismissed_at, NOW()), delivery_state = 'dismissed'
    WHERE notification_id = input_notification_id AND user_id = auth.uid();
    IF NOT FOUND THEN RAISE EXCEPTION 'Notification was not found for this user'; END IF;
END;
$$;

CREATE OR REPLACE FUNCTION public.clear_my_notifications()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE changed_count INTEGER;
BEGIN
    UPDATE public.notification_recipients
    SET dismissed_at = COALESCE(dismissed_at, NOW()), delivery_state = 'dismissed'
    WHERE user_id = auth.uid() AND delivery_state NOT IN ('dismissed', 'expired');
    GET DIAGNOSTICS changed_count = ROW_COUNT;
    RETURN changed_count;
END;
$$;

DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notification_recipients;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.attendance_sessions;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;
DO $$ BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.child_care_events;
EXCEPTION WHEN duplicate_object THEN NULL; END $$;

REVOKE ALL ON FUNCTION public.fetch_school_directory(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.submit_child_connection_request(UUID, TEXT, TEXT, DATE, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.review_child_connection_request(UUID, TEXT, UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_child_guardian_invite(UUID, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.revoke_child_guardian(UUID, UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.submit_assignment_with_payload(UUID, JSONB, TEXT, JSONB, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fetch_assignment_child_binding(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.save_onboarding_template_requirement_v2(UUID, UUID, TEXT, TEXT, TEXT, INTEGER, JSONB, BOOLEAN, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_school_attendance(UUID, TEXT, TIMESTAMPTZ, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.correct_attendance_session(UUID, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_child_care_event(UUID, TEXT, TIMESTAMPTZ, JSONB, TEXT, UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.submit_family_request(UUID, TEXT, JSONB, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_family_request_status(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_school_announcement(UUID, TEXT, TEXT, UUID[], TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_transactional_notification(UUID, TEXT, TEXT, TEXT, TEXT, UUID, UUID[], TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.create_director_chat_room(UUID, TEXT, TEXT, TEXT, UUID[], TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_director_chat_room(UUID, TEXT, TEXT, TEXT, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_director_chat_room_image_path(UUID, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_director_chat_participants(UUID, UUID[]) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.delete_director_chat_room(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.acknowledge_notification(UUID) FROM PUBLIC;

GRANT EXECUTE ON FUNCTION public.fetch_school_directory(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_child_connection_request(UUID, TEXT, TEXT, DATE, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_child_connection_request(UUID, TEXT, UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_child_guardian_invite(UUID, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.revoke_child_guardian(UUID, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_assignment_with_payload(UUID, JSONB, TEXT, JSONB, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_assignment_child_binding(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.save_onboarding_template_requirement_v2(UUID, UUID, TEXT, TEXT, TEXT, INTEGER, JSONB, BOOLEAN, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_school_attendance(UUID, TEXT, TIMESTAMPTZ, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.correct_attendance_session(UUID, TIMESTAMPTZ, TIMESTAMPTZ, TEXT, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_child_care_event(UUID, TEXT, TIMESTAMPTZ, JSONB, TEXT, UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.submit_family_request(UUID, TEXT, JSONB, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_family_request_status(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_school_announcement(UUID, TEXT, TEXT, UUID[], TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_transactional_notification(UUID, TEXT, TEXT, TEXT, TEXT, UUID, UUID[], TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_director_chat_room(UUID, TEXT, TEXT, TEXT, UUID[], TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_director_chat_room(UUID, TEXT, TEXT, TEXT, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_director_chat_room_image_path(UUID, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_director_chat_participants(UUID, UUID[]) TO authenticated;
GRANT EXECUTE ON FUNCTION public.delete_director_chat_room(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.acknowledge_notification(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260722010000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';

-- Migration: 20260722020000_fix_community_and_chat_visibility.sql

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

-- Migration: 20260722030000_chat_room_self_leave.sql

-- Allow invited teachers and parents to leave director-managed rooms while
-- preserving immediate access revocation and participant audit history.

CREATE OR REPLACE FUNCTION public.leave_managed_chat_room(input_room_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    room_record public.chat_rooms%ROWTYPE;
    actor_role TEXT;
    director_ids UUID[];
    workflow_event_id UUID;
BEGIN
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    SELECT * INTO room_record
    FROM public.chat_rooms
    WHERE id = input_room_id AND deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Chat room was not found';
    END IF;

    SELECT membership.role INTO actor_role
    FROM public.school_memberships membership
    WHERE membership.school_id = room_record.school_id
      AND membership.user_id = actor
      AND membership.active = TRUE
      AND membership.role IN ('parent', 'teacher')
    ORDER BY CASE membership.role WHEN 'teacher' THEN 0 ELSE 1 END
    LIMIT 1;

    IF actor_role IS NULL THEN
        RAISE EXCEPTION 'Only parent and teacher participants can leave a room';
    END IF;

    IF NOT EXISTS (
        SELECT 1 FROM public.chat_participants participant
        WHERE participant.room_id = input_room_id
          AND participant.user_id = actor
    ) THEN
        RAISE EXCEPTION 'You are not a participant in this room';
    END IF;

    INSERT INTO public.chat_participant_audit (
        room_id, school_id, user_id, action, acted_by
    ) VALUES (
        input_room_id, room_record.school_id, actor, 'removed', actor
    );

    DELETE FROM public.chat_participants participant
    WHERE participant.room_id = input_room_id
      AND participant.user_id = actor;

    INSERT INTO public.workflow_audit_events (
        school_id, actor_id, event_type, source_type, source_id,
        metadata
    ) VALUES (
        room_record.school_id, actor, 'participant_left', 'chat_room',
        input_room_id, jsonb_build_object('role', actor_role)
    ) RETURNING id INTO workflow_event_id;

    SELECT array_agg(membership.user_id) INTO director_ids
    FROM public.school_memberships membership
    WHERE membership.school_id = room_record.school_id
      AND membership.active = TRUE
      AND membership.role = 'school_director';

    PERFORM public.enqueue_workflow_notification(
        room_record.school_id,
        'A member left ' || room_record.name,
        'A parent or teacher left this group chat.',
        'chat_participant_left',
        'chat_room',
        input_room_id,
        director_ids,
        'chat:participant:left:' || workflow_event_id::TEXT,
        'routine',
        jsonb_build_object('type', 'chat_room', 'id', input_room_id),
        actor
    );
END;
$$;

REVOKE ALL ON FUNCTION public.leave_managed_chat_room(UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.leave_managed_chat_room(UUID) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ SELECT 20260722030000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';

-- Migration: 20260727000000_chat_first_foundation.sql

-- Chat-first privacy, automatic room lifecycle, and director vacancy rules.

ALTER TABLE public.schools
    ADD COLUMN IF NOT EXISTS family_chat_teacher_scope TEXT NOT NULL DEFAULT 'all_school_teachers';
ALTER TABLE public.schools
    DROP CONSTRAINT IF EXISTS schools_family_chat_teacher_scope_check;
ALTER TABLE public.schools
    ADD CONSTRAINT schools_family_chat_teacher_scope_check
    CHECK (family_chat_teacher_scope IN ('all_school_teachers', 'assigned_teachers'));

ALTER TABLE public.chat_rooms
    ADD COLUMN IF NOT EXISTS subject_child_id UUID REFERENCES public.children(id) ON DELETE SET NULL,
    ADD COLUMN IF NOT EXISTS system_managed BOOLEAN NOT NULL DEFAULT FALSE,
    ADD COLUMN IF NOT EXISTS archive_reason TEXT,
    ADD COLUMN IF NOT EXISTS retention_until TIMESTAMPTZ;
ALTER TABLE public.chat_rooms DROP CONSTRAINT IF EXISTS chat_rooms_room_type_check;
UPDATE public.chat_rooms
SET room_type = 'custom'
WHERE room_type IS NULL OR room_type IN ('public', 'private', 'director_managed');
ALTER TABLE public.chat_rooms
    ALTER COLUMN room_type SET DEFAULT 'custom',
    ALTER COLUMN room_type SET NOT NULL,
    ADD CONSTRAINT chat_rooms_room_type_check
    CHECK (room_type IN ('child_family', 'school_group', 'custom'));

ALTER TABLE public.chat_participants
    ADD COLUMN IF NOT EXISTS membership_source TEXT NOT NULL DEFAULT 'manual';
ALTER TABLE public.chat_participants
    DROP CONSTRAINT IF EXISTS chat_participants_membership_source_check;
ALTER TABLE public.chat_participants
    ADD CONSTRAINT chat_participants_membership_source_check
    CHECK (membership_source IN ('manual', 'guardian', 'teacher', 'director', 'school'));

ALTER TABLE public.chat_participant_audit
    ALTER COLUMN acted_by DROP NOT NULL;

ALTER TABLE public.messages
    ADD COLUMN IF NOT EXISTS entry_kind TEXT NOT NULL DEFAULT 'message',
    ADD COLUMN IF NOT EXISTS structured_source_type TEXT,
    ADD COLUMN IF NOT EXISTS structured_source_id UUID,
    ADD COLUMN IF NOT EXISTS audio_duration_seconds DOUBLE PRECISION;
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_entry_kind_check;
ALTER TABLE public.messages
    ADD CONSTRAINT messages_entry_kind_check
    CHECK (entry_kind IN ('message', 'care_event', 'family_request', 'goal_update'));
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_structured_source_check;
ALTER TABLE public.messages
    ADD CONSTRAINT messages_structured_source_check CHECK (
        (entry_kind = 'message' AND structured_source_type IS NULL AND structured_source_id IS NULL)
        OR
        (entry_kind <> 'message' AND structured_source_type IS NOT NULL AND structured_source_id IS NOT NULL)
    );
ALTER TABLE public.messages DROP CONSTRAINT IF EXISTS messages_audio_duration_check;
ALTER TABLE public.messages
    ADD CONSTRAINT messages_audio_duration_check
    CHECK (audio_duration_seconds IS NULL OR audio_duration_seconds >= 0);

CREATE TABLE IF NOT EXISTS public.chat_message_links (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    message_id UUID NOT NULL REFERENCES public.messages(id) ON DELETE CASCADE,
    room_id UUID NOT NULL REFERENCES public.chat_rooms(id) ON DELETE CASCADE,
    normalized_url TEXT NOT NULL,
    display_url TEXT NOT NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (message_id, normalized_url)
);
ALTER TABLE public.chat_message_links ENABLE ROW LEVEL SECURITY;

CREATE UNIQUE INDEX IF NOT EXISTS idx_chat_rooms_one_active_child_family
    ON public.chat_rooms(school_id, subject_child_id)
    WHERE room_type = 'child_family' AND deleted_at IS NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_chat_rooms_one_school_group
    ON public.chat_rooms(school_id)
    WHERE room_type = 'school_group' AND deleted_at IS NULL;
CREATE INDEX IF NOT EXISTS idx_chat_rooms_subject_child
    ON public.chat_rooms(subject_child_id)
    WHERE subject_child_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_chat_message_links_room_created
    ON public.chat_message_links(room_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_messages_room_attachment_created
    ON public.messages(room_id, attachment_type, created_at DESC)
    WHERE is_deleted = FALSE;
CREATE INDEX IF NOT EXISTS idx_messages_structured_source
    ON public.messages(structured_source_type, structured_source_id)
    WHERE structured_source_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_one_structured_timeline_entry
    ON public.messages(structured_source_type, structured_source_id)
    WHERE structured_source_id IS NOT NULL;

-- Resolve legacy duplicate active directors deterministically before adding the
-- invariant. The newest membership stays active and every automatic vacancy is
-- preserved in the workflow audit trail.
WITH ranked AS (
    SELECT membership.id,
           row_number() OVER (
               PARTITION BY membership.school_id
               ORDER BY membership.joined_at DESC NULLS LAST,
                        membership.created_at DESC NULLS LAST,
                        membership.id DESC
           ) AS position
    FROM public.school_memberships membership
    WHERE membership.active = TRUE
      AND membership.role = 'school_director'
), deactivated AS (
    UPDATE public.school_memberships membership
    SET active = FALSE
    FROM ranked
    WHERE membership.id = ranked.id
      AND ranked.position > 1
    RETURNING membership.id, membership.school_id, membership.user_id
)
INSERT INTO public.workflow_audit_events (
    school_id, actor_id, event_type, source_type, source_id, metadata
)
SELECT school_id, NULL, 'director_membership_deduplicated',
       'school_membership', id, jsonb_build_object('user_id', user_id)
FROM deactivated;

CREATE UNIQUE INDEX IF NOT EXISTS idx_school_memberships_one_active_director
    ON public.school_memberships(school_id)
    WHERE active = TRUE AND role = 'school_director';

WITH ranked AS (
    SELECT invite.id,
           row_number() OVER (
               PARTITION BY invite.school_id
               ORDER BY invite.created_at DESC, invite.id DESC
           ) AS position
    FROM public.role_invites invite
    WHERE invite.role = 'school_director'
      AND invite.status = 'pending'
)
UPDATE public.role_invites invite
SET status = 'revoked', token = NULL, token_hash = NULL
FROM ranked
WHERE invite.id = ranked.id
  AND ranked.position > 1;

CREATE UNIQUE INDEX IF NOT EXISTS idx_role_invites_one_pending_director
    ON public.role_invites(school_id)
    WHERE role = 'school_director' AND status = 'pending';

CREATE OR REPLACE FUNCTION public.guard_school_director_invite()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF NEW.role = 'school_director' AND NEW.status = 'pending' THEN
        IF EXISTS (
            SELECT 1
            FROM public.school_memberships membership
            WHERE membership.school_id = NEW.school_id
              AND membership.active = TRUE
              AND membership.role = 'school_director'
        ) THEN
            RAISE EXCEPTION 'Vacate the current school director before sending a replacement invitation';
        END IF;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS guard_school_director_invite_trigger ON public.role_invites;
CREATE TRIGGER guard_school_director_invite_trigger
    BEFORE INSERT OR UPDATE OF school_id, role, status
    ON public.role_invites
    FOR EACH ROW EXECUTE FUNCTION public.guard_school_director_invite();

CREATE OR REPLACE FUNCTION public.cancel_school_director_invite(input_invite_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    invite_record public.role_invites%ROWTYPE;
BEGIN
    IF actor IS NULL OR NOT public.is_hq_director(actor) THEN
        RAISE EXCEPTION 'Only a headquarter director can cancel a director invitation';
    END IF;

    SELECT * INTO invite_record
    FROM public.role_invites
    WHERE id = input_invite_id
      AND role = 'school_director'
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Director invitation not found';
    END IF;
    IF invite_record.status <> 'pending' THEN
        RAISE EXCEPTION 'Only a pending director invitation can be cancelled';
    END IF;

    UPDATE public.role_invites
    SET status = 'revoked', token = NULL, token_hash = NULL
    WHERE id = input_invite_id;

    INSERT INTO public.workflow_audit_events (
        school_id, actor_id, event_type, source_type, source_id, metadata
    ) VALUES (
        invite_record.school_id, actor, 'director_invite_cancelled',
        'role_invite', invite_record.id,
        jsonb_build_object('email', invite_record.email)
    );
END;
$$;

-- HQ is an administrative role, not an implicit participant in private child
-- records. Keep staff access school-scoped and explicit.
CREATE OR REPLACE FUNCTION public.can_staff_access_child(
    child_uuid UUID,
    user_uuid UUID,
    allowed_roles TEXT[]
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.children child
        JOIN public.school_memberships membership
          ON membership.school_id = child.school_id
         AND membership.user_id = user_uuid
         AND membership.active = TRUE
         AND membership.access_state = 'full'
        WHERE child.id = child_uuid
          AND membership.role = ANY(allowed_roles)
          AND membership.role IN ('teacher', 'school_director')
    );
$$;

CREATE OR REPLACE FUNCTION public.is_chat_room_member(room_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.chat_participants participant
        JOIN public.chat_rooms room ON room.id = participant.room_id
        WHERE participant.room_id = room_uuid
          AND participant.user_id = user_uuid
          AND room.deleted_at IS NULL
          AND (
              public.has_direct_school_role(
                  room.school_id,
                  user_uuid,
                  ARRAY['parent', 'teacher', 'school_director']
              )
              OR (
                  room.room_type = 'child_family'
                  AND room.archived_at IS NOT NULL
                  AND room.retention_until > NOW()
                  AND participant.membership_source = 'guardian'
              )
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.sync_child_family_room(input_child_id UUID)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    child_record public.children%ROWTYPE;
    room_record public.chat_rooms%ROWTYPE;
    expected_ids UUID[] := ARRAY[]::UUID[];
    archive_ids UUID[] := ARRAY[]::UUID[];
    has_full_guardian BOOLEAN := FALSE;
BEGIN
    PERFORM set_config('firefly.system_room_sync', 'on', TRUE);
    PERFORM pg_advisory_xact_lock(hashtextextended('child-family-room:' || input_child_id::TEXT, 0));

    SELECT * INTO child_record
    FROM public.children
    WHERE id = input_child_id;
    IF NOT FOUND THEN
        PERFORM set_config('firefly.system_room_sync', 'off', TRUE);
        RETURN NULL;
    END IF;

    SELECT EXISTS (
        SELECT 1
        FROM public.child_guardians guardian
        JOIN public.school_memberships membership
          ON membership.school_id = child_record.school_id
         AND membership.user_id = guardian.guardian_id
         AND membership.active = TRUE
         AND membership.access_state = 'full'
         AND membership.role = 'parent'
        WHERE guardian.child_id = child_record.id
          AND guardian.verification_status = 'verified'
          AND guardian.ended_at IS NULL
    ) INTO has_full_guardian;

    SELECT * INTO room_record
    FROM public.chat_rooms room
    WHERE room.school_id = child_record.school_id
      AND room.subject_child_id = child_record.id
      AND room.room_type = 'child_family'
      AND room.deleted_at IS NULL
    FOR UPDATE;

    IF child_record.active = TRUE AND has_full_guardian THEN
        IF NOT FOUND THEN
            INSERT INTO public.chat_rooms (
                name, description, invite_hash, school_id, room_type,
                subject_child_id, system_managed, created_by,
                created_at, updated_at
            ) VALUES (
                btrim(child_record.first_name || ' ' || child_record.last_name) || ' • Family Team',
                'Private updates, care, and family requests for ' || btrim(child_record.first_name || ' ' || child_record.last_name),
                NULL, child_record.school_id, 'child_family',
                child_record.id, TRUE, NULL, NOW(), NOW()
            ) RETURNING * INTO room_record;
        ELSE
            UPDATE public.chat_rooms
            SET name = btrim(child_record.first_name || ' ' || child_record.last_name) || ' • Family Team',
                description = 'Private updates, care, and family requests for ' || btrim(child_record.first_name || ' ' || child_record.last_name),
                system_managed = TRUE,
                archived_at = NULL,
                archive_reason = NULL,
                retention_until = NULL,
                updated_at = NOW()
            WHERE id = room_record.id
            RETURNING * INTO room_record;
        END IF;

        WITH expected AS (
            SELECT guardian.guardian_id AS user_id, 'member'::TEXT AS participant_role,
                   'guardian'::TEXT AS membership_source, 1 AS priority
            FROM public.child_guardians guardian
            JOIN public.school_memberships membership
              ON membership.school_id = child_record.school_id
             AND membership.user_id = guardian.guardian_id
             AND membership.active = TRUE
             AND membership.access_state = 'full'
             AND membership.role = 'parent'
            WHERE guardian.child_id = child_record.id
              AND guardian.verification_status = 'verified'
              AND guardian.ended_at IS NULL
            UNION ALL
            SELECT membership.user_id, 'owner', 'director', 2
            FROM public.school_memberships membership
            WHERE membership.school_id = child_record.school_id
              AND membership.active = TRUE
              AND membership.access_state = 'full'
              AND membership.role = 'school_director'
            UNION ALL
            SELECT membership.user_id, 'member', 'teacher', 3
            FROM public.school_memberships membership
            WHERE membership.school_id = child_record.school_id
              AND membership.active = TRUE
              AND membership.access_state = 'full'
              AND membership.role = 'teacher'
              AND (
                  (SELECT school.family_chat_teacher_scope FROM public.schools school WHERE school.id = child_record.school_id) = 'all_school_teachers'
                  OR EXISTS (
                      SELECT 1
                      FROM public.classroom_children classroom_child
                      JOIN public.classroom_teachers classroom_teacher
                        ON classroom_teacher.classroom_id = classroom_child.classroom_id
                      WHERE classroom_child.child_id = child_record.id
                        AND classroom_teacher.teacher_id = membership.user_id
                  )
              )
        ), deduplicated AS (
            SELECT DISTINCT ON (user_id) user_id, participant_role, membership_source
            FROM expected
            ORDER BY user_id, priority
        )
        SELECT COALESCE(array_agg(user_id), ARRAY[]::UUID[])
        INTO expected_ids
        FROM deduplicated;

        INSERT INTO public.chat_participant_audit (
            room_id, school_id, user_id, action, acted_by
        )
        SELECT room_record.id, child_record.school_id, expected_id, 'added', NULL
        FROM unnest(expected_ids) expected_id
        WHERE NOT EXISTS (
            SELECT 1 FROM public.chat_participants participant
            WHERE participant.room_id = room_record.id
              AND participant.user_id = expected_id
        );

        WITH expected AS (
            SELECT guardian.guardian_id AS user_id, 'member'::TEXT AS participant_role,
                   'guardian'::TEXT AS membership_source, 1 AS priority
            FROM public.child_guardians guardian
            JOIN public.school_memberships membership
              ON membership.school_id = child_record.school_id
             AND membership.user_id = guardian.guardian_id
             AND membership.active = TRUE
             AND membership.access_state = 'full'
             AND membership.role = 'parent'
            WHERE guardian.child_id = child_record.id
              AND guardian.verification_status = 'verified'
              AND guardian.ended_at IS NULL
            UNION ALL
            SELECT membership.user_id, 'owner', 'director', 2
            FROM public.school_memberships membership
            WHERE membership.school_id = child_record.school_id
              AND membership.active = TRUE
              AND membership.access_state = 'full'
              AND membership.role = 'school_director'
            UNION ALL
            SELECT membership.user_id, 'member', 'teacher', 3
            FROM public.school_memberships membership
            WHERE membership.school_id = child_record.school_id
              AND membership.active = TRUE
              AND membership.access_state = 'full'
              AND membership.role = 'teacher'
              AND (
                  (SELECT school.family_chat_teacher_scope FROM public.schools school WHERE school.id = child_record.school_id) = 'all_school_teachers'
                  OR EXISTS (
                      SELECT 1
                      FROM public.classroom_children classroom_child
                      JOIN public.classroom_teachers classroom_teacher
                        ON classroom_teacher.classroom_id = classroom_child.classroom_id
                      WHERE classroom_child.child_id = child_record.id
                        AND classroom_teacher.teacher_id = membership.user_id
                  )
              )
        ), deduplicated AS (
            SELECT DISTINCT ON (user_id) user_id, participant_role, membership_source
            FROM expected
            ORDER BY user_id, priority
        )
        INSERT INTO public.chat_participants (
            room_id, user_id, role, membership_source
        )
        SELECT room_record.id, user_id, participant_role, membership_source
        FROM deduplicated
        ON CONFLICT (room_id, user_id) DO UPDATE
        SET role = EXCLUDED.role,
            membership_source = EXCLUDED.membership_source;

        INSERT INTO public.chat_participant_audit (
            room_id, school_id, user_id, action, acted_by
        )
        SELECT room_record.id, child_record.school_id, participant.user_id, 'removed', NULL
        FROM public.chat_participants participant
        WHERE participant.room_id = room_record.id
          AND NOT (participant.user_id = ANY(expected_ids));

        DELETE FROM public.chat_participants participant
        WHERE participant.room_id = room_record.id
          AND NOT (participant.user_id = ANY(expected_ids));
    ELSIF FOUND THEN
        UPDATE public.chat_rooms
        SET archived_at = COALESCE(archived_at, NOW()),
            archive_reason = CASE
                WHEN child_record.active = FALSE THEN 'child_left_school'
                ELSE 'no_full_access_guardian'
            END,
            retention_until = CASE
                WHEN child_record.active = FALSE THEN COALESCE(retention_until, NOW() + INTERVAL '90 days')
                ELSE NULL
            END,
            updated_at = NOW()
        WHERE id = room_record.id
        RETURNING * INTO room_record;

        SELECT COALESCE(array_agg(allowed.user_id), ARRAY[]::UUID[])
        INTO archive_ids
        FROM (
            SELECT guardian.guardian_id AS user_id
            FROM public.child_guardians guardian
            WHERE guardian.child_id = child_record.id
              AND guardian.verification_status = 'verified'
              AND guardian.ended_at IS NULL
            UNION
            SELECT membership.user_id
            FROM public.school_memberships membership
            WHERE membership.school_id = child_record.school_id
              AND membership.active = TRUE
              AND membership.access_state = 'full'
              AND membership.role = 'school_director'
        ) allowed;

        INSERT INTO public.chat_participant_audit (
            room_id, school_id, user_id, action, acted_by
        )
        SELECT room_record.id, child_record.school_id, participant.user_id, 'removed', NULL
        FROM public.chat_participants participant
        WHERE participant.room_id = room_record.id
          AND NOT (participant.user_id = ANY(archive_ids));

        DELETE FROM public.chat_participants participant
        WHERE participant.room_id = room_record.id
          AND NOT (participant.user_id = ANY(archive_ids));
    END IF;

    PERFORM set_config('firefly.system_room_sync', 'off', TRUE);
    RETURN room_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_school_communication_rooms(input_school_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    school_record public.schools%ROWTYPE;
    room_record public.chat_rooms%ROWTYPE;
    expected_ids UUID[] := ARRAY[]::UUID[];
    child_id UUID;
BEGIN
    PERFORM set_config('firefly.system_room_sync', 'on', TRUE);
    PERFORM pg_advisory_xact_lock(hashtextextended('school-community-room:' || input_school_id::TEXT, 0));

    SELECT * INTO school_record
    FROM public.schools
    WHERE id = input_school_id;
    IF NOT FOUND THEN
        PERFORM set_config('firefly.system_room_sync', 'off', TRUE);
        RETURN;
    END IF;

    SELECT * INTO room_record
    FROM public.chat_rooms room
    WHERE room.school_id = input_school_id
      AND room.room_type = 'school_group'
      AND room.deleted_at IS NULL
    FOR UPDATE;

    IF NOT FOUND THEN
        INSERT INTO public.chat_rooms (
            name, description, invite_hash, school_id, room_type,
            system_managed, created_by, created_at, updated_at
        ) VALUES (
            school_record.name || ' • School Community',
            'School-wide announcements and conversation',
            NULL, school_record.id, 'school_group', TRUE, NULL, NOW(), NOW()
        ) RETURNING * INTO room_record;
    ELSE
        UPDATE public.chat_rooms
        SET name = school_record.name || ' • School Community',
            description = 'School-wide announcements and conversation',
            system_managed = TRUE,
            archived_at = NULL,
            archive_reason = NULL,
            retention_until = NULL,
            updated_at = NOW()
        WHERE id = room_record.id
        RETURNING * INTO room_record;
    END IF;

    SELECT COALESCE(array_agg(membership.user_id), ARRAY[]::UUID[])
    INTO expected_ids
    FROM public.school_memberships membership
    WHERE membership.school_id = input_school_id
      AND membership.active = TRUE
      AND membership.access_state = 'full'
      AND membership.role IN ('parent', 'teacher', 'school_director');

    INSERT INTO public.chat_participant_audit (
        room_id, school_id, user_id, action, acted_by
    )
    SELECT room_record.id, school_record.id, expected_id, 'added', NULL
    FROM unnest(expected_ids) expected_id
    WHERE NOT EXISTS (
        SELECT 1 FROM public.chat_participants participant
        WHERE participant.room_id = room_record.id
          AND participant.user_id = expected_id
    );

    INSERT INTO public.chat_participants (
        room_id, user_id, role, membership_source
    )
    SELECT room_record.id,
           membership.user_id,
           CASE WHEN membership.role = 'school_director' THEN 'owner' ELSE 'member' END,
           CASE WHEN membership.role = 'school_director' THEN 'director' ELSE 'school' END
    FROM public.school_memberships membership
    WHERE membership.school_id = input_school_id
      AND membership.active = TRUE
      AND membership.access_state = 'full'
      AND membership.role IN ('parent', 'teacher', 'school_director')
    ON CONFLICT (room_id, user_id) DO UPDATE
    SET role = EXCLUDED.role,
        membership_source = EXCLUDED.membership_source;

    INSERT INTO public.chat_participant_audit (
        room_id, school_id, user_id, action, acted_by
    )
    SELECT room_record.id, school_record.id, participant.user_id, 'removed', NULL
    FROM public.chat_participants participant
    WHERE participant.room_id = room_record.id
      AND NOT (participant.user_id = ANY(expected_ids));

    DELETE FROM public.chat_participants participant
    WHERE participant.room_id = room_record.id
      AND NOT (participant.user_id = ANY(expected_ids));

    FOR child_id IN
        SELECT child.id FROM public.children child WHERE child.school_id = input_school_id
    LOOP
        PERFORM public.sync_child_family_room(child_id);
    END LOOP;
    PERFORM set_config('firefly.system_room_sync', 'off', TRUE);
END;
$$;

CREATE OR REPLACE FUNCTION public.sync_chat_rooms_for_membership_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM public.sync_school_communication_rooms(OLD.school_id);
    ELSE
        PERFORM public.sync_school_communication_rooms(NEW.school_id);
        IF TG_OP = 'UPDATE' AND OLD.school_id IS DISTINCT FROM NEW.school_id THEN
            PERFORM public.sync_school_communication_rooms(OLD.school_id);
        END IF;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS sync_chat_rooms_for_membership_trigger ON public.school_memberships;
CREATE TRIGGER sync_chat_rooms_for_membership_trigger
    AFTER INSERT OR UPDATE OF school_id, role, active, access_state OR DELETE
    ON public.school_memberships
    FOR EACH ROW EXECUTE FUNCTION public.sync_chat_rooms_for_membership_change();

CREATE OR REPLACE FUNCTION public.sync_chat_room_for_child_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP <> 'DELETE' THEN
        PERFORM public.sync_child_family_room(NEW.id);
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS sync_chat_room_for_child_trigger ON public.children;
CREATE TRIGGER sync_chat_room_for_child_trigger
    AFTER INSERT OR UPDATE OF school_id, first_name, last_name, active
    ON public.children
    FOR EACH ROW EXECUTE FUNCTION public.sync_chat_room_for_child_change();

CREATE OR REPLACE FUNCTION public.sync_chat_room_for_guardian_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    IF TG_OP = 'DELETE' THEN
        PERFORM public.sync_child_family_room(OLD.child_id);
    ELSE
        PERFORM public.sync_child_family_room(NEW.child_id);
        IF TG_OP = 'UPDATE' AND OLD.child_id IS DISTINCT FROM NEW.child_id THEN
            PERFORM public.sync_child_family_room(OLD.child_id);
        END IF;
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS sync_chat_room_for_guardian_trigger ON public.child_guardians;
CREATE TRIGGER sync_chat_room_for_guardian_trigger
    AFTER INSERT OR UPDATE OF child_id, guardian_id, verification_status, ended_at OR DELETE
    ON public.child_guardians
    FOR EACH ROW EXECUTE FUNCTION public.sync_chat_room_for_guardian_change();

CREATE OR REPLACE FUNCTION public.sync_chat_rooms_for_school_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
    PERFORM public.sync_school_communication_rooms(NEW.id);
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS sync_chat_rooms_for_school_trigger ON public.schools;
CREATE TRIGGER sync_chat_rooms_for_school_trigger
    AFTER INSERT OR UPDATE OF name, family_chat_teacher_scope
    ON public.schools
    FOR EACH ROW EXECUTE FUNCTION public.sync_chat_rooms_for_school_change();

CREATE OR REPLACE FUNCTION public.sync_chat_rooms_for_classroom_change()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    changed_classroom_id UUID := COALESCE(NEW.classroom_id, OLD.classroom_id);
    child_id UUID;
BEGIN
    FOR child_id IN
        SELECT classroom_child.child_id
        FROM public.classroom_children classroom_child
        WHERE classroom_child.classroom_id = changed_classroom_id
    LOOP
        PERFORM public.sync_child_family_room(child_id);
    END LOOP;
    IF TG_TABLE_NAME = 'classroom_children' THEN
        PERFORM public.sync_child_family_room(COALESCE(NEW.child_id, OLD.child_id));
    END IF;
    RETURN COALESCE(NEW, OLD);
END;
$$;

DROP TRIGGER IF EXISTS sync_chat_rooms_for_classroom_children_trigger ON public.classroom_children;
CREATE TRIGGER sync_chat_rooms_for_classroom_children_trigger
    AFTER INSERT OR UPDATE OR DELETE ON public.classroom_children
    FOR EACH ROW EXECUTE FUNCTION public.sync_chat_rooms_for_classroom_change();
DROP TRIGGER IF EXISTS sync_chat_rooms_for_classroom_teachers_trigger ON public.classroom_teachers;
CREATE TRIGGER sync_chat_rooms_for_classroom_teachers_trigger
    AFTER INSERT OR UPDATE OR DELETE ON public.classroom_teachers
    FOR EACH ROW EXECUTE FUNCTION public.sync_chat_rooms_for_classroom_change();

-- System rooms are server-owned. Custom rooms retain director editing and
-- participant self-leave behavior.
CREATE OR REPLACE FUNCTION public.guard_chat_participant_update()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    room_is_system_managed BOOLEAN;
BEGIN
    SELECT system_managed INTO room_is_system_managed
    FROM public.chat_rooms
    WHERE id = OLD.room_id;

    IF room_is_system_managed
       AND current_setting('firefly.system_room_sync', TRUE) IS DISTINCT FROM 'on'
       AND (
        NEW.room_id <> OLD.room_id
        OR NEW.user_id <> OLD.user_id
        OR NEW.role <> OLD.role
        OR NEW.membership_source <> OLD.membership_source
       ) THEN
        RAISE EXCEPTION 'Membership in this room is managed by the school lifecycle';
    END IF;

    IF NOT room_is_system_managed
       AND NOT public.can_manage_chat_room(OLD.room_id, auth.uid())
       AND (
           NEW.room_id <> OLD.room_id
           OR NEW.user_id <> OLD.user_id
           OR NEW.role <> OLD.role
           OR NEW.membership_source <> OLD.membership_source
       ) THEN
        RAISE EXCEPTION 'Members can only change their room notification setting';
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.leave_managed_chat_room(input_room_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    room_record public.chat_rooms%ROWTYPE;
    actor_role TEXT;
    director_ids UUID[];
    workflow_event_id UUID;
BEGIN
    IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    SELECT * INTO room_record
    FROM public.chat_rooms
    WHERE id = input_room_id AND deleted_at IS NULL
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Chat room was not found'; END IF;
    IF room_record.system_managed THEN
        RAISE EXCEPTION 'This room is created automatically and cannot be left manually';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.chat_participants
        WHERE room_id = input_room_id AND user_id = actor
    ) THEN RAISE EXCEPTION 'You are not a participant in this room'; END IF;

    SELECT membership.role INTO actor_role
    FROM public.school_memberships membership
    WHERE membership.school_id = room_record.school_id
      AND membership.user_id = actor
      AND membership.active = TRUE
      AND membership.role IN ('parent', 'teacher')
    ORDER BY CASE membership.role WHEN 'teacher' THEN 0 ELSE 1 END
    LIMIT 1;
    IF actor_role IS NULL THEN
        RAISE EXCEPTION 'Only parent and teacher participants can leave a custom room';
    END IF;

    INSERT INTO public.chat_participant_audit (
        room_id, school_id, user_id, action, acted_by
    ) VALUES (input_room_id, room_record.school_id, actor, 'removed', actor);
    DELETE FROM public.chat_participants
    WHERE room_id = input_room_id AND user_id = actor;

    INSERT INTO public.workflow_audit_events (
        school_id, actor_id, event_type, source_type, source_id, metadata
    ) VALUES (
        room_record.school_id, actor, 'participant_left', 'chat_room',
        input_room_id, jsonb_build_object('role', actor_role)
    ) RETURNING id INTO workflow_event_id;

    SELECT array_agg(membership.user_id) INTO director_ids
    FROM public.school_memberships membership
    WHERE membership.school_id = room_record.school_id
      AND membership.active = TRUE
      AND membership.role = 'school_director';

    PERFORM public.enqueue_workflow_notification(
        room_record.school_id,
        'A member left ' || room_record.name,
        'A parent or teacher left this custom group chat.',
        'chat_participant_left', 'chat_room', input_room_id, director_ids,
        'chat:participant:left:' || workflow_event_id::TEXT,
        'routine', jsonb_build_object('type', 'chat_room', 'id', input_room_id), actor
    );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_director_chat_room(
    input_school_id UUID,
    input_name TEXT,
    input_description TEXT DEFAULT NULL,
    input_profile_image_url TEXT DEFAULT NULL,
    input_participant_ids UUID[] DEFAULT ARRAY[]::UUID[],
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.chat_rooms
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    room_record public.chat_rooms%ROWTYPE;
    existing_result UUID;
BEGIN
    IF NOT public.has_direct_school_role(input_school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can create rooms';
    END IF;
    IF NULLIF(btrim(COALESCE(input_name, '')), '') IS NULL
       OR NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Room name and idempotency key are required';
    END IF;

    PERFORM pg_advisory_xact_lock(
        hashtextextended(actor::TEXT || ':chat-create:' || btrim(input_idempotency_key), 0)
    );
    SELECT result_id INTO existing_result
    FROM public.school_workflow_mutations
    WHERE actor_id = actor
      AND operation = 'create_chat_room'
      AND idempotency_key = btrim(input_idempotency_key);
    IF existing_result IS NOT NULL THEN
        RETURN QUERY SELECT * FROM public.chat_rooms WHERE id = existing_result;
        RETURN;
    END IF;

    IF EXISTS (
        SELECT selected.user_id
        FROM unnest(COALESCE(input_participant_ids, ARRAY[]::UUID[])) selected(user_id)
        WHERE NOT EXISTS (
            SELECT 1
            FROM public.school_memberships membership
            WHERE membership.school_id = input_school_id
              AND membership.user_id = selected.user_id
              AND membership.active = TRUE
              AND membership.access_state = 'full'
              AND membership.role IN ('parent', 'teacher', 'school_director')
        )
    ) THEN
        RAISE EXCEPTION 'Every participant must be a full-access adult school member';
    END IF;

    INSERT INTO public.chat_rooms (
        name, description, profile_image_url, invite_hash, room_type,
        system_managed, created_by, school_id, created_at, updated_at
    ) VALUES (
        btrim(input_name),
        NULLIF(btrim(COALESCE(input_description, '')), ''),
        NULLIF(btrim(COALESCE(input_profile_image_url, '')), ''),
        NULL, 'custom', FALSE, actor, input_school_id, NOW(), NOW()
    ) RETURNING * INTO room_record;

    INSERT INTO public.chat_participants (
        room_id, user_id, role, membership_source
    ) VALUES (
        room_record.id, actor, 'owner', 'manual'
    ) ON CONFLICT (room_id, user_id) DO UPDATE
      SET role = 'owner', membership_source = 'manual';

    INSERT INTO public.chat_participants (
        room_id, user_id, role, membership_source
    )
    SELECT room_record.id, selected.user_id,
           CASE WHEN selected.user_id = actor THEN 'owner' ELSE 'member' END,
           'manual'
    FROM (
        SELECT DISTINCT unnest(COALESCE(input_participant_ids, ARRAY[]::UUID[])) AS user_id
    ) selected
    ON CONFLICT (room_id, user_id) DO NOTHING;

    INSERT INTO public.chat_participant_audit (
        room_id, school_id, user_id, action, acted_by
    )
    SELECT room_record.id, input_school_id, participant.user_id, 'added', actor
    FROM public.chat_participants participant
    WHERE participant.room_id = room_record.id;

    INSERT INTO public.school_workflow_mutations (
        actor_id, operation, idempotency_key, result_id
    ) VALUES (
        actor, 'create_chat_room', btrim(input_idempotency_key), room_record.id
    );
    INSERT INTO public.workflow_audit_events (
        school_id, actor_id, event_type, source_type, source_id
    ) VALUES (
        input_school_id, actor, 'created', 'chat_room', room_record.id
    );
    RETURN QUERY SELECT * FROM public.chat_rooms WHERE id = room_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_director_chat_room(
    input_room_id UUID,
    input_name TEXT,
    input_description TEXT DEFAULT NULL,
    input_profile_image_url TEXT DEFAULT NULL,
    input_archived BOOLEAN DEFAULT FALSE
)
RETURNS SETOF public.chat_rooms
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE room_record public.chat_rooms%ROWTYPE;
BEGIN
    SELECT * INTO room_record
    FROM public.chat_rooms
    WHERE id = input_room_id AND deleted_at IS NULL
    FOR UPDATE;
    IF NOT FOUND
       OR NOT public.has_direct_school_role(room_record.school_id, auth.uid(), ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can update this room';
    END IF;
    IF room_record.system_managed THEN
        RAISE EXCEPTION 'This room is managed automatically';
    END IF;
    IF NULLIF(btrim(COALESCE(input_name, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Room name is required';
    END IF;

    UPDATE public.chat_rooms
    SET name = btrim(input_name),
        description = NULLIF(btrim(COALESCE(input_description, '')), ''),
        profile_image_url = NULLIF(btrim(COALESCE(input_profile_image_url, '')), ''),
        archived_at = CASE WHEN input_archived THEN COALESCE(archived_at, NOW()) ELSE NULL END,
        archive_reason = CASE WHEN input_archived THEN 'director_archived' ELSE NULL END,
        updated_at = NOW()
    WHERE id = input_room_id
    RETURNING * INTO room_record;
    RETURN QUERY SELECT * FROM public.chat_rooms WHERE id = room_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_director_chat_room_image_path(
    input_room_id UUID,
    input_profile_image_path TEXT
)
RETURNS SETOF public.chat_rooms
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE room_record public.chat_rooms%ROWTYPE;
BEGIN
    SELECT * INTO room_record
    FROM public.chat_rooms
    WHERE id = input_room_id AND deleted_at IS NULL
    FOR UPDATE;
    IF NOT FOUND
       OR NOT public.has_direct_school_role(room_record.school_id, auth.uid(), ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can update this room image';
    END IF;
    IF room_record.system_managed THEN
        RAISE EXCEPTION 'This room is managed automatically';
    END IF;
    UPDATE public.chat_rooms
    SET profile_image_path = NULLIF(btrim(COALESCE(input_profile_image_path, '')), ''),
        updated_at = NOW()
    WHERE id = input_room_id
    RETURNING * INTO room_record;
    RETURN QUERY SELECT * FROM public.chat_rooms WHERE id = room_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.set_director_chat_participants(
    input_room_id UUID,
    input_participant_ids UUID[]
)
RETURNS TABLE (room_id UUID, user_id UUID)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    room_record public.chat_rooms%ROWTYPE;
    selected_ids UUID[];
BEGIN
    SELECT * INTO room_record
    FROM public.chat_rooms
    WHERE id = input_room_id AND deleted_at IS NULL
    FOR UPDATE;
    IF NOT FOUND
       OR NOT public.has_direct_school_role(room_record.school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can manage room membership';
    END IF;
    IF room_record.system_managed THEN
        RAISE EXCEPTION 'Membership in this room is managed automatically';
    END IF;

    SELECT COALESCE(array_agg(DISTINCT value), ARRAY[]::UUID[])
    INTO selected_ids
    FROM unnest(COALESCE(input_participant_ids, ARRAY[]::UUID[]) || actor) value;

    IF EXISTS (
        SELECT selected.user_id
        FROM unnest(selected_ids) selected(user_id)
        WHERE NOT EXISTS (
            SELECT 1
            FROM public.school_memberships membership
            WHERE membership.school_id = room_record.school_id
              AND membership.user_id = selected.user_id
              AND membership.active = TRUE
              AND membership.access_state = 'full'
              AND membership.role IN ('parent', 'teacher', 'school_director')
        )
    ) THEN
        RAISE EXCEPTION 'Every participant must be a full-access adult school member';
    END IF;

    INSERT INTO public.chat_participant_audit (
        room_id, school_id, user_id, action, acted_by
    )
    SELECT input_room_id, room_record.school_id, participant.user_id, 'removed', actor
    FROM public.chat_participants participant
    WHERE participant.room_id = input_room_id
      AND NOT (participant.user_id = ANY(selected_ids));

    DELETE FROM public.chat_participants participant
    WHERE participant.room_id = input_room_id
      AND NOT (participant.user_id = ANY(selected_ids));

    INSERT INTO public.chat_participant_audit (
        room_id, school_id, user_id, action, acted_by
    )
    SELECT input_room_id, room_record.school_id, selected.user_id, 'added', actor
    FROM unnest(selected_ids) selected(user_id)
    WHERE NOT EXISTS (
        SELECT 1 FROM public.chat_participants participant
        WHERE participant.room_id = input_room_id
          AND participant.user_id = selected.user_id
    );

    INSERT INTO public.chat_participants (
        room_id, user_id, role, membership_source
    )
    SELECT input_room_id, selected.user_id,
           CASE WHEN selected.user_id = actor THEN 'owner' ELSE 'member' END,
           'manual'
    FROM unnest(selected_ids) selected(user_id)
    ON CONFLICT (room_id, user_id) DO UPDATE
    SET role = EXCLUDED.role, membership_source = 'manual';

    RETURN QUERY
    SELECT participant.room_id, participant.user_id
    FROM public.chat_participants participant
    WHERE participant.room_id = input_room_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.delete_director_chat_room(input_room_id UUID)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE room_record public.chat_rooms%ROWTYPE;
BEGIN
    SELECT * INTO room_record
    FROM public.chat_rooms
    WHERE id = input_room_id AND deleted_at IS NULL
    FOR UPDATE;
    IF NOT FOUND
       OR NOT public.has_direct_school_role(room_record.school_id, auth.uid(), ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only a school director can delete this room';
    END IF;
    IF room_record.system_managed THEN
        RAISE EXCEPTION 'This room is managed automatically and cannot be deleted';
    END IF;

    UPDATE public.chat_rooms
    SET deleted_at = NOW(), deleted_by = auth.uid(),
        archived_at = COALESCE(archived_at, NOW()),
        archive_reason = 'director_deleted', updated_at = NOW()
    WHERE id = input_room_id;

    INSERT INTO public.chat_participant_audit (
        room_id, school_id, user_id, action, acted_by
    )
    SELECT input_room_id, room_record.school_id, participant.user_id, 'removed', auth.uid()
    FROM public.chat_participants participant
    WHERE participant.room_id = input_room_id;
    DELETE FROM public.chat_participants WHERE room_id = input_room_id;

    INSERT INTO public.workflow_audit_events (
        school_id, actor_id, event_type, source_type, source_id
    ) VALUES (
        room_record.school_id, auth.uid(), 'soft_deleted', 'chat_room', input_room_id
    );
END;
$$;

DROP FUNCTION IF EXISTS public.fetch_my_managed_chat_rooms(UUID);
CREATE FUNCTION public.fetch_my_managed_chat_rooms(input_school_id UUID)
RETURNS TABLE (
    id UUID,
    name TEXT,
    description TEXT,
    profile_image_url TEXT,
    profile_image_path TEXT,
    school_id UUID,
    room_type TEXT,
    subject_child_id UUID,
    system_managed BOOLEAN,
    created_at TIMESTAMPTZ,
    created_by UUID,
    updated_at TIMESTAMPTZ,
    archived_at TIMESTAMPTZ,
    archive_reason TEXT,
    retention_until TIMESTAMPTZ,
    deleted_at TIMESTAMPTZ,
    participant_joined_at TIMESTAMPTZ,
    participant_last_read_at TIMESTAMPTZ,
    participant_notifications_enabled BOOLEAN,
    participant_role TEXT,
    participant_membership_source TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE actor UUID := auth.uid();
BEGIN
    IF actor IS NULL THEN RAISE EXCEPTION 'School chat access denied'; END IF;

    RETURN QUERY
    SELECT room.id, room.name, room.description, room.profile_image_url,
           room.profile_image_path, room.school_id, room.room_type,
           room.subject_child_id, room.system_managed, room.created_at,
           room.created_by, room.updated_at, room.archived_at,
           room.archive_reason, room.retention_until, room.deleted_at,
           participant.joined_at, participant.last_read_at,
           participant.notifications_enabled, participant.role,
           participant.membership_source
    FROM public.chat_rooms room
    JOIN public.chat_participants participant
      ON participant.room_id = room.id
     AND participant.user_id = actor
    WHERE room.school_id = input_school_id
      AND room.deleted_at IS NULL
      AND public.is_chat_room_member(room.id, actor)
    ORDER BY room.archived_at NULLS FIRST,
             COALESCE(room.updated_at, room.created_at) DESC,
             room.id;
END;
$$;

DROP POLICY IF EXISTS "Participants can view active managed rooms" ON public.chat_rooms;
DROP POLICY IF EXISTS "Room participants can view rooms" ON public.chat_rooms;
CREATE POLICY "Room participants can view rooms"
    ON public.chat_rooms FOR SELECT
    USING (deleted_at IS NULL AND public.is_chat_room_member(id, auth.uid()));

DROP POLICY IF EXISTS "Participants can view managed room membership" ON public.chat_participants;
DROP POLICY IF EXISTS "Room participants can view membership" ON public.chat_participants;
CREATE POLICY "Room participants can view membership"
    ON public.chat_participants FOR SELECT
    USING (public.is_chat_room_member(room_id, auth.uid()));

DROP POLICY IF EXISTS "Managed room participants can view messages" ON public.messages;
DROP POLICY IF EXISTS "Room participants can view messages" ON public.messages;
CREATE POLICY "Room participants can view messages"
    ON public.messages FOR SELECT
    USING (public.is_chat_room_member(room_id, auth.uid()));

DROP POLICY IF EXISTS "Room participants can view indexed links" ON public.chat_message_links;
CREATE POLICY "Room participants can view indexed links"
    ON public.chat_message_links FOR SELECT
    USING (public.is_chat_room_member(room_id, auth.uid()));

DROP POLICY IF EXISTS "Senders can edit managed room messages" ON public.messages;
CREATE POLICY "Senders can edit managed room messages"
    ON public.messages FOR UPDATE
    USING (
        entry_kind = 'message'
        AND sender_id = auth.uid()
        AND public.is_chat_room_member(room_id, auth.uid())
    )
    WITH CHECK (
        entry_kind = 'message'
        AND structured_source_type IS NULL
        AND structured_source_id IS NULL
        AND sender_id = auth.uid()
        AND public.is_chat_room_member(room_id, auth.uid())
    );

DROP POLICY IF EXISTS "Senders can delete managed room messages" ON public.messages;
CREATE POLICY "Senders can delete managed room messages"
    ON public.messages FOR DELETE
    USING (
        entry_kind = 'message'
        AND sender_id = auth.uid()
        AND public.is_chat_room_member(room_id, auth.uid())
    );

DROP POLICY IF EXISTS "Managed room participants can send messages" ON public.messages;
CREATE POLICY "Managed room participants can send messages"
    ON public.messages FOR INSERT
    WITH CHECK (
        entry_kind = 'message'
        AND structured_source_type IS NULL
        AND structured_source_id IS NULL
        AND sender_id = auth.uid()
        AND public.is_chat_room_member(room_id, auth.uid())
        AND EXISTS (
            SELECT 1
            FROM public.chat_rooms room
            WHERE room.id = messages.room_id
              AND room.deleted_at IS NULL
              AND room.archived_at IS NULL
        )
    );

DROP POLICY IF EXISTS "Families and staff can view family requests" ON public.family_requests;
CREATE POLICY "Families and staff can view family requests"
    ON public.family_requests FOR SELECT
    USING (
        requested_by = auth.uid()
        OR public.can_staff_access_child(child_id, auth.uid(), ARRAY['teacher', 'school_director'])
    );

CREATE OR REPLACE FUNCTION public.append_structured_child_timeline_entry()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    target_room_id UUID;
    source_kind TEXT;
    source_id UUID;
    source_school_id UUID;
    source_child_id UUID;
    source_sender_id UUID;
    source_created_at TIMESTAMPTZ;
    source_label TEXT;
BEGIN
    IF TG_TABLE_NAME = 'child_care_events' THEN
        IF NEW.visibility <> 'parent' THEN RETURN NEW; END IF;
        source_kind := 'care_event';
        source_id := NEW.id;
        source_school_id := NEW.school_id;
        source_child_id := NEW.child_id;
        source_sender_id := NEW.recorded_by;
        source_created_at := NEW.occurred_at;
        source_label := CASE NEW.event_type
            WHEN 'meal' THEN 'Meal update'
            WHEN 'bottle' THEN 'Bottle update'
            WHEN 'nap' THEN 'Nap update'
            WHEN 'potty' THEN 'Toileting update'
            WHEN 'diaper' THEN 'Diaper update'
            WHEN 'medication' THEN 'Medication administration'
            WHEN 'health_check' THEN 'Health observation'
            WHEN 'activity' THEN 'Activity update'
            WHEN 'photo' THEN 'Photo update'
            ELSE 'Care note'
        END;
    ELSIF TG_TABLE_NAME = 'family_requests' THEN
        source_kind := 'family_request';
        source_id := NEW.id;
        source_school_id := NEW.school_id;
        source_child_id := NEW.child_id;
        source_sender_id := NEW.requested_by;
        source_created_at := NEW.created_at;
        source_label := CASE NEW.request_type
            WHEN 'absence' THEN 'Absence request'
            WHEN 'pickup_change' THEN 'Pickup change request'
            WHEN 'medication' THEN 'Medication question'
            ELSE 'Family request'
        END;
    ELSE
        RETURN NEW;
    END IF;

    SELECT room.id INTO target_room_id
    FROM public.chat_rooms room
    WHERE room.school_id = source_school_id
      AND room.subject_child_id = source_child_id
      AND room.room_type = 'child_family'
      AND room.deleted_at IS NULL
      AND room.archived_at IS NULL
    LIMIT 1;

    IF target_room_id IS NULL THEN RETURN NEW; END IF;

    INSERT INTO public.messages (
        room_id, school_id, sender_id, text, entry_kind,
        structured_source_type, structured_source_id,
        created_at, is_deleted
    ) VALUES (
        target_room_id, source_school_id, source_sender_id, source_label,
        source_kind, TG_TABLE_NAME, source_id, source_created_at, FALSE
    )
    ON CONFLICT (structured_source_type, structured_source_id)
        WHERE structured_source_id IS NOT NULL
    DO NOTHING;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS append_care_event_to_child_timeline_trigger ON public.child_care_events;
CREATE TRIGGER append_care_event_to_child_timeline_trigger
    AFTER INSERT ON public.child_care_events
    FOR EACH ROW EXECUTE FUNCTION public.append_structured_child_timeline_entry();

DROP TRIGGER IF EXISTS append_family_request_to_child_timeline_trigger ON public.family_requests;
CREATE TRIGGER append_family_request_to_child_timeline_trigger
    AFTER INSERT ON public.family_requests
    FOR EACH ROW EXECUTE FUNCTION public.append_structured_child_timeline_entry();

CREATE OR REPLACE FUNCTION public.notify_chat_message()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE room_record public.chat_rooms%ROWTYPE;
BEGIN
    SELECT * INTO room_record FROM public.chat_rooms WHERE id = NEW.room_id;
    IF room_record.deleted_at IS NULL THEN
        PERFORM public.enqueue_workflow_notification(
            room_record.school_id,
            room_record.name,
            COALESCE(
                NULLIF(NEW.text, ''),
                CASE
                    WHEN NEW.audio_path IS NOT NULL OR NEW.audio_url IS NOT NULL THEN 'Voice message'
                    WHEN NEW.entry_kind = 'care_event' THEN 'New care update'
                    WHEN NEW.entry_kind = 'family_request' THEN 'New family request'
                    WHEN NEW.entry_kind = 'goal_update' THEN 'New goal update'
                    ELSE 'New attachment'
                END
            ),
            'chat_message', 'chat_room', room_record.id,
            ARRAY(
                SELECT participant.user_id
                FROM public.chat_participants participant
                WHERE participant.room_id = room_record.id
                  AND participant.user_id <> NEW.sender_id
                  AND participant.notifications_enabled = TRUE
            ),
            'chat:message:' || NEW.id::TEXT,
            'routine',
            jsonb_build_object('type', 'chat_room', 'id', room_record.id, 'message_id', NEW.id),
            NEW.sender_id
        );
    END IF;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.record_attendance_batch(
    input_child_ids UUID[],
    input_action TEXT,
    input_idempotency_key TEXT
)
RETURNS TABLE (
    child_id UUID,
    success BOOLEAN,
    session_id UUID,
    error_code TEXT,
    error_message TEXT
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    target_child_id UUID;
    saved_session_id UUID;
    caught_state TEXT;
    caught_message TEXT;
BEGIN
    IF auth.uid() IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    IF COALESCE(array_length(input_child_ids, 1), 0) = 0 THEN
        RAISE EXCEPTION 'Select at least one child';
    END IF;
    IF input_action NOT IN ('check_in', 'check_out', 'absent') THEN
        RAISE EXCEPTION 'Invalid batch attendance action';
    END IF;
    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NULL THEN
        RAISE EXCEPTION 'An idempotency key is required';
    END IF;

    FOREACH target_child_id IN ARRAY input_child_ids LOOP
        BEGIN
            saved_session_id := NULL;
            SELECT session.id INTO saved_session_id
            FROM public.record_school_attendance(
                target_child_id,
                input_action,
                NOW(),
                NULL,
                btrim(input_idempotency_key) || ':' || target_child_id::TEXT
            ) session
            LIMIT 1;

            child_id := target_child_id;
            success := saved_session_id IS NOT NULL;
            session_id := saved_session_id;
            error_code := NULL;
            error_message := NULL;
            RETURN NEXT;
        EXCEPTION WHEN OTHERS THEN
            GET STACKED DIAGNOSTICS
                caught_state = RETURNED_SQLSTATE,
                caught_message = MESSAGE_TEXT;
            child_id := target_child_id;
            success := FALSE;
            session_id := NULL;
            error_code := caught_state;
            error_message := caught_message;
            RETURN NEXT;
        END;
    END LOOP;
END;
$$;

-- Assignment revisions stay creator-owned. Recipients can only submit a new
-- attempt after the creator has enabled revisions and requested changes.
ALTER TABLE public.assignment_submissions
    ADD COLUMN IF NOT EXISTS score SMALLINT;

ALTER TABLE public.assignment_submissions
    DROP CONSTRAINT IF EXISTS assignment_submissions_score_check;
ALTER TABLE public.assignment_submissions
    ADD CONSTRAINT assignment_submissions_score_check
    CHECK (score IS NULL OR score BETWEEN 1 AND 10);

ALTER TABLE public.school_events
    ADD COLUMN IF NOT EXISTS archived_at TIMESTAMPTZ,
    ADD COLUMN IF NOT EXISTS archived_by UUID REFERENCES auth.users(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_school_events_active_school_start
    ON public.school_events(school_id, start_at)
    WHERE archived_at IS NULL;

DROP POLICY IF EXISTS "School members can view events" ON public.school_events;
CREATE POLICY "School members can view events"
    ON public.school_events FOR SELECT
    USING (
        (archived_at IS NULL AND public.is_school_member(school_id, auth.uid()))
        OR public.has_school_role(school_id, auth.uid(), ARRAY['teacher', 'school_director', 'hq_director'])
    );

CREATE OR REPLACE FUNCTION public.set_school_event_archived(
    input_event_id UUID,
    input_archived BOOLEAN
)
RETURNS SETOF public.school_events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    event_record public.school_events%ROWTYPE;
BEGIN
    IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;

    SELECT * INTO event_record
    FROM public.school_events
    WHERE id = input_event_id
    FOR UPDATE;

    IF NOT FOUND OR NOT public.has_school_role(
        event_record.school_id,
        actor,
        ARRAY['teacher', 'school_director', 'hq_director']
    ) THEN
        RAISE EXCEPTION 'You cannot archive this event';
    END IF;

    UPDATE public.school_events
    SET archived_at = CASE WHEN input_archived THEN COALESCE(archived_at, NOW()) ELSE NULL END,
        archived_by = CASE WHEN input_archived THEN actor ELSE NULL END,
        updated_at = NOW()
    WHERE id = input_event_id
    RETURNING * INTO event_record;

    RETURN QUERY SELECT events.* FROM public.school_events events WHERE events.id = input_event_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_assignment_details(
    input_assignment_id UUID,
    input_title TEXT,
    input_description TEXT DEFAULT NULL,
    input_due_at TIMESTAMPTZ DEFAULT NULL,
    input_allow_resubmission BOOLEAN DEFAULT TRUE
)
RETURNS SETOF public.assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    assignment_record public.assignments%ROWTYPE;
BEGIN
    IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    IF NULLIF(btrim(COALESCE(input_title, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Assignment title is required';
    END IF;

    SELECT * INTO assignment_record
    FROM public.assignments
    WHERE id = input_assignment_id
    FOR UPDATE;

    IF NOT FOUND OR assignment_record.assigned_by <> actor THEN
        RAISE EXCEPTION 'Only the assignment creator can edit this assignment';
    END IF;
    IF assignment_record.status = 'archived' THEN
        RAISE EXCEPTION 'Archived assignments cannot be edited';
    END IF;
    IF input_due_at IS NOT NULL
       AND input_due_at <= COALESCE(assignment_record.publish_at, assignment_record.created_at, NOW()) THEN
        RAISE EXCEPTION 'The due date must be after the assignment is published';
    END IF;

    UPDATE public.assignments
    SET title = btrim(input_title),
        description = NULLIF(btrim(COALESCE(input_description, '')), ''),
        due_at = input_due_at,
        allow_resubmission = COALESCE(input_allow_resubmission, TRUE),
        updated_at = NOW()
    WHERE id = input_assignment_id
    RETURNING * INTO assignment_record;

    INSERT INTO public.assignment_events (
        assignment_id, school_id, actor_id, event_type, metadata
    ) VALUES (
        assignment_record.id,
        assignment_record.school_id,
        actor,
        'edited',
        jsonb_build_object(
            'allow_resubmission', assignment_record.allow_resubmission,
            'due_at', assignment_record.due_at
        )
    );

    RETURN QUERY SELECT assignments.* FROM public.assignments WHERE id = input_assignment_id;
END;
$$;

DROP FUNCTION IF EXISTS public.review_assignment_submission_v2(UUID, TEXT, TEXT, TEXT);
CREATE FUNCTION public.review_assignment_submission_v2(
    input_submission_id UUID,
    input_status TEXT,
    input_reviewer_message TEXT DEFAULT NULL,
    input_idempotency_key TEXT DEFAULT NULL,
    input_score INTEGER DEFAULT NULL
)
RETURNS SETOF public.assignment_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    submission_record public.assignment_submissions%ROWTYPE;
    latest_submission_id UUID;
    assignment_record public.assignments%ROWTYPE;
    existing_result_id UUID;
    notification_id UUID;
BEGIN
    IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    IF input_status NOT IN ('accepted', 'changes_requested') THEN
        RAISE EXCEPTION 'Review status must be accepted or changes_requested';
    END IF;
    IF input_score IS NOT NULL AND (input_score < 1 OR input_score > 10) THEN
        RAISE EXCEPTION 'Score must be between 1 and 10';
    END IF;
    IF input_status = 'changes_requested'
       AND NULLIF(btrim(COALESCE(input_reviewer_message, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Feedback is required when requesting changes';
    END IF;

    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(hashtextextended(
            actor::TEXT || ':review:' || btrim(input_idempotency_key), 0
        ));
        SELECT result_id INTO existing_result_id
        FROM public.assignment_mutation_requests
        WHERE actor_id = actor
          AND idempotency_key = btrim(input_idempotency_key)
          AND operation = 'review';
        IF existing_result_id IS NOT NULL THEN
            RETURN QUERY SELECT * FROM public.assignment_submissions WHERE id = existing_result_id;
            RETURN;
        END IF;
    END IF;

    SELECT * INTO submission_record
    FROM public.assignment_submissions
    WHERE id = input_submission_id
    FOR UPDATE;

    IF NOT FOUND OR NOT public.can_review_assignment_submission(input_submission_id, actor) THEN
        RAISE EXCEPTION 'Only the assignment creator can review this submission';
    END IF;

    SELECT id INTO latest_submission_id
    FROM public.assignment_submissions
    WHERE assignment_id = submission_record.assignment_id
      AND submitted_by = submission_record.submitted_by
    ORDER BY attempt_number DESC, submitted_at DESC
    LIMIT 1;

    IF latest_submission_id <> submission_record.id
       OR submission_record.status NOT IN ('submitted', 'resubmitted') THEN
        RAISE EXCEPTION 'Only the latest pending attempt can be reviewed';
    END IF;

    SELECT * INTO assignment_record
    FROM public.assignments
    WHERE id = submission_record.assignment_id;

    UPDATE public.assignment_submissions
    SET status = input_status,
        score = input_score,
        reviewer_message = NULLIF(btrim(COALESCE(input_reviewer_message, '')), ''),
        reviewed_by = actor,
        reviewed_at = NOW()
    WHERE id = submission_record.id
    RETURNING * INTO submission_record;

    UPDATE public.assignment_recipients
    SET completion_status = input_status,
        completed_at = CASE WHEN input_status = 'accepted' THEN NOW() ELSE NULL END
    WHERE assignment_id = assignment_record.id
      AND user_id = submission_record.submitted_by;

    IF NULLIF(btrim(COALESCE(input_reviewer_message, '')), '') IS NOT NULL THEN
        INSERT INTO public.assignment_feedback_messages (
            assignment_id, submission_id, school_id, sender_id, recipient_id, body
        ) VALUES (
            assignment_record.id, submission_record.id, assignment_record.school_id,
            actor, submission_record.submitted_by, btrim(input_reviewer_message)
        );
    END IF;

    INSERT INTO public.assignment_events (assignment_id, school_id, actor_id, event_type, metadata)
    VALUES (
        assignment_record.id, assignment_record.school_id, actor, input_status,
        jsonb_build_object(
            'submission_id', submission_record.id,
            'recipient_id', submission_record.submitted_by,
            'attempt_number', submission_record.attempt_number,
            'score', input_score
        )
    );

    INSERT INTO public.notifications (
        school_id, title, body, category, source_type, source_id, created_by, dedupe_key
    ) VALUES (
        assignment_record.school_id,
        assignment_record.title,
        'Status: ' || initcap(replace(input_status, '_', ' '))
            || CASE WHEN input_score IS NULL THEN '' ELSE '. Score: ' || input_score::TEXT || '/10' END
            || COALESCE('. ' || NULLIF(btrim(input_reviewer_message), ''), '.'),
        'assignment_reviewed', 'assignment', assignment_record.id, actor,
        'assignment:review:' || submission_record.id::TEXT || ':' || input_status
    ) RETURNING id INTO notification_id;

    INSERT INTO public.notification_recipients (notification_id, user_id)
    VALUES (notification_id, submission_record.submitted_by)
    ON CONFLICT DO NOTHING;

    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NOT NULL THEN
        INSERT INTO public.assignment_mutation_requests (actor_id, idempotency_key, operation, result_id)
        VALUES (actor, btrim(input_idempotency_key), 'review', submission_record.id);
    END IF;

    RETURN QUERY SELECT * FROM public.assignment_submissions WHERE id = submission_record.id;
END;
$$;

-- Bring existing schools and eligible families into the chat-first lifecycle.
DO $$
DECLARE school_id UUID;
BEGIN
    FOR school_id IN SELECT id FROM public.schools LOOP
        PERFORM public.sync_school_communication_rooms(school_id);
    END LOOP;
END;
$$;

REVOKE ALL ON FUNCTION public.cancel_school_director_invite(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sync_child_family_room(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.sync_school_communication_rooms(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fetch_my_managed_chat_rooms(UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.record_attendance_batch(UUID[], TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_assignment_details(UUID, TEXT, TEXT, TIMESTAMPTZ, BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.review_assignment_submission_v2(UUID, TEXT, TEXT, TEXT, INTEGER) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_school_event_archived(UUID, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.cancel_school_director_invite(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_my_managed_chat_rooms(UUID) TO authenticated;
GRANT EXECUTE ON FUNCTION public.record_attendance_batch(UUID[], TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_assignment_details(UUID, TEXT, TEXT, TIMESTAMPTZ, BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.review_assignment_submission_v2(UUID, TEXT, TEXT, TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.set_school_event_archived(UUID, BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$ SELECT 20260727000000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';

-- Migration: 20260727153000_expand_daily_activity_types.sql

BEGIN;

-- Daily activity options now follow the classroom feed vocabulary used by
-- modern childcare tools while preserving all existing Firefly event values.
ALTER TABLE public.child_care_events
    DROP CONSTRAINT IF EXISTS child_care_events_event_type_check;

ALTER TABLE public.child_care_events
    ADD CONSTRAINT child_care_events_event_type_check CHECK (event_type IN (
        'meal', 'bottle', 'nap', 'potty', 'diaper', 'medication',
        'health_check', 'activity', 'observation', 'kudos', 'incident',
        'note', 'photo'
    ));

CREATE OR REPLACE FUNCTION public.record_child_care_event(
    input_child_id UUID,
    input_event_type TEXT,
    input_occurred_at TIMESTAMPTZ,
    input_details JSONB,
    input_visibility TEXT,
    input_medication_task_id UUID DEFAULT NULL,
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.child_care_events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    child_record public.children%ROWTYPE;
    saved_event public.child_care_events%ROWTYPE;
    guardian_ids UUID[];
BEGIN
    SELECT * INTO child_record FROM public.children WHERE id = input_child_id AND active = TRUE;
    IF NOT FOUND OR NOT public.can_staff_access_child(input_child_id, actor, ARRAY['teacher', 'school_director']) THEN
        RAISE EXCEPTION 'You cannot record care for this child';
    END IF;
    IF input_event_type NOT IN (
        'meal', 'bottle', 'nap', 'potty', 'diaper', 'medication',
        'health_check', 'activity', 'observation', 'kudos', 'incident',
        'note', 'photo'
    ) THEN
        RAISE EXCEPTION 'Invalid care event type';
    END IF;
    IF input_visibility NOT IN ('parent', 'staff_only') THEN RAISE EXCEPTION 'Invalid visibility'; END IF;
    IF jsonb_typeof(COALESCE(input_details, '{}'::JSONB)) <> 'object' THEN RAISE EXCEPTION 'Details must be an object'; END IF;
    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NULL THEN RAISE EXCEPTION 'An idempotency key is required'; END IF;
    IF input_event_type = 'photo' AND (
        NULLIF(btrim(COALESCE(input_details->>'photo_path', '')), '') IS NULL
        OR input_details->>'photo_path' NOT LIKE (
            'schools/' || child_record.school_id::TEXT || '/care_events/' || input_child_id::TEXT
            || '/' || input_visibility || '/' || actor::TEXT || '/%'
        )
    ) THEN RAISE EXCEPTION 'Photo care events require a private photo uploaded by the recording staff member'; END IF;

    INSERT INTO public.child_care_events (
        school_id, child_id, event_type, occurred_at, details, visibility,
        recorded_by, source_medication_task_id, idempotency_key
    ) VALUES (
        child_record.school_id, input_child_id, input_event_type,
        COALESCE(input_occurred_at, NOW()), COALESCE(input_details, '{}'::JSONB),
        input_visibility, actor, input_medication_task_id, btrim(input_idempotency_key)
    )
    ON CONFLICT (recorded_by, idempotency_key) DO UPDATE SET idempotency_key = EXCLUDED.idempotency_key
    RETURNING * INTO saved_event;

    IF input_event_type = 'medication' THEN
        IF input_medication_task_id IS NULL OR NOT EXISTS (
            SELECT 1 FROM public.medication_tasks task
            JOIN public.medication_instructions instruction ON instruction.id = task.instruction_id
            WHERE task.id = input_medication_task_id
              AND task.child_id = input_child_id
              AND instruction.source_assignment_submission_id IS NOT NULL
        ) THEN RAISE EXCEPTION 'Medication care requires an approved authorization task'; END IF;
        UPDATE public.medication_tasks SET status = 'acknowledged' WHERE id = input_medication_task_id;
        INSERT INTO public.medication_acknowledgements (
            task_id, school_id, child_id, acknowledged_by, dosage_given, notes, given_at
        )
        SELECT input_medication_task_id, child_record.school_id, input_child_id, actor,
            NULLIF(input_details->>'dosage_given', ''), NULLIF(input_details->>'notes', ''), saved_event.occurred_at
        WHERE NOT EXISTS (
            SELECT 1 FROM public.medication_acknowledgements WHERE task_id = input_medication_task_id
        );
    END IF;

    IF input_visibility = 'parent' AND input_event_type IN ('medication', 'health_check', 'incident') THEN
        SELECT array_agg(guardian.guardian_id) INTO guardian_ids
        FROM public.child_guardians guardian
        WHERE guardian.child_id = input_child_id
          AND guardian.verification_status = 'verified' AND guardian.ended_at IS NULL;
        PERFORM public.enqueue_workflow_notification(
            child_record.school_id,
            CASE
                WHEN input_event_type = 'medication' THEN 'Medication administered'
                WHEN input_event_type = 'incident' THEN 'Incident update'
                ELSE 'Health update'
            END,
            child_record.first_name || ' has a new ' || replace(input_event_type, '_', ' ') || ' update.',
            'care_' || input_event_type, 'child_care_event', saved_event.id,
            guardian_ids, 'care:' || input_event_type || ':' || saved_event.id::TEXT,
            CASE WHEN input_event_type IN ('health_check', 'incident') THEN 'urgent' ELSE 'important' END,
            jsonb_build_object('type', 'child_care_event', 'id', saved_event.id, 'child_id', input_child_id), actor
        );
    END IF;
    INSERT INTO public.workflow_audit_events (school_id, actor_id, event_type, source_type, source_id)
    VALUES (child_record.school_id, actor, 'recorded', 'child_care_event', saved_event.id);
    RETURN QUERY SELECT * FROM public.child_care_events WHERE id = saved_event.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.append_structured_child_timeline_entry()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    target_room_id UUID;
    source_kind TEXT;
    source_id UUID;
    source_school_id UUID;
    source_child_id UUID;
    source_sender_id UUID;
    source_created_at TIMESTAMPTZ;
    source_label TEXT;
BEGIN
    IF TG_TABLE_NAME = 'child_care_events' THEN
        IF NEW.visibility <> 'parent' THEN RETURN NEW; END IF;
        source_kind := 'care_event';
        source_id := NEW.id;
        source_school_id := NEW.school_id;
        source_child_id := NEW.child_id;
        source_sender_id := NEW.recorded_by;
        source_created_at := NEW.occurred_at;
        source_label := CASE NEW.event_type
            WHEN 'meal' THEN 'Meal update'
            WHEN 'bottle' THEN 'Bottle update'
            WHEN 'nap' THEN 'Nap update'
            WHEN 'potty' THEN 'Toileting update'
            WHEN 'diaper' THEN 'Diaper update'
            WHEN 'medication' THEN 'Medication administration'
            WHEN 'health_check' THEN 'Health observation'
            WHEN 'activity' THEN 'Learning activity'
            WHEN 'observation' THEN 'Child observation'
            WHEN 'kudos' THEN 'Kudos and milestone'
            WHEN 'incident' THEN 'Incident update'
            WHEN 'photo' THEN 'Photo update'
            ELSE 'Care note'
        END;
        source_label := source_label || COALESCE(
            ' — ' || NULLIF(concat_ws(
                ' • ',
                NULLIF(NEW.details->>'summary', ''),
                NULLIF(NEW.details->>'amount', ''),
                NULLIF(NEW.details->>'outcome', ''),
                NULLIF(NEW.details->>'dosage_given', '')
            ), ''),
            ''
        );
    ELSIF TG_TABLE_NAME = 'family_requests' THEN
        source_kind := 'family_request';
        source_id := NEW.id;
        source_school_id := NEW.school_id;
        source_child_id := NEW.child_id;
        source_sender_id := NEW.requested_by;
        source_created_at := NEW.created_at;
        source_label := CASE NEW.request_type
            WHEN 'absence' THEN 'Absence request'
            WHEN 'pickup_change' THEN 'Pickup change request'
            WHEN 'medication' THEN 'Medication question'
            ELSE 'Family request'
        END;
        source_label := source_label || COALESCE(' — ' || NULLIF(NEW.details->>'message', ''), '');
    ELSE
        RETURN NEW;
    END IF;

    SELECT room.id INTO target_room_id
    FROM public.chat_rooms room
    WHERE room.school_id = source_school_id
      AND room.subject_child_id = source_child_id
      AND room.room_type = 'child_family'
      AND room.deleted_at IS NULL
      AND room.archived_at IS NULL
    LIMIT 1;

    IF target_room_id IS NULL THEN RETURN NEW; END IF;

    INSERT INTO public.messages (
        room_id, school_id, sender_id, text, entry_kind,
        structured_source_type, structured_source_id,
        created_at, is_deleted
    ) VALUES (
        target_room_id, source_school_id, source_sender_id, source_label,
        source_kind, TG_TABLE_NAME, source_id, source_created_at, FALSE
    )
    ON CONFLICT (structured_source_type, structured_source_id)
        WHERE structured_source_id IS NOT NULL
    DO NOTHING;
    RETURN NEW;
END;
$$;

COMMIT;

-- Migration: 20260728090000_assignment_workflow_improvements.sql

BEGIN;

CREATE TABLE IF NOT EXISTS public.assignment_revisions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    assignment_id UUID NOT NULL REFERENCES public.assignments(id) ON DELETE CASCADE,
    revision_number INTEGER NOT NULL CHECK (revision_number > 0),
    title TEXT NOT NULL,
    description TEXT,
    due_at TIMESTAMPTZ,
    allow_resubmission BOOLEAN NOT NULL DEFAULT TRUE,
    created_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (assignment_id, revision_number)
);

CREATE TABLE IF NOT EXISTS public.assignment_revision_materials (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    revision_id UUID NOT NULL REFERENCES public.assignment_revisions(id) ON DELETE CASCADE,
    material_type TEXT NOT NULL DEFAULT 'file' CHECK (material_type IN ('article', 'link', 'image', 'video', 'file', 'mixed')),
    title TEXT,
    url TEXT,
    private_file_path TEXT,
    file_name TEXT,
    content_type TEXT,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

ALTER TABLE public.assignments
    ADD COLUMN IF NOT EXISTS current_revision_id UUID REFERENCES public.assignment_revisions(id) ON DELETE SET NULL;

ALTER TABLE public.assignment_submissions
    ADD COLUMN IF NOT EXISTS assignment_revision_id UUID REFERENCES public.assignment_revisions(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_assignment_revisions_assignment
    ON public.assignment_revisions(assignment_id, revision_number DESC);
CREATE INDEX IF NOT EXISTS idx_assignment_revision_materials_revision
    ON public.assignment_revision_materials(revision_id);
CREATE INDEX IF NOT EXISTS idx_assignment_submissions_revision
    ON public.assignment_submissions(assignment_revision_id);

ALTER TABLE public.assignment_revisions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.assignment_revision_materials ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "Assignment participants can view revisions" ON public.assignment_revisions;
CREATE POLICY "Assignment participants can view revisions"
    ON public.assignment_revisions FOR SELECT
    USING (public.can_view_assignment(assignment_id, auth.uid()));

DROP POLICY IF EXISTS "Assignment participants can view revision materials" ON public.assignment_revision_materials;
CREATE POLICY "Assignment participants can view revision materials"
    ON public.assignment_revision_materials FOR SELECT
    USING (
        EXISTS (
            SELECT 1 FROM public.assignment_revisions revision
            WHERE revision.id = assignment_revision_materials.revision_id
              AND public.can_view_assignment(revision.assignment_id, auth.uid())
        )
    );

INSERT INTO public.assignment_revisions (
    assignment_id, revision_number, title, description, due_at,
    allow_resubmission, created_by, created_at
)
SELECT assignment.id, 1, assignment.title, assignment.description, assignment.due_at,
       COALESCE(assignment.allow_resubmission, TRUE), assignment.assigned_by,
       COALESCE(assignment.updated_at, assignment.created_at, NOW())
FROM public.assignments assignment
WHERE NOT EXISTS (
    SELECT 1 FROM public.assignment_revisions revision
    WHERE revision.assignment_id = assignment.id
);

INSERT INTO public.assignment_revision_materials (
    revision_id, material_type, title, url, private_file_path,
    file_name, content_type, created_at
)
SELECT revision.id, material.material_type, material.title, material.url,
       material.private_file_path, material.file_name, material.content_type,
       COALESCE(material.created_at, revision.created_at)
FROM public.assignment_revisions revision
JOIN public.assignment_materials material ON material.assignment_id = revision.assignment_id
WHERE revision.revision_number = 1
  AND NOT EXISTS (
      SELECT 1 FROM public.assignment_revision_materials existing
      WHERE existing.revision_id = revision.id
  );

UPDATE public.assignments assignment
SET current_revision_id = revision.id
FROM public.assignment_revisions revision
WHERE revision.assignment_id = assignment.id
  AND revision.revision_number = 1
  AND assignment.current_revision_id IS NULL;

UPDATE public.assignment_submissions submission
SET assignment_revision_id = assignment.current_revision_id
FROM public.assignments assignment
WHERE assignment.id = submission.assignment_id
  AND submission.assignment_revision_id IS NULL;

CREATE OR REPLACE FUNCTION public.snapshot_assignment_revision(
    input_assignment_id UUID,
    input_actor UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    assignment_record public.assignments%ROWTYPE;
    saved_revision public.assignment_revisions%ROWTYPE;
    next_revision INTEGER;
BEGIN
    SELECT * INTO assignment_record
    FROM public.assignments
    WHERE id = input_assignment_id
    FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Assignment was not found'; END IF;

    SELECT COALESCE(MAX(revision_number), 0) + 1 INTO next_revision
    FROM public.assignment_revisions
    WHERE assignment_id = input_assignment_id;

    INSERT INTO public.assignment_revisions (
        assignment_id, revision_number, title, description, due_at,
        allow_resubmission, created_by
    ) VALUES (
        assignment_record.id, next_revision, assignment_record.title,
        assignment_record.description, assignment_record.due_at,
        COALESCE(assignment_record.allow_resubmission, TRUE),
        COALESCE(input_actor, auth.uid())
    ) RETURNING * INTO saved_revision;

    INSERT INTO public.assignment_revision_materials (
        revision_id, material_type, title, url, private_file_path,
        file_name, content_type, created_at
    )
    SELECT saved_revision.id, material.material_type, material.title, material.url,
           material.private_file_path, material.file_name, material.content_type,
           COALESCE(material.created_at, NOW())
    FROM public.assignment_materials material
    WHERE material.assignment_id = assignment_record.id;

    UPDATE public.assignments
    SET current_revision_id = saved_revision.id
    WHERE id = assignment_record.id;

    RETURN saved_revision.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_assignment_v2(
    input_assignment_id UUID,
    input_title TEXT,
    input_description TEXT DEFAULT NULL,
    input_due_at TIMESTAMPTZ DEFAULT NULL,
    input_allow_resubmission BOOLEAN DEFAULT TRUE,
    input_materials JSONB DEFAULT '[]'::JSONB
)
RETURNS SETOF public.assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    assignment_record public.assignments%ROWTYPE;
    material JSONB;
    material_url TEXT;
    material_path TEXT;
    expected_prefix TEXT;
    revision_id UUID;
BEGIN
    IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    IF NULLIF(btrim(COALESCE(input_title, '')), '') IS NULL THEN
        RAISE EXCEPTION 'Assignment title is required';
    END IF;
    IF jsonb_typeof(COALESCE(input_materials, '[]'::JSONB)) <> 'array' THEN
        RAISE EXCEPTION 'Assignment materials must be a JSON array';
    END IF;

    SELECT * INTO assignment_record FROM public.assignments
    WHERE id = input_assignment_id FOR UPDATE;
    IF NOT FOUND OR assignment_record.assigned_by <> actor THEN
        RAISE EXCEPTION 'Only the assignment creator can edit this assignment';
    END IF;
    IF assignment_record.status = 'archived' THEN
        RAISE EXCEPTION 'Archived assignments cannot be edited';
    END IF;
    IF input_due_at IS NOT NULL
       AND input_due_at <= COALESCE(assignment_record.publish_at, assignment_record.created_at, NOW()) THEN
        RAISE EXCEPTION 'The due date must be after the assignment is published';
    END IF;

    expected_prefix := 'schools/' || assignment_record.school_id::TEXT
        || '/assignments/' || assignment_record.id::TEXT || '/materials/';

    FOR material IN SELECT * FROM jsonb_array_elements(COALESCE(input_materials, '[]'::JSONB)) LOOP
        IF COALESCE(material->>'material_type', '') NOT IN ('article', 'link', 'image', 'video', 'file', 'mixed') THEN
            RAISE EXCEPTION 'Material type is invalid';
        END IF;
        material_url := NULLIF(btrim(COALESCE(material->>'url', '')), '');
        material_path := NULLIF(btrim(COALESCE(material->>'private_file_path', '')), '');
        IF material_url IS NOT NULL AND material_url !~* '^https?://' THEN
            RAISE EXCEPTION 'Material links must use http or https';
        END IF;
        IF material_path IS NOT NULL AND LOWER(material_path) NOT LIKE LOWER(expected_prefix) || '%'
           AND NOT EXISTS (
               SELECT 1 FROM public.assignment_materials existing
               WHERE existing.assignment_id = input_assignment_id
                 AND existing.private_file_path = material_path
           ) THEN
            RAISE EXCEPTION 'Assignment material path is invalid';
        END IF;
        IF material_url IS NULL AND material_path IS NULL THEN
            RAISE EXCEPTION 'A material must include a link or private file';
        END IF;
    END LOOP;

    UPDATE public.assignments
    SET title = btrim(input_title),
        description = NULLIF(btrim(COALESCE(input_description, '')), ''),
        due_at = input_due_at,
        allow_resubmission = COALESCE(input_allow_resubmission, TRUE),
        updated_at = NOW()
    WHERE id = input_assignment_id
    RETURNING * INTO assignment_record;

    DELETE FROM public.assignment_materials WHERE assignment_id = input_assignment_id;
    FOR material IN SELECT * FROM jsonb_array_elements(COALESCE(input_materials, '[]'::JSONB)) LOOP
        INSERT INTO public.assignment_materials (
            assignment_id, material_type, title, url, private_file_path,
            file_name, content_type
        ) VALUES (
            input_assignment_id,
            material->>'material_type',
            NULLIF(btrim(COALESCE(material->>'title', '')), ''),
            NULLIF(btrim(COALESCE(material->>'url', '')), ''),
            NULLIF(btrim(COALESCE(material->>'private_file_path', '')), ''),
            NULLIF(btrim(COALESCE(material->>'file_name', '')), ''),
            NULLIF(btrim(COALESCE(material->>'content_type', '')), '')
        );
    END LOOP;

    revision_id := public.snapshot_assignment_revision(input_assignment_id, actor);

    INSERT INTO public.assignment_events (
        assignment_id, school_id, actor_id, event_type, metadata
    ) VALUES (
        assignment_record.id, assignment_record.school_id, actor, 'edited',
        jsonb_build_object(
            'allow_resubmission', assignment_record.allow_resubmission,
            'due_at', assignment_record.due_at,
            'revision_id', revision_id,
            'material_count', jsonb_array_length(COALESCE(input_materials, '[]'::JSONB))
        )
    );

    RETURN QUERY SELECT * FROM public.assignments WHERE id = input_assignment_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.post_assignment_comment_v2(
    input_assignment_id UUID,
    input_recipient_id UUID,
    input_body TEXT,
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.assignment_feedback_messages
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    assignment_record public.assignments%ROWTYPE;
    saved_message public.assignment_feedback_messages%ROWTYPE;
    latest_submission_id UUID;
    existing_result_id UUID;
    target_user UUID;
    notification_id UUID;
BEGIN
    IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    IF NULLIF(btrim(COALESCE(input_body, '')), '') IS NULL THEN RAISE EXCEPTION 'Comment cannot be empty'; END IF;

    SELECT * INTO assignment_record FROM public.assignments WHERE id = input_assignment_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'Assignment was not found'; END IF;
    IF assignment_record.status IN ('closed', 'archived') THEN
        RAISE EXCEPTION 'Comments are read-only while this assignment is closed or archived';
    END IF;
    IF NOT EXISTS (
        SELECT 1 FROM public.assignment_recipients recipient
        WHERE recipient.assignment_id = input_assignment_id
          AND recipient.user_id = input_recipient_id
    ) THEN RAISE EXCEPTION 'Assignment recipient was not found'; END IF;
    IF actor <> input_recipient_id AND actor <> assignment_record.assigned_by THEN
        RAISE EXCEPTION 'Only the recipient and assignment creator can comment';
    END IF;

    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(hashtextextended(actor::TEXT || ':comment-v2:' || btrim(input_idempotency_key), 0));
        SELECT result_id INTO existing_result_id
        FROM public.assignment_mutation_requests
        WHERE actor_id = actor AND idempotency_key = btrim(input_idempotency_key)
          AND operation = 'comment_v2';
        IF existing_result_id IS NOT NULL THEN
            RETURN QUERY SELECT * FROM public.assignment_feedback_messages WHERE id = existing_result_id;
            RETURN;
        END IF;
    END IF;

    SELECT submission.id INTO latest_submission_id
    FROM public.assignment_submissions submission
    WHERE submission.assignment_id = input_assignment_id
      AND submission.submitted_by = input_recipient_id
    ORDER BY submission.attempt_number DESC, submission.submitted_at DESC
    LIMIT 1;

    INSERT INTO public.assignment_feedback_messages (
        assignment_id, submission_id, school_id, sender_id, recipient_id, body
    ) VALUES (
        assignment_record.id, latest_submission_id, assignment_record.school_id,
        actor, input_recipient_id, btrim(input_body)
    ) RETURNING * INTO saved_message;

    target_user := CASE WHEN actor = input_recipient_id THEN assignment_record.assigned_by ELSE input_recipient_id END;
    INSERT INTO public.assignment_events (assignment_id, school_id, actor_id, event_type, metadata)
    VALUES (
        assignment_record.id, assignment_record.school_id, actor, 'commented',
        jsonb_build_object('submission_id', latest_submission_id, 'recipient_id', input_recipient_id)
    );

    IF target_user IS NOT NULL AND target_user <> actor THEN
        INSERT INTO public.notifications (
            school_id, title, body, category, source_type, source_id, created_by, dedupe_key
        ) VALUES (
            assignment_record.school_id, assignment_record.title, btrim(input_body),
            'assignment_feedback', 'assignment', assignment_record.id, actor,
            'assignment:comment:' || saved_message.id::TEXT
        ) RETURNING id INTO notification_id;
        INSERT INTO public.notification_recipients (notification_id, user_id)
        VALUES (notification_id, target_user) ON CONFLICT DO NOTHING;
    END IF;

    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NOT NULL THEN
        INSERT INTO public.assignment_mutation_requests (actor_id, idempotency_key, operation, result_id)
        VALUES (actor, btrim(input_idempotency_key), 'comment_v2', saved_message.id);
    END IF;
    RETURN QUERY SELECT * FROM public.assignment_feedback_messages WHERE id = saved_message.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.update_assignment_submission_score(
    input_submission_id UUID,
    input_score INTEGER DEFAULT NULL,
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.assignment_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    submission_record public.assignment_submissions%ROWTYPE;
    assignment_record public.assignments%ROWTYPE;
    old_score INTEGER;
    existing_result_id UUID;
    notification_id UUID;
BEGIN
    IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    IF input_score IS NOT NULL AND (input_score < 1 OR input_score > 10) THEN
        RAISE EXCEPTION 'Score must be between 1 and 10';
    END IF;
    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NOT NULL THEN
        PERFORM pg_advisory_xact_lock(hashtextextended(actor::TEXT || ':score:' || btrim(input_idempotency_key), 0));
        SELECT result_id INTO existing_result_id FROM public.assignment_mutation_requests
        WHERE actor_id = actor AND idempotency_key = btrim(input_idempotency_key)
          AND operation = 'score_update';
        IF existing_result_id IS NOT NULL THEN
            RETURN QUERY SELECT * FROM public.assignment_submissions WHERE id = existing_result_id;
            RETURN;
        END IF;
    END IF;

    SELECT * INTO submission_record FROM public.assignment_submissions
    WHERE id = input_submission_id FOR UPDATE;
    IF NOT FOUND THEN RAISE EXCEPTION 'Assignment submission was not found'; END IF;
    SELECT * INTO assignment_record FROM public.assignments WHERE id = submission_record.assignment_id;
    IF assignment_record.assigned_by <> actor THEN
        RAISE EXCEPTION 'Only the assignment creator can update a score';
    END IF;
    IF submission_record.reviewed_at IS NULL THEN
        RAISE EXCEPTION 'A pending submission must be reviewed before its score can be changed';
    END IF;

    old_score := submission_record.score;
    UPDATE public.assignment_submissions SET score = input_score
    WHERE id = input_submission_id RETURNING * INTO submission_record;

    INSERT INTO public.assignment_events (assignment_id, school_id, actor_id, event_type, metadata)
    VALUES (
        assignment_record.id, assignment_record.school_id, actor, 'score_updated',
        jsonb_build_object(
            'submission_id', submission_record.id,
            'recipient_id', submission_record.submitted_by,
            'attempt_number', submission_record.attempt_number,
            'old_score', old_score,
            'new_score', input_score
        )
    );

    INSERT INTO public.notifications (
        school_id, title, body, category, source_type, source_id, created_by, dedupe_key
    ) VALUES (
        assignment_record.school_id, assignment_record.title,
        CASE WHEN input_score IS NULL THEN 'Your score was cleared.' ELSE 'Your score is now ' || input_score::TEXT || '/10.' END,
        'assignment_reviewed', 'assignment', assignment_record.id, actor,
        'assignment:score:' || gen_random_uuid()::TEXT
    ) RETURNING id INTO notification_id;
    INSERT INTO public.notification_recipients (notification_id, user_id)
    VALUES (notification_id, submission_record.submitted_by) ON CONFLICT DO NOTHING;

    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NOT NULL THEN
        INSERT INTO public.assignment_mutation_requests (actor_id, idempotency_key, operation, result_id)
        VALUES (actor, btrim(input_idempotency_key), 'score_update', submission_record.id);
    END IF;
    RETURN QUERY SELECT * FROM public.assignment_submissions WHERE id = submission_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.fetch_my_assignment_agenda_v2(
    input_categories TEXT[] DEFAULT NULL,
    input_archived BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    assignment_id UUID, school_id UUID, school_name TEXT, child_id UUID,
    title TEXT, description TEXT, category TEXT, due_at TIMESTAMPTZ,
    assigned_by UUID, created_at TIMESTAMPTZ, lifecycle_status TEXT,
    completion_status TEXT, viewed_at TIMESTAMPTZ, acknowledged_at TIMESTAMPTZ,
    has_unread_feedback BOOLEAN, submitted_at TIMESTAMPTZ, review_status TEXT,
    reviewed_at TIMESTAMPTZ, reviewer_message TEXT, child_first_name TEXT,
    child_last_name TEXT, material_count BIGINT, submission_count BIGINT,
    recipient_count BIGINT, needs_review_count BIGINT, changes_requested_count BIGINT,
    not_started_count BIGINT, overdue_count BIGINT, complete_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT assignment.id, assignment.school_id, school.name, assignment.child_id,
           assignment.title, assignment.description, assignment.category, assignment.due_at,
           assignment.assigned_by, assignment.created_at, assignment.status,
           recipient.completion_status, recipient.viewed_at, receipt.checked_at,
           EXISTS (
               SELECT 1 FROM public.assignment_feedback_messages feedback
               WHERE feedback.assignment_id = assignment.id
                 AND feedback.recipient_id = auth.uid()
                 AND feedback.sender_id <> auth.uid()
                 AND feedback.created_at > COALESCE(recipient.viewed_at, '-infinity'::TIMESTAMPTZ)
           ),
           latest.submitted_at, latest.status, latest.reviewed_at, latest.reviewer_message,
           child.first_name, child.last_name,
           (SELECT COUNT(*) FROM public.assignment_materials material WHERE material.assignment_id = assignment.id),
           (SELECT COUNT(*) FROM public.assignment_submissions submission WHERE submission.assignment_id = assignment.id AND submission.submitted_by = auth.uid()),
           1::BIGINT, NULL::BIGINT, NULL::BIGINT, NULL::BIGINT, NULL::BIGINT, NULL::BIGINT
    FROM public.assignment_recipients recipient
    JOIN public.assignments assignment ON assignment.id = recipient.assignment_id
    JOIN public.schools school ON school.id = assignment.school_id
    LEFT JOIN public.assignment_read_receipts receipt ON receipt.assignment_id = assignment.id AND receipt.user_id = auth.uid()
    LEFT JOIN LATERAL (
        SELECT submission.submitted_at, submission.status, submission.reviewed_at, submission.reviewer_message
        FROM public.assignment_submissions submission
        WHERE submission.assignment_id = assignment.id AND submission.submitted_by = auth.uid()
        ORDER BY submission.attempt_number DESC, submission.submitted_at DESC LIMIT 1
    ) latest ON TRUE
    LEFT JOIN public.children child ON child.id = assignment.child_id
    WHERE recipient.user_id = auth.uid()
      AND ((input_archived AND assignment.status = 'archived') OR
           (NOT input_archived AND assignment.status IN ('published', 'closed', 'scheduled')))
      AND (assignment.status <> 'scheduled' OR assignment.publish_at <= NOW())
      AND (input_categories IS NULL OR cardinality(input_categories) = 0 OR assignment.category = ANY(input_categories))
    ORDER BY assignment.due_at NULLS LAST, assignment.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.fetch_my_assignment_review_queue_v2(
    input_school_id UUID,
    input_categories TEXT[] DEFAULT NULL,
    input_archived BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    assignment_id UUID, school_id UUID, school_name TEXT, child_id UUID,
    title TEXT, description TEXT, category TEXT, due_at TIMESTAMPTZ,
    assigned_by UUID, created_at TIMESTAMPTZ, lifecycle_status TEXT,
    completion_status TEXT, viewed_at TIMESTAMPTZ, acknowledged_at TIMESTAMPTZ,
    has_unread_feedback BOOLEAN, submitted_at TIMESTAMPTZ, review_status TEXT,
    reviewed_at TIMESTAMPTZ, reviewer_message TEXT, child_first_name TEXT,
    child_last_name TEXT, material_count BIGINT, submission_count BIGINT,
    recipient_count BIGINT, needs_review_count BIGINT, changes_requested_count BIGINT,
    not_started_count BIGINT, overdue_count BIGINT, complete_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    WITH latest AS (
        SELECT DISTINCT ON (assignment_id, submitted_by)
            assignment_id, submitted_by, status, submitted_at, reviewed_at
        FROM public.assignment_submissions
        ORDER BY assignment_id, submitted_by, attempt_number DESC, submitted_at DESC
    )
    SELECT assignment.id, assignment.school_id, school.name, assignment.child_id,
           assignment.title, assignment.description, assignment.category, assignment.due_at,
           assignment.assigned_by, assignment.created_at, assignment.status,
           CASE
               WHEN COUNT(latest.submitted_by) FILTER (WHERE latest.status = 'changes_requested') > 0 THEN 'changes_requested'
               WHEN COUNT(latest.submitted_by) FILTER (WHERE latest.status IN ('submitted', 'resubmitted')) > 0 THEN 'submitted'
               WHEN COUNT(latest.submitted_by) FILTER (WHERE latest.status = 'accepted') = COUNT(DISTINCT recipient.user_id)
                    AND COUNT(DISTINCT recipient.user_id) > 0 THEN 'accepted'
               ELSE 'not_started'
           END,
           NULL::TIMESTAMPTZ, NULL::TIMESTAMPTZ, FALSE, MAX(latest.submitted_at),
           CASE
               WHEN COUNT(latest.submitted_by) FILTER (WHERE latest.status = 'changes_requested') > 0 THEN 'changes_requested'
               WHEN COUNT(latest.submitted_by) FILTER (WHERE latest.status IN ('submitted', 'resubmitted')) > 0 THEN 'submitted'
               WHEN COUNT(latest.submitted_by) FILTER (WHERE latest.status = 'accepted') > 0 THEN 'accepted'
               ELSE NULL
           END,
           MAX(latest.reviewed_at), NULL::TEXT, child.first_name, child.last_name,
           (SELECT COUNT(*) FROM public.assignment_materials material WHERE material.assignment_id = assignment.id),
           COUNT(DISTINCT latest.submitted_by), COUNT(DISTINCT recipient.user_id),
           COUNT(DISTINCT latest.submitted_by) FILTER (WHERE latest.status IN ('submitted', 'resubmitted')),
           COUNT(DISTINCT latest.submitted_by) FILTER (WHERE latest.status = 'changes_requested'),
           COUNT(DISTINCT recipient.user_id) FILTER (WHERE latest.submitted_by IS NULL),
           COUNT(DISTINCT recipient.user_id) FILTER (WHERE assignment.due_at < NOW() AND (latest.submitted_by IS NULL OR latest.status = 'changes_requested')),
           COUNT(DISTINCT latest.submitted_by) FILTER (WHERE latest.status = 'accepted')
    FROM public.assignments assignment
    JOIN public.schools school ON school.id = assignment.school_id
    LEFT JOIN public.assignment_recipients recipient ON recipient.assignment_id = assignment.id
    LEFT JOIN latest ON latest.assignment_id = assignment.id AND latest.submitted_by = recipient.user_id
    LEFT JOIN public.children child ON child.id = assignment.child_id
    WHERE assignment.school_id = input_school_id
      AND assignment.assigned_by = auth.uid()
      AND ((input_archived AND assignment.status = 'archived') OR (NOT input_archived AND assignment.status <> 'archived'))
      AND (input_categories IS NULL OR cardinality(input_categories) = 0 OR assignment.category = ANY(input_categories))
    GROUP BY assignment.id, school.name, child.first_name, child.last_name
    ORDER BY MAX(latest.submitted_at) DESC NULLS LAST, assignment.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.set_assignment_status(
    input_assignment_id UUID,
    input_status TEXT
)
RETURNS SETOF public.assignments
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    assignment_record public.assignments%ROWTYPE;
    previous_status TEXT;
    event_name TEXT;
    notification_id UUID;
BEGIN
    IF actor IS NULL THEN RAISE EXCEPTION 'Authentication required'; END IF;
    IF input_status NOT IN ('published', 'closed', 'archived') THEN
        RAISE EXCEPTION 'Status must be published, closed, or archived';
    END IF;
    SELECT * INTO assignment_record FROM public.assignments
    WHERE id = input_assignment_id FOR UPDATE;
    IF NOT FOUND OR assignment_record.assigned_by <> actor THEN
        RAISE EXCEPTION 'Only the assignment creator can change its lifecycle';
    END IF;
    IF assignment_record.status = input_status THEN
        RETURN QUERY SELECT * FROM public.assignments WHERE id = input_assignment_id; RETURN;
    END IF;
    previous_status := assignment_record.status;
    IF previous_status = 'archived' AND input_status <> 'closed' THEN
        RAISE EXCEPTION 'Archived assignments must be restored to closed';
    END IF;
    IF previous_status = 'closed' AND input_status = 'archived' THEN event_name := 'archived';
    ELSIF previous_status = 'closed' AND input_status = 'published' THEN event_name := 'reopened';
    ELSIF previous_status = 'archived' AND input_status = 'closed' THEN event_name := 'restored';
    ELSE event_name := input_status; END IF;

    UPDATE public.assignments
    SET status = input_status,
        publish_at = CASE WHEN input_status = 'published' THEN COALESCE(publish_at, NOW()) ELSE publish_at END,
        updated_at = NOW()
    WHERE id = input_assignment_id RETURNING * INTO assignment_record;

    INSERT INTO public.assignment_events (assignment_id, school_id, actor_id, event_type, metadata)
    VALUES (assignment_record.id, assignment_record.school_id, actor, event_name,
            jsonb_build_object('previous_status', previous_status, 'new_status', input_status));

    INSERT INTO public.notifications (
        school_id, title, body, category, source_type, source_id, created_by, dedupe_key
    ) VALUES (
        assignment_record.school_id, assignment_record.title,
        CASE event_name
            WHEN 'closed' THEN 'This assignment is now closed and read-only.'
            WHEN 'reopened' THEN 'This assignment has reopened.'
            WHEN 'archived' THEN 'This assignment was archived.'
            WHEN 'restored' THEN 'This assignment was restored as closed.'
            ELSE 'This assignment is now available.'
        END,
        'assignment_lifecycle', 'assignment', assignment_record.id, actor,
        'assignment:lifecycle:' || gen_random_uuid()::TEXT
    ) RETURNING id INTO notification_id;
    INSERT INTO public.notification_recipients (notification_id, user_id)
    SELECT notification_id, recipient.user_id FROM public.assignment_recipients recipient
    WHERE recipient.assignment_id = assignment_record.id ON CONFLICT DO NOTHING;

    RETURN QUERY SELECT * FROM public.assignments WHERE id = assignment_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.submit_assignment_with_payload(
    input_assignment_id UUID,
    input_structured_payload JSONB DEFAULT '{}'::JSONB,
    input_feedback_text TEXT DEFAULT NULL,
    input_attachments JSONB DEFAULT '[]'::JSONB,
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.assignment_submissions
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    saved_submission public.assignment_submissions%ROWTYPE;
    revision_id UUID;
BEGIN
    IF jsonb_typeof(COALESCE(input_structured_payload, '{}'::JSONB)) <> 'object' THEN
        RAISE EXCEPTION 'Structured answers must be a JSON object';
    END IF;
    SELECT current_revision_id INTO revision_id FROM public.assignments WHERE id = input_assignment_id;
    IF revision_id IS NULL THEN revision_id := public.snapshot_assignment_revision(input_assignment_id, auth.uid()); END IF;
    SELECT * INTO saved_submission FROM public.submit_assignment_v2(
        input_assignment_id, input_feedback_text, input_attachments, input_idempotency_key
    );
    UPDATE public.assignment_submissions
    SET structured_payload = CASE
            WHEN structured_payload = '{}'::JSONB THEN COALESCE(input_structured_payload, '{}'::JSONB)
            ELSE structured_payload END,
        assignment_revision_id = COALESCE(assignment_revision_id, revision_id)
    WHERE id = saved_submission.id RETURNING * INTO saved_submission;
    RETURN QUERY SELECT * FROM public.assignment_submissions WHERE id = saved_submission.id;
END;
$$;

-- Compatibility entry points keep older app releases revision-aware and apply
-- the same lifecycle checks as the versioned APIs.
CREATE OR REPLACE FUNCTION public.update_assignment_details(
    input_assignment_id UUID,
    input_title TEXT,
    input_description TEXT DEFAULT NULL,
    input_due_at TIMESTAMPTZ DEFAULT NULL,
    input_allow_resubmission BOOLEAN DEFAULT TRUE
)
RETURNS SETOF public.assignments
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT * FROM public.update_assignment_v2(
        input_assignment_id,
        input_title,
        input_description,
        input_due_at,
        input_allow_resubmission,
        COALESCE((
            SELECT jsonb_agg(jsonb_build_object(
                'material_type', material.material_type,
                'title', material.title,
                'url', material.url,
                'private_file_path', material.private_file_path,
                'file_name', material.file_name,
                'content_type', material.content_type
            ) ORDER BY material.created_at, material.id)
            FROM public.assignment_materials material
            WHERE material.assignment_id = input_assignment_id
        ), '[]'::JSONB)
    );
$$;

CREATE OR REPLACE FUNCTION public.post_assignment_comment(
    input_submission_id UUID,
    input_body TEXT,
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.assignment_feedback_messages
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    submission_record public.assignment_submissions%ROWTYPE;
BEGIN
    SELECT * INTO submission_record
    FROM public.assignment_submissions
    WHERE id = input_submission_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Assignment submission was not found';
    END IF;

    RETURN QUERY
    SELECT * FROM public.post_assignment_comment_v2(
        submission_record.assignment_id,
        submission_record.submitted_by,
        input_body,
        input_idempotency_key
    );
END;
$$;

REVOKE ALL ON FUNCTION public.snapshot_assignment_revision(UUID, UUID) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_assignment_v2(UUID, TEXT, TEXT, TIMESTAMPTZ, BOOLEAN, JSONB) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.post_assignment_comment_v2(UUID, UUID, TEXT, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.update_assignment_submission_score(UUID, INTEGER, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fetch_my_assignment_agenda_v2(TEXT[], BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.fetch_my_assignment_review_queue_v2(UUID, TEXT[], BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.update_assignment_v2(UUID, TEXT, TEXT, TIMESTAMPTZ, BOOLEAN, JSONB) TO authenticated;
GRANT EXECUTE ON FUNCTION public.post_assignment_comment_v2(UUID, UUID, TEXT, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.update_assignment_submission_score(UUID, INTEGER, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_my_assignment_agenda_v2(TEXT[], BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_my_assignment_review_queue_v2(UUID, TEXT[], BOOLEAN) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260728090000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
COMMIT;

-- Migration: 20260728110000_event_creator_profile_visibility.sql

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

-- Migration: 20260728130000_mark_all_notifications_read.sql

-- Mark every visible inbox notification read without dismissing it.
BEGIN;

CREATE OR REPLACE FUNCTION public.mark_all_notifications_read()
RETURNS INTEGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    affected_count INTEGER;
BEGIN
    UPDATE public.notification_recipients
    SET read_at = COALESCE(read_at, NOW()),
        opened_at = COALESCE(opened_at, NOW()),
        delivery_state = CASE
            WHEN delivery_state IN ('acknowledged', 'failed') THEN delivery_state
            ELSE 'opened'
        END
    WHERE user_id = auth.uid()
      AND read_at IS NULL
      AND delivery_state NOT IN ('dismissed', 'expired');

    GET DIAGNOSTICS affected_count = ROW_COUNT;
    RETURN affected_count;
END;
$$;

REVOKE ALL ON FUNCTION public.mark_all_notifications_read() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.mark_all_notifications_read() TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260728130000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
COMMIT;

-- Migration: 20260728140000_onboarding_assignment_access_hardening.sql

-- Onboarding recipients may complete their checklist, but only the role's
-- onboarding manager may edit or change the lifecycle of checklist assignments.
BEGIN;

CREATE OR REPLACE FUNCTION public.can_manage_assignment(assignment_uuid UUID, user_uuid UUID)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM public.assignments assignments
        WHERE assignments.id = assignment_uuid
          AND (
              (
                  assignments.category <> 'onboarding'
                  AND assignments.assigned_by = user_uuid
              )
              OR EXISTS (
                  SELECT 1
                  FROM public.onboarding_requirement_instances requirement_instances
                  JOIN public.onboarding_instances instances
                    ON instances.id = requirement_instances.onboarding_instance_id
                  JOIN public.onboarding_templates templates
                    ON templates.id = instances.template_id
                  WHERE requirement_instances.assignment_id = assignments.id
                    AND public.is_onboarding_template_manager(
                        templates.school_id,
                        templates.target_role,
                        user_uuid
                    )
              )
          )
    );
$$;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260728140000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
COMMIT;

-- Migration: 20260728150000_onboarding_review_queue_authority.sql

-- Keep onboarding review queues aligned with notification/detail authority.
-- The authorized role reviewer may differ from the account that originally
-- published the template and was recorded as assignments.assigned_by.
BEGIN;

CREATE OR REPLACE FUNCTION public.fetch_my_assignment_review_queue_v2(
    input_school_id UUID,
    input_categories TEXT[] DEFAULT NULL,
    input_archived BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    assignment_id UUID, school_id UUID, school_name TEXT, child_id UUID,
    title TEXT, description TEXT, category TEXT, due_at TIMESTAMPTZ,
    assigned_by UUID, created_at TIMESTAMPTZ, lifecycle_status TEXT,
    completion_status TEXT, viewed_at TIMESTAMPTZ, acknowledged_at TIMESTAMPTZ,
    has_unread_feedback BOOLEAN, submitted_at TIMESTAMPTZ, review_status TEXT,
    reviewed_at TIMESTAMPTZ, reviewer_message TEXT, child_first_name TEXT,
    child_last_name TEXT, material_count BIGINT, submission_count BIGINT,
    recipient_count BIGINT, needs_review_count BIGINT, changes_requested_count BIGINT,
    not_started_count BIGINT, overdue_count BIGINT, complete_count BIGINT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
    WITH latest AS (
        SELECT DISTINCT ON (assignment_id, submitted_by)
            assignment_id, submitted_by, status, submitted_at, reviewed_at
        FROM public.assignment_submissions
        ORDER BY assignment_id, submitted_by, attempt_number DESC, submitted_at DESC
    )
    SELECT assignment.id, assignment.school_id, school.name, assignment.child_id,
           assignment.title, assignment.description, assignment.category, assignment.due_at,
           assignment.assigned_by, assignment.created_at, assignment.status,
           CASE
               WHEN COUNT(latest.submitted_by) FILTER (WHERE latest.status = 'changes_requested') > 0 THEN 'changes_requested'
               WHEN COUNT(latest.submitted_by) FILTER (WHERE latest.status IN ('submitted', 'resubmitted')) > 0 THEN 'submitted'
               WHEN COUNT(latest.submitted_by) FILTER (WHERE latest.status = 'accepted') = COUNT(DISTINCT recipient.user_id)
                    AND COUNT(DISTINCT recipient.user_id) > 0 THEN 'accepted'
               ELSE 'not_started'
           END,
           NULL::TIMESTAMPTZ, NULL::TIMESTAMPTZ, FALSE, MAX(latest.submitted_at),
           CASE
               WHEN COUNT(latest.submitted_by) FILTER (WHERE latest.status = 'changes_requested') > 0 THEN 'changes_requested'
               WHEN COUNT(latest.submitted_by) FILTER (WHERE latest.status IN ('submitted', 'resubmitted')) > 0 THEN 'submitted'
               WHEN COUNT(latest.submitted_by) FILTER (WHERE latest.status = 'accepted') > 0 THEN 'accepted'
               ELSE NULL
           END,
           MAX(latest.reviewed_at), NULL::TEXT, child.first_name, child.last_name,
           (SELECT COUNT(*) FROM public.assignment_materials material WHERE material.assignment_id = assignment.id),
           COUNT(DISTINCT latest.submitted_by), COUNT(DISTINCT recipient.user_id),
           COUNT(DISTINCT latest.submitted_by) FILTER (WHERE latest.status IN ('submitted', 'resubmitted')),
           COUNT(DISTINCT latest.submitted_by) FILTER (WHERE latest.status = 'changes_requested'),
           COUNT(DISTINCT recipient.user_id) FILTER (WHERE latest.submitted_by IS NULL),
           COUNT(DISTINCT recipient.user_id) FILTER (
               WHERE assignment.due_at < NOW()
                 AND (latest.submitted_by IS NULL OR latest.status = 'changes_requested')
           ),
           COUNT(DISTINCT latest.submitted_by) FILTER (WHERE latest.status = 'accepted')
    FROM public.assignments assignment
    JOIN public.schools school ON school.id = assignment.school_id
    LEFT JOIN public.assignment_recipients recipient ON recipient.assignment_id = assignment.id
    LEFT JOIN latest ON latest.assignment_id = assignment.id AND latest.submitted_by = recipient.user_id
    LEFT JOIN public.children child ON child.id = assignment.child_id
    WHERE assignment.school_id = input_school_id
      AND public.can_review_assignment(assignment.id, auth.uid())
      AND ((input_archived AND assignment.status = 'archived') OR (NOT input_archived AND assignment.status <> 'archived'))
      AND (input_categories IS NULL OR cardinality(input_categories) = 0 OR assignment.category = ANY(input_categories))
    GROUP BY assignment.id, school.name, child.first_name, child.last_name
    ORDER BY MAX(latest.submitted_at) DESC NULLS LAST, assignment.created_at DESC;
$$;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260728150000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
COMMIT;

-- Migration: 20260728160000_daily_activity_media_evidence.sql

-- Link child-scoped chat media to structured daily activities without copying
-- the attachment or creating a second timeline message. The activity remains
-- the reporting source of truth and the original chat message remains the
-- evidence source visible to the family.
BEGIN;

ALTER TABLE public.child_care_events
    ADD COLUMN IF NOT EXISTS source_message_id UUID,
    ADD COLUMN IF NOT EXISTS developmental_domains TEXT[] NOT NULL DEFAULT ARRAY[]::TEXT[],
    ADD COLUMN IF NOT EXISTS report_highlight BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE public.messages
    ADD COLUMN IF NOT EXISTS linked_care_event_id UUID;

ALTER TABLE public.child_care_events
    DROP CONSTRAINT IF EXISTS child_care_events_source_message_id_fkey;
ALTER TABLE public.child_care_events
    ADD CONSTRAINT child_care_events_source_message_id_fkey
    FOREIGN KEY (source_message_id) REFERENCES public.messages(id) ON DELETE SET NULL;

ALTER TABLE public.messages
    DROP CONSTRAINT IF EXISTS messages_linked_care_event_id_fkey;
ALTER TABLE public.messages
    ADD CONSTRAINT messages_linked_care_event_id_fkey
    FOREIGN KEY (linked_care_event_id) REFERENCES public.child_care_events(id) ON DELETE SET NULL;

ALTER TABLE public.child_care_events
    DROP CONSTRAINT IF EXISTS child_care_events_developmental_domains_check;
ALTER TABLE public.child_care_events
    ADD CONSTRAINT child_care_events_developmental_domains_check CHECK (
        developmental_domains <@ ARRAY[
            'communication_language', 'social_emotional', 'cognitive',
            'physical_motor', 'creative', 'independence_self_care'
        ]::TEXT[]
    );

CREATE UNIQUE INDEX IF NOT EXISTS idx_child_care_events_source_message
    ON public.child_care_events(source_message_id)
    WHERE source_message_id IS NOT NULL;
CREATE UNIQUE INDEX IF NOT EXISTS idx_messages_linked_care_event
    ON public.messages(linked_care_event_id)
    WHERE linked_care_event_id IS NOT NULL;
CREATE INDEX IF NOT EXISTS idx_child_care_events_report_evidence
    ON public.child_care_events(child_id, report_highlight, occurred_at DESC);

CREATE TABLE IF NOT EXISTS public.child_care_event_revisions (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    event_id UUID NOT NULL REFERENCES public.child_care_events(id) ON DELETE RESTRICT,
    school_id UUID NOT NULL REFERENCES public.schools(id) ON DELETE CASCADE,
    child_id UUID NOT NULL REFERENCES public.children(id) ON DELETE CASCADE,
    corrected_by UUID NOT NULL REFERENCES auth.users(id) ON DELETE RESTRICT,
    reason TEXT NOT NULL CHECK (NULLIF(btrim(reason), '') IS NOT NULL),
    previous_snapshot JSONB NOT NULL CHECK (jsonb_typeof(previous_snapshot) = 'object'),
    revised_snapshot JSONB NOT NULL CHECK (jsonb_typeof(revised_snapshot) = 'object'),
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
ALTER TABLE public.child_care_event_revisions ENABLE ROW LEVEL SECURITY;
CREATE INDEX IF NOT EXISTS idx_child_care_event_revisions_event_created
    ON public.child_care_event_revisions(event_id, created_at DESC);

DROP POLICY IF EXISTS "Authorized staff can view care event revisions" ON public.child_care_event_revisions;
CREATE POLICY "Authorized staff can view care event revisions"
    ON public.child_care_event_revisions FOR SELECT
    USING (public.can_staff_access_child(child_id, auth.uid(), ARRAY['teacher', 'school_director']));

CREATE OR REPLACE FUNCTION public.record_child_care_event_v2(
    input_child_id UUID,
    input_event_type TEXT,
    input_occurred_at TIMESTAMPTZ,
    input_details JSONB,
    input_visibility TEXT,
    input_medication_task_id UUID DEFAULT NULL,
    input_idempotency_key TEXT DEFAULT NULL,
    input_source_message_id UUID DEFAULT NULL,
    input_developmental_domains TEXT[] DEFAULT ARRAY[]::TEXT[],
    input_report_highlight BOOLEAN DEFAULT FALSE
)
RETURNS SETOF public.child_care_events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    child_record public.children%ROWTYPE;
    message_record public.messages%ROWTYPE;
    room_record public.chat_rooms%ROWTYPE;
    saved_event public.child_care_events%ROWTYPE;
    guardian_ids UUID[];
    normalized_domains TEXT[] := COALESCE(input_developmental_domains, ARRAY[]::TEXT[]);
BEGIN
    SELECT * INTO child_record
    FROM public.children
    WHERE id = input_child_id AND active = TRUE;
    IF NOT FOUND OR NOT public.can_staff_access_child(input_child_id, actor, ARRAY['teacher', 'school_director']) THEN
        RAISE EXCEPTION 'You cannot record care for this child';
    END IF;
    IF input_event_type NOT IN (
        'meal', 'bottle', 'nap', 'potty', 'diaper', 'medication',
        'health_check', 'activity', 'observation', 'kudos', 'incident',
        'note', 'photo'
    ) THEN RAISE EXCEPTION 'Invalid care event type'; END IF;
    IF input_visibility NOT IN ('parent', 'staff_only') THEN RAISE EXCEPTION 'Invalid visibility'; END IF;
    IF jsonb_typeof(COALESCE(input_details, '{}'::JSONB)) <> 'object' THEN RAISE EXCEPTION 'Details must be an object'; END IF;
    IF NULLIF(btrim(COALESCE(input_idempotency_key, '')), '') IS NULL THEN RAISE EXCEPTION 'An idempotency key is required'; END IF;
    IF NOT normalized_domains <@ ARRAY[
        'communication_language', 'social_emotional', 'cognitive',
        'physical_motor', 'creative', 'independence_self_care'
    ]::TEXT[] THEN RAISE EXCEPTION 'Invalid developmental domain'; END IF;

    IF input_source_message_id IS NOT NULL THEN
        SELECT message.* INTO message_record
        FROM public.messages message
        WHERE message.id = input_source_message_id;
        IF NOT FOUND OR message_record.is_deleted
           OR (message_record.media_path IS NULL AND message_record.media_url IS NULL
               AND message_record.audio_path IS NULL AND message_record.audio_url IS NULL) THEN
            RAISE EXCEPTION 'The source media message is unavailable';
        END IF;
        SELECT * INTO room_record FROM public.chat_rooms WHERE id = message_record.room_id;
        IF NOT FOUND OR room_record.room_type <> 'child_family'
           OR room_record.subject_child_id IS DISTINCT FROM input_child_id
           OR room_record.deleted_at IS NOT NULL OR room_record.archived_at IS NOT NULL
           OR NOT public.is_chat_room_member(room_record.id, actor) THEN
            RAISE EXCEPTION 'The source message is not in this child family room';
        END IF;
        IF message_record.sender_id <> actor
           AND NOT public.has_school_role(child_record.school_id, actor, ARRAY['school_director']) THEN
            RAISE EXCEPTION 'Only the sender or school director can label this media';
        END IF;
        IF input_visibility <> 'parent' THEN
            RAISE EXCEPTION 'Family chat media can only be linked to a parent-visible activity';
        END IF;
    END IF;

    IF input_event_type = 'photo' AND (
        NULLIF(btrim(COALESCE(input_details->>'photo_path', '')), '') IS NULL
        OR input_details->>'photo_path' NOT LIKE (
            'schools/' || child_record.school_id::TEXT || '/care_events/' || input_child_id::TEXT
            || '/' || input_visibility || '/' || actor::TEXT || '/%'
        )
    ) THEN RAISE EXCEPTION 'Photo care events require a private photo uploaded by the recording staff member'; END IF;

    INSERT INTO public.child_care_events (
        school_id, child_id, event_type, occurred_at, details, visibility,
        recorded_by, source_medication_task_id, idempotency_key,
        source_message_id, developmental_domains, report_highlight
    ) VALUES (
        child_record.school_id, input_child_id, input_event_type,
        COALESCE(input_occurred_at, NOW()), COALESCE(input_details, '{}'::JSONB),
        input_visibility, actor, input_medication_task_id, btrim(input_idempotency_key),
        input_source_message_id, normalized_domains, COALESCE(input_report_highlight, FALSE)
    )
    ON CONFLICT (recorded_by, idempotency_key)
    DO UPDATE SET idempotency_key = EXCLUDED.idempotency_key
    RETURNING * INTO saved_event;

    IF saved_event.child_id IS DISTINCT FROM input_child_id
       OR saved_event.event_type IS DISTINCT FROM input_event_type
       OR saved_event.source_message_id IS DISTINCT FROM input_source_message_id THEN
        RAISE EXCEPTION 'The idempotency key was already used for a different care event';
    END IF;

    IF input_event_type = 'medication' THEN
        IF input_medication_task_id IS NULL OR NOT EXISTS (
            SELECT 1 FROM public.medication_tasks task
            JOIN public.medication_instructions instruction ON instruction.id = task.instruction_id
            WHERE task.id = input_medication_task_id
              AND task.child_id = input_child_id
              AND instruction.source_assignment_submission_id IS NOT NULL
        ) THEN RAISE EXCEPTION 'Medication care requires an approved authorization task'; END IF;
        UPDATE public.medication_tasks SET status = 'acknowledged' WHERE id = input_medication_task_id;
        INSERT INTO public.medication_acknowledgements (
            task_id, school_id, child_id, acknowledged_by, dosage_given, notes, given_at
        )
        SELECT input_medication_task_id, child_record.school_id, input_child_id, actor,
            NULLIF(input_details->>'dosage_given', ''), NULLIF(input_details->>'notes', ''), saved_event.occurred_at
        WHERE NOT EXISTS (
            SELECT 1 FROM public.medication_acknowledgements WHERE task_id = input_medication_task_id
        );
    END IF;

    IF input_visibility = 'parent' AND input_event_type IN ('medication', 'health_check', 'incident') THEN
        SELECT array_agg(guardian.guardian_id) INTO guardian_ids
        FROM public.child_guardians guardian
        WHERE guardian.child_id = input_child_id
          AND guardian.verification_status = 'verified' AND guardian.ended_at IS NULL;
        PERFORM public.enqueue_workflow_notification(
            child_record.school_id,
            CASE
                WHEN input_event_type = 'medication' THEN 'Medication administered'
                WHEN input_event_type = 'incident' THEN 'Incident update'
                ELSE 'Health update'
            END,
            child_record.first_name || ' has a new ' || replace(input_event_type, '_', ' ') || ' update.',
            'care_' || input_event_type, 'child_care_event', saved_event.id,
            guardian_ids, 'care:' || input_event_type || ':' || saved_event.id::TEXT,
            CASE WHEN input_event_type IN ('health_check', 'incident') THEN 'urgent' ELSE 'important' END,
            jsonb_build_object('type', 'child_care_event', 'id', saved_event.id, 'child_id', input_child_id), actor
        );
    END IF;

    INSERT INTO public.workflow_audit_events (school_id, actor_id, event_type, source_type, source_id)
    VALUES (
        child_record.school_id, actor,
        CASE WHEN input_source_message_id IS NULL THEN 'recorded' ELSE 'recorded_from_chat_media' END,
        'child_care_event', saved_event.id
    );
    RETURN QUERY SELECT * FROM public.child_care_events WHERE id = saved_event.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.label_chat_message_as_activity(
    input_message_id UUID,
    input_event_type TEXT,
    input_summary TEXT DEFAULT NULL,
    input_developmental_domains TEXT[] DEFAULT ARRAY[]::TEXT[],
    input_report_highlight BOOLEAN DEFAULT TRUE,
    input_idempotency_key TEXT DEFAULT NULL
)
RETURNS SETOF public.child_care_events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    message_record public.messages%ROWTYPE;
    room_record public.chat_rooms%ROWTYPE;
    existing_event public.child_care_events%ROWTYPE;
    details JSONB;
BEGIN
    IF input_event_type NOT IN ('activity', 'observation', 'kudos', 'note') THEN
        RAISE EXCEPTION 'Chat media can only be labeled as a learning activity, observation, milestone, or note';
    END IF;
    SELECT * INTO message_record FROM public.messages WHERE id = input_message_id;
    IF NOT FOUND THEN RAISE EXCEPTION 'The source media message is unavailable'; END IF;
    SELECT * INTO room_record FROM public.chat_rooms WHERE id = message_record.room_id;
    IF NOT FOUND OR room_record.room_type <> 'child_family'
       OR room_record.subject_child_id IS NULL
       OR room_record.deleted_at IS NOT NULL OR room_record.archived_at IS NOT NULL
       OR NOT public.is_chat_room_member(room_record.id, actor)
       OR NOT public.can_staff_access_child(
           room_record.subject_child_id, actor, ARRAY['teacher', 'school_director']
       ) THEN
        RAISE EXCEPTION 'The source message is not in a child family room';
    END IF;
    IF message_record.sender_id <> actor
       AND NOT public.has_school_role(room_record.school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only the sender or school director can label this media';
    END IF;
    IF message_record.linked_care_event_id IS NOT NULL THEN
        RETURN QUERY SELECT * FROM public.child_care_events WHERE id = message_record.linked_care_event_id;
        RETURN;
    END IF;
    details := jsonb_strip_nulls(jsonb_build_object(
        'summary', NULLIF(btrim(COALESCE(input_summary, '')), ''),
        'attachment_name', message_record.attachment_name,
        'media_kind', CASE
            WHEN message_record.audio_path IS NOT NULL OR message_record.audio_url IS NOT NULL THEN 'audio'
            WHEN COALESCE(message_record.attachment_type, '') LIKE 'video/%' THEN 'video'
            ELSE 'photo'
        END
    ));
    SELECT * INTO existing_event
    FROM public.record_child_care_event_v2(
        room_record.subject_child_id, input_event_type, message_record.created_at,
        details, 'parent', NULL, input_idempotency_key, input_message_id,
        input_developmental_domains, input_report_highlight
    ) LIMIT 1;
    RETURN QUERY SELECT * FROM public.child_care_events WHERE id = existing_event.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.correct_linked_child_activity(
    input_event_id UUID,
    input_event_type TEXT,
    input_summary TEXT DEFAULT NULL,
    input_developmental_domains TEXT[] DEFAULT ARRAY[]::TEXT[],
    input_report_highlight BOOLEAN DEFAULT TRUE,
    input_reason TEXT DEFAULT 'Updated linked activity label'
)
RETURNS SETOF public.child_care_events
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    actor UUID := auth.uid();
    event_record public.child_care_events%ROWTYPE;
    previous_snapshot JSONB;
    revised_details JSONB;
    normalized_domains TEXT[] := COALESCE(input_developmental_domains, ARRAY[]::TEXT[]);
BEGIN
    SELECT * INTO event_record FROM public.child_care_events WHERE id = input_event_id FOR UPDATE;
    IF NOT FOUND OR event_record.source_message_id IS NULL THEN
        RAISE EXCEPTION 'The linked daily activity was not found';
    END IF;
    IF NOT public.can_staff_access_child(
        event_record.child_id, actor, ARRAY['teacher', 'school_director']
    ) THEN
        RAISE EXCEPTION 'You cannot correct care for this child';
    END IF;
    IF event_record.recorded_by <> actor
       AND NOT public.has_school_role(event_record.school_id, actor, ARRAY['school_director']) THEN
        RAISE EXCEPTION 'Only the recorder or school director can correct this activity';
    END IF;
    IF input_event_type NOT IN ('activity', 'observation', 'kudos', 'note') THEN
        RAISE EXCEPTION 'Invalid linked activity type';
    END IF;
    IF NOT normalized_domains <@ ARRAY[
        'communication_language', 'social_emotional', 'cognitive',
        'physical_motor', 'creative', 'independence_self_care'
    ]::TEXT[] THEN RAISE EXCEPTION 'Invalid developmental domain'; END IF;
    IF NULLIF(btrim(COALESCE(input_reason, '')), '') IS NULL THEN
        RAISE EXCEPTION 'A correction reason is required';
    END IF;

    previous_snapshot := to_jsonb(event_record);
    revised_details := (event_record.details - 'summary') || CASE
        WHEN NULLIF(btrim(COALESCE(input_summary, '')), '') IS NULL THEN '{}'::JSONB
        ELSE jsonb_build_object('summary', btrim(input_summary))
    END;
    UPDATE public.child_care_events
    SET event_type = input_event_type,
        details = revised_details,
        developmental_domains = normalized_domains,
        report_highlight = COALESCE(input_report_highlight, FALSE)
    WHERE id = input_event_id
    RETURNING * INTO event_record;

    INSERT INTO public.child_care_event_revisions (
        event_id, school_id, child_id, corrected_by, reason,
        previous_snapshot, revised_snapshot
    ) VALUES (
        event_record.id, event_record.school_id, event_record.child_id, actor,
        btrim(input_reason), previous_snapshot, to_jsonb(event_record)
    );
    INSERT INTO public.workflow_audit_events (school_id, actor_id, event_type, source_type, source_id)
    VALUES (event_record.school_id, actor, 'corrected', 'child_care_event', event_record.id);
    RETURN QUERY SELECT * FROM public.child_care_events WHERE id = event_record.id;
END;
$$;

CREATE OR REPLACE FUNCTION public.append_structured_child_timeline_entry()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
    target_room_id UUID;
    source_kind TEXT;
    source_id UUID;
    source_school_id UUID;
    source_child_id UUID;
    source_sender_id UUID;
    source_created_at TIMESTAMPTZ;
    source_label TEXT;
BEGIN
    IF TG_TABLE_NAME = 'child_care_events' THEN
        IF NEW.visibility <> 'parent' THEN RETURN NEW; END IF;
        IF NEW.source_message_id IS NOT NULL THEN
            UPDATE public.messages
            SET linked_care_event_id = NEW.id
            WHERE id = NEW.source_message_id;
            RETURN NEW;
        END IF;
        source_kind := 'care_event';
        source_id := NEW.id;
        source_school_id := NEW.school_id;
        source_child_id := NEW.child_id;
        source_sender_id := NEW.recorded_by;
        source_created_at := NEW.occurred_at;
        source_label := CASE NEW.event_type
            WHEN 'meal' THEN 'Meal update'
            WHEN 'bottle' THEN 'Bottle update'
            WHEN 'nap' THEN 'Nap update'
            WHEN 'potty' THEN 'Toileting update'
            WHEN 'diaper' THEN 'Diaper update'
            WHEN 'medication' THEN 'Medication administration'
            WHEN 'health_check' THEN 'Health observation'
            WHEN 'activity' THEN 'Learning activity'
            WHEN 'observation' THEN 'Child observation'
            WHEN 'kudos' THEN 'Kudos and milestone'
            WHEN 'incident' THEN 'Incident update'
            WHEN 'photo' THEN 'Photo update'
            ELSE 'Care note'
        END;
        source_label := source_label || COALESCE(
            ' — ' || NULLIF(concat_ws(
                ' • ', NULLIF(NEW.details->>'summary', ''),
                NULLIF(NEW.details->>'amount', ''), NULLIF(NEW.details->>'outcome', ''),
                NULLIF(NEW.details->>'dosage_given', '')
            ), ''), ''
        );
    ELSIF TG_TABLE_NAME = 'family_requests' THEN
        source_kind := 'family_request';
        source_id := NEW.id;
        source_school_id := NEW.school_id;
        source_child_id := NEW.child_id;
        source_sender_id := NEW.requested_by;
        source_created_at := NEW.created_at;
        source_label := CASE NEW.request_type
            WHEN 'absence' THEN 'Absence request'
            WHEN 'pickup_change' THEN 'Pickup change request'
            WHEN 'medication' THEN 'Medication question'
            ELSE 'Family request'
        END;
        source_label := source_label || COALESCE(' — ' || NULLIF(NEW.details->>'message', ''), '');
    ELSE
        RETURN NEW;
    END IF;

    SELECT room.id INTO target_room_id
    FROM public.chat_rooms room
    WHERE room.school_id = source_school_id
      AND room.subject_child_id = source_child_id
      AND room.room_type = 'child_family'
      AND room.deleted_at IS NULL AND room.archived_at IS NULL
    LIMIT 1;
    IF target_room_id IS NULL THEN RETURN NEW; END IF;

    INSERT INTO public.messages (
        room_id, school_id, sender_id, text, entry_kind,
        structured_source_type, structured_source_id, created_at, is_deleted
    ) VALUES (
        target_room_id, source_school_id, source_sender_id, source_label,
        source_kind, TG_TABLE_NAME, source_id, source_created_at, FALSE
    )
    ON CONFLICT (structured_source_type, structured_source_id)
        WHERE structured_source_id IS NOT NULL
    DO NOTHING;
    RETURN NEW;
END;
$$;

CREATE OR REPLACE FUNCTION public.guard_linked_activity_message_mutation()
RETURNS TRIGGER
LANGUAGE plpgsql
SET search_path = public
AS $$
BEGIN
    IF OLD.linked_care_event_id IS NOT NULL
       AND OLD.is_deleted = FALSE AND NEW.is_deleted = TRUE THEN
        RAISE EXCEPTION 'A message saved to the daily log cannot be deleted';
    END IF;
    IF OLD.linked_care_event_id IS NOT NULL
       AND NEW.linked_care_event_id IS DISTINCT FROM OLD.linked_care_event_id THEN
        RAISE EXCEPTION 'A daily log evidence link cannot be changed';
    END IF;
    IF OLD.linked_care_event_id IS NOT NULL AND (
        NEW.room_id IS DISTINCT FROM OLD.room_id
        OR NEW.school_id IS DISTINCT FROM OLD.school_id
        OR NEW.sender_id IS DISTINCT FROM OLD.sender_id
        OR NEW.created_at IS DISTINCT FROM OLD.created_at
        OR NEW.media_path IS DISTINCT FROM OLD.media_path
        OR NEW.media_url IS DISTINCT FROM OLD.media_url
        OR NEW.audio_path IS DISTINCT FROM OLD.audio_path
        OR NEW.audio_url IS DISTINCT FROM OLD.audio_url
        OR NEW.attachment_type IS DISTINCT FROM OLD.attachment_type
        OR NEW.attachment_name IS DISTINCT FROM OLD.attachment_name
        OR NEW.attachment_size IS DISTINCT FROM OLD.attachment_size
    ) THEN
        RAISE EXCEPTION 'Daily log evidence cannot be altered';
    END IF;
    IF OLD.linked_care_event_id IS NULL AND NEW.linked_care_event_id IS NOT NULL
       AND NOT EXISTS (
           SELECT 1
           FROM public.child_care_events event
           WHERE event.id = NEW.linked_care_event_id
             AND event.source_message_id = OLD.id
       ) THEN
        RAISE EXCEPTION 'The daily log evidence link is invalid';
    END IF;
    RETURN NEW;
END;
$$;
DROP TRIGGER IF EXISTS guard_linked_activity_message_deletion_trigger ON public.messages;
DROP TRIGGER IF EXISTS guard_linked_activity_message_mutation_trigger ON public.messages;
CREATE TRIGGER guard_linked_activity_message_mutation_trigger
    BEFORE UPDATE ON public.messages
    FOR EACH ROW EXECUTE FUNCTION public.guard_linked_activity_message_mutation();

REVOKE ALL ON FUNCTION public.record_child_care_event_v2(UUID, TEXT, TIMESTAMPTZ, JSONB, TEXT, UUID, TEXT, UUID, TEXT[], BOOLEAN) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.label_chat_message_as_activity(UUID, TEXT, TEXT, TEXT[], BOOLEAN, TEXT) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.correct_linked_child_activity(UUID, TEXT, TEXT, TEXT[], BOOLEAN, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.record_child_care_event_v2(UUID, TEXT, TIMESTAMPTZ, JSONB, TEXT, UUID, TEXT, UUID, TEXT[], BOOLEAN) TO authenticated;
GRANT EXECUTE ON FUNCTION public.label_chat_message_as_activity(UUID, TEXT, TEXT, TEXT[], BOOLEAN, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.correct_linked_child_activity(UUID, TEXT, TEXT, TEXT[], BOOLEAN, TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260728160000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
COMMIT;

-- Migration: 20260730123000_redact_deleted_chat_notifications.sql

BEGIN;

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
        SET body = 'Message deleted'
        WHERE category = 'chat_message'
          AND dedupe_key = 'chat:message:' || NEW.id::TEXT
          AND body IS DISTINCT FROM 'Message deleted';
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS redact_deleted_chat_message_notification_trigger ON public.messages;
CREATE TRIGGER redact_deleted_chat_message_notification_trigger
    AFTER UPDATE OF is_deleted, deleted_at ON public.messages
    FOR EACH ROW EXECUTE FUNCTION public.redact_deleted_chat_message_notification();

-- Redact previews for messages that were deleted before this trigger existed.
UPDATE public.notifications notification
SET body = 'Message deleted'
FROM public.messages message
WHERE (COALESCE(message.is_deleted, FALSE) OR message.deleted_at IS NOT NULL)
  AND notification.category = 'chat_message'
  AND notification.dedupe_key = 'chat:message:' || message.id::TEXT
  AND notification.body IS DISTINCT FROM 'Message deleted';

REVOKE ALL ON FUNCTION public.redact_deleted_chat_message_notification() FROM PUBLIC;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260730123000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
COMMIT;

-- Migration: 20260730180000_activity_push_notifications.sql

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
REVOKE ALL ON FUNCTION public.mark_notification_thread_read(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.publish_community_album(UUID, UUID, TEXT, TEXT, TEXT, JSONB, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.append_community_album_media(UUID, JSONB, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.publish_community_post(UUID, UUID, TEXT, TEXT, TEXT, TEXT, TEXT, UUID, TEXT, JSONB, TIMESTAMPTZ, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.publish_newsletter(UUID, UUID, TEXT, TEXT, JSONB, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.fetch_my_notifications(INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION public.mark_notification_thread_read(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_transactional_notification(UUID, TEXT, TEXT, TEXT, TEXT, UUID, UUID[], TEXT) TO authenticated;

CREATE OR REPLACE FUNCTION public.get_firefly_schema_version()
RETURNS BIGINT LANGUAGE sql STABLE SECURITY DEFINER SET search_path = public
AS $$ SELECT 20260730180000::BIGINT; $$;

NOTIFY pgrst, 'reload schema';
COMMIT;
