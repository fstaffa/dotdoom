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
    (holiday-sexp '(if (= 0 (% year 5))) "Liberation Day / Bevrijdingsdag")
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
(setq org-roam-directory "~/data/org-mode/roam")
(setq org-roam-dailies-directory (f-join org-roam-directory "daily"))
(setq org-directory "~/data/org-mode/org/")

;; save buffers after 30 sec of inactivity to prevent conflicts - https://emacs.stackexchange.com/questions/477/how-do-i-automatically-save-org-mode-buffers
(add-hook 'auto-save-hook 'org-save-all-org-buffers)

(setq x-selection-timeout 10)
(setq org-agenda-include-diary t)
(setq org-agenda-files (list org-directory))
(setq org-default-notes-file "refile.org")
(setq org-archive-location "archive.org::")
(setq org-refile-targets '((org-agenda-files :maxlevel . 3)))
(setq org-refile-allow-creating-parent-nodes 'confirm)
(defun my/person-template (name)
  (let* ((filename (personal/person-to-file name))
         (uppercase-name (capitalize name))
         (shortcut (concat "p" (substring name 0 1)))
         (label (concat uppercase-name " next")))
    `(,shortcut ,label entry (file+headline ,filename "next") "* %?\n:PROPERTIES:\n:CAPTURED: %U\n:END:\n")))
(defun personal/person-to-file (name) (concat name ".org"))
(after! org
  (setq org-log-done 'time)
  (setq org-todo-keywords '((sequence "TODO(t)" "DONE(d)")))
  (setq org-capture-templates
        (append  '(("f" "Followup" entry (file+headline "refile.org" "Followup")
                    "* TODO %?\n SCHEDULED: %^t\n:PROPERTIES:\n:CAPTURED: %U\n:END:\n")
                   ("c" "coach")
                   ("cv" "vztek" entry (file+olp+datetree "projekty.org" "coaching" "vztek") "* %?")
                   ("t" "Do Today" entry (file+headline "refile.org" "Do Today")
                    "* TODO %?\n DEADLINE: %t\n:PROPERTIES:\n:CAPTURED: %U\n:END:\n")
                   ("w" "This Week" entry (file+headline "refile.org" "This Week")
                    "* TODO %?\n DEADLINE: %(org-insert-time-stamp (org-read-date nil t \"Fri\"))\n:PROPERTIES:\n:CAPTURED: %U\n:END:\n")
                   ("s" "Standup point" entry (file+headline "work.org" "Standups")
                    "* %? :standup:")
                   ("r" "Retrospective point" entry (file+headline "work.org" "Retrospective")
                    "* %? :retrospective:\n:PROPERTIES:\n:CAPTURED: %U\n:END:\n")
                   ("l" "Deadline for later" entry (file+headline "refile.org" "later") "* TODO %?\nDEADLINE: %^t\n:PROPERTIES:\n:CAPTURED: %U\n:END:\n" :time-prompt t)
                   ("p" "Person"))
                 (list
                  (my/person-template "adam")
                  (my/person-template "ksenia")
                  (my/person-template "michal")
                  (my/person-template "stepan"))
                 ))
  )

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

(map! :leader :desc "prodigy" "o p" #'prodigy)

(dolist (account '("logisticsquotingplanning" "praguematic" "sapidus"))
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


(setenv "NVM_DIR" "~/.local/share/nvm")

(setq evil-snipe-override-evil-repeat-keys nil)
(setq doom-localleader-key ",")
(setq doom-localleader-alt-key "M-,")

(use-package! graphviz-dot-mode
  :ensure t)

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
                        (org-super-agenda-groups
                         '((:name "Today"
                            :time-grid t
                            :date today
                            :order 1)))))
            (alltodo "" ((org-agenda-overriding-header "")
                         (org-super-agenda-groups
                          '((:log t)
                            (:name "To refile"
                             :file-path "refile\\.org")
                            (:name "Standup"
                             :tag "standup")
                            (:name "Today's tasks"
                             :file-path "journal/")
                            (:name "Due Today"
                             :deadline today
                             :order 2)
                            (:name "Scheduled Soon"
                             :scheduled future
                             :order 8)
                            (:name "Overdue"
                             :deadline past
                             :order 7)
                            (:discard (:not (:todo "TODO")))))))))))
  :config
  (org-super-agenda-mode))

(setq +format-with-lsp nil)


(setq lsp-csharp-server-path "OmniSharp")

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

(use-package! chatgpt-shell
  :config (setq chatgpt-shell-openai-key
                (lambda ()
                  (auth-source-pick-first-password :host "api.openai.com"))))

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
