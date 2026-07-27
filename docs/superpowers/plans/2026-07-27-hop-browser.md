# hop v0.2 Browser Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn `hop` from a bookmark jumper into a browser that fuzzy-searches directories *and files* inside bookmarked trees, ranks favorites first, and lets you favorite from inside the picker.

**Architecture:** Everything stays in the single file `hop.plugin.zsh` — plugin managers source one entry file, and splitting would add `${0:A:h}` path-resolution complexity for no gain at ~400 lines. Five new pure functions (`_hop_index`, `_hop_rank`, `_hop_alias_for`, `_hop_fav_add`, `_hop_fav_remove`) sit between the existing parser and picker. `_hop_pick` stays ignorant of records and favorites: it consumes `path \t display` and signals a favorite-toggle back to `hop()` via exit code 2 rather than mutating config itself.

**Tech Stack:** zsh 5.x, fzf, POSIX `find`/`awk`/`sort`. No new dependencies.

## Global Constraints

- **Working directory:** `~/Code/hop/.worktrees/browser` (branch `browser`). All paths below are relative to it.
- **Shell:** zsh only. No bashisms. Every function starts `emulate -L zsh`.
- **No new runtime dependencies.** `find`, `awk`, `sort`, `sed` only — must work with BSD (macOS) *and* GNU (Linux CI) variants. No `find -printf`, no `sed -i` without a backup arg, no `sort -V`.
- **Tests:** `zsh test_hop.zsh`, currently 27 passing. Every task adds assertions; the suite must be green before each commit.
- **Config file is user-owned.** Any rewrite of `~/.hoprc` must preserve comments, blank lines, and ordering of untouched entries.
- **Commit style:** conventional commits (`feat:`, `fix:`, `test:`, `docs:`, `refactor:`). Every commit message ends with:
  ```
  Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01SWYKAEcegMgeSpq9dBwr8M
  ```
- **Never open files.** `Enter` on a file `cd`s to its containing directory. This is a deliberate scope decision, not an omission.

## Record Formats

These are the contracts between tasks. Fields are tab-separated.

| Producer | Format |
| --- | --- |
| `_hop_parse` | `alias \t path \t status \t depth` — status is `ok`/`missing`, depth is an integer |
| `_hop_index` | `kind \t path \t display \t fav \t depth` — kind is `dir`/`file`, fav is `1`/`0` |
| `_hop_rank` | same five fields, reordered |
| `_hop_format` | `path \t display` — the only thing `_hop_pick` ever sees |
| `_hop_children` | `path \t display \t kind` |

`display` for a bookmark is its alias; for an indexed item it is `<alias>/<relative path>`.

## File Structure

| File | Responsibility | Change |
| --- | --- | --- |
| `hop.plugin.zsh` | The whole tool | Modify — 4 functions extended, 5 added |
| `test_hop.zsh` | Test suite | Modify — ~30 assertions added |
| `hoprc.example` | Documented sample config | Modify — show `depth=` |
| `README.md` | User docs | Modify — search, favoriting, depth |
| `DESIGN.md` | Contributor notes | Modify — new units, new traps |

---

### Task 1: Parse the `depth=N` token

**Files:**
- Modify: `hop.plugin.zsh:33-85` (`_hop_parse`)
- Test: `test_hop.zsh`

**Interfaces:**
- Consumes: nothing (first task)
- Produces: `_hop_parse [rcfile]` → lines of `alias \t path \t status \t depth`. `depth` is an integer ≥ 0, defaulting to `2` when the `depth=` token is absent.

- [ ] **Step 1: Write the failing tests**

Add to `test_hop.zsh` immediately after the existing `_hop_parse` assertions (after the `unreadable rc returns non-zero` check, before `rmdir "$HOME/.hop_test_home_dir"`):

```zsh
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh test_hop.zsh`
Expected: FAIL — `depth defaults to 2 when absent` reports actual `""` (there is no field 4 yet).

- [ ] **Step 3: Implement**

In `_hop_parse`, replace the single regex block with a two-attempt match. Find:

