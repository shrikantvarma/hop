#!/usr/bin/env zsh
# Builds a throwaway $HOME for recording demos, so that no real paths, folder
# names, or account name can appear on screen. The .tape files run this first,
# then start a shell with HOME pointed at it.
#
#   zsh demo/sandbox.zsh saved   # two folders already bookmarked
#   zsh demo/sandbox.zsh fresh   # nothing bookmarked yet (first-run flow)
#
# The sandbox sits at a fixed, account-free path because hop prints $HOPRC and
# $PWD in full on first run — a path under the real home would leak into frame.

set -e

mode="${1:-saved}"
sandbox="/private/tmp/demo"

if [[ ! -f hop.plugin.zsh ]]; then
    print -u2 "sandbox.zsh: run this from the repository root"
    exit 1
fi

rm -rf "$sandbox"
mkdir -p "$sandbox"
cp -R demo/Code demo/Obsidian "$sandbox/"

if [[ "$mode" == saved ]]; then
    cat > "$sandbox/.hoprc" <<'EOF'
# ~/.hoprc — bookmarks for `hop`
code       ~/Code       depth=3
obsidian   ~/Obsidian   depth=3
EOF
fi
