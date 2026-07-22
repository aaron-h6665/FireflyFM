BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(6);

INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
    ('10000000-0000-0000-0000-000000000031', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'inbox-one@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000032', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'inbox-two@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW());

INSERT INTO public.schools (id, name)
VALUES ('20000000-0000-0000-0000-000000000031', 'Notification Test School');

INSERT INTO public.notifications (id, school_id, title, body, category)
VALUES
    ('30000000-0000-0000-0000-000000000031', '20000000-0000-0000-0000-000000000031', 'First', 'First body', 'school_announcement'),
    ('30000000-0000-0000-0000-000000000032', '20000000-0000-0000-0000-000000000031', 'Second', 'Second body', 'school_announcement');

INSERT INTO public.notification_recipients (notification_id, user_id)
VALUES
    ('30000000-0000-0000-0000-000000000031', '10000000-0000-0000-0000-000000000031'),
    ('30000000-0000-0000-0000-000000000031', '10000000-0000-0000-0000-000000000032'),
    ('30000000-0000-0000-0000-000000000032', '10000000-0000-0000-0000-000000000031'),
    ('30000000-0000-0000-0000-000000000032', '10000000-0000-0000-0000-000000000032');

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000031', TRUE);
SELECT set_config(
    'request.jwt.claims',
    '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000031"}',
    TRUE
);

SELECT lives_ok(
    $$SELECT public.dismiss_notification('30000000-0000-0000-0000-000000000031')$$,
    'a recipient can dismiss one notification'
);

RESET ROLE;
SELECT is(
    (SELECT delivery_state FROM public.notification_recipients
     WHERE notification_id = '30000000-0000-0000-0000-000000000031'
       AND user_id = '10000000-0000-0000-0000-000000000031'),
    'dismissed',
    'dismiss preserves the caller receipt with dismissed delivery state'
);
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.notifications
     WHERE id = '30000000-0000-0000-0000-000000000031'),
    1,
    'dismiss keeps the shared notification record'
);
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.notification_recipients
     WHERE notification_id = '30000000-0000-0000-0000-000000000031'
       AND user_id = '10000000-0000-0000-0000-000000000032'),
    1,
    'dismiss keeps another recipient inbox intact'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000031', TRUE);
SELECT set_config(
    'request.jwt.claims',
    '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000031"}',
    TRUE
);

SELECT is(
    public.clear_my_notifications(),
    1,
    'clear all removes every remaining receipt for the caller'
);

RESET ROLE;
SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.notification_recipients
     WHERE user_id = '10000000-0000-0000-0000-000000000032'),
    2,
    'clear all keeps every other recipient inbox intact'
);

SELECT * FROM finish();
ROLLBACK;
