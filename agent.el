;;; agent.el --- agent-shell session management  -*- lexical-binding: t; -*-

;; Loaded from config.el.  The basic agent-shell setup (login, elicitation, TAB filter)
;; stays in config.el.  This file adds: full-window layout that restores the project
;; layout on leave, a session list ("control plane"), notifications, modeline,
;; next-waiting jump and the worktree workflow.

(defun personal/agent--buffer-p (buf)
  (and (buffer-live-p buf)
       (provided-mode-derived-p (buffer-local-value 'major-mode buf) 'agent-shell-mode)))

(defun personal/agent--dir (buf)
  "Directory the agent shell BUF works in."
  (with-current-buffer buf (file-name-as-directory (agent-shell-cwd))))

(defun personal/agent--buffers-for (dir)
  "Agent shells working in DIR, most recently used first."
  (let ((dir (file-name-as-directory (expand-file-name dir))))
    (seq-filter (lambda (b) (equal (personal/agent--dir b) dir)) (agent-shell-buffers))))

(defvar-local personal/agent--unseen nil
  "Non-nil when this shell finished a turn while it wasn't focused.")

(defun personal/agent--status (buf)
  "Status of shell BUF: `blocked', `busy', `done' (finished, unseen) or `idle'."
  (let ((s (condition-case nil (agent-shell-status :shell-buffer buf) (error 'ready))))
    (cond ((eq s 'blocked) 'blocked)
          ((eq s 'busy) 'busy)
          ((buffer-local-value 'personal/agent--unseen buf) 'done)
          (t 'idle))))

(defun personal/agent--status-string (buf)
  (pcase (personal/agent--status buf)
    ('blocked (propertize "blocked" 'face 'error))
    ('busy (propertize "busy" 'face 'warning))
    ('done (propertize "done" 'face 'success))
    (_ (propertize "idle" 'face 'shadow))))

;; Full-window layout: showing a session saves the workspace's window layout and
;; leaving restores it.  Layouts are kept per workspace name.
(defvar personal/agent--layouts (make-hash-table :test 'equal))

(defun personal/agent--ws ()
  (if (bound-and-true-p persp-mode) (+workspace-current-name) "none"))

(defun personal/agent--full-p ()
  "Non-nil when the frame shows a single agent shell window."
  (and (one-window-p t)
       (personal/agent--buffer-p (window-buffer (selected-window)))))

(defun personal/agent--display (buffer &optional _alist)
  "Display action: show BUFFER alone in the frame, saving the current layout first."
  (unless (personal/agent--full-p)
    (puthash (personal/agent--ws) (window-state-get (frame-root-window))
             personal/agent--layouts))
  (let ((ignore-window-parameters t))
    (delete-other-windows))
  (let ((win (selected-window)))
    (set-window-dedicated-p win nil)
    (set-window-buffer win buffer)
    win))

(defun personal/agent--display-file (buffer &optional alist)
  "Display action for files opened from a shell: restore the project layout, then open."
  (personal/agent-leave)
  (display-buffer-same-window buffer alist))

(defun personal/agent-leave ()
  "Restore the window layout the workspace had before the agent shell took over."
  (interactive)
  (let* ((ws (personal/agent--ws))
         (state (gethash ws personal/agent--layouts)))
    (cond (state (remhash ws personal/agent--layouts)
                 (window-state-put state (frame-root-window)))
          ((personal/agent--buffer-p (current-buffer)) (bury-buffer)))))

(defun personal/agent--show (buf)
  "Show and focus BUF full window (a no-op if it already is)."
  (with-current-buffer buf (setq personal/agent--unseen nil))
  (if (and (personal/agent--full-p) (eq (window-buffer (selected-window)) buf))
      (selected-window)
    (select-window (personal/agent--display buf))))

(defun personal/agent--workspace-of (buf)
  (when-let* (((bound-and-true-p persp-mode))
              (persp (seq-find (lambda (p) (persp-contain-buffer-p buf p)) (persp-persps))))
    (safe-persp-name persp)))

(defun personal/agent--goto (buf)
  "Go to the workspace holding BUF and show it."
  (let ((ws (personal/agent--workspace-of buf)))
    (when (and ws (not (equal ws (+workspace-current-name))))
      (+workspace-switch ws))
    (personal/agent--show buf)))

(defun personal/agent--ensure-workspace ()
  "From the default workspace, switch to one named after the current project."
  (when (and (bound-and-true-p persp-mode)
             (equal (+workspace-current-name) +workspaces-main)
             (project-current))
    (+workspace-switch
     (file-name-nondirectory (directory-file-name (project-root (project-current))))
     t)))

(defvar agent-shell-context-sources)

(defun personal/agent-start (&optional dir session-strategy)
  "Start a Claude agent shell in DIR (default: current project).
SESSION-STRATEGY overrides `agent-shell-session-strategy' (e.g. `prompt' to resume)."
  (interactive)
  (require 'agent-shell)
  (let ((dir (or dir (agent-shell-cwd))))
    (personal/agent--ensure-workspace)
    (let ((default-directory dir)
          (agent-shell-session-strategy (or session-strategy agent-shell-session-strategy)))
      (agent-shell-anthropic-start-claude-code))))

(defun personal/agent-start-bare ()
  "Start a Claude agent shell without inserting region/file/line context."
  (interactive)
  (require 'agent-shell) ; must be loaded first so the variable is dynamically bound
  (let ((agent-shell-context-sources nil))
    (personal/agent-start)))

(defun personal/agent-resume ()
  "Start a Claude agent shell and pick a past session to resume."
  (interactive)
  (personal/agent-start nil 'prompt))

(defun personal/agent-toggle ()
  "Leave the agent shell, or show/start the one of the current project."
  (interactive)
  (require 'agent-shell)
  (if (personal/agent--buffer-p (current-buffer))
      (personal/agent-leave)
    (let* ((dir (agent-shell-cwd))
           (buf (car (personal/agent--buffers-for dir))))
      (if buf (personal/agent--show buf) (personal/agent-start dir)))))

(defun personal/agent-switch ()
  "Pick any agent shell and show it."
  (interactive)
  (require 'agent-shell)
  (let* ((bufs (agent-shell-buffers))
         (names (mapcar #'buffer-name bufs)))
    (unless bufs (user-error "No agent shells"))
    (personal/agent--goto
     (get-buffer (completing-read "Agent shell: " names nil t)))))

;; Notifications, modeline and refreshing the list on shell events.
(defvar personal/agent-list-buffer "*Agent Sessions*")
(defvar personal/agent--refresh-timer nil)

(defun personal/agent--project-name (buf)
  (let ((dir (personal/agent--dir buf)))
    (if (string-prefix-p personal/worktree-root dir)
        (personal/worktree--workspace-name dir)
      (file-name-nondirectory (directory-file-name dir)))))

(defun personal/agent--changed ()
  "Update the modeline and (debounced) the session list."
  (force-mode-line-update t)
  (unless personal/agent--refresh-timer
    (setq personal/agent--refresh-timer
          (run-at-time 0.2 nil
                       (lambda ()
                         (setq personal/agent--refresh-timer nil)
                         (when-let* ((b (get-buffer personal/agent-list-buffer)))
                           (with-current-buffer b (tabulated-list-revert))))))))

(defun personal/agent--notify (buf message)
  (unless (eq (window-buffer (selected-window)) buf)
    (condition-case err
        (progn (require 'notifications)
               (notifications-notify :title (format "Agent: %s" (personal/agent--project-name buf))
                                     :body message :app-name "Emacs"))
      (error (message "Agent notification failed: %S" err)))))

(defun personal/agent--on-event (buf event)
  (when (buffer-live-p buf)
    (pcase (map-elt event :event)
      ((or 'agent-message-chunk 'tool-call-update) nil)
      ((or 'permission-request 'elicitation-request)
       (personal/agent--notify buf "Needs your input")
       (personal/agent--changed))
      ('turn-complete
       (unless (eq (window-buffer (selected-window)) buf)
         (with-current-buffer buf (setq personal/agent--unseen t)))
       (personal/agent--notify buf "Finished")
       (personal/agent--changed))
      (_ (personal/agent--changed)))))

(defun personal/agent--setup-buffer ()
  "Hook for `agent-shell-mode-hook': workspace membership and event subscription."
  (when (bound-and-true-p persp-mode)
    (persp-add-buffer (current-buffer)))
  (let ((buf (current-buffer)))
    (agent-shell-subscribe-to :shell-buffer buf
                              :on-event (lambda (event) (personal/agent--on-event buf event)))))

(add-hook 'window-selection-change-functions
          (lambda (_)
            (let ((b (window-buffer)))
              (when (and (personal/agent--buffer-p b) (buffer-local-value 'personal/agent--unseen b))
                (with-current-buffer b (setq personal/agent--unseen nil))
                (personal/agent--changed)))))

(after! agent-shell
  (setq agent-shell-session-strategy 'new
        ;; replay the whole conversation on resume (default `minimal' shows only the title)
        agent-shell-session-restore-verbosity 'full
        agent-shell-display-action '(personal/agent--display)
        agent-shell-file-display-action '(personal/agent--display-file))
  ;; Evil's insert-state C-v is quoted-insert; use it to paste (images too) like a GUI app.
  (evil-define-key* 'insert agent-shell-mode-map (kbd "C-v") #'agent-shell-yank-dwim)
  (add-hook 'agent-shell-mode-hook #'personal/agent--setup-buffer)
  (add-hook 'kill-buffer-hook
            (defun personal/agent--killed ()
              (when (derived-mode-p 'agent-shell-mode)
                (run-at-time 0.1 nil #'personal/agent--changed)))))

(defun personal/agent-modeline ()
  "\" agent[N]\" plus counts of blocked (!), busy (*) and unseen finished (+) shells."
  (let ((bufs (and (featurep 'agent-shell) (agent-shell-buffers))))
    (when bufs
      (let* ((st (mapcar #'personal/agent--status bufs))
             (blocked (seq-count (lambda (s) (eq s 'blocked)) st))
             (busy (seq-count (lambda (s) (eq s 'busy)) st))
             (done (seq-count (lambda (s) (eq s 'done)) st)))
        (propertize (format " agent[%d]%s%s%s" (length bufs)
                            (if (> blocked 0) (format " !%d" blocked) "")
                            (if (> busy 0) (format " *%d" busy) "")
                            (if (> done 0) (format " +%d" done) ""))
                    'face (cond ((> blocked 0) 'error) ((> busy 0) 'warning)
                                ((> done 0) 'success) (t 'shadow)))))))
(after! doom-modeline
  (add-to-list 'global-mode-string '(:eval (personal/agent-modeline)) t))

(defun personal/agent-next-waiting ()
  "Go to the next shell that needs input, else the next that finished unseen."
  (interactive)
  (require 'agent-shell)
  (let* ((bufs (seq-remove (lambda (b) (eq b (current-buffer))) (agent-shell-buffers)))
         (target (or (seq-find (lambda (b) (eq (personal/agent--status b) 'blocked)) bufs)
                     (seq-find (lambda (b) (eq (personal/agent--status b) 'done)) bufs))))
    (if target (personal/agent--goto target) (message "No agent needs attention"))))

;; Overview of all agent shells.  RET go, x kill, gr refresh, q quit.
(define-derived-mode personal/agent-list-mode tabulated-list-mode "Agent-Sessions"
  "Major mode listing all agent shell sessions."
  (setq tabulated-list-format [("Project" 28 t) ("Status" 8 t) ("Title" 44 t) ("Directory" 0 t)]
        tabulated-list-padding 1
        tabulated-list-sort-key '("Project"))
  (add-hook 'tabulated-list-revert-hook #'personal/agent-list--refresh nil t)
  (tabulated-list-init-header))

(defun personal/agent-list--refresh ()
  (setq tabulated-list-entries
        (mapcar
         (lambda (buf)
           (list buf (vector (personal/agent--project-name buf)
                             (personal/agent--status-string buf)
                             (or (ignore-errors
                                   (map-nested-elt (buffer-local-value 'agent-shell--state buf)
                                                   '(:session :title)))
                                 "")
                             (abbreviate-file-name (personal/agent--dir buf)))))
         (agent-shell-buffers))))

(defun personal/agent-list--buffer ()
  (or (tabulated-list-get-id) (user-error "No session on this line")))

(defun personal/agent-list-switch ()
  "Go to the workspace of the session at point and show it."
  (interactive)
  (let ((buf (personal/agent-list--buffer)))
    (quit-window t)
    (personal/agent--goto buf)))

(defun personal/agent-list-kill ()
  (interactive)
  (let ((buf (personal/agent-list--buffer)))
    (when (y-or-n-p (format "Kill %s? " (buffer-name buf)))
      (kill-buffer buf)
      (tabulated-list-revert))))

(define-key personal/agent-list-mode-map (kbd "RET") #'personal/agent-list-switch)
(define-key personal/agent-list-mode-map (kbd "x") #'personal/agent-list-kill)
(define-key personal/agent-list-mode-map (kbd "q") #'quit-window)
(after! evil
  (evil-define-key 'normal personal/agent-list-mode-map
    (kbd "RET") #'personal/agent-list-switch
    "x" #'personal/agent-list-kill
    "gr" #'tabulated-list-revert
    "q" #'quit-window))

(defun personal/agent-list ()
  "List all agent shell sessions."
  (interactive)
  (require 'agent-shell)
  (with-current-buffer (get-buffer-create personal/agent-list-buffer)
    (personal/agent-list-mode)
    (personal/agent-list--refresh)
    (tabulated-list-print))
  (pop-to-buffer personal/agent-list-buffer))

(map! :leader
      (:prefix ("l" . "llm")
       :desc "Agent: toggle/start"     "l" #'personal/agent-toggle
       :desc "Agent: toggle"           "t" #'personal/agent-toggle
       :desc "Agent: new session"      "a" #'personal/agent-start
       :desc "Agent: new (no context)" "A" #'personal/agent-start-bare
       :desc "Agent: resume session"   "r" #'personal/agent-resume
       :desc "Agent: clear (restart)"  "c" #'agent-shell-restart
       :desc "Agent: switch session"   "s" #'personal/agent-switch
       :desc "Agent: list sessions"    "b" #'personal/agent-list
       :desc "Agent: next waiting"     "n" #'personal/agent-next-waiting
       :desc "Agent: send region"      "e" #'agent-shell-send-region
       :desc "Agent: send file"        "f" #'agent-shell-send-file
       :desc "Agent: new worktree"     "w" #'personal/agent-worktree-new
       :desc "Agent: remove worktree"  "W" #'personal/agent-worktree-remove
       :desc "Agent: list worktrees"   "g" #'personal/worktree-list))

;; Worktree workflow: one git worktree + one Doom workspace + one agent
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

(defun personal/agent-worktree-new (branch)
  "Create a git worktree for BRANCH, open it in its own workspace and start an agent shell."
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
      (personal/agent-start dir))))

(defun personal/agent-worktree-remove ()
  "Remove a worktree under `personal/worktree-root': Agent buffer, workspace, worktree."
  (interactive)
  (let* ((main (personal/worktree--main-repo))
         (default-directory main)
         (candidates (seq-filter
                      (lambda (p) (string-prefix-p personal/worktree-root p))
                      (mapcar (lambda (w) (expand-file-name (car w))) (magit-list-worktrees))))
         (dir (file-name-as-directory
               (or (and candidates (completing-read "Remove worktree: " candidates nil t))
                   (user-error "No worktrees under %s" personal/worktree-root)))))
    (when (yes-or-no-p (format "Remove worktree %s and its workspace? " dir))
      (personal/worktree--remove dir))))

(defun personal/worktree--remove (dir)
  "Remove worktree DIR: git worktree, Agent buffers and Doom workspace.
Asks for a forced removal if git refuses (e.g. dirty tree)."
  (let ((ws (personal/worktree--workspace-name dir))
        (default-directory (let ((default-directory dir)) (personal/worktree--main-repo))))
    ;; Remove the worktree first: if it is kept, the agent session must survive.
    (with-temp-buffer
      (unless (zerop (call-process "git" nil t nil "worktree" "remove" dir))
        (if (yes-or-no-p (format "%s\nForce removal? " (string-trim (buffer-string))))
            (call-process "git" nil nil nil "worktree" "remove" "--force" dir)
          (user-error "Worktree kept"))))
    (require 'agent-shell)
    (dolist (buf (personal/agent--buffers-for dir))
      (kill-buffer buf))
    (when (+workspace-exists-p ws)
      (+workspace/kill ws))
    (message "Removed worktree %s" dir)))

;; Overview of all worktrees under `personal/worktree-root'.
;; RET switch, d delete, D delete all final (MR merged/closed), f/F fetch
;; (at point / all), m magit-status, gr refresh (incl. MR lookup), q quit.
(defvar personal/worktree-list-buffer "*Agent Worktrees*")
(defvar personal/worktree-list--rows nil "Alist of (DIR . INFO-plist), see `personal/worktree--info'.")
(defvar personal/worktree-list--mr (make-hash-table :test 'equal)
  "DIR -> MR plist (:state :iid :url), `none', `error' or `loading'.")

(defun personal/worktree--git (dir &rest args)
  "Run git ARGS in DIR; return trimmed stdout, or nil on non-zero exit."
  (let ((default-directory dir))
    (with-temp-buffer
      (when (zerop (apply #'call-process "git" nil '(t nil) nil args))
        (string-trim (buffer-string))))))

(defun personal/worktree--info (dir)
  "Local git state of worktree DIR as a plist."
  (let* ((branch (personal/worktree--git dir "rev-parse" "--abbrev-ref" "HEAD"))
         (base (seq-find (lambda (r) (personal/worktree--git dir "rev-parse" "--verify" "-q" r))
                         '("refs/remotes/origin/master" "refs/remotes/origin/main")))
         (counts (and base (split-string
                            (or (personal/worktree--git dir "rev-list" "--left-right" "--count"
                                                        (concat base "...HEAD"))
                                "")
                            "[ \t]+" t)))
         (behind (and (= (length counts) 2) (string-to-number (car counts))))
         (ahead (and behind (string-to-number (cadr counts))))
         (remote (and branch (concat "refs/remotes/origin/" branch)))
         (pushed (and remote (personal/worktree--git dir "rev-parse" "--verify" "-q" remote)))
         (unpushed (and pushed
                        (string-to-number
                         (or (personal/worktree--git dir "rev-list" "--count" (concat remote "..HEAD"))
                             "0"))))
         (dirty (not (string-empty-p (or (personal/worktree--git dir "status" "--porcelain") ""))))
         ;; Dry-run merge of origin/master into HEAD; exit status 1 means conflicts.
         (conflicts (and behind (> behind 0)
                         (let ((default-directory dir))
                           (eql 1 (call-process "git" nil nil nil "merge-tree" "--write-tree"
                                                "--no-messages" "HEAD" base))))))
    (list :repo (file-name-nondirectory (directory-file-name (file-name-directory (directory-file-name dir))))
          :branch (or branch "?")
          :base (and base (string-remove-prefix "refs/remotes/" base))
          :behind behind :ahead ahead
          :pushed (and pushed t) :unpushed unpushed
          :dirty dirty :conflicts conflicts)))

(defun personal/worktree-list--collect ()
  (setq personal/worktree-list--rows
        (mapcar (lambda (dir) (cons dir (personal/worktree--info dir)))
                (seq-filter (lambda (d) (file-exists-p (expand-file-name ".git" d)))
                            (mapcar #'file-name-as-directory
                                    (file-expand-wildcards (concat personal/worktree-root "*/*/")))))))

(defun personal/worktree-list--mr-state (dir)
  (let ((mr (gethash dir personal/worktree-list--mr)))
    (and (listp mr) (plist-get mr :state))))

(defun personal/worktree-list--final-p (dir)
  (member (personal/worktree-list--mr-state dir) '("merged" "closed")))

(defun personal/worktree-list--entries ()
  (mapcar
   (lambda (row)
     (let* ((dir (car row)) (i (cdr row))
            (mr (gethash dir personal/worktree-list--mr))
            (mr-state (personal/worktree-list--mr-state dir))
            (state (cond ((personal/worktree-list--final-p dir) (propertize "final" 'face 'success))
                         ((equal mr-state "opened") "MR")
                         ((plist-get i :pushed) "remote")
                         (t (propertize "local" 'face 'shadow))))
            (mr-col (cond ((eq mr 'loading) (propertize "…" 'face 'shadow))
                          ((eq mr 'error) (propertize "?" 'face 'warning))
                          ((listp mr)
                           (if mr (format "!%s %s" (plist-get mr :iid)
                                          (if (equal mr-state "opened") "open" mr-state))
                             "-"))
                          (t "-")))
            (behind (plist-get i :behind)) (ahead (plist-get i :ahead))
            (vs (cond ((plist-get i :conflicts)
                       (propertize (format "CONFLICTS (behind %d)" behind) 'face 'error))
                      ((null behind) "?")
                      ((and (> behind 0) (> ahead 0)) (format "+%d -%d" ahead behind))
                      ((> behind 0) (propertize (format "behind %d" behind) 'face 'warning))
                      ((> ahead 0) (format "ahead %d" ahead))
                      (t "up to date")))
            (agent (and (featurep 'agent-shell)
                        (car (personal/agent--buffers-for dir)))))
       (list dir (vector (plist-get i :repo) (plist-get i :branch) state mr-col vs
                         (concat (if (plist-get i :dirty) "dirty" "")
                                 (if (> (or (plist-get i :unpushed) 0) 0)
                                     (format " ↑%d unpushed" (plist-get i :unpushed)) ""))
                         (if agent (personal/agent--status-string agent) "")))))
   personal/worktree-list--rows))

(define-derived-mode personal/worktree-list-mode tabulated-list-mode "Agent-Worktrees"
  "Major mode listing all worktrees under `personal/worktree-root'."
  (setq tabulated-list-format [("Repo" 22 t) ("Branch" 36 t) ("State" 7 t) ("MR" 12 t)
                               ("vs origin/master" 22 t) ("Local" 18 t) ("Agent" 0 t)]
        tabulated-list-padding 1
        tabulated-list-sort-key '("Repo"))
  (add-hook 'tabulated-list-revert-hook
            (lambda () (setq tabulated-list-entries (personal/worktree-list--entries)))
            nil t)
  (tabulated-list-init-header))

(defun personal/worktree-list--redraw ()
  (when-let* ((buf (get-buffer personal/worktree-list-buffer)))
    (with-current-buffer buf (tabulated-list-revert))))

(defun personal/worktree-list--dir ()
  (or (tabulated-list-get-id) (user-error "No worktree on this line")))

(defun personal/worktree-list--query-mr (dir branch)
  "Asynchronously look up the MR for BRANCH of worktree DIR with glab."
  (puthash dir 'loading personal/worktree-list--mr)
  (let ((default-directory dir)
        (buf (generate-new-buffer " *glab-mr*")))
    (make-process
     :name "glab-mr" :buffer buf :noquery t
     :command (list "sh" "-c" "exec glab mr list --all --source-branch=\"$1\" -F json 2>/dev/null"
                    "sh" branch)
     :sentinel
     (lambda (proc _)
       (unless (process-live-p proc)
         (puthash dir
                  (with-current-buffer buf
                    (condition-case nil
                        (let* ((mrs (and (zerop (process-exit-status proc))
                                         (json-parse-string (buffer-string) :object-type 'plist
                                                            :array-type 'list)))
                               (mr (or (seq-find (lambda (m) (equal (plist-get m :state) "opened")) mrs)
                                       (car mrs))))
                          (if (and (listp mrs) (zerop (process-exit-status proc)))
                              (and mr (list :state (plist-get mr :state) :iid (plist-get mr :iid)
                                            :url (plist-get mr :web_url)))
                            'error))
                      (error 'error)))
                  personal/worktree-list--mr)
         (kill-buffer buf)
         (personal/worktree-list--redraw))))))

(defun personal/worktree-list-refresh ()
  "Re-read local state and re-query MRs."
  (interactive)
  (personal/worktree-list--collect)
  (dolist (row personal/worktree-list--rows)
    (personal/worktree-list--query-mr (car row) (plist-get (cdr row) :branch)))
  (personal/worktree-list--redraw))

(defun personal/worktree-list--fetch (dirs)
  "Run `git fetch origin' once per repo of worktrees DIRS, then redraw."
  (let ((repos (delete-dups
                (delq nil (mapcar (lambda (d)
                                    (personal/worktree--git
                                     d "rev-parse" "--path-format=absolute" "--git-common-dir"))
                                  dirs))))
        (pending 0))
    (unless repos (user-error "Nothing to fetch"))
    (setq pending (length repos))
    (dolist (repo repos)
      (let ((default-directory (file-name-directory (directory-file-name repo)))
            (buf (generate-new-buffer " *git-fetch*")))
        (make-process
         :name "git-fetch" :buffer buf :noquery t :command '("git" "fetch" "origin")
         :sentinel
         (lambda (proc _)
           (unless (process-live-p proc)
             (unless (zerop (process-exit-status proc))
               (message "git fetch failed in %s: %s" repo
                        (string-trim (with-current-buffer buf (buffer-string)))))
             (kill-buffer buf)
             (when (zerop (cl-decf pending))
               (personal/worktree-list--collect)
               (personal/worktree-list--redraw)
               (message "Fetched %d repo(s)" (length repos))))))))
    (message "Fetching %d repo(s)..." (length repos))))

(defun personal/worktree-list-fetch ()
  "Fetch the repo of the worktree at point."
  (interactive)
  (personal/worktree-list--fetch (list (personal/worktree-list--dir))))

(defun personal/worktree-list-fetch-all ()
  "Fetch every repo that has a worktree."
  (interactive)
  (personal/worktree-list--fetch (mapcar #'car personal/worktree-list--rows)))

(defun personal/worktree-list--warnings (dir)
  "Human-readable reasons why deleting DIR could lose work."
  (let ((i (cdr (assoc dir personal/worktree-list--rows))))
    (delq nil
          (list (and (plist-get i :dirty) "uncommitted changes")
                (and (> (or (plist-get i :unpushed) 0) 0)
                     (format "%d unpushed commit(s)" (plist-get i :unpushed)))
                (and (not (plist-get i :pushed))
                     (not (personal/worktree-list--final-p dir))
                     (> (or (plist-get i :ahead) 0) 0)
                     "branch never pushed")))))

(defun personal/worktree-list-delete ()
  "Delete the worktree at point (folder, Agent buffer, workspace); keeps the branch."
  (interactive)
  (let* ((dir (personal/worktree-list--dir))
         (warn (personal/worktree-list--warnings dir)))
    (when (yes-or-no-p (format "Delete %s%s? "
                               dir (if warn (format " [WARNING: %s]" (string-join warn ", ")) "")))
      (personal/worktree--remove dir)
      (personal/worktree-list-refresh))))

(defun personal/worktree-list-delete-final ()
  "Delete all worktrees whose MR is merged or closed."
  (interactive)
  (let ((dirs (seq-filter #'personal/worktree-list--final-p (mapcar #'car personal/worktree-list--rows))))
    (unless dirs (user-error "No final worktrees (MR info may still be loading)"))
    (when (yes-or-no-p
           (format "Delete %d final worktree(s)?\n%s\n"
                   (length dirs)
                   (mapconcat (lambda (d)
                                (let ((w (personal/worktree-list--warnings d)))
                                  (format "  %s%s" (abbreviate-file-name d)
                                          (if w (format "  [WARNING: %s]" (string-join w ", ")) ""))))
                              dirs "\n")))
      (dolist (d dirs)
        (condition-case err (personal/worktree--remove d)
          (user-error (message "%s" (error-message-string err)))))
      (personal/worktree-list-refresh))))

(defun personal/worktree-list-switch ()
  "Switch to the Doom workspace of the worktree at point (created if missing)."
  (interactive)
  (let* ((dir (personal/worktree-list--dir))
         (ws (personal/worktree--workspace-name dir))
         (new (not (+workspace-exists-p ws))))
    (quit-window t)
    (+workspace-switch ws t)
    (when new (dired dir))))

(defun personal/worktree-list-magit ()
  "Open magit-status for the worktree at point."
  (interactive)
  (magit-status (personal/worktree-list--dir)))

(defun personal/worktree-list-open-mr ()
  "Open the MR of the worktree at point in the browser."
  (interactive)
  (let ((mr (gethash (personal/worktree-list--dir) personal/worktree-list--mr)))
    (if (and (listp mr) (plist-get mr :url))
        (browse-url (plist-get mr :url))
      (user-error "No MR known for this worktree"))))

(defun personal/worktree-list--rebase (dir)
  "Rebase worktree DIR onto its base ref. Return nil on success, else an error string.
Aborts the rebase if it fails."
  (let* ((i (cdr (assoc dir personal/worktree-list--rows)))
         (base (plist-get i :base))
         (default-directory dir))
    (cond ((not base) "no origin/master")
          ((plist-get i :dirty) "uncommitted changes")
          ((plist-get i :conflicts) "would conflict")
          (t (with-temp-buffer
               (if (zerop (call-process "git" nil t nil "rebase" base))
                   nil
                 (call-process "git" nil nil nil "rebase" "--abort")
                 (string-trim (buffer-string))))))))

(defun personal/worktree-list-rebase ()
  "Rebase the worktree at point onto origin/master (refused if dirty or conflicting)."
  (interactive)
  (let* ((dir (personal/worktree-list--dir))
         (err (personal/worktree-list--rebase dir)))
    (personal/worktree-list-refresh)
    (if err (user-error "Not rebased: %s" err) (message "Rebased %s" (abbreviate-file-name dir)))))

(defun personal/worktree-list-rebase-all ()
  "Rebase all behind, clean, non-final, conflict-free worktrees onto origin/master."
  (interactive)
  (let ((dirs (seq-filter
               (lambda (d)
                 (let ((i (cdr (assoc d personal/worktree-list--rows))))
                   (and (> (or (plist-get i :behind) 0) 0)
                        (not (plist-get i :conflicts))
                        (not (plist-get i :dirty))
                        (not (personal/worktree-list--final-p d)))))
               (mapcar #'car personal/worktree-list--rows))))
    (unless dirs (user-error "Nothing to rebase"))
    (when (yes-or-no-p (format "Rebase %d worktree(s) onto origin/master?\n%s\n"
                               (length dirs)
                               (mapconcat (lambda (d) (concat "  " (abbreviate-file-name d))) dirs "\n")))
      (let (failed)
        (dolist (d dirs)
          (when-let* ((err (personal/worktree-list--rebase d)))
            (push (format "%s: %s" (abbreviate-file-name d) err) failed)))
        (personal/worktree-list-refresh)
        (message "Rebased %d, failed %d%s" (- (length dirs) (length failed)) (length failed)
                 (if failed (concat "\n" (string-join failed "\n")) ""))))))

(defun personal/worktree-list-quit ()
  (interactive)
  (quit-window t))

(require 'transient) ; the macro must be available when this file is loaded
(transient-define-prefix personal/worktree-list-menu ()
  "Worktree list actions."
  [["Go"
    ("RET" "Switch workspace" personal/worktree-list-switch)
    ("m" "Magit status" personal/worktree-list-magit)
    ("o" "Open MR in browser" personal/worktree-list-open-mr)]
   ["Git"
    ("f" "Fetch repo at point" personal/worktree-list-fetch)
    ("F" "Fetch all repos" personal/worktree-list-fetch-all)
    ("r" "Rebase at point" personal/worktree-list-rebase)
    ("R" "Rebase all clean" personal/worktree-list-rebase-all)
    ("g" "Refresh (incl. MRs)" personal/worktree-list-refresh)]
   ["Delete"
    ("d" "Delete at point" personal/worktree-list-delete)
    ("D" "Delete all final" personal/worktree-list-delete-final)]])

(dolist (b '(("RET" . personal/worktree-list-switch) ("d" . personal/worktree-list-delete)
             ("D" . personal/worktree-list-delete-final) ("f" . personal/worktree-list-fetch)
             ("F" . personal/worktree-list-fetch-all) ("m" . personal/worktree-list-magit)
             ("o" . personal/worktree-list-open-mr) ("r" . personal/worktree-list-rebase)
             ("R" . personal/worktree-list-rebase-all)
             ("?" . personal/worktree-list-menu) ("q" . personal/worktree-list-quit)))
  (define-key personal/worktree-list-mode-map (kbd (car b)) (cdr b)))
(after! evil
  (evil-define-key 'normal personal/worktree-list-mode-map
    (kbd "RET") #'personal/worktree-list-switch
    "d" #'personal/worktree-list-delete
    "D" #'personal/worktree-list-delete-final
    "f" #'personal/worktree-list-fetch
    "F" #'personal/worktree-list-fetch-all
    "m" #'personal/worktree-list-magit
    "o" #'personal/worktree-list-open-mr
    "r" #'personal/worktree-list-rebase
    "R" #'personal/worktree-list-rebase-all
    "gr" #'personal/worktree-list-refresh
    "?" #'personal/worktree-list-menu
    "q" #'personal/worktree-list-quit))
(define-key personal/worktree-list-mode-map (kbd "g") #'personal/worktree-list-refresh)

(defun personal/worktree-list ()
  "List all worktrees with their git/MR state."
  (interactive)
  (require 'agent-shell)
  (with-current-buffer (get-buffer-create personal/worktree-list-buffer)
    (personal/worktree-list-mode)
    (personal/worktree-list--collect)
    (setq tabulated-list-entries (personal/worktree-list--entries))
    (tabulated-list-print))
  (pop-to-buffer personal/worktree-list-buffer)
  (personal/worktree-list-refresh)
  (message "? for menu"))

(provide 'agent)
