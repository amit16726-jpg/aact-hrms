#!/usr/bin/env node
// Writes .env.development.local from the running local Supabase stack, so `npm run dev`
// talks to the laptop database. Production builds (`npm run build`, Vercel, company server)
// never read this file.
import { execSync } from 'node:child_process';
import { writeFileSync } from 'node:fs';

let out;
try {
  out = execSync('npx supabase status -o env', { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
} catch (e) {
  console.error('Local Supabase is not running. Start Docker Desktop, then run:  npm run db:start');
  console.error(String(e.stderr || e.message));
  process.exit(1);
}
const vars = {};
for (const line of out.split(/\r?\n/)) {
  const m = line.match(/^([A-Z_]+)="?([^"]*)"?$/);
  if (m) vars[m[1]] = m[2];
}
const url = vars.API_URL;
const key = vars.ANON_KEY || vars.PUBLISHABLE_KEY;
if (!url || !key) {
  console.error('Could not read API_URL / ANON_KEY from `supabase status -o env`. Output was:\n' + out);
  process.exit(1);
}
writeFileSync('.env.development.local',
  '# Written by `npm run env:local` — local laptop stack (dummy data only). Not committed to git.\n' +
  `VITE_SUPABASE_URL=${url}\nVITE_SUPABASE_ANON_KEY=${key}\nVITE_ENV_LABEL=LOCAL\n`);
console.log(`.env.development.local written → ${url}`);
console.log(`Studio (database admin): ${vars.STUDIO_URL || 'http://127.0.0.1:54323'}`);
console.log(`Mailpit (test e-mails):  ${vars.INBUCKET_URL || vars.MAILPIT_URL || 'http://127.0.0.1:54324'}`);
