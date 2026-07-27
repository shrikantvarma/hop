# hop

**Bookmark a few directories. Search everything inside them.**

Bookmark the directories you care about, fuzzy-find them, then press `→` to step
*into* one and keep going. Bookmark the trunk, browse the branches.

```
$ hop
▌ notes        ~/Notes
  code         ~/Code
  vault        ~/Notes/Vault

  → descend into notes

▌ Projects
  Assets
  Archive

  → descend into Projects

▌ 2026-Q3
  2026-Q2
  Ideas

  ⏎  →  cd ~/Notes/Projects/2026-Q3
```

Bookmarking every leaf directory doesn't scale, and history-based jumpers can't
reach a directory you've never visited. `hop` bookmarks the few directories worth
naming and lets you navigate down from there.

> **Demo:** _(recording to be added)_

## Requirements

- **zsh** — bash is not supported today; the implementation leans on zsh glob
  qualifiers and regex matching. PRs welcome.
- **[fzf](https://github.com/junegunn/fzf)**

## Install

`hop` must be **sourced**, not executed — `cd` only affects the shell it runs in.

<details open>
<summary><b>Manual</b></summary>

```sh
git clone https://github.com/shrikantvarma/hop.git ~/.hop
echo 'source ~/.hop/hop.plugin.zsh' >> ~/.zshrc
exec zsh
```
</details>

<details>
<summary><b>Plugin managers</b></summary>

```sh
# antidote / antigen
shrikantvarma/hop

# zinit
zinit light shrikantvarma/hop

# oh-my-zsh
git clone https://github.com/shrikantvarma/hop.git \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/hop
# then add `hop` to plugins=(...) in ~/.zshrc
```
</details>

## Bookmarks

Bookmarks live in `~/.hoprc`, one per line: an alias, whitespace, a path.
Run `hop -e` to open it (the file is created on first run).

```sh
# ~/.hoprc
code      ~/Code
notes     ~/Documents/Notes
vault     ~/Documents/Notes/Vault
daily     ~/Documents/Daily Notes     # spaces in paths are fine
dotfiles  ~/.config                   # ~ expands
```

`#` starts a comment. Malformed lines are skipped with a line number on stderr.
Bookmarks whose path no longer exists are shown as `[missing]` rather than
silently dropped, so a typo is visible instead of mysterious.

## Usage

```sh
hop                # search everything in your bookmarked trees
hop goals          # jump to the best match for "goals"
hop notes          # exact alias -> jump immediately, no picker
hop notes/         # open the picker INSIDE ~/Documents/Notes
hop -l             # list bookmarks
hop -e             # edit ~/.hoprc
hop -h             # help
```

You don't have to remember aliases. The picker searches the whole line including
the full path, so typing a real directory name finds it.

### Keys in the picker

| Key | Action |
| --- | --- |
| `Enter` | cd to the highlighted directory |
| `→` or `Tab` | descend into it |
| `←` or `Shift-Tab` | back out one level |
| `Ctrl-S` | favorite / unfavorite the highlighted item |
| `Ctrl-F` / `Ctrl-B` | move the cursor within the query |
| `Esc` | cancel, shell stays put |

`cd` happens only on `Enter` — wandering the tree never moves your shell.
`Enter` on a **file** lands in the file's directory; hop never opens files.

### Why `hop <alias>/`

An exact alias jumps instantly, which leaves no picker to descend from. The
trailing slash says "open the picker here instead": `hop notes/` lands you in
the list of `~/Documents/Notes`'s subdirectories.

### Search depth

Bookmarks are searched two levels deep by default. Change it per bookmark:

```sh
code      ~/Code       depth=0    # jump target only, never searched
notes     ~/Notes      depth=3    # searched deeply
```

`depth=0` is for large trees you only ever `cd` into — without it, thousands of
`node_modules` and plugin files crowd out the handful of notes you actually
search for.

### Favorites

Everything in `~/.hoprc` is a favorite: it shows `★` and ranks above every
indexed result. Press `Ctrl-S` in the picker to add or remove one. `hop` writes
the change to `~/.hoprc` and leaves your comments and formatting alone.

## Configuration

Set these **before** sourcing the plugin.

| Variable | Default | Purpose |
| --- | --- | --- |
| `HOPRC` | `~/.hoprc` | Bookmarks file location |
| `HOP_FZF_OPTS` | _(empty)_ | Extra options passed to fzf |
| `_HOP_SKIP` | see below | Array of directory names hidden when descending |

```sh
HOP_FZF_OPTS='--height=80% --border=rounded'
_HOP_SKIP=(.git node_modules .venv)
source ~/.hop/hop.plugin.zsh
```

`_HOP_SKIP` defaults to common noise: `.git`, `node_modules`, `__pycache__`,
`.venv`, `dist`, `build`, `target`, and similar. It is a denylist rather than
"hide all dotfiles", so directories like `~/.config/nvim` stay reachable.

### Prefer a shorter command?

```sh
alias j=hop
```

If you also use [autojump](https://github.com/wting/autojump), note that it
binds `j` too — pick a different alias.

## Notes

**Symlinked bookmarks work.** Descending resolves symlinks before testing for
directory-ness, so bookmarks pointing into iCloud, Dropbox, or Google Drive
containers list their contents correctly. (A naive implementation using `find`
without `-L` reports them as empty.)

**Paths containing `~` are safe.** Tilde expansion is anchored to the first
character only, so macOS iCloud container names like `iCloud~md~obsidian`
survive intact.

## Tests

```sh
zsh test_hop.zsh
```

90 assertions covering config parsing, indexing, ranking, alias derivation,
config rewriting (byte-for-byte round-trip), and key handling — including
listing through symlinks. The fzf picker itself is interactive and is
verified by hand.

## License

MIT — see [LICENSE](LICENSE).
