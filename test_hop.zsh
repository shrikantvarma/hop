#!/bin/zsh
# Tests for hop. Run: zsh test_hop.zsh
emulate -L zsh
source "${0:A:h}/hop.plugin.zsh"

typeset -i pass=0 fail=0
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

check() {  # check <label> <expected> <actual>
    if [[ "$2" == "$3" ]]; then
        print "  ok   $1"; (( pass++ ))
    else
        print "  FAIL $1"
        print "       expected: ${(qqq)2}"
        print "       actual:   ${(qqq)3}"
        (( fail++ ))
    fi
}

# --- fixture -------------------------------------------------------------
mkdir -p "$tmp/plain" "$tmp/with space" "$tmp/iCloud~md~obsidian/Docs"
mkdir -p "$HOME/.hop_test_home_dir"

rc="$tmp/hoprc"
cat > "$rc" <<EOF
# a comment line
                                    # indented comment, then a blank line

plain        $tmp/plain
spaced       $tmp/with space
tilde        ~/.hop_test_home_dir
embedded     $tmp/iCloud~md~obsidian/Docs
gone         $tmp/does_not_exist
trailing     $tmp/plain          # trailing comment
orphan
EOF

out="$(_hop_parse "$rc" 2>"$tmp/err")"
errs="$(<"$tmp/err")"

# --- assertions ----------------------------------------------------------
print "_hop_parse"

field() { print -r -- "$out" | awk -F'\t' -v a="$1" -v n="$2" '$1==a {print $n; exit}'; }

check "comments and blank lines are dropped (6 valid entries)" \
      "6" "$(print -r -- "$out" | grep -c .)"

check "plain path resolves" \
      "$tmp/plain" "$(field plain 2)"

check "path containing spaces is kept whole" \
      "$tmp/with space" "$(field spaced 2)"

check "leading ~ expands to \$HOME" \
      "$HOME/.hop_test_home_dir" "$(field tilde 2)"

check "embedded ~ chars are NOT expanded" \
      "$tmp/iCloud~md~obsidian/Docs" "$(field embedded 2)"

check "existing dir marked ok" \
      "ok" "$(field plain 3)"

check "missing dir marked missing" \
      "missing" "$(field gone 3)"

check "missing dir still emitted, not dropped" \
      "$tmp/does_not_exist" "$(field gone 2)"

check "trailing comment stripped from path" \
      "$tmp/plain" "$(field trailing 2)"

check "malformed line skipped, not emitted" \
      "" "$(field orphan 2)"

check "malformed line reported with line number" \
      "1" "$(print -r -- "$errs" | grep -c 'hoprc:10: malformed')"

check "unreadable rc returns non-zero" \
      "1" "$(_hop_parse "$tmp/nope" >/dev/null 2>&1; print $?)"

# --- depth column ---------------------------------------------------------
print ""
print "_hop_parse depth"

dtmp="$tmp/depth"; mkdir -p "$dtmp/plain" "$dtmp/Chapter 3"
drc="$tmp/depthrc"
cat > "$drc" <<EOF
nodepth      $dtmp/plain
zero         $dtmp/plain    depth=0
three        $dtmp/plain    depth=3
spaced       $dtmp/Chapter 3
bad          $dtmp/plain    depth=abc
EOF
dout="$(_hop_parse "$drc" 2>"$tmp/derr")"
dfield() { print -r -- "$dout" | awk -F'\t' -v a="$1" -v n="$2" '$1==a {print $n; exit}'; }

check "depth defaults to 2 when absent" \
      "2" "$(dfield nodepth 4)"

check "depth=0 parsed" \
      "0" "$(dfield zero 4)"

check "depth=3 parsed" \
      "3" "$(dfield three 4)"

check "depth token stripped from path" \
      "$dtmp/plain" "$(dfield three 2)"

check "path ending in a number is NOT read as depth" \
      "$dtmp/Chapter 3" "$(dfield spaced 2)"

check "path ending in a number keeps default depth" \
      "2" "$(dfield spaced 4)"