```zsh
        if [[ ! "$line" =~ '^[[:space:]]*([^[:space:]]+)[[:space:]]+(.*[^[:space:]])[[:space:]]*$' ]]; then
            print -u2 "hop: $rc:$lineno: malformed (no path) -- skipped"
            continue
        fi
        name="$match[1]"
        path="$match[2]"
```

Replace with:

```zsh
        # Try the depth= form first. A keyed token is used rather than a bare
        # trailing number because paths may contain spaces: "~/Notes/Chapter 3"
        # would otherwise parse as path "~/Notes/Chapter" with depth 3.
        if [[ "$line" =~ '^[[:space:]]*([^[:space:]]+)[[:space:]]+(.*[^[:space:]])[[:space:]]+depth=([^[:space:]]+)[[:space:]]*$' ]]; then
            name="$match[1]"
            path="$match[2]"
            depth="$match[3]"
            if [[ ! "$depth" =~ '^[0-9]+$' ]]; then
                print -u2 "hop: $rc:$lineno: depth=$depth is not a number -- using 2"
                depth=2
            fi
        elif [[ "$line" =~ '^[[:space:]]*([^[:space:]]+)[[:space:]]+(.*[^[:space:]])[[:space:]]*$' ]]; then
            name="$match[1]"
            path="$match[2]"
            depth=2
        else
            print -u2 "hop: $rc:$lineno: malformed (no path) -- skipped"
            continue
        fi
```

Add `depth` to the function's `local` declaration — change:

```zsh
    local line name path lineno=0
```

to:

```zsh
    local line name path depth lineno=0
```

Then change both `printf` calls at the end of the loop from three fields to four, and
widen the existence test from `-d` to `-e`. Find:

```zsh
        if [[ -d "$path" ]]; then
```

Replace the whole block with:

```zsh
        # -e, not -d: a bookmark may be a FILE. Ctrl-S can star a file, and
        # Enter on it lands in its parent directory. Testing -d here would
        # mark every favorited file "missing" and drop it from the index.
        if [[ -e "$path" ]]; then
            printf '%s\t%s\t%s\t%s\n' "$name" "$path" "ok" "$depth"
        else
            printf '%s\t%s\t%s\t%s\n' "$name" "$path" "missing" "$depth"
        fi
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zsh test_hop.zsh`
Expected: PASS, 37 total. The 12 original `_hop_parse` assertions still pass — they only read fields 1–3, which are unchanged.

- [ ] **Step 5: Commit**

```bash
git add hop.plugin.zsh test_hop.zsh
git commit -m "feat: parse optional depth= token in .hoprc

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SWYKAEcegMgeSpq9dBwr8M"
```

---

### Task 2: List files as well as directories

**Files:**
- Modify: `hop.plugin.zsh:87-107` (`_hop_children`)
- Test: `test_hop.zsh`

**Interfaces:**
- Consumes: nothing from Task 1
- Produces: `_hop_children <dir>` → `path \t display \t kind`. Directories sort first and their `display` ends in `/`; `kind` is `dir` or `file`. Returns 1 if `<dir>` is not a directory.

- [ ] **Step 1: Write the failing tests**

Replace the existing `_hop_children` block in `test_hop.zsh` (from `print "_hop_children"` through the `nonexistent parent returns non-zero` check) with this expanded version. The original assertions are preserved with updated field expectations:

```zsh
print "_hop_children"

kid="$tmp/kids"
mkdir -p "$kid/Assets" "$kid/Projects" "$kid/.git" "$kid/node_modules" "$kid/.hidden_keep"
touch "$kid/a_file.md" "$kid/b_file.txt"

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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh test_hop.zsh`
Expected: FAIL — `lists subdirs with a trailing slash` reports `Assets Projects` (no slashes), and `lists files too` reports empty.

- [ ] **Step 3: Implement**

Replace the body loop of `_hop_children`. Find:

```zsh
    for child in "$parent"/*(-/N) "$parent"/.*(-/N); do
        name="${child:t}"
        [[ "$name" == "." || "$name" == ".." ]] && continue
        (( ${_HOP_SKIP[(Ie)$name]} )) && continue
        printf '%s\t%s\n' "$child" "$name"
    done
```

