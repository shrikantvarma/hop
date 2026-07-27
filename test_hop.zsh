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

rmdir "$HOME/.hop_test_home_dir"

# --- _hop_children -------------------------------------------------------
print ""
print "_hop_children"

kid="$tmp/kids"
mkdir -p "$kid/Assets" "$kid/Projects" "$kid/.git" "$kid/node_modules" "$kid/.hidden_keep"
touch "$kid/a_file.md"

# The vault is reached through symlinks, so cover that explicitly.
ln -s "$kid" "$tmp/link_to_kids"

names() { _hop_children "$1" | cut -f2 | sort | tr '\n' ' '; }

check "lists immediate subdirs only" \
      "Assets Projects " \
      "$(_hop_children "$kid" | cut -f2 | grep -vE '^\.' | sort | tr '\n' ' ')"

check "skips .git and node_modules" \
      "0" \
      "$(_hop_children "$kid" | cut -f2 | grep -cE '^(\.git|node_modules)$')"

check "keeps non-noise dotdirs" \
      "1" \
      "$(_hop_children "$kid" | cut -f2 | grep -c '^\.hidden_keep$')"

check "excludes plain files" \
      "0" \
      "$(_hop_children "$kid" | cut -f2 | grep -c 'a_file.md')"

check "emits absolute paths in field 1" \
      "$kid/Assets" \
      "$(_hop_children "$kid" | awk -F'\t' '$2=="Assets"{print $1}')"

check "descends through a SYMLINKED parent (the vault case)" \
      "$(names "$kid")" "$(names "$tmp/link_to_kids")"

check "leaf dir yields nothing" \
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

print ""
print "$pass passed, $fail failed"
(( fail == 0 ))
