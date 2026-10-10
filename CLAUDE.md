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
- **claude.el** - claude-code.el setup: smart toggle, session list, worktree workflow, notifications, modeline, `SPC l` keys; loaded from `config.el` (ghostel package settings stay in `config.el`)
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
- **Org-agenda** - Task management; agenda files are `tasks.org` plus notes with the `todo` keyword (not `archive`) in the KB root (`personal/kb-agenda-files`). The `todo` filetag is kept in sync on save (`personal/kb-sync-todo-tag`). Marking a task DONE in any KB note appends it to today's daily (created if missing) under `* Done` with a `[[denote:ID]]` link to the source note (`personal/kb-log-done-to-daily`, on `org-after-todo-state-change-hook`)
- **Org-super-agenda** - Enhanced agenda view with custom grouping
- Custom capture templates for tasks, people, and notes

#### External Services
- **Kubernetes** - K8s management via kubernetes.el
- **Docker** - Docker integration with LSP support
- **Prodigy** - Process manager for AWS profiles and database connections
- **Claude Code** - claude-code.el with ghostel backend (libghostty; Doom `:term ghostel` module, which also provides `evil-ghostel` and `SPC o t` popup / `SPC o T` here; native module dir and progress setup in `config.el`, native module in `~/.local/share/ghostel/`; ghostel is the only terminal) (`SPC l c`, `C-c c`)
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
- `SPC o t` / `SPC o T` - Ghostel terminal: popup at project root / open here (Doom `:term ghostel` defaults)
- `SPC f p` / `SPC f P` (Doom private config) switch to (or create) a dedicated `doom` workspace first (`personal/switch-to-doom-workspace`)
- `SPC l c` / `C-c c` - Claude Code transient menu
- `SPC l l` (also `SPC l t`) - `personal/claude-toggle`: start (and focus) Claude for the project if none, otherwise show+focus, or hide when focused. From the default workspace it first switches to a workspace named after the project
- `SPC l r/m/s` - Claude: resume / cycle mode / switch instance (new extra instance via `C-c c` menu). Instance names are never prompted (auto: default, 2, 3, ...)
- `SPC l b` - `personal/claude-list`: overview of all Claude sessions (RET go to its workspace and show it at the bottom, highlighted session is auto-previewed in a side window (p forces it), x kill, gr refresh, q quit)
- `SPC l e/f/x/X/E` - Claude: send region / send file / send command / command with context / fix error at point
- `SPC l w` / `SPC l W` - Claude worktree: create / remove (see below)
- `SPC l g` - `personal/worktree-list`: overview of all worktrees under `~/data/worktrees/` (columns: repo, branch, state local/remote/MR/final, MR number+state, ahead/behind origin/master with dry-run `git merge-tree` conflict detection, dirty/unpushed, Claude running). MR info is looked up async via `glab mr list --all --source-branch`; merged/closed MR = "final". Keys: RET switch workspace, d delete (extra warning if dirty/unpushed; keeps branch), D delete all final, f/F fetch at point/all repos, m magit-status, o open MR in browser, r/R rebase onto origin/master at point/all behind+clean+conflict-free non-final, gr refresh (re-queries MRs), ? transient menu of all keys, q quit

#### Custom Commands
- `personal/magit-repolist-fetch` - Fetch all git repositories
- `personal/solve-org-sync-conflicts` - Resolve Syncthing conflicts in org files
- `personal/work/ccm-npm-ci` - Run npm ci with PostgreSQL in nix-shell
- `personal/gpg-check` - Test GPG signing
- `personal/claude-worktree-new` - Create git worktree `~/data/worktrees/<repo>/<branch>/`, switch to a Doom workspace `<repo>:<branch>` and start Claude there (`personal/worktree-root`; deliberately not in the projectile search path)
- `personal/claude-worktree-remove` - Kill the worktree's Claude buffer and workspace, then `git worktree remove` (offers force if dirty)
- In Claude buffers `C-g` in evil insert state sends ESC to Claude; plain ESC leaves insert state (`personal/claude-send-escape-key` on `claude-code-start-hook`)
- Claude finish notifications go through `personal/claude-notify` (desktop notification when a Claude window isn't focused); modeline shows `claude[N]` (`*` and warning face while a session shows progress) via `personal/claude-modeline`
- `personal/claude-worktree-new` offers local + origin branches via completing-read (new names allowed)
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
