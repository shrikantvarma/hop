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

# missing bookmarks contribute nothing
im="$(irecs "gone	$ix/nowhere	missing	2" | _hop_index)"
check "missing bookmark yields no records" \
      "" "$im"

# multiple bookmarks
imulti="$(irecs "r	$ix/root	ok	0" "f	$ix/flat	ok	0" | _hop_index)"
check "handles multiple bookmarks" \
      "2" "$(print -r -- "$imulti" | grep -c .)"

# A favorited file is indexed as itself and walked no further.
ifile="$(irecs "n	$ix/root/top.md	ok	2" | _hop_index)"
check "a file bookmark yields one record tagged file" \
      "file	$ix/root/top.md	n	1	0" "$ifile"

print ""
print "$pass passed, $fail failed"
(( fail == 0 ))
