(use-package! f :ensure t)
;; holidays
(setq holiday-bahai-holidays nil)
(setq holiday-general-holidays nil)
(setq holiday-christian-holidays nil)
(setq holiday-hebrew-holidays nil)
(setq holiday-oriental-holidays nil)
(setq holiday-islamic-holidays nil)
(defvar czech-holidays-list
  '((holiday-fixed 1 1 "Den obnovy samostatného českého státu; Nový rok")
    (holiday-easter-etc -2 "Velký pátek")
    (holiday-easter-etc 1 "Velikonoční Pondělí")
    (holiday-fixed 5 1 "Svátek práce")
    (holiday-fixed 5 8 "Den vítězství")
    (holiday-fixed 7 5 "Den slovanských věrozvěstů Cyrila a Metoděje")
    (holiday-fixed 7 6 "Den upálení mistra Jana Husa")
    (holiday-fixed 9 28 "Den české státnosti")
    (holiday-fixed 10 28 "Den vzniku samostatného československého státu")
    (holiday-fixed 11 17 "Den boje za svobodu a demokracii")
    (holiday-fixed 12 24 "Štědrý den")
    (holiday-fixed 12 25 "svátek vánoční")
    (holiday-fixed 12 26 "svátek vánoční"))
  "List of Czech public holidays.")
(defvar dutch-holidays-list
  '((holiday-fixed 1 1 "New Year’s Day / Nieuwjaarsdag")
    (holiday-easter-etc -2 "Good Friday / Goede Vrijdag")
    (holiday-easter-etc 1 "Easter Monday / Tweede Paasdag")
    (holiday-sexp
     '(if (zerop (calendar-day-of-week (list 4 27 year)))
          (list 4 26 year)
        (list 4 27 year))
     "Koningsdag")
    (holiday-sexp '(if (zerop (% year 5)) (list 5 5 year)) "Liberation Day / Bevrijdingsdag")
    (holiday-easter-etc +39 "Ascension Day / Hemelvaart")
    (holiday-easter-etc +49 "Whit (Pentecost) Sunday / Eerste Pinksterdag")
    (holiday-easter-etc +50 "Whit (Pentecost) Monday / Tweede Pinksterdag")
    (holiday-fixed 12 25 "Christmas Day / Eerste Kerstdag")
    (holiday-fixed 12 26 "Boxing Day / Tweede Kerstdag")
    )
  "List of Dutch public holidays.")

(setq holiday-other-holidays (append czech-holidays-list dutch-holidays-list))

;; Some functionality uses this to identify you, e.g. GPG configuration, email
;; clients, file templates and snippets.
(setq user-full-name "Filip Staffa"
      user-mail-address "john@doe.com")

