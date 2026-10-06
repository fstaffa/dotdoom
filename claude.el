;;; claude.el --- Claude Code (claude-code.el) setup  -*- lexical-binding: t; -*-

;; Loaded from config.el.  Terminal backend setup (ghostel) stays in config.el.

(use-package! claude-code
  :after transient
  :defer t
  :config
  (setq claude-code-terminal-backend 'ghostel
        claude-code-toggle-auto-select t
        claude-code-display-window-fn
        (lambda (buffer)
          (display-buffer buffer '((display-buffer-reuse-window display-buffer-at-bottom)
                                   (window-height . 0.4))))
        claude-code-notification-function #'personal/claude-notify)
  (claude-code-mode)

  ;; Never ask for an instance name: "default" for the first one, then 2, 3, ...
  (define-advice claude-code--prompt-for-instance-name
      (:override (_dir existing-names &optional _force-prompt) personal/auto-name)
    (if (null existing-names)
        "default"
      (let ((n 2))
        (while (member (number-to-string n) existing-names) (cl-incf n))
        (number-to-string n)))))

(defun personal/claude-notify (title message)
  "Desktop notification when Claude is ready and its window isn't focused."
  (let ((project (or (ignore-errors (file-name-nondirectory
                                     (directory-file-name (claude-code--directory))))
                     "claude")))
    (message "%s: %s (%s)" title message project)
    (unless (claude-code--buffer-p (window-buffer (selected-window)))
      (condition-case err
          (progn (require 'notifications)
                 (notifications-notify :title title
                                       :body (format "%s (%s)" message project)
                                       :app-name "Emacs"))
        (error (message "Claude notification failed: %S" err))))
    (claude-code--pulse-modeline)))

(map! :leader
      :desc "Claude Code transient menu" "l c" #'claude-code-transient)

(map! "C-c c" #'claude-code-transient)

;; ESC leaves evil insert state, so Claude (interrupt) gets C-g instead.
(after! claude-code
  (add-hook 'claude-code-start-hook
            (defun personal/claude-send-escape-key ()
              (when (bound-and-true-p evil-local-mode)
                (evil-local-set-key 'insert (kbd "C-g") #'claude-code-send-escape)))))

(defun personal/claude--ensure-workspace ()
  "From the default workspace, switch to one named after the current project."
  (when (and (bound-and-true-p persp-mode)
             (equal (+workspace-current-name) +workspaces-main)
             (project-current))
    (+workspace-switch
     (file-name-nondirectory (directory-file-name (project-root (project-current))))
     t)))

(defun personal/claude-toggle ()
  "Start, show+focus, or hide the Claude session of the current project."
  (interactive)
  (require 'claude-code)
  (let* ((dir (claude-code--directory))
         (buf (car (claude-code--find-claude-buffers-for-directory dir)))
         (win (and buf (get-buffer-window buf))))
    (cond
     (win (cond ((not (eq win (selected-window))) (select-window win))
                ((cdr (window-list nil 'no-minibuf)) (delete-window win))
                (t (bury-buffer))))
     (buf (pop-to-buffer buf))
     (t (personal/claude--ensure-workspace)
        ;; The workspace switch changes the current buffer; keep the original dir.
        (let ((default-directory dir))
          (claude-code '(4)))
        (when-let ((new (car (claude-code--find-claude-buffers-for-directory dir))))
          (when (bound-and-true-p persp-mode)
            (persp-add-buffer new)))))))

(map! :leader
      (:prefix ("l" . "llm")
       :desc "Claude: toggle/start"    "l" #'personal/claude-toggle
       :desc "Claude: resume session"  "r" #'claude-code-resume
       :desc "Claude: cycle mode"      "m" #'claude-code-cycle-mode
       :desc "Claude: switch instance" "s" #'claude-code-switch-to-buffer
       :desc "Claude: toggle window"   "t" #'personal/claude-toggle
       :desc "Claude: send region"     "e" #'claude-code-send-region
       :desc "Claude: send file"       "f" #'claude-code-send-buffer-file
       :desc "Claude: send command"    "x" #'claude-code-send-command
       :desc "Claude: command + context" "X" #'claude-code-send-command-with-context
       :desc "Claude: fix error"       "E" #'claude-code-fix-error-at-point
       :desc "Claude: new worktree"    "w" #'personal/claude-worktree-new
       :desc "Claude: remove worktree" "W" #'personal/claude-worktree-remove))

;; ibuffer-like overview of all Claude sessions.
;; RET switch, p preview in side window, x kill, g refresh, q quit.
(defvar personal/claude-list-buffer "*Claude Sessions*")

(define-derived-mode personal/claude-list-mode tabulated-list-mode "Claude-Sessions"
  "Major mode listing all Claude Code sessions."
  (setq tabulated-list-format [("Project" 28 t) ("Instance" 10 t) ("State" 6 t) ("Directory" 0 t)]
        tabulated-list-padding 1
        tabulated-list-sort-key '("Project"))
  (add-hook 'tabulated-list-revert-hook #'personal/claude-list--refresh nil t)
  (add-hook 'post-command-hook #'personal/claude-list--auto-preview nil t)
  (add-hook 'kill-buffer-hook #'personal/claude-list--close-preview nil t)
  (tabulated-list-init-header))

(defvar-local personal/claude-list--previewed nil)

(defun personal/claude-list--auto-preview ()
  "Preview the session at point when the cursor moves to a different one."
  (let ((buf (tabulated-list-get-id)))
    (when (and (buffer-live-p buf) (not (eq buf personal/claude-list--previewed)))
      (setq personal/claude-list--previewed buf)
      (personal/claude-list-preview))))

(defun personal/claude-list--refresh ()
  (setq personal/claude-list--previewed nil) ; let auto-preview reopen after refresh/kill
  (setq tabulated-list-entries
        (mapcar
         (lambda (buf)
           (let* ((name (buffer-name buf))
                  (dir (or (claude-code--extract-directory-from-buffer-name name) ""))
                  (inst (or (claude-code--extract-instance-name-from-buffer-name name) "default"))
                  (busy (buffer-local-value 'ghostel--spinner-active buf)))
             (list buf (vector (file-name-nondirectory (directory-file-name dir))
                               inst
                               (if busy (propertize "busy" 'face 'warning) "idle")
                               (abbreviate-file-name dir)))))
         (claude-code--find-all-claude-buffers))))

(defun personal/claude-list--buffer ()
  (or (tabulated-list-get-id) (user-error "No session on this line")))

(defvar personal/claude-list--preview-window nil)

(defun personal/claude-list-switch ()
  "Go to the workspace holding the session at point and show it at the bottom."
  (interactive)
  (let* ((buf (personal/claude-list--buffer))
         (persp (and (bound-and-true-p persp-mode)
                     (seq-find (lambda (p) (persp-contain-buffer-p buf p))
                               (persp-persps))))
         (ws (and persp (safe-persp-name persp))))
    (quit-window t)
    (when (and ws (not (equal ws (+workspace-current-name))))
      (+workspace-switch ws))
    (let ((win (or (get-buffer-window buf)
                   (funcall claude-code-display-window-fn buf))))
      (select-window win))))

(defun personal/claude-list-preview ()
  "Show the session at point in a right side window without selecting it."
  (interactive)
  (setq personal/claude-list--preview-window
        (display-buffer (personal/claude-list--buffer)
                        '(display-buffer-in-side-window
                          (side . right) (window-width . 0.5) (slot . 0)))))

(defun personal/claude-list--close-preview ()
  (when (window-live-p personal/claude-list--preview-window)
    (ignore-errors (delete-window personal/claude-list--preview-window)))
  (setq personal/claude-list--preview-window nil
        personal/claude-list--previewed nil))

(defun personal/claude-list-quit ()
  (interactive)
  (quit-window t))

(defun personal/claude-list-kill ()
  (interactive)
  (let ((buf (personal/claude-list--buffer)))
    (when (y-or-n-p (format "Kill %s? " (buffer-name buf)))
      (claude-code--kill-buffer buf)
      (when (buffer-live-p buf) (kill-buffer buf))
      (tabulated-list-revert))))

(define-key personal/claude-list-mode-map (kbd "RET") #'personal/claude-list-switch)
(define-key personal/claude-list-mode-map (kbd "p") #'personal/claude-list-preview)
(define-key personal/claude-list-mode-map (kbd "q") #'personal/claude-list-quit)
(define-key personal/claude-list-mode-map (kbd "x") #'personal/claude-list-kill)
(after! evil
  (evil-define-key 'normal personal/claude-list-mode-map
    (kbd "RET") #'personal/claude-list-switch
    "p" #'personal/claude-list-preview
    "x" #'personal/claude-list-kill
    "gr" #'tabulated-list-revert
    "q" #'personal/claude-list-quit))

(defun personal/claude-list ()
  "List all Claude sessions."
  (interactive)
  (require 'claude-code)
  (with-current-buffer (get-buffer-create personal/claude-list-buffer)
    (personal/claude-list-mode)
    (personal/claude-list--refresh)
    (tabulated-list-print))
  (pop-to-buffer personal/claude-list-buffer))

(map! :leader :desc "Claude: list sessions" "l b" #'personal/claude-list)

;; Modeline: "claude[N]" with a "*" while any session shows ghostel progress.
(defun personal/claude-modeline ()
  (let ((bufs (and (featurep 'claude-code) (claude-code--find-all-claude-buffers))))
    (when bufs
      (let ((busy (seq-some (lambda (b) (buffer-local-value 'ghostel--spinner-active b)) bufs)))
        (propertize (format " claude[%d]%s" (length bufs) (if busy "*" ""))
                    'face (if busy 'warning 'shadow))))))
(after! doom-modeline
  (add-to-list 'global-mode-string '(:eval (personal/claude-modeline)) t))

;; Worktree workflow: one git worktree + one Doom workspace + one Claude
;; session per task. Worktrees live outside the repo (and outside the
;; projectile search path) in ~/data/worktrees/<repo>/<branch>/.
(defconst personal/worktree-root (expand-file-name "~/data/worktrees/"))

(defun personal/worktree--main-repo ()
  "Return the main checkout directory of the repo containing `default-directory'."
  (let ((common (magit-git-string "rev-parse" "--path-format=absolute" "--git-common-dir")))
    (unless common (user-error "Not in a git repository"))
    (file-name-as-directory (file-name-directory (directory-file-name common)))))

(defun personal/worktree--workspace-name (dir)
  "Doom workspace name (<repo>:<branch>) for worktree DIR."
  (let ((dir (directory-file-name dir)))
    (format "%s:%s"
            (file-name-nondirectory (directory-file-name (file-name-directory dir)))
            (file-name-nondirectory dir))))

(defun personal/claude-worktree-new (branch)
  "Create a git worktree for BRANCH, open it in its own workspace and start Claude."
  (interactive
   (list (let ((default-directory (personal/worktree--main-repo)))
           (replace-regexp-in-string
            "\\`origin/" ""
            (completing-read "Branch (existing or new): "
                             (delete-dups (append (magit-list-local-branch-names)
                                                  (magit-list-remote-branch-names "origin")))
                             nil nil)))))
  (when (or (string-empty-p branch) (string-prefix-p "-" branch))
    (user-error "Invalid branch name: %S" branch))
  (let* ((main (personal/worktree--main-repo))
         (repo (file-name-nondirectory (directory-file-name main)))
         (dir (file-name-as-directory
               (expand-file-name (replace-regexp-in-string "/" "-" branch)
                                 (expand-file-name repo personal/worktree-root))))
         (default-directory main)
         (ref-exists (lambda (ref)
                       (zerop (call-process "git" nil nil nil "show-ref" "--verify" "--quiet" ref)))))
    (if (file-exists-p dir)
        ;; Re-running after a failed start reuses the worktree, but only for the same
        ;; branch (`feature/x' and `feature-x' map to the same directory).
        (let ((current (let ((default-directory dir))
                         (string-trim (with-output-to-string
                                        (with-current-buffer standard-output
                                          (call-process "git" nil t nil "rev-parse" "--abbrev-ref" "HEAD")))))))
          (unless (equal current branch)
            (user-error "%s already exists on branch %s" dir current)))
      (make-directory (file-name-directory (directory-file-name dir)) t)
      (with-temp-buffer
        (unless (zerop (cond
                        ((funcall ref-exists (concat "refs/heads/" branch))
                         (call-process "git" nil t nil "worktree" "add" dir branch))
                        ((funcall ref-exists (concat "refs/remotes/origin/" branch))
                         (call-process "git" nil t nil "worktree" "add" "--track" "-b" branch
                                       dir (concat "origin/" branch)))
                        (t (call-process "git" nil t nil "worktree" "add" "-b" branch dir))))
          (user-error "git worktree add failed: %s" (string-trim (buffer-string))))))
    (+workspace-switch (personal/worktree--workspace-name dir) t)
    (let ((default-directory dir))
      (dired dir)
      (claude-code '(4)))))

(defun personal/claude-worktree-remove ()
  "Remove a worktree under `personal/worktree-root': Claude buffer, workspace, worktree."
  (interactive)
  (let* ((main (personal/worktree--main-repo))
         (default-directory main)
         (candidates (seq-filter
                      (lambda (p) (string-prefix-p personal/worktree-root p))
                      (mapcar (lambda (w) (expand-file-name (car w))) (magit-list-worktrees))))
         (dir (file-name-as-directory
               (or (and candidates (completing-read "Remove worktree: " candidates nil t))
                   (user-error "No worktrees under %s" personal/worktree-root))))
         (ws (personal/worktree--workspace-name dir)))
    (when (yes-or-no-p (format "Remove worktree %s and its workspace? " dir))
      ;; Remove the worktree first: if it is kept, the Claude session must survive.
      (with-temp-buffer
        (unless (zerop (call-process "git" nil t nil "worktree" "remove" dir))
          (if (yes-or-no-p (format "%s\nForce removal? " (string-trim (buffer-string))))
              (call-process "git" nil nil nil "worktree" "remove" "--force" dir)
            (user-error "Worktree kept"))))
      (require 'claude-code)
      (dolist (buf (claude-code--find-claude-buffers-for-directory dir))
        (claude-code--kill-buffer buf))
      (when (+workspace-exists-p ws)
        (+workspace/kill ws))
      (message "Removed worktree %s" dir))))

(provide 'claude)
