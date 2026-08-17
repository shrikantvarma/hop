# hop

**A folder navigator for your terminal: discover files and folders, favorite
the ones you care about, and control how deep each one is searched.**

`hop` is a zsh and [fzf](https://github.com/junegunn/fzf) plugin for jumping
between directories. Bookmark a few useful folders, fuzzy-search inside them,
and browse their contents interactively — without memorising paths or filling
your history with every directory you visit. Each favorite gets its own search
depth, so a huge folder stays shallow while your projects folder is searched
all the way down.




[![hop terminal demo](assets/hop-recording-zoom.gif)](https://github.com/shrikantvarma/hop/raw/refs/heads/main/assets/hop.mov)

## Install

You need [zsh](https://www.zsh.org/) and [fzf](https://github.com/junegunn/fzf).

```sh
git clone https://github.com/shrikantvarma/hop.git ~/.hop
echo 'source ~/.hop/hop.plugin.zsh' >> ~/.zshrc
source ~/.zshrc
```



## Your first minute

Run `hop`.

```sh
hop
```

On your first run, hop opens Settings at your current directory.

1. Choose **Add more folders**.
2. Use `→` to open a folder and `←` to go back.
3. Press `Space` on a folder to save it — star as many as you like.
4. Press `Enter` or `Esc` when you're done.

Saved folders appear first in future searches and are marked with `★`.

## Everyday use

Run `hop`, type a few letters, then press `Enter` to move there.

```sh
hop                 # search saved folders and their contents
hop notes           # jump straight to the saved alias "notes"
hop notes/          # browse inside the saved folder "notes"
hop -b ~/Code       # browse a folder without saving it
hop -l              # list saved folders
hop -e              # edit the saved-folder file directly
```

In the picker:

| Key | What it does |
| --- | --- |
| `Enter` | Move to the selected folder |
| `→` | Open the selected folder |
| `←` | Go back one folder |
| `Tab` | Save or unsave the selected folder (★) |
| `?` | Open Settings / Add more folders |
| `Esc` | Close hop and stay where you are |

One key per verb, everywhere: `Enter` always means *go*, `Tab` (or `Space`,
on screens where you aren't typing a search) always means *star/unstar*, and
`Esc` always means *back*.

If the selected item is a file, hop moves to the file’s parent folder. It never
opens files.

## Add folders and set search depth

The quickest way to save a folder is `Tab` on any search result. For
everything else, press `?` from the main picker to open Settings.

- **Add more folders** lets you browse from your current directory; `Space`
  (or `Tab`) stars or unstars the highlighted folder without moving you,
  `Enter` or `Esc` when you're done.
- **Saved folders & search depth** shows every saved folder with its path and
  `depth=N` value, so folders with the same name are easy to tell apart.
  `Enter` changes a folder's depth (`0` through `6`); `Space` unstars it.

Depth controls how far below a saved folder hop searches. `depth=0` includes
only the saved folder. `depth=2`—the default—also searches two levels beneath
it. Choose a lower depth for very large folders to keep results focused.

## Saved folders

Your saved folders live in `~/.hoprc`. You can manage them in Settings or edit
the file with `hop -e`.

```text
# folder (with an optional alias in front)   optional search depth
~/Clients/Acme/Code                           depth=1
~/Documents/Notes                             depth=3
dotfiles    ~/.config                         depth=0
```

Folders saved through Settings are stored as their path — no invented name to
learn. Every part of the path is searchable, so typing `acme` or `code` finds
`~/Clients/Acme/Code`. Add an alias in front of a path (like `dotfiles` above)
when you want a short jump token: `hop dotfiles` goes straight there. Aliases
may not begin with `~` or `/` — that's how hop tells the two forms apart.
Comments and paths containing spaces are supported.

## Optional configuration

Set options before sourcing `hop.plugin.zsh` in your `.zshrc`.

```sh
# Store saved folders somewhere else.
HOPRC="$HOME/.config/hop/bookmarks"

# Pass extra options to fzf. Search is case-insensitive by default;
# add +i here to restore fzf's smart-case behavior.
HOP_FZF_OPTS='--height=80% --border=rounded'
# HOP_FZF_OPTS is word-split on whitespace, so a value with embedded spaces
# (e.g. a --header) needs its own quoting layer, or should be left out.

# Change the default for entries without depth=N.
HOP_DEFAULT_DEPTH=2

source ~/.hop/hop.plugin.zsh
```

Hop skips common noisy folders such as `.git`, `node_modules`, `.venv`, and
`dist` while browsing. Add your own names before sourcing the plugin:

```sh
_HOP_SKIP=(.git node_modules .venv vendor)
```

## Plugin managers

```sh
# antidote / antigen
shrikantvarma/hop

# zinit
zinit light shrikantvarma/hop
```

For oh-my-zsh, clone the repository into its custom plugins directory, then add
`hop` to your `plugins=(...)` list.

```sh
git clone https://github.com/shrikantvarma/hop.git \
  ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/hop
```

## How hop compares to zoxide, z, and autojump

Tools like [zoxide](https://github.com/ajeetdsouza/zoxide),
[z](https://github.com/rupa/z), and autojump are *frecency* jumpers: they watch
every `cd`, score directories by how often and how recently you visit them, and
jump to the best match. That works well, but the ranking shifts as your habits
do, and one-off deep dives pollute the database.

`hop` is deliberate instead of statistical. You bookmark a handful of folders
once; searches cover exactly those folders and their contents to a depth you
set. Results are the same every time, nothing tracks your shell history, and
`→`/`←` let you browse when you don't remember a name at all.

|  | hop | zoxide / z / autojump | fzf `Alt-C` |
| --- | --- | --- | --- |
| Jump source | folders you saved | learned from `cd` history | everything under the current directory |
| Ranking | fixed, saved folders first | frecency score | none |
| Browse with preview | yes (`→`/`←`) | no | no |
| Setup beyond install | save a few folders | none | none |

They compose fine: many people keep a frecency jumper for "everywhere" and use
`hop` for the dozen folders they actually live in.

## Development

Run the test suite with:

```sh
zsh test_hop.zsh
```

The suite currently has 126 checks for parsing, indexing, ranking, saved-folder
updates, symlink handling, and picker wiring.

## License

[MIT](LICENSE)
