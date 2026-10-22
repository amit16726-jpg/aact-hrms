# AACT HRMS — installation on the company server

This is the production set-up. **Real employee data lives only here** — never on the cloud test project or a laptop.

```
 staff browsers ──HTTPS──▶ aact-hrms-web (nginx: app + TLS) ──▶ supabase-kong ──▶ auth · rest · storage · functions
                                                                         └────▶ supabase-db (PostgreSQL 17)
```

Everything runs in Docker on one Linux server inside the company network. The web container serves the app and passes
`/rest/v1`, `/auth/v1`, `/storage/v1`, `/functions/v1` and `/realtime/v1` to Supabase, so the app and its data use one
address (for example `https://hr.aact.om`). Supabase Studio (the database admin screen) is **not** published; it is reached
through an SSH tunnel.

## 1. What IT prepares

| Item | Minimum |
|---|---|
| Server | Ubuntu Server 24.04 LTS, 4 vCPU, 8 GB RAM, 100 GB SSD (VM is fine) |
| Software | Docker Engine 26+ with the Compose plugin 2.24+, `git`, `openssl`, `rsync` |
| Network | A fixed internal IP; DNS name (e.g. `hr.aact.om`) pointing to it; ports 80 and 443 open from the office network / VPN only |
| Certificate | Company TLS certificate for the name (`fullchain.pem`, `privkey.pem`). Without one, a self-signed certificate is created (browsers warn). |
| E-mail | An SMTP account for password resets and invitations (Microsoft 365: `smtp.office365.com:587`, licensed mailbox with SMTP AUTH enabled) |
| Backup target | A second machine or NAS reachable with `rsync` over SSH for off-site copies |
| Biometric devices | Exported punch files (CSV) are imported in *Import punches*; no device connection is needed |

Do **not** open ports 5432, 6543 or 8000 to the network — the installer binds them to the server itself.

## 2. Install

```bash
sudo mkdir -p /opt/aact-hrms && cd /opt/aact-hrms
sudo unzip ~/aact-hrms-1.7.0.zip            # creates /opt/aact-hrms/aact-hrms
cd aact-hrms
sudo cp deploy/env.server.example deploy/.env
sudo nano deploy/.env                        # DOMAIN, PUBLIC_URL, SMTP_* (keep the file private)
# put the company certificate here (optional — otherwise a self-signed one is made):
sudo mkdir -p /opt/aact-hrms/certs && sudo cp fullchain.pem privkey.pem /opt/aact-hrms/certs/
sudo bash deploy/scripts/install.sh
```

The installer:
1. checks Docker;
2. downloads the **tested Supabase release `self-hosted/v0.8.3`** into `/opt/aact-hrms/supabase` and generates new secrets
   (`/opt/aact-hrms/supabase/.env` — **copy this file to the company password safe**);
3. turns off public sign-up and anonymous users, sets the address and SMTP;
4. starts Supabase and applies all database migrations (recorded in `aact_admin.migrations`);
5. copies the e-mail function;
6. builds and starts the web app with TLS;
7. installs the nightly backup (02:00) and a monthly restore test (`/etc/cron.d/aact-hrms`).

Then open `https://hr.aact.om`. Staff can install it as an app on Android, iPhone and computers from the account menu (*Install the app on this device*); HTTPS with a trusted certificate is required for this. The **first person to sign up** on the set-up page becomes the administrator — do this
immediately, then invite everyone else from *Users*.

### E-mail notifications (Microsoft 365)
1. Create the Entra ID app and mailbox policy as described in `docs/ENVIRONMENTS.md` (→ "E-mail through Microsoft 365").
2. Put `M365_TENANT_ID`, `M365_CLIENT_ID`, `M365_CLIENT_SECRET` and `M365_SENDER` in `deploy/.env` and run `sudo bash deploy/scripts/install.sh`
   again (it keeps everything else; `MAIL_CRON_SECRET` is generated for you).
3. Schedule the sender every 2 minutes (Studio → SQL editor; the address is internal, so nothing leaves the server except the mail itself):