check "non-numeric depth falls back to 2" \
      "2" "$(dfield bad 4)"

check "non-numeric depth warns with line number" \
      "1" "$(print -r -- "$(<$tmp/derr)" | grep -c 'depthrc:5')"

# A favorited FILE is a valid bookmark — Ctrl-S can star a file, and Enter
# then lands in its parent. Status must not be "missing" just because the
# path is not a directory.
touch "$dtmp/note.md"
frc0="$tmp/filerc"
print -r -- "note	$dtmp/note.md" > "$frc0"
check "a file bookmark is status ok, not missing" \
      "ok" "$(_hop_parse "$frc0" | cut -f3)"

print -r -- "ghost	$dtmp/nope.md" > "$frc0"
check "a nonexistent file bookmark is still missing" \
      "missing" "$(_hop_parse "$frc0" | cut -f3)"

rmdir "$HOME/.hop_test_home_dir"

# --- _hop_children -------------------------------------------------------
print ""
print "_hop_children"

kid="$tmp/kids"
mkdir -p "$kid/Assets" "$kid/Projects" "$kid/.git" "$kid/node_modules" "$kid/.hidden_keep"
touch "$kid/a_file.md" "$kid/b_file.txt"

# The vault is reached through symlinks, so cover that explicitly.
ln -s "$kid" "$tmp/link_to_kids"

names() { _hop_children "$1" | cut -f2 | sort | tr '\n' ' '; }

check "lists subdirs with a trailing slash" \
      "Assets/ Projects/ " \
      "$(_hop_children "$kid" | awk -F'\t' '$3=="dir"' | cut -f2 | grep -v '^\.' | sort | tr '\n' ' ')"

check "lists files too" \
      "a_file.md b_file.txt " \
      "$(_hop_children "$kid" | awk -F'\t' '$3=="file"' | cut -f2 | sort | tr '\n' ' ')"

check "tags kind correctly for dirs" \
      "dir" \
      "$(_hop_children "$kid" | awk -F'\t' '$2=="Assets/"{print $3}')"

check "tags kind correctly for files" \
      "file" \
      "$(_hop_children "$kid" | awk -F'\t' '$2=="a_file.md"{print $3}')"

check "directories are emitted before files" \
      "dir" \
      "$(_hop_children "$kid" | head -1 | cut -f3)"

check "skips .git and node_modules" \
      "0" \
      "$(_hop_children "$kid" | cut -f2 | grep -cE '^(\.git|node_modules)/$')"

check "keeps non-noise dotdirs" \
      "1" \
      "$(_hop_children "$kid" | cut -f2 | grep -c '^\.hidden_keep/$')"

check "emits absolute paths in field 1" \
      "$kid/Assets" \
      "$(_hop_children "$kid" | awk -F'\t' '$2=="Assets/"{print $1}')"

check "descends through a SYMLINKED parent (the vault case)" \
      "$(names "$kid")" "$(names "$tmp/link_to_kids")"

check "empty dir yields nothing" \
      "" "$(_hop_children "$kid/Assets")"

check "nonexistent parent returns non-zero" \
      "1" "$(_hop_children "$tmp/nope" >/dev/null 2>&1; print $?)"

# --- _hop_split_expect ---------------------------------------------------
print ""
print "_hop_split_expect"

# fzf --expect: line 1 = key (empty on plain Enter), line 2 = selected record.
check "Enter yields empty key and the path" \
      $'\t/Users/x/Code' \
      "$(_hop_split_expect $'\n/Users/x/Code\tcode    /Users/x/Code')"

check "tab yields key=tab and the path" \
      $'tab\t/Users/x/Code' \
      "$(_hop_split_expect $'tab\n/Users/x/Code\tcode    /Users/x/Code')"

check "btab yields key=btab and the path" \
      $'btab\t/Users/x/Code' \
      "$(_hop_split_expect $'btab\n/Users/x/Code\tcode    /Users/x/Code')"

check "right arrow yields key=right and the path" \
      $'right\t/Users/x/Code' \
      "$(_hop_split_expect $'right\n/Users/x/Code\tcode    /Users/x/Code')"

