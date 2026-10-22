import { useState } from 'react';
import { Link, useSearchParams } from 'react-router-dom';
import { ClipboardList, HandHeart, Megaphone, Trophy } from 'lucide-react';
import { useI18n, type Key } from '../../i18n';
import { eapi, RECOG_CATEGORIES, type EngageHome, type RecogCategory, type Recognition } from '../../lib/api_eng';
import type { EmpBrief } from '../../lib/api_time';
import { Button, Empty, ErrorNote, Loading, Modal, Select, Tabs, Textarea, useAction, useAsync, useConfirm } from '../../components/ui';
import { PageHead } from '../../components/Layout';
import { AnnouncementCard, Avatar, ColleaguePicker, RecognitionCard } from '../../components/eng';
import { fmtDate } from '../../lib/format';

type Tab = 'news' | 'surveys' | 'recognition';

export default function EngagePage() {
  const { t } = useI18n();
  const [sp, setSp] = useSearchParams();
  const { data, error, loading, reload, setData } = useAsync(() => eapi.home(), []);
  const tab = (['news', 'surveys', 'recognition'].includes(sp.get('tab') ?? '') ? sp.get('tab') : 'news') as Tab;
  const openSurveys = (data?.surveys ?? []).filter((s) => !s.answered).length;
  const tabs: { id: Tab; label: string }[] = [
    { id: 'news', label: data?.unread ? `${t('eg.tab_news')} (${data.unread})` : t('eg.tab_news') },
    { id: 'surveys', label: openSurveys ? `${t('eg.tab_surveys')} (${openSurveys})` : t('eg.tab_surveys') },
    { id: 'recognition', label: t('eg.tab_recog') },
  ];
  return (
    <div className="stack">
      <PageHead title={t('eg.title')} sub={t('eg.sub')}
        actions={(data?.caps.manage || data?.caps.approve) ? <Link className="btn" to="/engage/admin">{t('enav.admin')}</Link> : undefined} />
      <ErrorNote error={error} onRetry={reload} />
      {loading && !data ? <Loading /> : data && (
        <>
          <div className="eg-summary">
            <button type="button" className="eg-sum" onClick={() => setSp({}, { replace: true })}>
              <Megaphone size={20} aria-hidden="true" /><span><b className="num">{data.unread}</b>{t('eg.s_unread')}</span>
            </button>
            <button type="button" className={`eg-sum${data.to_confirm ? ' is-due' : ''}`} onClick={() => setSp({}, { replace: true })}>
              <HandHeart size={20} aria-hidden="true" /><span><b className="num">{data.to_confirm}</b>{t('eg.s_confirm')}</span>
            </button>
            <button type="button" className={`eg-sum${openSurveys ? ' is-due' : ''}`} onClick={() => setSp({ tab: 'surveys' }, { replace: true })}>
              <ClipboardList size={20} aria-hidden="true" /><span><b className="num">{openSurveys}</b>{t('eg.s_surveys')}</span>
            </button>
            <button type="button" className="eg-sum" onClick={() => setSp({ tab: 'recognition' }, { replace: true })}>
              <Trophy size={20} aria-hidden="true" /><span><b className="num">{data.my_count}</b>{t('eg.s_recognised')}</span>
            </button>
          </div>
          <Tabs label={t('eg.title')} value={tab} tabs={tabs} onChange={(v) => setSp(v === 'news' ? {} : { tab: v }, { replace: true })} />
          {tab === 'news' && <News data={data} />}
          {tab === 'surveys' && <Surveys data={data} />}
          {tab === 'recognition' && <RecognitionTab data={data} onData={setData} />}
        </>
      )}
    </div>
  );
}

function News({ data }: { data: EngageHome }) {
  const { t } = useI18n();
  if (!data.announcements.length) return <Empty>{t('eg.no_news')}</Empty>;
  return <div className="eg-feed">{data.announcements.map((a) => <AnnouncementCard key={a.id} a={a} />)}</div>;
}

function Surveys({ data }: { data: EngageHome }) {
  const { t, L } = useI18n();
  if (!data.surveys.length) return <Empty>{t('eg.no_surveys')}</Empty>;
  return (
    <div className="eg-survey-list">
      {data.surveys.map((s) => (
        <div key={s.id} className={`eg-survey-card${s.answered ? ' is-done' : ''}`}>
          <div className="eg-survey-icon" aria-hidden="true"><ClipboardList size={22} /></div>
          <div className="eg-survey-main">
            <h3>{L(s.title_en, s.title_ar)}</h3>
            <div className="eg-meta">
              <span>{t('eg.closes', { d: fmtDate(s.closes_on) })}</span>
              <span>{(s.questions.length === 1 ? t('eg.one_question') : t('eg.n_questions', { n: s.questions.length }))}</span>
              <span className={`eg-chip ${s.anonymous ? 'eg-anon' : ''}`}>{s.anonymous ? t('eg.anonymous') : t('eg.named')}</span>
            </div>
          </div>
          {s.answered
            ? <span className="eg-done">{t('eg.answered')}</span>
            : <Link className="btn btn-primary" to={`/engage/survey/${s.id}`}>{t('eg.answer')}</Link>}
        </div>))}
    </div>
  );
}

