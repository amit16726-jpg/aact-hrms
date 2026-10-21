import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { recapi, type ProbationRow } from '../../lib/api_rec';
import { api } from '../../lib/api';
import { useI18n } from '../../i18n';
import { Badge, Button, Empty, ErrorNote, Input, Loading, Modal, Textarea, useAction, useAsync, useConfirm } from '../../components/ui';
import { PageHead } from '../../components/Layout';
import { fmtDate, todayMuscat } from '../../lib/format';

export default function ProbationPage() {
  const { t, L } = useI18n();
  const { data, error, loading, reload, setData } = useAsync(() => recapi.listProbation(), []);
  const [ext, setExt] = useState<ProbationRow | null>(null);
  const { busy, run } = useAction();
  const confirm = useConfirm();
  const confirmEmp = async (r: ProbationRow) => {
    const note = await confirm.ask({ title: t('pb.confirm_q', { n: L(r.full_name_en, r.full_name_ar) }), reason: 'optional', reasonLabel: t('c.notes'), okLabel: t('pb.confirm') });
    if (note === null) return;
    if (await run(() => api.changeStatus(r.employee_id, { action: 'CONFIRM', date: todayMuscat(), notes: note || null }), t('pb.confirmed'))) void reload();
  };
  return (
    <div className="stack">
      <PageHead title={t('pb.title')} sub={t('pb.hint')} />
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('pb.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('c.employee')}</th><th>{t('pb.joined')}</th><th>{t('pb.ends')}</th><th>{t('pb.max')}</th><th /></tr></thead>
            <tbody>{data.map((r) => (
              <tr key={r.employee_id}>
                <td data-label={t('c.employee')}><Link to={`/employees/${r.employee_id}`}>{L(r.full_name_en, r.full_name_ar)}</Link>
                  <span className="sub">{r.employee_no} · {L(r.job_en, r.job_ar)}{r.manager_en ? ` · ${L(r.manager_en, r.manager_ar)}` : ''}</span></td>
                <td data-label={t('pb.joined')} className="num">{fmtDate(r.join_date)}</td>
                <td data-label={t('pb.ends')}><span className="num">{fmtDate(r.probation_end_date)}</span>
                  {r.days_left != null && <span className="sub">{r.overdue ? <Badge tone="bad">{t('pb.overdue', { n: -r.days_left })}</Badge>
                    : <Badge tone={r.days_left <= 14 ? 'warn' : undefined}>{t('pb.left', { n: r.days_left })}</Badge>}</span>}</td>
                <td data-label={t('pb.max')} className="num">{fmtDate(r.max_end)}</td>
                <td className="r">{r.can_decide && <div className="row" style={{ gap: 4, justifyContent: 'flex-end' }}>
                  <Button small kind="primary" busy={busy} disabled={r.join_date > todayMuscat()} onClick={() => void confirmEmp(r)}>{t('pb.confirm')}</Button>
                  <Button small disabled={!r.probation_end_date || r.probation_end_date >= r.max_end} onClick={() => setExt(r)}>{t('pb.extend')}</Button>
                </div>}</td>
              </tr>))}
            </tbody></table></div>)}
      </div>
      <ExtendDialog r={ext} onClose={() => setExt(null)} onDone={(rows) => { setData(rows); setExt(null); }} />
      {confirm.node}
    </div>
  );
}

function ExtendDialog({ r, onClose, onDone }: { r: ProbationRow | null; onClose: () => void; onDone: (rows: ProbationRow[]) => void }) {
  const { t, L } = useI18n();
  const { busy, run } = useAction();
  const [f, setF] = useState({ date: '', reason: '' });
  useEffect(() => { if (r) setF({ date: r.max_end, reason: '' }); }, [r]);
  const submit = async () => {
    if (!r) return;
    const rows = await run(() => recapi.extendProbation(r.employee_id, { probation_end_date: f.date, reason: f.reason }), t('pb.extended'));
    if (rows) onDone(rows);
  };
  return (
    <Modal open={!!r} title={`${t('pb.extend_title')} — ${r ? L(r.full_name_en, r.full_name_ar) : ''}`} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={!f.date || f.reason.trim().length < 10} onClick={() => void submit()}>{t('pb.extend')}</Button></>}>
      <div className="stack">
        <Input label={t('pb.new_end')} type="date" ltr value={f.date} min={r?.probation_end_date ?? undefined} max={r?.max_end} hint={`${t('pb.max')}: ${fmtDate(r?.max_end)}`}
          onChange={(e) => setF({ ...f, date: e.target.value })} />
        <Textarea label={t('pb.reason')} required value={f.reason} onChange={(e) => setF({ ...f, reason: e.target.value })} />
      </div>
    </Modal>
  );
}
