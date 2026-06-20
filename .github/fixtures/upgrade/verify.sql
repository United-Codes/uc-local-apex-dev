-- Read-only integrity checks for the upgrade-test schema seeded by seed.sql.
-- Emits one `key=value` line per assertion so the workflow can grep -qx each.
-- Produces identical output before and after an in-place DB upgrade, so it can
-- be run as a pre-upgrade baseline and re-run post-upgrade.
--
-- Run as the seeded schema, e.g.:
--   sql -name local-26ai-upgrade_test @.github/fixtures/upgrade/verify.sql
--
-- This script mutates nothing (no inserts, no sequence NEXTVAL, no trigger
-- fires) so it is safe to run repeatedly.

set define off
set heading off feedback off pagesize 0 verify off trimspool on
whenever sqlerror exit failure

-- DB version (informational; the workflow asserts the expected tag post-upgrade).
-- Wrapped in a dual select so exactly one `version_full=` line is always emitted,
-- even if the scalar subquery matches no row -- otherwise the workflow's
-- `grep '^version_full='` finds nothing and aborts under `set -e`.
select 'version_full=' ||
       (select version_full
          from product_component_version
         where product like 'Oracle Database%'
           and rownum = 1)
  from dual;

-- No object may be left INVALID by the upgrade
select 'invalid=' || count(*)
  from user_objects
 where status = 'INVALID';

-- Row counts per table
select 'departments=' || count(*) from departments;
select 'employees='   || count(*) from employees;
select 'audit_log='   || count(*) from audit_log;

-- View (join) returns all employees
select 'view_rows=' || count(*) from v_emp_dept;

-- Standalone function
select 'fn_emp_count=' || fn_emp_count from dual;

-- Package function
select 'eng_total=' ||
       pkg_hr.total_salary((select dept_id from departments where dept_name = 'Engineering'))
  from dual;

-- Pipelined package function used in SQL
select 'eng_pipe=' || count(*)
  from table(pkg_hr.emp_pipe((select dept_id from departments where dept_name = 'Engineering')));

-- Materialized view retains its rows
select 'mv_rows=' || count(*) from mv_dept_salary;

exit
