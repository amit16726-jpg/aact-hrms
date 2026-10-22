import { useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { api } from '../lib/api';
import { useI18n, type Key } from '../i18n';
import { useSession } from '../lib/session';
import { Badge, Button, Check, Empty, ErrorNote, Input, Loading, Modal, Select, Tabs, Textarea, useAction, useAsync } from '../components/ui';
import { clearMasterCache, CountrySelect, EmployeePicker, MasterSelect } from '../components/pickers';
import { PageHead } from '../components/Layout';
import { fmtMoney } from '../lib/format';
import { splitAliases } from '../lib/aliases';

type Kind = 'entity' | 'location' | 'cost_centre' | 'department' | 'grade' | 'job_title' | 'category' | 'document_type';
type FType = 'text' | 'textarea' | 'number' | 'money' | 'bool' | 'select' | 'master' | 'intarray' | 'textarray' | 'country' | 'employee';
interface FDef { key: string; label: Key; type: FType; required?: boolean; ltr?: boolean; options?: [string, Key][]; master?: Kind;
  hint?: Key; rule?: boolean; wide?: boolean; upper?: boolean }

const common: FDef[] = [
  { key: 'code', label: 'c.code', type: 'text', required: true, ltr: true, upper: true },
  { key: 'name_en', label: 'c.name_en', type: 'text', required: true },
  { key: 'name_ar', label: 'c.name_ar', type: 'text' },
];

const aliases: FDef = { key: 'aliases', label: 'org.f_aliases', type: 'textarray', hint: 'org.f_aliases_hint', wide: true };

const DEFS: Record<Kind, { title: Key; fields: FDef[]; cols: string[] }> = {
  entity: { title: 'org.entity', cols: ['cr_number', 'country'], fields: [...common,
    { key: 'cr_number', label: 'org.f_cr', type: 'text', ltr: true }, { key: 'mol_establishment_no', label: 'org.f_mol', type: 'text', ltr: true },
    { key: 'sector', label: 'org.f_sector', type: 'text' }, { key: 'country', label: 'org.f_country', type: 'country' },
    { key: 'currency', label: 'org.f_currency', type: 'text', ltr: true, upper: true }, { key: 'address', label: 'org.f_address', type: 'textarea', wide: true }] },
  location: { title: 'org.location', cols: ['location_type', 'city'], fields: [...common,
    { key: 'location_type', label: 'org.f_type', type: 'select', options: [['FACTORY', 'loc.FACTORY'], ['OFFICE', 'loc.OFFICE'], ['WAREHOUSE', 'loc.WAREHOUSE'], ['SITE', 'loc.SITE'], ['ACCOMMODATION', 'loc.ACCOMMODATION']] },
    { key: 'city', label: 'org.f_city', type: 'text' }, { key: 'governorate', label: 'org.f_governorate', type: 'text' },
    { key: 'address', label: 'org.f_address', type: 'textarea', wide: true }] },
  cost_centre: { title: 'org.cost_centre', cols: ['gl_code'], fields: [...common, { key: 'gl_code', label: 'org.f_gl', type: 'text', ltr: true }] },
  department: { title: 'org.department', cols: ['aliases', 'parent_id', 'cost_centre_id'], fields: [...common,
    { key: 'parent_id', label: 'org.f_parent', type: 'master', master: 'department' },
    { key: 'cost_centre_id', label: 'org.f_cost_centre', type: 'master', master: 'cost_centre' },
    { key: 'head_employee_id', label: 'org.f_head', type: 'employee' }, aliases] },
  grade: { title: 'org.grade', cols: ['level', 'min_basic', 'max_basic'], fields: [...common,
    { key: 'level', label: 'org.f_level', type: 'number' }, { key: 'min_basic', label: 'org.f_min', type: 'money' }, { key: 'max_basic', label: 'org.f_max', type: 'money' }] },
  job_title: { title: 'org.job_title', cols: ['aliases', 'profession_code', 'omani_only'], fields: [...common,
    { key: 'profession_code', label: 'org.f_profession', type: 'text', ltr: true }, aliases,
    { key: 'description', label: 'org.f_description', type: 'textarea', wide: true },
    { key: 'required_qualifications', label: 'org.f_qualifications', type: 'textarea', wide: true },
    { key: 'omani_only', label: 'org.f_omani_only', type: 'bool', rule: true },
    { key: 'omani_only_verified', label: 'org.f_omani_verified', type: 'bool', rule: true },
    { key: 'omani_only_source', label: 'org.f_omani_source', type: 'text', rule: true, wide: true }] },
  category: { title: 'org.category', cols: ['pay_basis', 'counts_for_omanisation'], fields: [...common,
    { key: 'pay_basis', label: 'org.f_pay_basis', type: 'select', options: [['MONTHLY', 'pb.MONTHLY'], ['DAILY', 'pb.DAILY'], ['HOURLY', 'pb.HOURLY']] },
    { key: 'counts_for_omanisation', label: 'org.f_counts', type: 'bool' }] },
  document_type: { title: 'org.document_type', cols: ['category', 'applies_to', 'is_mandatory', 'has_expiry'], fields: [...common,
    { key: 'category', label: 'org.f_category', type: 'select', required: true, options: (['IDENTITY', 'IMMIGRATION', 'EMPLOYMENT', 'QUALIFICATION', 'MEDICAL', 'LICENCE', 'POLICY', 'DISCIPLINARY', 'OTHER'] as const).map((c) => [c, `dc.${c}` as Key]) },
    { key: 'applies_to', label: 'org.f_applies', type: 'select', options: [['ALL', 'ap_to.ALL'], ['OMANI', 'ap_to.OMANI'], ['EXPAT', 'ap_to.EXPAT']] },
    { key: 'is_mandatory', label: 'org.f_mandatory', type: 'bool' }, { key: 'allow_multiple', label: 'org.f_multiple', type: 'bool' },
    { key: 'has_number', label: 'org.f_has_number', type: 'bool' }, { key: 'has_expiry', label: 'org.f_has_expiry', type: 'bool' },
    { key: 'alert_days', label: 'org.f_alert_days', type: 'intarray', hint: 'org.f_alert_hint' },
    { key: 'is_sensitive', label: 'org.f_sensitive', type: 'bool' },
    { key: 'rule_basis', label: 'org.f_rule_basis', type: 'select', options: [['COMPANY_POLICY', 'tg.COMPANY_POLICY'], ['LEGAL', 'tg.LEGAL']] },
    { key: 'rule_reference', label: 'org.f_rule_ref', type: 'text' }, { key: 'sort', label: 'org.f_sort', type: 'number' }] },
};

type Row = Record<string, unknown> & { id?: string; code: string; name_en: string; name_ar: string | null; is_active: boolean };

export default function OrganisationPage() {
  const { t, L, tk } = useI18n();
  const { me, can, reload: reloadMe } = useSession();
  const [params, setParams] = useSearchParams();
  const kind = (params.get('kind') ?? 'department') as Kind;
  const [entityId, setEntityId] = useState(me?.entities[0]?.id ?? '');
  const def = DEFS[kind] ?? DEFS.department;
  const scoped = kind !== 'entity' && kind !== 'document_type';
  const { data, error, loading, reload } = useAsync(() => (scoped && !entityId ? Promise.resolve([] as Row[]) : api.listMaster<Row>(kind, scoped ? entityId : null)), [kind, entityId]);
  const [edit, setEdit] = useState<{ row: Record<string, unknown>; isNew: boolean; headLabel?: string | null } | null>(null);
  const { busy, run } = useAction();
  const writable = can('ORG_WRITE');
  const names = new Map((data ?? []).map((r) => [String(r.id ?? r.code), L(r.name_en, r.name_ar)]));

  const save = async () => {
    if (!edit) return;
    const row: Record<string, unknown> = {};
    for (const f of def.fields) {
      if (f.rule && !can('RULES_APPROVE')) continue;
      let v = edit.row[f.key];
      if (f.type === 'number') v = v === '' || v === null || v === undefined ? null : Number(v);
      if (f.type === 'money') v = v === '' || v === null || v === undefined ? null : String(v).replace(/,/g, '');
      if (f.type === 'intarray') v = String(v ?? '').split(/[,\s،]+/).filter(Boolean).map(Number).filter((n) => Number.isInteger(n) && n > 0);
      if (f.type === 'textarray') v = splitAliases(v);
      if (f.type === 'bool') v = !!v;
      if (typeof v === 'string') v = v.trim() === '' ? null : (f.upper ? v.trim().toUpperCase() : v.trim());
      row[f.key] = v;
    }
    row.is_active = edit.row.is_active !== false;
    if (!edit.isNew && edit.row.id) row.id = edit.row.id;
    if (edit.isNew && scoped) row.entity_id = entityId;
    const r = await run(() => api.saveMaster(kind, row), t('c.saved'));
    if (r) { clearMasterCache(); setEdit(null); void reload(); if (kind === 'entity') void reloadMe(); }
  };

  const cell = (r: Row, k: string) => {
    const v = r[k];
    const f = def.fields.find((x) => x.key === k);
    if (f?.type === 'bool') return v ? t('c.yes') : '—';
    if (f?.type === 'money') return v === null || v === undefined ? '—' : fmtMoney(v as number);
    if (f?.type === 'master') return v ? (kind === f.master ? names.get(String(v)) : '✓') ?? '—' : '—';
    if (f?.type === 'select') { const o = f.options?.find(([val]) => val === v); return o ? t(o[1]) : String(v ?? '—'); }
    if (Array.isArray(v)) return v.join(', ');
    return v === null || v === undefined || v === '' ? '—' : String(v);
  };

  const renderField = (f: FDef) => {
    const row = edit!.row;
    const val = row[f.key];
    const set = (v: unknown) => setEdit({ ...edit!, row: { ...row, [f.key]: v } });
    const disabled = !writable || (f.rule && !can('RULES_APPROVE')) || (kind === 'document_type' && f.key === 'code' && !edit!.isNew);
    const cls = f.wide || f.type === 'textarea' ? 'span-2' : undefined;
    switch (f.type) {
      case 'bool': return <div key={f.key} className={cls ?? ''}><Check label={t(f.label)} checked={!!val} disabled={disabled} onChange={set} /></div>;
      case 'textarea': return <Textarea key={f.key} className={cls} label={t(f.label)} value={String(val ?? '')} disabled={disabled} onChange={(e) => set(e.target.value)} />;
      case 'select': return (
        <Select key={f.key} label={t(f.label)} required={f.required} value={String(val ?? '')} disabled={disabled} onChange={(e) => set(e.target.value)}>
          {!f.required && <option value="">{t('c.select')}</option>}
          {f.options!.map(([v, k]) => <option key={v} value={v}>{t(k)}</option>)}
        </Select>);
      case 'master': return <MasterSelect key={f.key} kind={f.master!} entityId={entityId} label={t(f.label)} value={val as string | null}
        exclude={kind === f.master ? (row.id as string | undefined) : undefined} onChange={set} />;
      case 'country': return <CountrySelect key={f.key} label={t(f.label)} value={val as string | null} onChange={set} />;
      case 'employee': return <EmployeePicker key={f.key} label={t(f.label)} value={(val as string | null) ?? null} valueLabel={edit!.headLabel}
        onChange={(id, lbl) => setEdit({ ...edit!, headLabel: lbl, row: { ...row, [f.key]: id } })} />;
      case 'textarray': return <Input key={f.key} className={cls} label={t(f.label)} hint={f.hint ? t(f.hint) : undefined} disabled={disabled}
        value={Array.isArray(val) ? val.join(', ') : String(val ?? '')} onChange={(e) => set(e.target.value)} />;
      case 'intarray': return <Input key={f.key} label={t(f.label)} hint={f.hint ? t(f.hint) : undefined} ltr disabled={disabled}
        value={Array.isArray(val) ? val.join(', ') : String(val ?? '')} onChange={(e) => set(e.target.value)} />;
      default: return <Input key={f.key} className={cls} label={t(f.label)} required={f.required} ltr={f.ltr} disabled={disabled}
        inputMode={f.type === 'number' || f.type === 'money' ? 'decimal' : undefined}
        value={val === null || val === undefined ? '' : String(val)} onChange={(e) => set(e.target.value)} />;
    }
  };

  const tabs = (Object.keys(DEFS) as Kind[]).map((k) => ({ id: k, label: t(DEFS[k].title) }));
  const newRow = (): Record<string, unknown> => {
    const r: Record<string, unknown> = { is_active: true };
    if (kind === 'entity') { r.country = 'OM'; r.currency = 'OMR'; }
    if (kind === 'location') r.location_type = 'FACTORY';
    if (kind === 'category') { r.pay_basis = 'MONTHLY'; r.counts_for_omanisation = true; }
    if (kind === 'grade') r.level = 1;
    if (kind === 'document_type') Object.assign(r, { category: 'OTHER', applies_to: 'ALL', has_number: true, alert_days: [90, 60, 30], rule_basis: 'COMPANY_POLICY', sort: 100 });
    return r;
  };

  return (
    <div className="stack">
      <PageHead title={t('org.title')} actions={writable && (!scoped || entityId) &&
        <Button kind="primary" onClick={() => setEdit({ row: newRow(), isNew: true })}>{t('org.new')}</Button>} />
      <Tabs tabs={tabs} value={kind} label={t('org.title')} onChange={(k) => { const p = new URLSearchParams(params); p.set('kind', k); setParams(p, { replace: true }); }} />
      {scoped && me && me.entities.length > 1 && (
        <div className="field" style={{ maxWidth: 300 }}>
          <label htmlFor="org-ent">{t('c.company')}</label>
          <select id="org-ent" className="select" value={entityId} onChange={(e) => setEntityId(e.target.value)}>
            {me.entities.map((en) => <option key={en.id} value={en.id}>{L(en.name_en, en.name_ar)}</option>)}
          </select>
        </div>
      )}
      {kind === 'job_title' && <div className="note">{t('org.omani_only_rule')}</div>}
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {scoped && !entityId ? <Empty>{t('org.choose_company')}</Empty> : loading && !data ? <Loading /> : !data || data.length === 0 ? <Empty>{t('org.empty')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('c.code')}</th><th>{t('emp.name')}</th>{def.cols.map((c) => <th key={c}>{t(def.fields.find((f) => f.key === c)!.label)}</th>)}<th>{t('c.status')}</th></tr></thead>
            <tbody>{data.map((r) => (
              <tr key={String(r.id ?? r.code)} className="clickable" onClick={() => setEdit({ row: { ...r }, isNew: false })}>
                <td data-label={t('c.code')} className="num">{r.code}</td>
                <td data-label={t('emp.name')}>{L(r.name_en, r.name_ar)}</td>
                {def.cols.map((c) => <td key={c} data-label={t(def.fields.find((f) => f.key === c)!.label)}>
                  {c === 'omani_only' && r.omani_only ? <Badge tone="warn">{t('org.f_omani_only')}</Badge> : cell(r, c)}</td>)}
                <td data-label={t('c.status')}><Badge tone={r.is_active ? 'ok' : undefined}>{r.is_active ? t('c.active') : t('c.inactive')}</Badge></td>
              </tr>))}
            </tbody></table></div>
        )}
      </div>

      <Modal open={!!edit} title={`${t(def.title)}: ${edit?.isNew ? t('org.new') : String(edit?.row.code ?? '')}`} onClose={() => setEdit(null)} wide
        footer={<><Button onClick={() => setEdit(null)}>{t('c.cancel')}</Button>
          {writable && <Button kind="primary" busy={busy} onClick={() => void save()}>{t('c.save')}</Button>}</>}>
        {edit && (
          <div className="form-grid">
            {def.fields.map(renderField)}
            <div className="span-2"><Check label={t('c.active')} checked={edit.row.is_active !== false} disabled={!writable}
              onChange={(v) => setEdit({ ...edit, row: { ...edit.row, is_active: v } })} /></div>
            {kind === 'document_type' && <div className="span-2 muted" style={{ fontSize: 13 }}>{tk('cp.missing_hint')}</div>}
          </div>
        )}
      </Modal>
    </div>
  );
}