check "left arrow yields key=left and the path" \
      $'left\t/Users/x/Code' \
      "$(_hop_split_expect $'left\n/Users/x/Code\tcode    /Users/x/Code')"

check "path containing spaces survives the split" \
      $'tab\t/Users/x/Daily Notes' \
      "$(_hop_split_expect $'tab\n/Users/x/Daily Notes\tdaily   /Users/x/Daily Notes')"

check "[missing] marker in display does not leak into the path" \
      $'\t/Users/x/gone' \
      "$(_hop_split_expect $'\n/Users/x/gone\tgone    /Users/x/gone  [missing]')"

# --- _hop_index -----------------------------------------------------------
print ""
print "_hop_index"

ix="$tmp/ix"
mkdir -p "$ix/root/sub/deep" "$ix/root/.git" "$ix/flat"
touch "$ix/root/top.md" "$ix/root/sub/mid.md" "$ix/root/sub/deep/low.md" "$ix/root/.git/config"

irecs() { printf '%s\n' "$@"; }

# depth=0 -> only the bookmark itself
i0="$(irecs "r	$ix/root	ok	0" | _hop_index)"
check "depth=0 yields exactly one record" \
      "1" "$(print -r -- "$i0" | grep -c .)"
check "depth=0 record is the bookmark, favorited, depth 0" \
      "dir	$ix/root	r	1	0" "$i0"

# depth=1 -> bookmark + immediate children
i1="$(irecs "r	$ix/root	ok	1" | _hop_index)"
check "depth=1 includes immediate subdir" \
      "1" "$(print -r -- "$i1" | grep -c '	r/sub	')"
check "depth=1 includes immediate file" \
      "1" "$(print -r -- "$i1" | grep -c '	r/top.md	')"
check "depth=1 excludes grandchildren" \
      "0" "$(print -r -- "$i1" | grep -c 'r/sub/mid.md')"

# depth=2 -> two levels
i2="$(irecs "r	$ix/root	ok	2" | _hop_index)"
check "depth=2 includes grandchildren" \
      "1" "$(print -r -- "$i2" | grep -c '	r/sub/mid.md	')"
check "depth=2 excludes great-grandchildren" \
      "0" "$(print -r -- "$i2" | grep -c 'r/sub/deep/low.md')"

check "indexed items are not favorited" \
      "0" "$(print -r -- "$i2" | awk -F'\t' '$3=="r/sub"{print $4}')"

check "bookmark itself is favorited" \
      "1" "$(print -r -- "$i2" | awk -F'\t' '$3=="r"{print $4}')"

check "depth field counts levels below the bookmark" \
      "2" "$(print -r -- "$i2" | awk -F'\t' '$3=="r/sub/mid.md"{print $5}')"

check "skip list is honoured" \
      "0" "$(print -r -- "$i2" | grep -c '\.git')"

# Order-independent: emission order between the dir and file find passes is
# incidental — _hop_rank owns ordering.
check "files are tagged file" \
      "file" "$(print -r -- "$i2" | awk -F'\t' '$3=="r/top.md"{print $1}')"
check "dirs are tagged dir" \
      "dir" "$(print -r -- "$i2" | awk -F'\t' '$3=="r/sub"{print $1}')"

# Spec: a dead bookmark is excluded from indexing but still LISTED, marked,
# so the picker itself signals the config needs fixing.
im="$(irecs "gone	$ix/nowhere	missing	2" | _hop_index)"
check "missing bookmark is listed once, marked" \
      "1" "$(print -r -- "$im" | grep -c 'gone  \[missing\]')"
check "missing bookmark is not walked" \
      "1" "$(print -r -- "$im" | grep -c .)"
check "missing marker survives _hop_format" \
      "1" "$(print -r -- "$im" | _hop_format | grep -c '★ gone  \[missing\]')"

# An empty skip list must not break the find expression (silent degradation).
iempty="$(_HOP_SKIP=(); irecs "r	$ix/root	ok	1" | _hop_index | grep -c .)"
check "empty _HOP_SKIP still indexes children" \
      "4" "$iempty"

