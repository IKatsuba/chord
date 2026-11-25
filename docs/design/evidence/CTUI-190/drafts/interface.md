# CTUI-190 interface draft: what people see after the swap

Interface architect's draft for the brief's "people and words" questions:
what a user, a contributor and the maintainer read and run once
github.com/IKatsuba/chord holds the Dart tree. Read against `../chord` at
`577b58167` (v0.71.0) and this repository at `6e91c55d`. Everything marked
**owner** is a proposal, not a decision; the full list is in "Owner
questions" at the end.

## 1. The three people

**A user** (npm today; Homebrew from 0.72.0) sees nothing change in what
they type: the command is `chord`, the package `@chorded/chord`, the
platform packages `@chorded/chord-<os>-<cpu>`, the shim the same Node
script, settings, keybindings, notices, records and teams in the same files.
`chord upgrade` on 0.71.0 installs 0.72.0 through the manager that
installed it. What changes for them is listed in the release notes (§10):
no FFmpeg inside, a different heap report, a few recorded differences.
Homebrew is a new channel, not an upgrade: the tap has no `chord` formula
today (its `Formula/` holds `flipbook.rb` and `roost.rb` only) and the
v0.71.0 GitHub release carries no binaries (only `ffmpeg-9.0.2.tar.xz`
and `zlib-1.3.2.tar.gz`).

**A contributor** clones the repository and finds a Dart project: the app
at the root, the framework under `packages/chord_tui/`, one TypeScript
package (`packages/cursor-cloud-acp/`) with its own Bun toolchain. The
README is the user's pitch; CONTRIBUTING says how to run from source, how
to check a change, and how to get the TypeScript chord (`ts-final`) beside
the clone for the optional comparison tests.

**The maintainer** releases chord with `dart run tool/release.dart`, the
adapter with `bun dev release cursor-cloud-acp`, from the same tree. The
words they read for that are AGENTS.md's Commands and the release
sections, not README.

## 2. Where the reference now lives: words used everywhere

Every document uses the same three names, so nobody has to translate:

| Term | Means | Replaces |
| --- | --- | --- |
| `ts-final` | the tag on the last TypeScript main (`577b58167`, v0.71.0) | "the original", "`../chord`" |
| the TypeScript chord | the app as it was at `ts-final`, when prose needs a noun | "the original" |
| the `ts-final` checkout | a worktree of this repository at that tag, by default `../chord-ts` (runtime settles the default; this is the name the docs use) | "the original checkout", "`../chord`" |

"The port" stays correct in history (decisions, designs) but new prose
says "chord": after the swap the Dart tree is chord, not a port of it.

## 3. AGENTS.md, rewritten

Today's AGENTS.md (744 lines) is the base; the original's (251 lines)
gives two sections the Dart one lacks ("Choosing checks for a change",
"Checking the interface by hand") and the folder rule for
`packages/cursor-cloud-acp/`. Outline:

1. **What this is.** "chord is a full-screen terminal client for coding
   agents that speak the Agent Client Protocol, written in Dart. The tree
   holds three things that do not mix: the app at the root (package
   `chord`), its framework `chord_tui` under `packages/chord_tui/`, and
   `packages/cursor-cloud-acp/`, a TypeScript ACP adapter released to npm
   on its own. Up to 0.71.0 chord was TypeScript on Bun; that tree is the
   tag `ts-final`." Then the reading list: README (the pitch),
   `docs/guide.md` (everything chord does; see §6), FEATURES, decisions.
   The "framework proves itself through the app" paragraph stays as is.
   The English-only, no-private-path sentence stays; its exception becomes
   the `ts-final` checkout's default sibling (§2), or none if runtime
   settles on `CHORD_SOURCE` only.
2. **The rules.** Kept: framework from scratch; maintained package
   first; every action has a key; logic where a test reaches it; shared
   version (now also: the release bump does not touch
   `packages/cursor-cloud-acp/package.json`). Changed: "The port follows
   the original" becomes **"Behaviour carried over from `ts-final` is
   kept"**: screens, keys, states, wording and order that chord had at
   `ts-final` change only by a decision in `docs/decisions.md`; for how
   something was, read `ts-final`'s `docs/guide.md`, `docs/design/`,
   `src/` and `tests/`. Where a change departs from it, ask. (**owner**:
   whether `ts-final` stays binding or becomes history only.) Added from
   the original: the cursor-cloud-acp rule that its Cursor SDK is never
   packed into a binary and its toolchain is Bun.
