# hop — curated directory bookmarks you can walk into
# https://github.com/shrikantvarma/hop
#
# Must be SOURCED, not executed. A process gets a *copy* of its parent's
# working directory, so `cd` inside a script dies with the script. Changing the
# interactive shell's directory requires code running in that shell.

typeset -g HOP_VERSION="0.2.0"

# Config file. Override by setting HOPRC before sourcing.
: ${HOPRC:=$HOME/.hoprc}

# Directories never worth showing when descending. Override by declaring your
# own _HOP_SKIP array before sourcing this file.
if (( ! ${+_HOP_SKIP} )); then
    typeset -ga _HOP_SKIP=(
        .git .hg .svn node_modules __pycache__ .venv venv .tox .mypy_cache
        .pytest_cache .ruff_cache .cache .next .nuxt dist build target vendor
        .gradle .idea .DS_Store .obsidian .trash
    )
fi

# Extra options passed through to fzf, e.g. HOP_FZF_OPTS='--height=80%'
: ${HOP_FZF_OPTS:=}

# Index depth for bookmarks without an explicit depth= token. Raise it if your
# favorites are shallow anchors over deep trees (vaults, monorepos).
: ${HOP_DEFAULT_DEPTH:=2}

# ---------------------------------------------------------------------------
# _hop_display_path — abbreviate $HOME back to ~
#
# The inverse of the leading-~ expansion in _hop_parse_line. Used both for
# picker/list display and when writing alias-less entries to the rc file, so
# the account name never appears in either place.
# ---------------------------------------------------------------------------
_hop_display_path() {
    emulate -L zsh
    local p="$1"
    if [[ "$p" == "$HOME" ]]; then
        print -r -- "~"
    elif [[ "$p" == "$HOME/"* ]]; then
        print -r -- "~${p#$HOME}"
    else
        print -r -- "$p"
    fi
}

# ---------------------------------------------------------------------------
# _hop_parse_line — parse one raw rc line into its fields
#
# Shared by every function that reads rc-file lines (_hop_parse,
# _hop_fav_remove, _hop_fav_set_depth), so the comment-strip, the two-branch
# depth-or-no-depth regex, and the leading-~ expansion live in exactly one
# place instead of three copies that can drift out of sync.
#
#   in  : $1 -- the raw line, exactly as read from the file
#   out : globals (not `local` -- these are this helper's return values,
#         same convention as zsh's own $match/$MATCH/$REPLY):
#           _hop_pl_name     -- the alias
#           _hop_pl_rawpath  -- the path exactly as written (~ intact)
#           _hop_pl_path     -- the path with a leading ~ expanded to $HOME
#           _hop_pl_depth    -- the raw depth= token, or "" if absent
#           _hop_pl_aliased  -- 1 for `alias path` lines, 0 for alias-less
#                                path-only lines (name synthesized from path)
#           _hop_pl_stripped -- the line with its trailing #comment removed;
#                                callers that need to preserve the comment
#                                when rewriting a line can recover it via
#                                ${line#$_hop_pl_stripped}
#
# Returns 1 (fields left blank, only _hop_pl_stripped is meaningful) for a
# blank/comment-only line or one with no parseable path.
# ---------------------------------------------------------------------------
_hop_parse_line() {
    emulate -L zsh
    local line="$1"
    _hop_pl_stripped="${line%%'#'*}"                  # strip comments
    _hop_pl_name='' _hop_pl_rawpath='' _hop_pl_path='' _hop_pl_depth=''
    _hop_pl_aliased=1

    [[ "$_hop_pl_stripped" == *[^[:space:]]* ]] || return 1   # blank / whitespace only

    # Alias-less entries: a line may be just a path (plus optional depth=).
    #     ~/Clients/Acme/Code    depth=2
    #     /opt/data
    # Aliases never begin with `~` or `/`, so the first non-space character
    # decides the form. Paths may contain spaces, so the path cannot be
    # whitespace-split: the trailing depth= token is anchored instead, same
    # as in the aliased forms below.
    if [[ "$_hop_pl_stripped" =~ '^[[:space:]]*[~/]' ]]; then
        _hop_pl_aliased=0
        if [[ "$_hop_pl_stripped" =~ '^[[:space:]]*(.*[^[:space:]])[[:space:]]+depth=([^[:space:]]+)[[:space:]]*$' ]]; then
            _hop_pl_rawpath="$match[1]"
            _hop_pl_depth="$match[2]"
        else
            # Blank lines were rejected above, so this trim cannot fail.
            [[ "$_hop_pl_stripped" =~ '^[[:space:]]*(.*[^[:space:]])[[:space:]]*$' ]]
            _hop_pl_rawpath="$match[1]"
        fi

    # Aliased forms. Try the depth= form first. A keyed token is used rather
    # than a bare trailing number because paths may contain spaces:
    # "~/Notes/Chapter 3" would otherwise parse as path "~/Notes/Chapter"
    # with depth 3.
    elif [[ "$_hop_pl_stripped" =~ '^[[:space:]]*([^[:space:]]+)[[:space:]]+(.*[^[:space:]])[[:space:]]+depth=([^[:space:]]+)[[:space:]]*$' ]]; then
        _hop_pl_name="$match[1]"
        _hop_pl_rawpath="$match[2]"
        _hop_pl_depth="$match[3]"
    elif [[ "$_hop_pl_stripped" =~ '^[[:space:]]*([^[:space:]]+)[[:space:]]+(.*[^[:space:]])[[:space:]]*$' ]]; then
        _hop_pl_name="$match[1]"
        _hop_pl_rawpath="$match[2]"
    else
        return 1        # malformed: no path
    fi

    # Expand a leading ~ ONLY, anchored to position 0. A global substitution
    # would corrupt paths that legitimately contain ~, such as macOS iCloud
    # container names like `iCloud~md~obsidian`.
    _hop_pl_path="$_hop_pl_rawpath"
    if [[ "$_hop_pl_path" == "~" ]]; then
        _hop_pl_path="$HOME"
    elif [[ "$_hop_pl_path" == "~/"* ]]; then
        _hop_pl_path="$HOME/${_hop_pl_path#\~/}"
    fi

    # An alias-less entry's display identity is its ~-abbreviated EXPANDED
    # path, so `/Users/you/Code` and `~/Code` in the file produce the same
    # name, and the account name never reaches the picker.
    (( _hop_pl_aliased )) || _hop_pl_name="$(_hop_display_path "$_hop_pl_path")"
}

