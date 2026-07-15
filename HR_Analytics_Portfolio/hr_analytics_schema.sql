-- ============================================================
-- HR Workforce Analytics Schema (MySQL 8.0+)
-- Covers: headcount, promotions/transfers, attendance,
--         performance, Nigerian statutory payroll, attrition,
--         and recruitment (requisitions + applicants)
-- ============================================================

-- Creates the database only if it doesn't already exist.
-- utf8mb4 supports full Unicode (emoji, accented names, etc.)
-- and is the recommended default character set for MySQL 8.
CREATE DATABASE IF NOT EXISTS hr_analytics
  CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;

-- Every statement after this runs against the hr_analytics database,
-- so we don't have to prefix every table name with "hr_analytics."
USE hr_analytics;

-- ------------------------------------------------------------
-- 1. DEPARTMENTS
-- The top-level grouping every employee and job title belongs to.
-- ------------------------------------------------------------
CREATE TABLE departments (
    department_id   INT AUTO_INCREMENT PRIMARY KEY,   -- unique numeric ID, auto-generated for each new row
    department_name VARCHAR(100) NOT NULL UNIQUE,     -- e.g. "Human Resources"; UNIQUE stops duplicate department names
    division        VARCHAR(100),                      -- optional grouping above department, e.g. "Operations"
    created_at      TIMESTAMP DEFAULT CURRENT_TIMESTAMP -- auto-filled with the exact time the row was inserted
);

-- ------------------------------------------------------------
-- 2. JOB_TITLES
-- The specific roles that exist within a department (one department has many job titles).
-- ------------------------------------------------------------
CREATE TABLE job_titles (
    job_title_id    INT AUTO_INCREMENT PRIMARY KEY,   -- unique ID for this job title
    title_name      VARCHAR(100) NOT NULL,             -- e.g. "HR Generalist"
    -- ENUM restricts this column to only these listed values -- protects against typos like "senoir"
    job_level       ENUM('Intern','Officer','Associate','Senior','Manager','Head','Director') NOT NULL,
    department_id   INT NOT NULL,                       -- which department this job title belongs to
    -- This line ties department_id back to departments.department_id.
    -- It guarantees you can never insert a job title pointing at a department that doesn't exist.
    CONSTRAINT fk_jobtitle_department
        FOREIGN KEY (department_id) REFERENCES departments(department_id)
        ON UPDATE CASCADE   -- if a department_id ever changes, update it here automatically
        ON DELETE RESTRICT  -- block deleting a department if job titles still reference it
);

-- ------------------------------------------------------------
-- 3. EMPLOYEES
-- The central table -- every person who has worked at the company.
-- ------------------------------------------------------------
CREATE TABLE employees (
    employee_id       INT AUTO_INCREMENT PRIMARY KEY,   -- internal unique ID used by all other tables to reference this person
    staff_number      VARCHAR(20) NOT NULL UNIQUE,       -- human-readable staff ID (e.g. printed on an ID badge)
    first_name        VARCHAR(60) NOT NULL,
    last_name         VARCHAR(60) NOT NULL,
    gender            ENUM('Male','Female','Other'),
    date_of_birth     DATE,
    hire_date         DATE NOT NULL,                     -- date employment started; used for tenure calculations
    employment_type   ENUM('Full-time','Part-time','Contract','Intern') DEFAULT 'Full-time',
    employment_status ENUM('Active','On Leave','Suspended','Terminated') DEFAULT 'Active',
    termination_date  DATE,                              -- NULL while the person is still employed
    termination_reason VARCHAR(255),
    department_id     INT NOT NULL,                      -- current department (links to departments table)
    job_title_id       INT NOT NULL,                     -- current role (links to job_titles table)
    manager_id         INT,                               -- self-referencing FK: points to another row in THIS same table
    base_salary        DECIMAL(12,2) NOT NULL,             -- fixed-point number, safer than FLOAT for money (no rounding drift)
    email               VARCHAR(120) UNIQUE,
    phone               VARCHAR(20),
    created_at          TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    -- Links department_id to the departments table.
    CONSTRAINT fk_employee_department
        FOREIGN KEY (department_id) REFERENCES departments(department_id),
    -- Links job_title_id to the job_titles table.
    CONSTRAINT fk_employee_jobtitle
        FOREIGN KEY (job_title_id) REFERENCES job_titles(job_title_id),
    -- Links manager_id to employee_id in this same table -- this is how an org chart is modeled.
    -- ON DELETE SET NULL means: if a manager's row is deleted, their direct reports just lose
    -- their manager reference instead of also being deleted.
    CONSTRAINT fk_employee_manager
        FOREIGN KEY (manager_id) REFERENCES employees(employee_id)
        ON DELETE SET NULL,
    -- A CHECK constraint enforces a business rule at the database level:
    -- you cannot mark someone "Terminated" without also giving a termination_date,
    -- and you cannot set a termination_date unless the status is "Terminated".
    CONSTRAINT chk_termination
        CHECK (
            (employment_status = 'Terminated' AND termination_date IS NOT NULL)
            OR (employment_status <> 'Terminated')
        )
);

