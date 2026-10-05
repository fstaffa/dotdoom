---
name: triage
description: Process the KB inbox. Promote each capture into a proper note (title, tags) or merge it into an existing note. Use when the user says triage, process inbox, or file my captures.
---

# Triage the inbox

1. List captures with `ls *__inbox*` (files tagged `inbox`). If empty, say so and stop.
2. Read every capture. For each, decide one of:
   - **Promote**: standalone topic. `kb rename <file> --title "<title>" --add-tags <kw,...> --remove-tags inbox`
     Use keywords from the vocabulary in CLAUDE.md only.
   - **Merge**: belongs in an existing note (search with grep for the person/project). Append the text under a
     suitable heading in that note with Edit, move any task with `kb refile`, then delete the capture.
   - **Task only**: `kb refile` the task into the owning note, or into `tasks.org` if none fits.
   - **Drop**: junk. Delete only if it is clearly empty or a duplicate.
3. Show the user the proposed decisions as a table (capture, decision, target) and wait for approval
   before applying anything if any decision is a Merge or Drop. Pure promotions may be applied directly.
4. Apply, then `kb sync-todo-tags`, `kb validate --strict`, and commit with a message listing what was filed.
5. Report what was done and anything left in the inbox.
