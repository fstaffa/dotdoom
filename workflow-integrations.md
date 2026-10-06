# Unified Workflow Research: Gmail, GitLab, Confluence, Jira, Slack, Miro in Emacs

> Research completed 2026-07-04 via deep-research workflow (106 agents, 24 sources, 25 claims adversarially verified).

## Goals

1. Centralize all notifications and events in one place
2. Link org-roam knowledge base with web-based tools (Confluence, Miro)

Existing setup: org-roam, org-agenda, Magit+Forge, lab.el, gptel, aidermacs.

---

## Part 1: Emacs-Native Integrations

### Gmail → mu4e ✅ high confidence

- **Package**: `mu` / `mu4e` (v1.14.2, June 15 2026 — actively maintained)
- **How**: mu4e is a full Emacs email client but requires an external IMAP sync tool. Use **mbsync** (isync) to pull Gmail to local Maildir, then mu indexes it.
- **Gotcha**: Gmail is deprecating App Passwords; mbsync requires OAuth2 support for long-term use.
- **Benefit**: Email lands in org-mode–friendly buffers; can capture emails as org-agenda tasks.

### GitLab → lab.el ✅ high confidence (already configured)

Already in the setup — but underused features:

- `lab-watch-pipeline` / `lab-watch-mr` send desktop notifications via the `alert` package
- `#+BEGIN: lab-merge-requests` dynamic block embeds live MR listings in any org file
- `C-c ; n/r/t/u/a` keybindings for full in-Emacs code reviews

**Quick win**: Enable `alert` integration and add a `lab-merge-requests` block to the org-agenda file.

### Jira → org-jira ✅ high confidence

