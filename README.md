# hop

**A small, fast way to move between the folders you care about.**

`hop` is a zsh and [fzf](https://github.com/junegunn/fzf) plugin. Save a few
useful folders, search inside them, and move through their contents without
memorising paths or filling your history with every directory you visit.

> ▶ **[Watch the full terminal demo (MOV, 1.4 MB)](https://github.com/shrikantvarma/hop/raw/refs/heads/main/assets/hop.mov)**
>
> On GitHub, MOV files open or download as a separate file rather than playing
> inline in the README.

[![hop terminal demo](assets/hop-demo.gif)](https://github.com/shrikantvarma/hop/raw/refs/heads/main/assets/hop.mov)

## Install

You need [zsh](https://www.zsh.org/) and [fzf](https://github.com/junegunn/fzf).

```sh
git clone https://github.com/shrikantvarma/hop.git ~/.hop
echo 'source ~/.hop/hop.plugin.zsh' >> ~/.zshrc
source ~/.zshrc
```

`hop` must be sourced, rather than executed, so it can change your current
shell directory.

## Your first minute

Run `hop`.

```sh
hop
```

On your first run, hop opens Settings at your current directory.

1. Choose **Add more folders**.
2. Use `→` to open a folder and `←` to go back.
3. Press `Enter` on a folder to save it.
4. Press `Esc` to return to search.

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
| `Ctrl-T` | Open Settings / Add more folders |
| `Esc` | Close hop and stay where you are |

If the selected item is a file, hop moves to the file’s parent folder. It never
opens files.

## Add folders and set search depth

Press `Ctrl-T` from the main picker to open Settings.

- **Add more folders** lets you browse from your current directory and save or
  remove folders.
- **Saved folders & search depth** shows every saved folder and its current
  `depth=N` value.
- Select a saved folder to change its depth (`0` through `6`) or remove it.

Depth controls how far below a saved folder hop searches. `depth=0` includes
only the saved folder. `depth=2`—the default—also searches two levels beneath
it. Choose a lower depth for very large folders to keep results focused.

## Saved folders

Your saved folders live in `~/.hoprc`. You can manage them in Settings or edit
the file with `hop -e`.

```text
# alias    folder                         optional search depth
code        ~/Code                         depth=1
notes       ~/Documents/Notes              depth=3
dotfiles    ~/.config                      depth=0
```

Aliases are optional to remember: the picker also searches folder names and
full paths. Comments and paths containing spaces are supported.

## Optional configuration

Set options before sourcing `hop.plugin.zsh` in your `.zshrc`.

```sh
# Store saved folders somewhere else.
HOPRC="$HOME/.config/hop/bookmarks"

# Pass extra options to fzf.
HOP_FZF_OPTS='--height=80% --border=rounded'

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

## Development

Run the test suite with:

```sh
zsh test_hop.zsh
```

The suite currently has 108 checks for parsing, indexing, ranking, saved-folder
updates, symlink handling, and picker wiring.

## License

[MIT](LICENSE)
