import { useEffect, useState } from 'react';
import { useSearchParams } from 'react-router-dom';
import { ASSET_CATEGORIES, wfapi, type AssetCategory, type AssetIssue, type AssetItem } from '../../lib/api_wf';
import { useI18n, type Key } from '../../i18n';
import { useSession } from '../../lib/session';
import { Badge, Button, Check, Empty, ErrorNote, Input, Loading, Modal, Select, Tabs, Textarea, useAction, useAsync } from '../../components/ui';
import { EmpCell } from '../../components/time';
import { PageHead } from '../../components/Layout';
import { MultiEmployeePicker } from '../../components/wf';
import { OMR } from '../../components/pay';
import { fmtDate, todayMuscat } from '../../lib/format';

type Tab = 'out' | 'all' | 'items';

export default function AssetsPage() {
  const { t } = useI18n();
  const { can } = useSession();
  const [sp, setSp] = useSearchParams();
  const hr = can('ASSET_WRITE');
  const tabs: { id: Tab; label: string }[] = [{ id: 'out', label: t('as2.tab_out') }, { id: 'all', label: t('as2.tab_all') }, ...(hr ? [{ id: 'items' as Tab, label: t('as2.tab_items') }] : [])];
  const tab = (tabs.some((x) => x.id === sp.get('tab')) ? sp.get('tab') : 'out') as Tab;
  return (
    <div className="stack">
      <PageHead title={t('as2.title')} sub={t('as2.hint')} />
      <Tabs label={t('as2.title')} value={tab} onChange={(v) => setSp(v === 'out' ? {} : { tab: v }, { replace: true })} tabs={tabs} />
      {tab !== 'items' ? <Issues openOnly={tab === 'out'} /> : <Items />}
    </div>
  );
}

function Issues({ openOnly }: { openOnly: boolean }) {
  const { t, L } = useI18n();
  const { can } = useSession();
  const hr = can('ASSET_WRITE');
  const { data, error, loading, reload } = useAsync(() => wfapi.listIssues({ open_only: openOnly }), [openOnly]);
  const items = useAsync(() => (hr ? wfapi.listItems() : Promise.resolve([] as AssetItem[])), [hr]);
  const [issue, setIssue] = useState(false);
  const [ret, setRet] = useState<AssetIssue | null>(null);
  const showEmp = hr || can('EMP_READ');
  return (
    <>
      {hr && <div className="row" style={{ justifyContent: 'flex-end' }}><Button kind="primary" onClick={() => setIssue(true)}>{t('as2.issue')}</Button></div>}
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('as2.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr>{showEmp && <th>{t('c.employee')}</th>}<th>{t('as2.item')}</th><th>{t('as2.issued_on')}</th><th>{t('c.status')}</th>{hr && <th />}</tr></thead>
            <tbody>{data.map((x) => (
              <tr key={x.id}>
                {showEmp && <td data-label={t('c.employee')}><EmpCell r={x} /></td>}
                <td data-label={t('as2.item')}>{L(x.item_en, x.item_ar)}{x.qty > 1 && <span className="num"> × {x.qty}</span>}
                  <span className="sub">{t(`as2.cat_${x.category}` as Key)}{x.serial_no ? <> · <span className="num">{x.serial_no}</span></> : null}</span></td>
                <td data-label={t('as2.issued_on')}><span className="num">{fmtDate(x.issued_on)}</span>
                  {x.due_return_on && x.status === 'ISSUED' && <span className={`sub num${x.overdue ? ' bad-text' : ''}`}>{t('as2.due_return')} {fmtDate(x.due_return_on)}</span>}
                  {x.replace_due && <span className="sub num">{t('as2.replace_due', { d: fmtDate(x.replace_due) })}</span>}</td>
                <td data-label={t('c.status')}><Badge tone={x.status === 'ISSUED' ? (x.overdue ? 'bad' : 'info') : x.status === 'LOST' ? 'bad' : x.status === 'RETURNED' ? 'ok' : undefined}>
                  {x.overdue ? t('as2.overdue') : t(`as2.st_${x.status}` as Key)}</Badge>
                  {x.returned_on && <span className="sub">{fmtDate(x.returned_on)}{x.condition ? ` · ${t(`as2.cond_${x.condition}` as Key)}` : ''}</span>}</td>
                {hr && <td className="r">{x.status === 'ISSUED' && <Button small onClick={() => setRet(x)}>{t('as2.return')}</Button>}</td>}
              </tr>))}
            </tbody></table></div>)}
      </div>
      <IssueDialog open={issue} items={items.data ?? []} onClose={() => setIssue(false)} onDone={() => { setIssue(false); void reload(); }} />
      <ReturnDialog x={ret} onClose={() => setRet(null)} onDone={() => { setRet(null); void reload(); }} />
    </>
  );
}

