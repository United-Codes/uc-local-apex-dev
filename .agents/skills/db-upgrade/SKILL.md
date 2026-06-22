---
name: db-upgrade
description: A new Oracle Database version is released. It should work with the existing datafiles without requiring a dump/restore, verify and then prepare the migration guide for users.
---

## New Oracle Database version released

Use `gh run list --workflow=test-db-upgrade.yml` to check if a recent successful run of the `test-db-upgrade.yml` workflow exists. If not, ask the user if they want to trigger a new run with the new database version. First verify that such a version exists on the repo.

## Upgrade DB locally

Follow the actual migration guides of similar upgrades (e.g. 26-2) to upgrade the database locally. This will involve:

- Pulling new database image
- Backup the existing database
- Stopping the current database
- Starting the new database

Do it in a safe way and confirm that everything is working correctly before proceeding to the next step.

## Write migration guide

After a successful upgrade, create a new migration guide in `docs/src/content/docs/migrations/`. Use the existing guides (e.g. `25-3.md`) as a template. The guide should include:

- **Frontmatter**: `title`, `description`, `sidebar.order` (increment from the previous guide)
- **Intro**: link to getting-started, note to be on the previous version first
- **Changes section**: a human-readable changelog covering:
  - DB and ORDS version bumps (note whether DB files are compatible or a dump/restore is needed)
  - New scripts
  - Enhanced scripts (what changed and why)
  - Bug fixes
  - Use `git log --oneline <last-tag>..HEAD --no-merges` and `git show <hash> --stat` to gather the full list of commits and changed files since the last release tag (even though they where committed on the old tags branches, they are still relevant for the new version if they were committed after the last release)
- **Migration section**: step-by-step instructions (backup → stop → switch branch → chmod → start → verify)
  - If DB files are compatible (minor version bump), the steps are simple: backup, pull branch, start
  - If DB files are incompatible (major version change like 23ai → 26ai), include dump/restore steps
- End with an optional step to remove old docker images
