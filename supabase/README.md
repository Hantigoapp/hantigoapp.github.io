# HantiGo Supabase setup

This folder contains the database setup and feature migrations used by HantiGo. Run these in the Supabase Dashboard → SQL Editor, in the order below.

## Required order

1. `schema.sql` — core profiles and user data, RLS, access helpers.
2. `team.sql` — company memberships and team RPCs.
3. `isolation.sql` — company-only settings and table isolation.
4. `leave.sql` — leave-request support for team saves.
5. `roles.sql` — final owner/manager/staff permissions. **This must run after `leave.sql`**, because it replaces the earlier team-save function with role-aware checks.
6. `pricing.sql` — account plan.
7. `account.sql` — self-service account deletion.
8. `location.sql` — user-selected city/country.
9. `payment.sql` — payment request and admin decision RPCs.
10. `sales.sql` — payment history and sales reporting.
11. `signups.sql` — admin sign-up summary.
12. `security_hardening.sql` — final table/function grants and verification queries.

Run each file once in this order. If you are updating an existing deployment, review the file comments and take a database backup before applying migrations.

## Verification after setup

The final `security_hardening.sql` script prints:

- RLS status for `profiles`, `user_data`, `team_members`, and `payments` (all must be enabled).
- Table grants for `anon` and `authenticated` (no anonymous access; payment history is client read-only).
- Function execution grants (the listed RPCs must not be callable by `anon`).

Then test with separate test accounts:

- Owner: personal data, company data, staff invitation/removal, role changes.
- Manager: company-wide management only; no owner personal data.
- Staff: own company entries and leave requests only; cannot approve their own leave or change staff roles.
- Customer: own payment request and own profile only.
- Admin: customer support, payment decisions, sales reporting.

Use test data. Do not use another person's account or real financial records to test access boundaries.

## Important

Repository changes do not automatically update the Supabase database. The SQL files must be run in the Supabase project. This setup guide and hardening script do not certify the whole system as secure; verify the results and test the role boundaries before production use.