Replace with:

```zsh
    # Directories first, then files — the (-/N) qualifier resolves symlinks
    # before the type test, (-.N) does the same for plain files.
    for child in "$parent"/*(-/N) "$parent"/.*(-/N); do
        name="${child:t}"
        [[ "$name" == "." || "$name" == ".." ]] && continue
        (( ${_HOP_SKIP[(Ie)$name]} )) && continue
        printf '%s\t%s/\t%s\n' "$child" "$name" "dir"
    done

    for child in "$parent"/*(-.N) "$parent"/.*(-.N); do
        name="${child:t}"
        (( ${_HOP_SKIP[(Ie)$name]} )) && continue
        printf '%s\t%s\t%s\n' "$child" "$name" "file"
    done
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zsh test_hop.zsh`
Expected: PASS, 40 total.

- [ ] **Step 5: Commit**

```bash
git add hop.plugin.zsh test_hop.zsh
git commit -m "feat: list files alongside directories when descending

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SWYKAEcegMgeSpq9dBwr8M"
```

---

### Task 3: Build the index

**Files:**
- Modify: `hop.plugin.zsh` (add `_hop_index` after `_hop_children`)
- Test: `test_hop.zsh`

**Interfaces:**
- Consumes: `_hop_parse` output (Task 1) on stdin — `alias \t path \t status \t depth`
- Produces: `_hop_index` reads records on stdin, writes `kind \t path \t display \t fav \t depth`. Every `ok` bookmark yields its own record at depth 0 with `fav=1`. Bookmarks with `depth>0` additionally yield descendants with `fav=0`. `missing` bookmarks are skipped entirely.

- [ ] **Step 1: Write the failing tests**

Append to `test_hop.zsh` before the final `print "$pass passed, $fail failed"`:

```zsh
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

check "files are tagged file, dirs tagged dir" \
      "file dir" \
      "$(print -r -- "$i2" | awk -F'\t' '$3=="r/top.md"{printf "%s ",$1} $3=="r/sub"{print $1}')"

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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh test_hop.zsh`
Expected: FAIL — `_hop_index: command not found`.

- [ ] **Step 3: Implement**

Add after `_hop_children`:

```zsh
# ---------------------------------------------------------------------------
# _hop_index — bookmark records on stdin -> full candidate list on stdout
#
#   in : alias \t path \t status \t depth
#   out: kind \t path \t display \t fav \t depth
#
# Two `find` passes per bookmark (dirs, then files) rather than one. BSD find
# has no -printf, so there is no portable way to tag type inline; running twice
# with -type is the portable equivalent and still costs only milliseconds.
# ---------------------------------------------------------------------------
_hop_index() {
    emulate -L zsh

    local alias path st depth s
    local -a prune

    # Build the -prune expression once: \( -name .git -o -name ... \)
    prune=('(')
    for s in $_HOP_SKIP; do
        prune+=(-name "$s" -o)
    done
    prune[-1]=')'          # replace the trailing -o

    while IFS=$'\t' read -r alias path st depth; do
        [[ "$st" == "ok" ]] || continue

        # The bookmark itself is always present and always a favorite. It may
        # be a file — a starred file is a legal bookmark.
        if [[ -d "$path" ]]; then
            printf '%s\t%s\t%s\t%s\t%s\n' "dir" "$path" "$alias" "1" "0"
        else
            printf '%s\t%s\t%s\t%s\t%s\n' "file" "$path" "$alias" "1" "0"
            continue        # nothing to walk beneath a file
        fi

        (( depth > 0 )) || continue

        {
            find -L "$path" -mindepth 1 -maxdepth "$depth" "${prune[@]}" -prune -o -type d -print 2>/dev/null \
                | sed 's/^/dir\t/'
            find -L "$path" -mindepth 1 -maxdepth "$depth" "${prune[@]}" -prune -o -type f -print 2>/dev/null \
                | sed 's/^/file\t/'
        } | awk -F'\t' -v root="$path" -v al="$alias" 'BEGIN{OFS="\t"}
            {
                rel = substr($2, length(root) + 2)
                if (rel == "") next
                n = split(rel, parts, "/")
                print $1, $2, al "/" rel, 0, n
            }'
    done
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zsh test_hop.zsh`
Expected: PASS, 55 total.

