import { useState } from 'react';
import { api, type Contract, type EmployeeFile } from '../../lib/api';
import { useI18n } from '../../i18n';
import { Badge, Button, DateText, Empty, Input, Modal, Select, Textarea, useAction, useAsync } from '../../components/ui';

type Form = {
  id: string | null; contract_type: string; contract_no: string; start_date: string; end_date: string; probation_days: string;
  notice_days: string; working_hours_per_week: string; mol_registration_no: string; document_id: string; notes: string;
};

const toForm = (c: Contract | null, start: string): Form => ({
  id: c?.id ?? null, contract_type: c?.contract_type ?? 'FIXED_TERM', contract_no: c?.contract_no ?? '', start_date: c?.start_date ?? start,
  end_date: c?.end_date ?? '', probation_days: c?.probation_days?.toString() ?? '', notice_days: c?.notice_days?.toString() ?? '',
  working_hours_per_week: c?.working_hours_per_week?.toString() ?? '', mol_registration_no: c?.mol_registration_no ?? '',
  document_id: c?.document_id ?? '', notes: c?.notes ?? '',
});

export function ContractTab({ file, onChange }: { file: EmployeeFile; onChange: (f: EmployeeFile) => void }) {
  const { t, L, tk } = useI18n();
  const e = file.employee;
  const active = file.contracts.find((c) => c.status === 'ACTIVE') ?? null;
  const [form, setForm] = useState<Form | null>(null);
  const { busy, run } = useAction();
  const docs = useAsync(() => (file.caps.docs_read ? api.listDocuments(e.id, false) : Promise.resolve(null)), [e.id, file.caps.docs_read]);
  const contractDocs = (docs.data?.documents ?? []).filter((d) => d.doc_type === 'CONTRACT_COPY');

  const set = (k: keyof Form, v: string) => setForm((s) => (s ? { ...s, [k]: v } : s));
  const submit = async () => {
    if (!form) return;
    const p = {
      id: form.id, contract_type: form.contract_type, contract_no: form.contract_no.trim() || null, start_date: form.start_date || null,
      end_date: form.contract_type === 'FIXED_TERM' ? form.end_date || null : null,
      probation_days: form.probation_days || null, notice_days: form.notice_days || null,
      working_hours_per_week: form.working_hours_per_week || null, mol_registration_no: form.mol_registration_no.trim() || null,
      document_id: form.document_id || null, notes: form.notes.trim() || null,
    };
    const r = await run(() => api.saveContract(e.id, p), t('c.saved'));
    if (r) { onChange(r); setForm(null); }
  };

  return (
    <section className="panel">
      <div className="panel-head">
        <h2>{t('ed.tab_contract')}</h2>
        {file.caps.edit && e.status !== 'SEPARATED' && (
          <div className="row">
            {active && <Button small onClick={() => setForm(toForm(active, active.start_date))}>{t('co.correct')}</Button>}
            <Button small kind="primary" onClick={() => setForm(toForm(null, active?.end_date ?? e.join_date))}>{t('co.new')}</Button>
          </div>
        )}
      </div>
      {file.contracts.length === 0 ? <Empty>{t('co.none')}</Empty> : (
        <div className="table-wrap"><table className="t cards">
          <thead><tr><th>{t('c.version')}</th><th>{t('co.type')}</th><th>{t('co.no')}</th><th>{t('co.start')}</th><th>{t('co.end')}</th>
            <th>{t('co.probation_days')}</th><th>{t('co.notice_days')}</th><th>{t('c.status')}</th></tr></thead>
          <tbody>{file.contracts.map((c) => (
            <tr key={c.id}>
              <td data-label={t('c.version')} className="num">{c.version}</td>
              <td data-label={t('co.type')}>{tk(`co.${c.contract_type}`, c.contract_type)}</td>
              <td data-label={t('co.no')} className="num">{c.contract_no ?? '—'}{c.mol_registration_no && <span className="sub">{c.mol_registration_no}</span>}</td>
              <td data-label={t('co.start')}><DateText v={c.start_date} /></td>
              <td data-label={t('co.end')}>{c.end_date ? <DateText v={c.end_date} /> : '—'}</td>
              <td data-label={t('co.probation_days')} className="num">{c.probation_days ?? '—'}</td>
              <td data-label={t('co.notice_days')} className="num">{c.notice_days ?? '—'}</td>
              <td data-label={t('c.status')}><Badge tone={c.status === 'ACTIVE' ? 'ok' : undefined}>{tk(`co.${c.status}`, c.status)}</Badge></td>
            </tr>))}
          </tbody></table></div>
      )}

      <Modal open={!!form} title={form?.id ? t('co.correct') : t('co.new')} onClose={() => setForm(null)} wide
        footer={<><Button onClick={() => setForm(null)}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} onClick={() => void submit()}>{t('c.save')}</Button></>}>
        {form && (
          <div className="form-grid">
            {!form.id && active && <div className="span-2 note">{t('co.supersede_hint')}</div>}
            <div className="span-2 note note-warn">{t('co.policy_hint')}</div>
            <Select label={t('co.type')} required value={form.contract_type} onChange={(ev) => set('contract_type', ev.target.value)}>
              <option value="FIXED_TERM">{t('co.FIXED_TERM')}</option><option value="INDEFINITE">{t('co.INDEFINITE')}</option>
            </Select>
            <Input label={t('co.no')} ltr value={form.contract_no} onChange={(ev) => set('contract_no', ev.target.value)} />
            <Input type="date" label={t('co.start')} required value={form.start_date} onChange={(ev) => set('start_date', ev.target.value)} />
            {form.contract_type === 'FIXED_TERM' && <Input type="date" label={t('co.end')} required min={form.start_date || undefined}
              value={form.end_date} onChange={(ev) => set('end_date', ev.target.value)} />}
            <Input type="number" min={0} max={365} label={t('co.probation_days')} value={form.probation_days} onChange={(ev) => set('probation_days', ev.target.value)} />
            <Input type="number" min={0} max={365} label={t('co.notice_days')} value={form.notice_days} onChange={(ev) => set('notice_days', ev.target.value)} />
            <Input type="number" min={0} max={84} step="0.5" label={t('co.hours')} value={form.working_hours_per_week} onChange={(ev) => set('working_hours_per_week', ev.target.value)} />
            <Input label={t('co.mol')} ltr value={form.mol_registration_no} onChange={(ev) => set('mol_registration_no', ev.target.value)} />
            {file.caps.docs_read && (
              <Select label={t('co.document')} value={form.document_id} onChange={(ev) => set('document_id', ev.target.value)}>
                <option value="">{t('c.none')}</option>
                {contractDocs.map((d) => <option key={d.id} value={d.id}>{L(d.name_en, d.name_ar)} {d.title ?? d.file_name ?? ''}</option>)}
              </Select>
            )}
            <Textarea className="span-2" label={t('c.notes')} value={form.notes} onChange={(ev) => set('notes', ev.target.value)} />
          </div>
        )}
      </Modal>
    </section>
  );
}
