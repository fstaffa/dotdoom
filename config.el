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

(setq x-selection-timeout 10)
(setq org-agenda-include-diary t)
(setq org-agenda-files (list org-directory))
(setq org-default-notes-file "refile.org")
(setq org-archive-location "archive.org::")
(setq org-refile-targets '((org-agenda-files :maxlevel . 3)))
(setq org-refile-allow-creating-parent-nodes 'confirm)
(after! org
  (setq org-todo-keywords '((sequence "TODO(t)" "DONE(d)")))
  (setq org-capture-templates
        '(("t" "Todo" entry (file+headline "refile.org" "Todos")
           "* TODO %?\n%U")
          ("f" "Followup" entry (file+headline "refile.org" "Followup")
           "* TODO %?\n SCHEDULED: %^t")
          ("s" "Standup point" entry (file+headline "refile.org" "Standups")
           "* %? :standup:")
          ("r" "Retrospective point" entry (file+headline "refile.org" "Retrospective")
           "* %? :retrospective:")
          ("d" "Daily today" entry (file+olp+datetree "daily.org") "* %?" :time-prompt t)
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
  :command "docker "
  :path '("/usr/bin")
  :args '("run"  "--name" "ccm-postgresql-db" "-p" "5432:5432" "-e" "POSTGRES_PASSWORD=postgres" "-d" "postgres")
  :port 5432
  )

(setenv "NVM_DIR" "~/.local/share/nvm")

(setq evil-snipe-override-evil-repeat-keys nil)
(setq doom-localleader-key ",")
(setq doom-localleader-alt-key "M-,")

(use-package! graphviz-dot-mode
  :ensure t)
(use-package! company-graphviz-dot)