-- Indexes speed up queries that filter/search by these columns.
-- Without them, MySQL has to scan every row to find matches.
CREATE INDEX idx_employees_department ON employees(department_id);  -- speeds up "employees in department X" queries
CREATE INDEX idx_employees_status ON employees(employment_status);  -- speeds up "all Active employees" queries

-- ------------------------------------------------------------
-- 4. EMPLOYMENT_HISTORY
-- One row per change event (promotion, transfer, salary change, etc.)
-- This is what lets you analyze career progression over time instead
-- of only seeing an employee's CURRENT department/title/salary.
-- ------------------------------------------------------------
CREATE TABLE employment_history (
    history_id        INT AUTO_INCREMENT PRIMARY KEY,
    employee_id        INT NOT NULL,                      -- whose record this change belongs to
    change_type         ENUM('Hire','Promotion','Transfer','Demotion','Salary Adjustment','Termination') NOT NULL,
    effective_date       DATE NOT NULL,                    -- when the change took effect
    old_department_id     INT,                             -- department before the change (NULL if not applicable)
    new_department_id      INT,                            -- department after the change
    old_job_title_id        INT,                           -- job title before the change
    new_job_title_id         INT,                          -- job title after the change
    old_salary                DECIMAL(12,2),                -- salary before the change
    new_salary                 DECIMAL(12,2),               -- salary after the change
    notes                       VARCHAR(255),                -- free-text context, e.g. "Approved by HR director"
    -- If an employee is ever deleted, delete their history rows too (CASCADE) -- keeps orphan rows from piling up.
    CONSTRAINT fk_history_employee
        FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_history_old_dept FOREIGN KEY (old_department_id) REFERENCES departments(department_id),
    CONSTRAINT fk_history_new_dept FOREIGN KEY (new_department_id) REFERENCES departments(department_id),
    CONSTRAINT fk_history_old_title FOREIGN KEY (old_job_title_id) REFERENCES job_titles(job_title_id),
    CONSTRAINT fk_history_new_title FOREIGN KEY (new_job_title_id) REFERENCES job_titles(job_title_id)
);

CREATE INDEX idx_history_employee ON employment_history(employee_id);  -- speeds up "show this employee's full history"

-- ------------------------------------------------------------
-- 5. ATTENDANCE
-- One row per employee per day.
-- ------------------------------------------------------------
CREATE TABLE attendance (
    attendance_id     BIGINT AUTO_INCREMENT PRIMARY KEY,   -- BIGINT because this table grows fast (365+ rows/employee/year)
    employee_id        INT NOT NULL,
    attendance_date     DATE NOT NULL,
    status               ENUM('Present','Absent','Leave','Remote','Public Holiday') NOT NULL,
    hours_worked          DECIMAL(4,2) DEFAULT 0,           -- e.g. 8.00 hours; DECIMAL(4,2) allows up to 99.99
    CONSTRAINT fk_attendance_employee
        FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
        ON DELETE CASCADE,
    -- UNIQUE constraint across two columns together: prevents inserting two attendance
    -- rows for the same employee on the same day (data-entry safeguard).
    CONSTRAINT uq_attendance_day UNIQUE (employee_id, attendance_date)
);

CREATE INDEX idx_attendance_date ON attendance(attendance_date);  -- speeds up "attendance for this date range" queries

-- ------------------------------------------------------------
-- 6. PERFORMANCE_REVIEWS
-- ------------------------------------------------------------
CREATE TABLE performance_reviews (
    review_id       INT AUTO_INCREMENT PRIMARY KEY,
    employee_id      INT NOT NULL,                        -- who is being reviewed
    reviewer_id       INT,                                 -- who conducted the review (also an employee)
    review_period      VARCHAR(20) NOT NULL,               -- e.g. '2026-H1' for first half of 2026
    review_date         DATE NOT NULL,
    -- CHECK constraint enforces the rating must be between 1.00 and 5.00 -- rejects bad data like a rating of 9.
    rating                DECIMAL(3,2) CHECK (rating BETWEEN 1.00 AND 5.00),
    comments               TEXT,                            -- TEXT allows long free-form write-ups, unlike VARCHAR
    CONSTRAINT fk_review_employee
        FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
        ON DELETE CASCADE,
    -- If the reviewer's own employee record is deleted, just null out reviewer_id
    -- rather than deleting the review itself -- the review is still historically valid.
    CONSTRAINT fk_review_reviewer
        FOREIGN KEY (reviewer_id) REFERENCES employees(employee_id)
        ON DELETE SET NULL
);

