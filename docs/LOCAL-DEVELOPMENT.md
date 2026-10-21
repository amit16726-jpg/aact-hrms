# Local development on the laptop

The laptop runs the **same Supabase stack** (in Docker) that will later run on the company server,
with the **same database files** (`supabase/migrations`). Only the data differs: the laptop holds
**dummy data only** (`supabase/seed.sql`, then `supabase/seed_phase2.sql` for attendance and leave `supabase/seed_phase3.sql` for payroll `supabase/seed_phase4.sql` for letters and requests and `supabase/seed_phase5.sql` for recruitment).

## One-time setup (Windows 10/11)

1. **WSL 2** — open PowerShell *as Administrator*, run `wsl --install`, then restart the laptop.
2. **Docker Desktop** — install from docker.com. In Settings → General, keep "Use the WSL 2 based engine" ticked.
   Docker Desktop must be running whenever you work on the HRMS.
3. **Node.js 22 LTS** (or 20.19+) and **Git** — already installed if `node -v` and `git --version` work.
4. In the project folder:

   ```powershell
   npm ci
   npm run local:setup
   ```

   The first run downloads the Supabase images (a few GB, 5–15 minutes). It starts the local stack,
   creates the database from `supabase/migrations`, loads the dummy data and writes `.env.development.local`
   so that `npm run dev` talks to the laptop database.

## Daily work

| Task | Command |
|---|---|
| Start the local database (Docker Desktop running) | `npm run db:start` |
| Start the app | `npm run dev` → <http://localhost:5173> |
| Rebuild the database from scratch + dummy data | `npm run db:reset` |
| Database admin screen (Supabase Studio) | <http://127.0.0.1:54323> |
| Test e-mails (password reset, invitations) | <http://127.0.0.1:54324> (Mailpit) |
| Show local URLs and keys | `npm run db:status` |
| Stop the local database (data is kept) | `npm run db:stop` |

### Demo logins (password for all: `Demo@AACT2026`)

| E-mail | Role | What to test |
|---|---|---|
| admin@aact.test | Super administrator | users and roles, settings, everything |
| hr.manager@aact.test | HR manager | approvals of salary and Omanisation targets, document verification, sensitive documents |
| hr.officer@aact.test | HR officer | employee data entry, documents, salary and bank proposals |
| finance@aact.test | Finance | bank account approval, salary view |
| auditor@aact.test | Auditor | audit trail and access log, read-only |
| manager@aact.test | Line manager (Salim Al Harthy) | team view, team expiries |
| employee@aact.test | Employee (Ravi Kumar) | own record, own documents and salary |

The dummy data has 60 employees: managers, staff, workers, trainees, one person on notice and one who has left.
It also includes expired and soon-to-expire documents, missing documents, pending salary and bank approvals,
and a **dummy** Omanisation target of 40 %.

## Rules that keep go-live easy

1. **Every database change is a new migration file.** Run `npm run db:new <short_name>`, write the SQL in the new file
   under `supabase/migrations`, then run `npm run db:reset` to prove the whole database builds from zero.
   Never create or alter tables by hand in Studio: the company server would not get that change.
2. **Never edit a migration that has already been installed on test or production.** Add a new one instead.
3. **Dummy data only on the laptop.** Change `scripts/gen-seed.py`, then run `npm run seed:gen` and `npm run db:reset`.
   Attendance and leave demo data (`supabase/seed_phase2.sql`) is written by hand, uses dates relative to today and loads after `seed.sql`.
   Real employee data is loaded only on the company server.
4. **Nothing environment-specific in the code.** Addresses and keys live in `.env.*` files and server settings.
5. **Before every commit:** `npm run typecheck`, `npm test`, `npm run build`.
6. **Commit and push often** — GitHub is the only copy of the code that is not on the laptop.

## Troubleshooting

| Problem | Fix |
|---|---|
| `Cannot connect to the Docker daemon` | Start Docker Desktop and wait until it says "Running". |
| Port 54321/54322/54323 already in use | `npm run db:stop`, or close the other program using the port. |
| App says "not connected to its database" | `npm run env:local`, then restart `npm run dev`. |
| You want a clean database | `npm run db:reset` (removes all local data and reloads the dummy data). |
| Docker uses too much memory | Run `npm run db:stop` when you are not working on the HRMS. |
