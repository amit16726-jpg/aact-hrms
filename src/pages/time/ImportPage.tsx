import { useMemo, useState } from 'react';
import { tapi, type PunchBatch } from '../../lib/api_time';
import { useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import { Button, Check, Empty, ErrorNote, Input, Loading, Modal, Select, Tabs, useAction, useAsync, useToast } from '../../components/ui';
import { EmployeePicker } from '../../components/pickers';
import { PageHead } from '../../components/Layout';
import { EmpCell, EntitySelect, useEntity } from '../../components/time';
import { buildPunches, guessMap, parseCsv, type DateFmt, type PunchMap } from '../../lib/punches';
import { fmtDate, fmtDateTime } from '../../lib/format';

const CHUNK = 5000;
type RefKind = 'EMPLOYEE_NO' | 'DEVICE_ID' | 'CIVIL';

export default function ImportPage() {
  const { t } = useI18n();
  const [tab, setTab] = useState<'file' | 'history' | 'devices'>('file');
  const [entity, setEntity] = useEntity();
  return (
    <div className="stack">
      <PageHead title={t('imp.title')} />
      <div className="panel panel-pad row"><EntitySelect value={entity} onChange={setEntity} /></div>
      <Tabs tabs={[{ id: 'file', label: t('imp.file') }, { id: 'history', label: t('imp.history') }, { id: 'devices', label: t('imp.devices') }]}
        value={tab} onChange={setTab} label={t('imp.title')} />
      {tab === 'file' && <FileTab entity={entity} onDone={() => setTab('history')} />}
      {tab === 'history' && <HistoryTab entity={entity} />}
      {tab === 'devices' && <DevicesTab entity={entity} />}
    </div>
  );
}

function FileTab({ entity, onDone }: { entity: string; onDone: () => void }) {
  const { t } = useI18n();
  const { can } = useSession();
  const { push } = useToast();
  const { busy, run } = useAction();
  const [fileName, setFileName] = useState('');
  const [rows, setRows] = useState<string[][]>([]);
  const [refKind, setRefKind] = useState<RefKind>('EMPLOYEE_NO');
  const [device, setDevice] = useState('DEFAULT');
  const [separate, setSeparate] = useState(false);
  const [map, setMap] = useState<PunchMap>({ ref: 0, datetime: 1, date: null, time: null, dir: null, fmt: 'DMY', header: true });
  const [progress, setProgress] = useState<string | null>(null);

  const cols = rows[0]?.length ?? 0;
  const headers = useMemo(() => (rows[0] ?? []).map((h, i) => `${i + 1}: ${h.slice(0, 30)}`), [rows]);
  const built = useMemo(() => (rows.length ? buildPunches(rows, map) : { ok: [], bad: [] }), [rows, map]);

  const load = async (f: File) => {
    const text = await f.text();
    const r = parseCsv(text).filter((x) => x.some((c) => c.trim() !== ''));
    setFileName(f.name); setRows(r);
    const g = guessMap(r[0] ?? []);
    const sep = g.datetime === null || g.datetime === undefined;
    setSeparate(sep && g.date !== null && g.date !== undefined);
    setMap((m) => ({ ...m, ref: g.ref ?? 0, datetime: sep ? null : g.datetime ?? null, date: sep ? g.date ?? null : null, time: sep ? g.time ?? null : null, dir: g.dir ?? null }));
  };

  const colSelect = (label: Key, value: number | null, onChange: (v: number | null) => void, optional = false) => (
    <Select label={t(label)} value={value === null ? '' : String(value)} onChange={(e) => onChange(e.target.value === '' ? null : Number(e.target.value))}>
      {optional && <option value="">{t('imp.none_col')}</option>}
      {Array.from({ length: cols }, (_, i) => <option key={i} value={i}>{headers[i] ?? i + 1}</option>)}
    </Select>);

  const doImport = async () => {
    const all = built.ok;
    let ok = 0; let dup = 0; let err = 0;
    for (let i = 0; i < all.length; i += CHUNK) {
      setProgress(`${Math.min(i + CHUNK, all.length)} / ${all.length}`);
      const part = all.slice(i, i + CHUNK);
      const r = await run(() => tapi.importPunches({ entity_id: entity || null, file_name: fileName, ref_kind: refKind,
        device_code: refKind === 'DEVICE_ID' ? device : null, rows: part.map((p) => ({ ref: p.ref, at: p.at, dir: p.dir })) }));
      if (!r) { setProgress(null); return; }
      ok += r.rows_imported; dup += r.rows_duplicate; err += r.rows_error;
    }
    setProgress(null);
    push(t('imp.done', { ok, dup, err }), err > 0);
    setRows([]); setFileName('');
    onDone();
  };

  if (!can('ATT_WRITE')) return <Empty>{t('err.NOT_ALLOWED')}</Empty>;
  return (
    <div className="stack">
      <section className="panel panel-pad stack">
        <label className="btn btn-primary" style={{ alignSelf: 'flex-start' }}>{t('imp.file')}
          <input type="file" accept=".csv,.txt,text/csv,text/plain" hidden onChange={(e) => { const f = e.target.files?.[0]; e.target.value = ''; if (f) void load(f); }} /></label>
        <span className="muted">{fileName || t('imp.file_hint')}</span>
        {rows.length > 0 && (
          <div className="form-grid">
            <Select label={t('imp.ref_kind')} value={refKind} onChange={(e) => setRefKind(e.target.value as RefKind)}>
              {(['EMPLOYEE_NO', 'DEVICE_ID', 'CIVIL'] as const).map((k) => <option key={k} value={k}>{t(`imp.rk_${k}` as Key)}</option>)}
            </Select>
            {refKind === 'DEVICE_ID' ? <Input label={t('imp.device')} ltr value={device} onChange={(e) => setDevice(e.target.value.toUpperCase())} /> : <span />}
            {colSelect('imp.col_ref', map.ref, (v) => setMap({ ...map, ref: v ?? 0 }))}
            {colSelect('imp.col_dir', map.dir, (v) => setMap({ ...map, dir: v }), true)}
            <div className="span-2 row" style={{ gap: 18 }}>
              <Check label={t('imp.has_header')} checked={map.header} onChange={(v) => setMap({ ...map, header: v })} />
              <Check label={t('imp.separate')} checked={separate} onChange={(v) => {
                setSeparate(v);
                setMap(v ? { ...map, datetime: null, date: map.datetime ?? 0, time: Math.min((map.datetime ?? 0) + 1, cols - 1) } : { ...map, datetime: map.date ?? 0, date: null, time: null });
              }} />
            </div>
            {separate ? <>
              {colSelect('imp.col_date', map.date, (v) => setMap({ ...map, date: v }))}
              {colSelect('imp.col_time', map.time, (v) => setMap({ ...map, time: v }))}
            </> : <>{colSelect('imp.col_datetime', map.datetime, (v) => setMap({ ...map, datetime: v }))}<span /></>}
            <Select label={t('imp.date_format')} value={map.fmt} onChange={(e) => setMap({ ...map, fmt: e.target.value as DateFmt })}>
              {(['DMY', 'MDY', 'YMD'] as const).map((f) => <option key={f} value={f}>{t(`imp.f_${f}` as Key)}</option>)}
            </Select>
          </div>
        )}
      </section>
      {rows.length > 0 && (
        <section className="panel">
          <div className="panel-head"><h2>{t('imp.preview')}</h2>
            <div className="row" style={{ gap: 12 }}>
              <b className="ok-text">{t('imp.rows_ok', { n: built.ok.length })}</b>
              {built.bad.length > 0 && <b className="bad-text">{t('imp.rows_bad', { n: built.bad.length })}</b>}
              <Button kind="primary" busy={busy} disabled={!built.ok.length} onClick={() => void doImport()}>{progress ?? t('imp.import', { n: built.ok.length })}</Button>
            </div></div>
          <div className="table-wrap"><table className="t">
            <thead><tr><th>{t('imp.line')}</th><th>{t('imp.col_ref')}</th><th>{t('imp.col_datetime')}</th><th>{t('imp.col_dir')}</th></tr></thead>
            <tbody>{built.ok.slice(0, 8).map((p) => <tr key={p.line}><td className="num">{p.line}</td><td className="num">{p.ref}</td><td className="num">{p.at}</td><td>{p.dir ?? '—'}</td></tr>)}</tbody>
          </table></div>
          {built.bad.length > 0 && (
            <div className="panel-pad"><b>{t('imp.errors')}</b>
              <ul style={{ margin: '6px 0 0' }}>{built.bad.slice(0, 15).map((b) => <li key={b.line}>{t('imp.line')} {b.line}: {t(`imp.p_${b.problem}` as Key)} — <code>{rows[b.line - 1]?.join(' | ')}</code></li>)}</ul></div>
          )}
        </section>
      )}
    </div>
  );
}

function HistoryTab({ entity }: { entity: string }) {
  const { t } = useI18n();
  const { data, error, loading, reload } = useAsync(() => tapi.listPunchBatches(entity || null), [entity]);
  const [open, setOpen] = useState<PunchBatch | null>(null);
  return (
    <div className="panel">
      <ErrorNote error={error} onRetry={reload} />
      {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('imp.none')}</Empty> : (
        <div className="table-wrap"><table className="t cards">
          <thead><tr><th>{t('imp.file')}</th><th>{t('imp.period')}</th><th className="r">{t('imp.rows')}</th><th className="r">{t('imp.imported')}</th>
            <th className="r">{t('imp.duplicates')}</th><th className="r">{t('imp.errors')}</th><th>{t('c.by')}</th></tr></thead>
          <tbody>{data.map((b) => (
            <tr key={b.id}>
              <td data-label={t('imp.file')}>{b.file_name ?? '—'}<span className="sub">{t(`imp.rk_${b.ref_kind}` as Key)}</span></td>
              <td data-label={t('imp.period')} className="num">{b.date_from ? `${fmtDate(b.date_from)} – ${fmtDate(b.date_to)}` : '—'}</td>
              <td data-label={t('imp.rows')} className="r num">{b.rows_total}</td>
              <td data-label={t('imp.imported')} className="r num">{b.rows_imported}</td>
              <td data-label={t('imp.duplicates')} className="r num">{b.rows_duplicate}</td>
              <td data-label={t('imp.errors')} className="r num">{b.rows_error > 0 && b.errors?.length
                ? <button type="button" className="linklike bad-text" onClick={() => setOpen(b)}>{b.rows_error}</button> : b.rows_error}</td>
              <td data-label={t('c.by')}>{b.created_by_name}<span className="sub">{fmtDateTime(b.created_at)}</span></td>
            </tr>))}
          </tbody></table></div>
      )}
      <Modal open={!!open} title={`${t('imp.errors')} — ${open?.file_name ?? ''}`} onClose={() => setOpen(null)} footer={<Button onClick={() => setOpen(null)}>{t('c.close')}</Button>}>
        <div className="table-wrap"><table className="t">
          <thead><tr><th>{t('imp.line')}</th><th>{t('imp.col_ref')}</th><th>{t('imp.problem')}</th></tr></thead>
          <tbody>{(open?.errors ?? []).map((e, i) => <tr key={i}><td className="num">{e.row}</td><td className="num">{e.ref ?? '—'}</td><td>{e.message}</td></tr>)}</tbody>
        </table></div>
      </Modal>
    </div>
  );
}

