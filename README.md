# AACT HRMS

Human resources system for AACT (Oman): employee master, contracts, documents and expiry alerts, Omanisation,
attendance, shifts, overtime and leave under the Oman Labour Law, payroll with SPF, WPS file and end-of-service settlement,
employee self-service, letters with online verification, recruitment, onboarding and probation, e-mail through Microsoft 365, roles and audit trail — in English and Arabic.

- Architecture, security model, test results and open legal points: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Changes: [CHANGELOG.md](CHANGELOG.md)

## Run locally (laptop, dummy data)

Needs Node.js 20.19+ or 22.12+ (`node -v`) and Docker Desktop. Full guide: [docs/LOCAL-DEVELOPMENT.md](docs/LOCAL-DEVELOPMENT.md).

```powershell
npm ci
npm run local:setup   # starts local Supabase, builds the database, loads dummy data
npm run dev           # http://localhost:5173 — sign in as admin@aact.test / Demo@AACT2026
```

Environments and the path to the company server: [docs/ENVIRONMENTS.md](docs/ENVIRONMENTS.md).

## Checks

```powershell
npm run typecheck
npm test
npm run build
```

Database tests on plain PostgreSQL (developer/CI machine with PostgreSQL 16+ on port 5433 and bash): `npm run db:test`

## Database

Migrations are in `supabase/migrations`, in order. They are idempotent (safe to re-run) and contain no destructive statements.
New change → `npm run db:new <name>`. Masters (company, departments, designations, categories, pay components) → `supabase/seed_masters.sql`, used everywhere; no dummy employees. Cloud test reset → `scripts/reset-test-data.sql`. Company server: `deploy/README-SERVER.md`.

E-mail: `supabase/functions/send-mail` (Microsoft Graph). Set-up: [docs/ENVIRONMENTS.md](docs/ENVIRONMENTS.md#e-mail-through-microsoft-365).

Phone apps (Android APK / iPhone): `docs/MOBILE-APPS.md` — built by the *Mobile apps* GitHub Actions workflow or with `npm run mobile:android` / `npm run mobile:ios`.
