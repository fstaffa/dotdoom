;;; kb-denote.el --- Personal knowledge base on Denote  -*- lexical-binding: t; -*-

;; Loaded from config.el.  The `kb' batch tool lives in kb/.

(defvar personal/kb-root "~/data/org-mode/"
  "Root of the knowledge base (also the Syncthing folder).")

(defun personal/kb-todo-file-p (file)
  "Non-nil when FILE's Denote keywords (after `__') include `todo'."
  (string-match-p "__\\(?:[^.]*_\\)?todo\\(?:_[^.]*\\)?\\.org\\'"
                  (file-name-nondirectory file)))

(defun personal/kb-archived-file-p (file)
  "Non-nil when FILE's Denote keywords include `archive'."
  ;; Called while building the agenda, possibly before Denote is loaded.
  (require 'denote)
  (member "archive" (denote-extract-keywords-from-path file)))

(defun personal/kb-agenda-files ()
  "Agenda files: tasks.org plus every note tagged `todo' (not `archive') in the KB root.
Subfolders (archive/, legacy directories) are not searched."
  (let ((root (expand-file-name personal/kb-root)))
    (when (file-directory-p root)
      (append
       (seq-filter #'file-exists-p (list (expand-file-name "tasks.org" root)))
       (seq-filter (lambda (f)
                     ;; regular files only: skips Emacs lock symlinks (.#name)
                     (and (file-regular-p f)
                          (not (string-prefix-p ".#" (file-name-nondirectory f)))
                          (personal/kb-todo-file-p f)
                          (not (personal/kb-archived-file-p f))))
                   (directory-files root t "\\.org\\'"))))))

(defun personal/kb-refile-files ()
  "Refile targets: tasks.org plus every Denote org note (archive/export excluded)."
  (require 'denote)
  (let ((root (expand-file-name personal/kb-root)))
    (when (file-directory-p root)
      (append
       (seq-filter #'file-exists-p (list (expand-file-name "tasks.org" root)))
       (seq-filter (lambda (f) (not (string-prefix-p ".#" (file-name-nondirectory f))))
                   (denote-directory-files "\\.org\\'"))))))

(defun personal/kb-sync-todo-tag ()
  "Add/remove the `todo' keyword of the current note to match its open tasks.
For `after-save-hook'.  Same rule as `kb sync-todo-tags': a note is `todo' when it
has an open TODO/NEXT/WAITING heading.  Renames the file and rewrites #+filetags via
Denote; the buffer follows the file."
  (when-let* ((file buffer-file-name)
              ((derived-mode-p 'org-mode))
              ((string-prefix-p (file-name-as-directory (expand-file-name personal/kb-root))
                                (file-name-directory file)))
              ((denote-file-is-note-p file))
              ((denote-retrieve-filename-identifier file)))
    (let* ((open (save-excursion
                   (save-restriction
                     (widen)
                     (goto-char (point-min))
                     (re-search-forward "^\\*+ \\(?:TODO\\|NEXT\\|WAITING\\)\\(?: \\|$\\)" nil t))))
           (keywords (denote-extract-keywords-from-path file))
           (has (member "todo" keywords)))
      (unless (eq (and open t) (and has t))
        (let ((denote-rename-confirmations nil)
              (denote-save-buffers t))
          (denote-rename-file file 'keep-current
                              (if open (cons "todo" keywords) (remove "todo" keywords))
                              'keep-current 'keep-current 'keep-current))))))

;; Whole notes are archived with the `archive' keyword; subtree archiving is unused.
(defun personal/kb-archive-note ()
  "Archive the current note by adding the `archive' keyword to its file name."
  (interactive)
  (let ((file (or buffer-file-name (user-error "Buffer has no file")))
        (denote-rename-confirmations nil)
        (denote-save-buffers t))
    (denote-rename-file file 'keep-current
                        (cl-adjoin "archive" (denote-extract-keywords-from-path file)
                                   :test #'equal)
                        'keep-current 'keep-current 'keep-current)))

(defun personal/kb-no-subtree-archive (&rest _)
  (user-error "Subtree archiving is disabled; archive the whole note with `SPC n d a'"))
(advice-add 'org-archive-subtree :override #'personal/kb-no-subtree-archive)

(add-hook 'org-mode-hook
          (lambda () (add-hook 'after-save-hook #'personal/kb-sync-todo-tag nil t)))

(defun personal/kb-log-done-to-daily ()
  "Append the task just marked DONE to today's daily (created if missing).
For `org-after-todo-state-change-hook'.  The entry goes under a `* Done' heading as
`- TEXT ([[denote:ID]])', linking to the note holding the task when it has an ID."
  (when-let* (((equal org-state "DONE"))
              (file buffer-file-name)
              ((string-prefix-p (file-name-as-directory (expand-file-name personal/kb-root))
                                (file-name-directory file))))
    (require 'denote-journal)
    (let* ((text (org-get-heading t t t t))
           (id (denote-retrieve-filename-identifier file))
           (line (format "- %s%s\n" text (if id (format " ([[denote:%s]])" id) "")))
           (daily (denote-journal-path-to-new-or-existing-entry)))
      (unless (file-equal-p daily file)
        (with-current-buffer (find-file-noselect daily)
          ;; Don't write out the user's unsaved edits as a side effect.
          (let ((was-modified (buffer-modified-p)))
          (save-excursion
            (save-restriction
              (widen)
              (goto-char (point-min))
              (if (re-search-forward "^\\* Done$" nil t)
                  ;; end of this section: just before the next heading or at EOF
                  (progn (outline-next-heading)
                         (unless (bolp) (insert "\n")))
                (goto-char (point-max))
                (unless (bolp) (insert "\n"))
                (insert "* Done\n"))
              (insert line)))
          (unless was-modified (save-buffer))))
        (message "Logged to %s" (file-name-nondirectory daily))))))

(add-hook 'org-after-todo-state-change-hook #'personal/kb-log-done-to-daily)

;; The front matter mirrors what `kb new inbox' writes, so `kb validate' accepts it.
(defun personal/kb-new-inbox-file ()
  "Create an empty inbox capture file in the KB root and leave point in it.
For an `org-capture' target of type `function'.  Aborting the capture leaves the
empty file behind; `kb validate' accepts it."
  (let* ((root (file-name-as-directory (expand-file-name personal/kb-root)))
         (time (current-time))
         id file)
    (while (progn (setq id (format-time-string "%Y%m%dT%H%M%S" time)
                        file (expand-file-name (concat id "__inbox.org") root))
                  (directory-files root nil (concat "\\`" id)))
      (setq time (time-add time 1)))
    (with-temp-file file
      (insert (format "#+title:\n#+date:       %s\n#+filetags:   :inbox:\n#+identifier: %s\n\n"
                      (format-time-string "[%Y-%m-%d %a %H:%M]" time) id)))
    (set-buffer (find-file-noselect file))
    (goto-char (point-max))))

(defun personal/kb-open-inbox ()
  "List the unprocessed captures (notes tagged `inbox') in Dired."
  (interactive)
  (let* ((root (file-name-as-directory (expand-file-name personal/kb-root)))
         (files (directory-files root nil "__\\(?:[^.]*_\\)?inbox\\(?:_[^.]*\\)?\\.org\\'")))
    (if files
        (dired (cons root files))
      (message "Inbox is empty"))))

(setq denote-directory (expand-file-name personal/kb-root)
      denote-file-type 'org
      denote-known-keywords '("person" "project" "reference" "daily"
                              "inbox" "todo" "work" "personal" "archive")
      ;; keep legacy/archived and exported files out of link completion and backlinks
      denote-excluded-directories-regexp "\\(archive\\|export\\)"
      denote-save-buffers t
      ;; must stay identical to what `kb new' writes (see kb/kb.el)
      denote-org-front-matter
      "#+title:      %s\n#+date:       %s\n#+filetags:   %s\n#+identifier: %s\n\n")

;; Dailies: `denote-journal' finds an entry by keyword plus the date in the ID, which
;; matches the `daily' notes made by `kb new daily'.  Entries go in the KB root, titled
;; YYYY-MM-DD.
(with-eval-after-load 'denote-journal
  (setq denote-journal-directory nil   ; nil = `denote-directory'
        denote-journal-keyword "daily"
        denote-journal-title-format "%Y-%m-%d")
  (add-hook 'calendar-mode-hook #'denote-journal-calendar-mode)
  ;; Evil's normal-state calendar bindings shadow the minor mode's plain keys.
  (evil-define-minor-mode-key 'normal 'denote-journal-calendar-mode
    "N" #'denote-journal-calendar-new-or-existing
    "F" #'denote-journal-calendar-find-file)
  ;; The note opens in another window; close the calendar once it is shown.
  (defun personal/kb-close-calendar (&rest _)
    (when-let* ((buf (get-buffer calendar-buffer)))
      (dolist (win (get-buffer-window-list buf nil t))
        (when (cdr (window-list (window-frame win)))
          (delete-window win)))
      (kill-buffer buf)))
  (advice-add 'denote-journal-calendar-new-or-existing :after #'personal/kb-close-calendar)
  (advice-add 'denote-journal-calendar-find-file :after #'personal/kb-close-calendar))

(defun personal/kb-daily-via-calendar ()
  "Open the calendar; pick a date and press N (new/existing daily) or F (find)."
  (interactive)
  (require 'denote-journal)
  (calendar)
  (message "Move to a date, then N: new/existing daily, F: find existing"))

(with-eval-after-load 'denote
  (denote-rename-buffer-mode 1)
  (add-hook 'dired-mode-hook #'denote-dired-mode))

(with-eval-after-load 'consult-denote
  (consult-denote-mode 1))

;; Recompute agenda files from filename tags every time they are requested,
;; so adding/removing the `todo' tag takes effect without a restart.
(advice-add 'org-agenda-files :filter-return
            (lambda (files)
              (if (bound-and-true-p org-agenda-overriding-restriction)
                  files
                (personal/kb-agenda-files))))

(map! :leader
      (:prefix ("n d" . "denote")
       :desc "Find note"          "f" #'consult-denote-find
       :desc "Grep notes"         "g" #'consult-denote-grep
       :desc "Insert link"        "i" #'denote-link-or-create
       :desc "Backlinks buffer"   "b" #'denote-backlinks
       :desc "Backlinks block"    "B" #'denote-org-dblock-insert-backlinks
       :desc "New note"           "n" #'denote
       :desc "Rename (retag)"     "r" #'denote-rename-file
       :desc "Archive note"       "a" #'personal/kb-archive-note
       :desc "Today's daily"      "d" #'denote-journal-new-or-existing-entry
       :desc "Daily via calendar" "D" #'personal/kb-daily-via-calendar
       :desc "Inbox"              "I" #'personal/kb-open-inbox))

(provide 'kb-denote)
;;; kb-denote.el ends here
