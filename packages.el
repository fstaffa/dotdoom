(package! nerd-icons-corfu)
(package! key-chord)
(package! jq-mode)
(package! kubernetes)
(package! kubernetes-evil)
(package! nvm :pin "c214762")

(package! f)
(package! org-super-agenda)
(package! org-ql)
(package! denote)
(package! denote-journal)
(package! denote-org)
(package! consult-denote)
(package! magit-delta)

(unpin! lsp-mode)

(package! exercism)
(package! promise)
(package! iter2)
(package! async-await)
(package! lab
  :recipe (:host github :repo "isamert/lab.el"))

;; add package command-log-mode from github
(package! command-log-mode
  :recipe (:host github :repo "lewang/command-log-mode"))

(package! hyperbole)
(package! lsp-tailwindcss :recipe (:host github :repo "merrickluo/lsp-tailwindcss"))
(package! prodigy :recipe (:host github :repo "rejeep/prodigy.el"))
(package! majutsu :recipe (:host github :repo "0WD0/majutsu"))
(package! claude-code :recipe (:host github :repo "stevemolitor/claude-code.el"))
(package! ghostel)
(package! evil-ghostel)
