# HantiGo Business Module Manager — Foundation

## Status

The additive foundation and first backend migration are committed on `feature/business-module-manager-foundation`. The live `main` branch and live Supabase database have not been changed. No customer-facing module UI or operational module screens are enabled yet.

## Product decision

A company can enable multiple business modules at the same time. Modules extend HantiGo Core; they do not replace it. A company can add or disable modules later without deleting its underlying records.

## Core principles

1. Preserve the existing Shakhsi/Shirkad flows and all current features.
2. Keep module configuration scoped to the authenticated company, never to a global browser setting.
3. Enforce authorization on the server/database as well as in the UI. Hiding a menu item is not access control.
4. Use additive database migrations and new module-owned tables. Do not repurpose existing columns or overload the current `user_data` JSONB store for complex operational records.
5. Keep module catalog metadata separate from each company's enabled-module selection.
6. A module may declare dependencies, but enabling it must not silently enable unrelated modules.
7. Disabling a module hides its workflows but does not delete historical data.
8. Existing offline behavior must remain intact; new offline writes require an explicit sync/conflict design before release.

## Implemented backend foundation

New file: `supabase/business_modules.sql`.

- Adds a stable module catalog with IDs for Education, Hotel, Restaurant, Retail, Wholesale, Construction, Agriculture, Livestock, Transport, Manufacturing, Services and Fishing.
- Adds `company_modules`, keyed by the existing company owner account ID plus module ID. Disabled selections remain stored.
- Adds `business_modules_get(p_owner)`: company owner and authenticated company members can read that company's module selection; unrelated users are rejected.
- Adds `business_modules_set(p_module_ids)`: only the authenticated account owner can change their selection; unknown, inactive, duplicate and excessive module selections are rejected.
- Enables RLS and revokes direct client table access; authenticated clients use the guarded RPCs.
- Includes SQL verification queries.

**Important:** the migration has not been executed against Supabase. The UI integration is committed, but it cannot load or save selections until the migration is applied and verified. Back up/stage and run it manually only after reviewing it.

## Architecture

- **HantiGo Core:** existing finance, income/expense, debt, savings, staff, receipts, reports, and account functions.
- **Module Catalog:** stable module IDs, localized names, descriptions, categories, and dependency metadata.
- **Company Module Settings:** the selected module IDs for one company, managed through authenticated RPCs and protected by RLS.
- **Module UI Registry:** maps enabled module IDs to navigation entries and feature screens. Unknown IDs fail closed and do not break Core.
- **Permission layer:** owner controls module selection; manager/staff access is granted only through explicit role permissions.
- **Module data:** each module owns its tables and company-scoped records.

## Remaining rollout

### Phase 1 — Backend verification
- [ ] Review and run the migration in staging or after a fresh backup.
- [ ] Verify RLS, grants, RPC execution and cross-company negative tests.
- [ ] Confirm existing app and offline flows are unaffected.

### Phase 2 — UI integration (initial settings screen committed)
- Added an owner-only **Akoon → Maamulka qaybaha ganacsiga** screen for Shirkad accounts.
- Loads the module catalog and enabled selections through `business_modules_get` and saves through `business_modules_set`.
- Uses safe text rendering and displays a clear setup error if the RPC migration is missing; it does not block HantiGo Core.
- Selection is configuration only: module-specific operational screens are not yet implemented.
- The service worker cache was bumped for the updated PWA page.
- Next: verify both migrations on staging, then add a navigation registry and extend modules one at a time.

### Phase 3 — First business module (Education initial version committed)
- Added `supabase/education.sql` with company-scoped classes, students and fee-payment records.
- Added guarded RPCs for reading data, creating/updating classes and students, recording payments, and deleting records.
- Authorization checks company membership/manager role and requires the Education module to be enabled. Fee history is protected from accidental deletion when a student has payments; classes with enrolled students cannot be deleted.
- Added an Education screen under Akoon/More for business accounts: class registration, student registration, fee-payment entry, summary counts and record lists.
- The current UI is an initial operational foundation. It does not yet include attendance, exams, timetables, automated invoices, EVC/WaafiPay collection, parent portal, student transport, or offline sync for Education records.

## Required acceptance tests

- Existing Shakhsi and Shirkad account flows still work.
- Existing income, expense, debt, savings, receipt, report, staff and export flows still work.
- Owner A cannot read or change Company B's module settings.
- Manager and staff cannot change enabled modules unless explicitly granted.
- Disabling a module does not delete its records.
- An unavailable module-settings service does not block HantiGo Core.
- Existing offline/PWA behavior remains functional.
- SQL migrations are tested on a backup/staging database before production.
- Education module: verify class/student/payment CRUD, manager/staff permissions, company isolation, and fee-history retention on staging.

## Deployment warning

Repository changes do not apply SQL to Supabase automatically. The new migration must be reviewed, backed up, run manually in the Supabase project, and verified. Do not merge this branch into `main` until the acceptance tests pass.
