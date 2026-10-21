// AACT HRMS — send-mail edge function (Deno). Sends the e-mail outbox through Microsoft 365.
// Call it every few minutes (pg_cron + pg_net, see docs/ENVIRONMENTS.md) with header  x-cron-secret: <MAIL_CRON_SECRET>.
// Secrets: M365_TENANT_ID, M365_CLIENT_ID, M365_CLIENT_SECRET, M365_SENDER, MAIL_CRON_SECRET
// (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are provided by the platform).
import { processQueue, readConfig, restStore, type Fetch } from '../_shared/mail.ts';

declare const Deno: { env: { get(k: string): string | undefined }; serve(h: (r: Request) => Response | Promise<Response>): void };

const json = (status: number, body: unknown) => new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } });

function sameSecret(a: string, b: string) {
  if (!a || !b || a.length !== b.length) return false;
  let d = 0;
  for (let i = 0; i < a.length; i++) d |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return d === 0;
}

Deno.serve(async (req) => {
  if (req.method !== 'POST') return json(405, { error: 'POST only' });
  if (!sameSecret(req.headers.get('x-cron-secret') ?? '', Deno.env.get('MAIL_CRON_SECRET') ?? '')) return json(401, { error: 'Not allowed' });
  const cfg = readConfig((k) => Deno.env.get(k));
  if (!cfg) return json(500, { error: 'Microsoft 365 secrets are not set (M365_TENANT_ID, M365_CLIENT_ID, M365_CLIENT_SECRET, M365_SENDER).' });
  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const key = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '';
  const f: Fetch = (u, init) => fetch(u, init);
  try {
    return json(200, await processQueue(cfg, restStore(url, key, f), f, 25));
  } catch (e) {
    return json(500, { error: String(e) });
  }
});
