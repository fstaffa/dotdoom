#!/bin/sh
# Tests for `kb validate' against throwaway fixture KBs.  Run: kb/test.sh
dir=$(cd "$(dirname "$0")" && pwd)
kb="$dir/kb"
tmp=$(mktemp -d "${TMPDIR:-/tmp}/kbtest.XXXXXX")
trap 'rm -rf "$tmp"' EXIT
fail=0

note() { # note PATH ID TAGS BODY  (tags like ":a:b:" or "")
  mkdir -p "$(dirname "$1")"
  printf '#+title: t\n#+date: [2026-10-05 Mon]\n#+filetags: %s\n#+identifier: %s\n\n%s\n' "$3" "$2" "$4" > "$1"
}

# expect NAME EXPECTED_EXIT GREP_PATTERN ARGS...
expect() {
  name=$1; code=$2; pat=$3; shift 3
  out=$("$kb" validate "$@" 2>&1); got=$?
  if [ "$got" != "$code" ]; then
    echo "FAIL $name: exit $got, expected $code"; echo "$out"; fail=1; return
  fi
  if [ -n "$pat" ] && ! printf '%s\n' "$out" | grep -q -- "$pat"; then
    echo "FAIL $name: output lacks /$pat/"; echo "$out"; fail=1; return
  fi
  echo "ok   $name"
}

