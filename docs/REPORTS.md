# Report centre (1.13.0)

*Reports* in the menu (group *Reports & governance*). Every report: choose the filters, **Run report** to preview on screen,
then **Excel** (formatted workbook: title block, filters, number formats, totals, frozen header, filters on every column, right-to-left
sheet in Arabic) or **PDF** (A4, landscape for wide reports, company and report name, filters, page numbers and a confidentiality line
on every page, Arabic rendered exactly as on screen). In the phone apps the file opens the share sheet.

* Each report needs the permission shown; people see only the employees they may see on the screens.
* Pay reports never show management (MG) staff to anyone outside the management payroll team; an MG payroll run is refused.
* Opening a pay or sensitive report is written to the access log (report A02 lists it).
* **Board pack** (*Reports → Board pack*, permission EXEC_VIEW): PowerPoint with editable charts — key figures, headcount, joiners and
  leavers, Omanisation, workforce mix, payroll cost, overtime and absence, risks, leavers by reason.
* **Scheduled reports** (permission REPORT_ADMIN): on a chosen day each month the chosen people get an in-app notification and an
  e-mail with a link to the report (never the report itself). Relative periods: previous month, month to date, year to date.

Developers: catalogue `hr.report_defs`; one function `hr.rpt_<code>(params)` per report; `public.hr_run_report(code, params)`
checks the permission and returns `{columns, rows, meta}`; files are made in the browser (`src/lib/report_export.ts`).
Tests: `tests/db/95_reports.sql` (every report for every company), `e2e/report_files.py` (real Excel / PDF / PowerPoint files).

## Workforce

| Code | Report | Filters | Permission | What it shows |
|---|---|---|---|---|
| W01 | Headcount by department | entity, as_of, pay_group | EMP_READ | Active employees on a date by department: Omani / expatriate, male / female, MG / NMG. |
| W02 | Employee list | entity, as_of, department, pay_group, nationality_group | EMP_READ | Every employee on a date with job, department, nationality, age, service and status. |
| W03 | Joiners | entity, from_to, department | EMP_READ | Employees who joined in the period. |
| W04 | Leavers | entity, from_to, department | EMP_READ | Employees who left in the period, with the reason and length of service. |
| W05 | Turnover by month | entity, month | EMP_READ | Opening and closing headcount, joiners, leavers and turnover for the 12 months to the chosen month. |
| W06 | Turnover by department | entity, from_to | EMP_READ | Leavers against average headcount per department for the period. |
| W07 | Nationality profile | entity, as_of, department | EMP_READ | Headcount by nationality and gender. |
| W08 | Age profile | entity, as_of, department | EMP_READ | Headcount by age band, Omani / expatriate and gender. |
| W09 | Length of service | entity, as_of, department | EMP_READ | Headcount by years of service. |
| W10 | Contracts ending | entity, days, department | EMP_READ | Fixed-term contracts ending within the chosen number of days (and already ended but still active). |
| W11 | Probation ending | entity, days, department | EMP_READ | Employees on probation whose probation ends within the chosen number of days. |
| W12 | Managers and team sizes | entity, as_of | EMP_READ | Line managers with the number of direct reports. |

## Payroll and end of service

| Code | Report | Filters | Permission | What it shows |
|---|---|---|---|---|
| P01 | Payroll register 🔒 | entity, run | PAY_READ | Every payslip of a payroll run: paid days, basic, earnings, deductions, net pay and employer cost. |
| P02 | Payroll by department 🔒 | entity, run | PAY_READ | Headcount, earnings, deductions, net pay and employer cost per department for a run. |
| P03 | Payroll by cost centre 🔒 | entity, run | PAY_READ | Payroll cost per cost centre for a run (for the finance journal). |
| P04 | Pay items summary 🔒 | entity, run | PAY_READ | Total of each earning, deduction and employer item in a run. |
| P05 | Payroll variance (month on month) 🔒 | entity, run | PAY_READ | Net pay of each employee compared with the previous month, largest changes first. |
| P06 | Bank transfer summary 🔒 | entity, run | PAY_READ | Net pay to transfer, by bank, for a run. |
| P07 | Bank transfer list 🔒 | entity, run | PAY_READ | Each employee's net pay and bank account for a run (account numbers masked without bank permission). |
| P08 | Social Protection Fund contributions 🔒 | entity, run | PAY_READ | Employee and employer SPF contributions per person for a run. |
| P09 | End-of-service (gratuity) liability 🔒 | entity, as_of, department | PAY_READ | Accrued gratuity of every expatriate on a date, split before and after 31 July 2023. |
| P10 | Loans and advances outstanding 🔒 | entity | PAY_READ | Approved loans and advances with the amount repaid and the balance. |
| P11 | Payroll cost trend 🔒 | entity, month, pay_group | PAY_READ | Approved payroll totals for the 12 months to the chosen month. |
| P12 | Salary changes 🔒 | entity, from_to | EMP_SALARY_READ | Approved salary revisions effective in the period, with the old and new monthly total. |
| P13 | Final settlements 🔒 | entity, from_to | PAY_READ | Final settlements with a last working day in the period. |
| P14 | Salary listing 🔒 | entity, as_of, department, pay_group | EMP_SALARY_READ | Approved monthly salary of every employee on a date: basic, allowances and gross. |
| P15 | One-off pay items 🔒 | entity, month | PAY_READ | Bonuses, commissions, arrears and one-off deductions for the month. |