-- ------------------------------------------------------------
-- 7. PAYROLL
-- One row per employee per pay period, with Nigerian statutory
-- deductions broken into their own columns.
-- ------------------------------------------------------------
CREATE TABLE payroll (
    payroll_id         BIGINT AUTO_INCREMENT PRIMARY KEY,
    employee_id          INT NOT NULL,
    pay_period            CHAR(7) NOT NULL,                -- fixed-length string like '2026-07' (always exactly 7 characters)
    gross_salary            DECIMAL(12,2) NOT NULL,         -- salary before any deductions
    paye_tax                  DECIMAL(12,2) DEFAULT 0,      -- Pay-As-You-Earn income tax, per Nigeria Tax Act 2025 bands
    pension_employee            DECIMAL(12,2) DEFAULT 0,    -- 8% employee contribution withheld from salary (PENCOM)
    pension_employer             DECIMAL(12,2) DEFAULT 0,   -- 10% employer contribution, paid on top (not deducted from staff)
    nhf_deduction                  DECIMAL(12,2) DEFAULT 0, -- 2.5% National Housing Fund deduction
    nsitf_employer                  DECIMAL(12,2) DEFAULT 0,-- 1% employer-paid social insurance, not deducted from staff
    itf_employer                     DECIMAL(12,2) DEFAULT 0,-- 1% employer-paid Industrial Training Fund levy
    other_deductions                   DECIMAL(12,2) DEFAULT 0, -- e.g. loan repayments, union dues
    net_salary                           DECIMAL(12,2) NOT NULL, -- gross_salary minus all employee-side deductions
    payment_date                          DATE,             -- date salary was actually paid out
    CONSTRAINT fk_payroll_employee
        FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
        ON DELETE CASCADE,
    -- Prevents paying the same employee twice for the same month.
    CONSTRAINT uq_payroll_period UNIQUE (employee_id, pay_period)
);

CREATE INDEX idx_payroll_period ON payroll(pay_period);  -- speeds up "all payroll for July 2026" type queries

-- ------------------------------------------------------------
-- 8. EXIT_INTERVIEWS
-- At most one row per employee -- only exists if they left and did an exit interview.
-- ------------------------------------------------------------
CREATE TABLE exit_interviews (
    exit_id          INT AUTO_INCREMENT PRIMARY KEY,
    -- UNIQUE here (not just NOT NULL) enforces "at most one exit interview per employee".
    employee_id        INT NOT NULL UNIQUE,
    exit_date            DATE NOT NULL,
    reason_category        ENUM('Compensation','Career Growth','Management','Work-Life Balance',
                                 'Relocation','Health','Company Restructuring','Other') NOT NULL,
    reason_details           TEXT,
    would_recommend            BOOLEAN,                     -- TRUE/FALSE: would this person recommend the company
    exit_rating                  DECIMAL(3,2) CHECK (exit_rating BETWEEN 1.00 AND 5.00),
    CONSTRAINT fk_exit_employee
        FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
        ON DELETE CASCADE
);

-- ------------------------------------------------------------
-- 9. JOB_REQUISITIONS
-- A "we are hiring for this role" record. One requisition can
-- receive many applicants (see APPLICANTS below).
-- ------------------------------------------------------------
CREATE TABLE job_requisitions (
    requisition_id     INT AUTO_INCREMENT PRIMARY KEY,
    job_title_id        INT NOT NULL,                      -- what role is being hired for
    department_id       INT NOT NULL,                      -- which department is hiring
    date_opened          DATE NOT NULL,                     -- when the role was posted
    date_closed           DATE,                             -- NULL while still open
    status                 ENUM('Open','On Hold','Closed','Cancelled') DEFAULT 'Open',
    target_hires            INT NOT NULL DEFAULT 1,          -- how many people need to be hired for this requisition
    hiring_manager_id        INT,                            -- which employee owns this hiring decision
    CONSTRAINT fk_requisition_jobtitle
        FOREIGN KEY (job_title_id) REFERENCES job_titles(job_title_id),
    CONSTRAINT fk_requisition_department
        FOREIGN KEY (department_id) REFERENCES departments(department_id),
    CONSTRAINT fk_requisition_manager
        FOREIGN KEY (hiring_manager_id) REFERENCES employees(employee_id)
        ON DELETE SET NULL
);

