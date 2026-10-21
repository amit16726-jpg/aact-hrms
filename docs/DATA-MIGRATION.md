# Moving data from the old system

Done once, on the company server, by the HR manager (permission **Import data**), with IT on hand.
Every import can be **tried first**: a trial run checks every row and saves nothing. Each run (trial or real) is kept in the
import history with its results.

## Order

| Step | What | Where | Notes |
|---|---|---|---|
| 1 | Companies, departments, job titles (with MoL profession codes and Omani-only flags), grades, employee categories, locations, cost centres, shifts | *Organisation*, *Shifts* | Entered by hand; the import uses their **codes** |
| 2 | Pay components and legal rules (SPF, gratuity, overtime, leave) with effective dates | *Payroll setup*, *Payroll rules*, *Oman time rules* | Confirm values with the lawyer first |
| 3 | **Employees** | *Import data → Employees* | Import line managers first (or in an earlier file) — a manager's employee number must already exist |
| 4 | **Documents** (passport, visa, resident card, labour card, contract copy…) | *Import data → Documents* | Numbers and dates only; scans can be attached later on each employee |
| 5 | **Opening salaries** | *Import data → Opening salaries* | Created as proposals; a second person approves them in *Approvals* |
| 6 | Opening leave balances | *Leave → Balances → Import* | Days as at the opening date; approved by a second person |
| 7 | Contracts, bank accounts, emergency contacts | each employee | Bank accounts are approved by Finance |
| 8 | Check | *Employees*, *Expiries*, *Omanisation*, *Localisation report* | Compare head-count, Omani %, and totals with the old system |
| 9 | Parallel payroll | *Payroll* → *Parallel run* | At least one month; every difference explained before go-live |

## Preparing the files

1. In *Import data*, choose the type and click **Download template**. Open it in Excel.
2. Fill one row per record. Keep the first row (the column headings) exactly as it is. Extra columns are ignored.
3. Dates: `YYYY-MM-DD` (e.g. `2021-03-01`) or `DD/MM/YYYY` (e.g. `01/03/2021`).
4. **Save As → "CSV UTF-8 (Comma delimited)"** — this keeps Arabic names correct.
5. Upload, run **Trial run**, fix the rows listed with problems, upload again, and only then **Import**.

### Employees — columns

| Column | Required | Example | Rule |
|---|---|---|---|
| `employee_no` | no | `AACT-00101` | Blank = next number automatically |
| `full_name_en` | yes | `Ravi Kumar` | |
| `full_name_ar` | no | `رافي كومار` | |
| `nationality` | yes | `IN`, `OM` | 2-letter country code |
| `gender` | no | `M` / `F` | |
| `date_of_birth` | no | `1990-05-20` | |
| `marital_status` | no | `SINGLE`, `MARRIED`, `DIVORCED`, `WIDOWED` | |
| `civil_number` | no | | Omani civil ID / resident card number |
| `mobile`, `personal_email`, `work_email` | no | `+968 9123 4567` | |
| `join_date` | yes | `2021-03-01` | |
| `probation_end_date` | no | | After the join date → employee is *on probation* |
| `company_code` | if more than one company | `AACT` | |
| `department_code`, `job_code`, `category_code` | yes | `PROD`, `OPR`, `WRK` | Codes from *Organisation* |
| `grade_code`, `location_code` | no | `W1`, `SOHAR` | |
| `manager_employee_no` | no | `AACT-00001` | Must already exist |
| `employment_type` | no | `FULL_TIME` | |
| `shift_code` | no | `DAY` | |

The usual rules apply exactly as when typing an employee in: duplicate check (same name, date of birth and nationality),
**Omani-only jobs** (an expatriate in an Omani-only job is refused unless an exception reason is given in an
`exception_reason` column and approved later), numbering format.

### Documents — columns
`employee_no`, `doc_type` (e.g. `PASSPORT`, `RESIDENT_CARD`, `EMPLOYMENT_VISA`, `WORK_PERMIT`), `doc_number`, `issue_date`,
`expiry_date`, `issuing_authority`, `issue_place`, `notes`. Number and expiry date are required for the types that have them.

### Opening salaries — columns
`employee_no`, `effective_from` (blank = joining date), then **one column per pay component code** (`BASIC`, `HOUSING`,
`TRANSPORT`, …) with the monthly amount, and `notes`. `BASIC` is required. Each row becomes a salary proposal waiting for approval.

## After the import
- Run the **Localisation report** and **Omanisation** page and compare with the last MoL statement.
- Run **Expiries** — every expired or soon-expiring document is a task for HR.
- Ask every employee to sign in, check *My HR*, and acknowledge the **privacy notice**.
