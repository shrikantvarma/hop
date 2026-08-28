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

# A favorited FILE is a valid bookmark — Settings / Add more folders can
# star a file, and Enter on it then lands in its parent. Status must not be
# "missing" just because the path is not a directory.
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

# fzf --print-query --expect: line 1 = query (empty if none typed), line 2 =
# key (EMPTY on plain Enter), line 3 = selected record.
check "Enter yields empty query, empty key, and the path" \
      $'\t\t/Users/x/Code' \
      "$(_hop_split_expect $'\n\n/Users/x/Code\tcode    /Users/x/Code')"

check "right arrow yields key=right and the path" \
      $'\tright\t/Users/x/Code' \
      "$(_hop_split_expect $'\nright\n/Users/x/Code\tcode    /Users/x/Code')"

check "the typed query survives in field 1, spaces intact" \
      $'acme co\ttab\t/Users/x/Code' \
      "$(_hop_split_expect $'acme co\ntab\n/Users/x/Code\tcode    /Users/x/Code')"

check "path containing spaces survives the split" \
      $'\ttab\t/Users/x/Daily Notes' \
      "$(_hop_split_expect $'\ntab\n/Users/x/Daily Notes\tdaily   /Users/x/Daily Notes')"

check "[missing] marker in display does not leak into the path" \
      $'\t\t/Users/x/gone' \
      "$(_hop_split_expect $'\n\n/Users/x/gone\tgone    /Users/x/gone  [missing]')"

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

# --- _hop_display_path -----------------------------------------------------
print ""
print "_hop_display_path"

check "abbreviates a path under \$HOME to ~" \
      "~/.hop_test_home_dir" "$(_hop_display_path "$HOME/.hop_test_home_dir")"

check "\$HOME itself becomes ~" \
      "~" "$(_hop_display_path "$HOME")"

check "paths outside \$HOME are left alone" \
      "/opt/data" "$(_hop_display_path /opt/data)"

# --- alias-less entries ----------------------------------------------------
print ""
print "alias-less entries (path-only lines)"

mkdir -p "$tmp/NoAlias" "$tmp/No Alias Spaced"
arc="$tmp/aliaslessrc"
cat > "$arc" <<EOF
$tmp/NoAlias
$tmp/No Alias Spaced    depth=3
~/.hop_test_home_dir
named    $tmp/NoAlias    depth=1
EOF
aout="$(_hop_parse "$arc" 2>"$tmp/aerr")"
apath() { print -r -- "$aout" | awk -F'\t' -v p="$1" -v n="$2" '$2==p {print $n; exit}'; }

check "no lines rejected as malformed" \
      "" "$(<"$tmp/aerr")"

check "path-only line: the path IS the name" \
      "$tmp/NoAlias" "$(print -r -- "$aout" | awk -F'\t' -v p="$tmp/NoAlias" '$2==p {print $1; exit}')"

check "path-only line gets the default depth" \
      "2" "$(apath "$tmp/NoAlias" 4)"

check "path-only line with spaces keeps the path whole" \
      "3" "$(apath "$tmp/No Alias Spaced" 4)"

check "path-only ~ line: path expands, name stays ~-abbreviated" \
      "~/.hop_test_home_dir" "$(apath "$HOME/.hop_test_home_dir" 1)"

check "aliased entries still parse alongside alias-less ones" \
      "1" "$(print -r -- "$aout" | awk -F'\t' '$1=="named" {print $4; exit}')"

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

check "add writes a path-only line (no invented alias)" \
      "$tmp/FavTarget" "$(_hop_parse "$frc" 2>/dev/null | awk -F'\t' -v p="$tmp/FavTarget" '$2==p{print $1}')"

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
# GNU stat first, BSD fallback -- NOT the other way round: BSD's -f flag
# means "format" but GNU's means "filesystem status", so `stat -f '%Lp'` on
# Linux SUCCEEDS with garbage output and the || fallback never fires. GNU's
# -c is a genuine error on BSD, so this direction fails cleanly into the
# fallback on macOS.
check "remove preserves file permissions" \
      "600" "$(stat -c '%a' "$perm" 2>/dev/null || stat -f '%Lp' "$perm")"

