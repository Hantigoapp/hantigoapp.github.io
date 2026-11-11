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

**Important:** this is a migration file only. It has not been executed against Supabase, and the UI does not call these RPCs yet. Back up/stage and run it manually only after reviewing it.

## Architecture

- **HantiGo Core:** existing finance, income/expense, debt, savings, staff, receipts, reports, and account functions.
- **Module Catalog:** stable module IDs, localized names, descriptions, categories, and dependency metadata.
- **Company Module Settings:** the selected module IDs for one company, managed through authenticated RPCs and protected by RLS.
- **Module UI Registry:** maps enabled module IDs to navigation entries and feature screens. Unknown IDs fail closed and do not break Core.
- **Permission layer:** owner controls module selection; manager/staff access is granted only through explicit role permissions.
- **Module data:** each module owns its tables and company-scoped records.

## Remaining rollout

### Phase 1 — Backend verification
- Review and run the migration in staging or after a fresh backup.
- Verify RLS, grants, RPC execution and cross-company negative tests.
- Confirm existing app and offline flows are unaffected.

### Phase 2 — UI integration
- Add a Module Manager screen as a separate feature entry point.
- Render only modules returned as enabled for the active company.
- Keep existing navigation and Core screens available.
- Add feature flags and a safe fallback if module settings cannot load.

### Phase 3 — First business module
- Start with Education as the first module, then validate the pattern before adding more modules.
- Add module-specific screens and tables only after the shared foundation passes tests.

## Required acceptance tests

- Existing Shakhsi and Shirkad account flows still work.
- Existing income, expense, debt, savings, receipt, report, staff and export flows still work.
- Owner A cannot read or change Company B's module settings.
- Manager and staff cannot change enabled modules unless explicitly granted.
- Disabling a module does not delete its records.
- An unavailable module-settings service does not block HantiGo Core.
- Existing offline/PWA behavior remains functional.
- SQL migrations are tested on a backup/staging database before production.

## Deployment warning

Repository changes do not apply SQL to Supabase automatically. The new migration must be reviewed, backed up, run manually in the Supabase project, and verified. Do not merge this branch into `main` until the acceptance tests pass.