# ---------------------------------------------------------------------------
# _hop_parse — pure text transform, no side effects
#
# Reads $HOPRC (or $1), writes one record per valid entry:
#     alias \t path \t (ok|missing) \t depth
# Malformed lines are skipped and reported to stderr with a line number.
# ---------------------------------------------------------------------------
_hop_parse() {
    emulate -L zsh

    local rc="${1:-$HOPRC}"
    local line depth lineno=0

    [[ -r "$rc" ]] || { print -u2 "hop: cannot read $rc"; return 1 }

    while IFS= read -r line || [[ -n "$line" ]]; do
        (( lineno++ ))

        if ! _hop_parse_line "$line"; then
            # A blank/comment-only line strips to nothing (or whitespace) and
            # is skipped silently; anything else that failed to parse had
            # real content with no usable path, and is worth a warning.
            [[ "$_hop_pl_stripped" == *[^[:space:]]* ]] \
                && print -u2 "hop: $rc:$lineno: malformed (no path) -- skipped"
            continue
        fi

        depth="$_hop_pl_depth"
        if [[ -z "$depth" ]]; then
            depth=$HOP_DEFAULT_DEPTH
        elif [[ "$depth" != <-> ]]; then
            print -u2 "hop: $rc:$lineno: depth=$depth is not a number -- using $HOP_DEFAULT_DEPTH"
            depth=$HOP_DEFAULT_DEPTH
        fi

        # printf, not `print -r`: -r suppresses escape interpretation, which
        # would emit a literal backslash-t instead of a tab separator.
        # -e, not -d: a bookmark may be a FILE. Settings can save a file, and
        # Enter on it lands in its parent directory. Testing -d here would
        # mark every favorited file "missing" and drop it from the index.
        if [[ -e "$_hop_pl_path" ]]; then
            printf '%s\t%s\t%s\t%s\n' "$_hop_pl_name" "$_hop_pl_path" "ok" "$depth"
        else
            printf '%s\t%s\t%s\t%s\n' "$_hop_pl_name" "$_hop_pl_path" "missing" "$depth"
        fi
    done < "$rc"
}