function RecognitionTab({ data, onData }: { data: EngageHome; onData: (d: EngageHome) => void }) {
  const { t, L } = useI18n();
  const [open, setOpen] = useState(false);
  const { run } = useAction();
  const confirm = useConfirm();
  const update = (r: Recognition) => onData({ ...data, recognitions: data.recognitions.map((x) => (x.id === r.id ? r : x)) });
  const hide = async (r: Recognition) => {
    const reason = await confirm.ask({ title: t('eg.hide'), reason: 'required', reasonLabel: t('eg.hide_reason'), danger: true, okLabel: t('eg.hide') });
    if (reason === null) return;
    const res = await run(() => eapi.hide(r.id, reason), t('eg.hidden_ok'));
    if (res) onData({ ...data, recognitions: data.recognitions.filter((x) => x.id !== r.id) });
  };
  return (
    <div className="eg-recog-layout">
      <section className="stack" aria-label={t('eg.wall')}>
        {data.recognitions.length
          ? data.recognitions.map((r) => <RecognitionCard key={r.id} r={r} onChange={update} onHide={(x) => void hide(x)} />)
          : <Empty>{t('eg.no_recog')}</Empty>}
      </section>
      <aside className="stack">
        <div className="panel panel-pad eg-give-box">
          <HandHeart size={28} aria-hidden="true" />
          <h2>{t('eg.recognise')}</h2>
          {data.caps.recognise
            ? <Button kind="primary" onClick={() => setOpen(true)}>{t('eg.recognise')}</Button>
            : <p className="muted small">{t('eg.not_linked')}</p>}
          {data.caps.recognise && <p className="muted small">{t('eg.my_count', { n: data.my_count })}</p>}
        </div>
        <div className="panel">
          <div className="panel-head"><h2>{t('eg.top_month')}</h2></div>
          <div className="panel-pad">
            {data.top_month.length ? (
              <ol className="eg-top">
                {data.top_month.map((p) => (
                  <li key={p.employee_id}>
                    <Avatar name={p.full_name_en} />
                    <span className="eg-top-name"><b>{L(p.full_name_en, p.full_name_ar)}</b>
                      {p.department_en && <span className="muted small">{L(p.department_en, p.department_ar)}</span>}</span>
                    <span className="eg-top-n num">{t('eg.times', { n: p.count })}</span>
                  </li>))}
              </ol>) : <p className="muted small">{t('eg.no_recog')}</p>}
          </div>
        </div>
      </aside>
      <GiveDialog open={open} onClose={() => setOpen(false)}
        onDone={(r) => onData({ ...data, recognitions: [r, ...data.recognitions] })} />
      {confirm.node}
    </div>
  );
}

function GiveDialog({ open, onClose, onDone }: { open: boolean; onClose: () => void; onDone: (r: Recognition) => void }) {
  const { t } = useI18n();
  const { busy, run } = useAction();
  const [who, setWho] = useState<EmpBrief | null>(null);
  const [cat, setCat] = useState<RecogCategory>('TEAMWORK');
  const [msg, setMsg] = useState('');
  const reset = () => { setWho(null); setCat('TEAMWORK'); setMsg(''); };
  const submit = async () => {
    if (!who) return;
    const r = await run(() => eapi.give({ employee_id: who.employee_id, category: cat, message: msg.trim() }), t('eg.sent'));
    if (r) { onDone(r); reset(); onClose(); }
  };
  if (!open) return null;
  return (
    <Modal open title={t('eg.recognise')} onClose={() => { reset(); onClose(); }}
      footer={<><Button onClick={() => { reset(); onClose(); }}>{t('c.cancel')}</Button>
        <Button kind="primary" busy={busy} disabled={!who || msg.trim().length < 3} onClick={() => void submit()}>{t('eg.give')}</Button></>}>
      <div className="stack">
        <ColleaguePicker value={who} onChange={setWho} />
        <Select label={t('eg.for')} value={cat} onChange={(e) => setCat(e.target.value as RecogCategory)}>
          {RECOG_CATEGORIES.map((c) => <option key={c} value={c}>{t(`eg.rc_${c}` as Key)}</option>)}
        </Select>
        <Textarea label={t('eg.message')} hint={t('eg.message_hint')} required maxLength={500} rows={4} value={msg} onChange={(e) => setMsg(e.target.value)} />
      </div>
    </Modal>
  );
}