CREATE INDEX idx_requisition_status ON job_requisitions(status);  -- speeds up "show all Open requisitions"

-- ------------------------------------------------------------
-- 10. APPLICANTS
-- One row per person who applied to a requisition. If hired,
-- employee_id gets filled in, linking them to their new employee record.
-- ------------------------------------------------------------
CREATE TABLE applicants (
    applicant_id       INT AUTO_INCREMENT PRIMARY KEY,
    requisition_id      INT NOT NULL,                       -- which open role this application is for
    full_name             VARCHAR(120) NOT NULL,
    email                  VARCHAR(120),
    phone                    VARCHAR(20),
    source                    ENUM('Referral','LinkedIn','Job Board','Agency','Career Site','Walk-in','Other') NOT NULL,
    application_date          DATE NOT NULL,                 -- when they applied
    current_stage               ENUM('Applied','Screening','Interview','Offer','Hired','Rejected','Withdrawn') DEFAULT 'Applied',
    rejection_reason              VARCHAR(255),               -- filled in only if current_stage = 'Rejected'
    offer_date                     DATE,                      -- filled in once an offer is extended
    hire_date                        DATE,                    -- filled in once they officially start
    employee_id                       INT,                    -- NULL until hired, then points to the employees table
    CONSTRAINT fk_applicant_requisition
        FOREIGN KEY (requisition_id) REFERENCES job_requisitions(requisition_id)
        ON DELETE CASCADE,
    CONSTRAINT fk_applicant_employee
        FOREIGN KEY (employee_id) REFERENCES employees(employee_id)
        ON DELETE SET NULL,
    -- Ensures one employee record can only be linked back to one applicant record (no duplicates).
    CONSTRAINT uq_applicant_employee UNIQUE (employee_id)
);

CREATE INDEX idx_applicant_source ON applicants(source);         -- speeds up "group applicants by source" queries
CREATE INDEX idx_applicant_stage ON applicants(current_stage);   -- speeds up "show all applicants at Interview stage"

-- ============================================================
-- ANALYTICS VIEWS
-- A VIEW is a saved query that behaves like a virtual table.
-- Instead of re-writing these JOINs every time, you just run
-- "SELECT * FROM v_headcount_by_department" and MySQL runs the
-- underlying query live. Great for connecting Power BI directly
-- to clean, pre-aggregated tables.
-- ============================================================

-- Current headcount by department and job level
CREATE OR REPLACE VIEW v_headcount_by_department AS
SELECT
    d.department_name,
    jt.job_level,
    COUNT(*) AS headcount                              -- counts how many employee rows fall into each group below
FROM employees e
JOIN departments d ON e.department_id = d.department_id   -- pulls in the readable department name
JOIN job_titles jt ON e.job_title_id = jt.job_title_id     -- pulls in the readable job level
WHERE e.employment_status = 'Active'                        -- only count people currently employed
GROUP BY d.department_name, jt.job_level;                    -- one row per department + job level combination

-- Monthly turnover / attrition rate
-- Restructured as a derived table (subquery "t") so the headcount subqueries
-- reference the already-grouped "period" column instead of the raw
-- termination_date -- this avoids MySQL's ONLY_FULL_GROUP_BY error, which
-- flags any ungrouped column referenced inside a correlated subquery.
CREATE OR REPLACE VIEW v_monthly_turnover AS
SELECT
    t.period,
    t.exits,
    -- Headcount snapshot: everyone hired on or before the end of that month
    (SELECT COUNT(*) FROM employees e2
       WHERE e2.hire_date <= LAST_DAY(STR_TO_DATE(CONCAT(t.period, '-01'), '%Y-%m-%d'))) AS headcount_snapshot,
    -- Turnover rate = exits that month / headcount that month, as a percentage
    ROUND(t.exits /
        (SELECT COUNT(*) FROM employees e2
           WHERE e2.hire_date <= LAST_DAY(STR_TO_DATE(CONCAT(t.period, '-01'), '%Y-%m-%d'))) * 100, 2) AS turnover_rate_pct
FROM (
    -- Inner query does the grouping first: one row per month, with exit count
    SELECT DATE_FORMAT(termination_date, '%Y-%m') AS period, COUNT(*) AS exits
    FROM employees
    WHERE employment_status = 'Terminated'
    GROUP BY DATE_FORMAT(termination_date, '%Y-%m')
) t
ORDER BY t.period;                                              -- sorted chronologically

