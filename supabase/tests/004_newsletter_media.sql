BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(8);

INSERT INTO auth.users (
    id, instance_id, aud, role, email, encrypted_password,
    email_confirmed_at, raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) VALUES
    ('10000000-0000-0000-0000-000000000041', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'newsletter-director@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000042', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'newsletter-parent@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW()),
    ('10000000-0000-0000-0000-000000000043', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'newsletter-outsider@test.fireflyfm.local', '', NOW(), '{}', '{}', NOW(), NOW());

INSERT INTO public.schools (id, name)
VALUES ('20000000-0000-0000-0000-000000000041', 'Newsletter Test School');

INSERT INTO public.school_memberships (id, school_id, user_id, role, active)
VALUES
    ('30000000-0000-0000-0000-000000000041', '20000000-0000-0000-0000-000000000041', '10000000-0000-0000-0000-000000000041', 'school_director', TRUE),
    ('30000000-0000-0000-0000-000000000042', '20000000-0000-0000-0000-000000000041', '10000000-0000-0000-0000-000000000042', 'parent', TRUE);

UPDATE public.school_memberships
SET access_state = 'full'
WHERE school_id = '20000000-0000-0000-0000-000000000041';

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.role', 'authenticated', TRUE);
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000041', TRUE);
SELECT set_config(
    'request.jwt.claims',
    '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000041"}',
    TRUE
);

SELECT lives_ok(
    $$INSERT INTO public.newsletters (id, school_id, title, body, created_by, media)
      VALUES (
        '40000000-0000-0000-0000-000000000041',
        '20000000-0000-0000-0000-000000000041',
        'A media-rich update',
        'Newsletter body',
        auth.uid(),
        '[{"id":"50000000-0000-0000-0000-000000000041","file_name":"classroom.jpg","file_path":"schools/20000000-0000-0000-0000-000000000041/newsletters/40000000-0000-0000-0000-000000000041/0-classroom.jpg","content_type":"image/jpeg","alt_text":"Children painting at a classroom table","caption":"Our art morning","sort_order":0}]'::JSONB
      )$$,
    'a school director can publish a newsletter media manifest'
);

SELECT ok(
    public.can_write_newsletter_private_file(
        'schools/20000000-0000-0000-0000-000000000041/newsletters/40000000-0000-0000-0000-000000000041/0-classroom.jpg',
        auth.uid()
    ),
    'a school director can upload to the newsletter private-media path'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000042', TRUE);
SELECT set_config(
    'request.jwt.claims',
    '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000042"}',
    TRUE
);

SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.newsletters WHERE id = '40000000-0000-0000-0000-000000000041'),
    1,
    'a school member can read the newsletter'
);
SELECT ok(
    public.can_access_newsletter_private_file(
        'schools/20000000-0000-0000-0000-000000000041/newsletters/40000000-0000-0000-0000-000000000041/0-classroom.jpg',
        auth.uid()
    ),
    'a school member can access media referenced by the newsletter'
);
SELECT isnt(
    public.can_access_newsletter_private_file(
        'schools/20000000-0000-0000-0000-000000000041/newsletters/40000000-0000-0000-0000-000000000041/1-unlisted.jpg',
        auth.uid()
    ),
    TRUE,
    'a school member cannot access an unreferenced file in the newsletter folder'
);
SELECT isnt(
    public.can_write_newsletter_private_file(
        'schools/20000000-0000-0000-0000-000000000041/newsletters/40000000-0000-0000-0000-000000000041/0-classroom.jpg',
        auth.uid()
    ),
    TRUE,
    'a parent cannot upload newsletter media'
);

SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000043', TRUE);
SELECT set_config(
    'request.jwt.claims',
    '{"role":"authenticated","sub":"10000000-0000-0000-0000-000000000043"}',
    TRUE
);

SELECT is(
    (SELECT COUNT(*)::INTEGER FROM public.newsletters WHERE id = '40000000-0000-0000-0000-000000000041'),
    0,
    'an outsider cannot read the newsletter'
);
SELECT isnt(
    public.can_access_newsletter_private_file(
        'schools/20000000-0000-0000-0000-000000000041/newsletters/40000000-0000-0000-0000-000000000041/0-classroom.jpg',
        auth.uid()
    ),
    TRUE,
    'an outsider cannot access newsletter media'
);

SELECT * FROM finish();
ROLLBACK;