- [ ] **Step 5: Commit**

```bash
git add hop.plugin.zsh test_hop.zsh
git commit -m "feat: add _hop_index to walk bookmarked trees

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SWYKAEcegMgeSpq9dBwr8M"
```

---

### Task 4: Rank the candidates

**Files:**
- Modify: `hop.plugin.zsh` (add `_hop_rank` after `_hop_index`)
- Test: `test_hop.zsh`

**Interfaces:**
- Consumes: `_hop_index` output (Task 3) on stdin
- Produces: `_hop_rank` writes the same five fields, ordered: `fav` descending, then `depth` ascending, then `display` ascending. fzf preserves input order for equal match scores, so emission order *is* the ranking.

- [ ] **Step 1: Write the failing tests**

Append to `test_hop.zsh` before the final summary:

```zsh
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh test_hop.zsh`
Expected: FAIL — `_hop_rank: command not found`.

- [ ] **Step 3: Implement**

Add after `_hop_index`:

```zsh
# ---------------------------------------------------------------------------
# _hop_rank — order candidates for fzf
#
# fzf keeps input order among equally-scoring matches, so emission order is
# the ranking. Favorites first, then shallower paths, then alphabetical.
#
# LC_ALL=C keeps the sort deterministic across machines and CI locales.
# ---------------------------------------------------------------------------
_hop_rank() {
    emulate -L zsh
    LC_ALL=C sort -t$'\t' -k4,4r -k5,5n -k3,3
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zsh test_hop.zsh`
Expected: PASS, 59 total.

- [ ] **Step 5: Commit**

```bash
git add hop.plugin.zsh test_hop.zsh
git commit -m "feat: rank favorites first, then by depth

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SWYKAEcegMgeSpq9dBwr8M"
```

---

### Task 5: Derive aliases for new favorites

**Files:**
- Modify: `hop.plugin.zsh` (add `_hop_alias_for` after `_hop_rank`)
- Test: `test_hop.zsh`

**Interfaces:**
- Consumes: nothing
- Produces: `_hop_alias_for <path> [existing-alias ...]` → a single alias on stdout. Lowercases the basename, collapses every run of non-alphanumeric characters to `-`, strips leading/trailing `-`, and suffixes `-2`, `-3`, … on collision with any listed existing alias.

- [ ] **Step 1: Write the failing tests**

Append to `test_hop.zsh` before the final summary:

```zsh
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh test_hop.zsh`
Expected: FAIL — `_hop_alias_for: command not found`.

- [ ] **Step 3: Implement**

Add after `_hop_rank`:

```zsh
# ---------------------------------------------------------------------------
# _hop_alias_for — path + existing aliases -> a unique alias
#
#   _hop_alias_for /a/b/Daily\ Notes code notes   ->  daily-notes
# ---------------------------------------------------------------------------
_hop_alias_for() {
    emulate -L zsh

    local path="$1"; shift
    local -a taken=("$@")
    local base="${path:t}" cand n

    base="${(L)base}"                       # lowercase
    base="${base//[^a-z0-9]##/-}"           # runs of non-alphanumerics -> one -
    base="${base##-}"                       # strip leading
    base="${base%%-}"                       # strip trailing
    [[ -n "$base" ]] || base="dir"

    cand="$base"
    n=2
    while (( ${taken[(Ie)$cand]} )); do
        cand="$base-$n"
        (( n++ ))
    done

    print -r -- "$cand"
}
```

Note: `${base//[^a-z0-9]##/-}` needs `extended_glob` for the `##` quantifier. Add `setopt local_options extended_glob` immediately after `emulate -L zsh` in this function — this is the exact trap documented in `DESIGN.md`, where the quantifier silently becomes a literal `#` without the option.

- [ ] **Step 4: Run tests to verify they pass**

Run: `zsh test_hop.zsh`
Expected: PASS, 68 total.

