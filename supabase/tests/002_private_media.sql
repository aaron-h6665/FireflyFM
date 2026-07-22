BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(17);

INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
    ('50000000-0000-0000-0000-000000000001', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'owner@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('50000000-0000-0000-0000-000000000002', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'participant@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('50000000-0000-0000-0000-000000000003', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'outsider@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('50000000-0000-0000-0000-000000000004', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'hq@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW());

INSERT INTO public.schools (id, name)
VALUES ('60000000-0000-0000-0000-000000000001', 'Private Media School');
INSERT INTO public.school_memberships (school_id, user_id, role, active, access_state) VALUES
    ('60000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001', 'parent', TRUE, 'full'),
    ('60000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000002', 'teacher', TRUE, 'full'),
    ('60000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000004', 'hq_director', TRUE, 'full');
INSERT INTO public.chat_rooms (id, school_id, name, created_by)
VALUES ('70000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', 'Private Room', '50000000-0000-0000-0000-000000000001');
INSERT INTO public.chat_participants (room_id, user_id) VALUES
    ('70000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001'),
    ('70000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000002');
INSERT INTO public.children (id, school_id, first_name, last_name, birthdate)
VALUES ('80000000-0000-0000-0000-000000000001', '60000000-0000-0000-0000-000000000001', 'Private', 'Child', '2021-01-10');
INSERT INTO public.child_guardians (child_id, guardian_id, relationship)
VALUES ('80000000-0000-0000-0000-000000000001', '50000000-0000-0000-0000-000000000001', 'Parent');
INSERT INTO storage.objects (bucket_id, name)
VALUES (
    'school_private_files',
    'schools/60000000-0000-0000-0000-000000000001/chat_rooms/70000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/images/photo.jpg'
);

SELECT ok(
    public.can_access_school_private_file(
        'schools/60000000-0000-0000-0000-000000000001/chat_rooms/70000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/images/photo.jpg',
        '50000000-0000-0000-0000-000000000001'
    ), 'uploader can read room media'
);
SELECT ok(
    public.can_access_school_private_file(
        'schools/60000000-0000-0000-0000-000000000001/chat_rooms/70000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/images/photo.jpg',
        '50000000-0000-0000-0000-000000000002'
    ), 'room participant can read room media'
);
SELECT isnt(
    public.can_access_school_private_file(
        'schools/60000000-0000-0000-0000-000000000001/chat_rooms/70000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/images/photo.jpg',
        '50000000-0000-0000-0000-000000000003'
    ), TRUE, 'outsider cannot read room media'
);
SELECT isnt(
    public.can_access_school_private_file(
        'schools/60000000-0000-0000-0000-000000000001/chat_rooms/70000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/images/photo.jpg',
        '50000000-0000-0000-0000-000000000004'
    ), TRUE, 'HQ status alone does not grant room-media access'
);
SELECT isnt(
    public.can_access_school_private_file(
        'schools/60000000-0000-0000-0000-000000000001/chat_rooms/70000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/images/photo.jpg',
        NULL
    ), TRUE, 'anonymous access is denied'
);
SELECT ok(
    public.can_write_school_private_file(
        'schools/60000000-0000-0000-0000-000000000001/chat_rooms/70000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/images/photo.jpg',
        '50000000-0000-0000-0000-000000000001'
    ), 'uploader can write their own path'
);
SELECT isnt(
    public.can_write_school_private_file(
        'schools/60000000-0000-0000-0000-000000000001/chat_rooms/70000000-0000-0000-0000-000000000001/50000000-0000-0000-0000-000000000001/images/photo.jpg',
        '50000000-0000-0000-0000-000000000002'
    ), TRUE, 'another participant cannot overwrite the uploader path'
);
SELECT ok(
    public.can_write_profile_asset(
        'users/50000000-0000-0000-0000-000000000001/avatars/avatar.jpg',
        '50000000-0000-0000-0000-000000000001'
    ), 'profile owner can write their avatar path'
);
SELECT isnt(
    public.can_write_profile_asset(
        'users/50000000-0000-0000-0000-000000000001/avatars/avatar.jpg',
        '50000000-0000-0000-0000-000000000002'
    ), TRUE, 'another user cannot overwrite an avatar'
);
SELECT ok(
    public.can_view_profile_asset(
        'users/50000000-0000-0000-0000-000000000001/avatars/avatar.jpg',
        '50000000-0000-0000-0000-000000000002'
    ), 'a shared-school participant can view an avatar'
);
SELECT isnt(
    public.can_view_profile_asset(
        'users/50000000-0000-0000-0000-000000000001/avatars/avatar.jpg',
        '50000000-0000-0000-0000-000000000003'
    ), TRUE, 'an unrelated user cannot view an avatar'
);
SELECT ok(
    public.can_access_child(
        '80000000-0000-0000-0000-000000000001',
        '50000000-0000-0000-0000-000000000001'
    ), 'a guardian can access their child record'
);
SELECT isnt(
    public.can_access_child(
        '80000000-0000-0000-0000-000000000001',
        '50000000-0000-0000-0000-000000000003'
    ), TRUE, 'an unrelated account cannot access child or medical data'
);

SET LOCAL ROLE authenticated;
SELECT set_config(
    'request.jwt.claims',
    '{"role":"authenticated","sub":"50000000-0000-0000-0000-000000000002","email":"participant@test.fireflyfm.local"}',
    TRUE
);
SELECT is(
    (SELECT COUNT(*) FROM storage.objects WHERE bucket_id = 'school_private_files'),
    1::BIGINT,
    'room participants can read room objects through storage RLS'
);
SELECT set_config(
    'request.jwt.claims',
    '{"role":"authenticated","sub":"50000000-0000-0000-0000-000000000003","email":"outsider@test.fireflyfm.local"}',
    TRUE
);
SELECT is(
    (SELECT COUNT(*) FROM storage.objects WHERE bucket_id = 'school_private_files'),
    0::BIGINT,
    'nonparticipants cannot read room objects through storage RLS'
);
RESET ROLE;

SET LOCAL ROLE anon;
SELECT set_config('request.jwt.claims', '{"role":"anon"}', TRUE);
SELECT is(
    (SELECT COUNT(*) FROM public.children),
    0::BIGINT,
    'anonymous users cannot read school child records through RLS'
);
SELECT is(
    (SELECT COUNT(*) FROM storage.objects WHERE bucket_id IN ('school_private_files', 'profile_assets')),
    0::BIGINT,
    'anonymous users cannot read private objects through storage RLS'
);
RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
