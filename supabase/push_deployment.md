# HantiGo Web Push deployment

This feature is not live until the SQL migration, Edge Functions, secrets, and scheduler are configured in the Supabase project.

## 1. Create VAPID keys locally

On a trusted computer, install/use the `web-push` CLI and generate a VAPID key pair:

```sh
npx web-push generate-vapid-keys
```

Keep the private key secret. Do not commit either key to GitHub, place them in `index.html`, or share them in chat.

## 2. Apply the database migration

In Supabase Dashboard → SQL Editor, run `supabase/push_notifications.sql` after the existing `security_hardening.sql`.

The migration creates `push_subscriptions` and `push_preferences`. RLS limits browser users to their own rows; service-role access is reserved for the Edge Functions.

## 3. Configure Edge Function secrets

From a trusted local checkout linked to the correct Supabase project, set these secrets using the Supabase CLI's secret-management command (do not add values to repository files):

- `VAPID_PUBLIC_KEY`
- `VAPID_PRIVATE_KEY`
- `VAPID_SUBJECT` (a monitored `mailto:` address controlled by the project owner)
- `CRON_SECRET` (a long random secret)

Supabase provides `SUPABASE_URL`, `SUPABASE_ANON_KEY`, and `SUPABASE_SERVICE_ROLE_KEY` to Edge Functions. Never expose the service-role key to the browser.

## 4. Deploy functions

```sh
supabase functions deploy push-public-key
supabase functions deploy send-test-push
supabase functions deploy send-reminders
```

`push-public-key` and `send-test-push` require a signed-in user JWT. `send-reminders` has JWT verification disabled in `config.toml` because it is called by the scheduler; it independently requires the secret `x-cron-secret` header.

## 5. Schedule the daily reminder worker

In Supabase SQL Editor, enable the `pg_cron`, `pg_net`, and Vault extensions if they are not already enabled. Store the same random `CRON_SECRET` value in Supabase Vault under the name `hantigo_cron_secret`. Never put its value in this SQL file or GitHub.

Replace `<PROJECT_REF>` with the Supabase project reference, then schedule the function every minute. It sends at each user's configured local time and records one send per device per local day.

```sql
select cron.schedule(
  'hantigo-background-reminders',
  '* * * * *',
  $job$
    select net.http_post(
      url := 'https://<PROJECT_REF>.supabase.co/functions/v1/send-reminders',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'x-cron-secret', (
          select decrypted_secret
          from vault.decrypted_secrets
          where name = 'hantigo_cron_secret'
          limit 1
        )
      ),
      body := '{}'::jsonb
    );
  $job$
);
```

Check the job with `select * from cron.job;` and inspect `cron.job_run_details` for failures. Ensure the Vault secret is present before enabling the job. Remove/replace the schedule with `cron.unschedule(jobid)` if needed.

## 6. Browser setup and test

1. Open HantiGo on HTTPS in a browser that supports Web Push.
2. Sign in and open reminder settings.
3. Press **Shid ogeysiisyada taleefanka** and allow notifications.
4. Press **Tijaabi hadda**. This sends a real push through the Edge Function to all subscriptions for the signed-in account.
5. Close every HantiGo tab and verify the test notification still appears.
6. Turn on the daily reminder and choose a time a few minutes ahead in the device's local time zone. Close HantiGo and verify one reminder arrives.
7. Test on a second device; each device should receive one notification, not repeated notifications.
8. Revoke browser notification permission and verify that the UI reports the failure. Remove stale endpoints (HTTP 404/410 are cleaned up by the sender).

Web Push support varies by browser and platform. iOS requires an installed Home Screen web app and user-initiated permission on supported versions. Native Capacitor notifications are not implemented by this Web Push flow.

## Current scope and privacy

The scheduled worker currently implements the **daily check-in reminder** only. It checks whether the signed-in account has entered any transaction for the local day. Bill, budget, savings-goal, debt, and leave alerts still need separate server-side evaluators before they can be delivered while the app is closed. Reminder payloads intentionally contain no financial amounts or transaction details.

The current preferences row is per signed-in account. The existing UI has separate personal/business preferences and local-only team preferences; this first push release syncs the preference set active when the user enables or changes reminders. A later iteration should split server preferences by account mode/company and add manager/owner-specific company alerts.

## Operational safety

- Rotate VAPID keys only with a planned subscription renewal strategy.
- Rotate `CRON_SECRET` in both Supabase secrets and Vault together.
- Never expose `SUPABASE_SERVICE_ROLE_KEY`, VAPID private key, or cron secret in the static site.
- Monitor Edge Function logs and cron failures. Do not treat a successful deployment as proof of delivery.
