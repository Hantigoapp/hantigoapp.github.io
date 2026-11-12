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
15. `business_modules.sql` — additive Business Module Manager backend foundation: module catalog, company-scoped selections, and owner/member-checked RPCs. Run only after the existing migrations above.
16. `education.sql` — first operational module: company-scoped classes, students and fee payments, with role-checked RPCs. Run after `business_modules.sql`.
17. `education_v2.sql` — additive multi-level Education foundation (stages, academic periods, departments, programmes, courses, cohorts, enrolment history, attendance, assessments/results, fee obligations and certificates). Run after `education.sql`; it preserves V1 tables and RPCs, backfills old classes as explicitly unclassified, and currently exposes a read-only V2 snapshot RPC. The current feature branch also includes an initial V2 UI for stage, academic-period, cohort and student enrolment/transfer management. It is an early integration and must be validated against a staging Supabase project before real use.
18. `education_v2_rpc.sql` — first guarded V2 write API for stages, academic periods, cohorts and auditable student enrolment transfers. Run after `education_v2.sql`; it uses the existing Education owner/manager authorization and does not alter V1 RPCs. Programme/course, attendance, assessment/result, fee-obligation and certificate write APIs remain future slices.
19. `education_v2_academic_rpc.sql` — guarded write APIs for university/vocational departments, programmes and courses. Run after `education_v2_rpc.sql`; records remain scoped to the same company owner and use the existing Education authorization helper. Attendance, assessments/results, fee obligations and certificates remain future slices.

Run each file once in this order. If you are updating an existing deployment, review the file comments and take a database backup before applying migrations.

## Business Module Manager migration

The new `business_modules.sql` migration is **not applied automatically** by a GitHub commit. Before running it on a live Supabase project:

1. Take a fresh database backup, or use a staging project first.
2. Review `business_modules.sql`.
3. Run it after the existing migrations listed above.
4. Confirm both new tables report `rls_enabled = true`.
5. Confirm anon and authenticated direct table grants are false.
6. Confirm only authenticated users can execute the two RPCs.
7. Test with disposable accounts: owner can read/update their own module selection; a member can read only their company's selection; a member cannot update it; a user from another company cannot read it.
8. Confirm existing Shakhsi/Shirkad, team, finance, export and offline flows still work.

The migration seeds stable IDs for Education, Hotel, Restaurant, Retail, Wholesale, Construction, Agriculture, Livestock, Transport, Manufacturing, Services and Fishing. The app includes the module selection UI. Education is the first module with operational tables and a basic app screen; the other modules do not yet have operational screens. Disabling a module stores `enabled = false`; it does not delete module data.

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

## Background notifications status

The service worker handles incoming Web Push events and notification clicks, including when the HantiGo page is closed. This is only the browser-side receiver. Actual background delivery is **not yet configured**: it also requires VAPID keys, authenticated push-subscription storage, a trusted server-side sender (for example a Supabase Edge Function), and a scheduled job that evaluates each account's reminder preferences. Do not put VAPID private keys or a Supabase service-role key in `index.html` or any other public repository file. The current in-app reminder timer continues to work only while HantiGo is open.


## Web Push deployment

After applying `push_notifications.sql`, follow [`push_deployment.md`](push_deployment.md) to configure VAPID secrets, deploy the three Edge Functions, store the scheduler secret in Vault, and enable the cron job. The browser UI can request a subscription and send a test push. The scheduled worker currently sends only the daily check-in reminder; other alert types are not yet delivered in the background. Do not commit secrets or the service-role key.


Use [`push_deployment.md`](push_deployment.md) for the VAPID, Edge Function, Vault, and cron setup. Use [`role_acceptance_tests.md`](role_acceptance_tests.md) for the owner/manager/staff isolation test matrix.
## Business Module Manager UI

The `index.html` settings screen includes an owner-only Business Module Manager under **Akoon** for Shirkad accounts. It reads and saves selected module IDs through `business_modules_get` and `business_modules_set`. It fails safely if the migration is not installed; the rest of HantiGo Core remains available.

The current screen stores module selection only. Module-specific workflows (school management, hotel operations, restaurant orders, stock, transport, and other module screens) are not implemented by this settings screen. Apply and verify `business_modules.sql` and `education.sql` on staging before testing the Education UI. The service worker cache was bumped so installed PWAs pick up the updated page. The Education screen supports class and student registration and recording fee payments; payment history cannot be deleted in this first version. It does not yet generate invoices, automate EVC/WaafiPay collection, or connect student transport.
## Education V2 UI status

The Education panel now includes an initial V2 management screen for:
- Creating institution stages (primary, middle, secondary, university, vocational).
- Creating academic years and child terms/semesters.
- Creating stage-linked cohorts/classes.
- Enrolling or transferring existing V1 students into V2 cohorts while retaining enrolment history.
- Viewing stages, periods, cohorts, and enrolment history from `education_v2_get`.

This is a development-branch UI only. The V2 snapshot and write RPC migrations must be installed in a non-production Supabase staging project before the forms can save data. The V1 Education forms remain present and use their existing RPCs.

### Required staging acceptance checks before production

- Owner can read/write only their own institution's V2 records.
- Manager can read/write within the institution; Staff can read but cannot write.
- Inactive owner and disabled Education module are denied.
- A user from another company cannot read or mutate records by supplying another `p_owner`.
- Stage, academic-year, semester/term, and cohort validation rejects invalid parent/company references.
- A student can have only one active enrolment; transfer closes the prior enrolment and preserves its history.
- Existing V1 classes, students, and fee-payment history remain intact after the additive V2 backfill.
- V1 fee payment history cannot be altered through V2 operations.
- Verify mobile layout, Somali/English labels, reload behavior, and graceful V2-not-installed messaging.

Do not run these migrations against production until SQL review and the staging checks above pass.
