import { useRef, useState } from 'react';
import { api, checkFile, signedUrl, uploadFile, type DocType, type EmpDocument, type EmployeeFile } from '../../lib/api';
import { useI18n } from '../../i18n';
import { Badge, Button, Check, DateText, DaysLeft, Empty, ErrorNote, Input, Loading, Modal, Select, Textarea, useAction, useAsync, useToast } from '../../components/ui';
import { useMasters } from '../../components/pickers';
import type { ConfirmFn } from './ProfileTab';

type Mode = { kind: 'add' } | { kind: 'replace'; doc: EmpDocument } | { kind: 'correct'; doc: EmpDocument };
interface Form { doc_type: string; doc_number: string; title: string; issue_date: string; expiry_date: string; issuing_authority: string; issue_place: string; notes: string }

export function DocumentsTab({ file, confirm }: { file: EmployeeFile; confirm: ConfirmFn }) {
  const { t, L, tk } = useI18n();
  const e = file.employee;
  const [history, setHistory] = useState(false);
  const { data, error, loading, reload } = useAsync(() => api.listDocuments(e.id, history), [e.id, history]);
  const types = useMasters<DocType & { id: string; is_active: boolean; name_ar: string; code: string }>('document_type', null);
  const [mode, setMode] = useState<Mode | null>(null);
  const [form, setForm] = useState<Form | null>(null);
  const [fileSel, setFileSel] = useState<File | null>(null);
  const fileRef = useRef<HTMLInputElement>(null);
  const { busy, run } = useAction();
  const { push } = useToast();

  if (loading && !data) return <Loading />;
  if (error) return <ErrorNote error={error} onRetry={reload} />;
  if (!data) return null;

  const typeOf = (code: string) => types.find((x) => x.code === code);
  const usable = types.filter((x) => x.is_active && (file.caps.docs_sensitive || !x.is_sensitive)
    && (x.applies_to === 'ALL' || (x.applies_to === 'OMANI') === e.is_omani));

  const openAdd = (code = '') => {
    setMode({ kind: 'add' }); setFileSel(null);
    setForm({ doc_type: code, doc_number: '', title: '', issue_date: '', expiry_date: '', issuing_authority: '', issue_place: '', notes: '' });
  };
  const openReplace = (doc: EmpDocument) => {
    setMode({ kind: 'replace', doc }); setFileSel(null);
    setForm({ doc_type: doc.doc_type, doc_number: '', title: doc.title ?? '', issue_date: '', expiry_date: '',
      issuing_authority: doc.issuing_authority ?? '', issue_place: doc.issue_place ?? '', notes: '' });
  };
  const openCorrect = (doc: EmpDocument) => {
    setMode({ kind: 'correct', doc }); setFileSel(null);
    setForm({ doc_type: doc.doc_type, doc_number: doc.doc_number ?? '', title: doc.title ?? '', issue_date: doc.issue_date ?? '',
      expiry_date: doc.expiry_date ?? '', issuing_authority: doc.issuing_authority ?? '', issue_place: doc.issue_place ?? '', notes: doc.notes ?? '' });
  };
  const close = () => { setMode(null); setForm(null); setFileSel(null); };

  const pickFile = (f: File | undefined) => {
    if (!f) return;
    const bad = checkFile(f);
    if (bad) { push(t(bad === 'FILE_SIZE' ? 'doc.file_size' : 'doc.file_type'), true); return; }
    setFileSel(f);
  };

  const submit = async () => {
    if (!form || !mode) return;
    const r = await run(async () => {
      let file_path: string | null = null;
      if (fileSel && mode.kind !== 'correct') file_path = await uploadFile(e.id, form.doc_type, fileSel);
      const base = {
        doc_type: form.doc_type, doc_number: form.doc_number.trim() || null, title: form.title.trim() || null,
        issue_date: form.issue_date || null, expiry_date: form.expiry_date || null,
        issuing_authority: form.issuing_authority.trim() || null, issue_place: form.issue_place.trim() || null, notes: form.notes.trim() || null,
      };
      if (mode.kind === 'correct') return api.saveDocument(e.id, { ...base, id: mode.doc.id });
      return api.saveDocument(e.id, {
        ...base, replace_id: mode.kind === 'replace' ? mode.doc.id : null,
        file_path, file_name: fileSel?.name ?? null, mime_type: fileSel?.type ?? null, file_size: fileSel?.size ?? null,
      });
    }, t('c.saved'));
    if (r) { close(); void reload(); }
  };

  const openFile = async (d: EmpDocument) => {
    // open the tab inside the click (popup blockers), then point it at the short-lived signed link
    const w = window.open('', '_blank');
    if (w) w.opener = null;
    const ok = await run(async () => {
      const f = await api.documentFile(d.id);
      const url = await signedUrl(f.file_path, 120);
      if (w) w.location.href = url; else window.location.assign(url);
      return true;
    });
    if (!ok && w) w.close();
  };

  const cancelDoc = async (d: EmpDocument) => {
    const reason = await confirm({ title: t('doc.cancel'), body: L(d.name_en, d.name_ar), reason: 'required', reasonLabel: t('doc.cancel_reason'), danger: true });
    if (reason === null) return;
    if (await run(() => api.cancelDocument(d.id, reason), t('c.saved'))) void reload();
  };
  const verify = async (d: EmpDocument) => {
    if (await run(() => api.verifyDocument(d.id), t('c.saved'))) void reload();
  };

  const tp = form ? typeOf(form.doc_type) : undefined;
  const checklistTone = { MISSING: 'bad', EXPIRED: 'bad', EXPIRING: 'warn', OK: 'ok' } as const;

  return (
    <div className="grid-side">
      <section className="panel">
        <div className="panel-head">
          <h2>{t('ed.tab_documents')}</h2>
          <div className="row">
            <Check label={t('doc.show_history')} checked={history} onChange={setHistory} />
            {file.caps.docs_write && <Button small kind="primary" onClick={() => openAdd()}>{t('doc.add')}</Button>}
          </div>
        </div>
        {data.scope === 'NON_SENSITIVE' && <div className="note" style={{ margin: '12px 20px 0' }}>{t('doc.sensitive_hidden')}</div>}
        {data.documents.length === 0 ? <Empty>{t('doc.empty')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('doc.type')}</th><th>{t('doc.number')}</th><th>{t('doc.expiry')}</th><th>{t('c.status')}</th><th /></tr></thead>
            <tbody>{data.documents.map((d) => (
              <tr key={d.id} style={d.is_current ? undefined : { opacity: 0.7 }}>
                <td data-label={t('doc.type')}>
                  {L(d.name_en, d.name_ar)} {d.is_sensitive && <Badge>{t('doc.sensitive')}</Badge>}
                  <span className="sub">{d.title}{d.version > 1 ? ` ${t('c.version')} ${d.version}` : ''}</span>
                </td>
                <td data-label={t('doc.number')} className="num">{d.doc_number ?? '—'}
                  {d.issuing_authority && <span className="sub">{d.issuing_authority}</span>}</td>
                <td data-label={t('doc.expiry')}>{d.expiry_date ? <><DateText v={d.expiry_date} />{d.is_current && <span className="sub"><DaysLeft days={d.days_left} /></span>}</> : '—'}</td>
                <td data-label={t('c.status')}>
                  <Badge tone={d.status === 'ACTIVE' ? (d.verified_at ? 'ok' : undefined) : d.status === 'CANCELLED' ? 'bad' : undefined}>{tk(`doc.${d.status}`, d.status)}</Badge>
                  <span className="sub">{d.verified_at ? t('doc.verified', { name: d.verified_by_name ?? '' }) : d.is_current ? t('doc.unverified') : (d.cancel_reason ?? '')}</span>
                </td>
                <td className="r">
                  <div className="row" style={{ justifyContent: 'flex-end', gap: 4 }}>
                    {d.file_path && <Button small kind="ghost" onClick={() => void openFile(d)}>{t('c.open')}</Button>}
                    {d.is_current && file.caps.docs_write && <>
                      <Button small kind="ghost" onClick={() => openReplace(d)}>{t('doc.replace')}</Button>
                      <Button small kind="ghost" onClick={() => openCorrect(d)}>{t('c.edit')}</Button>
                      {!d.verified_at && <Button small kind="ghost" onClick={() => void verify(d)}>{t('doc.verify')}</Button>}
                      <Button small kind="ghost" onClick={() => void cancelDoc(d)}>{t('c.cancel')}</Button>
                    </>}
                  </div>
                </td>
              </tr>))}
            </tbody></table></div>
        )}
      </section>

      <section className="panel">
        <div className="panel-head"><h2>{t('doc.checklist')}</h2></div>
        <ul className="panel-body" style={{ margin: 0, listStyle: 'none' }}>
          {data.checklist.map((c) => (
            <li key={c.doc_type} className="row" style={{ padding: '5px 0' }}>
              <span style={{ flex: 1 }}>{L(c.name_en, c.name_ar)}</span>
              <Badge tone={checklistTone[c.status]}>{tk(`doc.${c.status}`, c.status)}</Badge>
              {c.status === 'MISSING' && file.caps.docs_write && <Button small kind="ghost" onClick={() => openAdd(c.doc_type)}>{t('c.add')}</Button>}
            </li>
          ))}
        </ul>
      </section>

      <Modal open={!!mode} onClose={close} title={mode?.kind === 'replace' ? t('doc.replace') : mode?.kind === 'correct' ? t('doc.correct') : t('doc.add')}
        footer={<><Button onClick={close}>{t('c.cancel')}</Button>
          <Button kind="primary" busy={busy} disabled={!form?.doc_type} onClick={() => void submit()}>{busy && fileSel ? t('doc.uploading') : t('c.save')}</Button></>}>
        {form && (
          <div className="form-grid">
            {mode?.kind === 'replace' && <div className="span-2 note">{t('doc.replace_hint')}</div>}
            <Select className="span-2" label={t('doc.type')} required value={form.doc_type} disabled={mode?.kind !== 'add'}
              onChange={(ev) => setForm({ ...form, doc_type: ev.target.value })}>
              <option value="">{t('c.select')}</option>
              {(mode?.kind === 'add' ? usable : types).map((x) => <option key={x.code} value={x.code}>{L(x.name_en, x.name_ar)}</option>)}
            </Select>
            {tp?.has_number !== false && <Input label={t('doc.number')} required={!!tp?.has_number} ltr value={form.doc_number} onChange={(ev) => setForm({ ...form, doc_number: ev.target.value })} />}
            <Input label={t('doc.title')} value={form.title} onChange={(ev) => setForm({ ...form, title: ev.target.value })} />
            <Input type="date" label={t('doc.issue')} value={form.issue_date} onChange={(ev) => setForm({ ...form, issue_date: ev.target.value })} />
            {tp?.has_expiry !== false && <Input type="date" label={t('doc.expiry')} required={!!tp?.has_expiry} min={form.issue_date || undefined}
              value={form.expiry_date} onChange={(ev) => setForm({ ...form, expiry_date: ev.target.value })} />}
            <Input label={t('doc.authority')} value={form.issuing_authority} onChange={(ev) => setForm({ ...form, issuing_authority: ev.target.value })} />
            <Input label={t('doc.place')} value={form.issue_place} onChange={(ev) => setForm({ ...form, issue_place: ev.target.value })} />
            {mode?.kind !== 'correct' && (
              <div className="field span-2">
                <label htmlFor="doc-file">{t('doc.file')}</label>
                <input ref={fileRef} id="doc-file" type="file" accept="application/pdf,image/jpeg,image/png,image/webp"
                  onChange={(ev) => pickFile(ev.target.files?.[0])} />
                <span className="hint">{fileSel ? `${fileSel.name} (${Math.ceil(fileSel.size / 1024)} KB)` : t('doc.file_hint')}</span>
              </div>
            )}
            <Textarea className="span-2" label={t('c.notes')} value={form.notes} onChange={(ev) => setForm({ ...form, notes: ev.target.value })} />
          </div>
        )}
      </Modal>
    </div>
  );
}
