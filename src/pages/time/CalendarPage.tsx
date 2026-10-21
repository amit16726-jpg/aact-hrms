import { useEffect, useState } from 'react';
import { tapi, type Holiday, type RamadanPeriod } from '../../lib/api_time';
import { useI18n } from '../../i18n';
import { useSession } from '../../lib/session';
import { Badge, Button, DateText, Empty, ErrorNote, Input, Loading, Modal, Select, Textarea, useAction, useAsync, useConfirm } from '../../components/ui';
import { PageHead } from '../../components/Layout';
import { daysInclusive, todayMuscat } from '../../lib/format';

export default function CalendarPage() {
  const { t, L } = useI18n();
  const { can, me } = useSession();
  const [year, setYear] = useState(Number(todayMuscat().slice(0, 4)));
  const { data, error, loading, reload, setData } = useAsync(() => tapi.listHolidays(year, null), [year]);
  const [hol, setHol] = useState<Partial<Holiday> | null>(null);
  const [ram, setRam] = useState<Partial<RamadanPeriod> | null>(null);
  const { busy, run } = useAction();
  const confirm = useConfirm();
  const write = can('ATT_WRITE');
  const entities = me?.entities ?? [];
  const entName = (id: string | null) => { if (!id) return t('cal.all_companies'); const e = entities.find((x) => x.id === id); return e ? L(e.name_en, e.name_ar) : '—'; };
  const holidays = (data?.holidays ?? []).filter((h) => h.is_active);

  const remove = async (h: Holiday) => {
    const ok = await confirm.ask({ title: `${t('cal.remove')} — ${L(h.name_en, h.name_ar)}`, danger: true });
    if (ok === null) return;
    const r = await run(() => tapi.saveHoliday({ ...h, is_active: false }), t('cal.removed'));
    if (r) void reload();
  };

  return (
    <div className="stack">
      <PageHead title={t('cal.title')} />
      <div className="note">{t('cal.hint')}</div>
      <div className="panel panel-pad row" style={{ alignItems: 'flex-end', gap: 8 }}>
        <Button onClick={() => setYear(year - 1)} aria-label={t('c.previous')}>‹</Button>
        <div className="field"><label htmlFor="cal-y">{t('cal.year')}</label>
          <input id="cal-y" className="input ltr" style={{ width: 110 }} inputMode="numeric" value={year}
            onChange={(e) => { const v = Number(e.target.value); if (v > 2000 && v < 2100) setYear(v); }} /></div>
        <Button onClick={() => setYear(year + 1)} aria-label={t('c.next')}>›</Button>
      </div>
      <ErrorNote error={error} onRetry={reload} />
      <div className="grid-2" style={{ alignItems: 'start' }}>
        <section className="panel">
          <div className="panel-head"><h2>{t('cal.holidays')}</h2>
            {write && <Button small kind="primary" onClick={() => setHol({ holiday_date: `${year}-01-01`, name_en: '', name_ar: '', kind: 'PUBLIC', entity_id: null, source_reference: '', is_active: true })}>{t('cal.new_holiday')}</Button>}</div>
          {loading && !data ? <Loading /> : !holidays.length ? <Empty>{t('cal.none')}</Empty> : (
            <div className="table-wrap"><table className="t cards">
              <thead><tr><th>{t('c.date')}</th><th>{t('c.details')}</th><th>{t('cal.kind')}</th><th /></tr></thead>
              <tbody>{holidays.map((h) => (
                <tr key={h.id}>
                  <td data-label={t('c.date')}><DateText v={h.holiday_date} /></td>
                  <td data-label={t('c.details')}>{L(h.name_en, h.name_ar)}{h.source_reference && <span className="sub">{h.source_reference}</span>}
                    <span className="sub">{entName(h.entity_id)}</span></td>
                  <td data-label={t('cal.kind')}><Badge tone={h.kind === 'PUBLIC' ? 'info' : undefined}>{t(h.kind === 'PUBLIC' ? 'cal.k_PUBLIC' : 'cal.k_COMPANY')}</Badge></td>
                  <td className="r">{write && <div className="row" style={{ gap: 4, justifyContent: 'flex-end' }}>
                    <Button small onClick={() => setHol(h)}>{t('c.edit')}</Button>
                    <Button small kind="danger" busy={busy} onClick={() => void remove(h)}>{t('cal.remove')}</Button></div>}</td>
                </tr>))}
              </tbody></table></div>
          )}
        </section>
        <section className="panel">
          <div className="panel-head"><h2>{t('cal.ramadan')}</h2>
            {write && <Button small kind="primary" onClick={() => setRam({ start_date: `${year}-01-01`, end_date: `${year}-01-30`, name_en: `Ramadan ${year}`, name_ar: `رمضان ${year}`, notes: '' })}>{t('cal.new_ramadan')}</Button>}</div>
          {loading && !data ? <Loading /> : !data?.ramadan.length ? <Empty>{t('cal.no_ramadan')}</Empty> : (
            <div className="table-wrap"><table className="t cards">
              <thead><tr><th>{t('c.details')}</th><th>{t('cal.first_day')}</th><th>{t('cal.last_day')}</th><th className="r">{t('c.days')}</th><th /></tr></thead>
              <tbody>{data.ramadan.map((r) => (
                <tr key={r.id}>
                  <td data-label={t('c.details')}>{L(r.name_en, r.name_ar)}{r.notes && <span className="sub">{r.notes}</span>}</td>
                  <td data-label={t('cal.first_day')}><DateText v={r.start_date} /></td>
                  <td data-label={t('cal.last_day')}><DateText v={r.end_date} /></td>
                  <td data-label={t('c.days')} className="r num">{daysInclusive(r.start_date, r.end_date)}</td>
                  <td className="r">{write && <Button small onClick={() => setRam(r)}>{t('c.edit')}</Button>}</td>
                </tr>))}
              </tbody></table></div>
          )}
        </section>
      </div>
      <HolidayDialog row={hol} onClose={() => setHol(null)} onDone={(d) => setData(d)} />
      <RamadanDialog row={ram} onClose={() => setRam(null)} onDone={(d) => setData(d)} />
      {confirm.node}
    </div>
  );
}

