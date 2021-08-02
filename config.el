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
                               :size 14
                               :weight 'normal
                               :width 'normal
                               :powerline-scale 1.1))

;; start fullscreen
(add-to-list 'initial-frame-alist '(fullscreen . maximized))


;; If you use `org' and don't want your org files in the default location below,
;; change `org-directory'. It must be set before org loads!
(setq org-roam-directory "c:/data/org-mode/roam")
(setq org-roam-graph-executable "C:/Program Files/Graphviz/bin/dot.exe")
(setq org-directory "c:/data/org-mode/org")

(setq org-agenda-files (list org-directory))
(setq org-default-notes-file "refile.org")
(setq org-archive-location "archive.org::")
(setq org-refile-targets '((org-agenda-files :maxlevel . 3)))
(setq org-refile-allow-creating-parent-nodes 'confirm)
(setq org-capture-templates
        '(("t" "Todo" entry (file+headline "refile.org" "Todos")
        "* TODO %?\n%U")
        ("f" "Followup" entry (file+headline "refile.org" "Followup")
        "* TODO %?\n SCHEDULED: %^t")
        ("s" "Standup point" entry (file+headline "refile.org" "Standups")
        "* %? :standup:")
        ("r" "Retrospective point" entry (file+headline "refile.org" "Retrospective")
        "* %? :retrospective:")
        )
)

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
