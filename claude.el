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
                   (user-error "No worktrees under %s" personal/worktree-root)))))
    (when (yes-or-no-p (format "Remove worktree %s and its workspace? " dir))
      (personal/worktree--remove dir))))

(defun personal/worktree--remove (dir)
  "Remove worktree DIR: git worktree, Claude buffers and Doom workspace.
Asks for a forced removal if git refuses (e.g. dirty tree)."
  (let ((ws (personal/worktree--workspace-name dir))
        (default-directory (let ((default-directory dir)) (personal/worktree--main-repo))))
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
    (message "Removed worktree %s" dir)))

;; Overview of all worktrees under `personal/worktree-root'.
;; RET switch, d delete, D delete all final (MR merged/closed), f/F fetch
;; (at point / all), m magit-status, gr refresh (incl. MR lookup), q quit.
(defvar personal/worktree-list-buffer "*Claude Worktrees*")
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
            (claude (length (and (featurep 'claude-code)
                                 (claude-code--find-claude-buffers-for-directory dir)))))
       (list dir (vector (plist-get i :repo) (plist-get i :branch) state mr-col vs
                         (concat (if (plist-get i :dirty) "dirty" "")
                                 (if (> (or (plist-get i :unpushed) 0) 0)
                                     (format " ↑%d unpushed" (plist-get i :unpushed)) ""))
                         (if (> claude 0) "yes" "")))))
   personal/worktree-list--rows))

(define-derived-mode personal/worktree-list-mode tabulated-list-mode "Claude-Worktrees"
  "Major mode listing all worktrees under `personal/worktree-root'."
  (setq tabulated-list-format [("Repo" 22 t) ("Branch" 36 t) ("State" 7 t) ("MR" 12 t)
                               ("vs origin/master" 22 t) ("Local" 18 t) ("Claude" 0 t)]
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
  "Delete the worktree at point (folder, Claude buffer, workspace); keeps the branch."
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
  (require 'claude-code)
  (with-current-buffer (get-buffer-create personal/worktree-list-buffer)
    (personal/worktree-list-mode)
    (personal/worktree-list--collect)
    (setq tabulated-list-entries (personal/worktree-list--entries))
    (tabulated-list-print))
  (pop-to-buffer personal/worktree-list-buffer)
  (personal/worktree-list-refresh)
  (message "? for menu"))

(map! :leader :desc "Claude: list worktrees" "l g" #'personal/worktree-list)

(provide 'claude)