type CalData = { holidays: Holiday[]; ramadan: RamadanPeriod[] };

function HolidayDialog({ row, onClose, onDone }: { row: Partial<Holiday> | null; onClose: () => void; onDone: (d: CalData) => void }) {
  const { t, L } = useI18n();
  const { me } = useSession();
  const { busy, run } = useAction();
  const [f, setF] = useState<Partial<Holiday>>({});
  useEffect(() => { if (row) setF(row); }, [row]);
  const submit = async () => {
    const r = await run(() => tapi.saveHoliday({ ...f, source_reference: f.source_reference || null, name_ar: f.name_ar || null }), t('c.saved'));
    if (r) { onDone(r); onClose(); }
  };
  return (
    <Modal open={!!row} title={row?.id ? t('cal.edit_holiday') : t('cal.new_holiday')} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={!f.holiday_date || !f.name_en} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="form-grid">
        <Input label={t('c.date')} type="date" ltr required value={f.holiday_date ?? ''} onChange={(e) => setF({ ...f, holiday_date: e.target.value })} />
        <Select label={t('cal.kind')} value={f.kind ?? 'PUBLIC'} onChange={(e) => setF({ ...f, kind: e.target.value as Holiday['kind'] })}>
          <option value="PUBLIC">{t('cal.k_PUBLIC')}</option><option value="COMPANY">{t('cal.k_COMPANY')}</option>
        </Select>
        <Input label={t('c.name_en')} required value={f.name_en ?? ''} onChange={(e) => setF({ ...f, name_en: e.target.value })} />
        <Input label={t('c.name_ar')} value={f.name_ar ?? ''} onChange={(e) => setF({ ...f, name_ar: e.target.value })} />
        <Select label={t('c.company')} value={f.entity_id ?? ''} onChange={(e) => setF({ ...f, entity_id: e.target.value || null })}>
          <option value="">{t('cal.all_companies')}</option>
          {(me?.entities ?? []).map((x) => <option key={x.id} value={x.id}>{L(x.name_en, x.name_ar)}</option>)}
        </Select>
        <Input label={t('cal.source')} value={f.source_reference ?? ''} onChange={(e) => setF({ ...f, source_reference: e.target.value })} />
      </div>
    </Modal>
  );
}

function RamadanDialog({ row, onClose, onDone }: { row: Partial<RamadanPeriod> | null; onClose: () => void; onDone: (d: CalData) => void }) {
  const { t } = useI18n();
  const { busy, run } = useAction();
  const [f, setF] = useState<Partial<RamadanPeriod>>({});
  useEffect(() => { if (row) setF(row); }, [row]);
  const bad = !!f.start_date && !!f.end_date && f.end_date < f.start_date;
  const submit = async () => {
    const r = await run(() => tapi.saveRamadan({ ...f, name_ar: f.name_ar || null, notes: f.notes || null }), t('c.saved'));
    if (r) { onDone(r); onClose(); }
  };
  return (
    <Modal open={!!row} title={t('cal.ramadan')} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={!f.start_date || !f.end_date || !f.name_en || bad} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      <div className="form-grid">
        <Input label={t('cal.first_day')} type="date" ltr required value={f.start_date ?? ''} onChange={(e) => setF({ ...f, start_date: e.target.value })} />
        <Input label={t('cal.last_day')} type="date" ltr required value={f.end_date ?? ''} error={bad ? t('err.INVALID_DATE') : undefined} onChange={(e) => setF({ ...f, end_date: e.target.value })} />
        <Input label={t('c.name_en')} required value={f.name_en ?? ''} onChange={(e) => setF({ ...f, name_en: e.target.value })} />
        <Input label={t('c.name_ar')} value={f.name_ar ?? ''} onChange={(e) => setF({ ...f, name_ar: e.target.value })} />
        <Textarea label={t('c.notes')} className="span-2" value={f.notes ?? ''} onChange={(e) => setF({ ...f, notes: e.target.value })} />
        <div className="span-2 muted">{t('sh.temp_hint')}</div>
      </div>
    </Modal>
  );
}
