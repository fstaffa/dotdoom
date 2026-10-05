;;; kb.el --- Validation and maintenance tools for the Denote knowledge base  -*- lexical-binding: t; -*-

;; Batch tool, run through the `kb' wrapper script (see `kb--usage').
;; ROOT defaults to $KB_ROOT, then ~/data/org-mode/.  Exit status is 1 when
;; errors are found (warnings too with --strict) or a command is refused, 2 on
;; usage errors.
;;
;; Every command that writes a note builds the complete new text first, checks
;; it with the same rules as `kb validate' and refuses to save when that would
;; introduce an error the file did not already have (`kb--gate').  Writes go
;; to a temp file in the same directory and are renamed into place.
;;
;; Deliberately independent of Doom: files are scanned as text, and org (the
;; built-in one) is only loaded for the commands that need it.

(require 'cl-lib)
(require 'subr-x)
(require 'seq)
(require 'calendar)
(require 'ucs-normalize)

;; Notes are UTF-8 whatever the machine's locale says; weekday names in time
;; stamps must be English.
(set-language-environment "UTF-8")
(prefer-coding-system 'utf-8)
(setq system-time-locale "C")

(defvar kb-root (expand-file-name (or (getenv "KB_ROOT") "~/data/org-mode/"))
  "Root directory of the knowledge base.")

(defvar kb-ignored-paths
  '(".git" ".stfolder" ".stversions" ".claude" "org" "roam" "org-roam.bak"
    "backups" "archive/legacy" "export")
  "Paths relative to `kb-root' that are not scanned (prefix match on whole components).
`org' and `roam' are the legacy directories, skipped until migrated; `export'
holds generated read-only views (`kb agenda-export').")

(defvar kb-plain-files '("tasks.org")
  "Org files in `kb-root' that are intentionally not Denote notes.")

(defconst kb--denote-file-regexp
  "\\`\\([0-9]\\{8\\}T[0-9]\\{6\\}\\)\\(==[^-_.]+\\)?\\(--[^_.]+\\)?\\(__[^.]+\\)?\\.org\\'"
  "Denote file name: ID, optional ==signature, optional --title, optional __keywords.")

(defconst kb--weekdays '("Sun" "Mon" "Tue" "Wed" "Thu" "Fri" "Sat"))

(defconst kb-todo-keywords '("TODO" "NEXT" "WAITING" "DONE"))

(defconst kb--note-types
  '(("person" . "* Notes\n") ("project" . "* Tasks\n\n* Notes\n")
    ("reference" . "") ("daily" . "") ("inbox" . ""))
  "Note types and the body skeleton of a new note of that type.")

;;;; Small helpers

(defun kb--die (fmt &rest args)
  (princ (concat "kb: " (apply #'format fmt args) "\n"))
  (kill-emacs 1))

(defun kb--rel (file)
  (file-relative-name file (file-name-as-directory kb-root)))

(defun kb--ignored-p (rel)
  "Non-nil when relative path REL is inside an ignored path."
  (seq-some (lambda (p) (or (string= rel p) (string-prefix-p (concat p "/") rel)))
            kb-ignored-paths))

(defun kb--files ()
  "All regular .org files under `kb-root', minus ignored paths and lock files."
  (let ((root (file-name-as-directory kb-root)))
    (seq-filter
     (lambda (f)
       (and (file-regular-p f)
            (not (string-prefix-p ".#" (file-name-nondirectory f)))
            (not (kb--ignored-p (kb--rel f)))))
     (directory-files-recursively
      root "\\.org\\'" nil
      (lambda (dir) (not (kb--ignored-p (directory-file-name (kb--rel dir)))))))))

(defun kb--filename-keywords (match-string-4)
  "Keywords (sorted) from the `__kw_kw' part of a Denote file name."
  (and match-string-4
       (sort (split-string (substring match-string-4 2) "_" t) #'string<)))

(defun kb--fix-arg (a)
  "Re-decode command line argument A as UTF-8 when the locale decoded it as raw bytes."
  (if (string-match-p "[\x3fff80-\x3fffff]" a)
      (decode-coding-string (encode-coding-string a 'raw-text) 'utf-8)
    a))

(defun kb--single-line (s what)
  (when (string-match-p "[\n\r]" s)
    (kb--die "%s must be a single line" what))
  s)

;;;; Reading and writing

(defun kb--read (file)
  "Return (TEXT . CODING) for FILE; CODING records the encoding and line ends found."
  (with-temp-buffer
    (insert-file-contents file)
    (cons (buffer-string) last-coding-system-used)))

(defun kb--out-coding (coding)
  "Coding system to write with, so that an edit keeps the file's encoding and line ends."
  (let* ((base (and coding (coding-system-base coding)))
         (enc (if (memq base '(nil undecided no-conversion raw-text)) 'utf-8 base))
         (eol (and coding (coding-system-eol-type coding))))
    (coding-system-change-eol-conversion enc (if (integerp eol) eol 0))))

(defun kb--atomic-write (file text coding overwrite)
  "Write TEXT to FILE via a temp file in the same directory, renamed into place."
  (let* ((dir (file-name-directory file))
         (tmp (make-temp-file (expand-file-name ".kb-tmp-" dir)))
         (coding-system-for-write (kb--out-coding coding)))
    (unwind-protect
        (progn
          (write-region text nil tmp nil 'silent)
          (set-file-modes tmp (if (file-exists-p file) (file-modes file) #o644))
          (rename-file tmp file overwrite))
      (when (file-exists-p tmp) (delete-file tmp)))))

(defun kb--save (file text coding &optional old-file)
  "Save TEXT as FILE.  With OLD-FILE (a different path) the note is moved: the new
file is written first and the old one deleted afterwards, so a failure can leave
a duplicate (which `kb validate' reports) but never lose the note."
  (let ((in-place (or (null old-file) (file-equal-p file old-file))))
    (make-directory (file-name-directory file) t)
    (when (and (not in-place) (file-exists-p file))
      (kb--die "already exists: %s" (kb--rel file)))
    (kb--atomic-write file text coding in-place)
    (unless in-place (delete-file old-file))))

;;;; Scanning and checking note text

(defun kb--block-line-p (kind line)
  (let ((case-fold-search t))
    (string-match-p (format "\\`[ \t]*#\\+%s_" kind) line)))

(defun kb--scan-text (text)
  "Scan TEXT.  Returns a plist of :identifier :tags :links :stamps :open :unterminated."
  (with-temp-buffer
    (insert text)
    (let ((case-fold-search nil)          ; `Next steps' is not a NEXT task
          (lineno 0) (in-block nil) (block-line nil) (in-header t)
          identifier tags links stamps open)
      (goto-char (point-min))
      (while (not (eobp))
        (setq lineno (1+ lineno))
        (let ((line (buffer-substring-no-properties
                     (line-beginning-position) (line-end-position))))
          (cond
           (in-block
            (when (kb--block-line-p "end" line) (setq in-block nil)))
           ((kb--block-line-p "begin" line) (setq in-block t block-line lineno))
           (t
            (when (string-match-p "\\`\\*+ " line) (setq in-header nil))
            (when (and in-header
                       (string-match "\\`#\\+\\([A-Za-z_]+\\):[ \t]*\\(.*?\\)[ \t]*\\'" line))
              (let ((key (downcase (match-string 1 line))) (val (match-string 2 line)))
                (cond ((and (string= key "identifier") (not identifier))
                       (setq identifier val))
                      ((and (string= key "filetags") (not tags))
                       (setq tags (sort (split-string val ":" t "[ \t]+") #'string<))))))
            (when (string-match-p "\\`\\*+ \\(TODO\\|NEXT\\|WAITING\\)\\( \\|\\'\\)" line)
              (setq open t))
            (let ((pos 0))
              (while (string-match "\\[\\[\\(denote\\|id\\):\\([^]:]+\\)\\(?:::[^]]*\\)?\\]" line pos)
                (push (list lineno (match-string 1 line) (match-string 2 line)) links)
                (setq pos (match-end 0))))
            (let ((pos 0))
              (while (string-match
                      "[<[]\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\) \\([A-Za-z]\\{3\\}\\)[^]>]*[]>]"
                      line pos)
                (push (list lineno
                            (string-to-number (match-string 1 line))
                            (string-to-number (match-string 2 line))
                            (string-to-number (match-string 3 line))
                            (match-string 4 line))
                      stamps)
                (setq pos (match-end 0)))))))
        (forward-line 1))
      (list :identifier identifier :tags tags
            :links (nreverse links) :stamps (nreverse stamps) :open open
            :unterminated (and in-block block-line)))))

(defun kb--scan-file (file)
  (kb--scan-text (car (kb--read file))))

(defun kb--check-note (rel text ids)
  "Problems in TEXT, the contents of the note stored at relative path REL.
IDS maps known note IDs to their relative paths.  Returns a list of
\(LEVEL LINE MESSAGE)."
  (let* ((name (file-name-nondirectory rel))
         (scan (kb--scan-text text))
         problems)
    (cl-flet ((add (level line fmt &rest args)
                (push (list level line (apply #'format fmt args)) problems))
              (common ()
                (when-let ((line (plist-get scan :unterminated)))
                  (push (list 'error line "unterminated #+begin_ block") problems))
                (pcase-dolist (`(,line ,kind ,target) (plist-get scan :links))
                  (cond ((string= kind "id")
                         (push (list 'warning line (format "legacy id: link [[id:%s]]" target))
                               problems))
                        ((not (gethash target ids))
                         (push (list 'error line (format "broken link [[denote:%s]]" target))
                               problems))))
                (pcase-dolist (`(,line ,y ,m ,d ,wd) (plist-get scan :stamps))
                  (if (not (and (<= 1 m 12) (<= 1 d (calendar-last-day-of-month m y))))
                      (push (list 'error line (format "invalid date %04d-%02d-%02d" y m d))
                            problems)
                    (let ((expected (nth (calendar-day-of-week (list m d y)) kb--weekdays)))
                      (unless (string= wd expected)
                        (push (list 'error line
                                    (format "%04d-%02d-%02d is a %s, not %s" y m d expected wd))
                              problems)))))))
      (cond
       ((string-match-p "\\.sync-conflict-" name)
        (add 'error 1 "Syncthing conflict file, resolve it"))
       ((string-match kb--denote-file-regexp name)
        (let* ((id (match-string 1 name))
               (name-tags (kb--filename-keywords (match-string 4 name)))
               (fm-id (plist-get scan :identifier))
               (fm-tags (plist-get scan :tags))
               (open (plist-get scan :open))
               (todo-tag (member "todo" name-tags)))
          (cond ((null fm-id) (add 'error 1 "missing #+identifier"))
                ((not (string= fm-id id))
                 (add 'error 1 "#+identifier %s does not match file name ID %s" fm-id id)))
          (unless (equal fm-tags name-tags)
            (add 'error 1 "#+filetags %S do not match file name keywords %S" fm-tags name-tags))
          (when (and open (not todo-tag))
            (add 'warning 1 "open tasks but no `todo' keyword"))
          (when (and todo-tag (not open))
            (add 'warning 1 "`todo' keyword but no open tasks"))
          (common)))
       ((member rel kb-plain-files) (common))
       (t (add 'error 1 "not a Denote file name (ID--title__tags.org)"))))
    problems))

;;;; Validating the whole KB

(defvar kb--problems nil "List of (LEVEL FILE LINE MESSAGE), collected while validating.")

(defun kb--note-ids (notes)
  (let ((ids (make-hash-table :test #'equal)))
    (dolist (n notes ids)
      (puthash (plist-get n :id) (plist-get n :rel) ids))))

(defun kb--validate ()
  "Validate the KB, filling `kb--problems'.  Returns the number of files checked."
  (setq kb--problems nil)
  (let* ((files (kb--files)) (notes (kb--notes)) (ids (make-hash-table :test #'equal)))
    ;; Duplicate IDs (the first file in scan order keeps the ID).
    (dolist (n notes)
      (let ((id (plist-get n :id)) (rel (plist-get n :rel)))
        (if-let ((prev (gethash id ids)))
            (push (list 'error rel 1 (format "duplicate ID %s (also %s)" id prev)) kb--problems)
          (puthash id rel ids))))
    (dolist (f files)
      (let ((rel (kb--rel f)))
        (pcase-dolist (`(,level ,line ,msg) (kb--check-note rel (car (kb--read f)) ids))
          (push (list level rel line msg) kb--problems))))
    (length files)))

;;;; Note name and front matter

(defun kb--set-header-line (key value)
  "In the current buffer set front matter line #+KEY: to VALUE (nil/\"\" = empty).
Keeps the existing spacing (Denote style padding if there was none); inserts
the line when missing."
  (goto-char (point-min))
  (let ((case-fold-search t)
        (limit (or (save-excursion (re-search-forward "^\\*+ " nil t)) (point-max)))
        (val (or value "")))
    (if (re-search-forward (format "^#\\+%s:\\([ \t]*\\).*$" key) limit t)
        (replace-match
         (concat "#+" key ":"
                 (unless (string= val "")
                   (concat (if (string= (match-string 1) "")
                               (make-string (max 1 (- 12 (1+ (length key)))) ?\s)
                             (match-string 1))
                           val)))
         t t)
      (goto-char (point-min))
      (when (re-search-forward "^#\\+identifier:" limit t) (beginning-of-line))
      (insert (format "#+%-11s %s\n" (concat key ":") val)))))

(defun kb--text-set-header (text key value)
  (with-temp-buffer
    (insert text)
    (kb--set-header-line key value)
    (buffer-string)))

(defun kb--tags-value (tags)
  (and tags (concat ":" (string-join tags ":") ":")))

(defun kb--file-name (id sig title-part tags)
  "Denote file name.  TITLE-PART is \"\" or \"--slug\"."
  (concat id sig title-part (and tags (concat "__" (string-join tags "_"))) ".org"))

(defun kb--slug (s)
  "Denote style title slug: ascii, lower case, words joined by hyphens."
  (let* ((s (replace-regexp-in-string "[^[:ascii:]]" "" (ucs-normalize-NFD-string s)))
         (s (replace-regexp-in-string "[^a-z0-9]+" "-" (downcase s))))
    (replace-regexp-in-string "\\`-+\\|-+\\'" "" s)))

(defun kb--norm-tags (s)
  "Comma separated string (or list) -> sorted, de-duplicated list of clean keywords."
  (let ((items (if (listp s) s (split-string (or s "") "," t "[ \t]+"))))
    (sort (delete-dups
           (seq-remove #'string-empty-p
                       (mapcar (lambda (x) (replace-regexp-in-string "[^a-z0-9]" "" (downcase x)))
                               items)))
          #'string<)))

(defun kb--notes ()
  "All Denote named notes as plists (:file :rel :id :sig :title :slug :tags)."
  (let (notes)
    (dolist (f (kb--files))
      (let ((name (file-name-nondirectory f)))
        (when (string-match kb--denote-file-regexp name)
          ;; Grab every group before calling anything that may clobber the match data.
          (let ((id (match-string 1 name)) (sig (or (match-string 2 name) ""))
                (title (match-string 3 name)) (kw (match-string 4 name)))
            (push (list :file f :rel (kb--rel f) :id id :sig sig :title (or title "")
                        :slug (and title (substring title 2))
                        :tags (kb--filename-keywords kw))
                  notes)))))
    (nreverse notes)))

(defun kb--parse-created (s)
  "Parse \"YYYY-MM-DD[ HH:MM[:SS]]\" (local time) to a time value; nil for nil."
  (when s
    (unless (string-match "\\`\\([0-9]\\{4\\}-[0-9][0-9]-[0-9][0-9]\\)\\(?: \\([0-9][0-9]\\):\\([0-9][0-9]\\)\\(?::\\([0-9][0-9]\\)\\)?\\)?\\'" s)
      (kb--die "invalid --created %S (want YYYY-MM-DD[ HH:MM[:SS]])" s))
    (let ((date (match-string 1 s))
          (h (string-to-number (or (match-string 2 s) "0")))
          (m (string-to-number (or (match-string 3 s) "0")))
          (sec (string-to-number (or (match-string 4 s) "0"))))
      (kb--check-iso-date date)
      (when (or (> h 23) (> m 59) (> sec 59))
        (kb--die "invalid time in --created %S" s))
      (encode-time (list sec m h (string-to-number (substring date 8 10))
                         (string-to-number (substring date 5 7))
                         (string-to-number (substring date 0 4)) nil -1 nil)))))

(defun kb--id-date-stamp (id)
  "Org inactive timestamp for the time encoded in Denote ID, e.g. [2021-07-31 Sat 14:04]."
  (format-time-string "[%Y-%m-%d %a %H:%M]"
                      (encode-time (list (string-to-number (substring id 13 15))
                                         (string-to-number (substring id 11 13))
                                         (string-to-number (substring id 9 11))
                                         (string-to-number (substring id 6 8))
                                         (string-to-number (substring id 4 6))
                                         (string-to-number (substring id 0 4)) nil -1 nil))))

(defun kb--free-id (notes &optional time)
  "A timestamp ID not used by NOTES (bumps by seconds on collision).
TIME defaults to now."
  (let ((time (or time (current-time))) id)
    (while (progn (setq id (format-time-string "%Y%m%dT%H%M%S" time))
                  (seq-some (lambda (n) (string= (plist-get n :id) id)) notes))
      (setq time (time-add time 1)))
    id))

;;;; Validate before save

(defun kb--gate (file text &optional old-file)
  "Errors (list of strings) that saving TEXT as FILE would introduce.
OLD-FILE is the path being replaced when a note moves.  Errors already present
in the current contents (OLD-FILE, else FILE) do not count, so a note that is
already broken can still be edited, just not made worse."
  (let* ((rel (kb--rel file))
         (old (or old-file file))
         (old-rel (kb--rel old))
         (name (file-name-nondirectory file))
         (ids (kb--note-ids (kb--notes)))
         (old-text (and (file-exists-p old) (car (kb--read old))))
         (before (and old-text
                      (mapcar #'caddr (seq-filter (lambda (p) (eq (car p) 'error))
                                                  (kb--check-note old-rel old-text ids)))))
         errors)
    ;; The note's ID now lives at REL instead of OLD-REL.
    (maphash (lambda (id r) (when (string= r old-rel) (remhash id ids))) ids)
    (when (string-match kb--denote-file-regexp name)
      (let ((id (match-string 1 name)))
        (when-let ((prev (gethash id ids)))
          (push (format "duplicate ID %s (also %s)" id prev) errors))
        (puthash id rel ids)))
    (when (kb--ignored-p rel)
      (push (format "%s is in an ignored path" rel) errors))
    (dolist (p (kb--check-note rel text ids))
      (when (and (eq (car p) 'error) (not (member (caddr p) before)))
        (push (format "line %d: %s" (cadr p) (caddr p)) errors)))
    (nreverse errors)))

(defun kb--commit (file text coding &optional old-file)
  "Check TEXT with `kb--gate', then save it as FILE (moving it from OLD-FILE)."
  (when (and old-file (file-exists-p file) (not (file-equal-p file old-file)))
    (kb--die "already exists: %s" (kb--rel file)))
  (when-let ((errors (kb--gate file text old-file)))
    (kb--die "refusing to save %s:\n  %s" (kb--rel file) (string-join errors "\n  ")))
  (kb--save file text coding old-file))

;;;; Command line handling

(defun kb--usage ()
  (princ "usage: kb validate [--strict] [--fix] [ROOT]
       kb sync-todo-tags [--dry-run] [ROOT]
       kb new person|project|reference TITLE [--tags a,b] [--body TEXT] [--created DATE] [--root DIR]
       kb new daily [YYYY-MM-DD] | kb new inbox [--body TEXT]   (all take --created \"YYYY-MM-DD[ HH:MM[:SS]]\")
       kb rename FILE [--title T] [--tags a,b] [--add-tags a,b] [--remove-tags a,b] [--dir DIR]
       kb refile SRC-FILE HEADING DEST-FILE [DEST-HEADING]
       kb query [--state S,S] [--tag T] [--before YYYY-MM-DD] [--undated] [--root DIR]
       kb agenda-export [--print] [--root DIR]
       kb state FILE HEADING TODO|NEXT|WAITING|DONE|none [--root DIR]
       kb schedule FILE HEADING YYYY-MM-DD|none [--root DIR]
       kb deadline FILE HEADING YYYY-MM-DD|none [--root DIR]
       kb install-template [--root DIR]   (copy template/CLAUDE.md and template/.claude into the KB root)\n")
  (kill-emacs 2))

(defun kb--parse-args (args flags)
  "Parse ARGS: known FLAGS (strings) and an optional ROOT.  Sets `kb-root'.
Returns the list of flags that were given."
  (let (given root)
    (dolist (a args)
      (cond ((member a flags) (push a given))
            ((string-prefix-p "--" a) (kb--usage))
            (t (setq root a))))
    (when root (setq kb-root (expand-file-name root)))
    (unless (file-directory-p kb-root)
      (princ (format "kb: no such directory: %s\n" kb-root))
      (kill-emacs 2))
    given))

(defun kb--extract-root (args)
  "Remove `--root DIR' from ARGS, setting `kb-root'.  Returns the remaining args."
  (let (rest)
    (while args
      (if (string= (car args) "--root")
          (progn (unless (cdr args) (kb--usage))
                 (setq kb-root (expand-file-name (cadr args)) args (cddr args)))
        (push (pop args) rest)))
    (nreverse rest)))

(defun kb--split-args (args value-opts)
  "Split ARGS into (OPTS . POSITIONAL).  OPTS is an alist of (\"--opt\" . value)."
  (let (opts pos)
    (while args
      (let ((a (pop args)))
        (cond ((member a value-opts)
               (unless args (kb--usage))
               (push (cons a (pop args)) opts))
              ((string-prefix-p "--" a) (kb--usage))
              (t (push a pos)))))
    (cons opts (nreverse pos))))

(defun kb--resolve-file (name)
  "Absolute path for NAME (relative to `kb-root' or absolute); must be inside the KB."
  (let ((full (expand-file-name name (file-name-as-directory kb-root))))
    (unless (file-regular-p full) (kb--die "no such file: %s" name))
    (unless (file-in-directory-p full kb-root) (kb--die "outside the KB: %s" name))
    (when (kb--ignored-p (kb--rel full)) (kb--die "in an ignored path: %s" name))
    full))

(defun kb--check-iso-date (s)
  (unless (and (string-match "\\`\\([0-9]\\{4\\}\\)-\\([0-9]\\{2\\}\\)-\\([0-9]\\{2\\}\\)\\'" s)
               (let ((y (string-to-number (match-string 1 s)))
                     (m (string-to-number (match-string 2 s)))
                     (d (string-to-number (match-string 3 s))))
                 (and (<= 1 m 12) (<= 1 d (calendar-last-day-of-month m y)))))
    (kb--die "invalid date \"%s\" (use YYYY-MM-DD or none)" s)))

;;;; validate, sync-todo-tags

(defun kb--sync-todo-tags (dry-run)
  "Add/remove the `todo' keyword so it matches whether a note has open tasks.
Renames the file and rewrites #+filetags.  Notes whose front matter disagrees
with their file name, and renames the gate refuses, are skipped.  Returns a
list of strings describing what was (or would be) done."
  (let (done)
    (dolist (f (kb--files))
      (let ((name (file-name-nondirectory f)))
        (when (string-match kb--denote-file-regexp name)
          (let* ((id (match-string 1 name))
                 (sig (or (match-string 2 name) ""))
                 (title (or (match-string 3 name) ""))
                 (tags (kb--filename-keywords (match-string 4 name)))
                 (read (kb--read f))
                 (scan (kb--scan-text (car read)))
                 (open (plist-get scan :open))
                 (has (member "todo" tags))
                 (rel (kb--rel f)))
            (cond
             ((not (and (equal (plist-get scan :identifier) id)
                        (equal (plist-get scan :tags) tags)))
              (push (format "skip %s: front matter disagrees with file name" rel) done))
             ((eq (and open t) (and has t)))
             (t
              (let* ((new-tags (sort (if open (cons "todo" tags) (remove "todo" tags))
                                     #'string<))
                     (new-name (kb--file-name id sig title new-tags))
                     (new-file (expand-file-name new-name (file-name-directory f)))
                     (new-text (kb--text-set-header (car read) "filetags"
                                                    (kb--tags-value new-tags))))
                (cond
                 ((file-exists-p new-file)
                  (push (format "skip %s: %s already exists" rel new-name) done))
                 ((kb--gate new-file new-text f)
                  (push (format "skip %s: would introduce errors (%s)" rel
                                (car (kb--gate new-file new-text f)))
                        done))
                 (t
                  (unless dry-run (kb--save new-file new-text (cdr read) f))
                  (push (format "%s %s -> %s" (if dry-run "would rename" "renamed")
                                rel new-name)
                        done))))))))))
    (nreverse done)))

(defun kb-cmd-sync-todo-tags (args)
  (let* ((flags (kb--parse-args args '("--dry-run")))
         (changes (kb--sync-todo-tags (and (member "--dry-run" flags) t))))
    (dolist (c changes) (princ (concat c "\n")))
    (princ (format "kb sync-todo-tags: %d change(s)\n"
                   (seq-count (lambda (c) (not (string-prefix-p "skip " c))) changes)))
    (kill-emacs 0)))

(defun kb-cmd-validate (args)
  (let* ((flags (kb--parse-args args '("--strict" "--fix")))
         (strict (member "--strict" flags)))
    (when (member "--fix" flags)
      (dolist (c (kb--sync-todo-tags nil)) (princ (concat c "\n"))))
    (let* ((n (kb--validate))
           (problems (sort (copy-sequence kb--problems)
                           (lambda (a b)
                             (if (string= (nth 1 a) (nth 1 b))
                                 (< (nth 2 a) (nth 2 b))
                               (string< (nth 1 a) (nth 1 b))))))
           (errors (seq-count (lambda (p) (eq (car p) 'error)) problems))
           (warnings (- (length problems) errors)))
      (pcase-dolist (`(,level ,file ,line ,msg) problems)
        (princ (format "%s:%d: %s: %s\n" file line level msg)))
      (princ (format "kb validate: %d files, %d errors, %d warnings\n" n errors warnings))
      (kill-emacs (if (or (> errors 0) (and strict (> warnings 0))) 1 0)))))

;;;; state, schedule, deadline (org does the editing)

(defmacro kb--with-org (&rest body)
  "Run BODY with org loaded and configured for predictable, quiet edits."
  `(progn
     (require 'org)
     (let ((org-todo-keywords '((sequence "TODO(t)" "NEXT(n)" "WAITING(w)" "|" "DONE(d)")))
           (inhibit-message t)          ; keep org's own progress messages out of stdout
           (org-tags-column 0)          ; tags right after the headline, like Doom
           (org-log-done 'time)
           (org-log-repeat nil)
           (org-log-reschedule nil)
           (org-log-redeadline nil))
       ,@body)))

(defun kb--goto-heading (heading name)
  "Move point to the unique headline whose bare text is HEADING in the current org buffer.
NAME is the file name, used in error messages."
  (let (hits)
    (org-map-entries
     (lambda ()
       (when (string= (org-get-heading t t t t) heading)
         (push (line-number-at-pos) hits))))
    (setq hits (nreverse hits))
    (cond
     ((null hits) (kb--die "no headline \"%s\" in %s" heading name))
     ((cdr hits) (kb--die "headline \"%s\" is ambiguous in %s (lines %s)"
                          heading name (mapconcat #'number-to-string hits ", "))))
    (goto-char (point-min))
    (forward-line (1- (car hits)))))

(defun kb--with-heading (name heading fn)
  "Call FN with point on the unique headline whose bare text is HEADING in file NAME.
Checks and saves the file afterwards and prints the resulting headline and planning line."
  (let* ((file (kb--resolve-file name))
         (read (kb--read file))
         report)
    (kb--with-org
     (with-temp-buffer
       (insert (car read))
       (org-mode)
       (kb--goto-heading heading name)
       (funcall fn)
       (setq report
             (concat
              (format "%s:%d: %s\n" (kb--rel file) (line-number-at-pos)
                      (buffer-substring-no-properties (line-beginning-position)
                                                      (line-end-position)))
              (save-excursion
                (forward-line 1)
                (when (looking-at "[ \t]*\\(?:\\(?:SCHEDULED\\|DEADLINE\\|CLOSED\\):.*\\)")
                  (format "  %s\n" (string-trim (match-string 0)))))))
       (kb--commit file (buffer-string) (cdr read))))
    (princ report)))

(defun kb-cmd-state (args)
  (pcase (kb--extract-root args)
    (`(,file ,heading ,state)
     (unless (member state (append kb-todo-keywords '("none")))
       (kb--die "unknown state \"%s\" (use %s or none)" state
                (string-join kb-todo-keywords ", ")))
     (kb--with-heading file heading
                       (lambda () (org-todo (if (string= state "none") 'none state)))))
    (_ (kb--usage)))
  (kill-emacs 0))

(defun kb--cmd-planning (args kind)
  (pcase (kb--extract-root args)
    (`(,file ,heading ,date)
     (unless (string= date "none") (kb--check-iso-date date))
     (kb--with-heading file heading
                       (lambda ()
                         (pcase (cons kind (string= date "none"))
                           (`(schedule . t) (org-schedule '(4)))
                           (`(schedule . nil) (org-schedule nil date))
                           (`(deadline . t) (org-deadline '(4)))
                           (`(deadline . nil) (org-deadline nil date))))))
    (_ (kb--usage)))
  (kill-emacs 0))

;;;; new, rename, refile

(defun kb-cmd-new (args)
  (pcase-let* ((`(,opts . ,pos) (kb--split-args (kb--extract-root args) '("--tags" "--body" "--created")))
               (created (kb--parse-created (cdr (assoc "--created" opts))))
               (type (car pos))
               (skeleton (cdr (assoc type kb--note-types)))
               (notes (progn (unless skeleton (kb--usage)) (kb--notes)))
               (title (pcase type
                        ("inbox" (when (cdr pos) (kb--usage)) "")
                        ("daily" (let ((d (or (cadr pos) (format-time-string "%Y-%m-%d"))))
                                   (kb--check-iso-date d) d))
                        (_ (kb--single-line (or (cadr pos) (kb--usage)) "title"))))
               (tags (kb--norm-tags (cons type (kb--norm-tags (cdr (assoc "--tags" opts))))))
               (slug (kb--slug title))
               (dup (and (not (string= type "inbox"))
                         (seq-find (lambda (n) (and (equal (plist-get n :slug) slug)
                                                    (member type (plist-get n :tags))))
                                   notes))))
    (when (and (not (string= type "inbox")) (string= slug ""))
      (kb--die "title \"%s\" has no usable characters" title))
    (when dup
      (if (string= type "daily")
          (progn (princ (format "%s\n" (plist-get dup :rel))) (kill-emacs 0))
        (kb--die "%s note \"%s\" already exists: %s" type title (plist-get dup :rel))))
    (let* ((id (kb--free-id notes created))
           (name (kb--file-name id "" (if (string= slug "") "" (concat "--" slug)) tags))
           (file (expand-file-name name (file-name-as-directory kb-root)))
           (body (or (cdr (assoc "--body" opts)) ""))
           (text (concat (format "#+title:%s\n#+date:       %s\n#+filetags:   :%s:\n#+identifier: %s\n\n"
                                 (if (string= title "") "" (concat "      " title))
                                 (kb--id-date-stamp id)
                                 (string-join tags ":") id)
                         skeleton
                         body
                         (if (or (string= body "") (string-suffix-p "\n" body)) "" "\n"))))
      (when (file-exists-p file) (kb--die "already exists: %s" (kb--rel file)))
      (kb--commit file text 'utf-8-unix)
      (princ (format "%s\n" (kb--rel file)))
      (kill-emacs 0))))

(defun kb-cmd-rename (args)
  "kb rename FILE [--title T] [--tags a,b] [--add-tags a,b] [--remove-tags a,b] [--dir DIR]"
  (pcase-let* ((`(,opts . ,pos)
                (kb--split-args (kb--extract-root args)
                                '("--title" "--tags" "--add-tags" "--remove-tags" "--dir")))
               (_ (unless (= (length pos) 1) (kb--usage)))
               (file (kb--resolve-file (car pos)))
               (name (file-name-nondirectory file)))
    (unless (string-match kb--denote-file-regexp name)
      (kb--die "not a Denote file name: %s" (car pos)))
    (let* ((id (match-string 1 name))
           (sig (or (match-string 2 name) ""))
           (old-title-part (or (match-string 3 name) ""))
           (old-tags (kb--filename-keywords (match-string 4 name)))
           (read (kb--read file))
           (scan (kb--scan-text (car read)))
           (title-opt (and (assoc "--title" opts)
                           (cons "--title" (kb--single-line (cdr (assoc "--title" opts)) "title"))))
           (title-part (if title-opt
                           (let ((s (kb--slug (cdr title-opt)))) (if (string= s "") "" (concat "--" s)))
                         old-title-part))
           (tags (kb--norm-tags
                  (if (assoc "--tags" opts)
                      (kb--norm-tags (cdr (assoc "--tags" opts)))
                    (append (seq-remove (lambda (x) (member x (kb--norm-tags (cdr (assoc "--remove-tags" opts)))))
                                        old-tags)
                            (kb--norm-tags (cdr (assoc "--add-tags" opts)))))))
           (dir-opt (assoc "--dir" opts))
           (dir (if dir-opt
                    (expand-file-name (cdr dir-opt) (file-name-as-directory kb-root))
                  (file-name-directory file)))
           (new-file (expand-file-name (kb--file-name id sig title-part tags) dir)))
      (unless (and (equal (plist-get scan :identifier) id) (equal (plist-get scan :tags) old-tags))
        (kb--die "front matter disagrees with file name (run kb validate): %s" (car pos)))
      (unless (file-in-directory-p new-file kb-root) (kb--die "destination is outside the KB"))
      (let* ((text (car read))
             (text (if title-opt (kb--text-set-header text "title" (cdr title-opt)) text))
             (text (kb--text-set-header text "filetags" (kb--tags-value tags)))
             (same-path (file-equal-p file new-file)))
        (cond
         ((and same-path (string= text (car read)))
          (princ (format "%s (unchanged)\n" (kb--rel file))))
         (t
          (kb--commit new-file text (cdr read) (unless same-path file))
          (princ (format "%s\n" (kb--rel new-file))))))
      (kill-emacs 0))))

(defun kb-cmd-refile (args)
  "kb refile SRC-FILE HEADING DEST-FILE [DEST-HEADING]: move a subtree between files."
  (pcase-let* ((`(,src ,heading ,dest . ,dest-heading) (kb--extract-root args))
               (dest-heading (car dest-heading)))
    (unless (and src heading dest) (kb--usage))
    (let* ((sfile (kb--resolve-file src))
           (dfile (kb--resolve-file dest))
           (sread (kb--read sfile))
           (dread (kb--read dfile))
           subtree src-text dest-text dest-line)
      (when (file-equal-p sfile dfile) (kb--die "source and destination are the same file"))
      (kb--with-org
       (with-temp-buffer
         (insert (car sread)) (org-mode)
         (kb--goto-heading heading src)
         (let ((beg (point)) (end (progn (org-end-of-subtree t t) (point))))
           (setq subtree (buffer-substring-no-properties beg end))
           (unless (string-suffix-p "\n" subtree) (setq subtree (concat subtree "\n")))
           (delete-region beg end))
         (setq src-text (buffer-string)))
       (with-temp-buffer
         (insert (car dread)) (org-mode)
         (let ((level 1))
           (if dest-heading
               (progn (kb--goto-heading dest-heading dest)
                      (setq level (1+ (org-current-level)))
                      (org-end-of-subtree t t))
             (goto-char (point-max)))
           (unless (or (bobp) (bolp)) (insert "\n"))
           (setq dest-line (line-number-at-pos))
           (org-paste-subtree level subtree))
         (setq dest-text (buffer-string))))
      ;; Check both files before writing either.
      (let ((errors (append (mapcar (lambda (e) (format "%s: %s" (kb--rel dfile) e))
                                    (kb--gate dfile dest-text))
                            (mapcar (lambda (e) (format "%s: %s" (kb--rel sfile) e))
                                    (kb--gate sfile src-text)))))
        (when errors
          (kb--die "refusing to refile:\n  %s" (string-join errors "\n  "))))
      ;; Destination first: a crash in between leaves a duplicate, never a loss.
      (kb--save dfile dest-text (cdr dread))
      (kb--save sfile src-text (cdr sread))
      (princ (format "moved \"%s\": %s -> %s:%d\n" heading (kb--rel sfile) (kb--rel dfile) dest-line))
      (kill-emacs 0))))

;;;; query, agenda-export

(defun kb--today ()
  (or (getenv "KB_TODAY") (format-time-string "%Y-%m-%d")))

(defun kb--date-plus (iso days)
  "ISO date string DAYS after ISO (a YYYY-MM-DD string)."
  (let* ((y (string-to-number (substring iso 0 4)))
         (m (string-to-number (substring iso 5 7)))
         (d (string-to-number (substring iso 8 10)))
         (g (calendar-gregorian-from-absolute
             (+ days (calendar-absolute-from-gregorian (list m d y))))))
    (format "%04d-%02d-%02d" (nth 2 g) (nth 0 g) (nth 1 g))))

(defun kb--ts-date (ts)
  "YYYY-MM-DD of the org time stamp string TS, or nil."
  (and ts (string-match "\\([0-9]\\{4\\}-[0-9]\\{2\\}-[0-9]\\{2\\}\\)" ts)
       (match-string 1 ts)))

(defun kb--open-tasks ()
  "Open TODO/NEXT/WAITING headings in all notes, as plists
\(:rel :line :state :heading :tags :scheduled :deadline :date :note).
:date is the earlier of the scheduled and deadline dates.  :tags are the file
keywords plus the heading's own tags.  Sorted by date (undated last), then file."
  (let (tasks)
    (kb--with-org
     (dolist (f (kb--files))
       (let* ((name (file-name-nondirectory f))
              (file-tags (and (string-match kb--denote-file-regexp name)
                              (kb--filename-keywords (match-string 4 name))))
              (rel (kb--rel f))
              (text (car (kb--read f))))
         (when (plist-get (kb--scan-text text) :open)
           (with-temp-buffer
             (insert text)
             (delay-mode-hooks (org-mode))
             (let ((note (save-excursion
                           (goto-char (point-min))
                           (let ((case-fold-search t))
                             (if (re-search-forward "^#\\+title:[ \t]*\\(.*?\\)[ \t]*$" nil t)
                                 (match-string-no-properties 1)
                               (file-name-base name))))))
               (org-map-entries
                (lambda ()
                  (let ((state (org-get-todo-state)))
                    (when (member state '("TODO" "NEXT" "WAITING"))
                      (let* ((sched (kb--ts-date (org-entry-get nil "SCHEDULED")))
                             (dead (kb--ts-date (org-entry-get nil "DEADLINE")))
                             (dates (delq nil (list sched dead))))
                        (push (list :rel rel :line (line-number-at-pos) :state state
                                    :heading (org-get-heading t t t t)
                                    :tags (sort (delete-dups
                                                 (append file-tags
                                                         (mapcar #'downcase
                                                                 (org-get-tags nil t))))
                                                #'string<)
                                    :scheduled sched :deadline dead
                                    :date (car (sort (copy-sequence dates) #'string<))
                                    :note note)
                              tasks))))))))))))
    (sort (nreverse tasks)
          (lambda (a b)
            (let ((da (or (plist-get a :date) "9999")) (db (or (plist-get b :date) "9999")))
              (string< da db))))))

(defun kb--format-task (tk)
  (format "%s:%d: %s %s%s%s%s" (plist-get tk :rel) (plist-get tk :line)
          (plist-get tk :state) (plist-get tk :heading)
          (if (plist-get tk :scheduled) (format "  SCHEDULED %s" (plist-get tk :scheduled)) "")
          (if (plist-get tk :deadline) (format "  DEADLINE %s" (plist-get tk :deadline)) "")
          (if (plist-get tk :tags) (format "  :%s:" (string-join (plist-get tk :tags) ":")) "")))

(defun kb-cmd-query (args)
  "kb query [--state S,S] [--tag T] [--before DATE] [--undated]: list open tasks."
  (let* ((undated (member "--undated" args))
         (args (remove "--undated" args)))
    (pcase-let* ((`(,opts . ,pos) (kb--split-args (kb--extract-root args)
                                                  '("--state" "--tag" "--before")))
                 (_ (when pos (kb--usage)))
                 (states (and (assoc "--state" opts)
                              (mapcar #'upcase (split-string (cdr (assoc "--state" opts)) "," t))))
                 (tag (and (assoc "--tag" opts) (downcase (cdr (assoc "--tag" opts)))))
                 (before (cdr (assoc "--before" opts))))
      (dolist (s states)
        (unless (member s '("TODO" "NEXT" "WAITING")) (kb--die "unknown state \"%s\"" s)))
      (when before (kb--check-iso-date before))
      (let ((n 0))
        (dolist (tk (kb--open-tasks))
          (when (and (or (null states) (member (plist-get tk :state) states))
                     (or (null tag) (member tag (plist-get tk :tags)))
                     (or (null before)
                         (and (plist-get tk :date) (string< (plist-get tk :date) (concat before "\0"))))
                     (or (not undated) (null (plist-get tk :date))))
            (setq n (1+ n))
            (princ (concat (kb--format-task tk) "\n"))))
        (princ (format "kb query: %d task(s)\n" n))
        (kill-emacs 0)))))

(defun kb--agenda-text ()
  "Plain-text org view of the open tasks for reading on the phone."
  (let* ((today (kb--today))
         (week (kb--date-plus today 7))
         (tasks (kb--open-tasks))
         (inbox (length (seq-filter (lambda (f) (and (string-match kb--denote-file-regexp (file-name-nondirectory f))
                                                                  (member "inbox" (kb--filename-keywords (match-string 4 (file-name-nondirectory f))))))
                                    (kb--files))))
         (sections (mapcar #'list '("Overdue" "Today" "Next 7 days" "Later"
                                    "Next" "Waiting" "Open, undated"))))
    (dolist (tk tasks)
      (let* ((date (plist-get tk :date)) (state (plist-get tk :state))
             (name (cond ((string= state "WAITING") "Waiting")
                         ((null date) (if (string= state "NEXT") "Next" "Open, undated"))
                         ((string< date today) "Overdue")
                         ((string= date today) "Today")
                         ((string< date (concat week "\0")) "Next 7 days")
                         (t "Later"))))
        (push tk (cdr (assoc name sections)))))
    (concat
     (format "#+title: Agenda\n# Generated %s by `kb agenda-export'.  Read-only: edits here are overwritten.\n\n"
             today)
     (format "Inbox: %d unprocessed capture(s)\n\n" inbox)
     (mapconcat
      (lambda (sec)
        (format "* %s (%d)\n%s" (car sec) (length (cdr sec))
                (mapconcat
                 (lambda (tk)
                   (format "- %s %s%s%s — %s\n" (plist-get tk :state) (plist-get tk :heading)
                           (if (plist-get tk :scheduled) (format " (sched %s)" (plist-get tk :scheduled)) "")
                           (if (plist-get tk :deadline) (format " (due %s)" (plist-get tk :deadline)) "")
                           (plist-get tk :note)))
                 (reverse (cdr sec)) "")))
      sections ""))))

(defun kb-cmd-agenda-export (args)
  "kb agenda-export [--print]: write export/agenda.org (or print it)."
  (let* ((print (member "--print" args))
         (rest (kb--extract-root (remove "--print" args))))
    (when rest (kb--usage))
    (let ((text (kb--agenda-text)))
      (if print
          (princ text)
        (let ((file (expand-file-name "export/agenda.org" (file-name-as-directory kb-root))))
          (make-directory (file-name-directory file) t)
          (kb--atomic-write file text 'utf-8-unix t)
          (princ (format "%s\n" (kb--rel file)))))
      (kill-emacs 0))))

;;;; install-template

(defconst kb--template-dir
  (expand-file-name "template" (file-name-directory (or load-file-name buffer-file-name)))
  "Source of the CLAUDE.md and .claude/ files deployed to the KB root.")

(defun kb-cmd-install-template (args)
  "kb install-template: copy template/CLAUDE.md and template/.claude into `kb-root'.
Existing files are overwritten; files only present in the destination are kept."
  (let ((rest (kb--extract-root args))
        (root (file-name-as-directory kb-root))
        (n 0))
    (when rest (kb--usage))
    (unless (file-directory-p root)
      (princ (format "kb: no such directory: %s\n" root))
      (kill-emacs 2))
    (dolist (src (directory-files-recursively kb--template-dir "" nil))
      (let* ((rel (file-relative-name src kb--template-dir))
             (dest (expand-file-name rel root)))
        (make-directory (file-name-directory dest) t)
        (copy-file src dest t)
        (setq n (1+ n))
        (princ (format "%s\n" rel))))
    (princ (format "installed %d file(s) into %s\n" n root))
    (kill-emacs 0)))

;;;; Entry point

(defun kb-main ()
  "Entry point: dispatch on the first remaining command line argument."
  (let* ((args (mapcar #'kb--fix-arg
                       (if (equal (car command-line-args-left) "--")
                           (cdr command-line-args-left)
                         command-line-args-left)))
         (cmd (car args)))
    (setq command-line-args-left nil)
    (pcase cmd
      ("validate" (kb-cmd-validate (cdr args)))
      ("sync-todo-tags" (kb-cmd-sync-todo-tags (cdr args)))
      ("new" (kb-cmd-new (cdr args)))
      ("rename" (kb-cmd-rename (cdr args)))
      ("refile" (kb-cmd-refile (cdr args)))
      ("query" (kb-cmd-query (cdr args)))
      ("agenda-export" (kb-cmd-agenda-export (cdr args)))
      ("install-template" (kb-cmd-install-template (cdr args)))
      ("state" (kb-cmd-state (cdr args)))
      ("schedule" (kb--cmd-planning (cdr args) 'schedule))
      ("deadline" (kb--cmd-planning (cdr args) 'deadline))
      (_ (kb--usage)))))

(provide 'kb)
;;; kb.el ends here