# A favorite under $HOME is stored ~-abbreviated so the account name never
# reaches the rc file; set-depth on it must keep the line alias-less.
hfrc="$tmp/homefavrc"; : > "$hfrc"
_hop_fav_add "$HOME/.hop_test_home_dir" "$hfrc"
check "a favorite under \$HOME is stored ~-abbreviated" \
      "1" "$(grep -Fxc -- '~/.hop_test_home_dir' "$hfrc")"

_hop_fav_set_depth "$HOME/.hop_test_home_dir" 4 "$hfrc"
check "set-depth keeps an alias-less entry alias-less" \
      "~/.hop_test_home_dir depth=4" "$(<$hfrc)"

check "the ~-stored favorite round-trips through parse to the expanded path" \
      "$HOME/.hop_test_home_dir" "$(_hop_parse "$hfrc" 2>/dev/null | cut -f2)"

# _hop_fav_set_depth needs the same empty-array guard as _hop_fav_remove:
# rewriting a genuinely empty rc file must not turn it into one blank line.
edrc="$tmp/emptydepthrc"
: > "$edrc"
_hop_fav_set_depth "$tmp/Other" 3 "$edrc"
check "set-depth on an empty rc file leaves it empty, not one blank line" \
      "0" "$(wc -c < "$edrc" | tr -d ' ')"

# --- Settings wiring through hop() (stubbed picker) ------------------------
print ""
print "hop settings wiring"

mkdir -p "$tmp/TogRoot/sub"

# The stub runs inside hop()'s own command substitution, so shell-variable
# state cannot escape it — call-counting must live on the filesystem.
# Enter in Add-more-folders means "done", never "toggle" — toggling lives on
# Space/Tab inside the picker itself. A stubbed Enter-with-path must therefore
# leave the rc file untouched.
check "Add more folders: Enter does not toggle (rc unchanged)" \
      "0" "$(
        togrc="$tmp/togrc1"; printf 'root\t%s\tdepth=1\n' "$tmp/TogRoot" > "$togrc"
        HOPRC="$togrc"; flag="$tmp/settingsflag1"; rm -f "$flag" "$flag.add" "$flag.folder"
        _hop_pick() {
            if [[ ! -e "$flag" ]]; then : > "$flag"; cat > /dev/null; return 3
            elif [[ ! -e "$flag.add" ]]; then : > "$flag.add"; cat > /dev/null; print -r -- __hop_add__; return 0
            elif [[ ! -e "$flag.folder" ]]; then : > "$flag.folder"; cat > /dev/null; print -r -- "$tmp/TogRoot/sub"; return 0
            fi
            cat > /dev/null; return 1
        }
        hop >/dev/null 2>&1
        _hop_parse "$togrc" 2>/dev/null | grep -c "	$tmp/TogRoot/sub	"
      )"

check "Add more folders runs its picker in toggle mode (with_toggle=1)" \
      "1" "$(
        togrc="$tmp/togrc1b"; printf 'root\t%s\tdepth=1\n' "$tmp/TogRoot" > "$togrc"
        HOPRC="$togrc"; flag="$tmp/settingsflag1b"; seen="$tmp/togmode-seen"
        rm -f "$flag" "$flag.add" "$seen"
        _hop_pick() {
            if [[ ! -e "$flag" ]]; then : > "$flag"; cat > /dev/null; return 3
            elif [[ ! -e "$flag.add" ]]; then : > "$flag.add"; cat > /dev/null; print -r -- __hop_add__; return 0
            fi
            print -r -- "${6:-0}" >> "$seen"; cat > /dev/null; return 1
        }
        hop >/dev/null 2>&1
        grep -cx '1' "$seen"
      )"

check "Settings can change a favorite's search depth" \
      "1" "$(
        togrc="$tmp/togrc2"; printf 'root\t%s\tdepth=1\n' "$tmp/TogRoot" > "$togrc"
        HOPRC="$togrc"; c1="$tmp/sf2a" c2="$tmp/sf2b" c3="$tmp/sf2c" c4="$tmp/sf2d"; seen="$tmp/sf2seen"; rm -f "$c1" "$c2" "$c3" "$c4" "$seen"
        _hop_pick() {
            if   [[ ! -e "$c1" ]]; then : > "$c1"; cat > /dev/null; return 3
            elif [[ ! -e "$c2" ]]; then : > "$c2"; cat > /dev/null; print -r -- __hop_saved__; return 0
            elif [[ ! -e "$c3" ]]; then : > "$c3"; cat > "$seen"; print -r -- "$tmp/TogRoot"; return 0
            elif [[ ! -e "$c4" ]]; then : > "$c4"; cat > /dev/null; print -r -- __hop_depth_6__; return 0
            fi
            cat > /dev/null; return 1
        }
        cd "$tmp/TogRoot" && hop >/dev/null 2>&1
        grep -q "★ root   $tmp/TogRoot   depth=1" "$seen" && _hop_parse "$togrc" | awk -F'\t' '$1=="root" {print $4}' | grep -c '^6$'
      )"

