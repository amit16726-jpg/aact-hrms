// AACT HRMS — translate edge function (Deno). Translates an announcement title and message English <-> Arabic.
// Called from the app with the person's sign-in (supabase.functions.invoke). The database checks the ENGAGE_MANAGE
// permission and the daily limit and records the request (hr_translate_begin) before the text is sent for translation.
// Secrets: ANTHROPIC_API_KEY (required), TRANSLATE_MODEL (optional, default claude-sonnet-5-5).
// (SUPABASE_URL and SUPABASE_ANON_KEY are provided by the platform.)
import { beginRequest, mergeGlossary, readConfig, readRequest, translate, type Fetch } from '../_shared/translate.ts';

declare const Deno: { env: { get(k: string): string | undefined }; serve(h: (r: Request) => Response | Promise<Response>): void };

const CORS = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};
const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { ...CORS, 'Content-Type': 'application/json; charset=utf-8' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: CORS });
  if (req.method !== 'POST') return json(405, { error: 'INVALID: POST only.' });

  const auth = req.headers.get('Authorization') ?? '';
  if (!/^Bearer\s+\S+/.test(auth)) return json(401, { error: 'NOT_SIGNED_IN: Please sign in again.' });

  let raw: unknown;
  try { raw = await req.json(); } catch { return json(400, { error: 'INVALID: The request is not valid JSON.' }); }
  const r = readRequest(raw);
  if (!r.ok) return json(400, { error: r.error });

  const cfg = readConfig((k) => Deno.env.get(k));
  if (!cfg) return json(503, { error: 'TRANSLATE_OFF: Translation is not set up on this server (ANTHROPIC_API_KEY is missing).' });

  const url = Deno.env.get('SUPABASE_URL') ?? '';
  const anon = Deno.env.get('SUPABASE_ANON_KEY') ?? '';
  const f: Fetch = (u, init) => fetch(u, init);
  try {
    const b = await beginRequest(url, anon, auth, r.req, f);
    if (!b.ok) return json(b.status, { error: b.error });
    const out = await translate(cfg, r.req, mergeGlossary(b.glossary), f);
    return json(200, { ...out, model: cfg.model });
  } catch (e) {
    const msg = e instanceof Error ? e.message : String(e);
    return json(502, { error: /^[A-Z_]{3,40}:/.test(msg) ? msg : `TRANSLATE_FAILED: ${msg.slice(0, 300)}` });
  }
});
