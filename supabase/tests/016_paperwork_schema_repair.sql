BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap WITH SCHEMA extensions;
SELECT plan(12);

SELECT has_column('public', 'paperwork_assignments', 'request_kind', 'Paperwork requests expose their kind');
SELECT has_column('public', 'paperwork_assignments', 'status', 'Paperwork requests expose lifecycle status');
SELECT has_column('public', 'paperwork_submissions', 'attempt_number', 'Paperwork submissions track attempts');
SELECT has_column('public', 'paperwork_submissions', 'idempotency_key', 'Paperwork submissions support idempotency');
SELECT has_column('public', 'onboarding_requirement_instances', 'paperwork_request_id', 'Onboarding can link to native Paperwork');

SELECT has_function(
    'public',
    'fetch_my_paperwork_items',
    ARRAY['uuid', 'boolean'],
    'The unified Paperwork list RPC exists'
);
SELECT has_function(
    'public',
    'create_paperwork_request',
    ARRAY['uuid', 'text', 'text', 'text', 'text', 'uuid', 'uuid[]', 'timestamp with time zone', 'boolean'],
    'The Paperwork creation RPC exists'
);
SELECT has_function(
    'public',
    'acknowledge_paperwork_request',
    ARRAY['uuid', 'text'],
    'The acknowledgement RPC exists'
);
SELECT has_function(
    'public',
    'submit_paperwork_request',
    ARRAY['uuid', 'text', 'text', 'text'],
    'The document submission RPC exists'
);
SELECT has_function(
    'public',
    'review_paperwork_submission_v2',
    ARRAY['uuid', 'text', 'text'],
    'The latest-attempt review RPC exists'
);

SELECT ok(
    has_function_privilege(
        'authenticated',
        'public.fetch_my_paperwork_items(uuid,boolean)',
        'EXECUTE'
    ),
    'Authenticated users can load Paperwork'
);
SELECT ok(
    NOT has_function_privilege(
        'anon',
        'public.fetch_my_paperwork_items(uuid,boolean)',
        'EXECUTE'
    ),
    'Anonymous users cannot load Paperwork'
);

SELECT * FROM finish();
ROLLBACK;
