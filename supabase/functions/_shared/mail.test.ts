import { describe, expect, it } from 'vitest';
import { graphMessage, processQueue, readConfig, restStore, sendUrl, tokenBody, type Fetch, type QueuedMail, type Store } from './mail';

const cfg = { tenantId: 'tenant-1', clientId: 'client-1', clientSecret: 's3cret', sender: 'hr@aact.om' };

function memStore(items: QueuedMail[]) {
  const marks: { id: string; ok: boolean; error?: string }[] = [];
  const store: Store = { claim: async () => items, mark: async (id, ok, error) => { marks.push({ id, ok, error }); } };
  return { store, marks };
}

function fakeFetch(handler: (url: string, body: string) => { status: number; body: string }) {
  const calls: { url: string; headers: Record<string, string>; body: string }[] = [];
  const f: Fetch = async (url, init) => {
    calls.push({ url, headers: init.headers, body: init.body });
    const r = handler(url, init.body);
    return { ok: r.status >= 200 && r.status < 300, status: r.status, text: async () => r.body };
  };
  return { f, calls };
}

describe('Microsoft 365 mail sender', () => {
  it('builds a plain-text Graph message without line breaks in the subject', () => {
    const m = graphMessage({ id: '1', to: 'a@b.om', subject: 'Leave\r\napproved', body: 'Line 1\nLine 2' });
    expect(m.message.subject).toBe('Leave approved');
    expect(m.message.body).toEqual({ contentType: 'Text', content: 'Line 1\nLine 2' });
    expect(m.message.toRecipients[0].emailAddress.address).toBe('a@b.om');
    expect(m.saveToSentItems).toBe(false);
  });

  it('uses the client-credentials flow and the sender mailbox', () => {
    expect(tokenBody(cfg)).toContain('grant_type=client_credentials');
    expect(tokenBody(cfg)).toContain('scope=https%3A%2F%2Fgraph.microsoft.com%2F.default');
    expect(sendUrl('hr@aact.om')).toBe('https://graph.microsoft.com/v1.0/users/hr%40aact.om/sendMail');
  });

  it('needs every secret and a valid sender', () => {
    const env = (o: Record<string, string>) => (k: string) => o[k];
    expect(readConfig(env({ M365_TENANT_ID: 't', M365_CLIENT_ID: 'c', M365_CLIENT_SECRET: 's', M365_SENDER: 'hr@aact.om' }))).not.toBeNull();
    expect(readConfig(env({ M365_TENANT_ID: 't', M365_CLIENT_ID: 'c', M365_CLIENT_SECRET: 's', M365_SENDER: 'not-an-email' }))).toBeNull();
    expect(readConfig(env({ M365_CLIENT_ID: 'c', M365_CLIENT_SECRET: 's', M365_SENDER: 'hr@aact.om' }))).toBeNull();
  });

  it('sends each message with one token and records success, Graph errors and bad addresses', async () => {
    const { store, marks } = memStore([
      { id: 'm1', to: 'ok@aact.om', subject: 'A', body: 'x' },
      { id: 'm2', to: 'busy@aact.om', subject: 'B', body: 'y' },
      { id: 'm3', to: 'broken', subject: 'C', body: 'z' },
    ]);
    const { f, calls } = fakeFetch((url, body) => {
      if (url.includes('login.microsoftonline.com')) return { status: 200, body: '{"access_token":"tok"}' };
      return body.includes('busy@aact.om') ? { status: 503, body: 'Service unavailable' } : { status: 202, body: '' };
    });
    const r = await processQueue(cfg, store, f);
    expect(r).toEqual({ claimed: 3, sent: 1, failed: 2 });
    expect(calls.filter((c) => c.url.includes('login.')).length).toBe(1);
    expect(calls.find((c) => c.url.includes('sendMail'))?.headers.Authorization).toBe('Bearer tok');
    expect(marks).toEqual([
      { id: 'm1', ok: true, error: undefined },
      { id: 'm2', ok: false, error: 'Graph 503: Service unavailable' },
      { id: 'm3', ok: false, error: 'Invalid recipient address' },
    ]);
  });

  it('marks the whole batch failed when Microsoft 365 sign-in fails, and does nothing on an empty queue', async () => {
    const a = memStore([{ id: 'm1', to: 'a@aact.om', subject: 'A', body: 'x' }]);
    const bad = fakeFetch(() => ({ status: 401, body: '{"error":"invalid_client"}' }));
    expect(await processQueue(cfg, a.store, bad.f)).toEqual({ claimed: 1, sent: 0, failed: 1 });
    expect(a.marks[0].error).toContain('sign-in failed (401)');
    const b = memStore([]);
    const none = fakeFetch(() => ({ status: 500, body: '' }));
    expect(await processQueue(cfg, b.store, none.f)).toEqual({ claimed: 0, sent: 0, failed: 0 });
    expect(none.calls.length).toBe(0);
  });

  it('talks to the database through the service-role REST functions', async () => {
    const { f, calls } = fakeFetch((url) => url.endsWith('mail_claim_batch') ? { status: 200, body: '[{"id":"m1","to":"a@b.om","subject":"S","body":"B"}]' } : { status: 204, body: '' });
    const s = restStore('https://x.supabase.co/', 'svc', f);
    expect((await s.claim(10))[0].id).toBe('m1');
    await s.mark('m1', false, 'oops');
    expect(calls[0].url).toBe('https://x.supabase.co/rest/v1/rpc/mail_claim_batch');
    expect(calls[0].headers.apikey).toBe('svc');
    expect(JSON.parse(calls[1].body)).toEqual({ p_id: 'm1', p_ok: false, p_error: 'oops' });
  });
});