# multiple bookmarks
imulti="$(irecs "r	$ix/root	ok	0" "f	$ix/flat	ok	0" | _hop_index)"
check "handles multiple bookmarks" \
      "2" "$(print -r -- "$imulti" | grep -c .)"

# A favorited file is indexed as itself and walked no further.
ifile="$(irecs "n	$ix/root/top.md	ok	2" | _hop_index)"
check "a file bookmark yields one record tagged file" \
      "file	$ix/root/top.md	n	1	0" "$ifile"

# --- _hop_rank ------------------------------------------------------------
print ""
print "_hop_rank"

rin="dir	/a/deep/x	z/deep/x	0	3
dir	/a/shallow	a/shallow	0	1
dir	/a/fav	fav	1	0
file	/a/also	b/also	0	1"

rout="$(print -r -- "$rin" | _hop_rank | cut -f3 | tr '\n' ' ')"

check "favorites rank first" \
      "fav" "$(print -r -- "$rin" | _hop_rank | head -1 | cut -f3)"

check "shallower before deeper, alphabetical within a depth" \
      "fav a/shallow b/also z/deep/x " "$rout"

check "record count is preserved" \
      "4" "$(print -r -- "$rin" | _hop_rank | grep -c .)"

check "fields are not mangled" \
      "dir	/a/fav	fav	1	0" "$(print -r -- "$rin" | _hop_rank | head -1)"

# --- _hop_alias_for -------------------------------------------------------
print ""
print "_hop_alias_for"

check "lowercases the basename" \
      "assets" "$(_hop_alias_for /a/b/Assets)"

check "collapses spaces to a single hyphen" \
      "daily-notes" "$(_hop_alias_for '/a/b/Daily  Notes')"

check "collapses dots (file extensions) to hyphens" \
      "goals-md" "$(_hop_alias_for /a/b/goals.md)"

check "strips leading and trailing separators" \
      "inbox" "$(_hop_alias_for '/a/b/_Inbox_')"

check "leaves underscores-only names usable" \
      "b-ai-and-ml" "$(_hop_alias_for /a/b/B_AI_and_ML)"

check "no collision means no suffix" \
      "assets" "$(_hop_alias_for /a/b/Assets code notes)"

check "collision gets -2" \
      "assets-2" "$(_hop_alias_for /a/b/Assets assets notes)"

check "double collision gets -3" \
      "assets-3" "$(_hop_alias_for /a/b/Assets assets assets-2)"

check "purely non-alphanumeric name falls back to 'dir'" \
      "dir" "$(_hop_alias_for '/a/b/---')"

# --- favorites round-trip -------------------------------------------------
print ""
print "_hop_fav_add / _hop_fav_remove"

frc="$tmp/favrc"
mkdir -p "$tmp/FavTarget" "$tmp/Other"
cat > "$frc" <<EOF
# leading comment
code   $tmp/Other    depth=1

# a section comment
other  $tmp/Other
EOF
orig="$(<$frc)"

_hop_fav_add "$tmp/FavTarget" "$frc"

check "add appends the new path" \
      "1" "$(_hop_parse "$frc" 2>/dev/null | grep -c "	$tmp/FavTarget	")"

check "add derives the alias from the basename" \
      "favtarget" "$(_hop_parse "$frc" 2>/dev/null | awk -F'\t' -v p="$tmp/FavTarget" '$2==p{print $1}')"

check "add preserves the leading comment" \
      "1" "$(grep -c '^# leading comment' "$frc")"

check "add preserves the section comment" \
      "1" "$(grep -c '^# a section comment' "$frc")"

check "add is idempotent" \
      "1" "$(_hop_fav_add "$tmp/FavTarget" "$frc"; _hop_parse "$frc" 2>/dev/null | grep -c "	$tmp/FavTarget	")"

_hop_fav_remove "$tmp/FavTarget" "$frc"

check "remove drops the entry" \
      "0" "$(_hop_parse "$frc" 2>/dev/null | grep -c "	$tmp/FavTarget	")"

