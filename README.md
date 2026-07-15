# HR Workforce Analytics — MySQL & Power BI

A normalized HR analytics data warehouse built in MySQL, covering headcount, employment history, attendance, performance, recruitment, and Nigerian statutory payroll compliance — connected to a Power BI dashboard for turnover, attrition, and compensation-cost analysis.

This project follows on from an earlier [[stock market investment analysis portfolio project](https://github.com/muhammed2624/Stock-Market-Analysis)](#), moving from financial time-series analysis into HR/people analytics with a Nigeria-specific compliance layer (PAYE, PENCOM, NHF, NSITF, ITF).

---

## Overview

The database models the full employee lifecycle — from job requisition and application, through hiring, promotions, attendance, and performance reviews, to exit and statutory payroll deductions — as 10 normalized tables and 7 analytics views.

**Stack:** MySQL 8.0 · MySQL Workbench · Power BI Desktop

## Entity-Relationship Diagram

The schema is built around `employees` as the central table, with dedicated tables separating operational HR data (attendance, performance) from compliance-sensitive payroll data, and a two-table recruitment funnel (`job_requisitions` → `applicants`) that feeds into `employees` once someone is hired.

*(See `/docs/erd.png` for the full diagram)*

**Tables:** `departments`, `job_titles`, `employees`, `employment_history`, `attendance`, `performance_reviews`, `payroll`, `exit_interviews`, `job_requisitions`, `applicants`

**Views:** `v_headcount_by_department`, `v_monthly_turnover`, `v_attrition_by_reason`, `v_time_to_hire`, `v_source_of_hire`, `v_requisition_pipeline`, `v_payroll_cost_by_department`

## Key Design Decisions

- **`employment_history` as an event log** — rather than overwriting an employee's current department/title/salary, every change is recorded as its own row. This is what makes promotion velocity and department-transfer analysis possible, instead of only ever seeing a snapshot of "now."
- **Payroll separated from HR ops data** — `payroll` holds PAYE, employee/employer pension, NHF, NSITF, and ITF as individual columns rather than one lump deduction figure, mapping directly onto Nigerian statutory requirements (Nigeria Tax Act 2025, PENCOM).
- **Recruitment funnel modeled as two tables** — `job_requisitions` (the "we need to hire" record) and `applicants` (each person who applied), with `applicants.employee_id` populated only once someone is actually hired — linking recruitment data straight into the employee lifecycle.
- **Data integrity enforced at the database level**, not just the application layer — foreign keys throughout, a `CHECK` constraint requiring a `termination_date` whenever `employment_status = 'Terminated'`, and `UNIQUE` constraints preventing duplicate payroll runs or double-booked attendance days.

## Sample Dataset

The repo includes a seed script (`hr_analytics_seed_data.sql`) generating a realistic synthetic dataset:

| Table | Rows |
|---|---|
| departments | 6 |
| job_titles | 16 |
| employees | 60 |
| employment_history | 92 |
| attendance | 820 |
| performance_reviews | 54 |
| payroll | 267 |
| exit_interviews | 17 |
| job_requisitions | 12 |
| applicants | 74 |

## Sample Insights (from the seeded dataset)

- **Overall attrition: 28.3%** of all-time hires (17 of 60) have left the company — high enough to warrant a closer look at exit reasons by department.
- **Customer Service carries the largest active headcount** (12 of 41 active employees), followed by Operations (9).
- Turnover, exit-reason, and payroll-cost trends are broken down month-by-month and department-by-department in the corresponding views — see `v_monthly_turnover` and `v_attrition_by_reason` for the full breakdown.



## Files in this Repo

```
├── hr_analytics_schema.sql        -- creates database, 10 tables, 7 views (run first)
├── hr_analytics_seed_data.sql     -- populates all tables with sample data (run second)
├── docs/
│   └── erd.png                    -- entity-relationship diagram
├── dashboard/
│   └── hr_analytics_dashboard.pbix -- Power BI dashboard file
└── README.md
```

## How to Run This Locally

1. Clone this repo
2. Open MySQL Workbench, connect to your local MySQL instance
3. Run `hr_analytics_schema.sql` — creates the `hr_analytics` database and all tables/views
4. Run `hr_analytics_seed_data.sql` — populates the tables with sample data
5. Open `dashboard/hr_analytics_dashboard.pbix` in Power BI Desktop, or connect fresh via **Get Data → Text/CSV** using views exported from Workbench (see note below)

**Note on Power BI connectivity:** MySQL's native Power BI connector (Connector/NET) and the ODBC driver both have known, version-specific compatibility issues on Windows. If you hit an "additional components" or authentication error, the most reliable workaround is exporting each view to CSV from Workbench (Results grid → Export) and loading those into Power BI via **Get Data → Text/CSV**.

## Skills Demonstrated

- Relational database design & normalization (3NF, event-log modeling for history tracking)
- SQL: multi-table joins, correlated subqueries, `GROUP BY` aggregation, window-independent view design
- Debugging MySQL's `ONLY_FULL_GROUP_BY` strict mode in production-style view logic
- Nigerian statutory payroll compliance modeling (PAYE, PENCOM, NHF, NSITF, ITF)
- Power BI dashboard design: stacked bar/column charts, line charts, donut charts, slicers
- End-to-end data pipeline: MySQL → CSV export → Power BI

---

*Part of an ongoing data analytics portfolio by Ijiola Muhammed Abiodun (MOTTG), Lagos, Nigeria.*