- [ ] **Step 5: Commit**

```bash
git add hop.plugin.zsh test_hop.zsh
git commit -m "feat: derive unique aliases for new favorites

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SWYKAEcegMgeSpq9dBwr8M"
```

---

### Task 6: Add and remove favorites in `.hoprc`

**Files:**
- Modify: `hop.plugin.zsh` (add `_hop_fav_add`, `_hop_fav_remove` after `_hop_alias_for`)
- Test: `test_hop.zsh`

**Interfaces:**
- Consumes: `_hop_parse` (Task 1), `_hop_alias_for` (Task 5)
- Produces:
  - `_hop_fav_add <path> [rcfile]` → appends `<alias>  <path>` to the config. Returns 1 and writes to stderr if the file is not writable. No-op returning 0 if the path is already bookmarked.
  - `_hop_fav_remove <path> [rcfile]` → removes the line whose expanded path equals `<path>`. Preserves comments, blank lines, and every other entry verbatim.

This is the highest-risk task in the plan: it rewrites a user-owned file. The round-trip test exists specifically to prove comments survive.

- [ ] **Step 1: Write the failing tests**

Append to `test_hop.zsh` before the final summary:

```zsh
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh test_hop.zsh`
Expected: FAIL — `_hop_fav_add: command not found`.

- [ ] **Step 3: Implement**

Add after `_hop_alias_for`:

```zsh
# ---------------------------------------------------------------------------
# _hop_fav_add — append a bookmark to the config file
#
# Idempotent: adding an already-bookmarked path does nothing.
# ---------------------------------------------------------------------------
_hop_fav_add() {
    emulate -L zsh

    local target="$1" rc="${2:-$HOPRC}"
    local -a taken

    [[ -e "$rc" ]] || : > "$rc"
    if [[ ! -w "$rc" ]]; then
        print -u2 "hop: cannot write $rc"
        return 1
    fi

    # Already bookmarked?
    if _hop_parse "$rc" 2>/dev/null | cut -f2 | grep -qxF -- "$target"; then
        return 0
    fi

    taken=(${(f)"$(_hop_parse "$rc" 2>/dev/null | cut -f1)"})
    printf '%s\t%s\n' "$(_hop_alias_for "$target" "${taken[@]}")" "$target" >> "$rc"
}

# ---------------------------------------------------------------------------
# _hop_fav_remove — drop the entry whose expanded path matches
#
# Rewrites line by line rather than filtering with sed, so comments, blank
# lines, spacing, and depth= tokens on other entries all survive untouched.
# ---------------------------------------------------------------------------
_hop_fav_remove() {
    emulate -L zsh

    local target="$1" rc="${2:-$HOPRC}"
    local line stripped path tmpf
    local -a keep

    [[ -r "$rc" ]] || return 1
    if [[ ! -w "$rc" ]]; then
        print -u2 "hop: cannot write $rc"
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        stripped="${line%%'#'*}"
        path=""
        if [[ "$stripped" =~ '^[[:space:]]*[^[:space:]]+[[:space:]]+(.*[^[:space:]])[[:space:]]+depth=[^[:space:]]+[[:space:]]*$' ]]; then
            path="$match[1]"
        elif [[ "$stripped" =~ '^[[:space:]]*[^[:space:]]+[[:space:]]+(.*[^[:space:]])[[:space:]]*$' ]]; then
            path="$match[1]"
        fi

        if [[ -n "$path" ]]; then
            if [[ "$path" == "~" ]]; then
                path="$HOME"
            elif [[ "$path" == "~/"* ]]; then
                path="$HOME/${path#\~/}"
            fi
            [[ "$path" == "$target" ]] && continue     # drop this line
        fi

        keep+=("$line")
    done < "$rc"

    tmpf="$rc.hoptmp$$"
    print -rl -- "${keep[@]}" > "$tmpf" && mv "$tmpf" "$rc"
}
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zsh test_hop.zsh`
Expected: PASS, 79 total. Pay particular attention to `remove restores the file byte-for-byte` — if it fails, the rewrite is losing something and must be fixed before proceeding.

