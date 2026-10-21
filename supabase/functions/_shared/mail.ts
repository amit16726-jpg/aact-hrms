// Shared, runtime-neutral logic for the send-mail edge function (no Deno or Node APIs here, so it is unit-tested with Vitest).
// Sends queued HR notifications through Microsoft 365 using the Microsoft Graph sendMail API with an app registration
// (client-credentials flow; application permission Mail.Send, limited to the sender mailbox by an Exchange access policy).

export interface QueuedMail { id: string; to: string; subject: string; body: string }
export interface MailConfig { tenantId: string; clientId: string; clientSecret: string; sender: string }
export type Fetch = (url: string, init: { method: string; headers: Record<string, string>; body: string }) => Promise<{ ok: boolean; status: number; text(): Promise<string> }>;

export const isEmail = (s: string) => /^[^@\s]+@[^@\s]+\.[^@\s]+$/.test(s);

export function tokenUrl(tenantId: string) {
  return `https://login.microsoftonline.com/${encodeURIComponent(tenantId)}/oauth2/v2.0/token`;
}

export function tokenBody(c: MailConfig) {
  return new URLSearchParams({
    client_id: c.clientId, client_secret: c.clientSecret, grant_type: 'client_credentials', scope: 'https://graph.microsoft.com/.default',
  }).toString();
}

export function sendUrl(sender: string) {
  return `https://graph.microsoft.com/v1.0/users/${encodeURIComponent(sender)}/sendMail`;
}

/** The Graph sendMail request body for one queued message (plain text, not kept in Sent Items). */
export function graphMessage(m: QueuedMail) {
  return {
    message: {
      subject: m.subject.replace(/[\r\n]+/g, ' ').slice(0, 250),
      body: { contentType: 'Text', content: m.body },
      toRecipients: [{ emailAddress: { address: m.to } }],
    },
    saveToSentItems: false,
  };
}

export function readConfig(env: (k: string) => string | undefined): MailConfig | null {
  const c = { tenantId: env('M365_TENANT_ID') ?? '', clientId: env('M365_CLIENT_ID') ?? '', clientSecret: env('M365_CLIENT_SECRET') ?? '', sender: env('M365_SENDER') ?? '' };
  return c.tenantId && c.clientId && c.clientSecret && isEmail(c.sender) ? c : null;
}

export interface Store {
  claim(limit: number): Promise<QueuedMail[]>;
  mark(id: string, ok: boolean, error?: string): Promise<void>;
}

/** Claim a batch, get one Graph token, send each message and record the result. Returns counts. */
export async function processQueue(cfg: MailConfig, store: Store, fetchFn: Fetch, limit = 20) {
  const batch = await store.claim(limit);
  const result = { claimed: batch.length, sent: 0, failed: 0 };
  if (!batch.length) return result;
  const tr = await fetchFn(tokenUrl(cfg.tenantId), {
    method: 'POST', headers: { 'Content-Type': 'application/x-www-form-urlencoded' }, body: tokenBody(cfg),
  });
  const tokenText = await tr.text();
  let token = '';
  try { token = tr.ok ? (JSON.parse(tokenText) as { access_token?: string }).access_token ?? '' : ''; } catch { token = ''; }
  if (!token) {
    const why = `Microsoft 365 sign-in failed (${tr.status}): ${tokenText.slice(0, 300)}`;
    for (const m of batch) { await store.mark(m.id, false, why); result.failed++; }
    return result;
  }
  for (const m of batch) {
    if (!isEmail(m.to)) { await store.mark(m.id, false, 'Invalid recipient address'); result.failed++; continue; }
    try {
      const r = await fetchFn(sendUrl(cfg.sender), {
        method: 'POST', headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' }, body: JSON.stringify(graphMessage(m)),
      });
      if (r.ok) { await store.mark(m.id, true); result.sent++; }
      else { await store.mark(m.id, false, `Graph ${r.status}: ${(await r.text()).slice(0, 300)}`); result.failed++; }
    } catch (e) {
      await store.mark(m.id, false, `Network error: ${String(e).slice(0, 300)}`); result.failed++;
    }
  }
  return result;
}

/** Store backed by the two service-role database functions, called through the REST API. */
export function restStore(supabaseUrl: string, serviceKey: string, fetchFn: Fetch): Store {
  const call = async (fn: string, args: Record<string, unknown>) => {
    const r = await fetchFn(`${supabaseUrl.replace(/\/$/, '')}/rest/v1/rpc/${fn}`, {
      method: 'POST', headers: { apikey: serviceKey, Authorization: `Bearer ${serviceKey}`, 'Content-Type': 'application/json' }, body: JSON.stringify(args),
    });
    const t = await r.text();
    if (!r.ok) throw new Error(`${fn} failed (${r.status}): ${t.slice(0, 300)}`);
    return t ? JSON.parse(t) as unknown : null;
  };
  return {
    claim: async (limit) => ((await call('mail_claim_batch', { p_limit: limit })) as QueuedMail[] | null) ?? [],
    mark: async (id, ok, error) => { await call('mail_mark', { p_id: id, p_ok: ok, p_error: error ?? null }); },
  };
}