-- Average tenure at exit, by exit reason
CREATE OR REPLACE VIEW v_attrition_by_reason AS
SELECT
    ei.reason_category,
    COUNT(*) AS exit_count,                                    -- how many exits fall under this reason
    -- DATEDIFF gives days between two dates; dividing by 365.25 converts days to years (accounts for leap years)
    ROUND(AVG(DATEDIFF(ei.exit_date, e.hire_date) / 365.25), 1) AS avg_tenure_years,
    ROUND(AVG(ei.exit_rating), 2) AS avg_exit_rating            -- average satisfaction rating given at exit
FROM exit_interviews ei
JOIN employees e ON ei.employee_id = e.employee_id              -- need hire_date from employees to compute tenure
GROUP BY ei.reason_category
ORDER BY exit_count DESC;                                        -- most common exit reasons appear first

-- Average time-to-hire (days) by department and job title
CREATE OR REPLACE VIEW v_time_to_hire AS
SELECT
    d.department_name,
    jt.title_name,
    COUNT(*) AS hires,                                          -- how many people were hired into this role
    -- Average number of days between application and start date
    ROUND(AVG(DATEDIFF(a.hire_date, a.application_date)), 1) AS avg_days_to_hire
FROM applicants a
JOIN job_requisitions jr ON a.requisition_id = jr.requisition_id  -- links applicant back to the role they applied for
JOIN departments d ON jr.department_id = d.department_id
JOIN job_titles jt ON jr.job_title_id = jt.job_title_id
WHERE a.current_stage = 'Hired'                                   -- only count applicants who were actually hired
GROUP BY d.department_name, jt.title_name;

-- Source-of-hire effectiveness: applications received vs. actual hires per channel
CREATE OR REPLACE VIEW v_source_of_hire AS
SELECT
    source,
    COUNT(*) AS total_applicants,                                -- total people who applied via this channel
    -- CASE WHEN acts like an if/else: returns 1 if hired, 0 otherwise, then SUM adds them all up
    SUM(CASE WHEN current_stage = 'Hired' THEN 1 ELSE 0 END) AS total_hired,
    -- Conversion rate: hires / total applicants from that source, as a percentage
    ROUND(SUM(CASE WHEN current_stage = 'Hired' THEN 1 ELSE 0 END) / COUNT(*) * 100, 2) AS hire_rate_pct
FROM applicants
GROUP BY source
ORDER BY total_hired DESC;                                         -- channels that produced the most hires appear first

-- Requisition fill rate and open pipeline health
CREATE OR REPLACE VIEW v_requisition_pipeline AS
SELECT
    jr.requisition_id,
    d.department_name,
    jt.title_name,
    jr.status,
    jr.target_hires,
    SUM(CASE WHEN a.current_stage = 'Hired' THEN 1 ELSE 0 END) AS hires_made,   -- how many of the target have been filled
    COUNT(a.applicant_id) AS total_applicants,                                  -- total pipeline size for this role
    -- Days the requisition has been open: if still open (date_closed IS NULL), compare to today's date instead
    DATEDIFF(COALESCE(jr.date_closed, CURDATE()), jr.date_opened) AS days_open
FROM job_requisitions jr
JOIN departments d ON jr.department_id = d.department_id
JOIN job_titles jt ON jr.job_title_id = jt.job_title_id
LEFT JOIN applicants a ON a.requisition_id = jr.requisition_id      -- LEFT JOIN so requisitions with zero applicants still show up
GROUP BY jr.requisition_id, d.department_name, jt.title_name, jr.status, jr.target_hires, jr.date_closed, jr.date_opened;

-- Payroll cost summary by department and period (for statutory compliance reporting)
CREATE OR REPLACE VIEW v_payroll_cost_by_department AS
SELECT
    d.department_name,
    p.pay_period,
    SUM(p.gross_salary) AS total_gross,                                     -- total payroll cost before deductions
    SUM(p.paye_tax) AS total_paye,                                          -- total income tax remitted
    SUM(p.pension_employee + p.pension_employer) AS total_pension,          -- combined employee + employer pension contributions
    SUM(p.nhf_deduction) AS total_nhf,                                      -- total National Housing Fund deductions
    SUM(p.nsitf_employer + p.itf_employer) AS total_employer_levies,        -- total employer-only statutory levies
    SUM(p.net_salary) AS total_net                                          -- total actually paid out to staff
FROM payroll p
JOIN employees e ON p.employee_id = e.employee_id
JOIN departments d ON e.department_id = d.department_id
GROUP BY d.department_name, p.pay_period
ORDER BY p.pay_period, d.department_name;
