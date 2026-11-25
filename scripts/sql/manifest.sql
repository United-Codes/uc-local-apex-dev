-- One line per object: OWNER|OBJECT_TYPE|OBJECT_NAME.
-- backup-all writes it (export-gaps), and import-all runs it again after the
-- import and compares the two. A line that is missing is an object that did not
-- come back. Names, not counts: a missing object and an extra object of the same
-- type do not cancel out.
-- Generated objects (system names for indexes, LOBs, constraints) and the
-- DataPump master tables are left out.
set heading off feedback off verify off pagesize 0 linesize 600 trimspool on termout on echo off
select o.owner || '|' || o.object_type || '|' || o.object_name
  from dba_objects o
 where o.owner in (select username from dba_users
                    where oracle_maintained = 'N'
                      and username not in ('ORDS_METADATA','ORDS_PUBLIC_USER','PDBADMIN','UTPLSQL')
                      and username not like 'APEX\_%' escape '\'
                      and username not like 'C##%')
   and o.generated = 'N'
   and o.object_name not like 'ESQL\_%' escape '\'
   and o.object_name not like 'ISQL\_%' escape '\'
   and o.object_name not like 'AQ$\_%' escape '\'
   and o.object_name not like 'SYS\_%' escape '\'
   and o.object_name not like 'BIN$%'
   -- tables of a vector index: their names hold object ids that change on import
   and o.object_name not like 'VECTOR$%'
   and o.object_type not in ('LOB','LOB PARTITION','TABLE PARTITION','INDEX PARTITION')
union all
-- The SQL domain of each column. A wrong link is a defect that the object list
-- does not show (see the domain bug in export_gaps.sql).
select c.owner || '|DOMAIN LINK|' || c.table_name || '.' || c.column_name || '=' || c.domain_owner || '.' || c.domain_name
  from dba_tab_cols c
 where c.owner in (select username from dba_users
                    where oracle_maintained = 'N'
                      and username not in ('ORDS_METADATA','ORDS_PUBLIC_USER','PDBADMIN','UTPLSQL')
                      and username not like 'APEX\_%' escape '\'
                      and username not like 'C##%')
   and c.domain_name is not null
   and c.table_name not like 'BIN$%'
 order by 1;
exit
