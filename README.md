# AACT HRMS

Human resources system for AACT (Oman): employee master, contracts, documents and expiry alerts, Omanisation,
roles and audit trail — in English and Arabic.

- Architecture, security model, test results and open legal points: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- Changes: [CHANGELOG.md](CHANGELOG.md)

## Run locally

```powershell
npm ci
copy .env.example .env.local   # then fill in the Supabase URL and publishable (anon) key
npm run dev
```

## Checks

```powershell
npm run typecheck
npm test
npm run build
```

Database tests (needs a local PostgreSQL 16+ on port 5433): `npm run db:test`

## Database

Migrations are in `supabase/migrations`, in order. They are idempotent (safe to re-run) and contain no destructive statements.