check "Saved folders show the full path to distinguish duplicate names" \
      "1" "$(
        togrc="$tmp/togrc-path-label"; printf 'same-a\t%s\tdepth=1\nsame-b\t%s\tdepth=2\n' "$tmp/TogRoot" "$tmp/TogRoot/sub" > "$togrc"
        HOPRC="$togrc"; c1="$tmp/sf-path-a"; c2="$tmp/sf-path-b"; c3="$tmp/sf-path-c"; seen="$tmp/sf-path-seen"; rm -f "$c1" "$c2" "$c3" "$seen"
        _hop_pick() {
            if [[ ! -e "$c1" ]]; then : > "$c1"; cat > /dev/null; return 3
            elif [[ ! -e "$c2" ]]; then : > "$c2"; cat > /dev/null; print -r -- __hop_saved__; return 0
            elif [[ ! -e "$c3" ]]; then : > "$c3"; cat > "$seen"; print -r -- "$tmp/TogRoot"; return 0
            fi
            cat > /dev/null; return 1
        }
        cd "$tmp/TogRoot" && hop >/dev/null 2>&1
        grep -cF "$tmp/TogRoot/sub" "$seen"
      )"

check "Settings can remove a saved folder" \
      "0" "$(
        togrc="$tmp/togrc3"; printf 'root\t%s\tdepth=1\n' "$tmp/TogRoot" > "$togrc"
        HOPRC="$togrc"; c1="$tmp/sf3a" c2="$tmp/sf3b" c3="$tmp/sf3c"; rm -f "$c1" "$c2" "$c3"
        _hop_pick() {
            if   [[ ! -e "$c1" ]]; then : > "$c1"; cat > /dev/null; return 3
            elif [[ ! -e "$c2" ]]; then : > "$c2"; cat > /dev/null; print -r -- __hop_saved__; return 0
            elif [[ ! -e "$c3" ]]; then : > "$c3"; cat > /dev/null; print -r -- "$tmp/TogRoot"; return 4
            fi
            cat > /dev/null; return 1
        }
        cd "$tmp/TogRoot" && hop >/dev/null 2>&1
        _hop_parse "$togrc" 2>/dev/null | grep -c .
      )"

check "Space (via the extra-key list) unfavorites from the saved-folder list" \
      "1" "$(
        togrc="$tmp/togrc3-label"; printf 'root\t%s\tdepth=1\nother\t%s\tdepth=1\n' "$tmp/TogRoot" "$tmp/TogRoot/sub" > "$togrc"
        HOPRC="$togrc"; c1="$tmp/sf3-label-a"; c2="$tmp/sf3-label-b"; c3="$tmp/sf3-label-c"; seen="$tmp/sf3-label"; rm -f "$c1" "$c2" "$c3" "$seen"
        _hop_pick() {
            if [[ ! -e "$c1" ]]; then : > "$c1"; cat > /dev/null; return 3
            elif [[ ! -e "$c2" ]]; then : > "$c2"; cat > /dev/null; print -r -- __hop_saved__; return 0
            elif [[ ! -e "$c3" ]]; then : > "$c3"; cat > /dev/null; print -r -- "$3" > "$seen"; print -r -- "$tmp/TogRoot"; return 4
            fi
            cat > /dev/null; return 1
        }
        cd "$tmp/TogRoot" && hop >/dev/null 2>&1
        grep -q 'Space unstar' "$seen" && _hop_parse "$togrc" | awk -F'\t' '$1=="root" {found=1} END {print found ? 0 : 1}'
      )"

