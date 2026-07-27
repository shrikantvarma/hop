# hop — design notes

Why the implementation looks the way it does. Useful if you're contributing;
not needed to use the tool.

## Hard constraint: this cannot be a script

A process receives a **copy** of its parent's working directory. `cd` inside a
script changes the child's cwd, and the child then exits and takes the change
with it. Changing the interactive shell's directory requires code running *in*
that shell, so `hop` is a shell **function**, sourced from `.zshrc`. This is the
same reason `zoxide`, `nvm`, and `autojump` ship shell functions rather than
plain binaries.

## Architecture

Units are split so that everything with non-trivial logic is testable without an
interactive terminal. Only `_hop_pick` needs a TTY, and it holds no logic beyond
loop control.

| Unit | Does | Pure? |
| --- | --- | --- |
| `_hop_parse` | `.hoprc` → `alias \t path \t (ok\|missing)` | yes |
| `_hop_children` | dir → immediate subdirs as `path \t name` | yes (reads fs) |
| `_hop_format` | records → `path \t display` picker lines | yes |
| `_hop_split_expect` | `fzf --expect` output → `key \t path` | yes |
| `_hop_pick` | picker loop over `path \t display` lines | no (TTY) |
| `hop` | orchestration; the only unit that calls `cd` | no |

`_hop_pick` consumes a neutral `path \t display` and knows nothing about the
`.hoprc` record format — `_hop_format` does that conversion. That narrower
interface is what lets the same picker serve both the bookmark list and a
`_hop_children` listing during descent.

## Five traps worth knowing

These each produced a real bug during development.

### 1. `print -r` does not interpret `\t`

`-r` means *raw*, which is what you want for paths (a path containing `\n`
shouldn't be mangled) but it also suppresses the tab separator, emitting a
literal backslash-t. Field lookups then silently return empty while the output
still *looks* plausible. Use `printf`, where the format string interprets `\t`
but `%s` arguments stay raw.

### 2. `[[:space:]]#` is a no-op without `extended_glob`

The `#` quantifier ("zero or more") only exists when `extended_glob` is set.
Without it the pattern is a literal `#`, so a trim like `${line##[[:space:]]#}`
does nothing at all — no error, just silence. `_hop_parse` uses regex matching
instead, which avoids depending on a global shell option.

### 3. Symlinks: `(/)` and bare `find` report empty directories

`find` does not follow symlinks by default, and zsh's `/` glob qualifier tests
the link rather than its target. A bookmark that is (or lives behind) a symlink
— common with iCloud, Dropbox, and Google Drive containers — then appears to
have no children, while ordinary directories work fine. The asymmetry makes it
read as a filesystem problem rather than a bug.

`_hop_children` uses `(-/N)`: `-` resolves symlinks before the type test, `/`
keeps directories, `N` yields nothing rather than erroring on no match. A
`find`-based reimplementation needs `-L`.

### 4. BSD sed does not interpret `\t` in replacements

GNU sed does, so `sed 's/^/dir\t/'` works on Linux and silently emits a
literal `t` on macOS — the records look plausible but field splitting breaks.
`_hop_index` tags its streams with `awk -v` instead.

### 5. `local path` shadows zsh's tied PATH array

Lowercase `path` is tied to `$PATH` in zsh. Declaring `local path` and
assigning a directory to it replaces the function's command-search path, so
the next external command fails with "command not found" — but only in
functions that call external commands after the assignment, which is why it
can lurk unnoticed. This codebase uses `p` for path-valued locals.

## Tilde expansion is anchored

Only a leading `~` is expanded. A global substitution would corrupt paths that
legitimately contain `~` — macOS iCloud containers are named things like
`iCloud~md~obsidian`, which a naive `${p//\~/$HOME}` turns into nonsense.

## Keybindings

`→`/`Tab` descend, `←`/`Shift-Tab` ascend, `Enter` accepts. Binding the arrows
is safe because fzf aliases them to `ctrl-f`/`ctrl-b` (`forward-char` /
`backward-char`), which remain available for moving the cursor inside the query.

Descent pushes the previous list and prompt onto parallel stacks, so backing out
restores exactly what was on screen. Descending into a directory with no
subdirectories is a no-op rather than an error. `cd` happens only on `Enter`, so
browsing never moves the shell.

## The trailing slash

Instant-jump and drill-down collide: `hop notes` jumps immediately, leaving no
picker to descend from — precisely on the bookmarks most worth descending into.
`hop notes/` resolves the alias and opens the picker on its children instead.

Degradation is deliberate: a trailing slash on a non-alias falls through to a
plain query; a trailing slash on a childless directory reports
`<name> has no subdirectories` and exits 1 rather than opening an empty picker.

## Error handling

| Condition | Behavior |
| --- | --- |
| `.hoprc` absent | Seed a commented template, tell the user, continue |
| Path does not exist | Listed as `[missing]`; `cd` refuses |
| fzf not installed | Named error with a link, not a broken pipe |
| Malformed line | Skipped; `hoprc:<lineno>: malformed` on stderr |
| Picker cancelled | Exit non-zero, cwd unchanged |

Dead bookmarks are shown rather than silently dropped — silent dropping is how a
user edits `.hoprc` and then wonders why the entry never appears.

## Testing

`zsh test_hop.zsh` — 103 assertions over the pure units, including descent
through a symlinked parent, per-bookmark index depth, favorite round-trips that
must restore the config byte-for-byte, paths containing spaces, paths
containing literal `~` characters, and every `--expect` key.

The fzf loop is hand-verified. Driving it under a pty was attempted and
abandoned: fzf reads keys from `/dev/tty` while its list arrives on stdin, and
the two cannot be fed reliably from a non-interactive harness.

## Deliberately out of scope

Opening files, frecency/usage tracking, content search (grep inside files),
caching, and multi-select. Bookmarks are curated (by hand or via Ctrl-S), never
auto-discovered; the action is `cd` only.
