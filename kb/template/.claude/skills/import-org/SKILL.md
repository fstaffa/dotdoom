---
name: import-org
description: Selectively import legacy org and roam notes from archive/legacy (or a given path) into the Denote KB. Proposes keep/merge/drop per file. Copies, never moves.
---

# Import legacy notes

Source: the path given by the user, default `legacy/org` and `legacy/roam` (the old `org/` and `roam/`,
left in place until the trial ends).

1. Inventory: list files with size and first heading. Work in batches of about 10.
2. For each file propose **keep** (new note via `kb new <type>`, content copied in), **merge** (into a
   named existing note), or **drop** (obsolete, empty, duplicate). Give one-line reasons.
   - Per-person files become `person` notes; project files become `project` notes.
   - Roam `:ID:` links `[[id:...]]` become `[[denote:ID]]` of the new note; keep a mapping of old to new.
   - Open tasks keep their state, SCHEDULED and DEADLINE.
3. Wait for approval of each batch. Then apply with `kb new` plus Edit for the body; never hand-build
   filenames or IDs.
4. Afterwards fix links using the mapping, then `kb sync-todo-tags`, `kb validate --strict`, commit.
5. Never delete or move the source files. Record progress (done / pending files) in `import-progress.org`
   so the next session can resume.
