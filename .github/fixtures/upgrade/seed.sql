-- Comprehensive upgrade-test fixture.
-- Seeds a wide variety of object types with deterministic, committed data so
-- that .github/fixtures/upgrade/verify.sql can assert nothing was lost or
-- invalidated by an in-place Oracle DB upgrade.
--
-- Run as a dedicated schema, e.g.:
--   sql -name local-26ai-upgrade_test @.github/fixtures/upgrade/seed.sql
--
-- Notes:
--   * SQLcl + heredocs hang; this is a file run via @ on purpose.
--   * ROWS is a reserved word in Oracle SQL -- never alias a column ROWS.

set define off
whenever sqlerror exit failure

prompt Seeding upgrade-test schema

-- ---------------------------------------------------------------------------
-- Object types (schema-level) + nested table type
-- ---------------------------------------------------------------------------
create type t_phone as object (
  phone_type varchar2(10),
  phone_num  varchar2(30)
);
/

create type t_phone_list as table of t_phone;
/

create type t_emp_obj as object (
  emp_id   number,
  emp_name varchar2(100),
  salary   number
);
/

create type t_emp_tab as table of t_emp_obj;
/

-- ---------------------------------------------------------------------------
-- Tables: PK, FK, check constraint, identity, CLOB, nested table storage
-- ---------------------------------------------------------------------------
create table departments (
  dept_id   number generated always as identity primary key,
  dept_name varchar2(100 char) not null,
  budget    number check (budget >= 0),
  phones    t_phone_list
) nested table phones store as dept_phones;

create table employees (
  emp_id   number generated always as identity primary key,
  emp_name varchar2(100 char) not null,
  dept_id  number not null references departments (dept_id),
  salary   number check (salary > 0),
  bio      clob,
  hired_on date default sysdate
);

create table audit_log (
  log_id    number generated always as identity primary key,
  tab_name  varchar2(30),
  action    varchar2(10),
  logged_at timestamp default systimestamp
);

-- ---------------------------------------------------------------------------
-- Indexes: single + composite
-- ---------------------------------------------------------------------------
create index idx_emp_dept     on employees (dept_id);
create index idx_emp_name_sal on employees (emp_name, salary);

-- ---------------------------------------------------------------------------
-- Sequence
-- ---------------------------------------------------------------------------
create sequence seq_ticket start with 1 increment by 1;

-- ---------------------------------------------------------------------------
-- Trigger: audit inserts into employees
-- ---------------------------------------------------------------------------
create or replace trigger trg_emp_audit
after insert on employees
for each row
begin
  insert into audit_log (tab_name, action) values ('EMPLOYEES', 'INSERT');
end;
/

-- ---------------------------------------------------------------------------
-- Package: function, procedure, pipelined function, record/table types
-- ---------------------------------------------------------------------------
create or replace package pkg_hr as
  type r_emp_rec is record (
    emp_id   employees.emp_id%type,
    emp_name employees.emp_name%type
  );
  type t_emp_recs is table of r_emp_rec;

  function total_salary (p_dept_id in number) return number;
  procedure raise_salary (p_emp_id in number, p_pct in number);
  function emp_pipe (p_dept_id in number) return t_emp_tab pipelined;
end pkg_hr;
/

create or replace package body pkg_hr as
  function total_salary (p_dept_id in number) return number is
    l_total number;
  begin
    select nvl(sum(salary), 0) into l_total
      from employees
     where dept_id = p_dept_id;
    return l_total;
  end total_salary;

  procedure raise_salary (p_emp_id in number, p_pct in number) is
  begin
    update employees
       set salary = salary * (1 + p_pct / 100)
     where emp_id = p_emp_id;
  end raise_salary;

  function emp_pipe (p_dept_id in number) return t_emp_tab pipelined is
  begin
    for r in (select emp_id, emp_name, salary
                from employees
               where dept_id = p_dept_id) loop
      pipe row (t_emp_obj(r.emp_id, r.emp_name, r.salary));
    end loop;
    return;
  end emp_pipe;
end pkg_hr;
/

-- ---------------------------------------------------------------------------
-- Standalone function
-- ---------------------------------------------------------------------------
create or replace function fn_emp_count return number is
  l_cnt number;
begin
  select count(*) into l_cnt from employees;
  return l_cnt;
end fn_emp_count;
/

-- ---------------------------------------------------------------------------
-- View (join across tables)
-- ---------------------------------------------------------------------------
create or replace view v_emp_dept as
  select e.emp_id, e.emp_name, e.salary, d.dept_name
    from employees e
    join departments d on e.dept_id = d.dept_id;

-- ---------------------------------------------------------------------------
-- Data
-- ---------------------------------------------------------------------------
insert into departments (dept_name, budget, phones)
values ('Engineering', 1000000,
        t_phone_list(t_phone('WORK', '555-0100'), t_phone('FAX', '555-0101')));

insert into departments (dept_name, budget, phones)
values ('Sales', 500000,
        t_phone_list(t_phone('WORK', '555-0200')));

insert into employees (emp_name, dept_id, salary, bio)
values ('Alice', (select dept_id from departments where dept_name = 'Engineering'),
        9000, 'Senior engineer, owns the build pipeline.');

insert into employees (emp_name, dept_id, salary, bio)
values ('Bob', (select dept_id from departments where dept_name = 'Engineering'),
        7000, 'Backend developer.');

insert into employees (emp_name, dept_id, salary, bio)
values ('Carol', (select dept_id from departments where dept_name = 'Sales'),
        5000, 'Account executive.');

insert into employees (emp_name, dept_id, salary, bio)
values ('Dave', (select dept_id from departments where dept_name = 'Sales'),
        4000, 'Sales development rep.');

commit;

-- ---------------------------------------------------------------------------
-- Materialized view: built immediately, refreshed on demand
-- ---------------------------------------------------------------------------
create materialized view mv_dept_salary
  build immediate
  refresh on demand
as
  select dept_id,
         sum(salary) as total_sal,
         count(*)    as emp_count
    from employees
   group by dept_id;

-- ---------------------------------------------------------------------------
-- Advanced-compressed table + index: a compressed segment is a distinct
-- on-disk storage format, so this asserts that compression survives an
-- in-place Oracle DB upgrade intact (verify.sql re-reads the attributes).
-- ---------------------------------------------------------------------------
create table compressed_events (
  id   number generated always as identity primary key,
  grp  varchar2(20) not null,
  note varchar2(200)
) row store compress advanced;

create index idx_comp_events on compressed_events (grp, id) compress advanced low;

insert into compressed_events (grp, note)
  select 'g' || mod(level, 5), rpad('x', 200, 'x')
    from dual connect by level <= 500;
commit;

prompt Upgrade-test schema seeded

exit