- [ ] **Step 5: Commit**

```bash
git add hop.plugin.zsh test_hop.zsh
git commit -m "feat: add and remove favorites while preserving config comments

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SWYKAEcegMgeSpq9dBwr8M"
```

---

### Task 7: Display favorites and signal toggles from the picker

**Files:**
- Modify: `hop.plugin.zsh` (`_hop_format`, `_hop_pick`)
- Test: `test_hop.zsh`

**Interfaces:**
- Consumes: `_hop_rank` output (Task 4)
- Produces:
  - `_hop_format` now reads five-field index records and writes `path \t display`, prefixing `★ ` when `fav=1` and two spaces otherwise so columns line up.
  - `_hop_pick` gains exit code **2** meaning "favorite toggle requested"; it prints the highlighted path and returns without mutating anything. Exit 0 = selected, 1 = cancelled.

`_hop_pick` deliberately does not call `_hop_fav_add`/`_hop_fav_remove`. Keeping config mutation in `hop()` means the picker stays a pure selection loop and the toggle path is testable.

- [ ] **Step 1: Write the failing tests**

Append to `test_hop.zsh` before the final summary:

```zsh
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
```

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh test_hop.zsh`
Expected: FAIL — `favorites are starred` reports `0`; `_hop_format` still emits the old three-field layout.

- [ ] **Step 3: Implement**

Replace `_hop_format` entirely:

```zsh
# ---------------------------------------------------------------------------
# _hop_format — index records -> `path \t display` picker lines
#
#   in : kind \t path \t display \t fav \t depth
#   out: path \t display
#
# Favorites get a star; everything else gets two spaces so the columns align.
# ---------------------------------------------------------------------------
_hop_format() {
    awk -F'\t' 'BEGIN{OFS="\t"}
        { print $2, ($4 == "1" ? "★ " : "  ") $3 }'
}
```

In `_hop_pick`, add `ctrl-s` to the expect list. Find:

```zsh
              --expect=right,left,tab,btab \
```

Replace with:

```zsh
              --expect=right,left,tab,btab,ctrl-s \
```

Update the header. Find:

```zsh
              --header='Enter hop   →/Tab descend   ←/S-Tab up   (^F ^B move cursor)' \
```

Replace with:

```zsh
              --header='Enter hop   →/Tab descend   ←/S-Tab up   ^S favorite' \
```

Add a `ctrl-s` branch to the `case` statement, immediately before the final `*)` branch:

```zsh
            ctrl-s)
                # Signal upward; hop() owns config mutation.
                print -r -- "$sel"
                return 2
                ;;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zsh test_hop.zsh`
Expected: PASS, 84 total.

- [ ] **Step 5: Commit**

```bash
git add hop.plugin.zsh test_hop.zsh
git commit -m "feat: star favorites in the picker and signal ctrl-s toggles

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SWYKAEcegMgeSpq9dBwr8M"
```

---

### Task 8: Wire search, file landing, and toggling into `hop()`

**Files:**
- Modify: `hop.plugin.zsh:223-308` (`hop`)
- Test: `test_hop.zsh`

**Interfaces:**
- Consumes: every function from Tasks 1–7
- Produces: no new callable interface. `hop` behavior changes: the default picker list is the ranked index rather than bare bookmarks; `Enter` on a file `cd`s to its parent; exit code 2 from `_hop_pick` toggles the favorite and reopens the picker.

- [ ] **Step 1: Write the failing tests**

Append to `test_hop.zsh` before the final summary. These cover the non-interactive paths only — the picker still needs a TTY:

```zsh
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

check "-v reports a 0.2 version" \
      "1" "$(HOPRC="$hrc" hop -v | grep -c '0\.2')"

check "help mentions the favorite key" \
      "1" "$(HOPRC="$hrc" hop -h | grep -ci 'favorite')"
