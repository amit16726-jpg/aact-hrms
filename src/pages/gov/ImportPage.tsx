import { useState } from 'react';
import { IMPORT_COLUMNS, IMPORT_EXAMPLE, csvToRows, govapi, missingColumns, type ImportKind, type ImportResult } from '../../lib/api_gov';
import { useI18n, type Key } from '../../i18n';
import { Badge, Button, Empty, ErrorNote, Loading, Select, useAction, useAsync, useConfirm } from '../../components/ui';
import { PageHead } from '../../components/Layout';
import { downloadCsv } from '../../lib/csv';
import { fmtDateTime } from '../../lib/format';

const KINDS: ImportKind[] = ['EMPLOYEES', 'DOCUMENTS', 'SALARIES'];

export default function ImportPage() {
  const { t } = useI18n();
  const [kind, setKind] = useState<ImportKind>('EMPLOYEES');
  const [file, setFile] = useState<{ name: string; headers: string[]; rows: Record<string, string>[] } | null>(null);
  const [res, setRes] = useState<ImportResult | null>(null);
  const hist = useAsync(() => govapi.listImports(), []);
  const { busy, run } = useAction();
  const confirm = useConfirm();
  const missing = file ? missingColumns(kind, file.headers) : [];
  const pickFile = async (f: File | undefined) => {
    setRes(null);
    if (!f) { setFile(null); return; }
    const parsed = csvToRows(await f.text());
    setFile({ name: f.name, ...parsed });
  };
  const go = async (dry: boolean) => {
    if (!file) return;
    if (!dry && (await confirm.ask({ title: t('im.run'), body: t('im.run_q', { n: file.rows.length }) })) === null) return;
    const r = await run(() => govapi.importRows(kind, file.rows, dry, file.name));
    if (r) { setRes(r); void hist.reload(); }
  };
  return (
    <div className="stack">
      <PageHead title={t('im.title')} sub={t('im.hint')} />
      <div className="note">{t('im.order')}</div>
      <section className="panel panel-pad stack" style={{ maxWidth: 820 }}>
        <div className="grid-2" style={{ alignItems: 'end' }}>
          <Select label={t('im.kind')} value={kind} onChange={(e) => { setKind(e.target.value as ImportKind); setRes(null); }}>
            {KINDS.map((k) => <option key={k} value={k}>{t(`im.k_${k}` as Key)}</option>)}
          </Select>
          <div><Button onClick={() => downloadCsv(`aact-hrms-import-${kind.toLowerCase()}.csv`, IMPORT_COLUMNS[kind], [IMPORT_EXAMPLE[kind]])}>{t('im.template')}</Button></div>
        </div>
        {kind === 'SALARIES' && <div className="note note-warn">{t('im.salary_note')}</div>}
        <div className="field"><label htmlFor="im-file">{t('im.file')}</label>
          <input id="im-file" type="file" accept=".csv,text/csv" className="input" onChange={(e) => void pickFile(e.target.files?.[0])} /></div>
        {file && <div className="muted num">{file.name} · {t('im.rows', { n: file.rows.length })}</div>}
        {file && missing.length > 0 && <div className="note note-bad">{t('im.missing', { c: missing.join(', ') })}</div>}
        <div className="row" style={{ gap: 6 }}>
          <Button busy={busy} disabled={!file || !file.rows.length || missing.length > 0} onClick={() => void go(true)}>{t('im.check')}</Button>
          <Button kind="primary" busy={busy} disabled={!file || !file.rows.length || missing.length > 0 || !res || !res.dry_run || res.ok === 0} onClick={() => void go(false)}>{t('im.run')}</Button>
        </div>
      </section>
      {res && (
        <section className="panel">
          <div className="panel-head"><h2>{res.dry_run ? t('im.dry') : t('im.saved', { ok: res.ok })}</h2>
            <span><Badge tone={res.failed ? 'warn' : 'ok'}>{t('im.result', { ok: res.ok, f: res.failed })}</Badge></span></div>
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th className="r">{t('im.row')}</th><th>{t('im.key')}</th><th>{t('im.message')}</th></tr></thead>
            <tbody>{[...res.results].sort((a, b) => Number(a.ok) - Number(b.ok) || a.row - b.row).slice(0, 500).map((x) => (
              <tr key={x.row}><td data-label={t('im.row')} className="r num">{x.row + 1}</td><td data-label={t('im.key')} className="num">{x.key ?? '—'}</td>
                <td data-label={t('im.message')}>{x.ok ? <Badge tone="ok">✓</Badge> : <span className="bad-text wrap-text">{x.message}</span>}</td></tr>))}
            </tbody></table></div>
        </section>)}
      <section className="panel">
        <div className="panel-head"><h2>{t('im.history')}</h2></div>
        <ErrorNote error={hist.error} onRetry={hist.reload} />
        {hist.loading && !hist.data ? <Loading /> : !hist.data?.length ? <Empty>—</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <tbody>{hist.data.map((b) => (
              <tr key={b.id}><td>{t(`im.k_${b.kind}` as Key)}<span className="sub">{b.file_name ?? ''}</span></td>
                <td className="num">{fmtDateTime(b.created_at)}<span className="sub">{b.created_by_name}</span></td>
                <td>{b.dry_run && <Badge>{t('im.trial')}</Badge>} <span className="num">{t('im.result', { ok: b.rows_ok, f: b.rows_failed })}</span></td></tr>))}
            </tbody></table></div>)}
      </section>
      {confirm.node}
    </div>
  );
}