# --- a clean KB -------------------------------------------------------------
g="$tmp/good"; mkdir -p "$g"
note "$g/20261004T101500--anna__person_work.org" 20261004T101500 ":person:work:" "Hi"
note "$g/20260301T090000--billing__project_todo.org" 20260301T090000 ":project:todo:" \
"* TODO Send estimate
DEADLINE: <2026-10-10 Sat>
See [[denote:20261004T101500][Anna]] and [[denote:20261004T101500::#x][Anna x]]"
note "$g/20261005T093012__inbox.org" 20261005T093012 ":inbox:" "Call landlord"
printf '* TODO plain task\nSCHEDULED: <2026-10-05 Mon>\n' > "$g/tasks.org"
# TODO lines and bad dates inside source blocks must be ignored
note "$g/20240711T211507--golang__reference.org" 20240711T211507 ":reference:" \
"#+begin_src org
* TODO not a task <2026-10-10 Fri>
[[denote:99999999T999999]]
#+end_src"
mkdir -p "$g/org" "$g/roam" "$g/.git"   # ignored legacy/system dirs
printf 'not a denote name\n' > "$g/org/whatever.org"
expect clean 0 "0 errors, 0 warnings" "$g"

# --- individual failures ----------------------------------------------------
b="$tmp/bad"
reset() { rm -rf "$b"; mkdir -p "$b"; }

reset; note "$b/20261004T101500--a__person.org" 20261004T101501 ":person:" "x"
expect id-mismatch 1 "does not match file name ID" "$b"

reset; note "$b/20261004T101500--a__person.org" 20261004T101500 ":person:work:" "x"
expect tag-mismatch 1 "filetags" "$b"

reset; note "$b/20261004T101500--a__person.org" 20261004T101500 ":person:" "[[denote:20000101T000000]]"
expect broken-link 1 "broken link" "$b"

reset; note "$b/20261004T101500--a__person.org" 20261004T101500 ":person:" "SCHEDULED: <2026-10-10 Fri>"
expect wrong-weekday 1 "is a Sat, not Fri" "$b"

reset; note "$b/20261004T101500--a__person.org" 20261004T101500 ":person:" "<2026-02-30 Mon>"
expect invalid-date 1 "invalid date" "$b"

reset
note "$b/20261004T101500--a__person.org" 20261004T101500 ":person:" "x"
note "$b/sub/20261004T101500--b__person.org" 20261004T101500 ":person:" "x"
expect duplicate-id 1 "duplicate ID" "$b"

reset; note "$b/20261004T101500--a__person.org" 20261004T101500 ":person:" "x"
cp "$b/20261004T101500--a__person.org" "$b/20261004T101500--a__person.sync-conflict-20261005-101500-ABCDEFG.org"
expect sync-conflict 1 "Syncthing conflict" "$b"

reset; printf 'x\n' > "$b/notes.org"
expect non-denote-name 1 "not a Denote file name" "$b"

reset; note "$b/20261005T093012--a__project.org" 20261005T093012 ":project:" "* TODO open"
expect todo-tag-missing 0 "open tasks but no \`todo'" "$b"
expect todo-tag-missing-strict 1 "" --strict "$b"

reset; note "$b/20261005T093012--a__project_todo.org" 20261005T093012 ":project:todo:" "* DONE closed"
expect todo-tag-stale 0 "no open tasks" "$b"

reset; note "$b/20261005T093012--a__project.org" 20261005T093012 ":project:" "[[id:abc-123][old]]"
expect legacy-id-link 0 "legacy id: link" "$b"

reset; printf '* TODO x\nSCHEDULED: <2026-10-10 Fri>\n' > "$b/tasks.org"
expect tasks-org-dates 1 "tasks.org:2" "$b"

# --- sync-todo-tags ---------------------------------------------------------
# cmd NAME EXPECTED_EXIT GREP_PATTERN KBCMD ARGS...   (like expect, any command)
cmd() {
  name=$1; code=$2; pat=$3; shift 3
  out=$("$kb" "$@" 2>&1); got=$?
  if [ "$got" != "$code" ]; then echo "FAIL $name: exit $got, expected $code"; echo "$out"; fail=1; return; fi
  if [ -n "$pat" ] && ! printf '%s\n' "$out" | grep -q -- "$pat"; then
    echo "FAIL $name: output lacks /$pat/"; echo "$out"; fail=1; return; fi
  echo "ok   $name"
}
# has NAME PATH   /   hasnt NAME PATH   /   contains NAME PATH PATTERN
has()   { if [ -e "$2" ]; then echo "ok   $1"; else echo "FAIL $1: missing $2"; fail=1; fi; }
hasnt() { if [ ! -e "$2" ]; then echo "ok   $1"; else echo "FAIL $1: unexpected $2"; fail=1; fi; }
contains() { if grep -q -- "$3" "$2"; then echo "ok   $1"; else echo "FAIL $1: $2 lacks /$3/"; fail=1; fi; }

reset
note "$b/20260101T000000--open__project.org"       20260101T000000 ":project:" "* TODO a"          # needs todo
note "$b/20260102T000000--open-sorted__work.org"   20260102T000000 ":work:" "* NEXT a"             # keywords stay sorted: todo before work
note "$b/20260103T000000--open-untagged.org"       20260103T000000 "" "* WAITING a"                # no keywords at all
note "$b/20260104T000000--done__project_todo.org"  20260104T000000 ":project:todo:" "* DONE a"     # stale todo
note "$b/20260105T000000--done-only__todo.org"     20260105T000000 ":todo:" "* DONE a"            # only tag removed
note "$b/20260106T000000--fine__project_todo.org"  20260106T000000 ":project:todo:" "* TODO a"     # unchanged
note "$b/20260107T000000__inbox.org"         20260107T000000 ":inbox:" "* TODO quick"        # no title
note "$b/20260108T000000--mismatch__project.org"   20260108T000000 ":other:" "* TODO a"            # skipped
note "$b/20260109T000000--collide__project.org"    20260109T000000 ":project:" "* TODO a"
note "$b/20260109T000000--collide__project_todo.org" 20260109T000000 ":project:todo:" "* TODO a"   # name taken
printf '* TODO plain\n' > "$b/tasks.org"
cp -r "$b" "$tmp/before"

cmd sync-dry-run 0 "would rename" sync-todo-tags --dry-run "$b"
if diff -r "$tmp/before" "$b" >/dev/null; then echo "ok   dry-run-changes-nothing"; else echo "FAIL dry-run modified files"; fail=1; fi

cmd sync-run 0 "renamed" sync-todo-tags "$b"
has    adds-todo             "$b/20260101T000000--open__project_todo.org"
hasnt  old-name-gone         "$b/20260101T000000--open__project.org"
contains filetags-updated    "$b/20260101T000000--open__project_todo.org" "^#+filetags: :project:todo:$"
has    sorted-insert         "$b/20260102T000000--open-sorted__todo_work.org"
contains filetags-sorted     "$b/20260102T000000--open-sorted__todo_work.org" "^#+filetags: :todo:work:$"
has    adds-first-keyword    "$b/20260103T000000--open-untagged__todo.org"
contains filetags-from-empty "$b/20260103T000000--open-untagged__todo.org" "^#+filetags: :todo:$"
has    removes-todo          "$b/20260104T000000--done__project.org"
contains filetags-removed    "$b/20260104T000000--done__project.org" "^#+filetags: :project:$"
has    removes-last-keyword  "$b/20260105T000000--done-only.org"
contains filetags-emptied    "$b/20260105T000000--done-only.org" "^#+filetags:$"
has    unchanged-untouched   "$b/20260106T000000--fine__project_todo.org"
has    inbox-renamed-in-place "$b/20260107T000000__inbox_todo.org"
has    mismatch-skipped      "$b/20260108T000000--mismatch__project.org"
has    collision-skipped     "$b/20260109T000000--collide__project.org"
has    tasks-org-untouched   "$b/tasks.org"
cmd sync-idempotent 0 "0 change" sync-todo-tags "$b"
rm "$b/20260108T000000--mismatch__project.org" "$b/20260109T000000--collide__project.org"
cmd validate-after-sync 0 "0 errors, 0 warnings" validate --strict "$b"

reset; note "$b/20260101T000000--open__project.org" 20260101T000000 ":project:" "* TODO a"
cmd validate-fix 0 "0 errors, 0 warnings" validate --fix --strict "$b"
has fix-renamed "$b/20260101T000000--open__project_todo.org"

# --- state / schedule / deadline --------------------------------------------
reset
printf '* TODO Send estimate :work:\nBody text.\n* TODO Water plants\nSCHEDULED: <2026-10-05 Mon +1w>\n* TODO Dup\n* TODO Dup\n' > "$b/tasks.org"
export KB_ROOT="$b"

cmd schedule 0 "SCHEDULED: <2026-10-10 Sat>" schedule tasks.org "Send estimate" 2026-10-10
cmd deadline 0 "DEADLINE: <2026-10-12 Mon>" deadline tasks.org "Send estimate" 2026-10-12
cmd state-next 0 "^tasks.org:1: \* NEXT Send estimate :work:$" state tasks.org "Send estimate" NEXT
contains tags-not-realigned "$b/tasks.org" "^\* NEXT Send estimate :work:$"
contains body-preserved     "$b/tasks.org" "^Body text.$"
cmd state-done 0 "CLOSED: \[" state tasks.org "Send estimate" DONE
cmd state-reopen 0 "^tasks.org:1: \* TODO" state tasks.org "Send estimate" TODO
if grep -q "CLOSED" "$b/tasks.org"; then echo "FAIL reopen keeps CLOSED"; fail=1; else echo "ok   reopen-removes-closed"; fi
cmd state-none 0 "^tasks.org:1: \* Send estimate" state tasks.org "Send estimate" none
cmd schedule-none 0 "" schedule tasks.org "Send estimate" none
contains schedule-removed-keeps-deadline "$b/tasks.org" "DEADLINE: <2026-10-12 Mon>"
cmd repeater-advances 0 "SCHEDULED: <2026-10-12 Mon +1w>" state tasks.org "Water plants" DONE
contains repeater-still-todo "$b/tasks.org" "^\* TODO Water plants$"
cmd ambiguous 1 "ambiguous" state tasks.org "Dup" DONE
cmd missing-heading 1 "no headline" state tasks.org "Nope" DONE
cmd bad-date 1 "invalid date" schedule tasks.org "Dup" 2026-02-30
cmd bad-date-format 1 "invalid date" schedule tasks.org "Dup" tomorrow
cmd bad-state 1 "unknown state" state tasks.org "Dup" MAYBE
cmd missing-file 1 "no such file" state nothere.org "Dup" DONE
cmd outside-kb 1 "outside the KB" state /etc/hosts "Dup" DONE
cmd state-usage 2 "usage" state tasks.org "Dup"
cmd root-option 0 "SCHEDULED" schedule tasks.org "Send estimate" 2026-10-10 --root "$b"
unset KB_ROOT

# --- new ---------------------------------------------------------------------
reset; export KB_ROOT="$b"
p=$("$kb" new person "Anna Novák" --tags work,Work); rc=$?
if [ $rc = 0 ] && printf '%s\n' "$p" | grep -Eq '^[0-9]{8}T[0-9]{6}--anna-novak__person_work\.org$'; then echo "ok   new-person-name"; else echo "FAIL new-person-name: rc=$rc out=$p"; fail=1; fi
contains new-person-title    "$b/$p" "^#+title:      Anna Novák$"
contains new-person-skeleton "$b/$p" "^\* Notes$"
cmd new-duplicate 1 "already exists" new person "Anna Novak"
p=$("$kb" new project "Billing migration")
contains new-project-skeleton "$b/$p" "^\* Tasks$"
a=$("$kb" new reference "Alpha"); c=$("$kb" new reference "Beta")
if [ "$a" != "$c" ] && [ -e "$b/$a" ] && [ -e "$b/$c" ]; then echo "ok   new-same-second-distinct-ids"; else echo "FAIL ids: $a $c"; fail=1; fi
d1=$("$kb" new daily 2026-10-05); d2=$("$kb" new daily 2026-10-05)
if [ "$d1" = "$d2" ] && printf '%s' "$d1" | grep -q -- '--2026-10-05__daily\.org'; then echo "ok   new-daily-idempotent"; else echo "FAIL daily: $d1 / $d2"; fail=1; fi
i=$("$kb" new inbox --body "Call landlord about boiler")
if printf '%s' "$i" | grep -Eq '^[0-9]{8}T[0-9]{6}__inbox\.org$'; then echo "ok   new-inbox-name"; else echo "FAIL inbox name: $i"; fail=1; fi
contains new-inbox-body "$b/$i" "^Call landlord about boiler$"
cmd new-validates 0 "0 errors" validate --strict "$b"
cmd new-bad-type 2 "usage" new nonsense "x"
cmd new-missing-title 2 "usage" new person
cmd new-bad-daily-date 1 "invalid date" new daily 2026-13-01
# --created sets the ID and #+date; same second is bumped; bad values are refused
c1=$("$kb" new reference "Created one" --created "2021-07-31 14:04:00"); c2=$("$kb" new reference "Created two" --created "2021-07-31 14:04")
contains new-created-date "$b/$c1" "^#+date:       \[2021-07-31 Sat 14:04\]$"
cmd new-created-bad-date 1 "invalid date" new reference "X" --created 2021-02-30
cmd new-created-bad-time 1 "invalid time" new reference "X" --created "2021-07-31 25:00"

# --- rename (promote the inbox capture) ------------------------------------
cmd rename-promote 0 "^[0-9]\{8\}T[0-9]\{6\}--call-landlord__personal\.org$" \
  rename "$i" --title "Call landlord" --remove-tags inbox --add-tags personal
n=$(ls "$b" | grep -- '--call-landlord__personal\.org')
contains rename-title-updated "$b/$n" "^#+title:      Call landlord$"
contains rename-tags-updated  "$b/$n" "^#+filetags:   :personal:$"
contains rename-body-kept     "$b/$n" "^Call landlord about boiler$"
cmd rename-validates 0 "0 errors" validate --strict "$b"
cmd rename-unchanged 0 "unchanged" rename "$n" --tags personal
cmd rename-retag 0 "__project_work\.org" rename "$n" --tags work,project
note "$b/20240202T000000--one__reference.org" 20240202T000000 ":reference:" "x"
note "$b/20240202T000000--two__reference.org" 20240202T000000 ":reference:" "y"      # same ID on purpose
cmd rename-collision 1 "already exists" rename 20240202T000000--one__reference.org --title "two"
rm "$b/20240202T000000--one__reference.org" "$b/20240202T000000--two__reference.org"
note "$b/20250101T000000.org" 20250101T000000 "" "x"; sed -i.bak '/^#+filetags:/d' "$b/20250101T000000.org"; rm "$b/20250101T000000.org.bak"
cmd rename-adds-missing-filetags 0 "20250101T000000__x\.org" rename 20250101T000000.org --add-tags x
cmd rename-validates-again 0 "0 errors" validate "$b"

# --- refile ----------------------------------------------------------------
reset
printf '* TODO Keep me\n* TODO Move me :work:\nSCHEDULED: <2026-10-10 Sat>\nbody line\n** TODO child\n* TODO Other\n' > "$b/tasks.org"
note "$b/20260301T090000--proj__project.org" 20260301T090000 ":project:" "* Tasks
** TODO existing
* Notes"
cmd refile-to-end 0 "moved \"Move me\"" refile tasks.org "Move me" 20260301T090000--proj__project.org
contains refile-arrives    "$b/20260301T090000--proj__project.org" "^\* TODO Move me :work:$"
contains refile-keeps-plan "$b/20260301T090000--proj__project.org" "SCHEDULED: <2026-10-10 Sat>"
contains refile-keeps-child "$b/20260301T090000--proj__project.org" "^\*\* TODO child$"
if grep -q "Move me" "$b/tasks.org"; then echo "FAIL refile left source copy"; fail=1; else echo "ok   refile-removed-from-source"; fi
contains refile-keeps-others "$b/tasks.org" "^\* TODO Keep me$"
contains refile-keeps-others2 "$b/tasks.org" "^\* TODO Other$"
cmd refile-under-heading 0 "moved \"Keep me\"" refile tasks.org "Keep me" 20260301T090000--proj__project.org "Tasks"
contains refile-level-adjusted "$b/20260301T090000--proj__project.org" "^\*\* TODO Keep me$"
cmd refile-child-under-heading 0 "moved" refile 20260301T090000--proj__project.org "child" tasks.org "Other"
contains refile-child-level "$b/tasks.org" "^\*\* TODO child$"
cmd refile-same-file 1 "same file" refile tasks.org "Other" tasks.org
cmd refile-missing-src 1 "no headline" refile tasks.org "Nope" 20260301T090000--proj__project.org
cmd refile-missing-dest-heading 1 "no headline" refile tasks.org "Other" 20260301T090000--proj__project.org "Nope"
cmd refile-usage 2 "usage" refile tasks.org
unset KB_ROOT

# --- regression tests from the code review ---------------------------------
pass() { echo "ok   $1"; }
failt() { echo "FAIL $1: $2"; fail=1; }
check() { if [ "$2" = "$3" ]; then pass "$1"; else failt "$1" "got [$2], expected [$3]"; fi; }
check new-created-id "$c1" "20210731T140400--created-one__reference.org"
check new-created-collision-bumped "$c2" "20210731T140401--created-two__reference.org"
count_files() { find "$b" -type f | wc -l | tr -d ' '; }

# headings like `Next steps' are not tasks
reset; export KB_ROOT="$b"
note "$b/20260101T000000--a__person.org" 20260101T000000 ":person:" "* Next steps
* todo list
* Waiting for reply"
cmd case-sensitive-sync 0 "0 change" sync-todo-tags "$b"
cmd case-sensitive-validate 0 "0 errors, 0 warnings" validate --strict "$b"

# a newline in a title must not inject front matter or headings
t=$(printf 'Evil\n* TODO injected')
n0=$(count_files)
cmd newline-title-new 1 "single line" new reference "$t"
cmd newline-title-rename 1 "single line" rename 20260101T000000--a__person.org --title "$t"
check newline-title-writes-nothing "$(count_files)" "$n0"

# CRLF files stay CRLF through refile and state
reset
printf '* TODO Move me\r\nbody\r\n* TODO Keep\r\n' > "$b/tasks.org"
printf '#+title: t\r\n#+date: [2026-10-05 Mon]\r\n#+filetags: :project:\r\n#+identifier: 20260301T090000\r\n\r\n* Tasks\r\n' > "$b/20260301T090000--p__project.org"
"$kb" refile tasks.org "Move me" 20260301T090000--p__project.org "Tasks" >/dev/null
cr=$(printf '\r')
for f in tasks.org 20260301T090000--p__project.org; do
  check "crlf-kept-after-refile-$f" "$(grep -c "$cr\$" "$b/$f")" "$(wc -l < "$b/$f" | tr -d ' ')"
done
"$kb" state tasks.org Keep NEXT >/dev/null
check crlf-kept-after-state "$(grep -c "$cr\$" "$b/tasks.org")" "$(wc -l < "$b/tasks.org" | tr -d ' ')"

# edits change only the lines they must: no trailing newline, trailing spaces, file mode
reset
printf '* TODO a\nkeep this line   \n* TODO b' > "$b/tasks.org"
chmod 640 "$b/tasks.org"; cp "$b/tasks.org" "$tmp/before.org"
"$kb" state tasks.org a NEXT >/dev/null
check byte-diff-two-lines "$(diff "$tmp/before.org" "$b/tasks.org" | grep -c '^[<>]')" 2
check no-final-newline-kept "$(tail -c 8 "$b/tasks.org")" "* TODO b"
check file-mode-kept "$(ls -l "$b/tasks.org" | cut -c1-10)" "-rw-r-----"
check no-temp-files-left "$(find "$b" -name '.kb-tmp-*' | wc -l | tr -d ' ')" 0

# non-UTF-8 locale with non-ASCII title and body
reset
p=$(env LANG=C LC_ALL=C "$kb" new reference "Zürich" --body "ü body"); rc=$?
check c-locale-new-exit "$rc" 0
case $p in *--zurich__reference.org) pass c-locale-slug;; *) failt c-locale-slug "$p";; esac
contains c-locale-title "$b/$p" "^#+title:      Zürich$"
contains c-locale-body  "$b/$p" "^ü body$"

