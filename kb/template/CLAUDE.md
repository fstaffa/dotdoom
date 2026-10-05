# Personal knowledge base: conventions for AI

This folder is a Denote-style org-mode knowledge base (work, personal, learning, projects). It is synced by
Syncthing to Mac, Linux and iPhone. Git lives on the Linux machine only. Commit after every run.

## Layout
- Flat: notes live in the root, classified by filename keywords, not folders.
- `tasks.org`: plain file, tasks with no other home.
- `<ID>__inbox.org`: one capture per file, in the root like every note; tag `inbox` = unprocessed.
- `<ID>--<slug>__<kw>_<kw>.org`: Denote files. ID = `YYYYMMDDTHHMMSS`.
- `archive/`: done projects, old dailies, `archive/legacy/` = the old `org/` and `roam/`.
- `export/agenda.org`: generated read-only phone view. Never edit, never read as a source.
- Keywords: person, project, reference, daily, inbox, todo, work, personal.
- `todo` keyword = note has an open TODO/NEXT/WAITING heading. It is maintained by the tool, never by hand.
- A task lives in exactly one file. Links are `[[denote:ID]]`; never use file paths in links.
- Task states: `TODO NEXT WAITING | DONE`.

## Rules
1. Never rename, move, retag, or change task state by hand. Use the `kb` tool (path below). It validates
   before writing and refuses edits that add validation errors.
2. Body text of a note may be edited directly (Edit tool). Do not touch the front matter (`#+title`,
   `#+date`, `#+filetags`, `#+identifier`); use `kb rename` for that.
3. After a batch of edits run `kb sync-todo-tags`, then `kb validate --strict`. Fix what it reports
   (`kb validate --fix` for mechanical problems). Then `git add -A && git commit`.
4. Never delete a note without saying so. Merging a capture into another note and deleting the capture is
   allowed in `/triage` only; git keeps the original.
5. Never create files by hand with made-up IDs: use `kb new`.
6. Do not read or modify `.stfolder`, `.stversions`, `*.sync-conflict-*` except in `/review`, which only
   reports conflicts.
7. Work notes may contain confidential Cimpress data. Do not paste note contents into external services.

## The kb tool
Run as `~/.doom.d/kb/kb <command>` (KB root = `$KB_ROOT`, default `~/data/org-mode/`).

    kb validate [--strict] [--fix]
    kb sync-todo-tags [--dry-run]
    kb new person|project|reference TITLE [--tags a,b] [--body TEXT]
    kb new daily [YYYY-MM-DD] | kb new inbox [--body TEXT]
    kb rename FILE [--title T] [--tags a,b] [--add-tags a,b] [--remove-tags a,b] [--dir DIR]
    kb refile SRC-FILE HEADING DEST-FILE [DEST-HEADING]
    kb query [--state S,S] [--tag T] [--before YYYY-MM-DD] [--undated]
    kb state FILE HEADING TODO|NEXT|WAITING|DONE|none
    kb schedule FILE HEADING YYYY-MM-DD|none
    kb deadline FILE HEADING YYYY-MM-DD|none
    kb agenda-export [--print]

## Style
- Titles: short, lower-case slugs come from the tool; keep titles human readable.
- One topic per note. Prefer linking to an existing person/project note over duplicating facts.
- Dates ISO (`2026-10-05`). People are `person` notes, linked with `[[denote:ID]]`.

## Skills
`/triage` process the inbox. `/review` stale tasks, duplicates, conflicts, link suggestions.
`/ask` answer a question from the notes with citations. `/import-org` selectively import legacy notes.