;; Doom exposes five (optional) variables for controlling fonts in Doom. Here
;; are the three important ones:
;;
;; + `doom-font'
;; + `doom-variable-pitch-font'
;; + `doom-big-font' -- used for `doom-big-font-mode'; use this for
;;   presentations or streaming.
;;
;; They all accept either a font-spec, font string ("Input Mono-12"), or xlfd
;; font string. You generally only need these two:
;; (setq doom-font (font-spec :family "monospace" :size 12 :weight 'semi-light)
;;       doom-variable-pitch-font (font-spec :family "sans" :size 13))

;; There are two ways to load a theme. Both assume the theme is installed and
;; available. You can either set `doom-theme' or manually load a theme with the
;; `load-theme' function. This is the default:
(setq doom-theme 'doom-solarized-light)

(setq doom-font (font-spec :family "PragmataPro Mono Liga"
                           :size 16
                           :weight 'normal
                           :width 'normal
                           :powerline-scale 1.1))

;; start fullscreen
(add-to-list 'initial-frame-alist '(fullscreen . maximized))

;;
(setq confirm-kill-emacs nil)


;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
;; Denote based knowledge base (see kb-denote.el and kb/).
(load! "kb-denote")
(setq org-directory personal/kb-root)

;; save buffers after 30 sec of inactivity to prevent conflicts - https://emacs.stackexchange.com/questions/477/how-do-i-automatically-save-org-mode-buffers
(add-hook 'auto-save-hook 'org-save-all-org-buffers)
(auto-save-visited-mode 1)

;; automatically reload org files when they change on disk (Syncthing sync)
(global-auto-revert-mode 1)
(setq auto-revert-verbose nil)  ; don't show messages when reverting
(setq auto-revert-use-notify t) ; use file system notifications for faster updates

(setq x-selection-timeout 10)
(setq org-agenda-include-diary t)
(setq org-default-notes-file "tasks.org")
(setq org-refile-targets '((personal/kb-refile-files :maxlevel . 2)))
(setq org-refile-allow-creating-parent-nodes 'confirm)
(after! org
  (require 'org-habit)
  (add-to-list 'org-modules 'org-habit)
  (setq org-habit-graph-column 60
        org-habit-show-habits-only-for-today nil
        org-habit-following-days 7
        org-habit-preceding-days 21)
  (setq org-log-done 'time)
  (setq org-todo-keywords '((sequence "TODO(t)" "NEXT(n)" "WAITING(w)" "|" "DONE(d)")))
  (setq org-capture-templates
        '(("i" "Inbox note (new file)" plain (function personal/kb-new-inbox-file) "%?"
           :empty-lines 0 :jump-to-captured nil)
          ("t" "Task" entry (file "tasks.org")
           "* TODO %?\n:PROPERTIES:\n:CAPTURED: %U\n:END:\n")
          ("s" "Task (scheduled)" entry (file "tasks.org")
           "* TODO %?\nSCHEDULED: %^t\n:PROPERTIES:\n:CAPTURED: %U\n:END:\n")
          ("d" "Task (deadline)" entry (file "tasks.org")
           "* TODO %?\nDEADLINE: %^t\n:PROPERTIES:\n:CAPTURED: %U\n:END:\n"))))

;; fix org-capture-mode not starting correctly after org agenda https://github.com/doomemacs/doomemacs/issues/5714
(after! org
  (defadvice! personal/+org--restart-mode-h-careful-restart (fn &rest args)
    :around #'+org--restart-mode-h
    (let ((old-org-capture-current-plist (and (bound-and-true-p org-capture-mode)
                                              (bound-and-true-p org-capture-current-plist))))
      (apply fn args)
      (when old-org-capture-current-plist
        (setq-local org-capture-current-plist old-org-capture-current-plist)
        (org-capture-mode +1)))))

(setq org-agenda-custom-commands
      '(("h" "Agenda and Home-related tasks"
         ((agenda "")
          (tags "standup")
          (tags "retrospective")))
        ))

(let* ((git-project-paths '("~/data/cimpress/" "~/data/personal/"))
       (magit-dirs (seq-map (lambda (folder) (cons folder 1)) git-project-paths)))
  (setq projectile-project-search-path git-project-paths)
  (setq magit-repository-directories magit-dirs))

(defun my-git-commit-message ()
  (let ((ISSUEKEY "[[:upper:]]+-[[:digit:]]+"))
    (when (string-match-p ISSUEKEY (magit-get-current-branch))
      (insert
       (replace-regexp-in-string
        (concat ".*?\\(" ISSUEKEY "\\).*")
        "\\1 "
        (magit-get-current-branch))))))

(defun personal/magit-repolist-fetch ()
  "Fetch all remotes in repositories returned by `magit-list-repos'.
Fetching is done synchronously."
  (interactive)
  (run-hooks 'magit-credential-hook)
  (let* ((repos (magit-list-repos))
         (l (length repos))
         (i 0))
    (dolist (repo repos)
      (let* ((default-directory (file-name-as-directory repo))
             (msg (format "(%s/%s) Fetching in %s..."
                          (cl-incf i) l default-directory)))
        (message msg)
        (magit-run-git "remote" "update" (magit-fetch-arguments))
        (message (concat msg "done")))))
  (magit-refresh))

(add-hook 'git-commit-setup-hook 'my-git-commit-message)

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type nil)


;; Here are some additional functions/macros that could help you configure Doom:
;;
;; - `load!' for loading external *.el files relative to this one
;; - `use-package!' for configuring packages
;; - `after!' for running code after a package has loaded
;; - `add-load-path!' for adding directories to the `load-path', relative to
;;   this file. Emacs searches the `load-path' when you load packages with
;;   `require' or `use-package'.
;; - `map!' for binding new keys
;;
;; To get information about any of these functions/macros, move the cursor over
;; the highlighted symbol at press 'K' (non-evil users must press 'C-c c k').
;; This will open documentation for it, including demos of how they are used.
;;
;; You can also try 'gd' (or 'C-c c d') to jump to their definition and see how
;; they are implemented.

(map! :leader "w s" #'switch-to-buffer-other-window)

(use-package! key-chord
  :config
  (key-chord-mode 1)
  (setq key-chord-one-keys-delay 0.02
        key-chord-two-keys-delay 0.03)
  (key-chord-define evil-insert-state-map "fd" 'evil-normal-state)
  (key-chord-define evil-insert-state-map "fs" 'save-buffer)
  (key-chord-define evil-insert-state-map "jk" 'copilot-next-completion))

(defun exercism-tests ()
  (interactive)
  (let* ((current-file (buffer-name))
         (implementation-file (string-replace "-test" "" current-file))
         (test-file (string-replace ".el" "-test.el" implementation-file)))
    (message "%s" test-file )
    (save-buffer)
    (eval-buffer implementation-file)
    (eval-buffer test-file)
    )
  (lispy-ert))

(defun personal/exercism-disable-copilot ()
  (let ((target-dir (expand-file-name exercism--workspace))
        (current-file (buffer-file-name)))
    (when (and current-file (string-prefix-p target-dir (expand-file-name current-file)))
      (copilot-mode -1))))

(add-hook 'find-file-hook 'personal/exercism-disable-copilot)

(use-package! kubernetes
  :defer t
  :config
  (setq kubernetes-poll-frequency 3600
        kubernetes-redraw-frequency 3600))

(use-package! kubernetes-evil
  :after kubernetes-overview)

(use-package! prodigy)
(map! :leader :desc "prodigy" "o p" #'prodigy)

(dolist (account '("logisticsquotingplanning"))
  (prodigy-define-service
    :name (concat "AWS " account)
    :command "stskeygen"
    :args (list "--account" account "--profile" account "--admin" "--duration" "43200")
    ))

(dolist (db-host '("rds-planning-ccm-prd" "rds-planning-ccm-stg"
                   "rds-planning-shipping-calculator-prd" "rds-planning-shipping-calculator-stg"))
  (prodigy-define-service
    :name db-host
    :command "ssh"
    :args (list db-host "-v")))

(dolist (environment '("production" "staging"))
  (let ((path "~/data/cimpress/ccm/"))
    (prodigy-define-service
      :name (concat "CCM " environment)
      :command "bash"
      :cwd path
      :args (list "run.sh" environment)
      )))

(prodigy-define-service
  :name "docker postgres"
  :command "docker"
  :args '("run" "--rm" "-p" "5432:5432" "-e" "POSTGRES_PASSWORD=postgres" "postgres")
  )

(setenv "NVM_DIR" "~/.local/share/nvm")

(setq evil-snipe-override-evil-repeat-keys nil)
(setq doom-localleader-key ",")
(setq doom-localleader-alt-key "M-,")

;; (setq org-super-agenda-header-map evil-org-agenda-mode-map)
(use-package! org-super-agenda
  :after org-agenda
  :init
  (setq org-agenda-skip-scheduled-if-done t
        org-agenda-skip-deadline-if-done t
        org-agenda-include-deadlines t
        org-agenda-block-separator nil
        org-agenda-compact-blocks t
        org-agenda-start-day nil ;; i.e. today
        org-agenda-span 1
        org-agenda-start-on-weekday nil
        org-super-agenda-header-map (make-sparse-keymap))

  (setq org-agenda-custom-commands
        '(("c" "Super view"
           ((agenda "" ((org-agenda-overriding-header "")
                        (org-agenda-span 'day)
                        (org-habit-show-all-today t)
                        (org-habit-show-habits-only-for-today t)
                        (org-super-agenda-groups
                         '((:name "Habits"
                            :habit t
                            :order 0)
                           (:name "Today"
                            :time-grid t
                            :date today
                            :order 1)))))
            (alltodo "" ((org-agenda-overriding-header "")
                         (org-super-agenda-groups
                          '((:log t)
                            (:name "Habits"
                             :habit t)
                            (:name "GitLab"
                             :file-path "gitlab\\.org"
                             :order 0)
                            (:name "Standup"
                             :tag "standup")
                            (:name "Today's tasks"
                             :file-path "journal/")
                            (:name "Due Today"
                             :deadline today
                             :order 2)
                            (:name "Scheduled Soon"
                             :scheduled future
                             :order 4)
                            (:name "Overdue"
                             :deadline past
                             :order 3)
                            (:name "Captured in tasks.org"
                             :file-path "tasks\\.org"
                             :order 5)
                            (:discard (:not (:todo ("TODO" "REVIEW"))))))))))))
  :config
  (org-super-agenda-mode))

;; Agenda views for the knowledge base.  Added after the "c" view above is defined.
(after! org-agenda
  (dolist (cmd '(("n" "Next actions" todo "NEXT")
                 ("w" "Waiting for" todo "WAITING")))
    (add-to-list 'org-agenda-custom-commands cmd t)))

(setq +format-with-lsp nil)

;; fix for lsp
(defvar-local my/flycheck-local-cache nil)

(defun my/flycheck-checker-get (fn checker property)
  (or (alist-get property (alist-get checker my/flycheck-local-cache))
      (funcall fn checker property)))

(advice-add 'flycheck-checker-get :around 'my/flycheck-checker-get)

(add-hook 'lsp-managed-mode-hook
          (lambda ()
            (when (derived-mode-p 'sh-mode)
              (setq my/flycheck-local-cache '((lsp . ((next-checkers . (sh-shellcheck)))))))
            (when (derived-mode-p 'go-mode)
              (setq my/flycheck-local-cache '((lsp . ((next-checkers . (golangci-lint)))))))
            ))

(setq jiralib-url "https://cimpress-support.atlassian.net")

;; https://github.com/doomemacs/doomemacs/pull/3021/files
(use-package! magit-delta
  :after magit
  :config (setq
           magit-delta-default-dark-theme "Solarized (dark)"
           magit-delta-default-light-theme "Solarized (light)")
  :hook (magit-mode . magit-delta-mode))

(setq personal/remaining-sync-conflicts ())
(setq personal/last-solved-conflict nil)

(defun personal/solve-org-sync-conflicts ()
  "Runs ediff on all sync conflicts in org-directory"
  (interactive)
  (let ((files (seq-filter (lambda (x) (string-match-p "sync-conflict" x)) (directory-files org-directory 'full))))
    (progn (setq personal/remaining-sync-conflicts files)
           (add-hook 'ediff-after-quit-hook-internal 'personal/solve-org-sync-conflicts-hook)
           (personal/solve-org-sync-conflicts-hook))
    ))

(defun personal/solve-org-sync-conflicts-hook ()
  (progn
    (if personal/last-solved-conflict
        (let ((file personal/last-solved-conflict))
          (if (string-equal (read-string (format "Do you want to delete file %s: " file) "yes") "yes")
              (progn
                (delete-file file)
                (setq personal/last-solved-conflict nil)))))
    (if (not personal/remaining-sync-conflicts)
        (progn (remove-hook 'ediff-after-quit-hook-internal 'personal/solve-org-sync-conflicts-hook)
               (message "done"))
      (let* ((file (car personal/remaining-sync-conflicts))
             (original-file (replace-regexp-in-string "\.sync-conflict[^.]*" "" file)))
        (progn
          (setq personal/remaining-sync-conflicts (cdr personal/remaining-sync-conflicts))
          (setq personal/last-solved-conflict file)
          (ediff-files file original-file))))))

(defun personal/chat-mode ()
  (visual-line-mode 1))

(require 'auth-source)
(defun personal/openai-auth-token ()
  "Search for and return the OpenAI API token from auth-sources."
  (auth-source-pick-first-password :host "api.anthropic.com"))

(defun personal/anthropic-auth-token ()
  "Search for and return the Anthropic API token from auth-sources."
  (auth-source-pick-first-password :host "api.anthropic.com"))
(auth-source-forget-all-cached)

(use-package! chatgpt-shell
  :config (setq chatgpt-shell-openai-key 'personal/openai-auth-token
                chatgpt-shell-anthropic-key 'personal/anthropic-auth-token
                chatgpt-shell-default-model "claude-3-7-sonnet-20250219"
                chatgpt-shell-default-backend 'anthropic))

(use-package! claude-code
  :after transient
  :defer t
  :config
  (setq claude-code-terminal-backend 'vterm)
  (claude-code-mode))

(map! :leader
      :desc "Claude Code transient menu" "l c" #'claude-code-transient)

(map! "C-c c" #'claude-code-transient)

(defun personal/gitlab-set-token (&rest ARG)
  (if (null lab-token)
      (setq lab-token (auth-source-pick-first-password :host "gitlab.com/api"))))

(use-package! lab
  :config (setq lab-host "https://gitlab.com"

                ;; Required.
                ;; See the following link to learn how you can gather one for yourself:
                ;; https://docs.gitlab.com/ee/user/profile/personal_access_tokens.html#create-a-personal-access-token
                ;; no token set, using advice to load from authsources

                ;; Optional, but useful. See the variable documentation.
                lab-group "8501113")
  (advice-add 'lab--request :before #'personal/gitlab-set-token))

(defun personal/org-agenda-open-gitlab-url ()
  "Open the URL property of the current org-agenda entry in browser."
  (interactive)
  (let* ((marker (or (org-get-at-bol 'org-hd-marker)
                     (org-get-at-bol 'org-marker)))
         (url (when marker
                (with-current-buffer (marker-buffer marker)
                  (save-excursion
                    (goto-char (marker-position marker))
                    (org-entry-get nil "URL"))))))
    (if (and url (not (string-empty-p url)))
        (browse-url url)
      (message "No URL property found on this entry"))))

(after! evil-org-agenda
  (evil-define-key 'motion evil-org-agenda-mode-map
    "o" #'personal/org-agenda-open-gitlab-url
    "x" #'personal/gitlab-mark-todo-done))

(defun personal/gitlab--time-ago (iso-string)
  "Return a compact human-readable age string for ISO-STRING timestamp."
  (let* ((then (float-time (date-to-time iso-string)))
         (delta (- (float-time) then))
         (mins  (floor (/ delta 60)))
         (hours (floor (/ delta 3600)))
         (days  (floor (/ delta 86400))))
    (cond ((< delta 3600)  (format "%dm" mins))
          ((< delta 86400) (format "%dh" hours))
          ((< days 30)     (format "%dd" days))
          ((< days 365)    (format "%dmo" (floor (/ days 30))))
          (t               (format "%dy" (floor (/ days 365)))))))

(defvar personal/gitlab--refreshing nil
  "Non-nil while an async GitLab refresh is in flight.")

(defun personal/gitlab--request-async (callback endpoint &rest params)
  "Request ENDPOINT asynchronously and call CALLBACK with the data (nil on error)."
  (apply #'lab--request endpoint
         (append params
                 (list :%success callback
                       :%error (lambda (&rest _) (funcall callback nil))))))

(defun personal/gitlab-refresh ()
  "Fetch GitLab todos, MRs, and issues asynchronously and write them to gitlab.org."
  (interactive)
  (if personal/gitlab--refreshing
      (message "GitLab: refresh already in progress")
    (message "GitLab: refreshing...")
    (personal/gitlab-set-token)
    (setq personal/gitlab--refreshing t)
    (let ((pending 4) todos mrs-created mrs-assigned issues)
      (cl-flet ((collector (setter)
                  (lambda (data)
                    (funcall setter data)
                    (when (zerop (cl-decf pending))
                      (unwind-protect
                          (personal/gitlab--write
                           todos
                           (seq-uniq (append mrs-created mrs-assigned)
                                     (lambda (a b) (equal (alist-get 'web_url a)
                                                          (alist-get 'web_url b))))
                           issues)
                        (setq personal/gitlab--refreshing nil))))))
        (condition-case err
            (progn
              (personal/gitlab--request-async
               (collector (lambda (d) (setq todos d))) "todos")
              (personal/gitlab--request-async
               (collector (lambda (d) (setq mrs-created d)))
               "merge_requests" :scope 'created_by_me :state 'opened)
              (personal/gitlab--request-async
               (collector (lambda (d) (setq mrs-assigned d)))
               "merge_requests" :scope 'assigned_to_me :state 'opened)
              (personal/gitlab--request-async
               (collector (lambda (d) (setq issues d)))
               "issues" :scope "assigned_to_me" :state "opened"))
          (error (setq personal/gitlab--refreshing nil)
                 (message "GitLab refresh error: %s" err)))))))

(defun personal/gitlab--write (todos mrs issues)
  "Write TODOS, MRS and ISSUES to gitlab.org and refresh the agenda."
  (let* ((gitlab-file (expand-file-name "gitlab.org" org-directory))
         (buf (find-file-noselect gitlab-file)))
    (with-current-buffer buf
      (setq buffer-read-only nil)
      (erase-buffer)
      (insert "#+TODO: TODO | DONE\n")
      (insert "#+TODO: REVIEW | DONE\n")
      (insert "#+FILETAGS: :gitlab:\n")
      (insert "#+TITLE: GitLab\n\n")
      (insert "* GitLab\n")
      (insert ":PROPERTIES:\n")
      (insert (format ":GITLAB_REFRESHED: %s\n"
                      (format-time-string "[%Y-%m-%d %a %H:%M]")))
      (insert ":END:\n\n")
      (insert "** Todos\n")
      (dolist (todo todos)
        (let-alist todo
          (let* ((target-state (alist-get 'state .target))
                 (state-tag (pcase target-state
                              ("closed" ":closed:")
                              ("merged" ":merged:")
                              (_ "")))
                 (author (or (alist-get 'username .author) ""))
                 (title (or (alist-get 'title .target) "Untitled"))
                 (body (or .body ""))
                 (heading (if (string= body "") title body))
                 (type-prefix (pcase .target_type
                                ("MergeRequest" "!")
                                ("Issue" "#")
                                (_ ""))))
            (insert (format "*** TODO %s  [%s]  :gitlab:todo:%s\n"
                            heading
                            (if .created_at (personal/gitlab--time-ago .created_at) "?")
                            state-tag))
            (insert ":PROPERTIES:\n")
            (insert (format ":URL:            %s\n" (or .target_url "")))
            (insert (format ":GITLAB_TODO_ID: %s\n" (or .id "")))
            (insert (format ":TITLE:          [%s%s] %s\n"
                            type-prefix
                            (or (alist-get 'iid .target) "")
                            title))
            (insert (format ":PROJECT:        %s\n" (or (alist-get 'name .project) "")))
            (insert (format ":ACTION:         %s\n" (or .action_name "")))
            (insert (format ":AUTHOR:         %s\n" author))
            (when .created_at
              (insert (format ":CREATED:  %s\n"
                              (format-time-string "[%Y-%m-%d %a]"
                                                  (date-to-time .created_at)))))
            (insert ":END:\n"))))
      (insert "\n** Merge Requests\n")
      (dolist (mr mrs)
        (let-alist mr
          (let ((project (thread-last (or .web_url "")
                           (s-chop-prefix lab-host)
                           (s-chop-prefix "/")
                           (s-split "/-/")
                           (car))))
            (insert (format "*** REVIEW %s  [%s]  :gitlab:mr:\n"
                            .title
                            (if .created_at (personal/gitlab--time-ago .created_at) "?")))
            (insert ":PROPERTIES:\n")
            (insert (format ":URL:     %s\n" .web_url))
            (insert (format ":PROJECT: %s\n" project))
            (insert (format ":AUTHOR:  %s\n" (or (alist-get 'username .author) "")))
            (insert ":END:\n"))))
      (insert "\n** Issues\n")
      (dolist (issue issues)
        (let-alist issue
          (let ((project (thread-last (or .web_url "")
                           (s-chop-prefix lab-host)
                           (s-chop-prefix "/")
                           (s-split "/-/")
                           (car))))
            (insert (format "*** REVIEW %s  [%s]  :gitlab:issue:\n"
                            .title
                            (if .created_at (personal/gitlab--time-ago .created_at) "?")))
            (insert ":PROPERTIES:\n")
            (insert (format ":URL:     %s\n" .web_url))
            (insert (format ":PROJECT: %s\n" project))
            (insert ":END:\n"))))
      (save-buffer))
    (message "GitLab: %d todos, %d MRs, %d issues"
             (length todos) (length mrs) (length issues))
    (when (get-buffer org-agenda-buffer-name)
      (with-current-buffer org-agenda-buffer-name
        (org-agenda-redo t)))))

(defvar personal/gitlab-refresh-interval-minutes 30)

(defun personal/gitlab-maybe-refresh ()
  (let* ((f (expand-file-name "gitlab.org" org-directory))
         (mtime (when (file-exists-p f)
                  (float-time (nth 5 (file-attributes f)))))
         (stale? (or (null mtime)
                     (> (- (float-time) mtime)
                        (* personal/gitlab-refresh-interval-minutes 60)))))
    (when stale?
      (run-with-idle-timer 1 nil #'personal/gitlab-refresh))))

(add-hook 'org-agenda-mode-hook #'personal/gitlab-maybe-refresh)

(map! :leader
      :desc "Refresh GitLab" "o g" #'personal/gitlab-refresh)

(defun personal/gitlab-mark-todo-done ()
  "Mark the GitLab todo at point as done via the API."
  (interactive)
  (let* ((marker (or (org-get-at-bol 'org-hd-marker)
                     (org-get-at-bol 'org-marker)))
         (todo-id (when marker
                    (with-current-buffer (marker-buffer marker)
                      (save-excursion
                        (goto-char (marker-position marker))
                        (org-entry-get nil "GITLAB_TODO_ID"))))))
    (if (and todo-id (not (string-empty-p todo-id)))
        (progn
          (personal/gitlab-set-token)
          (lab--request (format "todos/%s/mark_as_done" todo-id) :%type "POST"
                        :%success (lambda (_) (message "GitLab todo %s marked as done" todo-id)))
          (message "GitLab: marking todo %s as done..." todo-id))
      (message "No GITLAB_TODO_ID on this entry"))))

(defun personal/gitlab-org-todo-done-hook ()
  "When a gitlab:todo entry is marked DONE, resolve it in GitLab."
  (when (and (buffer-file-name)
             (string-match-p "gitlab\\.org$" (buffer-file-name)))
    (let ((todo-id (org-entry-get nil "GITLAB_TODO_ID")))
      (when (and todo-id
                 (not (string-empty-p todo-id))
                 (string= (org-get-todo-state) "DONE"))
        (personal/gitlab-set-token)
        (lab--request (format "todos/%s/mark_as_done" todo-id) :%type "POST"
                      :%success (lambda (_) (message "GitLab todo %s resolved" todo-id)))))))

(add-hook 'org-after-todo-state-change-hook #'personal/gitlab-org-todo-done-hook)

(defun personal/chat ()
  (interactive)
  (chat))


(defun personal/run-tests ()
  (eval-buffer)
  (ert t)
  (other-window 1))

(defun personal/nix/home-manager-switch ()
  (interactive)
  (personal/helper/custom-project-compile-command "home-manager switch --flake \".\""))

(add-hook 'after-save-hook 'my/run-tests nil t)

(defun personal/setup-tests ()
  (interactive)
  (add-hook 'after-save-hook 'personal/run-tests nil t))

(defun personal/helper/custom-project-compile-command (command)
  (projectile-run-compilation command))

(defun personal/work/ccm-npm-ci ()
  (interactive)
  (personal/helper/custom-project-compile-command "nix-shell -p postgresql --command 'npm ci'"))

(defun personal/gpg-check () (interactive)
       (let ((output-buffer "*GPG Encryption Test*"))
         (if (zerop (shell-command "echo \"test\" | gpg --clearsign" output-buffer))
             (progn
               (message "GPG check successful")
               (kill-buffer output-buffer)))))

(use-package! exercism)

(use-package! copilot
  :hook (prog-mode . copilot-mode)
  :custom (copilot-indent-offset-warning-disable t)
  :bind (:map copilot-completion-map
              ("<tab>" . 'copilot-accept-completion)
              ("TAB" . 'copilot-accept-completion)
              ("C-TAB" . 'copilot-accept-completion-by-word)
              ("C-<tab>" . 'copilot-accept-completion-by-word)))


(after! corfu
  (require 'nerd-icons-corfu)
  (add-to-list 'corfu-margin-formatters #'nerd-icons-corfu-formatter))

(use-package! hyperbole
  :init (hyperbole-mode)
  (defvar personal/jira-cs-browse-url "https://cimpress-support.atlassian.net/browse/")
  (defun personal/jira-cs-reference (jira-id)
    "Open ticket in CS Jira"
    (let ((url (concat personal/jira-cs-browse-url jira-id)))
      (browse-url-default-browser url)))
  (defib personal/jira-cs ()
         "Get the Jira ticket identifier at point and load ticket in browser"
         (let ((case-fold-search t)
               (jira-id nil)
               (jira-regex "\\(LABE-[0-9]+\\)"))
           (if (or (looking-at jira-regex)
                   (save-excursion
                     (skip-chars-backward "0-9")
                     (skip-chars-backward "-")
                     (skip-chars-backward "LABE")
                     (looking-at jira-regex)))
               (progn (setq jira-id (match-string-no-properties 1))
                      (ibut:label-set jira-id
                                      (match-beginning 1)
                                      (match-end 1))
                      (hact 'personal/jira-cs-reference jira-id)))))
  )

(use-package! beancount
  :init (add-to-list 'auto-mode-alist '("\\.beancount\\'" . beancount-mode)))
(use-package lsp-tailwindcss
  :init
  (setq lsp-tailwindcss-add-on-mode t))

;; (use-package! jj
;;   :commands (jj-status)
;;   :config
;;   (when (and (boundp 'evil-mode) (fboundp 'evil-define-key))
;;     (evil-define-key 'normal jj-status-mode-map (kbd "q") #'jj-window-quit)
;;     (evil-define-key 'normal jj-status-mode-map (kbd "l") #'jj-status-log-popup)
;;     (evil-define-key 'normal jj-status-mode-map (kbd "?") #'jj-status-popup)))

;; (map! :leader :desc "jujutsu status" "j s" #'jj-status)

(add-hook 'emacs-startup-hook
          (lambda ()
            (org-agenda nil "c")
            (org-super-agenda-mode)))

(setq +doom-dashboard-ascii-banner-fn nil)
(setq inhibit-startup-screen t)

(set-popup-rule! "^\\*npm:.*\\*" :side 'bottom :size 0.3 :quit t)

(add-hook 'compilation-finish-functions
          (lambda (buf str)
            (if (string-match ".*exited abnormally.*" str)
                (progn
                  (switch-to-buffer-other-window buf)))))

(defun my/use-literal-tabs ()
  "Configure the buffer to use literal tabs for indentation."
  (setq-local tab-width 2))

;; 2. Add this function to the hooks for the relevant major modes.
(add-hook 'typescript-ts-mode-hook #'my/use-literal-tabs)
(add-hook 'tsx-ts-mode-hook #'my/use-literal-tabs)
(add-hook 'js-mode-hook #'my/use-literal-tabs)

(require 'acp)
(require 'agent-shell)
(setq agent-shell-anthropic-authentication
      (agent-shell-anthropic-make-authentication :login t))
