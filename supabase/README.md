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
    - `autopay.sql` — automatic EVC Plus / WaafiPay payment (`autopay_grant`, service role only). Run it with the Edge Function `pay-auto` (Verify JWT off, secrets `WAAFI_MERCHANT_UID`, `WAAFI_API_USER_ID`, `WAAFI_API_KEY`). Same `payments` table as `sales.sql`, either order works.
11. `signups.sql` — admin sign-up summary.
12. `security_hardening.sql` — final table/function grants and verification queries.
13. `push_notifications.sql` — private, RLS-protected browser push subscriptions and preferences.
14. `activity.sql` — activity history: a trigger on `user_data` records every add / correction / delete (who, when, before/after) in `activity_log`; read through `activity_list` (owner: all, manager: company, staff: own). Until it is run, the app hides the history panel.
15. `customer_info.sql` — customer name + phone (sign-up, receipts, admin details).
16. `start_date.sql` — start date chosen at sign-up (admin view).
17. Education (admin-only page `education.html`): `education.sql` (base tables), then `education_students_class.sql`, then `education_attendance.sql`. `education_audit.sql` is read-only.

**Shortcut for the live project:** `pending_setup.sql` = `sales`, `autopay`, `signups`, `customer_info`, `start_date` and `activity` in one file (safe to run again). Its last line prints six `true` values when everything is in place.

**Never re-run `team.sql`, `isolation.sql` or `leave.sql` after `roles.sql`:** they redefine `team_load` / `team_save` and remove the role checks. If you must, run `roles.sql` again straight after.

Edge Function `notify-admin` (no SQL needed): emails every `is_admin` account when a customer sends a manual "I paid" request (with the payment screenshot) and when a new account opens for the first time; on that first sign-in the new customer also gets a welcome email (in the app language they used) with the sign-in link, plan price and trial end date. Deploy it with Verify JWT ON; it uses the same `SMTP_USER` / `SMTP_PASS` secrets as `send-receipt`. Secret `NOTIFY_SIGNUPS=0` turns the admin sign-up email off; `NOTIFY_WELCOME=0` turns the customer welcome email off. Each event is sent once (remembered in the user's `app_metadata`). Automatic WaafiPay payments are already reported by `pay-auto`.

Edge Function `send-receipt` (Shirkad 🧾 Rasiid by email): only an open Business account (trial or paid, or an admin) or staff of an active company may send, at most 10 emails an hour per account. Uses the same SMTP secrets.

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

## Role and RLS audit

After applying all migrations, run `role_security_audit.sql` in the SQL Editor. It is read-only: it reports RLS flags, policies, table grants, role-aware RPC grants, and current staff roles. Review the results and complete the negative tests listed at the end with separate disposable accounts and dummy data. A SQL report alone does not prove that role boundaries work end-to-end.

## Web Push deployment

After applying `push_notifications.sql`, follow [`push_deployment.md`](push_deployment.md) to configure VAPID secrets, deploy the three Edge Functions, store the scheduler secret in Vault, and enable the cron job. The browser UI can request a subscription and send a test push. The scheduled worker currently sends only the daily check-in reminder; other alerts (bills, budget, leave) show only while HantiGo is open. Do not commit secrets or the service-role key.


Use [`role_acceptance_tests.md`](role_acceptance_tests.md) for the owner/manager/staff isolation test matrix.
