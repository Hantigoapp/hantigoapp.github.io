# HantiGo Business Module Manager — Foundation

## Status

This is an additive design foundation on the `feature/business-module-manager-foundation` branch. It does not change the live application, existing account flows, database, or service worker. No module is enabled for customers by this document alone.

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

## Proposed architecture

- **HantiGo Core:** existing finance, income/expense, debt, savings, staff, receipts, reports, and account functions.
- **Module Catalog:** stable module IDs, localized names, descriptions, categories, and dependency metadata.
- **Company Module Settings:** the selected module IDs for one company, managed through authenticated RPCs and protected by RLS.
- **Module UI Registry:** maps enabled module IDs to navigation entries and feature screens. Unknown IDs fail closed and do not break Core.
- **Permission layer:** owner controls module selection; manager/staff access is granted only through explicit role permissions.
- **Module data:** each module owns its tables and company-scoped records.

## Proposed rollout

### Phase 0 — Foundation (this branch)
- Define catalog and data contract.
- Review current company identity, membership, RLS, RPC and offline-sync behavior.
- No production UI or database changes.

### Phase 1 — Backend foundation
- Add a company-scoped module-settings table and an RPC to read/update enabled modules.
- Add RLS and role checks; only company owners may change the module selection.
- Add migration verification and negative tests using disposable accounts.
- Preserve all existing tables and RPC signatures.

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

Repository changes do not apply SQL to Supabase automatically. Any future migration must be reviewed, backed up, run manually in the documented order, and verified in the Supabase project. Do not deploy a migration or merge this branch into `main` until the acceptance tests pass.
