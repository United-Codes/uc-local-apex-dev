---
name: db-ru-dictionary-check
description: A new Oracle Free release update (23.26.x) is out and we want to adopt it for an existing oradata volume. Find out what the RU added to the data dictionary, teach scripts/repair-ru-dictionary.sh about it, and prove on a throwaway host that the image swap plus repair is safe before shipping a migration guide.
---

# Can we adopt this release update?

Run this **before** the `db-upgrade` skill. That skill produces the release and
the migration guide. This one answers whether the release is adoptable at all.

## The thing you are testing

Changing the image tag on an existing `oradata` volume is **not an upgrade**.
The Oracle Free entrypoint relinks a few config files and opens the existing
database with the new binaries. There is no upgrade code in it.

The datafiles are forward compatible, so the data survives. What does not come
along is everything the skipped RU added to the data dictionary, plus the
in-database JVM. Nothing warns you: no alert-log error, no startup warning, a
container that reports itself healthy.

Oracle states plainly that this is not a supported path:

> "The Oracle AI Database 26ai Free release is not supported for patching with RUs."
> — [Oracle docs](https://docs.oracle.com/en/database/oracle/oracle-database/26/upgrd/oracle-database-changes-deprecations-desupports.html)

So the honest framing in anything user-facing is: fine for a local dev
database, never for anything treated as production. The supported path is a
fresh volume plus Data Pump. Keep that caveat in the migration guide.

## Step 1 — Confirm the image tag exists

Do not guess tags. List them from the registry (anonymous pull token):

```sh
TOKEN=$(curl -s 'https://container-registry.oracle.com/auth?service=Oracle%20Registry&scope=repository:database/free:pull' \
  | python3 -c 'import sys,json; d=json.load(sys.stdin); print(d.get("access_token") or d.get("token",""))')

curl -s -H "Authorization: Bearer $TOKEN" \
  https://container-registry.oracle.com/v2/database/free/tags/list \
  | python3 -c 'import sys,json; [print(t) for t in sorted(json.load(sys.stdin)["tags"])]'
```

Note the key is `access_token`, not `token`.

## Step 2 — Find what the new RU added to the dictionary

Read Oracle's ["Changes in This Release for Oracle Database Reference"](https://docs.oracle.com/en/database/oracle/oracle-database/26/refrn/changes-this-release-oracle-database-reference.html).
It has a section per RU listing **new static data dictionary views** and new
dynamic performance views.

Collect the new `DBA_*` / `ALL_*` / `USER_*` view names for the RU being
adopted. These are the probes — you do not need every view, but you need at
least one per feature the RU added, or that feature's gap goes undetected.

## Step 3 — Teach the script about them

In `scripts/repair-ru-dictionary.sh`, add a block next to the existing ones
(around lines 198-224) and append it to the combined list:

```sh
NEW_VIEWS_23_26_4="
DBA_SOMETHING ALL_SOMETHING USER_SOMETHING
"

ALL_PROBE_VIEWS="$NEW_VIEWS_23_26_1 $NEW_VIEWS_23_26_2 $NEW_VIEWS_23_26_3 $NEW_VIEWS_23_26_4"
```

Only the names go here. The script resolves each missing view back to the
catalog script that creates it, so no script paths are ever hardcoded.

## Step 4 — Prove it on a throwaway host

**Do not run this on the user's machine.** It creates and destroys containers
and volumes, needs about 25 GB free for two images, and runs two Oracle
instances at once.

```sh
scripts/test-ru-dictionary-repair.sh <OLD_RU> <NEW_RU>
# e.g. scripts/test-ru-dictionary-repair.sh 23.26.2.0 23.26.3.0
```

Test the jump users will actually make (from the currently pinned tag in
`docker-compose.yml`), and ideally the widest supported jump too.

The harness seeds real objects and data, swaps the image on the same volume,
then asserts `--check` detects the gap, `--repair` closes it, and the data
fingerprint is unchanged end to end. It also starts a **fresh** NEW_RU database
as a control — that is what makes a finding attributable to the swap rather
than to the image.

**Pass looks like:** `RESULT: DATA FINGERPRINT UNCHANGED`, plus `--summary`
reporting `missing_repairable=0`, `jvm_ok=yes`, `javavm_registry=VALID`,
`non_valid_components=0`.

Before starting, confirm both images use the same `ORACLE_HOME`:

```sh
docker run --rm --entrypoint bash container-registry.oracle.com/database/free:<TAG> \
  -c 'ls -d /opt/oracle/product/*/dbhomeFree'
```

If the path differs between the two tags, the relinked config files break and
the whole approach needs rethinking. Stop and report that.

## Step 5 — Run the full CI gate

```sh
gh workflow run test-db-upgrade.yml -f db_image=<NEW_RU>
gh run watch
```

This is the realistic run: it installs the current version with APEX and ORDS,
seeds the fixture schema, swaps, repairs, and re-asserts everything including
the APEX snapshot. Failures worth reading closely are `sys_invalid_objects`
growing versus the baseline, and any diff in `apex-*.out`.

## Step 6 — Decide

**Adoptable** when: the swap test passes, the CI gate is green, and the repair
ends with `missing_repairable=0` and `jvm_ok=yes` while leaving data and APEX
byte-identical. Then hand over to the `db-upgrade` skill, and make sure the new
migration guide includes the dictionary repair step.

**Not adoptable** when: the datafiles do not open, `ORACLE_HOME` moved, the
control (fresh NEW_RU) database is itself unclean, or the repair cannot close
the gap. Then the migration guide needs a Data Pump export/import instead of an
in-place swap.

## Traps that cost real time — do not rediscover these

**Diagnosis**

- **Oracle's "Changes in This Release" page is incomplete.** Its 23.26.3 section
  lists nine static views; the home actually defines ten. It omitted
  `DBA_HIST_DATA_MEMORY_AREA`, which then went missing on every swap undetected.
  Do not use that page as the source of truth. Diff the view definitions of the
  two image homes instead — no database needed, about a minute per tag:

  ```sh
  docker run --rm --entrypoint bash container-registry.oracle.com/database/free:<TAG> -c '
    H=$(ls -d /opt/oracle/product/*/dbhomeFree); cd $H/rdbms/admin
    ls *.sql | grep -vE "^(e|f)[0-9]+\.sql$" | xargs $H/perl/bin/perl -0777 -ne \
      "while(/CREATE\s+(?:OR\s+REPLACE\s+)?(?:FORCE\s+)?VIEW\s+(?:SYS\.)?\"?([A-Za-z][A-Za-z0-9_]*)\"?/gi){print uc(\$1),\"\n\"}" \
    | sort -u' > views-<TAG>.txt
  ```

  Then `LC_ALL=C comm -13 views-<OLD>.txt views-<NEW>.txt`. Use the doc page only
  to understand what a view is for.
- **Check every candidate probe against the control database before you add it.**
  The home defining a view does not mean a Free install ever creates it. The
  23.26.3 diff also reports `ALL/DBA/USER_CATALOG_PROVIDERS`, and adding them
  looks correct — but a fresh 23.26.3 database has neither those views nor the
  `C##ADP$SERVICE` user that owns them, because Free does not install Data
  Studio. They are false positives that no repair can ever close:
  `dbms_catalog_install.sql` fails with `ORA-00942`, and its real driver
  `data_studio_install.sql` would install the whole stack Free leaves out. If the
  control does not have the view, it does not belong in the probe list.
- `DBA_REGISTRY` lies. It reports `JAVAVM VALID` while every Java call raises
  `ORA-29548`. Only `select dbms_java.longname('TEST') from dual` is a real
  test.
- `datapatch` destroys the evidence. It rewrites `DBA_REGISTRY_HISTORY` to the
  new RU while applying nothing, erasing the only record of which RU built the
  volume. **Read that value before running anything.**
- `datapatch` and `catctl.pl catupgrd.sql` both refuse: the first matches on the
  RU patch ID (identical across 23.26.x), the second compares only `23.0.0.0.0`.
  Neither is broken. Do not spend time on them.
- A fresh install legitimately has a few invalid `SYS` objects. Assert "no worse
  than baseline", never `= 0`.

**Repair internals** (only relevant if the script needs changing)

- **Not every base table comes from an apply script.** AWR is the exception that
  broke 23.26.3. `catawr*vw.sql` only creates views; the `WRH$_*` tables they
  select from come from `catawrtb.sql`, a normal catalog script. Run the view
  script alone and it fails with `ORA-00942`, Oracle still creates the
  `DBA_HIST_*` synonym over the view that does not exist, and the synonym then
  resolves to itself — `ORA-01775` on every query, and `--check` reports the view
  as missing forever. Run `catawrtv.sql` instead: it is Oracle's own driver and
  runs `catawrtb` first, then every AWR view layer in order. When a new RU adds
  views whose script has a `SQL_CALLING_FILE` header, prefer that driver.
- **A multi-RU jump needs more than one pass.** All the RUs' scripts land in one
  catcon pass in whatever order the view map produced, so a view script can run
  before the apply script that creates its base table. The widest jump,
  23.26.0 → 23.26.3, left `ALL/DBA/USER_REQUIRED_PARENT_DATA_PRIVILEGES` missing
  after pass 1 and created them in an identical pass 2. Repeat while the missing
  count keeps falling. Give each pass its own catcon log basename, or the
  previous pass's `ORA-` errors get re-reported as new.
- **Revalidate components one per session.** The validation procedures recompile
  their own packages, so a second call in the same session runs against state the
  first one just invalidated and dies with `ORA-04061`. `VALIDATE_APEX` catches
  that internally, reports `ORA-20001: ORA-04061 ...` and then sets the APEX
  registry flag to `INVALID` — so JAVAVM is revalidated first and APEX always
  loses. This only shows on an install that has APEX, which means the local
  harness cannot catch it and only the CI gate can: `non_valid_components` went
  0 → 1 while all 4492 APEX objects stayed VALID. Also trust `dba_registry` over
  the procedure's return value, because `VALIDATE_APEX` reports success anyway.
- `set -e` plus a `grep` inside a command substitution is a silent killer:
  `x="$(... | grep ...)"` aborts the whole script when grep matches nothing.
  Every such assignment needs `|| true`. This is the same class of bug as the
  `pipefail` / SIGPIPE trap below, and it bit twice in one session.

- An `*_apply.sql` never names the views it enables — only the matching
  `*_rollback.sql` does. Resolve apply scripts through the rollback sibling.
- After an apply script changes a base table's shape, reload the matching
  `prvt*.plb` package bodies, or `SYS.XS_*` bodies stay invalid with `ORA-00947`.
- Never call `dbms_registry_sys.validate_components`. It marks every component
  INVALID then revalidates, which leaves **APEX INVALID** on a real install.
  Revalidate only already-INVALID components, via `dba_registry.procedure`.
- `procedure` is a PL/SQL reserved word: `c.procedure` raises `ORA-06550`
  although the column selects fine in SQL. Alias it.
- The JVM needs `javavm/install/update_javavm_db.sql`; `initjvm.sql` refuses
  with `ORA-29539`.
- In the script itself, `set -o pipefail` plus an early-exiting `awk` or `head`
  gives SIGPIPE (exit 141) and kills the run silently. Read whole streams.

**After a repair on a real database**

- Diff the invalid-object list before and after. Package bodies that call a SQL
  macro can fail the mass recompile with `ORA-62565` / `PLS-00201` while the
  macro function is valid. `utl_recomp.recomp_serial()` does **not** fix them
  (verified) — only a direct `alter package "OWNER"."NAME" compile body;` does.

## Files this skill touches

- `scripts/repair-ru-dictionary.sh` — the probe list and the repair
- `scripts/test-ru-dictionary-repair.sh` — the swap regression test
- `.github/workflows/test-db-upgrade.yml` — the full CI gate
- `.github/fixtures/upgrade/verify-dictionary.sql` — the `key=value` checks
- `docs/src/content/docs/migrations/` — where the result gets written up
