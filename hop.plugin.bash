# hop for bash: runs the zsh plugin in a child zsh, then cd's here to wherever it landed.
hop() {
    local out dest rc
    out=$(mktemp) || return
    HOP_OUT=$out zsh -c '
        source ~/.hop/hop.plugin.zsh
        cd -- "$1"; shift
        hop "$@"; rc=$?
        print -r -- "$PWD" > "$HOP_OUT"
        exit $rc' _ "$PWD" "$@"
    rc=$?
    dest=$(<"$out"); rm -f "$out"
    [[ -n $dest && $dest != "$PWD" ]] && builtin cd -- "$dest"
    return $rc
}
