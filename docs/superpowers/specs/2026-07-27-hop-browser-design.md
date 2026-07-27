# hop v0.2 — browser design

**Date:** 2026-07-27
**Status:** Approved, not yet implemented
**Supersedes:** parts of `DESIGN.md` (v0.1 bookmark jumper)

## Problem

v0.1 lists only bookmarked directories and their subdirectories. Two gaps:

1. **Directories that contain only files are dead ends.** `Obsidian/context/` holds
   five markdown files and no subdirectories, so descending into it shows an empty
   list. Same for `Daily Notes/` (28 files, 0 dirs).
2. **Reaching a known item requires knowing where it lives.** There is no way to type
   `goals` and find `context/goals.md`; you must navigate to it.

The user also wants to add favorites without leaving the picker.

## Measurements

Taken 2026-07-27 against the live `.jumprc` (21 bookmarks).

| | |
| --- | --- |
| Total items, all bookmarks, depth 3 | 8,596 (2,662 dirs / 5,934 files) |
| Full index scan, three largest trees | 41 ms |

Scanning is cheap enough to rebuild the index on every invocation. **No cache** — and
therefore no staleness, no invalidation logic, no `--refresh` flag.

Composition is the real constraint:

| bookmark | dirs | files |
| --- | --- | --- |
| `claude` (`~/.claude`) | 820 | 2,294 |
| `code` (`~/Code`) | 767 | 1,322 |
| all 19 others | 1,075 | 2,318 |

Two bookmarks contribute 60% of the index and near-zero search value — nobody
fuzzy-searches for `plugins/cache/**/SKILL.md`. Indexing every bookmark uniformly
would bury `context/goals.md` under thousands of irrelevant paths. Bookmarks have
different roles: some are jump targets, some are search corpora. The config must
express that.

## Design

### Config format

`~/.hoprc` gains an optional third column: the depth to index beneath that bookmark.

```
# alias      path                                       depth
code         ~/Code                                     0
claude       ~/.claude                                  0
context      ~/Digital_Brain/Obsidian/context           3
db           ~/Digital_Brain/Obsidian/DB                2
daily        ~/Digital_Brain/Obsidian/Daily Notes       1
```

- `0` — jump target only; never appears in the index beyond itself.
- Omitted — defaults to `2`.
- Existing two-column files remain valid, so v0.1 configs keep working.

**Every `.hoprc` entry is a favorite** and renders with a `★`. There is no separate
favorites file and no second concept to learn: the bookmark list *is* the favorites
list. Items discovered by indexing are unmarked until favorited.

### Index

For each bookmark with depth > 0, walk to that depth and emit both directories and
files, filtered through `_HOP_SKIP`. Combined with the bookmark entries themselves,
this produces the candidate list.

Record format grows to carry what ranking needs:

```
kind \t path \t display \t fav \t depth
```

`kind` is `dir` or `file`; `fav` is `1` for `.hoprc` entries, `0` otherwise; `depth`
is the record's distance below its bookmark root, where the bookmark itself is `0`.

Note the two senses of zero, which are consistent but easy to conflate: the *config*
column `0` means "index nothing beneath this bookmark", which yields exactly one
record — the bookmark itself, at record depth `0`. A bookmark is always present in the
candidate list regardless of its configured depth.

### Ranking

Emission order, since fzf preserves input order for equal match scores:

1. Favorites (`fav=1`) first
2. Then ascending `depth` — shallower before deeper
3. Then alphabetical by path

So `context/goals.md` (favorited or depth 1) outranks
`Code/nutrition/src/lib/goals.py` (depth 3) for the query `goals`.

### Actions

| Key | Action |
| --- | --- |
| `Enter` | `cd` to the item — for a **file**, to its containing directory |
| `→` / `Tab` | descend into the highlighted directory |
| `←` / `Shift-Tab` | back out one level |
| `Ctrl-S` | toggle favorite on the highlighted item |
| `Esc` | cancel; shell does not move |

**Files are never opened.** Enter on a file lands in its parent directory. This was an
explicit scope decision — opening introduces per-filetype rules and, for this user's
Obsidian vault, `obsidian://` URI construction. Deferred until the navigation case has
been used enough to justify it.

`Ctrl-S` is chosen because fzf leaves it unbound; `Ctrl-F`/`Ctrl-B` must stay free as
they are the non-arrow bindings for cursor movement within the query.

### Favoriting

`Ctrl-S` on an unfavorited item appends a line to `~/.hoprc`; on a favorited item,
removes its line. The alias is derived from the basename: lowercased, spaces and dots
to hyphens, collisions suffixed `-2`, `-3`. Favoriting a **file** stores the file's
own path — it ranks first and `Enter` still lands in its parent directory.

Rewrites preserve comments and ordering: append at end, remove by exact path match.
The file remains hand-editable, which is the point.

## Architecture

Additions to the v0.1 unit list. Every new unit is pure and testable without a TTY.

| Unit | Does | New? |
| --- | --- | --- |
| `_hop_parse` | `.hoprc` → `alias \t path \t status \t depth` | extended |
| `_hop_index` | bookmarks → full candidate records | **new** |
| `_hop_rank` | candidate records → emission order | **new** |
| `_hop_fav_add` | append a bookmark to `.hoprc` | **new** |
| `_hop_fav_remove` | remove a bookmark from `.hoprc` by path | **new** |
| `_hop_alias_for` | path → unique alias | **new** |
| `_hop_children` | dir → immediate children (now files too) | extended |
| `_hop_format` | records → `path \t display` picker lines | extended |
| `_hop_split_expect` | fzf `--expect` output → `key \t path` | unchanged |
| `_hop_pick` | picker loop | extended (Ctrl-S) |
| `hop` | orchestration; only unit that calls `cd` | extended |

`_hop_pick` continues to consume a neutral `path \t display`, so it stays ignorant of
records, favorites, and ranking.

## Error handling

Inherits v0.1 behavior. New cases:

| Condition | Behavior |
| --- | --- |
| `.hoprc` not writable on `Ctrl-S` | Warn on stderr, picker stays open, no crash |
| Favorite already present | `Ctrl-S` removes it (toggle), does not duplicate |
| Alias collision on add | Suffix `-2`, `-3`, … |
| Depth column non-numeric | Treat as default 2, warn with line number |
| Bookmark path missing | Excluded from the index; still listed `[missing]` |

## Testing

Extends `test_hop.zsh`. New assertions cover:

- depth column parsing: present, absent (defaults to 2), `0`, non-numeric
- backward compatibility: a v0.1 two-column file parses unchanged
- `_hop_index` includes files, respects per-bookmark depth, honours `_HOP_SKIP`,
  and emits nothing for depth `0`
- `_hop_rank` puts favorites first, then shallower, then alphabetical
- `_hop_alias_for` derivation and collision suffixing
- `_hop_fav_add` / `_hop_fav_remove` round-trip while preserving comments
- `_hop_split_expect` handles `ctrl-s`

The fzf loop stays hand-verified.

## Risks

- **Code roughly doubles** (~200 → ~400 lines). Still one file, still small, but no
  longer a script you read in one sitting.
- **`.hoprc` is now written by the program**, not only by hand. The remove-by-path
  rewrite is the most dangerous operation in the tool; it must never lose user
  comments or unrelated lines. Covered by round-trip tests.
- **Ranking is heuristic.** Favorites-then-depth is a guess at intent. If it feels
  wrong in use, the fix is to change emission order in `_hop_rank` only.

## Out of scope

Opening files, frecency/usage tracking, content search (grep inside files), caching,
and multi-select. Each is separable and none is needed to close the two gaps above.
