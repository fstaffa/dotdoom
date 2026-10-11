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

(defvar-local personal/agent--last-activity nil
  "`float-time' of the last event from this shell.")

(defvar-local personal/agent--reply-tail ""
  "Tail of the agent's message text streamed during the current/last turn.")

(defvar-local personal/agent--last-message ""
  "Raw markdown of the agent's last message (text after the last tool call).")

(defvar-local personal/agent--message-closed nil
  "Non-nil after a tool call: the next text chunk starts a new message.")

(defun personal/agent--dead-p (buf)
  "Non-nil when the comint or ACP client process of shell BUF has exited.
`agent-shell-status' keeps saying `ready' in that case."
  (or (not (process-live-p (get-buffer-process buf)))
      (let ((proc (ignore-errors
                    (map-nested-elt (buffer-local-value 'agent-shell--state buf)
                                    '(:client :process)))))
        (and proc (not (process-live-p proc))))))

(defun personal/agent--status (buf)
  "Status of shell BUF: `dead', `blocked', `busy', `done' (finished, unseen) or `idle'."
  (let ((s (condition-case nil (agent-shell-status :shell-buffer buf) (error 'ready))))
    (cond ((personal/agent--dead-p buf) 'dead)
          ((eq s 'blocked) 'blocked)
          ((eq s 'busy) 'busy)
          ((buffer-local-value 'personal/agent--unseen buf) 'done)
          (t 'idle))))

(defun personal/agent--status-string (buf)
  (pcase (personal/agent--status buf)
    ('dead (propertize "dead" 'face 'error))
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

;; The overview (`personal/agent-list') also takes over the frame, so while it or a full
;; shell is shown, the layout saved earlier must be kept.
(defvar personal/agent-list-buffer)
(defun personal/agent--save-layout ()
  (unless (or (personal/agent--full-p) (get-buffer-window personal/agent-list-buffer))
    (puthash (personal/agent--ws) (window-state-get (frame-root-window))
             personal/agent--layouts)))

(defun personal/agent--display (buffer &optional _alist)
  "Display action: show BUFFER alone in the frame, saving the current layout first."
  (personal/agent--save-layout)
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

(defun personal/agent-open-in-project ()
  "Prompt for a known project and show its agent shell, or start one there."
  (interactive)
  (require 'agent-shell)
  (let* ((dir (expand-file-name (projectile-completing-read "Project: "
                                                            (projectile-relevant-known-projects))))
         (buf (car (personal/agent--buffers-for dir))))
    (if buf
        (personal/agent--goto buf)
      (when (bound-and-true-p persp-mode)
        (let ((name (file-name-nondirectory (directory-file-name dir))))
          (unless (equal name (+workspace-current-name))
            (+workspace-switch name t))))
      (personal/agent-start dir))))

(defun personal/agent-copy-last-message ()
  "Copy the agent's last message as markdown, without tool calls or usage chrome.
Falls back to `agent-shell-copy-last-output' when no message was captured (e.g. a
resumed session)."
  (interactive)
  (unless (personal/agent--buffer-p (current-buffer)) (user-error "Not in a shell"))
  (if (string-empty-p (string-trim personal/agent--last-message))
      (agent-shell-copy-last-output)
    (kill-new (string-trim personal/agent--last-message))
    (message "Copied last message")))

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
                           (with-current-buffer b (personal/agent-list--update))))))))

(defun personal/agent--notify (buf message)
  (unless (eq (window-buffer (selected-window)) buf)
    (condition-case err
        (progn (require 'notifications)
               (notifications-notify :title (format "Agent: %s" (personal/agent--project-name buf))
                                     :body message :app-name "Emacs"))
      (error (message "Agent notification failed: %S" err)))))

(defun personal/agent--on-event (buf event)
  (when (buffer-live-p buf)
    (with-current-buffer buf
      (setq personal/agent--last-activity (float-time))
      (pcase (map-elt event :event)
        ('input-submitted (setq personal/agent--reply-tail ""
                                personal/agent--last-message ""
                                personal/agent--message-closed nil))
        ((or 'tool-call-update 'permission-request) (setq personal/agent--message-closed t))
        ('agent-message-chunk
         (when personal/agent--message-closed
           (setq personal/agent--last-message "" personal/agent--message-closed nil))
         (setq personal/agent--last-message
               (concat personal/agent--last-message
                       (or (map-nested-elt event '(:data :text-chunk)) "")))
         (let ((s (concat personal/agent--reply-tail
                          (or (map-nested-elt event '(:data :text-chunk)) ""))))
           (setq personal/agent--reply-tail
                 (if (> (length s) 400) (substring s -400) s))))))
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
        agent-shell-file-display-action '(personal/agent--display-file)
        ;; no banner/news/funding block at startup
        agent-shell-show-welcome-message nil
        ;; usage: context indicator in the header, cost, and a summary after each turn
        agent-shell-show-context-usage-indicator 'detailed
        agent-shell-show-cost-indicator t
        agent-shell-show-usage-at-turn-end t
        ;; UI: values are the upstream defaults, listed here to flip easily
        agent-shell-header-style (if (display-graphic-p) 'graphical 'text)
        agent-shell-thought-process-expand-by-default nil
        agent-shell-tool-use-expand-by-default nil
        agent-shell-user-message-expand-by-default nil
        agent-shell-activity-group-expand-by-default 'latest
        agent-shell-inhibit-system-sleep t) ; only effective on Emacs 31+
  ;; Evil's insert-state C-v is quoted-insert; use it to paste (images too) like a GUI app.
  (evil-define-key* 'insert agent-shell-mode-map (kbd "C-v") #'agent-shell-yank-dwim)
  ;; Back to the overview from a session without leaving insert state.
  (evil-define-key* '(insert normal emacs) agent-shell-mode-map
    (kbd "C-c b") #'personal/agent-list)
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

;; Overview of all agent shells (`SPC l b').  Sorted by urgency: blocked, done, busy, idle, dead.
;; RET open+close list, o open (list kept), p live preview, m/u mark, x kill marked/at point,
;; D kill dead+done, M model, S mode, i interrupt, r restart, f fork, R rename, c new,
;; gr refresh, ? help, q quit.
(defvar-local personal/agent-list--marked nil "Shell buffers marked for killing.")
(defvar-local personal/agent-list--preview-p nil "Non-nil while the live preview follows point.")
(defvar-local personal/agent-list--preview-window nil)
(defvar-local personal/agent-list--preview-id nil)
(defvar-local personal/agent-list--session-window nil
  "Window beside the overview that shows the opened session.")

(defun personal/agent-list--rank (buf)
  (pcase (personal/agent--status buf)
    ('blocked 0) ('done 1) ('busy 2) ('idle 3) (_ 4)))

(defun personal/agent-list--status< (a b)
  "Sort predicate for the Status column: by urgency, then by project name."
  (let ((ra (personal/agent-list--rank (car a)))
        (rb (personal/agent-list--rank (car b))))
    (if (= ra rb)
        (string< (aref (cadr a) 1) (aref (cadr b) 1))
      (< ra rb))))

(define-derived-mode personal/agent-list-mode tabulated-list-mode "Agent-Sessions"
  "Major mode listing all agent shell sessions."
  (setq tabulated-list-format
        (vector '("" 1 nil) '("Project" 22 t) '("Status" 8 personal/agent-list--status<)
                '("Mode" 12 t) '("Model" 14 t) '("Ctx" 4 t :right-align t)
                '("Perm" 4 t :right-align t) '("Age" 5 t :right-align t)
                '("Title" 30 t) '("Last reply" 44 nil) '("Directory" 0 t))
        tabulated-list-padding 1
        tabulated-list-sort-key '("Status"))
  (add-hook 'tabulated-list-revert-hook #'personal/agent-list--refresh nil t)
  (add-hook 'kill-buffer-hook #'personal/agent-list--close-preview nil t)
  (tabulated-list-init-header))

(defun personal/agent-list--age (buf)
  (let ((ts (buffer-local-value 'personal/agent--last-activity buf)))
    (if (not ts)
        ""
      (let ((s (- (float-time) ts)))
        (cond ((< s 60) "<1m")
              ((< s 3600) (format "%dm" (/ s 60)))
              ((< s 86400) (format "%dh" (/ s 3600)))
              (t (format "%dd" (/ s 86400))))))))

(defun personal/agent-list--reply (buf)
  (let ((s (string-trim (replace-regexp-in-string
                         "[ \t\n\r]+" " " (buffer-local-value 'personal/agent--reply-tail buf)))))
    (if (> (length s) 60) (concat "…" (substring s -59)) s)))

(defun personal/agent-list--entries ()
  (mapcar
   (lambda (buf)
     (let* ((state (buffer-local-value 'agent-shell--state buf))
            (usage (ignore-errors (map-elt state :usage)))
            (used (map-elt usage :context-used))
            (size (map-elt usage :context-size))
            (perm (or (ignore-errors
                        (seq-count (lambda (e) (map-elt (cdr e) :permission-request-id))
                                   (map-elt state :tool-calls)))
                      0)))
       (list buf (vector (if (memq buf personal/agent-list--marked) "*" " ")
                         (personal/agent--project-name buf)
                         (personal/agent--status-string buf)
                         (or (ignore-errors (agent-shell-get-mode-name state)) "")
                         (or (ignore-errors (agent-shell-get-model-name state)) "")
                         (if (and (numberp used) (numberp size) (> size 0))
                             (format "%d%%" (round (* 100.0 used) size))
                             "")
                         (if (> perm 0) (propertize (number-to-string perm) 'face 'error) "")
                         (personal/agent-list--age buf)
                         (or (ignore-errors (map-nested-elt state '(:session :title))) "")
                         (personal/agent-list--reply buf)
                         (abbreviate-file-name (personal/agent--dir buf))))))
   (agent-shell-buffers)))

(defun personal/agent-list--refresh ()
  (setq tabulated-list-entries (personal/agent-list--entries)))

(defun personal/agent-list--update ()
  "Re-render only when the entries changed (called on shell events)."
  (let ((new (personal/agent-list--entries)))
    (unless (equal new tabulated-list-entries)
      (setq tabulated-list-entries new)
      (tabulated-list-print t))))

(defun personal/agent-list--buffer ()
  (or (tabulated-list-get-id) (user-error "No session on this line")))

;; Live preview: the real shell buffer of the row at point, in a window below the list.
;; It is shown with `set-window-buffer' (not the full-window display action) and must be
;; closed before anything that goes through `personal/agent--display', which would save
;; the preview split as part of the layout to restore.
(defun personal/agent-list--close-preview ()
  (when-let* ((b (get-buffer personal/agent-list-buffer)))
    (with-current-buffer b
      (when (window-live-p personal/agent-list--preview-window)
        (ignore-errors (delete-window personal/agent-list--preview-window)))
      (setq personal/agent-list--preview-window nil
            personal/agent-list--preview-p nil
            personal/agent-list--preview-id nil))))

(defun personal/agent-list--show-preview ()
  (let ((buf (tabulated-list-get-id)))
    (when (buffer-live-p buf)
      (unless (window-live-p personal/agent-list--preview-window)
        (setq personal/agent-list--preview-window
              (split-window (selected-window) (max 8 (/ (window-height) 3)) 'below)))
      (set-window-buffer personal/agent-list--preview-window buf)
      (setq personal/agent-list--preview-id buf))))

(defun personal/agent-list--follow ()
  (when personal/agent-list--preview-p
    (if (not (window-live-p personal/agent-list--preview-window))
        (setq personal/agent-list--preview-p nil)
      (let ((id (tabulated-list-get-id)))
        (unless (or (null id) (eq id personal/agent-list--preview-id))
          (personal/agent-list--show-preview))))))

(defun personal/agent-list-preview ()
  "Toggle a live preview of the session at point below the list."
  (interactive)
  (if personal/agent-list--preview-p
      (personal/agent-list--close-preview)
    (setq personal/agent-list--preview-p t)
    (add-hook 'post-command-hook #'personal/agent-list--follow nil t)
    (personal/agent-list--show-preview)))

(defun personal/agent-list--open-side (buf select)
  "Show BUF in the window beside the overview (created on demand); SELECT it if non-nil."
  (personal/agent-list--close-preview)
  (let ((win (if (window-live-p personal/agent-list--session-window)
                 personal/agent-list--session-window
               (setq personal/agent-list--session-window
                     (split-window (selected-window) nil 'right)))))
    (set-window-dedicated-p win nil)
    (set-window-buffer win buf)
    (with-current-buffer buf (setq personal/agent--unseen nil))
    (when select (select-window win))))

(defun personal/agent-list-switch ()
  "Open the session at point beside the overview and select it."
  (interactive)
  (personal/agent-list--open-side (personal/agent-list--buffer) t))

(defun personal/agent-list-open ()
  "Open the session at point beside the overview, staying in the overview."
  (interactive)
  (personal/agent-list--open-side (personal/agent-list--buffer) nil))

(defun personal/agent-list-open-full ()
  "Go to the workspace of the session at point and show it full window."
  (interactive)
  (let ((buf (personal/agent-list--buffer)))
    (personal/agent-list--close-preview)
    (personal/agent--goto buf)))

(defun personal/agent-list-quit ()
  "Close the overview and restore the window layout from before it."
  (interactive)
  (personal/agent-list--close-preview)
  (if (gethash (personal/agent--ws) personal/agent--layouts)
      (personal/agent-leave)
    (quit-window)))

(defun personal/agent-list--kill-buffers (bufs)
  (dolist (b bufs) (when (buffer-live-p b) (kill-buffer b)))
  (setq personal/agent-list--marked nil)
  (personal/agent-list--update)
  (when personal/agent-list--preview-p (personal/agent-list--show-preview)))

(defun personal/agent-list-mark ()
  (interactive)
  (let ((buf (personal/agent-list--buffer)))
    (cl-pushnew buf personal/agent-list--marked)
    (personal/agent-list--update)
    (forward-line 1)))

(defun personal/agent-list-unmark ()
  (interactive)
  (let ((buf (personal/agent-list--buffer)))
    (setq personal/agent-list--marked (delq buf personal/agent-list--marked))
    (personal/agent-list--update)
    (forward-line 1)))

(defun personal/agent-list-kill ()
  "Kill the marked sessions, or the one at point when none are marked."
  (interactive)
  (let ((targets (or (seq-filter #'buffer-live-p personal/agent-list--marked)
                     (list (personal/agent-list--buffer)))))
    (when (y-or-n-p (if (cdr targets)
                        (format "Kill %d sessions? " (length targets))
                      (format "Kill %s? " (buffer-name (car targets)))))
      (personal/agent-list--kill-buffers targets))))

(defun personal/agent-list-kill-finished ()
  "Kill all dead and finished (unseen) sessions."
  (interactive)
  (let ((targets (seq-filter (lambda (b) (memq (personal/agent--status b) '(dead done)))
                             (agent-shell-buffers))))
    (cond ((null targets) (message "No dead or finished sessions"))
          ((y-or-n-p (format "Kill %d dead/finished sessions? " (length targets)))
           (personal/agent-list--kill-buffers targets)))))

(defmacro personal/agent-list--defaction (name doc &rest body)
  "Define interactive NAME acting on the shell BUF of the row at point."
  (declare (indent 2))
  `(defun ,name ()
     ,doc
     (interactive)
     (let ((buf (personal/agent-list--buffer)))
       ,@body
       (run-at-time 0.5 nil #'personal/agent--changed))))

(personal/agent-list--defaction personal/agent-list-set-model "Set the model of the session at point."
  (with-current-buffer buf (call-interactively #'agent-shell-set-session-model)))

(personal/agent-list--defaction personal/agent-list-set-mode "Set the mode of the session at point."
  (with-current-buffer buf (call-interactively #'agent-shell-set-session-mode)))

(personal/agent-list--defaction personal/agent-list-interrupt "Interrupt the session at point."
  (with-current-buffer buf (agent-shell-interrupt)))

;; Restart and fork display the new shell full window, so drop the preview split first.
(personal/agent-list--defaction personal/agent-list-restart "Restart the session at point."
  (personal/agent-list--close-preview)
  (with-current-buffer buf (agent-shell-restart)))

(personal/agent-list--defaction personal/agent-list-fork "Fork the session at point."
  (personal/agent-list--close-preview)
  (with-current-buffer buf (agent-shell-fork)))

(personal/agent-list--defaction personal/agent-list-rename "Rename the session at point."
  (shell-maker-set-buffer-name buf (read-string "Rename to: " (buffer-name buf))))

(defun personal/agent-list-new ()
  "Start a new session in the directory of the session at point."
  (interactive)
  (let ((dir (personal/agent--dir (personal/agent-list--buffer))))
    (personal/agent-list--close-preview)
    (personal/agent-start dir)))

(defun personal/agent-list-help ()
  (interactive)
  (message "RET open beside+select  o open beside  O open full  p preview  m/u mark  x kill  D kill dead/done  M model  S mode  i interrupt  r restart  f fork  R rename  c new  gr refresh  q quit"))

(let ((keys '(("RET" . personal/agent-list-switch) ("o" . personal/agent-list-open)
              ("O" . personal/agent-list-open-full)
              ("p" . personal/agent-list-preview) ("m" . personal/agent-list-mark)
              ("u" . personal/agent-list-unmark) ("x" . personal/agent-list-kill)
              ("D" . personal/agent-list-kill-finished) ("M" . personal/agent-list-set-model)
              ("S" . personal/agent-list-set-mode) ("i" . personal/agent-list-interrupt)
              ("r" . personal/agent-list-restart) ("f" . personal/agent-list-fork)
              ("R" . personal/agent-list-rename) ("c" . personal/agent-list-new)
              ("?" . personal/agent-list-help) ("q" . personal/agent-list-quit))))
  (pcase-dolist (`(,k . ,cmd) keys)
    (define-key personal/agent-list-mode-map (kbd k) cmd))
  (after! evil
    (pcase-dolist (`(,k . ,cmd) keys)
      (evil-define-key 'normal personal/agent-list-mode-map (kbd k) cmd))
    (evil-define-key 'normal personal/agent-list-mode-map "gr" #'tabulated-list-revert)))

(defun personal/agent-list ()
  "Show the agent shell overview full frame.
When it is already visible (e.g. with a session beside it), select it and close the
session window."
  (interactive)
  (require 'agent-shell)
  (let ((buf (get-buffer-create personal/agent-list-buffer)))
    (personal/agent-list--close-preview)
    (with-current-buffer buf
      (unless (derived-mode-p 'personal/agent-list-mode)
        (personal/agent-list-mode))
      (personal/agent-list--refresh)
      (tabulated-list-print t))
    (if-let* ((win (get-buffer-window buf)))
        (select-window win)
      (personal/agent--save-layout)
      (let ((ignore-window-parameters t))
        (delete-other-windows))
      (set-window-dedicated-p (selected-window) nil)
      (switch-to-buffer buf))
    (let ((ignore-window-parameters t))
      (delete-other-windows))))

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
       :desc "Agent: open in project"  "P" #'personal/agent-open-in-project
       :desc "Agent: worktree in project" "L" #'personal/agent-worktree-new-in-project
       :desc "Agent: remove worktree"  "W" #'personal/agent-worktree-remove
       :desc "Agent: list worktrees"   "g" #'personal/worktree-list
       :desc "Agent: set model"        "m" #'agent-shell-set-session-model
       :desc "Agent: set mode"         "M" #'agent-shell-set-session-mode
       :desc "Agent: cycle mode"       "C" #'agent-shell-cycle-session-mode
       :desc "Agent: set thought level" "T" #'agent-shell-set-session-thought-level
       :desc "Agent: fork session"     "F" #'agent-shell-fork
       :desc "Agent: copy last message" "y" #'personal/agent-copy-last-message
       :desc "Agent: open transcript"  "o" #'agent-shell-open-transcript
       :desc "Agent: help menu"        "?" #'agent-shell-help-menu))

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

(defun personal/agent-worktree-new-in-project ()
  "Prompt for a known project, create a worktree there and start an empty agent session.
Empty means without file/region context, like `personal/agent-start-bare'."
  (interactive)
  (require 'agent-shell) ; must be loaded first so the variable is dynamically bound
  (let ((default-directory (projectile-completing-read "Project: "
                                                       (projectile-relevant-known-projects)))
        (agent-shell-context-sources nil))
    (call-interactively #'personal/agent-worktree-new)))

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

(map! :leader :desc "Agent: open in project" "p l" #'personal/agent-open-in-project
              :desc "Agent: worktree in project" "p L" #'personal/agent-worktree-new-in-project)

(provide 'agent)
