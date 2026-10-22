# AACT HRMS — user acceptance test (UAT) plan

**Purpose:** AACT staff confirm that the system does what the business needs, with their own rules, before real use.
**Where:** a test copy on the company server (restore of the migrated data into a separate installation, or the cloud test
project with dummy data for the first round). **Never** test on the live database after go-live.
**Who:** HR manager (lead), HR officer, Finance (payroll), two line managers, three employees (one Omani, one expatriate, one on
probation), IT (server), auditor.
**Duration:** two weeks for the functional rounds, plus one full payroll month in parallel with the old system.

## How to record results
For each test write: date, tester, **Pass / Fail / Pass with remark**, and for a failure what happened and a screenshot.
A failure is graded **A** (blocks go-live: wrong money, wrong legal result, data visible to the wrong person),
**B** (must be fixed before go-live but has a workaround) or **C** (improvement, can follow later).
Go-live needs **no open A or B items**.

## 1. Access and security
| # | Test | Who | Expected |
|---|---|---|---|
| 1.1 | Sign in, sign out, reset password by e-mail | everyone | Reset mail arrives; old password stops working |
| 1.2 | Employee opens another employee's page (change the address bar) | employee | "Not allowed"; nothing shown |
| 1.3 | Line manager sees only his team in Employees, Attendance, Leave | manager | Other departments not listed |
| 1.4 | Auditor tries to change any record | auditor | Read-only everywhere |
| 1.5 | Salary and bank details hidden from roles without permission | HR officer, manager | Amounts not shown |
| 1.6 | Every change appears in the audit trail with old and new value | HR manager | Entry with user and time |
| 1.7 | Arabic screens: switch language; names, dates and numbers read correctly; phone layout usable | all | No mixed-up text order, no sideways scrolling |

## 2. Employees, documents and Omanisation
| # | Test | Expected |
|---|---|---|
| 2.1 | Add an employee; try the same name + date of birth + nationality again | Duplicate warning |
| 2.2 | Put an expatriate in an Omani-only job | Refused unless an exception is raised and approved by another person |
| 2.3 | Transfer, promotion and salary change with future dates | History kept; current values change on the date |
| 2.4 | Upload passport and resident card; set an expiry within 30 days | Shown in Expiries; daily notification to HR and manager |
| 2.5 | Omanisation page and Localisation report (MoL) | Same counts as the last MoL statement; Omani-only violations listed |
| 2.6 | Imported data spot check: 20 employees picked at random | All fields match the old system |

## 3. Time and leave
| # | Test | Expected |
|---|---|---|
| 3.1 | Import a device punch file for one month | Attendance days, late minutes and missing punches correct for 10 checked people |
| 3.2 | Ramadan hours and public holidays | Shorter Ramadan day applied as set in the Oman time rules (the system stores no religion); holiday not counted absent |
| 3.3 | Overtime request (day / night / rest day) | Rates as per the approved Oman time rules; manager then HR approve |
| 3.4 | Annual leave request over a weekend and holiday | Days counted correctly; balance reduced after approval |
| 3.5 | Sick leave beyond the fully paid days | Pay percentage steps down as the rule says |
| 3.6 | Close the month (lock) and try to change a punch | Refused; correction needs reopening by an authorised person |

## 4. Payroll (with Finance)
| # | Test | Expected |
|---|---|---|
| 4.1 | Calculate a month; verify; approve by a third person | Same person cannot do two steps |
| 4.2 | **Parallel run**: compare net pay per employee with the old system | Every difference explained (rule, data, or error fixed) |
| 4.3 | SPF: Omani employee old-age, injury, job security; ceiling | Matches the Fund's calculation; **SPF contributions report** totals = payroll totals |
| 4.4 | Expatriate: no SPF employee deduction; employer items only | As per the approved rules |
| 4.5 | Loan instalments and one-off deductions (25 % limit) | Never more than the legal limit; the rest carried forward |
| 4.6 | Bank file (WPS) and journal | Bank accepts the file in a test upload; journal balances |
| 4.7 | Final settlement: resignation and termination, both before and after July 2023 service | Gratuity, leave pay, notice pay correct; approved by another person |
| 4.8 | Payslips: employee sees only his own; Arabic payslip prints | Correct |
| 4.9 | Management (MG) pay: HR manager, HR officer, normal Finance and the auditor open an MG employee; MG run made and approved by three team members | No salary, bank, payslip, loan, settlement or salary-letter figure of MG staff visible outside the team; MG run, bank file and SPF schedule separate; HR still sees attendance, leave and documents |

## 5. Self-service, letters, recruitment
| # | Test | Expected |
|---|---|---|
| 5.1 | Employee asks to change address and bank account | HR approves address; Finance approves bank |
| 5.2 | Salary certificate / NOC letter requested, prepared, approved | Letter has reference and QR code; *Verify* page confirms it; revoked letter shows as revoked |
| 5.3 | Requisition → candidates → interview → offer → hire | Probation limited by law; employee created; salary sent for approval; onboarding checklist created |
| 5.4 | Probation reminder and confirmation | Reminder before the end date; confirmation updates status |

## 6. People operations
| # | Test | Expected |
|---|---|---|
| 6.1 | Appraisal cycle: self-assessment → manager → HR → employee acknowledges | Rating calculated; HR cannot finalise a review it wrote |
| 6.2 | Improvement plan shorter than 6 months | Refused; "not improved" only after the end date |
| 6.3 | Training record with expiry | Appears in Expiries; mandatory-course gaps listed |
| 6.4 | Disciplinary case: employee responds, penalty proposed and decided by a different person | Deduction above the limit refused; deduction goes to payroll for Finance approval; employee can appeal |
| 6.5 | Issue PPE, return a damaged item with recovery | Recovery waits for Finance approval |
| 6.6 | Work injury (lost time) | HR alerted; overdue flag if not reported to the SPF in time |
| 6.7 | Exit: resignation with short notice; then with 30 days | Short notice refused (unless pay in lieu); clearance list includes items, housing, expat steps; completing separates the employee |

## 7. Data protection (PDPL) and reports
| # | Test | Expected |
|---|---|---|
| 7.1 | Publish the privacy notice (prepared by one person, published by another); employees acknowledge | Acknowledgement count rises |
| 7.2 | Employee makes an access request | Due date 45 days later; HR notified; employee told when answered |
| 7.3 | Record a breach discovered 3 days ago | Shown as overdue for the 72-hour notification |
| 7.4 | Retention: candidates past 12 months anonymised | Names and contacts removed |
| 7.5 | Executive dashboard | Head-count, Omani %, turnover and payroll cost agree with the reports |

## 8. Server and recovery (IT)
| # | Test | Expected |
|---|---|---|
| 8.1 | Nightly backup runs; off-site copy present | Folder with dump, files, checksums |
| 8.2 | `restore.sh --verify` on last night's backup | "restore test passed" |
| 8.3 | Full restore rehearsal on the test server | System works with yesterday's data; time taken recorded |
| 8.4 | Upgrade rehearsal with `update.sh` | Migrations applied; no data lost |
| 8.5 | Certificate valid; ports 5432/6543/8000 not reachable from another PC | Correct |

## Sign-off
| Area | Name | Signature | Date | Open A/B items |
|---|---|---|---|---|
| HR | | | | |
| Finance / payroll | | | | |
| IT / server | | | | |
| Management | | | | |