check "remove restores the file byte-for-byte" \
      "$orig" "$(<$frc)"

check "remove keeps other entries" \
      "2" "$(_hop_parse "$frc" 2>/dev/null | grep -c .)"

check "remove preserves the depth= token on untouched lines" \
      "1" "$(_hop_parse "$frc" 2>/dev/null | awk -F'\t' '$1=="code"{print $4}')"

check "removing an absent path is a no-op" \
      "$orig" "$(_hop_fav_remove "$tmp/NeverAdded" "$frc"; print -r -- "$(<$frc)")"

check "add to an unwritable file returns non-zero" \
      "1" "$(chmod a-w "$frc"; _hop_fav_add "$tmp/Other2" "$frc" >/dev/null 2>&1; print $?; chmod u+w "$frc")"

# CRITICAL regression guard: appending to a hand-edited file with no final
# newline must not merge the new entry into the last line.
nnl="$tmp/nonewlinerc"
printf 'other\t%s' "$tmp/Other" > "$nnl"          # note: no trailing \n
_hop_fav_add "$tmp/FavTarget" "$nnl"
check "add to a file lacking a final newline keeps both entries" \
      "2" "$(_hop_parse "$nnl" 2>/dev/null | grep -c '	ok	')"
check "no-newline add does not corrupt the prior entry" \
      "$tmp/Other" "$(_hop_parse "$nnl" 2>/dev/null | awk -F'\t' '$1=="other"{print $2}')"

# True byte-for-byte round-trip via cmp (the \$(<) idiom strips trailing
# newlines and can hide off-by-one-newline bugs).
cp "$frc" "$tmp/favrc.orig"
_hop_fav_add "$tmp/FavTarget" "$frc"
_hop_fav_remove "$tmp/FavTarget" "$frc"
check "add+remove round-trip is byte-identical (cmp)" \
      "0" "$(cmp -s "$frc" "$tmp/favrc.orig"; print $?)"

# Removing the last entry leaves a genuinely empty file, not one newline.
lone="$tmp/lonerc"
printf 'only\t%s\n' "$tmp/Other" > "$lone"
_hop_fav_remove "$tmp/Other" "$lone"
check "removing the last entry leaves an empty file" \
      "0" "$(wc -c < "$lone" | tr -d ' ')"

# Rewrite must preserve the config file's permissions (inode kept).
perm="$tmp/permrc"
printf 'only\t%s\n' "$tmp/Other" > "$perm"; chmod 600 "$perm"
_hop_fav_remove "$tmp/Other" "$perm"
check "remove preserves file permissions" \
      "600" "$(stat -f '%Lp' "$perm" 2>/dev/null || stat -c '%a' "$perm")"

# --- ctrl-s toggle wiring through hop() (stubbed picker) -------------------
print ""
print "hop toggle wiring"

mkdir -p "$tmp/TogRoot/sub"

# The stub runs inside hop()'s own command substitution, so shell-variable
# state cannot escape it — call-counting must live on the filesystem.
check "ctrl-s in the search picker adds a favorite and reopens" \
      "1" "$(
        togrc="$tmp/togrc1"; printf 'root\t%s\tdepth=1\n' "$tmp/TogRoot" > "$togrc"
        HOPRC="$togrc"; flag="$tmp/togflag1"; rm -f "$flag"
        _hop_pick() { print -r -- "$tmp/TogRoot/sub"; [[ -e "$flag" ]] && return 0; : > "$flag"; return 2 }
        hop >/dev/null 2>&1
        _hop_parse "$togrc" 2>/dev/null | grep -c "	$tmp/TogRoot/sub	"
      )"

check "ctrl-s in descend mode (hop alias/) also toggles" \
      "1" "$(
        togrc="$tmp/togrc2"; printf 'root\t%s\tdepth=1\n' "$tmp/TogRoot" > "$togrc"
        HOPRC="$togrc"; flag="$tmp/togflag2"; rm -f "$flag"
        _hop_pick() { print -r -- "$tmp/TogRoot/sub"; [[ -e "$flag" ]] && return 0; : > "$flag"; return 2 }
        hop root/ >/dev/null 2>&1
        _hop_parse "$togrc" 2>/dev/null | grep -c "	$tmp/TogRoot/sub	"
      )"