# emptied #+filetags gets its spacing back
reset
note "$b/20260105T000000--x__todo.org" 20260105T000000 ":todo:" "* DONE a"
"$kb" sync-todo-tags "$b" >/dev/null
contains filetags-emptied-2 "$b/20260105T000000--x.org" "^#+filetags:$"
printf '* TODO again\n' >> "$b/20260105T000000--x.org"
"$kb" sync-todo-tags "$b" >/dev/null
contains filetags-respaced "$b/20260105T000000--x__todo.org" "^#+filetags:   :todo:$"   # Denote style padding

# renaming to a title with the same slug still updates #+title
reset
note "$b/20260106T000000--foo__reference.org" 20260106T000000 ":reference:" "x"
cmd rename-same-slug 0 "20260106T000000--foo__reference.org" rename 20260106T000000--foo__reference.org --title "FOO!"
contains rename-same-slug-title "$b/20260106T000000--foo__reference.org" "^#+title: FOO!$"

# validate before save: refuse edits that add errors, leave everything untouched
reset
n0=$(count_files)
cmd gate-unterminated-block 1 "unterminated" new inbox --body "$(printf '#+begin_src\nx')"
cmd gate-wrong-weekday 1 "is a Sat, not Fri" new inbox --body "due <2026-10-10 Fri>"
cmd gate-broken-link 1 "broken link" new inbox --body "see [[denote:20000101T000000]]"
check gate-writes-nothing "$(count_files)" "$n0"

