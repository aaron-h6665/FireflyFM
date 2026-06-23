-- FireflyFM HQ director seed template.
-- Run this only from the Supabase SQL editor or another trusted service-role context.
-- 1. Create the HQ director user in Supabase Auth first.
-- 2. Edit the email below for the real internally approved HQ director.
-- 3. Re-run safely; only HQ directors are seeded here.
-- School directors should be invited from the HQ Home school-creation flow.

WITH seed_schools(name, description) AS (
    VALUES
        ('FireflyFM Headquarters', 'Headquarter director workspace.')
),
upserted_schools AS (
    INSERT INTO schools (name, description)
    SELECT name, description
    FROM seed_schools
    WHERE NOT EXISTS (
        SELECT 1
        FROM schools
        WHERE schools.name = seed_schools.name
    )
    RETURNING id, name
),
all_schools AS (
    SELECT id, name FROM upserted_schools
    UNION
    SELECT id, name FROM schools WHERE name IN (SELECT name FROM seed_schools)
),
director_seed(email, school_name, role) AS (
    VALUES
        ('hq-director@example.com', 'FireflyFM Headquarters', 'hq_director')
)
INSERT INTO school_memberships (school_id, user_id, role, active, joined_at)
SELECT all_schools.id, auth.users.id, director_seed.role, TRUE, NOW()
FROM director_seed
JOIN auth.users ON lower(auth.users.email) = lower(director_seed.email)
JOIN all_schools ON all_schools.name = director_seed.school_name
ON CONFLICT (school_id, user_id)
DO UPDATE SET role = EXCLUDED.role, active = TRUE;

NOTIFY pgrst, 'reload schema';