check "hop -b <path> browses that path" \
      "$tmp/TogRoot/sub" "$(
        togrc="$tmp/togrc14"; printf 'root\t%s\tdepth=1\n' "$tmp/TogRoot" > "$togrc"
        HOPRC="$togrc"
        _hop_pick() { cat > /dev/null; print -r -- "$tmp/TogRoot/sub"; return 0 }
        hop -b "$tmp/TogRoot" >/dev/null 2>&1 && pwd
      )"

check "hop -b rejects a non-directory" \
      "1" "$(
        HOPRC="$tmp/togrc14"
        hop -b /nonexistent_dir_xyz >/dev/null 2>&1; print $?
      )"

# Regression guard: an empty/missing ~/.hoprc must not let the first-run
# bootstrap block steal the target that -b already resolved. The stub's
# first call serves _hop_browse (from -b); if hop() wrongly falls through
# into the bootstrap block afterwards, the second call serves _hop_settings
# and immediately cancels (Esc), so a pre-fix run returns 1 instead of
# cd-ing -- this must NOT hang even when the bug is present.
check "hop -b browses even with an empty hoprc (no bootstrap steal)" \
      "$tmp/TogRoot/sub" "$(
        togrc="$tmp/togrc-b-empty"; : > "$togrc"
        HOPRC="$togrc"; flag="$tmp/bempty-flag"; rm -f "$flag"
        _hop_pick() {
            if [[ ! -e "$flag" ]]; then : > "$flag"; cat > /dev/null; print -r -- "$tmp/TogRoot/sub"; return 0; fi
            cat > /dev/null; return 1
        }
        hop -b "$tmp/TogRoot" >/dev/null 2>&1 && pwd
      )"

check "hop -b browses even with a missing hoprc (no bootstrap steal)" \
      "$tmp/TogRoot/sub" "$(
        togrc="$tmp/togrc-b-missing"; rm -f "$togrc"
        HOPRC="$togrc"; flag="$tmp/bmissing-flag"; rm -f "$flag"
        _hop_pick() {
            if [[ ! -e "$flag" ]]; then : > "$flag"; cat > /dev/null; print -r -- "$tmp/TogRoot/sub"; return 0; fi
            cat > /dev/null; return 1
        }
        hop -b "$tmp/TogRoot" >/dev/null 2>&1 && pwd
      )"

check "HOP_DEFAULT_DEPTH overrides the fallback depth" \
      "5" "$(
        HOP_DEFAULT_DEPTH=5
        print -r -- "plain	$tmp/plain" > "$tmp/ddrc"
        _hop_parse "$tmp/ddrc" | cut -f4
      )"

check "bootstrap Esc with nothing starred stays a cancel" \
      "1" "$(
        togrc="$tmp/togrc12"; : > "$togrc"
        HOPRC="$togrc"
        _hop_pick() { cat > /dev/null; return 1 }
        cd "$tmp/TogRoot" && hop >/dev/null 2>&1; print $?
      )"

check "-f shows only bookmarks, no indexed children" \
      "0" "$(
        togrc="$tmp/togrc6"; printf 'root\t%s\tdepth=2\n' "$tmp/TogRoot" > "$togrc"
        HOPRC="$togrc"; seen="$tmp/favseen"
        _hop_pick() { cat > "$seen"; return 1 }
        hop -f >/dev/null 2>&1
        grep -c "TogRoot/sub" "$seen"
      )"

check "-f lists the bookmark itself" \
      "1" "$(
        togrc="$tmp/togrc7"; printf 'root\t%s\tdepth=2\n' "$tmp/TogRoot" > "$togrc"
        HOPRC="$togrc"; seen="$tmp/favseen2"
        _hop_pick() { cat > "$seen"; return 1 }
        hop -f >/dev/null 2>&1
        grep -c '★ root' "$seen"
      )"

check "-f with no favorites exits non-zero with a hint" \
      "1" "$(
        togrc="$tmp/togrc9"; : > "$togrc"
        HOPRC="$togrc"
        hop -f >/dev/null 2>&1; print $?
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

# --- _hop_pick (Enter key handling) ---------------------------------------
print ""
print "_hop_pick"

# fzf is stubbed per-check inside the command substitution, so the stub
# never leaks into the outer shell or other checks.

check "Enter with no extra_key returns 0 and prints the selection" \
      $'0\t/tmp/foo' \
      "$(
        fzf() { cat > /dev/null; printf '%s\n' '' '' $'/tmp/foo\tfoo'; }
        out="$(print -r -- $'/tmp/foo\tfoo' | _hop_pick)"; rc=$?
        printf '%s\t%s' "$rc" "$out"
      )"