reset
note "$b/20260107T000000--a__reference.org" 20260107T000000 ":reference:" "x"
cmd gate-rename-into-ignored-path 1 "ignored path" rename 20260107T000000--a__reference.org --dir archive/legacy
[ -e "$b/20260107T000000--a__reference.org" ] && pass gate-rename-left-file || failt gate-rename-left-file missing

# a file that is already broken can still be edited, as long as the edit adds no error
reset
printf '* TODO a\nSCHEDULED: <2026-10-10 Fri>\n* TODO b\n' > "$b/tasks.org"
cmd gate-preexisting-error-tolerated 0 "NEXT b" state tasks.org b NEXT
cmd gate-still-reports-preexisting 1 "is a Sat, not Fri" validate "$b"

# refile that would introduce an error changes neither file
reset
printf '* TODO x\nSCHEDULED: <2026-10-10 Fri>\n' > "$b/tasks.org"
printf '#+title: t\n#+date: [2026-10-05 Mon]\n#+filetags: :project:\n#+identifier: 20260301T090000\n\n* Tasks\n' > "$b/20260301T090000--p__project.org"
cp "$b/tasks.org" "$tmp/t.before"; cp "$b/20260301T090000--p__project.org" "$tmp/p.before"
cmd gate-refile-refused 1 "refusing to refile" refile tasks.org x 20260301T090000--p__project.org Tasks
cmp -s "$tmp/t.before" "$b/tasks.org" && cmp -s "$tmp/p.before" "$b/20260301T090000--p__project.org" && pass gate-refile-untouched || failt gate-refile-untouched "files changed"
unset KB_ROOT

