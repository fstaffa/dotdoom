# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## IMPORTANT: Required Instructions

These instructions MUST be followed for every interaction:

1. **Always run `doom sync`** after modifying `init.el`, `packages.el`, or installing/uninstalling packages
2. **Update this CLAUDE.md file** after making any significant changes to the configuration:
   - New packages added or removed
   - New custom functions or keybindings
   - Changes to module configurations
   - New integrations or tools configured
   - Modified settings that affect workflow
3. **Test configuration changes** by restarting Emacs or running `doom/reload` after `doom sync`
4. **Preserve existing customizations** - Never remove personal functions or settings without explicit permission
5. **Follow Doom Emacs conventions**:
   - Use `after!` for package configuration
   - Use `use-package!` for new package setup
   - Keep personal config in `config.el`, not in `init.el`
   - Declare packages in `packages.el`, not in `config.el`

## Overview

This is a personal Doom Emacs configuration repository. Doom Emacs is a configuration framework for Emacs that focuses on ergonomics, mnemonics and consistency.

## Key Commands

### Configuration Management
- `doom sync` - Must run after modifying init.el, packages.el, or installing/uninstalling packages
- `doom upgrade` - Upgrade Doom and its packages
- `doom doctor` - Diagnose common issues with your environment and Doom config
- `doom env` - Regenerate your envvars file

### Development Workflow
- After editing configuration files:
  1. Save the file
  2. Run `doom sync` in terminal
  3. Restart Emacs or run `doom/reload` (`SPC h r r` in Doom)

## Architecture

