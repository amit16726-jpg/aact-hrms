import { useState } from 'react';
import { Link, useParams } from 'react-router-dom';
import { ArrowLeft, CircleCheck, Lock, UserRound } from 'lucide-react';
import { useI18n } from '../../i18n';
import { collectAnswers, eapi } from '../../lib/api_eng';
import { Button, ErrorNote, Loading, useAction, useAsync, useToast } from '../../components/ui';
import { EngStatus, RatingScale } from '../../components/eng';
import { fmtDate } from '../../lib/format';

export default function SurveyPage() {
  const { id = '' } = useParams();
  const { t, L } = useI18n();
  const { data: s, error, loading, reload } = useAsync(() => eapi.getSurvey(id), [id]);
  const [vals, setVals] = useState<Record<string, number | string | undefined>>({});
  const [missing, setMissing] = useState<string | null>(null);
  const [done, setDone] = useState(false);
  const { busy, run } = useAction();
  const { push } = useToast();

  const submit = async () => {
    if (!s) return;
    const c = collectAnswers(s.questions, vals);
    setMissing(c.missing);
    if (c.missing) {
      push(t('eg.required_q'), true);
      document.getElementById(`sq-${c.missing}`)?.scrollIntoView({ behavior: 'smooth', block: 'center' });
      return;
    }
    const r = await run(() => eapi.answerSurvey(s.id, c.answers), t('eg.thanks'));
    if (r) setDone(true);
  };

  const canAnswer = !!s?.can_answer && !done;
  return (
    <div className="stack eg-article-wrap">
      <Link to="/engage?tab=surveys" className="eg-back"><ArrowLeft size={16} aria-hidden="true" className="eg-back-ico" />{t('eg.tab_surveys')}</Link>
      <ErrorNote error={error} onRetry={reload} />
      {loading && !s ? <Loading /> : s && (
        <div className="panel eg-article">
          <div className="eg-ann-top">
            <span className={`eg-chip ${s.anonymous ? 'eg-anon' : ''}`}>{s.anonymous ? <Lock size={13} aria-hidden="true" /> : <UserRound size={13} aria-hidden="true" />}
              {s.anonymous ? t('eg.anonymous') : t('eg.named')}</span>
            <span className="eg-ann-date">{t('eg.closes', { d: fmtDate(s.closes_on) })}</span>
            {!s.live && <EngStatus s={s.status} />}
          </div>
          <h1>{L(s.title_en, s.title_ar)}</h1>
          {(s.intro_en || s.intro_ar) && <div className="eg-body">{L(s.intro_en, s.intro_ar)}</div>}
          <div className={`note ${s.anonymous ? 'note-ok' : 'note-warn'}`}>{s.anonymous ? t('eg.anon_note') : t('eg.named_note')}</div>

          {(done || s.answered) ? (
            <div className="eg-thanks"><CircleCheck size={40} aria-hidden="true" /><p>{done ? t('eg.thanks') : t('eg.already')}</p>
              <Link className="btn" to="/engage?tab=surveys">{t('eg.tab_surveys')}</Link></div>
          ) : (
            <form className="eg-questions" onSubmit={(e) => { e.preventDefault(); void submit(); }}>
              {!s.can_answer && <div className="note">{t('eg.not_open')}</div>}
              {s.questions.map((q, i) => {
                const key = q.key ?? `q${i + 1}`;
                const v = vals[key];
                return (
                  <fieldset key={key} id={`sq-${key}`} className={`eg-q${missing === key ? ' is-missing' : ''}`} disabled={!canAnswer}>
                    <legend><span className="eg-q-n num">{i + 1}</span>{L(q.text_en, q.text_ar)}{q.required && <span className="req" aria-hidden="true"> *</span>}</legend>
                    {q.kind === 'RATING' && <RatingScale name={key} value={typeof v === 'number' ? v : undefined} disabled={!canAnswer}
                      onChange={(n) => setVals({ ...vals, [key]: n })} />}
                    {q.kind === 'CHOICE' && (
                      <div className="eg-choices" role="radiogroup">
                        {q.options.map((o, oi) => (
                          <label key={oi} className={`eg-choice${v === oi ? ' is-on' : ''}`}>
                            <input type="radio" name={key} checked={v === oi} onChange={() => setVals({ ...vals, [key]: oi })} />
                            <span>{L(o.en, o.ar)}</span>
                          </label>))}
                      </div>)}
                    {q.kind === 'TEXT' && (
                      <div className="field">
                        <textarea className="textarea" rows={4} maxLength={1000} aria-label={t('eg.your_answer')} value={typeof v === 'string' ? v : ''}
                          onChange={(e) => setVals({ ...vals, [key]: e.target.value })} />
                        <span className="hint">{t('eg.chars_left', { n: 1000 - (typeof v === 'string' ? v.length : 0) })}</span>
                      </div>)}
                  </fieldset>);
              })}
              {canAnswer && <div className="row" style={{ justifyContent: 'flex-end' }}><Button kind="primary" type="submit" busy={busy}>{t('eg.submit')}</Button></div>}
            </form>
          )}
        </div>
      )}
    </div>
  );
}
