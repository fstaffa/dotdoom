(package! key-chord)
(package! jq-mode)
(package! kubernetes)
(package! kubernetes-evil)
(package! nvm :pin "c214762")

(package! f)
(package! org-super-agenda)
(package! org-ql)
(package! magit-delta)

(package! chatgpt-shell)

(unpin! lsp-mode)

(package! exercism)
(package! lab
  :recipe (:host github :repo "isamert/lab.el"))

(package! copilot
  :recipe (:host github :repo "zerolfx/copilot.el" :files ("*.el" "dist")))

;; add package command-log-mode from github
(package! command-log-mode
  :recipe (:host github :repo "lewang/command-log-mode"))

(package! treesit-auto)
(package! astro-ts-mode)
(package! hyperbole)
(package! lsp-tailwindcss :recipe (:host github :repo "merrickluo/lsp-tailwindcss"))
(package! prodigy :recipe (:host github :repo "rejeep/prodigy.el"))
