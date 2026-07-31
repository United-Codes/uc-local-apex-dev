# CLAUDE.md

## Documentation style

The documentation follows ASD-STE100 Simplified Technical English. Read
`.agents/skills/simple-english/SKILL.md` before you write or change text in these
places:

- `docs/src/content/docs/**`
- `readme.md` and `docs/README.md`
- The migration guides in `docs/src/content/docs/migrations/`

Use pragmatic mode. Domain words stay (`tablespace`, `datafile`, `workspace`,
`reverse proxy`). Run the checks in
`.agents/skills/simple-english/references/checklist.md` before you deliver.

### The main rules

- Instructions are imperative, one instruction per sentence, 20 words maximum.
- Explanations and notes use simple tenses, 25 words maximum.
- Put the condition before the command: "If the build fails, read the log."
- Approved modals: `can`, `will`, `must`. Do not use `should`, `may`, `might`,
  `could`, or `would`.
- Do not use contractions. Write "does not", not "doesn't".
- Warnings name the command first and the risk second.
- Do not use `e.g.`, `i.e.`, or `etc.` Write "for example", "that is", or name
  the items.
- Do not use a semicolon. Write two sentences.

### One word per concept

Use these terms only. Do not rotate synonyms.

| Concept | Term to use |
| --- | --- |
| Assert that a condition is true | make sure that |
| Show information on screen | show |
| Start a command | run |
| Configuration data in prose | configuration, configuration file |
| Delete a database object | drop |
| Delete a file or a directory | delete |
| A failed operation | failure (an error message is an error) |

The folder name `ords-config` and the APEX label "Workspace settings" are product
names. Keep them exact.

### Exceptions

- Never change code blocks, inline code, commands, flags, file paths, quoted
  error messages, port numbers, or version numbers.
- The hero tagline and the `<Card>` blurbs in `docs/src/content/docs/index.mdx`
  are marketing text. The rules do not apply there.
- The frontmatter `title` and `description` of every page are SEO text. The rules
  do not apply there.
- Do not rename a heading that another page links to with an anchor. The docs
  build runs `starlight-links-validator` and fails on a broken anchor. Search for
  the anchor first: `grep -rn "#the-heading-slug" docs/src readme.md`.

## Verify a documentation change

```bash
cd docs && bun install && bun run build
```