3. **Commands.** The framework and app blocks as today, minus nothing.
   Added: a third block for the adapter, from the root:
   `bun install`, `bun dev quality cursor-cloud-acp`, and
   `bun dev release cursor-cloud-acp --help` (maintainer's). The "Static
   checks" sentence gains the adapter's quality run when its files change.
4. **Choosing checks for a change.** New, the original's section with Dart
   commands: prose-only changes review the diff; code runs the reached
   tests and static checks; the full suites for broad changes. Today's
   CONTRIBUTING already says this in short; AGENTS.md becomes the place
   it is binding, and the PR template points at it again by that name.
5. **Layout.** As today, plus `packages/cursor-cloud-acp/` and the TS
   files the adapter keeps at the root (framework's inventory names them:
   `package.json`, `bun.lock`, `scripts/`, eslint, tsconfig, prettier),
   each in one line saying it exists only for the adapter.
6. **Tests.** As today, with the oracle paragraph rewritten (§9's words).
7. **Checking the interface by hand.** New, from the original: tmux at
   120x40 and 80x24, with `dart run tool/dev.dart chord --fake` and its
   `--qa` names, the session named and killed. Today this lives only in
   team instructions.
8. **The board.** Project key (**owner**: CTUI continues, or back to the
   original's CHD, or a new one). Board history is not in git either way.
9. **Git.** As today. **Comments.** As today.
10. **Folder rules.** One line: `packages/cursor-cloud-acp/AGENTS.md`
    binds that folder (the original's `src/`, `tests/`, `scripts/`
    AGENTS.md files go with their folders).

### Every sentence of today's AGENTS.md that names the original

| Line | Today | Becomes |
| --- | --- | --- |
| 8-12 | "This repository holds chord, a Dart port of the terminal app, and its Flutter-shaped framework" | §3.1's opening |
| 21-23 | "The original is the specification: the chord repository (github.com/IKatsuba/chord), checked out beside this one at `../chord`. Read it; never edit it." | "The TypeScript chord is the tag `ts-final`; behaviour carried over from it is kept (see The rules). Read it in a `ts-final` checkout (see Tests); nothing is committed there." |
| 33 | "`../chord` is the only path outside the repository that may be written down." | "`../chord-ts`, the `ts-final` checkout's default place, is the only path outside the repository that may be written down." (or dropped, per runtime) |
| 49-52 | "**The port follows the original.** … come from `../chord` (`docs/guide.md`, `docs/design/`, `src/`, `tests/`) as they are. Where Dart or the framework makes an exact copy impossible, or the original looks wrong, ask" | "**Behaviour carried over from `ts-final` is kept.** … change only by a decision; `ts-final`'s `docs/guide.md`, `docs/design/`, `src/` and `tests/` say how it was. Where a change departs from it, ask." |
| 149 | `dart test test/registry_test.dart # original parity` | `# ts-final registry parity` |
| 233-235 | "optional Bun comparison", "`--no-original` skips Bun" | "optional comparison with `ts-final` under Bun"; the flag keeps its name (renaming it is code, not words) |
| 562 | "original registry and CLI parity" | "`ts-final` registry and CLI parity" |
| 563 | "original finder" | "`ts-final` finder" |
| 653-656 | "the folders under `lib/` are named as the original's under `src/`, file for file … `src/ui/prompt/history.ts` is `lib/ui/prompt/history.dart`" | "named as `ts-final`'s under `src/`"; the example stays |
| 691-697 | "Ordinary `fake_agent` tests run by default without Bun or `../chord`. Optional TypeScript parity and original-oracle tests use `CHORD_SOURCE`, else the main checkout's sibling `../chord`, including from worktrees. Registry parity needs only that checkout; TypeScript comparisons also need its dependencies and Bun" | "… without Bun or a `ts-final` checkout. Optional parity and oracle tests run against `ts-final`: `CHORD_SOURCE`, else the main checkout's sibling `../chord-ts`, including from worktrees. Registry parity needs only the checkout; TypeScript comparisons also need `bun install` there and Bun" (lookup per runtime) |

The same substitution applies to `.chord/teams/architects.md` (7 mentions
of `../chord`, `chorded-tui` or CTUI) and `.chord/teams/ship.md` (13). The
original's `.chord/teams/` has files of the same two names with TS
instructions; the Dart ones replace them, rewritten as above. These are
words a coding agent reads as binding, so they are in scope of the swap,
not a follow-up.

## 4. README.md, rewritten

Today's root README (851 lines) is a reference for the port's developer:
it opens with "The Dart port of chord … Version 0.0.1 has …", then runs
through every subsystem, benchmarks and fixtures. The original's README
(230 lines) is the user's pitch with logo, badges, a tour with screenshots,
install, use, supported agents. The repository's front page is for users.
Proposal: the new README is the original's, section by section, with only
what is no longer true changed.

1. **Logo, tagline, badges** (`docs/images/logo-*.png`): unchanged. The npm
   badge stays; the CI badge points at the merged `ci.yml`, same name.
2. **Opening, team screenshot, "npm install -g", start page**: unchanged
   text. Screenshots are kept only if they still match the Dart screens
   (**owner**; see §7, `docs/images`).
3. **Why chord**: unchanged except the last bullet: "Open source. MIT,
   built on its own Dart terminal framework,
   [chord_tui](packages/chord_tui/README.md), and the Agent Client
   Protocol." (OpenTUI and the ACP TypeScript SDK no longer apply.)
4. **A tour**: unchanged, images as above.
5. **Install**: npm (unchanged sentence about the shim and signed,
   notarised macOS binaries), then Homebrew, new:
   `brew install ikatsuba/tap/chord`, stable only. "Build from source"
   becomes Dart 3.12+: `dart pub get`, `dart compile exe bin/chord.dart -o
   build/chord`. `chord upgrade` sentence keeps today's port wording
   (manager-aware, Homebrew included).
6. **Use**: unchanged commands and key table, except
   `chord -p "Explain src/main.tsx"` becomes `"Explain this project"` (the
   example named the TS tree's own file).
7. **Supported agents**: unchanged (the port lists the same 37).
8. **Contributing**: points at CONTRIBUTING; the screenshot line names how
   screenshots are taken now (**owner**, §7).
9. **Licence**: MIT; the FFmpeg/LGPL sentences and the libopentui link go
   (no FFmpeg in a Dart binary; npm platform packages carry `LICENSE` and
   `NOTICES`, the Dart packages' licences). Trademark and Chorded
   sentences unchanged.

The port's developer reference (today's README from "Run from source" on:
ACP and sessions, benchmarks, fixtures, maintainer release) moves out of
the front page. Where to: **owner**, with two options: (a) into
`docs/guide.md`'s "Development" and the relevant user sections, where the
original kept such things; (b) into a new `docs/development.md` linked
from CONTRIBUTING. I recommend (a) for user-facing facts (the heap report,
ACP behaviours, records) and (b) for benchmarks, fixtures and release.
`packages/chord_tui/README.md` stays as it is; its "Repository and app"
section already points to the root.

## 5. CONTRIBUTING.md, rewritten

Today's Dart CONTRIBUTING already follows the original's outline section
for section; it stays, with these changes:

1. **Reporting a bug**: unchanged (identical in both trees).
2. **Running chord from source**: Dart 3.12+; `dart pub get` twice as today;
   `dart run tool/dev.dart chord --fake` / `chord`. One added paragraph for
   the adapter: "`packages/cursor-cloud-acp/` is TypeScript; working on it
   needs Bun 1.4.4 or newer and `bun install` at the root. Nothing else in
   the tree needs Bun."
3. **Before you open a pull request**: the Dart checks as today; for the
   adapter, `bun dev quality cursor-cloud-acp`. The CI paragraph gains the
   adapter's node job (runtime names it).
4. **Comparing with the TypeScript chord** (new heading, replacing the
   `../chord` paragraph): the text in §9.
5. **Screenshots**: Dart's current paragraph (120x40 and 80x24 on the fake
   agent), plus whatever is decided for README images (§7).
6. **Code of conduct**: unchanged.

## 6. docs/guide.md: keep it as chord's user guide

The port has no user guide: its README mixes user facts and developer
facts; the original's `docs/guide.md` (2210 lines) is "everything chord
does, flag by flag and key by key", and the README and the bug template
send users to it (`docs/guide.md#cursor-cloud`,
`#rebuilding-with-a-modified-libopentui`;
`packages/cursor-cloud-acp/README.md` links `../../docs/guide.md#development`).
Since the Dart chord's claim is feature parity, almost all of the guide is
still true of it. A grep for the runtime finds the parts that are not:

- Install (lines 25-49): Bun build from source → Dart; Homebrew added.
- Use, line 60: the `src/main.tsx` example (as README).
- Line 277-278: "OpenTUI chooses the width method; `OPENTUI_FORCE_WCWIDTH`
  or `OPENTUI_FORCE_UNICODE` overrides it" → chord_tui's width rule, and
  whether those variables mean anything now (**owner**: they are user-set
  environment variables that silently stop working).
- Line 663: "OpenTUI's terminal queries reach stdout" → the Dart reason.
- Development (1996-2168): the Dart commands, pointing at AGENTS.md;
  the adapter's commands stay here.
- "Rebuilding with a modified libopentui" (2169-2187): removed (no
  libopentui).
- "Built on" (2188-2198): chord_tui, the Dart packages, the ACP spec.
- Every behaviour the port records as differing (README today: CLI parser
  refusals, file mention sort order, search paste filtering, reentrant
  steering recovery, ACP malformed-line handling, the heap report) gets
  its sentence in the guide where the TS behaviour is described.

Proposal: keep `docs/guide.md`, edit only those passages in the swap, and
open a follow-up task for a line-by-line check of the rest against the Dart
behaviour. **Owner**: keep and adapt (recommended), or drop and point to
`ts-final`'s guide (users then read a guide describing Bun builds and
OpenTUI, and the in-repo links above break).

## 7. The TypeScript history and other docs

| Path (in `../chord`) | Proposal | Why |
| --- | --- | --- |
| `docs/design/CHD-*.md` (TS designs) and `docs/design/evidence/CHD-*` | Keep in place beside `CTUI-*` (no name clash). **owner**: or drop and leave them to `ts-final`. | They are the "why" of the screens chord still draws; AGENTS.md sends people to them. Keeping costs size only (evidence is large). Framework settles the folder layout. |
| `docs/decisions.md` (TS, 8957 lines) | Keep, renamed `docs/decisions-ts.md` (framework settles the name); the Dart log stays `docs/decisions.md`, with a first new entry dated on the swap: "Up to 0.71.0 chord was TypeScript (`ts-final`); its decisions are in `decisions-ts.md`. In entries before this one, `../chord` and 'the original' mean `ts-final`." | Both logs are append-only; neither may be rewritten, so the old wording is explained once, not edited. |
| `docs/FEATURES.md` (TS map) | Replaced by the Dart one (§8); the TS map stays in `ts-final`. | The Dart map's rows already point at the TS milestones by name. |
| `docs/guide.md` | Keep and adapt (§6). | |
| `docs/qa/` (11 913 files of captures, CHD-126 etc.) | Drop; it stays in `ts-final`. **owner** | QA evidence of TS builds; nothing user-facing links to it. One Dart test comment cites `docs/qa/evidence/CHD-337` (`test/ui/transcript/left_open_test.dart:131`), which reads as "in `ts-final`" after §3's substitution. |
| `docs/images/` (logo, 10 screenshots) | Keep logo now. Screenshots: keep if a check at the swap finds the Dart screens the same, else retake. **owner**: the original retakes them with `bun dev screenshots` (tmux and Chrome); the Dart tree has no screenshot tool, so either one is ported (a task) or retaken by hand. | README depends on them. |
| `docs/memory.md` (Bun heap snapshots, `bun dev memory`, CHD-343 results) | Drop; its user part (USR2 writes a report in `heaps/`) moves into the guide in Dart terms. | Its content is Bun/JSC-specific: V8 `.heapsnapshot` from `Bun.generateHeapSnapshot`, `bun:jsc`'s `heapStats()`. The Dart binary writes a JSON report and `heap-error.txt` instead of a snapshot (README lines 430-435). |
| `docs/agent-capabilities.md` (6085 lines, CHD-433, agents' ACP surfaces) | Keep. | It is about the agents, not the runtime, and the Dart code relies on it (TS cites it at `src/cost_counts.ts:28`, `src/acp/plans.ts:3`, `src/acp/connection.ts:242`; the Dart counterparts carry the same reasoning). Its `src/registry.ts`/`src/clis.ts` references become "the registry pins (`lib/registry.dart`)" in a note at its head, not by editing the body. |

## 8. docs/FEATURES.md, rewritten

Today's Dart map opens "The goal: enough of the framework to port chord
(`../chord`, its own `docs/FEATURES.md` is the list of what chord does) to
Dart". After the swap the goal is reached for M0-M5 except the rows still
open. Outline:

1. **Intro**: "What gets built, and in which order. chord was ported from
   TypeScript (`ts-final`) feature for feature; the milestones below are
   the TypeScript map's, done when chord does what `ts-final` did." The
   framework/port definitions stay ("port" → "app").
2. **Core**, **F**, **M0-M5**: unchanged rows; their notes that say
   "the original's `src/acp/`" read "`ts-final`'s". The upgrade row
   (in progress, self-replacement) stays open.
3. **New: M6 — the swap** (or whatever the owner calls it): CTUI-190's row
   and what follows it (guide check, screenshots, privacy test, see §11).
4. **Agent-side: passed through**: the original's closing section, carried
   over word for word; the Dart map lacks it and it is still the rule.

## 9. Getting `ts-final` locally, in a contributor's words

For CONTRIBUTING's "Comparing with the TypeScript chord":

> Up to 0.71.0 chord was written in TypeScript. That tree is the tag
> `ts-final`, and a few optional tests compare today's chord with it: the
> agent registry, a handful of screens and the session record. They are
> skipped, with a reason, until you have it. To run them, put the tag in a
> worktree beside your clone and install its dependencies:
>
> ```sh
> git fetch origin tag ts-final
> git worktree add ../chord-ts ts-final
> (cd ../chord-ts && bun install)   # only for the TypeScript comparisons
> ```
>
> The tests find `../chord-ts` next to your clone, even from a worktree of
> your own. Elsewhere, point `CHORD_SOURCE` at it; `CHORD_BUN` picks a Bun
> other than the one on your PATH. Never commit in that worktree: it is a
> reference, and `git worktree remove ../chord-ts` takes it away.

(The exact default lookup is runtime's to settle; if it ends up
`CHORD_SOURCE` only, the paragraph says "set `CHORD_SOURCE=../chord-ts`"
instead.) A shallow clone (`--depth 1`) lacks the tag's tree; `git fetch
origin tag ts-final` with `--depth` set fetches only that commit, which is
enough.

## 10. Upgrading from 0.71.0, as the user lives it

### Commands

| They run | 0.71.0 did | 0.72.0 does |
| --- | --- | --- |
| `chord upgrade` on 0.71.0 (npm, bun, pnpm, yarn) | TS `src/upgrade.ts:70-85`: `npm install --global @chorded/chord@<v>` (or bun/pnpm/yarn add), exact version | the 0.71.0 binary does this to install 0.72.0; nothing new is needed, as the package and platform package names and layout are the same (`tool/npm.dart:76-104` against the published 0.71.0: `bin: {chord: bin/chord.js}`, the same four optional platform packages) |
| `npm install -g @chorded/chord` | shim + Bun binary | shim (same text, `tool/npm.dart:22`) + Dart binary |
| `brew install ikatsuba/tap/chord` | no formula | new; stable only |
| `chord upgrade` on 0.72.0 under Homebrew | n/a | `brew upgrade ikatsuba/tap/chord`; `--version` and `-l` refused |
| `chord --version` | `0.71.0` | `0.72.0` (the release bump sets `lib/version.dart`) |
| `kill -USR2 <pid>` | V8 `.heapsnapshot` + JSC stats JSON in `heaps/` | JSON report in `heaps/`; the shipped binary writes `heap-error.txt` instead of a snapshot |

npm platform packages change content: 0.71.0's carried `LICENSE-FFMPEG`,
`LICENSE-ZLIB` and `FFMPEG-SOURCE.md` (README, Licence); 0.72.0's carry
`LICENSE` and `NOTICES` (`tool/npm.dart:82`). The GitHub release changes
from FFmpeg/zlib source tarballs to the binary archives and checksums the
formula reads.

### State and settings

Verified the same in both trees (TS `xdg-basedir` against Dart
`xdg_directories` and `configHome`):

| What | TS | Dart |
| --- | --- | --- |
| state dir | `src/session/state_dir.ts:13` `$XDG_STATE_HOME/chord` | `lib/session/state_dir.dart:7` |
| records | `src/session/record.ts:243` `<state>/records` | `lib/session/sessions.dart:199,385` |
| heaps | `src/main.tsx:380` | `lib/cli.dart:1090` |
| settings | `src/settings.ts:154` `<config>/chord/settings.json` | `lib/settings.dart:237` |
| keybindings | `src/settings.ts:168` | `lib/settings.dart:242` |
| notices | `src/notices.ts:184` | `lib/notices.dart:147` |
| project settings | `src/settings.ts:224`, `src/mcp.ts:312` | `lib/settings.dart:282`, `lib/mcp.dart:421` |
| teams | `src/teams.ts:134-135` | `lib/teams.dart:241-242` |

One edge differs: with `HOME` unset, `xdg-basedir` falls back to
`os.homedir()` (the password database), while `xdg_directories` throws and
chord exits with "HOME or XDG_STATE_HOME must be set to keep chord's
state." (`lib/session/state_dir.dart:10`). Real sessions always have
`HOME`; noted, not a blocker.

### File contents, upgrade and downgrade

A read of both trees for every persisted file (task agent's audit;
notices and the record header spot-checked by hand) found **no
incompatibility** either way, 0.71.0 → 0.72.0 or back:

- `settings.json`: the same top-level, per-agent and `teamSelection`
  keys (TS `src/settings.ts:20-120`, Dart `lib/settings.dart:560-650`),
  the same enumerations, the same "unknown key, ignored" problem, and the
  same writes (two-space JSON, final newline, temp file then rename: TS
  `:1256-1257`, Dart `:1299-1302`).
- `keybindings.json`: the same 12 contexts (TS
  `src/ui/shortcuts/bindings.ts:18-31`, Dart
  `lib/ui/shortcuts/bindings.dart:14-26`), all 45 TS action ids known to
  Dart, the same removed `session:*` ids and key names.
- `notices.json`: `{"dismissed": [...]}`, id `dimcode-agents` (TS
  `src/notices.ts:15`, Dart `lib/notices.dart:18,165,181`).
- Records: header `type: session`, `version: 1` (Dart
  `lib/session/record.dart:85,438`), the same line kinds including
  `renamed` and `forked`, agent updates stored whole, `<uuid>.jsonl`.
- Team files: the same strict keys and length limits (TS
  `src/teams.ts:57-99`, Dart `lib/teams.dart:395-490`).
- Nothing else persisted on either side (no input history, theme files,
  tokens, locks or caches); every user-facing environment variable TS
  reads (`NO_COLOR`, `COLORFGBG`, `TERM*`, `TMUX`, `VISUAL`, `EDITOR`,
  `SHELL`, `HOME`, `XDG_*`) Dart reads too. Only OpenTUI's own
  (`OTUI_STDOUT_THREAD`, and the `OPENTUI_FORCE_*` of §6) lapse.

Differences a user could meet, none blocking:

- A malformed record line: Dart validates each line's shape and skips one
  that does not match (`lib/session/record.dart:77-127`); TS takes lines as
  written. Well-formed 0.71.0 records lose nothing.
- Team frontmatter: TS parses with `vfile-matter` and writes with npm
  `yaml` (`src/teams.ts:10-12`), Dart reads with `package:yaml`
  (`lib/teams.dart:14`); the port's `yaml_stringify` tests cover writing,
  but YAML 1.1 edge scalars (`yes`/`no`, odd numbers, anchors) in a
  hand-written team file are not proven to read the same. Worth one test
  before release (runtime's).
- Heap files keep their names (TS `src/platform/heap.ts:59-60,114`, Dart
  `lib/platform/heap.dart:53,103`) but not their content (§10, Commands).

## 11. Release notes for 0.72.0

Proposed text for the GitHub release (one long line per paragraph when
posted; **owner** for the wording and the headline):

> **chord 0.72.0: rewritten in Dart**
>
> chord is now a native Dart binary instead of a Bun-compiled one. It does
> what 0.71.0 did: the same command, agents, keys, settings, keybindings,
> teams and saved sessions. Upgrade as usual with `chord upgrade`, or
> `npm install -g @chorded/chord`. Your settings, sessions and teams are
> read where they were; `chord --continue` and `chord --resume` pick up
> sessions recorded by 0.71.0.
>
> New: Homebrew. `brew install ikatsuba/tap/chord` installs stable
> releases, and `chord upgrade` then runs `brew upgrade`.
>
> Changed:
> - The binary is smaller and starts faster (**fill in measured numbers or
>   drop**), and contains no FFmpeg; npm packages carry `LICENSE` and
>   `NOTICES` instead of the FFmpeg and zlib licences.
> - `kill -USR2` writes a JSON memory report in `heaps/`; heap snapshots
>   are no longer written by the release binary.
> - (each user-visible difference the audit and the README's recorded
>   differences leave, one line each: CLI option refusals, `@` file
>   order for non-ASCII and case ties, …)
>
> For contributors: the repository is now Dart (`dart pub get`, `dart
> test`); the TypeScript tree is the tag `ts-final`. The Cursor Cloud
> adapter, `@chorded/cursor-cloud-acp`, is unchanged and still TypeScript.

## 12. GitHub templates and community files

Diffed `../chord` against this tree:

| File | Difference | Proposal |
| --- | --- | --- |
| `LICENSE`, `SECURITY.md`, `CODE_OF_CONDUCT.md` | identical | keep |
| `.github/FUNDING.yml` | identical (`github: [IKatsuba]`) | keep |
| `.github/ISSUE_TEMPLATE/{bug,feature,config}.yml` | identical | keep; the bug template's fields (`chord --version`, agent, OS and terminal, `tmux capture-pane -p`) all still apply |
| `.github/pull_request_template.md` | line 7: "Choosing checks for a change" vs "Tests"; line 10: `bun dev screenshots` vs "captured at 120x40 and 80x24 on the fake agent" | Dart's, with line 7 naming "Choosing checks for a change" again once AGENTS.md has that section (§3.4) |
| `TRADEMARKS.md` | line 6: TS `scripts/mark.svg` and `src/ui/header/mark.ts` vs Dart `example/chord/lib/ui/header/mark_rows.dart` | Dart's, **fixed**: that path no longer exists; it is `lib/ui/header/mark_rows.dart` |
| `SECURITY.md` scope paragraph | true of Dart chord too (loopback MCP server with per-session token, records in the state dir) | keep |

## 13. Found while reading, outside the words of the swap

- `README.md:3-5` says "Version 0.0.1 has …" and `pubspec.yaml` is 0.0.1:
  the release bump sets 0.72.0, but README's sentence is prose and will
  not follow; §4 removes it.
- `TRADEMARKS.md:6` names a path that does not exist (§12).
- The original fails its quality run on any tracked file naming a home
  directory (`tests/privacy_test.ts`, per its AGENTS.md); the Dart tree
  has no such test. After the swap the public repository loses that
  guard. Runtime or a follow-up.
- `packages/cursor-cloud-acp/README.md:84-92` says "`bun install` installs
  the workspace" and links `../../docs/guide.md#development`; both hold
  only if §6 keeps the guide and runtime keeps the workspace root.
- Port comments cite the guide by line (`test/ui/prompt/prompt_rows_test.dart:2`,
  `test/ui/dialogs/questions_note_rows_test.dart:2`: "docs/guide.md
  259-262"). Once the guide is edited in-tree those numbers drift; they
  mean `ts-final`'s guide.

## 14. Owner questions

1. Is `ts-final` still binding for behaviour chord carried over (a change
   needs a decision), or history only? (§3.2)
2. Board project going forward: CTUI, CHD, or new? (§3.8)
3. `docs/guide.md`: keep and adapt (recommended), or drop in favour of
   `ts-final`'s? (§6)
4. Where the port's developer reference goes when README becomes the
   user's pitch: guide + `docs/development.md` (recommended), or keep
   README as it is? (§4)
5. TS design history (`docs/design/CHD-*` and evidence, `docs/decisions.md`
   as `decisions-ts.md`): keep in-tree (recommended), or leave to
   `ts-final`? `docs/qa/`: drop (recommended)? (§7)
6. README screenshots: keep if unchanged, retake by hand, or port
   `bun dev screenshots` first? (§7)
7. `OPENTUI_FORCE_WCWIDTH` / `OPENTUI_FORCE_UNICODE`: users who set them
   lose their effect; say so in the release notes only, or support an
   equivalent? (§6)
8. The release notes' headline and whether to call it a rewrite at all.
   (§11)