function DevicesTab({ entity }: { entity: string }) {
  const { t } = useI18n();
  const { can } = useSession();
  const { data, error, loading, reload, setData } = useAsync(() => tapi.listDeviceUsers(entity || null), [entity]);
  const { busy, run } = useAction();
  const [emp, setEmp] = useState<string | null>(null);
  const [dev, setDev] = useState('DEFAULT');
  const [uid, setUid] = useState('');
  const [k, setK] = useState(0);
  const save = async (employee_id: string, device_code: string, device_user_id: string | null) => {
    const r = await run(() => tapi.setDeviceUser({ employee_id, device_code, device_user_id }), t('imp.device_saved'));
    if (r) { setData(r.filter((x) => !entity || x.entity_id === entity)); setEmp(null); setUid(''); setK(k + 1); }
  };
  return (
    <div className="stack">
      {can('ATT_WRITE') && (
        <section className="panel panel-pad row" style={{ alignItems: 'flex-end', gap: 12 }}>
          <div style={{ minWidth: 260, flex: 1 }}><EmployeePicker key={k} label={t('c.employee')} value={emp} onChange={(v) => setEmp(v)} /></div>
          <Input label={t('imp.device')} ltr value={dev} onChange={(e) => setDev(e.target.value.toUpperCase())} />
          <Input label={t('imp.device_user')} ltr value={uid} onChange={(e) => setUid(e.target.value.trim())} />
          <Button kind="primary" busy={busy} disabled={!emp || !uid} onClick={() => void save(emp!, dev || 'DEFAULT', uid)}>{t('imp.set_device')}</Button>
        </section>
      )}
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('c.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('c.employee')}</th><th>{t('imp.device')}</th><th>{t('imp.device_user')}</th><th /></tr></thead>
            <tbody>{data.map((d) => (
              <tr key={`${d.employee_id}-${d.device_code}`}>
                <td data-label={t('c.employee')}><EmpCell r={d} tab="time" /></td>
                <td data-label={t('imp.device')} className="num">{d.device_code}</td>
                <td data-label={t('imp.device_user')} className="num">{d.device_user_id}</td>
                <td className="r">{can('ATT_WRITE') && <Button small kind="danger" busy={busy} onClick={() => void save(d.employee_id, d.device_code, null)}>{t('c.remove')}</Button>}</td>
              </tr>))}
            </tbody></table></div>
        )}
      </div>
    </div>
  );
}