function IssueDialog({ open, items, onClose, onDone }: { open: boolean; items: AssetItem[]; onClose: () => void; onDone: () => void }) {
  const { t, L } = useI18n();
  const { busy, run } = useAction();
  const [f, setF] = useState({ item_id: '', qty: '1', serial_no: '', issued_on: '', due_return_on: '', notes: '' });
  const [emps, setEmps] = useState<{ id: string; label: string }[]>([]);
  useEffect(() => { if (open) { setF({ item_id: '', qty: '1', serial_no: '', issued_on: todayMuscat(), due_return_on: '', notes: '' }); setEmps([]); } }, [open]);
  const it = items.find((x) => x.id === f.item_id);
  const submit = async () => {
    const r = await run(() => wfapi.issueAsset({ item_id: f.item_id, employee_ids: emps.map((e) => e.id), qty: Number(f.qty) || 1, serial_no: f.serial_no || null,
      issued_on: f.issued_on, due_return_on: f.due_return_on || null, notes: f.notes || null }));
    if (r) onDone();
  };
  return (
    <Modal open={open} title={t('as2.issue')} onClose={onClose} wide
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={!f.item_id || emps.length === 0} onClick={() => void submit()}>{t('as2.issue')}</Button></>}>
      <div className="stack">
        <div className="grid-2">
          <Select label={t('as2.item')} required value={f.item_id} onChange={(e) => setF({ ...f, item_id: e.target.value })}>
            <option value="">{t('c.select')}</option>
            {items.filter((x) => x.is_active).map((x) => <option key={x.id} value={x.id}>{x.code} — {L(x.name_en, x.name_ar)}</option>)}
          </Select>
          <Input label={t('as2.qty')} type="number" min={1} max={100} ltr value={f.qty} onChange={(e) => setF({ ...f, qty: e.target.value })} />
        </div>
        <MultiEmployeePicker label={t('tr.add_emp')} value={emps} onChange={setEmps} />
        <div className="grid-3">
          <Input label={t('as2.issued_on')} type="date" ltr value={f.issued_on} onChange={(e) => setF({ ...f, issued_on: e.target.value })} />
          {it?.returnable !== false && <Input label={t('as2.due_return')} type="date" ltr value={f.due_return_on} min={f.issued_on} onChange={(e) => setF({ ...f, due_return_on: e.target.value })} />}
          {emps.length <= 1 && <Input label={t('as2.serial')} ltr value={f.serial_no} onChange={(e) => setF({ ...f, serial_no: e.target.value })} />}
        </div>
        <Textarea label={t('c.notes')} value={f.notes} onChange={(e) => setF({ ...f, notes: e.target.value })} />
      </div>
    </Modal>
  );
}

function ReturnDialog({ x, onClose, onDone }: { x: AssetIssue | null; onClose: () => void; onDone: () => void }) {
  const { t, L } = useI18n();
  const { busy, run } = useAction();
  const [f, setF] = useState({ condition: 'GOOD', returned_on: '', recover_amount: '', notes: '' });
  useEffect(() => { if (x) setF({ condition: 'GOOD', returned_on: todayMuscat(), recover_amount: '', notes: '' }); }, [x]);
  const bad = f.condition === 'DAMAGED' || f.condition === 'LOST';
  const rec = bad && Number(f.recover_amount) > 0;
  const submit = async () => {
    if (!x) return;
    if (await run(() => wfapi.returnAsset(x.id, { condition: f.condition, returned_on: f.returned_on, recover_amount: rec ? f.recover_amount : null, notes: f.notes || null }), t('as2.returned'))) onDone();
  };
  return (
    <Modal open={!!x} title={`${t('as2.return')} — ${x ? L(x.item_en, x.item_ar) : ''}`} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={rec && f.notes.trim().length < 10} onClick={() => void submit()}>{t('c.save')}</Button></>}>
      {x && <div className="stack">
        <div><b>{L(x.full_name_en, x.full_name_ar)}</b> <span className="muted num">{x.employee_no}</span></div>
        <div className="grid-2">
          <Select label={t('as2.condition')} value={f.condition} onChange={(e) => setF({ ...f, condition: e.target.value, recover_amount: e.target.value === 'DAMAGED' || e.target.value === 'LOST' ? (x.unit_cost != null ? (x.unit_cost * x.qty).toFixed(3) : '') : '' })}>
            {(['GOOD', 'WORN', 'DAMAGED', 'LOST'] as const).map((c) => <option key={c} value={c}>{t(`as2.cond_${c}` as Key)}</option>)}
          </Select>
          <Input label={t('c.date')} type="date" ltr value={f.returned_on} min={x.issued_on} onChange={(e) => setF({ ...f, returned_on: e.target.value })} />
        </div>
        {bad && <Input label={t('as2.recover')} inputMode="decimal" ltr value={f.recover_amount} hint={t('as2.recover_hint')} onChange={(e) => setF({ ...f, recover_amount: e.target.value })} />}
        <Textarea label={t('c.notes')} required={rec} value={f.notes} onChange={(e) => setF({ ...f, notes: e.target.value })} />
      </div>}
    </Modal>
  );
}

