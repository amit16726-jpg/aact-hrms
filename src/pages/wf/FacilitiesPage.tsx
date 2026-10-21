import { useEffect, useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { wfapi, type Facility, type FacilityKind } from '../../lib/api_wf';
import { useI18n } from '../../i18n';
import { useSession } from '../../lib/session';
import { Badge, Button, Check, Empty, ErrorNote, Input, Loading, Modal, Tabs, useAction, useAsync, useConfirm } from '../../components/ui';
import { EmployeePicker } from '../../components/pickers';
import { EntitySelect, useEntity } from '../../components/time';
import { PageHead } from '../../components/Layout';
import { fmtDate, todayMuscat } from '../../lib/format';

export default function FacilitiesPage() {
  const { t, L } = useI18n();
  const { can } = useSession();
  const [sp, setSp] = useSearchParams();
  const kind: FacilityKind = sp.get('tab') === 'transport' ? 'TRANSPORT' : 'ACCOMMODATION';
  const hr = can('ASSET_WRITE');
  const { data, error, loading, reload, setData } = useAsync(() => wfapi.listFacilities(kind), [kind]);
  const [edit, setEdit] = useState<Facility | 'new' | null>(null);
  const [assign, setAssign] = useState<Facility | null>(null);
  const { busy, run } = useAction();
  const confirm = useConfirm();
  const end = async (assignmentId: string, name: string) => {
    if ((await confirm.ask({ title: `${t('fc.end')} — ${name}`, body: t('fc.end_q') })) === null) return;
    const r = await run(() => wfapi.endFacility(assignmentId, null), t('c.saved'));
    if (r) setData(r);
  };
  return (
    <div className="stack">
      <PageHead title={t('fc.title')} sub={t('fc.hint')} actions={hr ? <Button kind="primary" onClick={() => setEdit('new')}>{t(`fc.new_${kind}`)}</Button> : undefined} />
      <Tabs label={t('fc.title')} value={kind} onChange={(v) => setSp(v === 'TRANSPORT' ? { tab: 'transport' } : {}, { replace: true })}
        tabs={[{ id: 'ACCOMMODATION', label: t('fc.k_ACCOMMODATION') }, { id: 'TRANSPORT', label: t('fc.k_TRANSPORT') }]} />
      <ErrorNote error={error} onRetry={reload} />
      {loading && !data ? <Loading /> : !data?.length ? <div className="panel"><Empty>{t('fc.none')}</Empty></div> : (
        <div className="fac-grid">{data.map((f) => (
          <section key={f.id} className="panel fac-card">
            <div className="panel-head">
              <h2>{L(f.name_en, f.name_ar)} <span className="muted num">{f.code}</span></h2>
              {f.occupied >= f.capacity ? <Badge tone="warn">{t('fc.full')}</Badge> : <span className="num nowrap">{t('fc.occupied', { n: f.occupied, c: f.capacity })}</span>}
            </div>
            <div className="panel-pad stack" style={{ gap: 8 }}>
              {(f.address || f.vehicle_no || f.driver_en) && <div className="muted">{f.address}{f.vehicle_no ? ` · ${f.vehicle_no}` : ''}{f.driver_en ? ` · ${t('fc.driver')}: ${f.driver_en}` : ''}</div>}
              <progress max={f.capacity} value={f.occupied} aria-label={t('fc.occupied', { n: f.occupied, c: f.capacity })} />
              {!f.occupants.length ? <div className="muted">{t('fc.empty')}</div> : (
                <ul>{f.occupants.map((o) => (
                  <li key={o.assignment_id}>
                    <span><Link to={`/employees/${o.employee_id}`}>{L(o.full_name_en, o.full_name_ar)}</Link>
                      <span className="sub">{o.employee_no}{o.place ? ` · ${o.place}` : ''} · {t('fc.from')} {fmtDate(o.from_date)}</span></span>
                    {hr && <Button small kind="ghost" busy={busy} onClick={() => void end(o.assignment_id, L(o.full_name_en, o.full_name_ar))}>{t('fc.end')}</Button>}
                  </li>))}
                </ul>)}
              {hr && <div className="row" style={{ gap: 6 }}>
                <Button small kind="primary" disabled={f.occupied >= f.capacity || !f.is_active} onClick={() => setAssign(f)}>{t('fc.assign')}</Button>
                <Button small onClick={() => setEdit(f)}>{t('fc.edit')}</Button>
              </div>}
            </div>
          </section>))}
        </div>)}
      <FacilityDialog kind={kind} edit={edit} onClose={() => setEdit(null)} onDone={(r) => { setData(r); setEdit(null); }} />
      <AssignDialog f={assign} onClose={() => setAssign(null)} onDone={(r) => { setData(r); setAssign(null); }} />
      {confirm.node}
    </div>
  );
}

function FacilityDialog({ kind, edit, onClose, onDone }: { kind: FacilityKind; edit: Facility | 'new' | null; onClose: () => void; onDone: (r: Facility[]) => void }) {
  const { t } = useI18n();
  const [entity, setEntity] = useEntity();
  const { busy, run } = useAction();
  const blank = { code: '', name_en: '', name_ar: '', address: '', capacity: '', vehicle_no: '', driver_employee_id: null as string | null, driver_label: '', is_active: true };
  const [f, setF] = useState(blank);
  useEffect(() => {
    if (edit === 'new') setF(blank);
    else if (edit) setF({ code: edit.code, name_en: edit.name_en, name_ar: edit.name_ar ?? '', address: edit.address ?? '', capacity: String(edit.capacity),
      vehicle_no: edit.vehicle_no ?? '', driver_employee_id: edit.driver_employee_id, driver_label: edit.driver_en ?? '', is_active: edit.is_active });
  }, [edit]); // eslint-disable-line react-hooks/exhaustive-deps
  const save = async () => {
    const r = await run(() => wfapi.saveFacility({ ...(edit && edit !== 'new' ? { id: edit.id } : { entity_id: entity }), kind, code: f.code, name_en: f.name_en, name_ar: f.name_ar || null,
      address: f.address || null, capacity: Number(f.capacity), vehicle_no: f.vehicle_no || null, driver_employee_id: f.driver_employee_id, is_active: f.is_active }), t('c.saved'));
    if (r) onDone(r);
  };
  return (
    <Modal open={!!edit} title={t(edit === 'new' ? `fc.new_${kind}` : 'fc.edit')} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button>
        <Button kind="primary" busy={busy} disabled={!f.code.trim() || !f.name_en.trim() || !(Number(f.capacity) >= 1)} onClick={() => void save()}>{t('c.save')}</Button></>}>
      <div className="stack">
        {edit === 'new' && <EntitySelect value={entity} onChange={setEntity} />}
        <div className="grid-2">
          <Input label={t('fc.code')} required ltr value={f.code} onChange={(e) => setF({ ...f, code: e.target.value.toUpperCase() })} />
          <Input label={t('fc.capacity')} required type="number" min={1} max={2000} ltr value={f.capacity} onChange={(e) => setF({ ...f, capacity: e.target.value })} />
        </div>
        <Input label={t('fc.name_en')} required value={f.name_en} onChange={(e) => setF({ ...f, name_en: e.target.value })} />
        <Input label={t('fc.name_ar')} dir="rtl" value={f.name_ar} onChange={(e) => setF({ ...f, name_ar: e.target.value })} />
        <Input label={t(`fc.address_${kind}`)} value={f.address} onChange={(e) => setF({ ...f, address: e.target.value })} />
        {kind === 'TRANSPORT' && <div className="grid-2">
          <Input label={t('fc.vehicle')} ltr value={f.vehicle_no} onChange={(e) => setF({ ...f, vehicle_no: e.target.value })} />
          <EmployeePicker label={t('fc.driver')} value={f.driver_employee_id} valueLabel={f.driver_label} onChange={(id, l) => setF({ ...f, driver_employee_id: id, driver_label: l ?? '' })} />
        </div>}
        <Check label={t('tr.active')} checked={f.is_active} onChange={(v) => setF({ ...f, is_active: v })} />
      </div>
    </Modal>
  );
}

