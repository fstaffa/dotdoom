---
name: ask
description: Answer a question from the knowledge base with citations to the source notes. Use for questions about people, projects, decisions, or things the user has written down.
---

# Ask the KB

Read-only. Never modify files.

1. Find candidates: grep (case-insensitive, with synonyms) over `*.org` in the root and `archive/`;
   match filenames first (`ls | grep`), since names carry title and keywords. Skip `export/`.
2. Read the relevant notes fully, including linked ones (`[[denote:ID]]` → `ls *<ID>*`).
3. For open-task questions use `kb query` instead of grepping.
4. Answer concisely. Cite every claim as `[[denote:ID]]` with the note title. Mention dates of the notes
   when information may be stale. If notes conflict, say so.
5. If the KB has no answer, say that plainly; do not fill in from general knowledge unless asked, and label it
   if you do.