check "Enter still returns 0 when an extra_key is configured" \
      $'0\t/tmp/foo' \
      "$(
        fzf() { cat > /dev/null; printf '%s\n' '' '' $'/tmp/foo\tfoo'; }
        out="$(print -r -- $'/tmp/foo\tfoo' | _hop_pick '' 'prompt > ' 'header' 'ctrl-d')"; rc=$?
        printf '%s\t%s' "$rc" "$out"
      )"

check "pressing the configured extra_key still returns 4" \
      $'4\t/tmp/foo' \
      "$(
        fzf() { cat > /dev/null; printf '%s\n' '' 'ctrl-d' $'/tmp/foo\tfoo'; }
        out="$(print -r -- $'/tmp/foo\tfoo' | _hop_pick '' 'prompt > ' 'header' 'ctrl-d')"; rc=$?
        printf '%s\t%s' "$rc" "$out"
      )"

# Ctrl-T must only ever open Settings (return 3) where the caller actually
# handles it -- signalled by with_settings ($5). Everywhere else it must be
# a harmless no-op rather than a silent cancel.
check "ctrl-t returns 3 when with_settings is enabled" \
      $'3\t' \
      "$(
        fzf() { cat > /dev/null; printf '%s\n' '' 'ctrl-t' $'/tmp/foo\tfoo'; }
        out="$(print -r -- $'/tmp/foo\tfoo' | _hop_pick '' '' '' '' 1)"; rc=$?
        printf '%s\t%s' "$rc" "$out"
      )"

check "ctrl-t is a harmless no-op (not a cancel) when with_settings is off" \
      $'0\t/tmp/foo' \
      "$(
        seen="$tmp/ctrlt-seen"; rm -f "$seen"
        fzf() {
            cat > /dev/null
            if [[ ! -e "$seen" ]]; then
                : > "$seen"
                printf '%s\n' '' 'ctrl-t' $'/tmp/foo\tfoo'
            else
                printf '%s\n' '' '' $'/tmp/foo\tfoo'
            fi
        }
        out="$(print -r -- $'/tmp/foo\tfoo' | _hop_pick)"; rc=$?
        printf '%s\t%s' "$rc" "$out"
      )"

check "? returns 3 (Settings) when with_settings is enabled" \
      $'3\t' \
      "$(
        fzf() { cat > /dev/null; printf '%s\n' '' '?' $'/tmp/foo\tfoo'; }
        out="$(print -r -- $'/tmp/foo\tfoo' | _hop_pick '' '' '' '' 1)"; rc=$?
        printf '%s\t%s' "$rc" "$out"
      )"

check "space via the extra-key list returns 4" \
      $'4\t/tmp/foo' \
      "$(
        fzf() { cat > /dev/null; printf '%s\n' '' 'space' $'/tmp/foo\tfoo'; }
        out="$(print -r -- $'/tmp/foo\tfoo' | _hop_pick '' '' '' 'space,tab,ctrl-d')"; rc=$?
        printf '%s\t%s' "$rc" "$out"
      )"

check "tab at the top of the search picker returns 5 with query and path" \
      $'5\tqq\t/tmp/foo' \
      "$(
        fzf() { cat > /dev/null; printf '%s\n' 'qq' 'tab' $'/tmp/foo\t★ foo'; }
        out="$(print -r -- $'/tmp/foo\t★ foo' | _hop_pick '' '' '' '' 1)"; rc=$?
        printf '%s\t%s' "$rc" "$out"
      )"

# The heart of the toggle UX: Space stars the item WITHOUT leaving the picker
# — the list re-stars in place, the typed query is re-seeded, and a later
# Enter still selects normally.
tog_pk="$tmp/togpick"
mkdir -p "$tog_pk/A" "$tog_pk/B"