function AssignDialog({ f, onClose, onDone }: { f: Facility | null; onClose: () => void; onDone: (r: Facility[]) => void }) {
  const { t, L } = useI18n();
  const { busy, run } = useAction();
  const [v, setV] = useState({ employee_id: null as string | null, label: '', place: '', from_date: '' });
  useEffect(() => { if (f) setV({ employee_id: null, label: '', place: '', from_date: todayMuscat() }); }, [f]);
  const submit = async () => {
    if (!f) return;
    const r = await run(() => wfapi.assignFacility({ facility_id: f.id, employee_id: v.employee_id, place: v.place || null, from_date: v.from_date }), t('c.saved'));
    if (r) onDone(r);
  };
  return (
    <Modal open={!!f} title={`${t('fc.assign')} — ${f ? L(f.name_en, f.name_ar) : ''}`} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={!v.employee_id || !v.from_date} onClick={() => void submit()}>{t('fc.assign')}</Button></>}>
      {f && <div className="stack">
        <EmployeePicker label={t('c.employee')} value={v.employee_id} valueLabel={v.label} onChange={(id, l) => setV({ ...v, employee_id: id, label: l ?? '' })} hint={t('fc.move_hint')} />
        <div className="grid-2">
          <Input label={t(`fc.place_${f.kind}`)} value={v.place} onChange={(e) => setV({ ...v, place: e.target.value })} />
          <Input label={t('fc.from')} type="date" ltr value={v.from_date} onChange={(e) => setV({ ...v, from_date: e.target.value })} />
        </div>
      </div>}
    </Modal>
  );
}
