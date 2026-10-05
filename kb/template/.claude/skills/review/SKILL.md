---
name: review
description: Periodic KB health review. Finds stale tasks, duplicate notes, missing links, sync-conflict files and validation problems. Reports only; changes nothing without approval.
---

# Review the KB

1. `kb validate --strict`: report every problem.
2. `find . -name '*sync-conflict*' -not -path './.stversions/*'`: list conflicts with the original they belong to.
   Show a diff; never resolve automatically.
3. Stale tasks: `kb query --state TODO,NEXT,WAITING --before <today - 14 days>` and `kb query --undated`
   for NEXT/WAITING items. For each group suggest: schedule, mark DONE, drop, or ask.
4. Duplicates: look for notes with near-identical titles or overlapping keywords (person/reference).
   Propose merges, do not perform them.
5. Links: for `person` and `project` notes, find notes that mention their name or title without a
   `[[denote:ID]]` link, and suggest the link.
6. Inbox age: count captures tagged `inbox` older than 3 days.
7. Output a short report sorted by importance. Apply only what the user approves, through `kb`, then
   `kb sync-todo-tags`, `kb validate --strict`, commit.
