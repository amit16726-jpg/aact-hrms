# Environments and the path to go-live

| | Local (laptop) | Test (optional) | Production (company server) |
|---|---|---|---|
| Purpose | development | demos, HR acceptance testing | live use |
| Database | Supabase in Docker (Supabase CLI) | Supabase cloud project `nbseyccerlzerkmcwknw` | self-hosted Supabase in Docker on Ubuntu 24.04 |
| Data | **dummy** (`supabase/seed.sql`) | sample/dummy only | **real** employee data |
| Front end | `npm run dev` | Vercel | static files behind nginx with HTTPS |
| E-mail | Mailpit (nothing leaves the laptop) | Supabase default | company M365 (relay connector) |
| Environment label in the app | LOCAL – dummy data | TEST (set `VITE_ENV_LABEL=TEST` in Vercel) | none |

## What is identical everywhere

- `supabase/migrations/*` — the database: tables, rules, permissions and audit trail.
- The front-end code. Only `VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY` and `VITE_ENV_LABEL` differ per environment.
- PostgreSQL major version **17** (`supabase/config.toml` → `[db] major_version`). The company server must use 17 too.

## What exists only in one place

- `supabase/seed.sql` — local only. It refuses to run on a database that already has employees.
- `supabase/seed_phase2.sql` — local/test only (shifts, punches, leave). It stops if shifts already exist.
- `.env.development.local` — local only, written by `npm run env:local`, never committed.
- Production secrets (database password, JWT secret, SMTP password) — only on the company server, never in git.

## Go-live steps (when development and testing are complete)

1. Al Anwar IT provides the server (Ubuntu 24.04, Docker, fixed IP, ports 80/443), the DNS name from the web vendor,
   and the M365 mail relay.
2. Install self-hosted Supabase (Docker Compose) and the web front end; set the production secrets.
3. Apply `supabase/migrations` in order. Do **not** load `seed.sql` or `seed_phase2.sql`.
4. Run the security checks; test a backup **and a restore**.
5. Create the real administrator, HR and Finance accounts. Turn off public sign-up.
6. Enter the real master data (company, departments, grades, job titles, Omanisation targets with their sources).
7. Import the real employees, then upload documents.
8. HR checks a sample of records against the source files, then go live.

A separate deployment package (Docker Compose, nginx, backup/restore scripts, install guide) will be prepared before step 1.
