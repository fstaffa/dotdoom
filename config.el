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
(setq user-full-name "John Doe"
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
(setq org-directory "~/data/org-mode/org")

;; save buffers after 30 sec of inactivity to prevent conflicts - https://emacs.stackexchange.com/questions/477/how-do-i-automatically-save-org-mode-buffers
(add-hook 'auto-save-hook 'org-save-all-org-buffers)

(setq x-selection-timeout 10)
(setq org-agenda-include-diary t)
(setq org-agenda-files (list org-directory))
(setq org-default-notes-file "refile.org")
(setq org-archive-location "archive.org::")
(setq org-refile-targets '((org-agenda-files :maxlevel . 3)))
(setq org-refile-allow-creating-parent-nodes 'confirm)
(defun my/person-template (shortcut name)
                      (let* ((uppercase-name (capitalize name))
                            (filename (concat name ".org"))
                            (label (concat uppercase-name " next")))
                        `(,shortcut ,label entry (file+headline ,filename "next") "* %?" :time-prompt t)))
(after! org
  (setq org-log-done 'time)
  (setq org-todo-keywords '((sequence "TODO(t)" "DONE(d)")))
  (setq org-capture-templates
        `(("f" "Followup" entry (file+headline "refile.org" "Followup")
           "* TODO %?\n SCHEDULED: %^t")
          ("t" "Do Today" entry (file+headline "refile.org" "Do Today")
           "* TODO %?\n SCHEDULED: %t")
          ("w" "This Week" entry (file+headline "refile.org" "This Week")
           "* TODO %?\n SCHEDULED: %(org-insert-time-stamp (org-read-date nil t \"Fri\"))")
          ("s" "Standup point" entry (file+headline "refile.org" "Standups")
           "* %? :standup:")
          ("r" "Retrospective point" entry (file+headline "refile.org" "Retrospective")
           "* %? :retrospective:")
          ("d" "Daily today" entry (file+olp+datetree "daily.org") "* %?" :time-prompt t)
          ("p" "Person")
          ,(my/person-template "pa" "adam")
          ,(my/person-template "pd" "denis")
          ,(my/person-template "pg" "grand")
          ,(my/person-template "pk" "ksenia")
          ,(my/person-template "pm" "michal")
          ,(my/person-template "ps" "stepan")
          )
        ))
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

(defun my-magit-fetch-all-repositories ()
  "Run `magit-fetch-all' in all repositories returned by `magit-list-repos`."
  (interactive)
  (dolist (repo (magit-list-repos))
    (message "Fetching in %s..." repo)
    (let ((default-directory repo))
      (magit-fetch-all (magit-fetch-arguments)))
    (message "Fetching in %s...done" repo)))

(add-hook 'git-commit-setup-hook 'my-git-commit-message)

;; This determines the style of line numbers in effect. If set to `nil', line
;; numbers are disabled. For relative line numbers, set this to `relative'.
(setq display-line-numbers-type t)


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

(map! :leader :desc "prodigy" "o p" #'prodigy)
(use-package! key-chord
  :config
  (key-chord-mode 1)
  (setq key-chord-one-keys-delay 0.02
        key-chord-two-keys-delay 0.03))

(after! key-chord
  (key-chord-define evil-insert-state-map "fd" 'evil-normal-state))

(after! key-chord
  (key-chord-define evil-insert-state-map "fs" 'save-buffer))

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

(use-package! kubernetes
  :defer t
  :config
  (setq kubernetes-poll-frequency 3600
        kubernetes-redraw-frequency 3600))

(use-package! kubernetes-evil
  :after kubernetes-overview)

(prodigy-define-service
  :name "CCM Production database"
  :command "ssh"
  :args '("rds-planning-ccm-prd" "-v")
  :port 15432
  )

(prodigy-define-service
  :name "CCM local db"
  :command "podman"
  :args '("run" "-p" "5432:5432" "-e" "POSTGRES_PASSWORD=postgres" "postgres")
  :port 5432
  )

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
              (setq my/flycheck-local-cache '((lsp . ((next-checkers . (sh-shellcheck)))))))))

(setq jiralib-url "https://cimpress-support.atlassian.net")

;; https://github.com/doomemacs/doomemacs/pull/3021/files
(use-package! magit-delta
  :after magit
  :config (setq
   magit-delta-default-dark-theme "Solarized (dark)"
   magit-delta-default-light-theme "Solarized (light)")
  :hook (magit-mode . magit-delta-mode))