```sql
select cron.schedule('hr-send-mail', '*/2 * * * *', $$
  select net.http_post(url := 'http://kong:8000/functions/v1/send-mail',
                       headers := jsonb_build_object('x-cron-secret', '<MAIL_CRON_SECRET from deploy/.env>', 'Content-Type', 'application/json'),
                       body := '{}'::jsonb) $$);
```
4. In the app: *Settings → E-mail notifications* → system address `https://hr.aact.om` → switch on → **Send me a test e-mail**.

## 3. Backups and restore

| What | When | Where |
|---|---|---|
| Database (`pg_dump`), uploaded documents, checksums, manifest | Every night 02:00 | `/opt/aact-hrms/backups/<date-time>/` (kept 30 days) |
| Off-site copy | After each backup, if `BACKUP_OFFSITE` is set | the second machine / NAS |
| Restore test into a scratch database | 1st of every month 03:30 | log: `/var/log/aact-hrms-backup.log` |

```bash
sudo bash deploy/scripts/backup.sh                                    # backup now
sudo bash deploy/scripts/restore.sh --verify /opt/aact-hrms/backups/20261101-020000   # prove a backup works (live system untouched)
sudo bash deploy/scripts/restore.sh --apply  /opt/aact-hrms/backups/20261101-020000   # replace live data (asks to type RESTORE; backs up first)
```

Keep at least one monthly backup for 12 months outside the server (payroll and SPF audits). Backups contain personal data:
store them encrypted (the NAS share or the disk), and record where they are in *Data protection → Processing register*.

## 4. Upgrades

1. Unzip the new release over `/opt/aact-hrms/aact-hrms` (your `deploy/.env` is kept).
2. `sudo bash deploy/scripts/update.sh` — backs up, applies new migrations, updates the e-mail function, rebuilds the app.
3. Staff refresh the browser (Ctrl+Shift+R).

`bash deploy/scripts/apply-migrations.sh --status` lists applied and pending migrations. A migration file that changed after it
was applied is reported and never re-run.

## 5. Day-to-day administration

| Task | Command |
|---|---|
| Status of all containers | `docker ps --format 'table {{.Names}}\t{{.Status}}'` |
| App logs | `docker logs --tail 100 aact-hrms-web` |
| Database admin (Studio) | from your PC: `ssh -L 8000:127.0.0.1:8000 admin@hr-server` then open `http://localhost:8000` (user/password in `supabase/.env`: `DASHBOARD_USERNAME` / `DASHBOARD_PASSWORD`) |
| Replace the certificate | copy new `fullchain.pem` / `privkey.pem` to `/opt/aact-hrms/certs`, then `docker restart aact-hrms-web` |
| Restart everything | `cd /opt/aact-hrms/supabase && docker compose restart && docker restart aact-hrms-web` |

## 6. Go-live checklist

- [ ] Server hardened: automatic security updates, SSH keys only, firewall (80/443 from office/VPN, 22 from IT only).
- [ ] `supabase/.env` and `deploy/.env` stored in the company password safe.
- [ ] Administrator account created; no demo logins (`*@aact.test`) exist here.
- [ ] AACT masters loaded (`supabase/seed_masters.sql`); company CR, SPF employer number and WPS details entered; pay component names and SPF flags checked in *Payroll → Set-up*.
- [ ] Legal values confirmed with the company's lawyer and recorded with dates: SPF rates and ceiling, gratuity rules, leave,
      overtime, probation, notice, discipline limits, injury reporting deadline (*Oman time rules*, *Payroll rules*, *Settings → HR policy limits*).
- [ ] Management payroll team named (at least three people, so an MG payroll can be calculated, verified and approved by different people); the first member is given the role on *Users*, then adds the others in *Settings*.
- [ ] Data migrated (see `docs/DATA-MIGRATION.md`) and checked by HR against the old system; MG pay group set before salaries are imported.
- [ ] **Parallel payroll run** for at least one month: both systems produce the same net pay per employee, differences explained.
- [ ] User acceptance test signed (`docs/UAT-PLAN.md`).
- [ ] Privacy notice reviewed by the lawyer, published, and staff asked to acknowledge it.
- [ ] First backup and a `--verify` restore test done; off-site copy confirmed.
