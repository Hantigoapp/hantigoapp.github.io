# HantiGo staff and manager acceptance tests

Run these tests only with disposable accounts and dummy company records. Do not use a real employee's account or live financial information.

## Test accounts

Create one disposable company owner, two staff accounts (Staff A and Staff B), and one manager account. Add all three team accounts to the test company, set one role to `manager`, and leave the two others as `staff`. Confirm `roles.sql` and `security_hardening.sql` have been applied in that order.

## Expected access matrix

| Action | Owner | Manager | Staff A | Staff B |
|---|---:|---:|---:|---:|
| Read owner's personal data | Yes | No | No | No |
| Read all company records | Yes | Yes | No | No |
| Read own permitted company entries | Yes | Yes | Yes | Yes |
| Add own transaction | Yes | Yes | Yes | Yes |
| Edit/delete another staff member's transaction | Yes | Yes | No | No |
| Approve/decline leave | Yes | Yes | No | No |
| Submit own leave request | Yes | Yes | Yes | Yes |
| Change staff roles | Yes | No | No | No |
| Invite/remove team members | Yes | No | No | No |
| Read another company's records | No | No | No | No |

## Browser-level tests

1. As owner, create dummy company records attributed to Staff A and Staff B. Create one personal record. Add one pending leave request from each staff account.
2. As Staff A, confirm only Staff A's permitted company transactions/leave appear. Confirm Staff B's transaction and the owner's personal record do not appear.
3. As Staff A, try to edit/delete Staff B's record and approve/decline either leave request. The UI must not offer these actions; direct RPC attempts must be rejected or have no effect.
4. As Staff B, repeat the isolation checks against Staff A.
5. As manager, confirm all company records and pending leave requests are visible, but personal owner records are not. Confirm the manager cannot invite/remove team members or change their roles.
6. As owner, approve/decline leave and change a test member's role. Confirm the new role takes effect after reloading/re-authenticating.
7. As a separate unrelated account, try to call `team_load` and `team_save` with the test owner's UUID. Both must fail with `not a member`.
8. Sign out and verify anonymous requests cannot read or write `profiles`, `user_data`, `team_members`, `payments`, `push_subscriptions`, or `push_preferences`.
9. Remove the test members and delete the disposable accounts after the test.

## SQL audit

Run `role_security_audit.sql` after migrations. Confirm RLS is enabled on every listed table, there are no anonymous table grants, and `anon_can_execute` is false for every listed function. Inspect each policy's `USING` and `WITH CHECK` expressions rather than relying only on its name.

A passing static SQL audit does not replace the browser-level negative tests above. No tests are considered passed until performed in the connected Supabase project.
