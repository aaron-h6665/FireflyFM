"""Synthetic concurrency checks; refuses the application's normal database.
Run: python3 supabase/tests/concurrency/payment_review.py firefly_adversarial_<run>
The caller must provide an isolated database with current migrations applied.
"""
import concurrent.futures
from pathlib import Path
import subprocess
import sys

name = sys.argv[1]
if not name.startswith("firefly_adversarial_") or not name.replace("_", "").isalnum():
    raise SystemExit("Use a dedicated firefly_adversarial_<run> database")
command = ["docker", "exec", "-i", "supabase_db_fireflyfm", "psql", "-X", "-U", "supabase_admin", "-d", name, "-At", "-v", "ON_ERROR_STOP=1"]

def query(sql):
    return subprocess.run(command, input=sql, text=True, capture_output=True)

def checked(sql):
    result = query(sql)
    assert result.returncode == 0, result.stderr
    return result.stdout

# Reuse the payment suite's synthetic roles and open invoices, never existing app data.
fixture = (Path(__file__).parents[1] / "019_workspace_beta.sql").read_text()
fixture = fixture.split("SELECT is((SELECT recipient_snapshot", 1)[0]
fixture = fixture.replace("SELECT no_plan();", "")
checked(fixture + "\nCOMMIT;")
invoice = "52000000-0000-0000-0000-000000000091"
payer = "10000000-0000-0000-0000-000000000092"
director = "10000000-0000-0000-0000-000000000091"
hq = "10000000-0000-0000-0000-000000000096"

def as_actor(actor, sql):
    return f"SET LOCAL ROLE authenticated; SELECT set_config('request.jwt.claim.sub','{actor}',true); {sql}"

def race(actor1, sql1, actor2, sql2):
    # Signal after taking the same invoice lock as the RPC, then hold it briefly
    # while the other connection attempts its mutation.
    first = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    first.stdin.write(f"BEGIN; SELECT id FROM public.zelle_invoices WHERE id='{invoice}' FOR UPDATE; SELECT 'locked'; SELECT pg_sleep(1); " + as_actor(actor1, sql1) + " COMMIT;\n")
    first.stdin.close()
    while True:
        line = first.stdout.readline()
        assert line, first.stderr.read()
        if line.strip() == "locked":
            break
    with concurrent.futures.ThreadPoolExecutor() as executor:
        pending = executor.submit(query, "BEGIN; " + as_actor(actor2, sql2) + " COMMIT;")
        first_output = first.stdout.read()
        first_error = first.stderr.read()
        first.wait()
        second = pending.result()
    assert first.returncode == 0, first_error
    return first_output, second

submit = f"SELECT id FROM public.submit_zelle_payment('{invoice}',1000,now(),'RACE-REFERENCE','race-idempotency-key');"
first, second = race(payer, submit, payer, submit)
assert second.returncode == 0, second.stderr
assert checked(f"SELECT count(*) FROM public.zelle_payment_submissions WHERE invoice_id='{invoice}';").strip() == "1"
print("PASS: concurrent duplicate submissions produce one payment submission")
review = f"SELECT status FROM public.review_zelle_payment((SELECT id FROM public.zelle_payment_submissions WHERE invoice_id='{invoice}'),'approved',NULL);"
first, second = race(director, review, hq, review)
assert second.returncode != 0 and "cannot be reviewed" in second.stderr, second.stderr
assert checked(f"SELECT status || ':' || amount_paid_cents FROM public.zelle_invoices WHERE id='{invoice}';").strip() == "paid:1000"
assert checked(f"SELECT count(*) FROM public.zelle_payment_submissions WHERE invoice_id='{invoice}' AND status='approved';").strip() == "1"
print("PASS: simultaneous reviewers cannot approve the same submission twice")