- **Package**: `org-jira` ([ahungry/org-jira](https://github.com/ahungry/org-jira), last release June 2026)
- **How**: Syncs Jira issues as first-class org headings with `:PROPERTIES:` drawers (assignee, reporter, type, priority, status, ID). Issues become searchable/linkable in org-agenda and org-roam.
- **Alternative**: `ejira` ([nyyManni/ejira](https://github.com/nyyManni/ejira)) — bidirectional Jira↔org sync with full markup conversion (Jira markup ↔ org markup). Less mature but more complete two-way sync.

### Slack → emacs-slack ⚠️ medium confidence

- **Package**: `yuya373/emacs-slack` ([GitHub](https://github.com/yuya373/emacs-slack), last commit June 26 2026 — maintained)
- **Caveat**: Claims of "full client" and org-agenda integration extension were **refuted** in adversarial verification. It works for basic channel/DM reading and notifications via `alert`, but should not be relied on as a complete Slack replacement inside Emacs.
- **Realistic use**: Supplementary notification surface. Real Slack work stays in the browser/app.

---

## Part 2: Confluence Sync Options

### Option A: sync-docs.el — Org → Confluence (one-way) ✅

- [laertida/sync-docs.el](https://github.com/laertida/sync-docs.el)
- Publishes org buffers to Confluence Cloud via REST API (v2 API, email + API token)
- Stores Confluence page ID and version in org `:PROPERTIES:` for incremental updates
- **Limitation**: Confluence Cloud only; one-way (org → Confluence)
- Low popularity (9 stars) but confirmed working

### Option B: mark CLI — Markdown → Confluence (one-way) ✅ high confidence

- [kovetskiy/mark](https://github.com/kovetskiy/mark) v16.5.0 (June 29 2026, 110 releases, 1.5k stars)
- CLI tool: reads Markdown → pushes to Confluence via REST API, create-or-update
- Org workflow: export org → Markdown via `ox-md`, then invoke `mark` via shell
- Integrates with CI/CD pipelines for automated doc publishing
- **Best for**: publishing finished org notes to Confluence without manual copy-paste

### Option C: ConfluenceImportExport — Bidirectional via MCP ✅ high confidence ⭐

- [YuriyEnshin/ConfluenceImportExport](https://github.com/YuriyEnshin/ConfluenceImportExport) v2.18.0 (July 2 2026)
- Acts as **both CLI and MCP server**: exposes 6 sync operations (download update/merge, upload update/create/merge, compare)
- True **two-way sync** between Confluence (Server/DC/Cloud) and local filesystem
- Since Claude Code is in the workflow, this MCP server can be invoked directly from Claude Code sessions, enabling AI-assisted org↔Confluence workflows
- Credentials passed via env vars, never enter LLM context

---

## Part 3: Miro

**No viable Emacs integration exists.** Miro has no Emacs package and no n8n trigger node for real-time events.

Options:
1. **Browser-only** — accept Miro stays in the browser (pragmatic default)
2. **Miro webhooks → n8n** — Miro can send webhooks on board events; n8n can route these to ntfy for desktop alerts or org-capture
3. **Embed links in org-roam** — store Miro board URLs as org links in relevant notes; no sync, but navigation is fast

---

## Part 4: Unified Notification Aggregation

### n8n — Best open-source option ✅ high confidence ⭐

Self-hostable automation hub. Verified capabilities:

- **Gmail Trigger**: polls new messages, filter by label/sender/search syntax, up to 50/cycle
- **GitLab Trigger**: 12 event types (push, MR, pipeline, issue, deployment, wiki, release, comments, etc.)
- **Jira**: likely has trigger/webhook support (verify independently)
- **Slack**: native node
- **Sink**: route all events to ntfy.sh for desktop alerts, or to an HTTP endpoint that triggers org-capture

### ntfy.sh — Lightweight notification sink ✅ high confidence

- [binwiederhier/ntfy](https://github.com/binwiederhier/ntfy) — self-hostable, open-source HTTP pub-sub
- No account, no fees for public instance (ntfy.sh)
- Rate limits: 60-request burst, ~1 req/10s sustained
- GitLab webhooks → POST to ntfy topic → Emacs receives via `ntfy.el` or SSE polling
- **Minimal setup path**: skip n8n entirely; configure GitLab/Jira webhooks directly to ntfy

### Zapier — Simpler but paid

- Supports Gmail↔GitLab automation (starred email → GitLab issue, etc.)
- Less control than n8n; relevant if you want managed, no-maintenance option

---

## Part 5: Non-Emacs Alternatives

### Linear — Worth considering as Jira replacement ✅ high confidence

- **Linear Asks**: create issues from Slack messages, bidirectional thread sync, SLA tracking, triage queue
- Auto-creates Slack channel per project, adds members, posts updates
- GitLab integration: bidirectional MR↔issue sync
- **Tradeoff**: No Emacs-native client. Adopting Linear means losing org-jira–style deep integration unless you build a custom bridge.
- [linear.app/integrations](https://linear.app/integrations)

### Notion — Weak fit

- Has Jira AI Connector and Slack integration but no GitLab or Miro native integration
- Designed as a notes/wiki tool, not a notification hub

### Atlassian-native integrations

- Jira natively integrates with Confluence (76% of customers), Slack, Gmail, and GitLab (via "Git Integration for Jira" marketplace app)
- Sufficient for browser-based work; Emacs integration is the gap

---

## Recommended Rollout

### Tier 1 — High value, low friction

1. **lab.el alert integration** — enable `alert` for pipeline/MR notifications from existing lab.el setup. Zero new packages.
2. **org-jira** — pull Jira issues into org-agenda. Straightforward install, high payoff.
3. **ntfy.sh + GitLab webhooks** — configure GitLab to POST pipeline/MR events to ntfy; subscribe in Emacs. Near-real-time CI notifications with minimal setup.

### Tier 2 — Medium effort, high value

4. **mu4e + mbsync** — Gmail in Emacs. Setup effort is real (mbsync OAuth2 config), but payoff is email-as-org-tasks workflow.
5. **mark CLI** — publish finished org notes to Confluence. Invoke via `shell-command` or a small org-babel block.

### Tier 3 — Evaluate carefully

6. **emacs-slack** — test hands-on before committing. Useful for notifications; unreliable as full client.
7. **ConfluenceImportExport MCP** — most powerful Confluence sync option, especially given Claude Code usage. Investigate invoking from gptel tool-use or a custom elisp wrapper.
8. **n8n** — invest in this if you want a unified event pipeline across all services. Self-host on a home server or small VPS; route everything to ntfy or an org-capture HTTP endpoint.

### Miro

Accept browser-only. Store board links as org-roam properties. If events matter, wire Miro webhooks → n8n → ntfy.

---

## Open Questions

1. Does n8n have a Jira Trigger node? (The "no-trigger" claim was refuted in verification — confirm before building workflows)
2. Can ConfluenceImportExport MCP be invoked from gptel tool-use in Doom Emacs?
3. Current state of mbsync OAuth2 for Gmail — Google App Password deprecation timeline?

---

## Sources

| Tool | Link | Confidence |
|---|---|---|
| org-jira | https://github.com/ahungry/org-jira | High |
| lab.el | https://github.com/isamert/lab.el | High |
| emacs-slack | https://github.com/yuya373/emacs-slack | Medium |
| mu/mu4e | https://github.com/djcb/mu | High |
| ejira | https://github.com/nyyManni/ejira | Medium |
| sync-docs.el | https://github.com/laertida/sync-docs.el | High |
| mark CLI | https://github.com/kovetskiy/mark | High |
| ConfluenceImportExport | https://github.com/YuriyEnshin/ConfluenceImportExport | High |
| ntfy | https://github.com/binwiederhier/ntfy | High |
| n8n GitLab Trigger | https://docs.n8n.io/integrations/builtin/trigger-nodes/n8n-nodes-base.gitlabtrigger/ | High |
| n8n Gmail Trigger | https://docs.n8n.io/integrations/builtin/trigger-nodes/n8n-nodes-base.gmailtrigger/ | High |
| n8n Jira node | https://docs.n8n.io/integrations/builtin/app-nodes/n8n-nodes-base.jira/ | High |
| Linear integrations | https://linear.app/integrations | High |