```

Note: the `exact alias still jumps` check runs `hop` in the test shell and changes its directory. Add `cd "$tmp"` on the line immediately after it so later assertions are unaffected.

- [ ] **Step 2: Run tests to verify they fail**

Run: `zsh test_hop.zsh`
Expected: FAIL — `-l shows the depth` reports `0`, and `-v reports a 0.2 version` reports `0`.

- [ ] **Step 3: Implement**

Bump the version at `hop.plugin.zsh:8`:

```zsh
typeset -g HOP_VERSION="0.2.0"
```

Update the `-l` branch to show depth. Find:

```zsh
        print -r -- "$records" | awk -F'\t' '{
            printf "  %-22s %s%s\n", $1, $2, ($3=="missing" ? "  [missing]" : "")
        }'
```

Replace with:

```zsh
        print -r -- "$records" | awk -F'\t' '{
            printf "  %-22s %s%s  depth=%s\n", $1, $2, ($3=="missing" ? "  [missing]" : ""), $4
        }'
```

Add `favorite` to the help text. Find:

```zsh
            print -r -- "in the picker:  Enter hop   →/Tab descend   ←/S-Tab up"
```

Replace with:

```zsh
            print -r -- "in the picker:  Enter hop   →/Tab descend   ←/S-Tab up   ^S favorite"
```

Replace the picker-invocation and landing block. Find:

```zsh
    elif [[ -z "$target" ]]; then
        # No exact hit (or no argument): open the picker, seeded with the
        # argument. A trailing slash on a non-alias degrades to a plain query.
        target="$(print -r -- "$records" | _hop_format | _hop_pick "$arg")" || return $?
    fi

    [[ -z "$target" ]] && return 1          # picker cancelled

    if [[ ! -d "$target" ]]; then
        print -u2 "hop: $target no longer exists. Fix it with: hop -e"
        return 1
    fi

    cd "$target"
```

Replace with:

```zsh
    elif [[ -z "$target" ]]; then
        # No exact hit (or no argument): search the whole index, seeded with
        # the argument. Exit 2 means "toggle this favorite and come back", so
        # loop until the user selects or cancels.
        local rc_pick
        while true; do
            target="$(print -r -- "$records" | _hop_index | _hop_rank | _hop_format | _hop_pick "$arg")"
            rc_pick=$?

            (( rc_pick == 0 )) && break
            (( rc_pick == 1 )) && return 1        # cancelled
            (( rc_pick != 2 )) && return $rc_pick # fzf missing, etc.

            # rc_pick == 2: toggle the favorite, rebuild, reopen.
            if print -r -- "$records" | awk -F'\t' -v p="$target" '$2==p{f=1} END{exit !f}'; then
                _hop_fav_remove "$target"
            else
                _hop_fav_add "$target"
            fi
            records="$(_hop_parse)" || return 1
            target=''
        done
    fi

    [[ -z "$target" ]] && return 1          # picker cancelled

    # Landing on a file means landing in its directory. Files are never opened.
    [[ -f "$target" ]] && target="${target:h}"

    if [[ ! -d "$target" ]]; then
        print -u2 "hop: $target no longer exists. Fix it with: hop -e"
        return 1
    fi

    cd "$target"
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `zsh test_hop.zsh`
Expected: PASS, 89 total.

- [ ] **Step 5: Manual verification (requires a real terminal)**

The picker cannot be driven from an automated harness. In an interactive shell:

```sh
cd ~/Code/hop/.worktrees/browser
HOPRC=~/.hoprc source hop.plugin.zsh
hop goals
```

Confirm each of: files appear alongside directories; `★` marks bookmarks; `→` descends; `←` backs out; `Ctrl-S` toggles a star and the list reopens; `Enter` on a file lands in its parent directory; `Esc` leaves the shell where it was.

- [ ] **Step 6: Commit**

```bash
git add hop.plugin.zsh test_hop.zsh
git commit -m "feat: search the full index, land files in their folder, toggle favorites

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SWYKAEcegMgeSpq9dBwr8M"
```

---

### Task 9: Documentation

**Files:**
- Modify: `README.md`, `DESIGN.md`, `hoprc.example`

**Interfaces:**
- Consumes: the finished behavior from Tasks 1–8
- Produces: nothing callable

- [ ] **Step 1: Update `hoprc.example`**

Replace the file with:

