# hop — handoff state

**Written:** 2026-07-27
**Purpose:** Let a fresh session (GSD or otherwise) resume with zero prior context.
**Read next:** `docs/superpowers/plans/2026-07-27-hop-browser.md` — the plan being executed.

---

## What hop is

A zsh function that fuzzy-finds bookmarked directories with fzf and lets you press
`→`/`Tab` to descend *into* one and keep browsing. `cd` only — it never opens files.

Two versions exist and they are **not** the same file. This is the single most
important thing to understand before touching anything.

| | Live daily driver | The repo |
| --- | --- | --- |
| Path | `~/.config/jump/jump.zsh` | `~/Code/hop/` |
| Command | `j` | `hop` |
| Config | `~/.jumprc` (33 lines, 21 bookmarks) | `~/.hoprc` |
| Sourced from | `~/.zshrc` (last line) | not installed |
| Version | v0.1 + arrow keys | v0.1 on `main`, v0.2 in progress |
| Tests | 25 passing | 27 on `main`, 37 on `browser` |

The user uses `j` every day. **Do not break `~/.config/jump/` or `~/.zshrc`.** The repo
is a separate packaging effort intended for GitHub. They will be reconciled eventually
— that decision is still open (see Open Decisions).

## Git state

```
~/Code/hop                     main     5668c39   clean
~/Code/hop/.worktrees/browser  browser  5668c39   UNCOMMITTED WORK — see below
```

`main` has two commits:
- `90a22d4` feat: hop v0.1 — curated directory bookmarks you can walk into
- `5668c39` chore: ignore .worktrees/

**The `browser` worktree has uncommitted work that is not backed up anywhere.**

```
 M .gitignore
 M docs/superpowers/specs/2026-07-27-hop-browser-design.md
 M hop.plugin.zsh
 M test_hop.zsh
?? docs/superpowers/plans/
```

+94 / −19 across 4 files. **Commit this before doing anything else** — a
`git clean -fdx`, a branch switch, or an accidental checkout loses Task 1 and the plan.

```sh
git -C ~/Code/hop/.worktrees/browser add -A
git -C ~/Code/hop/.worktrees/browser commit -m "feat: parse optional depth= token in .hoprc

Co-Authored-By: Claude Opus 5 (1M context) <noreply@anthropic.com>
Claude-Session: https://claude.ai/code/session_01SWYKAEcegMgeSpq9dBwr8M"
```

## Where the work stopped

Executing a 9-task plan to turn hop from a bookmark jumper into a browser.

| Task | State |
| --- | --- |
| 1. Parse `depth=N` token | **Code done, tests pass (37/0), NOT COMMITTED** |
| 2. List files alongside dirs | not started |
| 3. `_hop_index` — walk bookmarked trees | not started |
| 4. `_hop_rank` — favorites first, then depth | not started |
| 5. `_hop_alias_for` — derive unique aliases | not started |
| 6. `_hop_fav_add` / `_hop_fav_remove` | not started |
| 7. `★` display + `Ctrl-S` signal | not started |
| 8. Wire into `hop()` | not started |
| 9. Documentation | not started |

Target on completion: **89 assertions passing**.

Task 1 was implemented by a subagent that was denied permission to `git commit`. Its
self-report contained two errors — it claimed files were staged (they were only
modified) and gave a test breakdown summing to 44 rather than 37. The **total was
independently verified**: `zsh test_hop.zsh` → 37 passed, 0 failed, with all 12
original parser assertions still green. Treat that report as unreliable; trust the
suite.

Task 1's report file was never written. `.superpowers/sdd/2026-07-27-hop-browser/`
holds only the ledger and `task-1-brief.md`.

## Resuming

```sh
cd ~/Code/hop/.worktrees/browser
zsh test_hop.zsh                                    # expect 37 passed, 0 failed
cat docs/superpowers/plans/2026-07-27-hop-browser.md
```

The plan is fully self-contained: every task carries the literal test code and the
literal implementation code, plus expected assertion counts per task (37 → 40 → 55 →
59 → 68 → 79 → 84 → 89). Remaining work is largely transcription plus verification.
It does not need the superpowers framework to execute — any agent can work through it
task by task.

## Decisions already made (do not relitigate)

- **`cd` only; files are never opened.** Enter on a file lands in its parent
  directory. Considered and explicitly deferred — opening needs per-filetype rules and
  `obsidian://` URI construction for the user's vault.
