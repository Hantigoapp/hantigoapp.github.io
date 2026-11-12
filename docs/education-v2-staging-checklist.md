# Education V2 staging checklist

Status: preparation only. No SQL in this document has been run against Supabase, and no production database should be changed from this checklist.

## Before testing

- Use a dedicated Supabase staging project, not production.
- Confirm the existing core, team, roles, pricing, business-module and Education V1 migrations are present.
- Take a staging backup/snapshot before applying changes.
- Use disposable owner, manager, staff and second-company accounts with dummy records only.
- Never paste passwords, API keys, service-role keys or other secrets into GitHub issues or chat.

## Migration order

1. `supabase/education_v2.sql`
2. `supabase/education_v2_rpc.sql`

Run only after the prerequisite migrations listed in `supabase/README.md`. Review SQL output and verification queries after each file. Stop on any error; do not continue to the next migration.

## Database checks

- All `education_%` V2 tables have RLS enabled.
- Direct table access is not granted to `anon` or `authenticated`; access is through guarded RPCs.
- `education_v2_get(uuid)` is executable by `authenticated`, not `anon`.
- Each V2 write RPC is executable by `authenticated`, not `anon` or `public`.
- Legacy V1 tables and RPCs remain present and unchanged.
- Existing classes are backfilled to an explicitly `unclassified` stage; do not infer a stage from a class name.
- Backfill can be re-run without duplicating stage/cohort/enrolment rows.

## Role and company isolation tests

| Scenario | Expected result |
| --- | --- |
| Company owner reads its V2 snapshot | Allowed |
| Company manager reads and writes V2 records | Allowed while company plan and Education module are active |
| Staff reads V2 snapshot | Allowed |
| Staff calls any V2 write RPC | Denied |
| Inactive owner or disabled Education module calls V2 RPC | Denied |
| User from company B requests company A owner ID | Denied; no data disclosed or changed |
| Anonymous user calls V2 RPC | Denied |

## Functional tests

- Create one company with multiple stages: primary, middle, secondary, university and vocational.
- Create an academic year, then a semester or term linked to that same company's academic year.
- Reject a semester/term whose parent year belongs to another company or is not an academic year.
- Create cohorts under each stage; reject a cohort whose stage or period belongs to another company.
- Enrol an active V1 student into a V2 cohort.
- Transfer that student to another cohort on the same date or a later date; preserve the previous enrolment and leave exactly one active enrolment.
- Reject transfer dates earlier than the current enrolment date.
- Reject a second active enrolment for the same student.
- Confirm legacy V1 classes, students and fee-payment history still display and remain unchanged.
- Confirm V1 fee-payment records cannot be deleted through V2 flows.

## UI smoke tests

- Sign in as owner, manager and staff; confirm the Education panel loads without JavaScript errors.
- Confirm V2 lists and selectors populate from `education_v2_get`.
- Confirm owner/manager can save stages, periods, cohorts and enrolment transfers.
- Confirm staff sees a clear permission error and cannot write.
- Confirm if V2 migrations are absent, V1 remains usable and the V2 status explains that V2 is not configured.
- Confirm Shakhsi/Shirkad, team roles, finance, reports, exports, offline/PWA and language switching still work.

## Exit criteria

Do not merge to `main` or deploy until all checks pass, SQL output is reviewed, and the tested commit SHA plus Supabase migration state are recorded. Any failure must be fixed and the affected tests rerun.