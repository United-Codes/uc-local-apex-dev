---
name: test-db-upgrade
description: Check if the database and ORDS can be upgraded successfully without breaking existing data, and produce a migration guide afterward.
---

When a new Oracle Database or ORDS version is released, it is crucial to ensure that the upgrade process does not lead to data loss or corruption. This skill covers the full upgrade workflow: testing the database upgrade, upgrading ORDS, and writing a migration guide for users.

## Start DB

- Check docker is running: `docker ps`
- Start the database container if it is not already running: `./local-26ai.sh start`

## Test user

- If it does not exist yet, create a new test user: `./local-26ai.sh create-user upgrade_test`
- The command saves a named SQLcl connection automatically. Connect with: `sql -name local-26ai-upgrade_test`
- If sample objects are not yet present, create them using a SQL script file and run it with `sql -name local-26ai-upgrade_test @path/to/script.sql`
  - **Do not use heredocs (`<< 'EOF'`) with SQLcl** — they cause the shell to hang waiting for input. Always write SQL to a `.sql` file first, then pass it via `@`.
  - `ROWS` is a reserved word in Oracle SQL — use `row_count` or another alias in `SELECT ... AS` clauses.
- The test schema should be extensive and cover all major object types to simulate real-world usage:
  - **Tables**: multiple related tables with primary keys, foreign keys, check constraints, identity columns, CLOB columns
  - **Indexes**: single and composite, on various columns
  - **Sequences**: standalone sequences
  - **Data**: realistic INSERT statements across all tables, committed with `COMMIT`
  - **Views**: regular views, including joins across multiple tables
  - **Packages**: package spec + body with functions, procedures, pipelined functions, and record/table types
  - **Triggers**: DML triggers (e.g. audit triggers that write to a log table)
  - **Standalone functions**
  - **Object types**: `CREATE OR REPLACE TYPE ... AS OBJECT` and nested table types
  - **Materialized views**: `BUILD IMMEDIATE REFRESH ON DEMAND`
- Verify all objects are created successfully by querying `user_objects` and checking row counts

## Pull new DB version

```
docker pull container-registry.oracle.com/database/free:23.26.1.0
```

## Update docker-compose.yml

- Update the `image:` tag for the `26ai` service in `docker-compose.yml` to the new version.

## Launch DB upgrade

- Stop the containers: `./local-26ai.sh stop`
- Start with the new image: `./local-26ai.sh start`
- The Oracle Database container upgrades automatically on first start with a new image version.
- Check logs for errors: `docker logs local-26ai 2>&1 | grep -E "upgrade|error|ORA-|version" -i`
- Reconnect via SQLcl: `sql -name local-26ai-upgrade_test`

## Verify data integrity post-upgrade

Write a verification SQL script and run it with `sql -name local-26ai-upgrade_test @path/to/verify.sql`. The script should check:

1. **DB version** — `SELECT version_full FROM v$instance`
2. **Object validity** — query `user_objects` grouping by `object_type`, count total and `INVALID` objects; expect 0 invalids
3. **Row counts** — `SELECT ... UNION ALL` across all tables to confirm data is intact
4. **Views** — query each view and confirm expected rows are returned
5. **Package functions** — call each function and confirm return values
6. **Triggers** — fire a DML statement and verify the audit log table received the entry
7. **Sequences** — `SELECT seq_name.NEXTVAL FROM dual`
8. **Materialized views** — query the MV and confirm data

## Upgrade ORDS

If ORDS is also being upgraded alongside the DB:

- Pull the new ORDS image: `docker pull container-registry.oracle.com/database/ords:26.1.0`
- Update the `image:` tag for the `ords-26ai` service in `docker-compose.yml`
- Restart: `./local-26ai.sh stop && ./local-26ai.sh start`
- The ORDS container detects the version mismatch and runs the upgrade automatically. Look for this in the logs:
  ```
  INFO : The Oracle REST Data Services version X.X.X is installed on your database and will be upgraded to Y.Y.Y version.
  INFO : The Oracle REST Data Services Y.Y.Y has been installed correctly on your database.
  INFO : Starting the Oracle REST Data Services instance.
  ```
- Confirm ORDS is serving traffic by checking: `docker logs local-26ai-ords 2>&1 | grep "listening"`
- Open a browser and navigate to `http://localhost:8181/ords/apex` to confirm the APEX sign-in page loads

## Write migration guide

After a successful upgrade, create a new migration guide in `docs/src/content/docs/migrations/`. Use the existing guides (e.g. `25-3.md`) as a template. The guide should include:

- **Frontmatter**: `title`, `description`, `sidebar.order` (increment from the previous guide)
- **Intro**: link to getting-started, note to be on the previous version first
- **Changes section**: a human-readable changelog covering:
  - DB and ORDS version bumps (note whether DB files are compatible or a dump/restore is needed)
  - New scripts
  - Enhanced scripts (what changed and why)
  - Bug fixes
  - Use `git log --oneline <last-tag>..HEAD --no-merges` and `git show <hash> --stat` to gather the full list of commits and changed files since the last release tag
- **Migration section**: step-by-step instructions (backup → stop → switch branch → chmod → start → verify)
  - If DB files are compatible (minor version bump), the steps are simple: backup, pull branch, start
  - If DB files are incompatible (major version change like 23ai → 26ai), include dump/restore steps
- End with an optional step to remove old docker images