# ---------------------------------------------------------------------------
# _hop_children — emit immediate subdirectories of $1 as `path \t name`
#
# The glob qualifier (-/N) is load-bearing: `-` resolves symlinks before the
# type test, `/` keeps directories only, `N` yields nothing instead of erroring
# on no match. Without `-`, a bookmark that is itself a symlink (or lives
# behind one, as with iCloud/Dropbox containers) reports zero children while
# ordinary directories work fine — an asymmetric failure that reads as a
# filesystem problem rather than a bug. `find` shares this default; a
# reimplementation needs `find -L`.
# ---------------------------------------------------------------------------
_hop_children() {
    emulate -L zsh
    setopt local_options no_nomatch

    local parent="$1" child name
    [[ -d "$parent" ]] || return 1

    # Directories first, then files — the (-/N) qualifier resolves symlinks
    # before the type test, (-.N) does the same for plain files.
    # zsh's .* glob never yields "." or ".." (unlike a literal shell glob in
    # other shells), so no extra guard is needed to skip them here.
    for child in "$parent"/*(-/N) "$parent"/.*(-/N); do
        name="${child:t}"
        (( ${_HOP_SKIP[(Ie)$name]} )) && continue
        printf '%s\t%s/\t%s\n' "$child" "$name" "dir"
    done

    for child in "$parent"/*(-.N) "$parent"/.*(-.N); do
        name="${child:t}"
        (( ${_HOP_SKIP[(Ie)$name]} )) && continue
        printf '%s\t%s\t%s\n' "$child" "$name" "file"
    done
}

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

    local alias p st depth s
    local -a prune

    # Build the -prune expression once: \( -name .git -o -name ... \)
    # An empty skip list must still yield a valid expression — `-name ''`
    # matches nothing, keeping find happy if a user declares _HOP_SKIP=().
    if (( ${#_HOP_SKIP} )); then
        prune=('(')
        for s in $_HOP_SKIP; do
            prune+=(-name "$s" -o)
        done
        prune[-1]=')'      # replace the trailing -o
    else
        prune=('(' -name '' ')')
    fi

    while IFS=$'\t' read -r alias p st depth; do
        if [[ "$st" != "ok" ]]; then
            # Spec: a dead bookmark is excluded from indexing but still shown,
            # marked, so the picker itself signals the config needs fixing.
            printf '%s\t%s\t%s\t%s\t%s\n' "dir" "$p" "$alias  [missing]" "1" "0"
            continue
        fi

        # The bookmark itself is always present and always a favorite. It may
        # be a file — a starred file is a legal bookmark.
        if [[ -d "$p" ]]; then
            printf '%s\t%s\t%s\t%s\t%s\n' "dir" "$p" "$alias" "1" "0"
        else
            printf '%s\t%s\t%s\t%s\t%s\n' "file" "$p" "$alias" "1" "0"
            continue        # nothing to walk beneath a file
        fi

        (( depth > 0 )) || continue

        # NB: no sed here — BSD sed does not interpret \t in replacements
        # (GNU does), so tagging the streams with sed silently corrupts the
        # records on macOS. awk's -v is portable.
        for s in dir file; do
            find -L "$p" -mindepth 1 -maxdepth "$depth" "${prune[@]}" -prune -o -type "${s[1]}" -print 2>/dev/null \
                | awk -v kind="$s" -v root="$p" -v al="$alias" 'BEGIN{OFS="\t"}
                    {
                        rel = substr($0, length(root) + 2)
                        if (rel == "") next
                        n = split(rel, parts, "/")
                        print kind, $0, al "/" rel, 0, n
                    }'
        done
    done
}

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

# ---------------------------------------------------------------------------
# _hop_fav_add — append a bookmark to the config file
#
# Idempotent: adding an already-bookmarked path does nothing.
# ---------------------------------------------------------------------------
_hop_fav_add() {
    emulate -L zsh

    local target="$1" rc="${2:-$HOPRC}"

    [[ -e "$rc" ]] || : > "$rc"
    if [[ ! -w "$rc" ]]; then
        print -u2 "hop: cannot write $rc"
        return 1
    fi

    # Already bookmarked?
    if _hop_parse "$rc" 2>/dev/null | cut -f2 | grep -qxF -- "$target"; then
        return 0
    fi

    # A hand-edited file may lack a final newline; appending straight onto it
    # would merge the new entry into the last line, corrupting both. tail -c 1
    # is BSD/GNU-common; $(...) strips a newline, so non-empty output means
    # the last byte is NOT a newline.
    if [[ -s "$rc" && -n "$(tail -c 1 "$rc")" ]]; then
        print >> "$rc"
    fi

    # No invented alias: the entry's identity is its path, stored
    # ~-abbreviated so the account name stays out of the file. Users who
    # want a short jump token add one by hand (hop -e).
    print -r -- "$(_hop_display_path "$target")" >> "$rc"
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
    local line tmpf
    local -a keep

    [[ -r "$rc" ]] || return 1
    if [[ ! -w "$rc" ]]; then
        print -u2 "hop: cannot write $rc"
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        if _hop_parse_line "$line" && [[ "$_hop_pl_path" == "$target" ]]; then
            continue     # drop this line
        fi
        keep+=("$line")
    done < "$rc"

    tmpf="$rc.hoptmp$$"
    if (( ${#keep} )); then
        print -rl -- "${keep[@]}" > "$tmpf"
    else
        : > "$tmpf"        # print -rl with an empty array emits one newline
    fi
    # cat-into rather than mv: keeps the config file's inode, so permissions
    # like chmod 600 survive an unfavorite.
    cat "$tmpf" > "$rc" && rm -f "$tmpf"
}

# ---------------------------------------------------------------------------
# _hop_split_expect — parse `fzf --print-query --expect` output into
# `query \t key \t path`
#
# fzf emits the current query on line 1 (empty if nothing was typed), the
# pressed key on line 2 (EMPTY for plain Enter), and the selected record on
# line 3. The query is carried so a favorite toggle can refresh the list
# without throwing away what the user typed. Pure string handling, split out
# so it is testable without a terminal.
# ---------------------------------------------------------------------------
_hop_split_expect() {
    emulate -L zsh
    local out="$1" q rest key sel
    q="${out%%$'\n'*}"
    rest="${out#*$'\n'}"
    key="${rest%%$'\n'*}"
    sel="${rest#*$'\n'}"
    sel="${sel%%$'\t'*}"          # field 1 is the real path
    printf '%s\t%s\t%s\n' "$q" "$key" "$sel"
}

# ---------------------------------------------------------------------------
# _hop_format — index records -> `path \t display` picker lines
#
#   in : kind \t path \t display \t fav \t depth
#   out: path \t display
#
# Favorites get a star; everything else gets two spaces so the columns align.
# ---------------------------------------------------------------------------
_hop_format() {
    emulate -L zsh
    awk -F'\t' 'BEGIN{OFS="\t"}
        { print $2, ($4 == "1" ? "★ " : "  ") $3 }'
}

# ---------------------------------------------------------------------------
# _hop_pick — consume `path \t display` lines on stdin, emit one chosen path
#
#   $1  initial query   $2  initial prompt   $3  header
#   $4  extra expected key(s), comma-separated -- any of them accepts the
#       highlighted line with return 4 (the saved-folders list binds
#       space,tab,ctrl-d this way)
#   $5  with_settings -- truthy only at the one call site whose caller
#       actually handles a return of 3 (opening Settings) and 5 (a favorite
#       toggle that needs the full list re-ranked). Everywhere else those
#       keys must stay unbound: binding them on a picker whose caller cannot
#       honour the return code either gets swallowed by that caller's own
#       `|| return 1`/`continue` (a silent, confusing cancel) or just
#       propagates out to a caller with no handling.
#   $6  with_toggle -- Space/Tab toggle the highlighted item's favorite state
#       INSIDE the picker loop: the list re-stars in place and the cursor,
#       level, and typed query all survive. Used by the browse and
#       Add-more-folders screens, where jumping back to the top after every
#       toggle would make bulk curation miserable.
#
# Loops so the list can be replaced in place:
#   →             descend into the highlighted directory
#   ←             back out one level
#   Enter         accept
#   Space/Tab     toggle favorite (with_toggle; Tab only under with_settings)
#
# Binding the arrows is safe because fzf aliases them to ctrl-f / ctrl-b
# (forward-char / backward-char), which remain available for moving the cursor
# inside the query. Space is NEVER bound under with_settings: there the query
# is the primary interface and a space types an AND between search terms.
# `?` opens Settings (Ctrl-T kept as a hidden legacy alias); a literal ? is
# essentially never part of a folder-name query.
#
# Return-code protocol -- every caller relies on these exact values:
#   0    a selection was made (Enter); the path is on stdout
#   1    cancelled (Esc, or fzf itself exited non-zero)
#   3    ? (or Ctrl-T) pressed with with_settings enabled -- caller should
#        open Settings; nothing is printed
#   4    one of the configured extra keys ($4) was pressed; the highlighted
#        path is on stdout, same as a plain Enter
#   5    Tab pressed at the TOP level with with_settings enabled -- the
#        caller should toggle the favorite and rebuild its re-ranked list.
#        `query \t path` is on stdout so the search can be re-seeded.
#        (Toggles below the top level are handled in place instead: only the
#        top list's ordering depends on favorite state.)
#   127  fzf is not installed
# ---------------------------------------------------------------------------
_hop_pick() {
    emulate -L zsh

    local query="$1"
    local lines out q key sel kids prompt="${2:-hop > }"
    local header="${3:-Enter hop   → descend   ← up}" extra_key="${4:-}"
    local with_settings="${5:-0}" with_toggle="${6:-0}"
    local -a stack_lines stack_prompt expect

    if ! command -v fzf >/dev/null 2>&1; then
        print -u2 "hop: fzf is not installed -- see https://github.com/junegunn/fzf"
        return 127
    fi

    lines="$(cat)"

    expect=(right left)
    (( with_settings )) && expect+=('?' ctrl-t tab)
    (( with_toggle )) && expect+=(tab space)
    [[ -n "$extra_key" ]] && expect+=("${(s:,:)extra_key}")
    (( with_settings )) && header="${header}   Tab ★   ? Settings"

    while true; do
        out="$(print -r -- "$lines" | fzf \
              -i \
              --delimiter=$'\t' \
              --with-nth=2 \
              --query="$query" \
              --print-query \
              --height=60% \
              --reverse \
              --border \
              --prompt="$prompt" \
              --expect="${(j:,:)expect}" \
              --preview='ls -1p {1} 2>/dev/null | head -40' \
              --preview-window='right:45%:wrap' \
              --header="$header" \
              ${=HOP_FZF_OPTS})" || return 1

        out="$(_hop_split_expect "$out")"
        q="${out%%$'\t'*}"
        out="${out#*$'\t'}"
        key="${out%%$'\t'*}"
        sel="${out#*$'\t'}"
        query=''                       # don't re-seed after the first round

        # Extra keys are checked before the named cases so a caller may bind
        # space/tab (the saved-folders list does) without colliding with the
        # toggle handling below.
        if [[ -n "$extra_key" && ",$extra_key," == *",$key,"* ]]; then
            print -r -- "$sel"
            return 4
        fi

        case "$key" in
            right)
                kids="$(_hop_children "$sel" | _hop_mark_favs)"
                if [[ -n "$kids" ]]; then
                    stack_lines+=("$lines")
                    stack_prompt+=("$prompt")
                    lines="$kids"
                    prompt="${sel:t}/ > "
                fi
                ;;
            left)
                if (( ${#stack_lines} )); then
                    lines="${stack_lines[-1]}"
                    prompt="${stack_prompt[-1]}"
                    shift -p stack_lines
                    shift -p stack_prompt
                    # Stars may have been toggled while a level deeper.
                    (( with_toggle || with_settings )) \
                        && lines="$(print -r -- "$lines" | _hop_restar)"
                fi
                ;;
            '?'|ctrl-t)
                (( with_settings )) || continue
                return 3
                ;;
            tab|space)
                [[ -n "$sel" ]] || continue
                if (( with_toggle )) || (( with_settings && ${#stack_lines} )); then
                    # Toggle in place: same level, same query, star refreshed.
                    _hop_toggle_fav "$sel"
                    lines="$(print -r -- "$lines" | _hop_restar)"
                    query="$q"
                elif (( with_settings )); then
                    # Top level: ordering depends on favorite state, so the
                    # caller must rebuild the ranked list and re-seed the query.
                    printf '%s\t%s\n' "$q" "$sel"
                    return 5
                fi
                ;;
            '')                        # Enter
                print -r -- "$sel"
                return 0
                ;;
            *)                         # Enter
                print -r -- "$sel"
                return 0
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# _hop_mark_favs — star bookmarked paths in `path \t display [\t kind]` lines
#
# The children listing knows nothing about favorites, so without this the
# browse view gives no feedback when Settings stars an item — the change only
# became visible on the next full `hop` run.
# ---------------------------------------------------------------------------
_hop_mark_favs() {
    emulate -L zsh
    local favs
    # Tab-joined: tabs cannot occur in our paths (they are the field
    # separator everywhere). An NR==FNR two-file join is NOT safe here —
    # with an empty favorites list it swallows the entire data stream.
    favs="$(_hop_parse 2>/dev/null | cut -f2 | tr '\n' '\t')"
    awk -F'\t' -v OFS='\t' -v favlist="$favs" '
        BEGIN { n = split(favlist, a, "\t"); for (i = 1; i <= n; i++) fav[a[i]] = 1 }
        { $2 = (fav[$1] ? "★ " : "  ") $2; print }
    '
}

# ---------------------------------------------------------------------------
# _hop_restar — refresh the ★ column after a favorite toggle
#
# Strips the two-column star prefix that _hop_mark_favs/_hop_format prepended
# and re-marks from the current rc file, so an in-picker toggle is visible
# immediately without rebuilding the listing. sub() rather than substr():
# ★ is multibyte, and BSD awk's substr counts bytes.
# ---------------------------------------------------------------------------
_hop_restar() {
    emulate -L zsh
    awk -F'\t' 'BEGIN{OFS="\t"}
        { if (!sub(/^★ /, "", $2)) sub(/^  /, "", $2); print }' | _hop_mark_favs
}

# ---------------------------------------------------------------------------
# _hop_browse — descend-mode picker loop rooted at $1; prints the chosen path
#
# with_toggle: Space/Tab star or unstar the highlighted item without leaving
# the spot being browsed — the same gesture as the Settings screens.
# ---------------------------------------------------------------------------
_hop_browse() {
    emulate -L zsh
    local base="$1" kids sel
    kids="$(_hop_children "$base" | _hop_mark_favs)"
    if [[ -z "$kids" ]]; then
        print -u2 "hop: ${base:t} has no subdirectories"
        return 1
    fi
    sel="$(print -r -- "$kids" | _hop_pick '' "${base:t}/ > " \
        'Enter hop   → descend   ← up   Space ★' '' 0 1)" || return $?
    print -r -- "$sel"
}

# ---------------------------------------------------------------------------
# _hop_toggle_fav — add the path if unbookmarked, remove it if bookmarked
# ---------------------------------------------------------------------------
_hop_toggle_fav() {
    emulate -L zsh
    local target="$1"
    if _hop_parse 2>/dev/null | cut -f2 | grep -qxF -- "$target"; then
        _hop_fav_remove "$target"
    else
        _hop_fav_add "$target"
    fi
}

# ---------------------------------------------------------------------------
# _hop_fav_set_depth — update one bookmark's depth, retaining its alias.
# ---------------------------------------------------------------------------
_hop_fav_set_depth() {
    emulate -L zsh
    local target="$1" depth="$2" rc="${3:-$HOPRC}" line comment tmpf
    local -a out
    [[ "$depth" == <-> ]] || return 1
    [[ -r "$rc" && -w "$rc" ]] || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        if _hop_parse_line "$line" && [[ "$_hop_pl_path" == "$target" ]]; then
            comment="${line#$_hop_pl_stripped}"
            # An alias-less line stays alias-less: rewriting it with its
            # synthesized name would freeze that name into the file.
            if (( _hop_pl_aliased )); then
                out+=("$_hop_pl_name"$'\t'"$_hop_pl_rawpath depth=$depth${comment:+ }$comment")
            else
                out+=("$_hop_pl_rawpath depth=$depth${comment:+ }$comment")
            fi
            continue
        fi
        out+=("$line")
    done < "$rc"
    tmpf="$rc.hoptmp$$"
    if (( ${#out} )); then
        print -rl -- "${out[@]}" > "$tmpf"
    else
        : > "$tmpf"        # print -rl with an empty array emits one newline
    fi
    cat "$tmpf" > "$rc" && rm -f "$tmpf"
}

# ---------------------------------------------------------------------------
# _hop_edit_favorite — choose a saved folder's search depth.
# ---------------------------------------------------------------------------
_hop_edit_favorite() {
    emulate -L zsh
    local target="$1" alias depth choice records
    # One parse, not one per field: the depth picker itself is a single
    # choice, so there is no loop here for a second round to serve.
    records="$(_hop_parse 2>/dev/null)"
    alias="$(print -r -- "$records" | awk -F'\t' -v p="$target" '$2==p {print $1; exit}')"
    depth="$(print -r -- "$records" | awk -F'\t' -v p="$target" '$2==p {print $4; exit}')"
    choice="$(printf '%s\t%s\n' \
        '__hop_depth_0__' 'Search depth: 0' \
        '__hop_depth_1__' 'Search depth: 1' \
        '__hop_depth_2__' 'Search depth: 2' \
        '__hop_depth_3__' 'Search depth: 3' \
        '__hop_depth_4__' 'Search depth: 4' \
        '__hop_depth_5__' 'Search depth: 5' \
        '__hop_depth_6__' 'Search depth: 6' | _hop_pick '' "saved folder: $alias (depth: $depth) > " 'Enter choose   Esc back')" || return 1
    case "$choice" in
        __hop_depth_*) _hop_fav_set_depth "$target" "${${choice##*depth_}%%__}"; return $? ;;
        *) return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# _hop_settings — the visible home for adding/removing folders and depth.
# ---------------------------------------------------------------------------
_hop_settings() {
    emulate -L zsh
    local base="$1" records choice target
    while true; do
        choice="$(printf '%s\t%s\n' \
            '__hop_add__' 'Add more folders' \
            '__hop_saved__' 'Saved folders & search depth' | _hop_pick '' 'settings > ' 'Enter choose   Esc return')" || return 1
        case "$choice" in
            __hop_add__) _hop_manage_favorites "$base" || true ;;
            __hop_saved__)
                records="$(_hop_parse)" || return 1
                [[ -z "$records" ]] && continue
                target="$(print -r -- "$records" | awk -F'\t' -v home="$HOME" 'BEGIN{OFS="\t"} {
                    display_path=$2
                    if (display_path == home) display_path="~"
                    else if (index(display_path, home "/") == 1) display_path="~" substr(display_path, length(home) + 1)
                    print $2, "★ " $1 ($1 == display_path ? "" : "   " display_path) "   depth=" $4
                }' | _hop_pick '' 'saved folders > ' 'Enter change depth   Space unstar   Esc back' 'space,tab,ctrl-d')"
                case $? in
                    0) _hop_edit_favorite "$target" || true ;;
                    4) _hop_fav_remove "$target" || true ;;
                    *) continue ;;
                esac
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# _hop_manage_favorites — browse the filesystem and add/remove bookmarks.
#
# Space/Tab toggle the highlighted item's saved state inside the picker
# (with_toggle), so the cursor stays put and several folders can be starred
# in one pass. Enter and Esc both mean "done" — Enter never changes state,
# the same as everywhere else in hop.
# ---------------------------------------------------------------------------
_hop_manage_favorites() {
    emulate -L zsh
    local base="$1" kids
    kids="$(_hop_children "$base" | _hop_mark_favs)"
    if [[ -z "$kids" ]]; then
        print -u2 "hop: ${base:t} has no folders to add"
        return 1
    fi
    print -r -- "$kids" | _hop_pick '' "settings > " \
        'Space star/unstar   → descend   ← up   Enter/Esc done' '' 0 1 >/dev/null
    return 0
}

# ---------------------------------------------------------------------------
# _hop_seed_rc — write a commented starter file. Does NOT scan the disk.
# ---------------------------------------------------------------------------
_hop_seed_rc() {
    emulate -L zsh
    cat > "$HOPRC" <<'EOF'
# ~/.hoprc — bookmarks for `hop`
#
#   alias<whitespace>path
#
# A leading ~ expands to $HOME. Paths may contain spaces. `#` starts a comment.

# code    ~/Code
# notes   ~/Documents/Notes
EOF
    print -u2 "hop: created $HOPRC — use Settings / Add more folders, or edit with: hop -e"
    return 0
}

# ---------------------------------------------------------------------------
# hop — orchestration; the only unit that calls cd
# ---------------------------------------------------------------------------
hop() {
    emulate -L zsh
    local records target arg="$1" descend=0

    case "$1" in
        -h|--help)
            print -r -- "hop $HOP_VERSION — curated directory bookmarks you can walk into"
            print -r -- ""
            print -r -- "usage: hop                 pick from all bookmarks"
            print -r -- "       hop <text>          pick, pre-filtered by <text>"
            print -r -- "       hop <alias>         jump straight there (exact alias only)"
            print -r -- "       hop <alias>/        open the picker INSIDE that bookmark"
            print -r -- "       hop -b | --browse [path]  browse from path (default: here)"
            print -r -- "       hop -f | --favorites jump from saved folders only"
            print -r -- "       hop -l | --list     list bookmarks"
            print -r -- "       hop -e | --edit     edit $HOPRC"
            print -r -- "       hop -v | --version  print version"
            print -r -- ""
            print -r -- "in the picker:  Enter hop   → descend   ← up"
            print -r -- "                Tab star/unstar   ? Settings / Add more folders"
            print -r -- ""
            print -r -- "first run: Settings / Add more folders opens at the current directory"
            return 0
            ;;
        -v|--version)
            print -r -- "hop $HOP_VERSION"
            return 0
            ;;
        -e|--edit)
            [[ -f "$HOPRC" ]] || _hop_seed_rc
            "${EDITOR:-vi}" "$HOPRC"
            return $?
            ;;
    esac

    if [[ ! -f "$HOPRC" ]]; then
        _hop_seed_rc || return 1
    fi

    records="$(_hop_parse)" || return 1

    if [[ "$1" == "-l" || "$1" == "--list" ]]; then
        print -r -- "$records" | awk -F'\t' -v home="$HOME" '{
            display_path=$2
            if (display_path == home) display_path="~"
            else if (index(display_path, home "/") == 1) display_path="~" substr(display_path, length(home) + 1)
            # Alias-less entries: name IS the path — printing both would
            # just duplicate the line.
            if ($1 == display_path)
                printf "  %s%s  depth=%s\n", display_path, ($3=="missing" ? "  [missing]" : ""), $4
            else
                printf "  %-22s %s%s  depth=%s\n", $1, display_path, ($3=="missing" ? "  [missing]" : ""), $4
        }'
        return 0
    fi

    if [[ "$1" == "-f" || "$1" == "--favorites" ]]; then
        if [[ -z "$records" ]]; then
            print -u2 "hop: no favorites yet — run hop and choose Settings / Add more folders"
            return 1
        fi
        # Forcing depth=0 makes _hop_index emit each bookmark and walk
        # nothing beneath it: the favorites list, nothing else.
        target="$(print -r -- "$records" \
            | awk 'BEGIN{FS=OFS="\t"} {$4=0; print}' \
            | _hop_index | _hop_rank | _hop_format \
            | _hop_pick '' 'favorites > ')" || return $?
        [[ -f "$target" ]] && target="${target:h}"
        if [[ ! -d "$target" ]]; then
            print -u2 "hop: $target no longer exists. Fix it with: hop -e"
            return 1
        fi
        cd "$target"
        return $?
    fi

    # Explicit browse mode: hop -b [path]. Enter jumps; Esc cancels. This
    # must run regardless of whether any bookmarks are configured yet, so
    # it is an `elif` against the first-run bootstrap below rather than a
    # separate `if` -- otherwise an empty/missing $HOPRC falls through into
    # bootstrap and clobbers the target -b already resolved.
    if [[ "$arg" == "-b" || "$arg" == "--browse" ]]; then
        local bbase="${2:-$PWD}"
        arg=''
        if [[ ! -d "$bbase" ]]; then
            print -u2 "hop: $bbase is not a directory"
            return 1
        fi
        target="$(_hop_browse "$bbase")" || return $?

    # First run: nothing bookmarked yet. Browse from the current directory
    # instead of erroring into a config file — Settings creates the first
    # bookmark, no hand-editing required. _hop_settings never writes to
    # stdout and only ever returns 1 (it exits solely via `|| return 1` when
    # the picker is cancelled), so its result is always "Esc was pressed" --
    # what happens next depends only on whether Settings saved something
    # before that Esc.
    elif [[ -z "$records" ]]; then
        print -u2 "hop: no bookmarks yet — Settings / Add more folders opens at $PWD"
        _hop_settings "$PWD"
        arg=''
        # Esc after saving things means "done curating" — fall through to
        # the search picker over the new favorites instead of forcing a
        # quit-and-rerun. Esc with nothing starred stays a plain cancel.
        records="$(_hop_parse)" || return 1
        [[ -z "$records" ]] && return 1
        print -u2 "hop: favorites saved — searching them now (Esc again to quit)"
        target=''
    fi

    # A trailing slash means "open the picker INSIDE this bookmark" rather than
    # jumping to it. Without it an exact alias jumps instantly, leaving no
    # picker to navigate in.
    if [[ -n "$arg" && "$arg" == */ ]]; then
        descend=1
        arg="${arg%/}"
    fi

    # Exact alias match jumps straight there, skipping the picker. The
    # expanded path also matches ($2): the shell turns `hop ~/Code` into
    # `hop /Users/you/Code` before hop sees it, so an alias-less bookmark
    # must be reachable by its absolute path as well as its ~ display name.
    if [[ -n "$arg" ]]; then
        target="$(print -r -- "$records" | awk -F'\t' -v a="$arg" '$1==a || $2==a {print $2; exit}')"
    fi

    if (( descend )) && [[ -n "$target" ]]; then
        if [[ ! -d "$target" ]]; then
            print -u2 "hop: $target no longer exists. Fix it with: hop -e"
            return 1
        fi
        target="$(_hop_browse "$target")" || return $?
    elif [[ -z "$target" ]]; then
        # No exact hit (or no argument): search the whole index, seeded with
        # the argument. Ctrl-T opens the single Settings flow for bookmarks --
        # this is the only _hop_pick call site that passes with_settings=1,
        # since it is the only caller that handles a return of 3.
        local rc_pick
        while true; do
            target="$(print -r -- "$records" | _hop_index | _hop_rank | _hop_format | _hop_pick "$arg" '' '' '' 1)"
            rc_pick=$?

            if (( rc_pick == 3 )); then
                _hop_settings "$PWD" || true
                records="$(_hop_parse)" || return 1
                target=''
                arg=''
                continue
            fi
            if (( rc_pick == 5 )); then
                # Tab at the top level: toggle the favorite, rebuild the
                # re-ranked list, and re-seed the query the user had typed.
                _hop_toggle_fav "${target#*$'\t'}"
                arg="${target%%$'\t'*}"
                records="$(_hop_parse)" || return 1
                target=''
                continue
            fi
            (( rc_pick == 0 )) && break
            (( rc_pick == 1 )) && return 1        # cancelled
            (( rc_pick != 0 )) && return $rc_pick
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
}

# Completion: offer aliases from the config file.
_hop_complete() {
    emulate -L zsh
    local -a aliases
    aliases=(${(f)"$(_hop_parse 2>/dev/null | cut -f1)"})
    compadd -- $aliases
}
compdef _hop_complete hop 2>/dev/null || true