check "space in toggle mode: favorite saved, star refreshed, query kept, picker open" \
      $'0\t'"$tog_pk/B"$'\t1\t1\tqq' \
      "$(
        togrc="$tmp/togpickrc"; : > "$togrc"; HOPRC="$togrc"
        st="$tmp/togpick-step"; seen="$tmp/togpick-seen"; qseen="$tmp/togpick-q"
        rm -f "$st" "$seen" "$qseen"
        fzf() {
            local a
            if [[ ! -e "$st" ]]; then
                : > "$st"; cat > /dev/null
                printf '%s\n' 'qq' 'space' "$tog_pk/A"$'\t''  A/'
            else
                cat > "$seen"
                for a in "$@"; do
                    [[ "$a" == --query=* ]] && print -r -- "${a#--query=}" > "$qseen"
                done
                printf '%s\n' '' '' "$tog_pk/B"$'\t''  B/'
            fi
        }
        lines="$tog_pk/A"$'\t''  A/'$'\n'"$tog_pk/B"$'\t''  B/'
        out="$(print -r -- "$lines" | _hop_pick '' '' '' '' 0 1)"; rc=$?
        printf '%s\t%s\t%s\t%s\t%s' "$rc" "$out" \
            "$(_hop_parse "$togrc" 2>/dev/null | grep -c "	$tog_pk/A	")" \
            "$(grep -c '★ A/' "$seen")" \
            "$(<"$qseen")"
      )"

# Descend/back stack: → replaces the list in place with real children (via
# the real _hop_children), ← must restore the EXACT prior list rather than
# just "a" prior list -- proven by selecting an item that only exists at the
# top level once back out.
pkroot="$tmp/pick_stack"
mkdir -p "$pkroot/ChildA/Grandchild" "$pkroot/ChildB"
pklines="$pkroot/ChildA	ChildA/	dir
$pkroot/ChildB	ChildB/	dir"

check "right descends into children, left restores the original list, Enter selects from it" \
      $'0\t'"$pkroot/ChildB" \
      "$(
        step="$tmp/pickstack-step"; rm -f "$step.1" "$step.2"
        fzf() {
            cat > /dev/null
            if [[ ! -e "$step.1" ]]; then
                : > "$step.1"
                printf '%s\n' '' 'right' "$pkroot/ChildA"$'\t''ChildA/'$'\t''dir'
            elif [[ ! -e "$step.2" ]]; then
                : > "$step.2"
                printf '%s\n' '' 'left' "$pkroot/ChildA/Grandchild"$'\t''Grandchild/'$'\t''dir'
            else
                printf '%s\n' '' '' "$pkroot/ChildB"$'\t''ChildB/'$'\t''dir'
            fi
        }
        out="$(print -r -- "$pklines" | _hop_pick)"; rc=$?
        printf '%s\t%s' "$rc" "$out"
      )"

# ← with nothing to pop walks up the real tree: list the parent's children
# with the folder we came from lifted to the top (fzf keeps input order, so
# that is where the cursor lands).
uproot="$tmp/pick_up"
mkdir -p "$uproot/Aaa" "$uproot/Mid/Deep/Leaf" "$uproot/Zzz"

check "_hop_lift moves the matching path to the top" \
      $'/b\tB\n/a\tA\n/c\tC' \
      "$(printf '/a\tA\n/b\tB\n/c\tC\n' | _hop_lift /b)"

check "left at the launch level lists the parent, came-from folder first" \
      $'0\t'"$uproot/Mid"$'\t'"$uproot/Mid"$'\t'"$uproot/Aaa"$'\t'"$uproot/Zzz" \
      "$(
        step="$tmp/pickup-step"; rm -f "$step.1"
        seen="$tmp/pickup-seen"
        fzf() {
            if [[ ! -e "$step.1" ]]; then
                : > "$step.1"; cat > /dev/null
                printf '%s\n' '' 'left' "$uproot/Mid/Deep"$'\t''Deep/'$'\t''dir'
            else
                cut -f1 > "$seen"
                printf '%s\n' '' '' "$uproot/Mid"$'\t''Mid/'$'\t''dir'
            fi
        }
        out="$(_hop_children "$uproot/Mid" | _hop_pick '' 'Mid/ > ' '' '' 0 1 "$uproot/Mid")"; rc=$?
        printf '%s\t%s\t%s' "$rc" "$out" "$(paste -sd '\t' "$seen")"
      )"

