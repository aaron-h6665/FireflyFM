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
    status TEXT DEFAULT 'active' CHECK (status IN ('draft', 'active', 'archived')),
    visibility TEXT DEFAULT 'assigned' CHECK (visibility IN ('assigned', 'school_staff', 'school')),
    requires_review BOOLEAN DEFAULT TRUE,
    allow_resubmission BOOLEAN DEFAULT TRUE,
    legacy_source_type TEXT,
    legacy_source_id UUID,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ
);

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
    token TEXT UNIQUE NOT NULL DEFAULT replace(gen_random_uuid()::TEXT, '-', ''),
    status TEXT DEFAULT 'pending' CHECK (status IN ('pending', 'accepted', 'revoked', 'expired')),
    invited_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    accepted_by UUID REFERENCES auth.users(id) ON DELETE SET NULL,
    accepted_at TIMESTAMPTZ,
    expires_at TIMESTAMPTZ DEFAULT (NOW() + INTERVAL '14 days'),
    created_at TIMESTAMPTZ DEFAULT NOW()
);

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
    status TEXT DEFAULT 'needs_setup' CHECK (status IN ('needs_setup', 'submitted', 'verified', 'flagged')),
    notes TEXT,
    updated_at TIMESTAMPTZ DEFAULT NOW(),
    created_at TIMESTAMPTZ DEFAULT NOW(),
    UNIQUE (school_id, user_id, payment_type)
);

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
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF NOT public.is_hq_director(actor) THEN
        RAISE EXCEPTION 'Only headquarter directors can create schools';
    END IF;

    IF NULLIF(TRIM(input_school_name), '') IS NULL THEN
        RAISE EXCEPTION 'School name is required';
    END IF;

    IF NULLIF(TRIM(input_director_email), '') IS NULL THEN
        RAISE EXCEPTION 'Director email is required';
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
        invited_by
    )
    VALUES (
        created_school.id,
        lower(TRIM(input_director_email)),
        NULLIF(TRIM(input_director_name), ''),
        'school_director',
        actor
    )
    RETURNING * INTO created_invite;

    school_id := created_school.id;
    school_name := created_school.name;
    invite_token := created_invite.token;
    invite_url := 'fireflyfm://role-invite?token=' || created_invite.token;
    RETURN NEXT;
END;
$$;

GRANT EXECUTE ON FUNCTION public.create_school_with_director_invite(TEXT, TEXT, TEXT) TO authenticated;

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
            'chat_rooms', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.chat_rooms t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'messages', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.messages t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'newsletters', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.newsletters t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'events', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.school_events t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'notifications', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.notifications t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'children', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.children t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'paperwork_assignments', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.paperwork_assignments t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'paperwork_submissions', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.paperwork_submissions t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'curriculum_resources', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.curriculum_resources t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'training_assignments', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.training_assignments t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'community_posts', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.community_posts t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'community_albums', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.community_albums t WHERE t.school_id = school_record.id), '[]'::jsonb),
            'community_album_media', COALESCE((SELECT jsonb_agg(to_jsonb(t)) FROM public.community_album_media t WHERE t.school_id = school_record.id), '[]'::jsonb),
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
    WHERE token = NULLIF(TRIM(invite_token), '')
      AND status = 'pending'
      AND (expires_at IS NULL OR expires_at > NOW())
    LIMIT 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Invalid or expired invite link';
    END IF;

    IF lower(invite_record.email) <> joining_email THEN
        RAISE EXCEPTION 'This invite was issued to %, but you are signed in as %', invite_record.email, joining_email;
    END IF;

    INSERT INTO public.school_memberships (school_id, user_id, role, active, joined_at)
    VALUES (invite_record.school_id, joining_user, invite_record.role, TRUE, NOW())
    ON CONFLICT (school_id, user_id)
    DO UPDATE SET active = TRUE, role = EXCLUDED.role, joined_at = NOW();

    UPDATE public.role_invites
    SET status = 'accepted',
        accepted_by = joining_user,
        accepted_at = NOW()
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
    input_materials JSONB DEFAULT '[]'::JSONB
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
BEGIN
    actor := auth.uid();
    IF actor IS NULL THEN
        RAISE EXCEPTION 'Authentication required';
    END IF;

    IF input_title IS NULL OR btrim(input_title) = '' THEN
        RAISE EXCEPTION 'Assignment title is required';
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

    INSERT INTO public.assignments (
        school_id,
        child_id,
        title,
        description,
        category,
        audience_role,
        assigned_by,
        due_at,
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
        'active',
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
      AND assignment_recipients.user_id <> actor
    ON CONFLICT DO NOTHING;

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

CREATE OR REPLACE FUNCTION public.fetch_assignment_review_queue(
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
GRANT EXECUTE ON FUNCTION public.create_assignment(UUID, TEXT, TEXT, TEXT, TEXT, UUID, TIMESTAMPTZ, BOOLEAN, UUID[], JSONB) TO authenticated;
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
ON CONFLICT (assignment_id, submitted_by) DO UPDATE SET
    status = EXCLUDED.status,
    reviewer_message = EXCLUDED.reviewer_message,
    reviewed_by = EXCLUDED.reviewed_by,
    reviewed_at = EXCLUDED.reviewed_at,
    submitted_at = EXCLUDED.submitted_at;

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
ON CONFLICT (assignment_id, submitted_by) DO UPDATE SET
    status = EXCLUDED.status,
    reviewer_message = EXCLUDED.reviewer_message,
    reviewed_by = EXCLUDED.reviewed_by,
    reviewed_at = EXCLUDED.reviewed_at,
    submitted_at = EXCLUDED.submitted_at;

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
ON CONFLICT (assignment_id, submitted_by) DO UPDATE SET
    status = EXCLUDED.status,
    reviewer_message = EXCLUDED.reviewer_message,
    reviewed_by = EXCLUDED.reviewed_by,
    reviewed_at = EXCLUDED.reviewed_at,
    submitted_at = EXCLUDED.submitted_at;

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
            RETURN public.has_school_role(school_uuid, user_uuid, ARRAY['school_director', 'hq_director']);
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

-- Make newly created/updated RPC functions visible to PostgREST immediately.
NOTIFY pgrst, 'reload schema';