### File Structure
- **init.el** - Declares which Doom modules to enable and their load order. Modules are organized by categories (input, completion, ui, editor, emacs, term, checkers, tools, os, lang, email, app, config)
- **agent.el** - agent-shell session management: full-window layout with restore, session list (control plane), notifications, modeline, next-waiting jump, worktree workflow, `SPC l` keys; loaded from `config.el` (basic agent-shell setup stays in `config.el`). Replaced `claude.el`/claude-code.el
- **kb-denote.el** - Denote knowledge-base setup (agenda files, todo-tag sync, archive/inbox helpers, `SPC n d` keys); loaded from `config.el`
- **kb/** - KB command-line tool and template (see below)
- **.claude/**, **.mcp.json** - Claude Code project settings/MCP config for this repo
- **workflow-integrations.md** - Research notes on Gmail/GitLab/Jira/Slack integrations in Emacs (may mention outdated setup such as org-roam, gptel, aidermacs)
- **config.el** - Personal configuration and customizations. Loaded after Doom's modules
- **packages.el** - Declares additional packages to install via straight.el, or packages to disable

### Key Configuration Patterns

#### Module Configuration
Modules in init.el use flags for configuration:
- `(module-name +flag1 +flag2)` - Enable module with specific features
- Flags modify module behavior (e.g., `+lsp` adds LSP support, `+tree-sitter` adds tree-sitter support)

#### Package Management
In packages.el:
- `(package! name)` - Install a package
- `(package! name :recipe (...))` - Install from specific source
- `(unpin! package)` - Allow package to update beyond pinned version
- `(disable-package! name)` - Disable a built-in package

#### Configuration Hooks
In config.el:
- `(after! package ...)` - Configure after package loads
- `(use-package! package ...)` - Configure and potentially lazy-load packages
- `(add-hook 'hook-name 'function)` - Add functions to hooks

### Active Integrations

#### Development Tools
- **LSP Mode** - Enabled for multiple languages (C#, Go, JavaScript, Nix, Python, etc.)
- **Magit + Forge** - Git integration with GitHub/GitLab support
- **majutsu** - Jujutsu VCS integration for Emacs (declared in `packages.el`)
- **Projectile** - Project management, searches in `~/data/cimpress/` and `~/data/personal/`
- **Corfu** - Primary completion system (`corfu +orderless`), with `nerd-icons-corfu` for icons. Company is disabled. `corfu-popupinfo` shows doc panel to the right on selection.
- **Tree-sitter** - Enhanced syntax highlighting for supported languages

#### Org Mode & Productivity
- **Denote** - Note-taking/knowledge base (replaced org-roam), flat files in `~/data/org-mode/` (`personal/kb-root`), which is also `org-directory`. Config in `kb-denote.el`, with `denote-journal`, `denote-org` and `consult-denote`. Keybindings under `SPC n d` (find, grep, link, backlinks, new, rename, archive, daily, inbox). `SPC n d D` opens the calendar (`personal/kb-daily-via-calendar`), where `N`/`F` create/find a daily. Evil shadows plain minor-mode keys, so such bindings need `evil-define-minor-mode-key`
- **Org-agenda** - Task management; agenda files are `tasks.org` plus notes with the `todo` keyword (not `archive`) in the KB root (`personal/kb-agenda-files`). The `todo` filetag is kept in sync on save (`personal/kb-sync-todo-tag`). Marking a task DONE in any KB note appends it to today's daily (created if missing) under `* Done` with a `[[denote:ID]]` link to the source note (`personal/kb-log-done-to-daily`, on `org-after-todo-state-change-hook`); an identical line already under `* Done` is not added again. `kb state FILE HEADING DONE` does the same logging from the CLI (`kb--log-done-to-daily` in `kb/kb.el`), since batch Emacs doesn't run the hook
- **Org-super-agenda** - Enhanced agenda view with custom grouping
- Custom capture templates for tasks, people, and notes

#### External Services
- **Kubernetes** - K8s management via kubernetes.el
- **Docker** - Docker integration with LSP support
- **Prodigy** - Process manager for AWS profiles and database connections
- **Terminal** - ghostel (libghostty; Doom `:term ghostel` module, which also provides `evil-ghostel` and `SPC o t` popup / `SPC o T` here; native module dir and progress setup in `config.el`, native module in `~/.local/share/ghostel/`). claude-code.el is no longer used
- **agent-shell** - ACP client and the only Claude interface (`agent-shell`, `acp`, `shell-maker` in `packages.el`; basic config in `config.el`, session management in `agent.el`). Needs the `claude-agent-acp` binary on PATH (provided by the Nix config, `home-manager/shared/emacs`); uses subscription login. `agent-shell-elicitation--experimental-feature-enabled` is set to t so AskUserQuestion works (upstream default is off, which hides the tool from the model). In evil insert state, TAB/S-TAB move between question options only while a question is pending (`personal/agent-shell-tab-filter`), otherwise TAB inserts spaces as usual; `RET` selects. In insert state `C-v` pastes via `agent-shell-yank-dwim` (clipboard image becomes file context; `gp` does the same in normal state). `agent-shell-session-strategy` is `new`; resume uses `prompt`. `agent-shell-session-restore-verbosity` is `full` so a resumed session replays the whole conversation (default `minimal` shows only the title). A shell is shown full window (`agent-shell-display-action` = `personal/agent--display`): the workspace's window layout is saved per workspace name and restored by `personal/agent-leave`. Files opened from a shell leave it first (`agent-shell-file-display-action`). Shells join the current workspace and an event subscription (`personal/agent--setup-buffer`) drives notifications, modeline and list refresh. Status per shell: blocked (permission/question) / busy / done (finished, unseen) / idle
- **GitLab** - Integration via lab.el; `gitlab.org` in org-directory is auto-generated by `personal/gitlab-refresh` with todos, MRs, and assigned issues; shown as "GitLab" section in org-super-agenda

### Knowledge Base tool (`kb/`)
- `kb/kb` - batch-Emacs CLI (`kb.el`) for the Denote-style KB in `~/data/org-mode/` (`validate`, `new`, `rename`, `query`, `install-template`, ...). Tests: `kb/test.sh`
- `kb/template/` - source of truth for the `CLAUDE.md` and `.claude/skills/` deployed to the KB root. Claude only reads those from the KB directory, so the template is not used in place.
- **If anything in `kb/template/` is changed, ask the user for confirmation, then run `~/.doom.d/kb/kb install-template`** (copies the files to `$KB_ROOT`, default `~/data/org-mode/`, overwriting). Do not run it without confirmation.

### Custom Functions & Keybindings

#### Key Chord Bindings (in insert mode)
- `fd` - Return to normal mode
- `fs` - Save buffer

#### Leader Key Bindings
- `,` - Local leader key
- `SPC w s` - Switch to buffer in other window
- `SPC o p` - Open Prodigy
- `SPC o g` - Refresh GitLab todos/MRs/issues into gitlab.org
- `SPC n d c` - `personal/kb-capture` (kb-denote.el): org-capture menu; `w`/`p` = work/personal task into `tasks.org` (heading tag). In the capture buffer: `C-c i` inserts a `[[denote:ID][Title]]` link to any KB note (`personal/kb-insert-link`), `C-c C-c` saves, `C-c C-w` refiles to a project/person note, `C-c C-s`/`C-c C-d` schedule/deadline
- `SPC o t` / `SPC o T` - Ghostel terminal: popup at project root / open here (Doom `:term ghostel` defaults)
- `SPC f p` / `SPC f P` (Doom private config) switch to (or create) a dedicated `doom` workspace first (`personal/switch-to-doom-workspace`)
- `SPC l l` (also `SPC l t`) - `personal/agent-toggle`: from a shell restore the project layout; otherwise show the project's most recent shell full window, or start one (from the default workspace it first switches to a workspace named after the project)
- `SPC l c` (also `g R` in normal state) - Agent: clear, like `/clear` in Claude Code: `agent-shell-restart` kills the current shell and starts a fresh session in the same project, buffer name and window (asks only if the agent is busy)
- `SPC l A` - Agent: new session without context (`personal/agent-start-bare` binds `agent-shell-context-sources` to nil; `SPC l a` inserts file/region/error/line context into the prompt)
- `SPC l a` / `SPC l r` / `SPC l s` - Agent: new session / resume (pick a past session via `prompt` strategy) / switch to any session
- `SPC l b` - `personal/agent-list`: control plane listing all shells (project or `repo:branch`, status, title, directory); RET goes to its workspace and shows it, x kill, gr refresh, q quit. Refreshes on shell events
- `SPC l n` - `personal/agent-next-waiting`: jump to the next shell that is blocked, else the next finished-unseen one
- `SPC l e/f` - Agent: send region / send file (`agent-shell-send-region`, `agent-shell-send-file`)
- `SPC l w` / `SPC l W` - Agent worktree: create / remove (see below)
- `SPC l g` - `personal/worktree-list`: overview of all worktrees under `~/data/worktrees/` (columns: repo, branch, state local/remote/MR/final, MR number+state, ahead/behind origin/master with dry-run `git merge-tree` conflict detection, dirty/unpushed, Claude running). MR info is looked up async via `glab mr list --all --source-branch`; merged/closed MR = "final". Keys: RET switch workspace, d delete (extra warning if dirty/unpushed; keeps branch), D delete all final, f/F fetch at point/all repos, m magit-status, o open MR in browser, r/R rebase onto origin/master at point/all behind+clean+conflict-free non-final, gr refresh (re-queries MRs), ? transient menu of all keys, q quit

#### Custom Commands
- `personal/magit-repolist-fetch` - Fetch all git repositories
- `personal/solve-org-sync-conflicts` - Resolve Syncthing conflicts in org files
- `personal/work/ccm-npm-ci` - Run npm ci with PostgreSQL in nix-shell
- `personal/gpg-check` - Test GPG signing
- `personal/agent-worktree-new` - Create git worktree `~/data/worktrees/<repo>/<branch>/`, switch to a Doom workspace `<repo>:<branch>` and start an agent shell there (`personal/worktree-root`; deliberately not in the projectile search path)
- `personal/agent-worktree-remove` - Kill the worktree's agent buffers and workspace, then `git worktree remove` (offers force if dirty)
- Agent notifications go through `personal/agent--notify` (desktop notification on permission/question/finished when the shell isn't the selected window); modeline shows `agent[N] !blocked *busy +done` via `personal/agent-modeline`
- `personal/agent-worktree-new` offers local + origin branches via completing-read (new names allowed)
- `personal/gitlab-refresh` - Fetch GitLab todos/MRs/issues and write to gitlab.org; auto-runs on agenda open if file is >30 min stale
- `personal/org-agenda-open-gitlab-url` - Open `:URL:` property of current agenda entry in browser (bound to `o` in org-agenda)

## Language-Specific Configuration

### C# / .NET
- OmniSharp LSP server
- Tree-sitter support
- Configured for Unity and .NET development

### JavaScript/TypeScript
- LSP and tree-sitter enabled
- TailwindCSS LSP integration
- Format on save disabled for LSP (`+format-with-lsp nil`)

### Go
- LSP with golangci-lint integration
- Tree-sitter support

### Nix
- LSP and tree-sitter support
- Home-manager helper function

### Emacs Lisp
- Lispy mode for structural editing
- Exercism integration with test runner

## Important Settings

- **Theme**: doom-solarized-light
- **Font**: PragmataPro Mono Liga, size 16
- **Auto-save**: Enabled with 30-second interval for org buffers
- **Line numbers**: Disabled (`display-line-numbers-type nil`)
- **Startup**: Opens with org-super-agenda view
- **Format on save**: Enabled globally, LSP formatting disabled
- use `~/.emacs.d/bin/doom sync` when running doom sync