check "left twice keeps climbing (grandparent), then right/left round-trips" \
      $'0\t'"$uproot/Mid/Deep" \
      "$(
        n="$tmp/pickup2-n"; : > "$n"
        fzf() {
            cat > /dev/null
            print x >> "$n"
            case "$(wc -l < "$n" | tr -d ' ')" in
                1) printf '%s\n' '' 'left' "$uproot/Mid/Deep/Leaf"$'\t''Leaf/'$'\t''dir' ;;
                2) printf '%s\n' '' 'left' "$uproot/Mid/Deep"$'\t''Deep/'$'\t''dir' ;;
                3) printf '%s\n' '' 'right' "$uproot/Mid"$'\t''Mid/'$'\t''dir' ;;
                4) printf '%s\n' '' 'left' "$uproot/Mid/Deep"$'\t''Deep/'$'\t''dir' ;;
                *) printf '%s\n' '' '' "$uproot/Mid/Deep"$'\t''Deep/'$'\t''dir' ;;
            esac
        }
        out="$(_hop_children "$uproot/Mid/Deep" | _hop_pick '' '' '' '' 0 1 "$uproot/Mid/Deep")"; rc=$?
        printf '%s\t%s' "$rc" "$out"
      )"

check "left with no base (search results) climbs from the highlighted item" \
      "$uproot/Mid"$'\t'"$uproot/Aaa"$'\t'"$uproot/Zzz" \
      "$(
        step="$tmp/pickup3-step"; rm -f "$step.1"
        seen="$tmp/pickup3-seen"
        fzf() {
            if [[ ! -e "$step.1" ]]; then
                : > "$step.1"; cat > /dev/null
                printf '%s\n' '' 'left' "$uproot/Mid"$'\t''  Mid'
            else
                cut -f1 > "$seen"
                printf '%s\n' '' '' "$uproot/Aaa"$'\t''Aaa/'$'\t''dir'
            fi
        }
        printf '%s\t  Mid\n' "$uproot/Mid" | _hop_pick >/dev/null
        paste -sd '\t' "$seen"
      )"

check "left at / is a no-op" \
      $'0\t/' \
      "$(
        n="$tmp/pickup4-n"; : > "$n"
        fzf() {
            cat > /dev/null; print x >> "$n"
            if (( $(wc -l < "$n") == 1 )); then printf '%s\n' '' 'left' $'/\t/'
            else printf '%s\n' '' '' $'/\t/'; fi
        }
        out="$(printf '/\t/\n' | _hop_pick '' '' '' '' 0 0 /)"; rc=$?
        printf '%s\t%s' "$rc" "$out"
      )"

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

# Tab in the main picker (return 5): hop() must toggle the favorite, rebuild
# the list, and re-seed the query the user had typed.
check "Tab in the main picker stars the item and re-seeds the query" \
      $'1\tqq' \
      "$(
        togrc="$tmp/togrc-tab-main"; printf 'root\t%s\tdepth=1\n' "$tmp/OrchRoot" > "$togrc"
        HOPRC="$togrc"; flag="$tmp/tabmain-flag"; qseen="$tmp/tabmain-q"
        rm -f "$flag" "$qseen"
        _hop_pick() {
            if [[ ! -e "$flag" ]]; then
                : > "$flag"; cat > /dev/null
                printf '%s\t%s\n' 'qq' "$tmp/OrchRoot/sub"; return 5
            fi
            print -r -- "$1" > "$qseen"; cat > /dev/null; return 1
        }
        hop >/dev/null 2>&1
        printf '%s\t%s' \
            "$(_hop_parse "$togrc" 2>/dev/null | grep -c "	$tmp/OrchRoot/sub	")" \
            "$(<"$qseen")"
      )"

# The shell expands ~ before hop sees it, so an alias-less bookmark must be
# reachable by its full expanded path as well.
check "an exact expanded path jumps without a picker" \
      "$tmp/OrchRoot" "$(HOPRC="$hrc" hop "$tmp/OrchRoot" >/dev/null 2>&1 && pwd)"
cd "$tmp"

check "hop <alias>/ opens the picker INSIDE that bookmark instead of jumping" \
      "$tmp/OrchRoot/sub" "$(
        HOPRC="$hrc"
        _hop_pick() { cat > /dev/null; print -r -- "$tmp/OrchRoot/sub"; return 0 }
        hop orch/ >/dev/null 2>&1 && pwd
      )"
cd "$tmp"

check "-v reports a 0.2 version" \
      "1" "$(HOPRC="$hrc" hop -v | grep -c '0\.2')"

print ""
print "$pass passed, $fail failed"
(( fail == 0 ))
