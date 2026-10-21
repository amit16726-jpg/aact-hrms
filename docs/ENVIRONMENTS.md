# Environments and the path to go-live

| | Local (laptop) | Test (optional) | Production (company server) |
|---|---|---|---|
| Purpose | development | demos, HR acceptance testing | live use |
| Database | Supabase in Docker (Supabase CLI) | Supabase cloud project `nbseyccerlzerkmcwknw` | self-hosted Supabase in Docker on Ubuntu 24.04 |
| Data | **dummy** (`supabase/seed.sql`) | sample/dummy only | **real** employee data |
| Front end | `npm run dev` | Vercel | static files behind nginx with HTTPS |
| E-mail | Mailpit (nothing leaves the laptop) | Supabase default; HR notifications off | company M365 (sign-in e-mails by relay; HR notifications by the `send-mail` function) |
| Environment label in the app | LOCAL – dummy data | TEST (set `VITE_ENV_LABEL=TEST` in Vercel) | none |

## What is identical everywhere

- `supabase/migrations/*` — the database: tables, rules, permissions and audit trail.
- The front-end code. Only `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` and `VITE_ENV_LABEL` differ per environment.
- PostgreSQL major version **17** (`supabase/config.toml` → `[db] major_version`). The company server must use 17 too.

## What exists only in one place

- `supabase/seed.sql` — local only. It refuses to run on a database that already has employees.
- `supabase/seed_phase2.sql` — local/test only (shifts, punches, leave). It stops if shifts already exist.
- `supabase/seed_phase3.sql` — local/test only (payroll months, loans, settlement). It stops if payroll runs exist.
- `supabase/seed_phase4.sql` — local/test only (letters, change requests). It stops if letters exist.
- `supabase/seed_phase5.sql` — local/test only (requisitions, candidates, offers, onboarding). It stops if requisitions exist.
- `supabase/seed_phase6.sql` — local/test only (appraisal cycle, training, cases, assets, housing, injuries, an exit). It stops if appraisal cycles exist.
- `.env.development.local` — local only, written by `npm run env:local`, never committed.
- Production secrets (database password, JWT secret, SMTP password) — only on the company server, never in git.

## Go-live steps (when development and testing are complete)

1. Al Anwar IT provides the server (Ubuntu 24.04, Docker, fixed IP, ports 80/443), the DNS name from the web vendor,
   and the M365 mail relay.
2. Install self-hosted Supabase (Docker Compose) and the web front end; set the production secrets.
3. Apply `supabase/migrations` in order. Do **not** load `seed.sql` or any `seed_phase*.sql`.
4. Run the security checks; test a backup **and a restore**.
5. Create the real administrator, HR and Finance accounts. Turn off public sign-up.
6. Enter the real master data (company, departments, grades, job titles, Omanisation targets with their sources).
7. Import the real employees, then upload documents.
8. HR checks a sample of records against the source files, then go live.

A separate deployment package (Docker Compose, nginx, backup/restore scripts, install guide) will be prepared before step 1.

## E-mail through Microsoft 365

HR notifications (approvals, decisions, reminders) can also go out by e-mail. The database queues them in `hr.email_outbox`
when **Settings → E-mail notifications** is switched on; the `send-mail` edge function sends the queue through Microsoft Graph.

1. **Microsoft Entra admin centre** (Al Anwar IT): App registrations → New → name `AACT HRMS mail`. API permissions → Microsoft Graph →
   *Application* permission **Mail.Send** → Grant admin consent. Certificates & secrets → New client secret (note the expiry date).
2. Limit the app to one mailbox (Exchange Online PowerShell):
   `New-ApplicationAccessPolicy -AppId <client id> -PolicyScopeGroupId hr-notifications@aact.om -AccessRight RestrictAccess -Description "AACT HRMS"`
3. Set the secrets on the server (self-hosted: in the functions `.env`; cloud: `supabase secrets set`):
   `M365_TENANT_ID`, `M365_CLIENT_ID`, `M365_CLIENT_SECRET`, `M365_SENDER=hr-notifications@aact.om`, `MAIL_CRON_SECRET=<long random text>`.
4. Deploy the function: `npx supabase functions deploy send-mail --no-verify-jwt` (it checks `MAIL_CRON_SECRET` itself).
5. Run it every 2 minutes from the database (needs the `pg_cron` and `pg_net` extensions; replace the address and secret):

   ```sql
   select cron.schedule('hr-send-mail', '*/2 * * * *', $$
     select net.http_post(url := 'https://<server>/functions/v1/send-mail',
                          headers := jsonb_build_object('x-cron-secret', '<MAIL_CRON_SECRET>', 'Content-Type', 'application/json'),
                          body := '{}'::jsonb) $$);
   ```
6. In the app: Settings → E-mail notifications → enter the system address (e.g. `https://hr.aact.om`) → switch on → **Send me a test e-mail**.
   Failed messages are retried up to 5 times within a day and listed with the error.

Employees can switch e-mails off for themselves in Settings. Real employee e-mails are sent only from the company server.

## Letter verification address

Letters print an address of the form `https://<server>/verify?ref=…&code=…`. Set the public address once in
**Requests and letters → Letter settings**; the page works without signing in and shows only the letter type, date, company and name.