## Time and leave

| Code | Report | Filters | Permission | What it shows |
|---|---|---|---|---|
| T01 | Attendance summary | entity, month, department | ATT_READ | Present, absent, leave, missing punches, lateness and hours per employee for a month. |
| T02 | Late arrivals | entity, from_to, department | ATT_READ | Every late arrival in the period with minutes late. |
| T03 | Absences | entity, from_to, department | ATT_READ | Days marked absent (no punch, no approved leave) in the period. |
| T04 | Missing punches | entity, from_to, department | ATT_READ | Days with only one punch, to be corrected before the month is locked. |
| T05 | Overtime | entity, from_to, department | ATT_READ | Approved overtime in the period with hours and payable hours. |
| T06 | Overtime by department | entity, from_to | ATT_READ | Approved overtime hours per department in the period. |
| T07 | Leave balances | entity, as_of, department, leave_type | LEAVE_READ | Entitled, taken, pending and available days per employee for a leave type (annual by default). |
| T08 | Annual leave liability 🔒 | entity, as_of, department | PAY_READ | Value of untaken annual leave on a date (available days × basic ÷ 30). |
| T09 | Leave taken | entity, from_to, department, leave_type | LEAVE_READ | Approved leave starting in the period. |
| T10 | Leave by type | entity, from_to | LEAVE_READ | Approved leave days and requests per leave type in the period. |

## Compliance

| Code | Report | Filters | Permission | What it shows |
|---|---|---|---|---|
| C01 | Omanisation by department | entity, as_of | COMPLIANCE_READ | Omani share of the counted workforce per department against the approved target. |
| C02 | Omanisation by profession | entity, as_of | COMPLIANCE_READ | Omani share per job title and Ministry of Labour profession code; Omani-only jobs flagged. |
| C03 | Document expiries | entity, days, department | DOC_READ | Documents, contracts and certificates expired or expiring within the chosen number of days. |
| C04 | Missing mandatory documents | entity, department | DOC_READ | Active employees without a current copy of a mandatory document. |
| C05 | Expatriate residence and permits | entity, department | DOC_READ | Each expatriate with passport, resident card, visa and work permit expiry dates. |
| C06 | Expatriates in Omani-only jobs | entity, as_of | COMPLIANCE_READ | Expatriates assigned to Omani-only job titles, with the approved exception if any. |

## Talent and people operations

| Code | Report | Filters | Permission | What it shows |
|---|---|---|---|---|
| R01 | Recruitment pipeline | entity | REC_READ | Open and recent requisitions with candidates at each stage. |
| R02 | Time to hire | entity, from_to | REC_READ | Days from requisition approval to each hire in the period. |
| R03 | Performance ratings | entity, cycle | PERF_MANAGE | Every review of an appraisal cycle with reviewer, stage and overall rating. |
| R04 | Rating distribution | entity, cycle | PERF_MANAGE | How finalised overall ratings of a cycle are spread. |
| R05 | Training completed | entity, from_to | TRAIN_WRITE | Training completed in the period with certificate expiry and cost. |
| R06 | Training by course | entity, from_to | TRAIN_WRITE | Participants and cost per course for training completed in the period. |
| R07 | Disciplinary cases 🔒 | entity, from_to | DISC_READ | Disciplinary cases opened in the period with status and penalty (every opening is logged). |
| R08 | Work injuries 🔒 | entity, from_to | HSE_WRITE | Work injuries in the period with severity, lost days and SPF reporting. |
| R09 | Assets with employees | entity | ASSET_WRITE | Items currently issued to employees, overdue returns first. |
| R10 | Exits | entity, from_to | EXIT_MANAGE | Exit cases with a last working day in the period, with type, reason and clearance progress. |
| R11 | Certificates expiring | entity, days | TRAIN_WRITE | Training certificates expired or expiring within the chosen number of days. |

## Audit and control

| Code | Report | Filters | Permission | What it shows |
|---|---|---|---|---|
| A01 | Audit trail | from_to, table | AUDIT_READ | Every change in the period (who, when, what) — up to 5,000 entries; filter by table. |
| A02 | Sensitive-data access log | from_to | AUDIT_READ | Who opened salaries, bank details, documents, discipline and money reports in the period. |
| A03 | Users and roles | — | AUDIT_READ | Every user with active roles, linked employee and status — for the periodic access review. |
| A04 | Approvals log (maker-checker) | from_to | AUDIT_READ | Who prepared and who approved each controlled decision in the period. |
| A05 | Self-approval and control exceptions | from_to | AUDIT_READ | Checks that nobody decided their own item and that payroll steps were done by different people. Empty means no exceptions. |

🔒 = pay or sensitive data; every opening is logged.