- **Search-first, descend to refine.** One list across bookmarked trees, favorites
  ranked top, `Tab` still descends.
- **Every `.hoprc` entry is a favorite**, shown with `★`. No separate favorites file.
- **`depth=N`, not a bare third column.** Paths contain spaces, so `~/Notes/Chapter 3`
  would parse as path `~/Notes/Chapter`, depth 3.
- **`Ctrl-S` toggles a favorite.** `Ctrl-F`/`Ctrl-B` must stay unbound — they are the
  non-arrow bindings for cursor movement inside the fzf query.
- **`_hop_pick` never writes config.** On `Ctrl-S` it prints the path and exits 2;
  `hop()` performs the mutation. Keeps the picker a pure selection loop.
- **Name is `hop`, not `jump`.** [gsamokovarov/jump](https://github.com/gsamokovarov/jump)
  has 1,939 stars, is actively maintained, and binds `j` by default. The `hop` repos
  that exist are 1–4 stars and abandoned since 2024.
- **zsh only.** bash is not supported; the code uses zsh glob qualifiers and `$match`.

## Traps that already caused bugs

Each of these produced a real failure during development. They are documented in
`DESIGN.md` but repeated here because they will bite again.

1. **`print -r` does not interpret `\t`.** `-r` is raw, so the tab separator becomes a
   literal backslash-t and every field lookup silently returns empty. Use `printf`.
2. **`[[:space:]]#` is a no-op without `extended_glob`.** The `#` quantifier only
   exists when that option is set; otherwise the pattern is a literal `#` and the trim
   does nothing — no error. `_hop_parse` uses regex matching instead.
3. **Symlinks: `(/)` and bare `find` report empty directories.** `find` does not follow
   symlinks by default and zsh's `/` qualifier tests the link, not the target. The
   user's Obsidian vault is behind **two** symlink hops, so it reported zero children
   while `~/Code` worked fine. Use `(-/N)` in zsh and `find -L`.
4. **BSD `find` has no `-printf`.** `_hop_index` runs `find` twice per bookmark
   (`-type d`, then `-type f`) and tags each stream with `sed`. CI runs on ubuntu *and*
   macos, so GNU-only flags break the build.
5. **The user's two `Digital_Brain` trees are different iCloud containers.**
   `~/Digital_Brain/B_AI_and_ML` and `~/Digital_Brain/Obsidian/DB/B_AI_and_ML` are
   different folders with near-identical names.

## Measurements (2026-07-27, live `.jumprc`)

| | |
| --- | --- |
| Items across 21 bookmarks, depth 3 | 8,596 (2,662 dirs / 5,934 files) |
| Full index scan, three largest trees | 41 ms |

Fast enough to rebuild the index every invocation — **no cache**, no staleness logic.

Composition drove the `depth=` design: `~/.claude` (3,114 items) and `~/Code` (2,089)
are 60% of the index and almost never worth searching. They get `depth=0`.

## Open decisions

1. **Two copies will drift.** `~/.config/jump/` and `~/Code/hop/` are diverging.
   Options: repoint `~/.zshrc` at the repo and migrate `~/.jumprc` → `~/.hoprc` with
   `alias j=hop`; or keep them separate deliberately. Not decided.
2. **GitHub username unverified.** README and the plugin header say
   `github.com/shrikantvarma/hop`. Guessed, never confirmed.
3. **Demo recording.** README has a placeholder. Cannot be automated — fzf needs a
   real TTY. `vhs` was suggested as a way to script it.
4. **Nothing is pushed.** No remote is configured. The repo exists only locally.
5. **Permission friction.** Commits and subagent tool calls require approval, which
   stalled execution twice. Options discussed: restart with
   `--dangerously-skip-permissions`, use accept-edits mode, or run tasks inline
   without subagents.

## What is NOT verified

- **The fzf picker's interactive behavior.** fzf reads keys from `/dev/tty` while its
  list arrives on stdin, so it cannot be driven from an automated harness. Driving it
  under a pty (`script -q /dev/null`) was attempted and abandoned. Every keybinding —
  `→`, `←`, `Tab`, `Shift-Tab`, and the planned `Ctrl-S` — is verified only by hand.
  **Anyone finishing this must press the keys in a real terminal.**
- All pure functions ARE covered by the test suite; the gap is only the interactive
  loop.
