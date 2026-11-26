set serveroutput on size unlimited
set feedback off
set verify off

-- @dblinter ignore(Core G-5040): when others is fine here, a failed table is skipped
-- @dblinter ignore(Core G-5010): this is a SQLcl script, dbms_output is its output

-- A delete does not lower the high-water mark of a table. A table that once held
-- many rows keeps the whole segment, even when only a few rows are left. Neither
-- dbms_space.shrink_tablespace nor a datafile resize can return that space.
-- This script finds such tables and rebuilds them.
--
-- Call it with a define for the mode (see shrink-space.sh):
--   list : gather the statistics of the large tables and list the candidates
--   run  : rebuild the candidates
--
-- A table is a candidate when all of this is true:
--   - the owner is not an Oracle-maintained user (APEX schemas stay as they are)
--   - the table is a heap table that is not partitioned, with a segment of 50 MB or more
--   - the live rows need less than half of the segment
--   - every index is a normal or bitmap index (no domain or vector index)
--
-- "alter table ... move online" compacts the table and keeps it open for DML.
-- The indexes are rebuilt online afterwards, because the move does not shrink them.
declare
  c_mode      constant varchar2(10 char) := '&MODE';
  c_min_bytes constant number       := 50 * 1024 * 1024;
  c_max_ratio constant number       := 0.5;

  l_found   pls_integer := 0;
  l_moved   pls_integer := 0;
  l_before  number;
  l_after   number;
  l_total   number := 0;
  l_sql     varchar2(1000 char);

  cursor l_big_cur is
    select t.owner, t.table_name
      from dba_tables t
      join dba_segments s
        on s.owner = t.owner
       and s.segment_name = t.table_name
       and s.segment_type = 'TABLE'
      join dba_users u
        on u.username = t.owner
       and u.oracle_maintained = 'N'
     where t.partitioned = 'NO'
       and t.iot_type is null
       and t.temporary = 'N'
       and s.bytes >= c_min_bytes;

  cursor l_candidates_cur is
    select t.owner, t.table_name, s.bytes seg_bytes,
           t.num_rows * t.avg_row_len / (1 - nvl(t.pct_free, 10) / 100) live_bytes
      from dba_tables t
      join dba_segments s
        on s.owner = t.owner
       and s.segment_name = t.table_name
       and s.segment_type = 'TABLE'
      join dba_users u
        on u.username = t.owner
       and u.oracle_maintained = 'N'
     where t.partitioned = 'NO'
       and t.iot_type is null
       and t.temporary = 'N'
       and t.num_rows is not null
       and s.bytes >= c_min_bytes
       and t.num_rows * t.avg_row_len / (1 - nvl(t.pct_free, 10) / 100) < s.bytes * c_max_ratio
       and not exists (
             select 1
               from dba_indexes i
              where i.table_owner = t.owner
                and i.table_name = t.table_name
                and i.index_type not in ('NORMAL', 'FUNCTION-BASED NORMAL', 'BITMAP',
                                         'FUNCTION-BASED BITMAP', 'NORMAL/REV', 'LOB'))
     order by s.bytes desc;

  function seg_bytes(p_owner in varchar2, p_table in varchar2) return number is
    l_bytes number;
  begin
    select nvl(sum(bytes), 0) into l_bytes
      from dba_segments
     where owner = p_owner
       and segment_name = p_table
       and segment_type = 'TABLE';
    return l_bytes;
  end seg_bytes;
begin
  if c_mode = 'list' then
    -- Statistics decide the list, so refresh them for the large tables first.
    <<stats_loop>>
    for r in l_big_cur loop
      begin
        sys.dbms_stats.gather_table_stats(r.owner, r.table_name);
      exception when others then
        null;
      end;
    end loop stats_loop;
  end if;

  <<table_loop>>
  for r in l_candidates_cur loop
    l_found := l_found + 1;

    if c_mode = 'list' then
      sys.dbms_output.put_line('###' || rpad(r.owner || '.' || r.table_name, 50) ||
        lpad(round(r.seg_bytes / 1048576), 7) || ' MB segment, about ' ||
        round(r.live_bytes / 1048576) || ' MB of data');
    else
      l_before := seg_bytes(r.owner, r.table_name);
      begin
        l_sql := 'alter table ' || sys.dbms_assert.enquote_name(r.owner) || '.' ||
          sys.dbms_assert.enquote_name(r.table_name) || ' move online';
        execute immediate l_sql;

        -- The move does not shrink the indexes, so rebuild each one.
        <<index_loop>>
        for i in (select owner, index_name
                    from dba_indexes
                   where table_owner = r.owner
                     and table_name = r.table_name
                     and index_type <> 'LOB'
                     and partitioned = 'NO') loop
          begin
            l_sql := 'alter index ' || sys.dbms_assert.enquote_name(i.owner) || '.' ||
              sys.dbms_assert.enquote_name(i.index_name) || ' rebuild online';
            execute immediate l_sql;
          exception when others then
            sys.dbms_output.put_line('  skip index ' || i.owner || '.' || i.index_name ||
              ': ' || sqlerrm || ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
          end;
        end loop index_loop;

        sys.dbms_stats.gather_table_stats(r.owner, r.table_name);

        l_after := seg_bytes(r.owner, r.table_name);
        l_total := l_total + (l_before - l_after);
        l_moved := l_moved + 1;
        sys.dbms_output.put_line('rebuilt ' || r.owner || '.' || r.table_name || ': ' ||
          round(l_before / 1048576) || ' MB -> ' || round(l_after / 1048576) || ' MB');
      exception when others then
        sys.dbms_output.put_line('skip ' || r.owner || '.' || r.table_name || ': ' || sqlerrm ||
          ' - Backtrace: ' || sys.dbms_utility.format_error_backtrace);
      end;
    end if;
  end loop table_loop;

  if c_mode = 'run' then
    sys.dbms_output.put_line(l_moved || ' of ' || l_found || ' tables rebuilt, ' ||
      round(l_total / 1048576) || ' MB of table segments freed');
  end if;
end;
/