```
# ~/.hoprc — bookmarks for `hop`
#
#   alias<whitespace>path<whitespace>[depth=N]
#
# A leading ~ expands to $HOME. Paths may contain spaces. `#` starts a comment.
# Every entry here is a favorite: it shows ★ and ranks above everything else.
#
# depth=N controls how far below a bookmark to index for search.
#   depth=0  jump target only — nothing beneath it appears in search
#   omitted  defaults to 2
# Use depth=0 for big noisy trees you only ever cd into.

code        ~/Code                        depth=0
dotfiles    ~/.config                     depth=0

notes       ~/Documents/Notes             depth=3
daily       ~/Documents/Daily Notes       depth=1

# Cloud-synced directories work even when reached through symlinks:
# vault     ~/Library/Mobile Documents/iCloud~md~obsidian/Documents/Vault
```

- [ ] **Step 2: Update `README.md`**

Change the tagline under `# hop` from "Curated directory bookmarks you can walk into." to "**Bookmark a few directories. Search everything inside them.**"

In the `## Usage` block, replace the command list with:

```sh
hop                # search everything in your bookmarked trees
hop goals          # jump to the best match for "goals"
hop notes          # exact alias -> jump immediately, no picker
hop notes/         # open the picker INSIDE ~/Documents/Notes
hop -l             # list bookmarks
hop -e             # edit ~/.hoprc
hop -h             # help
```

In the `### Keys in the picker` table, add a row between the `←` row and the `Ctrl-F` row:

```
| `Ctrl-S` | favorite / unfavorite the highlighted item |
```

Add a new section immediately after `### Why hop <alias>/`:

```markdown
### Search depth

Bookmarks are searched two levels deep by default. Change it per bookmark:

```sh
code      ~/Code       depth=0    # jump target only, never searched
notes     ~/Notes      depth=3    # searched deeply
```

`depth=0` is for large trees you only ever `cd` into — without it, thousands of
`node_modules` and plugin files crowd out the handful of notes you actually search
for.

### Favorites

Everything in `~/.hoprc` is a favorite: it shows `★` and ranks above every indexed
result. Press `Ctrl-S` in the picker to add or remove one. `hop` writes the change
to `~/.hoprc` and leaves your comments and formatting alone.
```

Update the `## Tests` count from `27 assertions` to `89 assertions`.

- [ ] **Step 3: Update `DESIGN.md`**

Add these rows to the architecture table, after the `_hop_children` row:

```
| `_hop_index` | bookmarks → candidate records | yes (reads fs) |
| `_hop_rank` | candidates → emission order | yes |
| `_hop_alias_for` | path → unique alias | yes |
| `_hop_fav_add` / `_hop_fav_remove` | mutate `.hoprc` | no (writes) |
```

Add a fourth entry to the "Three traps worth knowing" section, and retitle that
heading to "Four traps worth knowing":

```markdown
### 4. BSD find has no `-printf`

Tagging each result with its type inline is not portable. `_hop_index` runs `find`
twice per bookmark — once with `-type d`, once with `-type f` — and tags each stream
with `sed`. Two passes over a tree that scans in ~40 ms is cheaper than depending on
GNU findutils.
```

Replace the "Deliberately out of scope" section's first sentence with:

```markdown
Opening files, frecency/usage tracking, content search (grep inside files), caching,
and multi-select.
```

- [ ] **Step 4: Verify the docs match reality**

Run: `zsh test_hop.zsh` and confirm the assertion count printed matches the number claimed in `README.md`. Run `hop -h` and confirm every documented flag exists.

- [ ] **Step 5: Commit**

```bash
git add README.md DESIGN.md hoprc.example
git commit -m "docs: document search, depth, and favorites for v0.2

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SWYKAEcegMgeSpq9dBwr8M"
```

---

## Verification

After Task 9, from `~/Code/hop/.worktrees/browser`:

```bash
zsh test_hop.zsh              # expect 89 passed, 0 failed
git log --oneline main..HEAD  # expect 9 commits
git diff --stat main..HEAD
```

Then the manual pass from Task 8 Step 5, which is the only coverage the interactive
loop gets.