function Items() {
  const { t, L } = useI18n();
  const { data, error, loading, reload, setData } = useAsync(() => wfapi.listItems(), []);
  const [edit, setEdit] = useState<AssetItem | 'new' | null>(null);
  return (
    <>
      <div className="row" style={{ justifyContent: 'flex-end' }}><Button kind="primary" onClick={() => setEdit('new')}>{t('as2.new_item')}</Button></div>
      <div className="panel">
        <ErrorNote error={error} onRetry={reload} />
        {loading && !data ? <Loading /> : !data?.length ? <Empty>{t('as2.none')}</Empty> : (
          <div className="table-wrap"><table className="t cards">
            <thead><tr><th>{t('as2.item')}</th><th>{t('tr.category')}</th><th className="r">{t('as2.unit_cost')}</th><th>{t('as2.replace')}</th><th className="r">{t('as2.tab_out')}</th><th /></tr></thead>
            <tbody>{data.map((i) => (
              <tr key={i.id}>
                <td data-label={t('as2.item')}><b>{L(i.name_en, i.name_ar)}</b><span className="sub">{i.code}{!i.returnable ? ` · ${t('as2.st_CONSUMED')}` : ''}{!i.is_active ? ` · ${t('c.inactive')}` : ''}</span></td>
                <td data-label={t('tr.category')}>{t(`as2.cat_${i.category}` as Key)}</td>
                <td data-label={t('as2.unit_cost')} className="r num">{i.unit_cost != null ? OMR(i.unit_cost) : '—'}</td>
                <td data-label={t('as2.replace')} className="num">{i.replace_months ?? '—'}</td>
                <td data-label={t('as2.tab_out')} className="r num">{i.issued}</td>
                <td className="r"><Button small onClick={() => setEdit(i)}>{t('c.edit')}</Button></td>
              </tr>))}
            </tbody></table></div>)}
      </div>
      <ItemDialog edit={edit} onClose={() => setEdit(null)} onDone={(r) => { setData(r); setEdit(null); }} />
    </>
  );
}

function ItemDialog({ edit, onClose, onDone }: { edit: AssetItem | 'new' | null; onClose: () => void; onDone: (r: AssetItem[]) => void }) {
  const { t } = useI18n();
  const { busy, run } = useAction();
  const [f, setF] = useState({ code: '', name_en: '', name_ar: '', category: 'PPE' as AssetCategory, returnable: true, unit_cost: '', replace_months: '', is_active: true });
  useEffect(() => {
    if (edit === 'new') setF({ code: '', name_en: '', name_ar: '', category: 'PPE', returnable: true, unit_cost: '', replace_months: '', is_active: true });
    else if (edit) setF({ code: edit.code, name_en: edit.name_en, name_ar: edit.name_ar ?? '', category: edit.category, returnable: edit.returnable,
      unit_cost: edit.unit_cost != null ? String(edit.unit_cost) : '', replace_months: edit.replace_months != null ? String(edit.replace_months) : '', is_active: edit.is_active });
  }, [edit]);
  const save = async () => {
    const r = await run(() => wfapi.saveItem({ ...(edit && edit !== 'new' ? { id: edit.id } : {}), ...f, name_ar: f.name_ar || null, unit_cost: f.unit_cost || null,
      replace_months: f.replace_months ? Number(f.replace_months) : null }), t('c.saved'));
    if (r) onDone(r);
  };
  return (
    <Modal open={!!edit} title={t(edit === 'new' ? 'as2.new_item' : 'as2.edit_item')} onClose={onClose}
      footer={<><Button onClick={onClose}>{t('c.cancel')}</Button><Button kind="primary" busy={busy} disabled={!f.code.trim() || !f.name_en.trim()} onClick={() => void save()}>{t('c.save')}</Button></>}>
      <div className="stack">
        <div className="grid-2">
          <Input label={t('tr.code')} required ltr value={f.code} onChange={(e) => setF({ ...f, code: e.target.value.toUpperCase() })} />
          <Select label={t('tr.category')} value={f.category} onChange={(e) => setF({ ...f, category: e.target.value as AssetCategory })}>
            {ASSET_CATEGORIES.map((c) => <option key={c} value={c}>{t(`as2.cat_${c}` as Key)}</option>)}
          </Select>
        </div>
        <Input label={t('tr.name_en')} required value={f.name_en} onChange={(e) => setF({ ...f, name_en: e.target.value })} />
        <Input label={t('tr.name_ar')} dir="rtl" value={f.name_ar} onChange={(e) => setF({ ...f, name_ar: e.target.value })} />
        <div className="grid-2">
          <Input label={t('as2.unit_cost')} inputMode="decimal" ltr value={f.unit_cost} onChange={(e) => setF({ ...f, unit_cost: e.target.value })} />
          <Input label={t('as2.replace')} type="number" min={1} max={60} ltr value={f.replace_months} onChange={(e) => setF({ ...f, replace_months: e.target.value })} />
        </div>
        <Check label={t('as2.returnable')} checked={f.returnable} onChange={(v) => setF({ ...f, returnable: v })} />
        <Check label={t('tr.active')} checked={f.is_active} onChange={(v) => setF({ ...f, is_active: v })} />
      </div>
    </Modal>
  );
}
