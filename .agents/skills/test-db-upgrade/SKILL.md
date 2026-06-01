---
name: test-db-upgrade
description: Check if the database and ORDS can be upgraded successfully without breaking existing data, and produce a migration guide afterward.
---

When a new Oracle Database or ORDS version is released, it is crucial to ensure that the upgrade process does not lead to data loss or corruption. This skill covers the full upgrade workflow: testing the database upgrade, upgrading ORDS, and writing a migration guide for users.

## Automated check (CI)

The DB datafile-integrity part of this skill is also available as a manually-triggered GitHub Actions workflow: `.github/workflows/test-db-upgrade.yml`. Run it from the **Actions** tab (`workflow_dispatch`) with the new DB tag (e.g. `23.26.2.0`); it installs the currently-pinned version, seeds the shared fixtures below, upgrades in place on the same `oradata` volume, and asserts integrity. Use it as the fast pass/fail gate. The ORDS upgrade and migration-guide steps below remain manual.

## Start DB

- Check docker is running: `docker ps`
- Start the database container if it is not already running: `./local-26ai.sh start`

## Test user

- If it does not exist yet, create a new test user: `./local-26ai.sh create-user upgrade_test`
- The command saves a named SQLcl connection automatically. Connect with: `sql -name local-26ai-upgrade_test`
- Seed the comprehensive shared fixture (the same one the CI workflow uses):
  `sql -name local-26ai-upgrade_test @.github/fixtures/upgrade/seed.sql`
  - **Do not use heredocs (`<< 'EOF'`) with SQLcl** — they cause the shell to hang waiting for input. Always run SQL from a `.sql` file via `@`.
  - `ROWS` is a reserved word in Oracle SQL — use `row_count` or another alias in `SELECT ... AS` clauses.
- The fixture in [.github/fixtures/upgrade/seed.sql](../../../.github/fixtures/upgrade/seed.sql) deliberately covers all major object types (related tables with PK/FK/check/identity/CLOB and a nested-table column, single + composite indexes, a sequence, a joined view, a package with function/procedure/pipelined function/record+table types, a DML audit trigger, a standalone function, schema-level object + nested-table types, and a `BUILD IMMEDIATE REFRESH ON DEMAND` materialized view) with deterministic committed data. Extend it there (not in an ad-hoc script) so CI and manual runs stay in sync.
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

Run the shared verification script and confirm the output:
`sql -name local-26ai-upgrade_test @.github/fixtures/upgrade/verify.sql`

[.github/fixtures/upgrade/verify.sql](../../../.github/fixtures/upgrade/verify.sql) is **read-only** (safe to run repeatedly) and emits `key=value` lines covering:

1. **DB version** — `version_full` from `product_component_version` (accessible to any schema, unlike `v$instance`)
2. **Object validity** — `INVALID` object count from `user_objects`; expect `invalid=0`
3. **Row counts** — counts per table confirm data is intact
4. **Views** — the joined view returns the expected rows
5. **Package functions** — calls `total_salary` and the pipelined `emp_pipe`
6. **Materialized views** — the MV still holds its rows

Triggers and sequences are write operations, so the CI workflow checks them in a separate post-upgrade step (fire one `INSERT`, confirm the audit log grows by 1, then `seq_ticket.NEXTVAL`). Do the same manually if running by hand.

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