check "empty config: hop browses from cwd instead of erroring" \
      "$tmp/TogRoot/sub" "$(
        togrc="$tmp/togrc4"; : > "$togrc"
        HOPRC="$togrc"
        _hop_pick() { print -r -- "$tmp/TogRoot/sub"; return 0 }
        cd "$tmp/TogRoot" && hop >/dev/null 2>&1 && pwd
      )"

check "first ctrl-s bootstraps the config from scratch" \
      "1" "$(
        togrc="$tmp/togrc5"; : > "$togrc"
        HOPRC="$togrc"; flag="$tmp/togflag5"; rm -f "$flag"
        _hop_pick() { print -r -- "$tmp/TogRoot/sub"; [[ -e "$flag" ]] && return 0; : > "$flag"; return 2 }
        cd "$tmp/TogRoot" && hop >/dev/null 2>&1
        _hop_parse "$togrc" 2>/dev/null | grep -c "	$tmp/TogRoot/sub	"
      )"

check "second ctrl-s on the same item removes the favorite" \
      "0" "$(
        togrc="$tmp/togrc3"; printf 'root\t%s\tdepth=1\n' "$tmp/TogRoot" > "$togrc"
        HOPRC="$togrc"; f1="$tmp/togflag3a" f2="$tmp/togflag3b"; rm -f "$f1" "$f2"
        _hop_pick() {
            print -r -- "$tmp/TogRoot/sub"
            if [[ ! -e "$f1" ]]; then : > "$f1"; return 2
            elif [[ ! -e "$f2" ]]; then : > "$f2"; return 2
            fi
            return 0
        }
        hop >/dev/null 2>&1
        _hop_parse "$togrc" 2>/dev/null | grep -c "	$tmp/TogRoot/sub	"
      )"

# --- _hop_format ----------------------------------------------------------
print ""
print "_hop_format"

frecs="dir	/a/fav	fav	1	0
file	/a/b/note.md	b/note.md	0	2"

check "favorites are starred" \
      "1" "$(print -r -- "$frecs" | _hop_format | grep -c '★ fav')"

check "non-favorites are not starred" \
      "0" "$(print -r -- "$frecs" | _hop_format | grep -c '★ b/note.md')"

check "path stays in field 1" \
      "/a/b/note.md" "$(print -r -- "$frecs" | _hop_format | awk -F'\t' 'NR==2{print $1}')"

check "output is exactly two fields" \
      "2" "$(print -r -- "$frecs" | _hop_format | head -1 | awk -F'\t' '{print NF}')"

check "ctrl-s is parsed by _hop_split_expect" \
      $'ctrl-s\t/Users/x/Code' \
      "$(_hop_split_expect $'ctrl-s\n/Users/x/Code\t★ code')"

# --- hop orchestration (non-interactive paths) ----------------------------
print ""
print "hop"

hrc="$tmp/hoprc_orch"
mkdir -p "$tmp/OrchRoot/sub"
touch "$tmp/OrchRoot/file.md"
cat > "$hrc" <<EOF
orch  $tmp/OrchRoot  depth=1
EOF

check "-l lists the bookmark" \
      "1" "$(HOPRC="$hrc" hop -l | grep -c 'orch')"

check "-l shows the depth" \
      "1" "$(HOPRC="$hrc" hop -l | grep -c 'depth=1')"

check "exact alias still jumps without a picker" \
      "$tmp/OrchRoot" "$(HOPRC="$hrc" hop orch >/dev/null 2>&1 && pwd)"
cd "$tmp"

check "-v reports a 0.2 version" \
      "1" "$(HOPRC="$hrc" hop -v | grep -c '0\.2')"

check "help mentions the favorite key" \
      "1" "$(HOPRC="$hrc" hop -h | grep -ci 'favorite')"

print ""
print "$pass passed, $fail failed"
(( fail == 0 ))
