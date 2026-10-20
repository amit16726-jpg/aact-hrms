import { useState } from 'react';
import { api, type Target } from '../lib/api';
import { useI18n } from '../i18n';
import { useSession } from '../lib/session';
import { Badge, Button, DateText, Empty, ErrorNote, Input, Loading, Modal, Select, Textarea, useAction, useAsync, useConfirm } from '../components/ui';
import { MasterSelect } from '../components/pickers';
import { PageHead } from '../components/Layout';
import { fmtPct, todayMuscat } from '../lib/format';

interface Form { scope_type: string; scope_id: string | null; profession_code: string; target_pct: string; effective_from: string;
  effective_to: string; rule_basis: string; source_reference: string; notes: string }

export default function TargetsPage() {
  const { t, L, tk } = useI18n();
  const { me, can } = useSession();
  const [entityId, setEntityId] = useState(me?.entities[0]?.id ?? '');
  const { data, error, loading, reload, setData } = useAsync(() => api.listTargets(entityId || null), [entityId]);
  const [form, setForm] = useState<Form | null>(null);
  const { busy, run } = useAction();
  const confirm = useConfirm();

  const submit = async () => {
    if (!form) return;
    const r = await run(() => api.proposeTarget({ ...form, entity_id: entityId, target_pct: form.target_pct,
      effective_to: form.effective_to || null, profession_code: form.profession_code.trim() || null, notes: form.notes.trim() || null }), t('tg.PENDING'));
    if (r) { setData(r); setForm(null); }
  };
  const decide = async (x: Target, approve: boolean) => {
    const note = await confirm.ask({ title: `${fmtPct(x.target_pct)} — ${L(x.scope_name_en, x.scope_name_ar)}`, body: x.source_reference,
      reason: approve ? 'optional' : 'required', reasonLabel: t('ap.decision_note'), danger: !approve, okLabel: t(approve ? 'c.approve' : 'c.reject') });
    if (note === null) return;
    const r = await run(() => api.decideTarget(x.id, approve, note || null), t(approve ? 'ap.done_approve' : 'ap.done_reject'));
    if (r) setData(r);
  };
  const retire = async (x: Target) => {
    const note = await confirm.ask({ title: t('tg.retire_title'), body: x.source_reference, reason: 'required', danger: true, okLabel: t('tg.retire') });
    if (note === null) return;
    const r = await run(() => api.retireTarget(x.id, null, note), t('c.saved'));
    if (r) setData(r);
  };
  const set = (k: keyof Form, v: string | null) => setForm((s) => (s ? { ...s, [k]: v ?? '' } : s));

  return (
    <div className="stack">
      <PageHead title={t('tg.title')} sub={t('tg.maker_checker')} actions={can('RULES_PROPOSE') && entityId &&
        <Button kind="primary" onClick={() => setForm({ scope_type: 'ENTITY', scope_id: null, profession_code: '', target_pct: '', effective_from: todayMuscat(),
          effective_to: '', rule_basis: 'LEGAL', source_reference: '', notes: '' })}>{t('tg.propose')}</Button>} />
      {me && me.entities.length > 1 && (
        <div className="panel panel-pad"><div className="field" style={{ maxWidth: 300 }}>
          <label htmlFor="tg-ent">{t('c.company')}</label>
          <select id="tg-ent" className="select" value={entityId} onChange={(e) => setEntityId(e.target.value)}>
            {me.entities.map((en) => <option key={en.id} value={en.id}>{L(en.name_en, en.name_ar)}</option>)}
          </select></div></div>
      )}
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data || data.length === 0 ? <Empty>{t('tg.empty')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('tg.scope')}</th><th className="r">{t('tg.pct')}</th><th>{t('c.from')}</th><th>{t('c.to')}</th>
              <th>{t('tg.basis')}</th><th>{t('tg.source')}</th><th>{t('c.status')}</th><th /></tr></thead>
            <tbody>{data.map((x) => (
              <tr key={x.id}>
                <td data-label={t('tg.scope')}>{tk(`tg.${x.scope_type}`, x.scope_type)}<span className="sub">{L(x.scope_name_en, x.scope_name_ar)}</span></td>
                <td data-label={t('tg.pct')} className="r num">{fmtPct(x.target_pct)}</td>
                <td data-label={t('c.from')}><DateText v={x.effective_from} /></td>
                <td data-label={t('c.to')}>{x.effective_to ? <DateText v={x.effective_to} /> : '—'}</td>
                <td data-label={t('tg.basis')}>{tk(`tg.${x.rule_basis}`, x.rule_basis)}</td>
                <td data-label={t('tg.source')}>{x.source_reference}<span className="sub">{t('pay.proposed_by', { name: x.proposed_by_name ?? '' })}
                  {x.decided_by_name ? `; ${t('pay.decided_by', { name: x.decided_by_name })}` : ''}</span>
                  {x.decision_note && <span className="sub">{x.decision_note}</span>}</td>
                <td data-label={t('c.status')}><Badge tone={x.status === 'APPROVED' ? 'ok' : x.status === 'PENDING' ? 'warn' : x.status === 'REJECTED' ? 'bad' : undefined}>{tk(`tg.${x.status}`, x.status)}</Badge></td>
                <td className="r">
                  {x.status === 'PENDING' && x.can_decide && <div className="row" style={{ justifyContent: 'flex-end', gap: 4 }}>
                    <Button small kind="primary" busy={busy} onClick={() => void decide(x, true)}>{t('c.approve')}</Button>
                    <Button small kind="danger" busy={busy} onClick={() => void decide(x, false)}>{t('c.reject')}</Button></div>}
                  {x.status === 'PENDING' && !x.can_decide && <span className="muted" style={{ fontSize: 12.5 }}>{t('ap.yours')}</span>}
                  {x.status === 'APPROVED' && can('RULES_APPROVE') && <Button small kind="ghost" onClick={() => void retire(x)}>{t('tg.retire')}</Button>}
                </td>
              </tr>))}
            </tbody></table></div>
        )}
      </div>

      <Modal open={!!form} title={t('tg.propose')} onClose={() => setForm(null)}
        footer={<><Button onClick={() => setForm(null)}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} onClick={() => void submit()}>{t('c.save')}</Button></>}>
        {form && (
          <div className="form-grid">
            <Select label={t('tg.scope')} value={form.scope_type} onChange={(e) => setForm({ ...form, scope_type: e.target.value, scope_id: null })}>
              {['ENTITY', 'DEPARTMENT', 'JOB_TITLE', 'PROFESSION_CODE'].map((s) => <option key={s} value={s}>{tk(`tg.${s}`, s)}</option>)}
            </Select>
            {form.scope_type === 'DEPARTMENT' && <MasterSelect kind="department" entityId={entityId} label={t('c.department')} required value={form.scope_id} onChange={(v) => set('scope_id', v)} />}
            {form.scope_type === 'JOB_TITLE' && <MasterSelect kind="job_title" entityId={entityId} label={t('emp.job')} required value={form.scope_id} onChange={(v) => set('scope_id', v)} />}
            {form.scope_type === 'PROFESSION_CODE' && <Input label={t('tg.PROFESSION_CODE')} required ltr value={form.profession_code} onChange={(e) => set('profession_code', e.target.value)} />}
            {form.scope_type === 'ENTITY' && <div />}
            <Input type="number" min={0} max={100} step="0.01" label={t('tg.pct')} required value={form.target_pct} onChange={(e) => set('target_pct', e.target.value)} />
            <Select label={t('tg.basis')} required value={form.rule_basis} onChange={(e) => set('rule_basis', e.target.value)}>
              <option value="LEGAL">{t('tg.LEGAL')}</option><option value="COMPANY_POLICY">{t('tg.COMPANY_POLICY')}</option>
            </Select>
            <Input type="date" label={t('c.from')} required value={form.effective_from} onChange={(e) => set('effective_from', e.target.value)} />
            <Input type="date" label={t('c.to')} value={form.effective_to} min={form.effective_from || undefined} onChange={(e) => set('effective_to', e.target.value)} />
            <Input className="span-2" label={t('tg.source')} required hint={t('tg.source_hint')} value={form.source_reference} onChange={(e) => set('source_reference', e.target.value)} />
            <Textarea className="span-2" label={t('c.notes')} value={form.notes} onChange={(e) => set('notes', e.target.value)} />
          </div>
        )}
      </Modal>
      {confirm.node}
    </div>
  );
}
