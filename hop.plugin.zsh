# hop — curated directory bookmarks you can walk into
# https://github.com/shrikantvarma/hop
#
# Must be SOURCED, not executed. A process gets a *copy* of its parent's
# working directory, so `cd` inside a script dies with the script. Changing the
# interactive shell's directory requires code running in that shell.

typeset -g HOP_VERSION="0.1.0"

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

# ---------------------------------------------------------------------------
# _hop_parse — pure text transform, no side effects
#
# Reads $HOPRC (or $1), writes one record per valid entry:
#     alias \t path \t (ok|missing)
# Malformed lines are skipped and reported to stderr with a line number.
# ---------------------------------------------------------------------------
_hop_parse() {
    emulate -L zsh

    local rc="${1:-$HOPRC}"
    local line name path lineno=0

    [[ -r "$rc" ]] || { print -u2 "hop: cannot read $rc"; return 1 }

    while IFS= read -r line || [[ -n "$line" ]]; do
        (( lineno++ ))

        line="${line%%'#'*}"                          # strip comments
        [[ "$line" == *[^[:space:]]* ]] || continue   # blank / whitespace only

        # Split on the first whitespace run. The trailing [^[:space:]] anchors
        # the greedy .* so trailing whitespace is excluded, while spaces INSIDE
        # the path are preserved.
        if [[ ! "$line" =~ '^[[:space:]]*([^[:space:]]+)[[:space:]]+(.*[^[:space:]])[[:space:]]*$' ]]; then
            print -u2 "hop: $rc:$lineno: malformed (no path) -- skipped"
            continue
        fi
        name="$match[1]"
        path="$match[2]"

        # Expand a leading ~ ONLY, anchored to position 0. A global substitution
        # would corrupt paths that legitimately contain ~, such as macOS iCloud
        # container names like `iCloud~md~obsidian`.
        if [[ "$path" == "~" ]]; then
            path="$HOME"
        elif [[ "$path" == "~/"* ]]; then
            path="$HOME/${path#\~/}"
        fi

        # printf, not `print -r`: -r suppresses escape interpretation, which
        # would emit a literal backslash-t instead of a tab separator.
        if [[ -d "$path" ]]; then
            printf '%s\t%s\t%s\n' "$name" "$path" "ok"
        else
            printf '%s\t%s\t%s\n' "$name" "$path" "missing"
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

    for child in "$parent"/*(-/N) "$parent"/.*(-/N); do
        name="${child:t}"
        [[ "$name" == "." || "$name" == ".." ]] && continue
        (( ${_HOP_SKIP[(Ie)$name]} )) && continue
        printf '%s\t%s\n' "$child" "$name"
    done
}

# ---------------------------------------------------------------------------
# _hop_split_expect — parse `fzf --expect` output into `key \t path`
#
# fzf emits the pressed key on line 1 (EMPTY for plain Enter) and the selected
# record on line 2. Pure string handling, split out so it is testable without a
# terminal.
# ---------------------------------------------------------------------------
_hop_split_expect() {
    emulate -L zsh
    local out="$1" key sel
    key="${out%%$'\n'*}"
    sel="${out#*$'\n'}"
    sel="${sel%%$'\t'*}"          # field 1 is the real path
    printf '%s\t%s\n' "$key" "$sel"
}

# ---------------------------------------------------------------------------
# _hop_format — 3-field records -> `path \t display` picker lines
# ---------------------------------------------------------------------------
_hop_format() {
    awk -F'\t' '{
        mark = ($3 == "missing") ? "  [missing]" : ""
        printf "%s\t%-22s %s%s\n", $2, $1, $2, mark
    }'
}

# ---------------------------------------------------------------------------
# _hop_pick — consume `path \t display` lines on stdin, emit one chosen path
#
#   $1  initial query   $2  initial prompt
#
# Loops so the list can be replaced in place:
#   → or Tab      descend into the highlighted directory
#   ← or S-Tab    back out one level
#   Enter         accept
#
# Binding the arrows is safe because fzf aliases them to ctrl-f / ctrl-b
# (forward-char / backward-char), which remain available for moving the cursor
# inside the query.
# ---------------------------------------------------------------------------
_hop_pick() {
    emulate -L zsh

    local query="$1"
    local lines out key sel kids prompt="${2:-hop > }"
    local -a stack_lines stack_prompt

    if ! command -v fzf >/dev/null 2>&1; then
        print -u2 "hop: fzf is not installed -- see https://github.com/junegunn/fzf"
        return 127
    fi

    lines="$(cat)"

    while true; do
        out="$(print -r -- "$lines" | fzf \
              --delimiter=$'\t' \
              --with-nth=2 \
              --query="$query" \
              --height=60% \
              --reverse \
              --border \
              --prompt="$prompt" \
              --expect=right,left,tab,btab \
              --preview='ls -1p {1} 2>/dev/null | head -40' \
              --preview-window='right:45%:wrap' \
              --header='Enter hop   →/Tab descend   ←/S-Tab up   (^F ^B move cursor)' \
              ${=HOP_FZF_OPTS})" || return 1

        out="$(_hop_split_expect "$out")"
        key="${out%%$'\t'*}"
        sel="${out#*$'\t'}"
        query=''                       # don't re-seed after the first round

        case "$key" in
            right|tab)
                kids="$(_hop_children "$sel")"
                if [[ -n "$kids" ]]; then
                    stack_lines+=("$lines")
                    stack_prompt+=("$prompt")
                    lines="$kids"
                    prompt="${sel:t}/ > "
                fi
                ;;
            left|btab)
                if (( ${#stack_lines} )); then
                    lines="${stack_lines[-1]}"
                    prompt="${stack_prompt[-1]}"
                    shift -p stack_lines
                    shift -p stack_prompt
                fi
                ;;
            *)                         # Enter
                print -r -- "$sel"
                return 0
                ;;
        esac
    done
}

# ---------------------------------------------------------------------------
# _hop_seed_rc — write a commented starter file. Does NOT scan the disk.
# ---------------------------------------------------------------------------
_hop_seed_rc() {
    cat > "$HOPRC" <<'EOF'
# ~/.hoprc — bookmarks for `hop`
#
#   alias<whitespace>path
#
# A leading ~ expands to $HOME. Paths may contain spaces. `#` starts a comment.

# code    ~/Code
# notes   ~/Documents/Notes
EOF
    print -u2 "hop: created $HOPRC — add bookmarks with: hop -e"
    return 0
}

# ---------------------------------------------------------------------------
# hop — orchestration; the only unit that calls cd
# ---------------------------------------------------------------------------
hop() {
    local records target arg="$1" descend=0 kids

    case "$1" in
        -h|--help)
            print -r -- "hop $HOP_VERSION — curated directory bookmarks you can walk into"
            print -r -- ""
            print -r -- "usage: hop                 pick from all bookmarks"
            print -r -- "       hop <text>          pick, pre-filtered by <text>"
            print -r -- "       hop <alias>         jump straight there (exact alias only)"
            print -r -- "       hop <alias>/        open the picker INSIDE that bookmark"
            print -r -- "       hop -l | --list     list bookmarks"
            print -r -- "       hop -e | --edit     edit $HOPRC"
            print -r -- "       hop -v | --version  print version"
            print -r -- ""
            print -r -- "in the picker:  Enter hop   →/Tab descend   ←/S-Tab up"
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
    if [[ -z "$records" ]]; then
        print -u2 "hop: no bookmarks in $HOPRC. Add some with: hop -e"
        return 1
    fi

    if [[ "$1" == "-l" || "$1" == "--list" ]]; then
        print -r -- "$records" | awk -F'\t' '{
            printf "  %-22s %s%s\n", $1, $2, ($3=="missing" ? "  [missing]" : "")
        }'
        return 0
    fi

    # A trailing slash means "open the picker INSIDE this bookmark" rather than
    # jumping to it. Without it an exact alias jumps instantly, leaving no
    # picker to press Tab in.
    if [[ -n "$arg" && "$arg" == */ ]]; then
        descend=1
        arg="${arg%/}"
    fi

    # Exact alias match jumps straight there, skipping the picker.
    if [[ -n "$arg" ]]; then
        target="$(print -r -- "$records" | awk -F'\t' -v a="$arg" '$1==a {print $2; exit}')"
    fi

    if (( descend )) && [[ -n "$target" ]]; then
        if [[ ! -d "$target" ]]; then
            print -u2 "hop: $target no longer exists. Fix it with: hop -e"
            return 1
        fi
        kids="$(_hop_children "$target")"
        if [[ -z "$kids" ]]; then
            print -u2 "hop: ${target:t} has no subdirectories"
            return 1
        fi
        target="$(print -r -- "$kids" | _hop_pick '' "${target:t}/ > ")" || return $?
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
}

# Completion: offer aliases from the config file.
_hop_complete() {
    local -a aliases
    aliases=(${(f)"$(_hop_parse 2>/dev/null | cut -f1)"})
    compadd -- $aliases
}
compdef _hop_complete hop 2>/dev/null || true
