# Employee engagement (1.14.0, announcements updated in 1.15.0)

Menu: **Engagement** (everyone) and **Engagement admin** (HR: `ENGAGE_MANAGE` prepares, `ENGAGE_APPROVE` approves).
Works the same in the browser and in the Android / iPhone apps, in English and Arabic.

## Announcements
- Category (general, HR policy, event, safety, holiday, celebration, IT), English and Arabic text, publish date and optional end date.
- Audience: all companies, one company, or one department (sub-departments included).
- Pin to the top; optionally ask everyone to **confirm they have read it** (safety and policy notices).
- Draft → sent for approval → approved by **another person** → published. Rejection needs a reason; the preparer edits and sends again.
- **Signed PDF (1.15.0):** optionally attach the signed circular (PDF, up to 10 MB). Stored in the private bucket `hr-engage`
  (`ann/<random>.pdf`); HR can open it at any time, employees only while the announcement is live for them. Replacing or removing the PDF
  changes the draft (it goes through approval again); old files are kept, never overwritten.
- **Translate (1.15.0):** *English → Arabic* / *Arabic → English* fill the other language's title and message in one step.
  Arabic follows official Omani circulars and a glossary of Omani terms; *Undo* restores the previous text. Always read the result
  before sending for approval. Set-up: `docs/ENVIRONMENTS.md` → *Translation*.
- Everyone in the audience is notified on the publish date (high priority when confirmation is asked). HR sees read and confirmed counts and the list of who has / has not.

## Surveys
- Questions: rating 1–5, one choice (2–10 choices), free text; each optional or required; up to 30 questions; open for up to 180 days.
- Approved by a second person before it opens; employees are notified; one answer per person.
- **Anonymous surveys (default):** who took part is recorded only to stop double answers (date only). Answers carry no person and no time,
  and are kept out of the audit trail. Results stay hidden until at least 5 people have answered (setting `engagement.survey_min_responses`).
- Named surveys keep the employee with each answer and say so to the person answering.
- Opening results is recorded in the access log. Surveys close automatically after the closing date (daily job 06:05 Muscat).

## Recognition
- Any employee can thank a colleague in the same company: category + short message; posted straight away; colleague and their manager notified.
- At most 5 a day per person (setting `engagement.peer_daily_limit`); colleagues can applaud a post once.
- HR can hide an unsuitable post with a reason (kept in the audit trail).
- **Awards** (e.g. Employee of the month) are proposed by HR and approved by a second person who is not the winner.
- "Most recognised this month" shows the top five.

## Settings
`hr.settings` key `engagement`: `{"survey_min_responses": 5, "peer_daily_limit": 5}`; optional `"translate_daily_limit": 100` (translations per person per day).
`hr.settings` key `translation_glossary`: company terms used by the translator, e.g. `[{"en": "Rusayl plant", "ar": "مصنع الرسيل"}]`
(they take priority over the built-in Omani glossary in `supabase/functions/_shared/translate.ts`).