# arguments that Emacs itself would interpret must reach kb untouched
reset; export KB_ROOT="$b"
p=$("$kb" new inbox --body "--version"); rc=$?
if [ $rc = 0 ] && [ -e "$b/$p" ] && grep -q -- '^--version$' "$b/$p"; then echo "ok   emacs-options-not-interpreted"; else echo "FAIL emacs-options: rc=$rc out=$p"; fail=1; fi
unset KB_ROOT

# --- query / agenda-export ---------------------------------------------------
reset; export KB_ROOT="$b" KB_TODAY=2026-10-05
printf '#+title: Billing\n#+date: [2026-10-05 Mon]\n#+filetags: :project:todo:work:\n#+identifier: 20260301T090000\n\n* TODO Send estimate :urgent:\nDEADLINE: <2026-10-10 Sat>\n* NEXT Call bank\n* WAITING Reply\nSCHEDULED: <2026-10-04 Sun>\n* DONE old\n' > "$b/20260301T090000--billing__project_todo_work.org"
printf '* TODO plain\nSCHEDULED: <2026-10-05 Mon>\n* TODO someday\n' > "$b/tasks.org"
check query-all "$("$kb" query | tail -1)" "kb query: 5 task(s)"
check query-state "$("$kb" query --state next,waiting | tail -1)" "kb query: 2 task(s)"
check query-tag-inherits-file-keyword "$("$kb" query --tag work | tail -1)" "kb query: 3 task(s)"
check query-heading-tag "$("$kb" query --tag urgent | tail -1)" "kb query: 1 task(s)"
check query-before-inclusive "$("$kb" query --before 2026-10-05 | tail -1)" "kb query: 2 task(s)"
check query-undated "$("$kb" query --undated | tail -1)" "kb query: 2 task(s)"
check query-sorted-by-date "$("$kb" query | head -1 | cut -d' ' -f2-3)" "WAITING Reply"
"$kb" query --state bogus >/dev/null 2>&1; check query-bad-state $? 1
"$kb" agenda-export >/dev/null; check agenda-written "$(grep -c '^\* ' "$b/export/agenda.org")" 7
check agenda-today "$(grep -c 'TODO plain' "$b/export/agenda.org")" 1
check agenda-export-not-scanned "$("$kb" validate "$b" | tail -1)" "kb validate: 2 files, 0 errors, 0 warnings"
unset KB_ROOT KB_TODAY

expect usage 2 "usage" --bogus
expect missing-dir 2 "no such directory" "$tmp/nope"

exit $fail
