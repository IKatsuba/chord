# CTUI-190: the swap into the chord repository

The owner approved replacing the TypeScript chord app in the chord
repository (github.com/IKatsuba/chord, checked out at `../chord`, main
`577b58167`, v0.71.0) with this repository's tree, then releasing 0.72.0
stable from it. This is the design of that swap; nothing in it has been
run against `../chord`. The record behind it is
`docs/design/evidence/CTUI-190/drafts/` (brief, framework, interface,
runtime; each with an "After the critic" section where amended). Where a
draft and this file differ, this file holds.

Owner questions are on the board as Q387 to Q400 (CTUI-190), all
answered; section 10 lists the answers, and every step here follows them.
Where an answer overrides a draft, this file holds. Everything the swap
copies is made ready on this repository's main first, by the pre-swap
task CTUI-191 (section 9); phase 0 gates on it.

## What changes, in one paragraph

`ts-final`, a signed tag on `577b58167`, keeps the TypeScript tree and
its whole history. On a branch `dart` of `../chord`, four signed commits
land on top of TS main: (1) the TS root reduced to the workspace
`packages/cursor-cloud-acp` needs; (2) this repository's tracked tree at a
pinned commit, by `git archive`, already at 0.71.0 and with its docs and
screenshots for the new home; (3) one CI workflow; (4) the docs lines
that name the TypeScript workspace. After the swap the Dart chord is its
own specification: `ts-final` is history, for reference only (Q387).
This repository's history is not imported. The owner reviews, lands
`dart` on main by fast forward, pushes, and runs `dart run
tool/release.dart chord --bump 0.72.0`.

## 1. Inventory of `../chord` at `577b58167`

Verdicts: **drop** (gone from the tree, kept at `ts-final`), **port**
(the port's file replaces it), **keep**, **reduce**, **merge**. Full
tables with counts: framework draft, "Inventory".

| Path | Verdict | Why |
| --- | --- | --- |
| `src/` | drop | the app; the port's `lib/`, `bin/` replace it. `src/channel.ts` alone survives, moved to `scripts/dev/release/channel.ts`: six release modules import it |
| `tests/` | drop but `tests/scripts/**` | the app's tests; the kept tooling's tests stay (section 2) |
| `steps.ts` | drop | chord's bun checks and release; the Dart release is `tool/release.dart` |
| `scripts/` | reduce | `dev.ts` cut to `quality`, `lint`, `release`; `dev/steps.ts`, `dev/covered.ts`, `dev/compile.ts`, `dev/release/*` but `pins.ts`, `targets.ts`, `macos/chord.entitlements` stay (the release engine imports them); `dev/{tools,npm,registry,mark,screenshots,social,memory,jsx_dev_runtime}.ts`, `screenshots_*.md`, `format.ts`, `mark.svg` go (the port's `tool/screenshots.dart` replaces the screenshot tool); `scripts/AGENTS.md` reduced |
| `lint/` | keep | `style.ts` is the ESLint plugin the package's config loads; its two tests run (section 2) |
| `package.json` | reduce | no longer `@chorded/chord`: `chord-workspace` (Q395), private, no version, `workspaces: ["packages/cursor-cloud-acp"]`, 7 deps, 14 dev deps |
| `bun.lock` | reduce | regenerated once (617 → 390 packages), frozen after |
| `bunfig.toml` | reduce | `[test] preload = ["./tests/colour.ts"]` goes (it would break the package's `bun test`) |
| `tsconfig.json` | reduce | `include: ["scripts/", "tests/", "lint/", "eslint.config.ts"]`; `jsx`, `jsxImportSource`, `paths`, `files` go |
| `eslint.config.ts` | keep | the package imports `shared`, `forbid`, `TOOLING`; dead `src/**` blocks stay so `lint/config_test.ts` holds; pruning is the follow-up |
| `.npmrc`, `.prettierrc.json`, `.prettierignore` | keep | `@jsr` registry for `@cliffy/command`; the package's format check |
| `.puppeteerrc.json` | drop | only the dropped screenshot tool used it |
| `.zed/`, `.git-blame-ignore-revs` | keep (Q400) | Prettier for TS, still true; blame data for kept history |
| `.gitignore` | merge | union, section 3 |
| `.github/` | port + merge | templates and FUNDING identical; `pull_request_template.md` the port's; `ci.yml` merged (section 4) |
| `.chord/teams/{architects,ship}.md` | port, rewritten | same names both sides; the port's, with `../chord` made history (section 6) |
| `.claude/` | nothing tracked | local only; ignored |
| `AGENTS.md`, `CONTRIBUTING.md`, `README.md` | port, rewritten | section 6 |
| `CODE_OF_CONDUCT.md`, `LICENSE`, `SECURITY.md` | keep | byte-identical in both trees |
| `TRADEMARKS.md` | port | the stale `example/chord/lib/ui/header/mark_rows.dart` already fixed to `lib/ui/header/mark_rows.dart` by CTUI-191 |
| `docs/FEATURES.md` | port | rewritten by CTUI-191 (section 6) |
| `docs/decisions.md` | port | the TS log stays at `ts-final` only (Q391); no `docs/decisions-ts.md` |
| `docs/guide.md` | port (Q389) | the user guide, brought into the port and adapted line by line to the Dart chord by CTUI-191; the one TS doc that moves |
| `docs/agent-capabilities.md` | drop (Q391) | no TS doc moves but the guide; it stays at `ts-final` |
| `docs/images/` | port (Q392) | all twelve retaken through the fake by the port's `tool/screenshots.dart` (CTUI-191); same file names |
| `docs/design/CHD-*.md` | drop (Q391) | stay at `ts-final`; the 85 port files citing a `CHD-` key cite history there |
| `docs/design/evidence/CHD-*`, `docs/qa/`, `docs/memory.md` | drop (Q391) | TS captures and Bun heap tooling; a clone keeps them in history either way |
| `packages/cursor-cloud-acp/` | keep, untouched | |
| `dist/`, `npm/`, `node_modules/`, `.release/` | untracked | ignored; `.release/` empty today |

Collisions: 18 tracked paths exist on both sides, 7 byte-identical; no
directory-level clash (`lib`/`src`, `test`/`tests`, `tool`/`scripts`,
`CTUI-*`/`CHD-*` are disjoint). Neither tree has symlinks, submodules or
`.gitattributes`.

## 2. cursor-cloud-acp's TypeScript toolchain

The package stays TypeScript and npm-released (its Cursor SDK may not be
packed into a binary). Its reach outside its folder, traced by import
closure: `../../eslint.config.ts` → `lint/style.ts`;
`scripts/dev/steps.ts` (types, `isPublish`); `scripts/dev/covered.ts`;
`scripts/dev/release/{build,lib,publish,sums}.ts` and, through them, the
whole release engine; `@modelcontextprotocol/sdk` from the root.

Three breaks the swap must fix, each proven in a scratch export:

1. `bun dev` dies on any command once `packages/chord_tui` exists: its
   finder globs the workspace pattern and reads each `package.json`
   (ENOENT). The workspace list names `packages/cursor-cloud-acp` alone.
   `bun install` itself ignores the folder.
2. The `bunfig.toml` test preload into `tests/` breaks `bun test`; it
   goes.
3. The finder counts the root `.` as a package (needs `steps.ts`, a
   publish stage, an `@chorded/` name). The `'.'` entry is removed
   unconditionally; the root is never a package again. `scripts/dev.ts`
   loses its static `../steps.ts` import and its `chord` default.

The release engine is kept whole (level L1): `stages.ts` imports chord's
stage modules, so pruning them is a follow-up, not the swap. Its tests stay
and run from the root:

```sh
bun test ./tests/scripts ./lint      # 612 pass, 21 files, ~150 s in the trial
```

Kept unchanged: 17 files. Moved: `tests/channel_test.ts` →
`tests/scripts/dev/release/channel_test.ts`. Fixed: `publish_test.ts`
and `stages_test.ts` take chord's old `steps.ts` from a new fixture
`tests/scripts/dev/release/fixtures/chord_steps.ts` (pins preflight
removed, `CHORDED_AGENTS` loop removed, no case dropped); `steps_test.ts`
rewrites its 7 root-as-package cases. Dropped: `npm`, `screenshots`,
`social`, `tools`, `compile`, `format` and `pins` tests (their modules
go). `tests/scripts/dev_test.ts` is rewritten with the `dev.ts` cut (the
describes kept and dropped are listed in the framework draft; `strip-ansi`
becomes `Bun.stripANSI`). Exact edits: framework draft, "After the
critic".

Result in the trial, the reduced root beside the port: `bun install
--frozen-lockfile` (390), `bun dev quality cursor-cloud-acp` (types,
covered, eslint, format, 310 tests, build, smoke), `bun dev lint
cursor-cloud-acp`, `bun dev release --help` listing only
`cursor-cloud-acp  install, quality, build, pack, publish`; `dart
analyze` both, `dart format` clean, `git status` clean after both
installs. `bun dev release cursor-cloud-acp` keeps working from the same
root: its stages, state under `.release/cursor-cloud-acp/` and tag
`cursor-cloud-acp-v{version}` are unchanged. It was not run (every form
authenticates npm).

npm names: after the swap only `lib/distribution.dart` and `tool/npm.dart`
name `@chorded/chord` and `@chorded/chord-{darwin,linux}-{arm64,x64}`.
The root is private and nameless to `bun dev`; the package is
`@chorded/cursor-cloud-acp`. The root's name is `chord-workspace`,
unscoped (Q395).

## 3. The merged `.gitignore`

```gitignore
.dart_tool/
build/
*.exe
.release/
dist/
node_modules/
npm/
.DS_Store
.claude/settings.local.json
.claude/worktrees/
```

Both release tools refuse a dirty tree, so each one's output is ignored
for the other. `.release/chord/` (Dart) and `.release/cursor-cloud-acp/`
(TS) do not overlap.

## 4. CI: one workflow

The port's `.github/workflows/ci.yml` job for job, plus the original's
`node` job renamed `cursor-cloud-acp` (`node` is the port's npm shim job):

| Job | Runs |
| --- | --- |
| `static` | setup-dart; pub get both; analyze both; format; actionlint |
| `tests (1/3..3/3)` | each package's shard through `tool/shards.dart` |
| `compile` | expect; both packages' `-t compile --run-skipped` |
| `node` | Node 22.13; `dart test test/tool/npm_test.dart` |
| `release` | `tool/ci.dart linux-x64`, `linux-arm64` |
| `cursor-cloud-acp` | checkout (`persist-credentials: false`); setup-bun 1.4.4; Node 22.13; `bun install --frozen-lockfile`; `bun dev quality cursor-cloud-acp`; `bun test ./tests/scripts ./lint` |
| `check` | needs all six, `if: always()`, one `test ... = success` per job; the name branch protection requires |

Triggers: push to `main`, pull requests (Q398); the port's file already has them.
`test/tool/workflow_test.dart` changes in three cases (seven jobs,
`check`'s needs, the allowed actions gain `oven-sh/setup-bun@v2`) plus one
new case for the job; `shards_test` and `ci_test` are unaffected. The
merged file passed actionlint in the trial.

## 5. Oracle and parity tests: removed

The parity and oracle tests go before the swap (Q397). With `ts-final`
history only (Q387), nothing in the Dart tree compares itself with the
TypeScript chord any more, so the pre-swap task removes every case and
file that needs `CHORD_SOURCE`, `CHORD_BUN`, a `../chord` lookup, Bun,
or a TS/JS probe of the original: `test/fixtures/fake_agent/parity_test.dart`,
registry parity, the original comparisons in the node_semver,
yaml_stringify, notify, resources, codex, record_interchange, layout_keys
and npm tests, `tester_probe.mjs`, `original_probe.ts`, the YAML and
record `.mjs` probes, the original finders in `fake.dart` and
`fake_harness.dart`, `benchmark/record_scan.dart`'s Bun comparison and
`--no-original`, and `tool/genai_prices.dart`'s default.

What stays: the Dart fake, the pinned recorded fixtures that run without
TypeScript, and the Node shim case of `npm_test.dart` (Node is not the
original). Comments that cite the original as history may stay.

So there is no `../chord-ts` worktree, no lookup to redirect, and no
parity run in CI or in the swap's verification. Release acceptance rests
on the suites, the compile tags and the post-publish checks (section 8).

## 6. Docs for the new home

Words used everywhere: `ts-final` (the tag, history for reference), "the
TypeScript chord" (the app as it was there). New prose says "chord", not
"the port". No path outside the repository is named.

Most of the docs are written on this repository's main by the pre-swap
task, so commit 2 copies them as they are:

- **README.md** (Q390): the TS README's pitch as the base, with what is
  untrue changed: chord_tui instead of OpenTUI, Homebrew added, build
  from source in Dart (`mkdir -p build` before `dart compile exe`), the
  `src/main.tsx` example becomes "Explain this project", the FFmpeg
  licence sentences go. Screenshots are the twelve retaken through the
  fake (Q392), at the same `docs/images/` names.
- **docs/development.md** (Q390): the port's developer reference that
  was its README (benchmarks, fixtures, release).
- **docs/guide.md** (Q389): brought from the TypeScript chord and adapted
  line by line: install, the `src/main.tsx` example, OpenTUI terminal
  queries, Development, "Rebuilding with a modified libopentui" removed,
  "Built on"; `OPENTUI_FORCE_WCWIDTH` and `OPENTUI_FORCE_UNICODE` are not
  supported, which the 0.72.0 release notes say (Q393). Every claim is
  checked against the Dart chord.
- **AGENTS.md**: "What this is" names the app, `chord_tui` and
  `ts-final`; "The port follows the original" becomes: chord is its own
  specification; `ts-final` is history, read for reference, never
  binding (Q387); a change to screens, keys or wording is decided like any
  other. Parity and oracle commands and paragraphs go; the board stays
  CTUI (Q388); the repository is github.com/IKatsuba/chord.
- **CONTRIBUTING.md**, **docs/FEATURES.md**: the same rewrite; FEATURES'
  intro names `ts-final` as history, with a milestone for the swap.
- **TRADEMARKS.md**: the stale mark_rows path fixed.

Commit 4 adds only what names the TypeScript workspace, which lands with
commit 1 and cannot be described before it:

- **AGENTS.md**: "What this is" gains `packages/cursor-cloud-acp`; a third
  Commands block for the adapter (`bun install`, `bun dev quality
  cursor-cloud-acp`, `bun test ./tests/scripts ./lint`, `bun dev release
  cursor-cloud-acp --help`); Layout gains the TS root files, one line
  each, "for the adapter only".
- **CONTRIBUTING.md**: the adapter paragraph (Bun only for
  `packages/cursor-cloud-acp/`).
- **docs/decisions.md**: the swap's entry: before it, `../chord` and
  "the original" mean `ts-final`, whose own decisions log stays there.
- **.chord/teams/*.md**, `.github/pull_request_template.md`: the adapter's
  checks beside chord's.

## 7. The sequence

Runs from the folder holding `chord/` and `chorded-tui/` side by side.
Phases 0 to 5 are the swap run (a later task, after the pre-swap task
CTUI-191 is on main); phase 6 is the owner's. Each phase is
pasted whole into one bash shell. Nothing pushes before phase 6. A failed
gate, test or signature stops the run.

```bash
#!/usr/bin/env bash
set -euo pipefail
# Start: the folder holding chord/ and chorded-tui/.
test -d chord/.git && test -d chorded-tui/.git
P=$PWD/chorded-tui
C=$PWD/chord
W=$PWD/chord-worktrees/dart
TS_MAIN=577b58167672e12c999aeaf4eed2a1a988513dc2
PORT=$(git -C "$P" rev-parse main)   # the reviewed port commit; pin it by hand if main moves
COMMON=$(git -C "$C" rev-parse --path-format=absolute --git-common-dir)

clean()  { test -z "$(git -C "$1" status --porcelain --untracked-files=all)"; }
signed() { git -C "$1" cat-file commit HEAD | grep -q '^gpgsig' \
             || { echo "unsigned HEAD in $1: stop" >&2; exit 1; }; }
on_dart(){ test "$(git -C "$W" symbolic-ref --short HEAD)" = dart \
             || { echo "W is not on dart: stop" >&2; exit 1; }; }
# A negative gate: `refuse <why> <command...>` stops the run if the command
# succeeds. A bare `! command` would not: set -e exempts inverted commands.
refuse() { local why=$1; shift
  if "$@"; then echo "gate failed: $why: stop" >&2; exit 1; fi; }
# Exit 2 = no such ref on origin; 0 = it exists; anything else = transport error.
absent_on_origin() {
  local rc=0; git -C "$C" ls-remote --exit-code origin "$1" >/dev/null || rc=$?
  case $rc in 2) ;; 0) echo "$1 exists on origin: stop" >&2; exit 1 ;;
              *) echo "ls-remote failed ($rc): stop" >&2; exit 1 ;; esac
}
```

### Phase 0: gates

```bash
clean "$C"
git -C "$C" fetch origin
test "$(git -C "$C" rev-parse main)" = "$TS_MAIN"
test "$(git -C "$C" rev-parse origin/main)" = "$TS_MAIN"
refuse "ts-final exists" git -C "$C" rev-parse -q --verify refs/tags/ts-final
refuse "dart exists" git -C "$C" rev-parse -q --verify refs/heads/dart
absent_on_origin refs/tags/ts-final
absent_on_origin refs/heads/dart
test ! -e "$W"
test -z "$(ls -A "$C/.release" 2>/dev/null)"
test ! -e "$COMMON/chord-release.lock"
clean "$P"
# The port tracks no path the copy must leave out.
if git -C "$P" ls-tree -r --name-only "$PORT" \
  | grep -E '(^|/)(build|\.dart_tool|\.release|node_modules|dist|worktrees)/|\.DS_Store|settings\.local\.json'
then echo "the port tracks a path the copy must leave out: stop" >&2; exit 1; fi
# The pre-swap task CTUI-191 is in: no parity or original probe is left ...
refuse "parity_test.dart is left" \
  git -C "$P" cat-file -e "$PORT:test/fixtures/fake_agent/parity_test.dart"
refuse "an original probe is left" \
  git -C "$P" grep -nE 'CHORD_BUN|originalSource|originalSkip' "$PORT" -- lib test tool benchmark
# ... the version is 0.71.0 in both packages, and live-version tests read `version` ...
git -C "$P" grep -qx 'version: 0.71.0' "$PORT" -- pubspec.yaml
git -C "$P" grep -qx 'version: 0.71.0' "$PORT" -- packages/chord_tui/pubspec.yaml
git -C "$P" grep -qxF "const version = '0.71.0';" "$PORT" -- lib/version.dart
# (wheel_window_test and error_window_test keep 0.0.1: it is their fixture
# launches' version, not the live one.)
refuse "a live-version test names 0.0.1" \
  git -C "$P" grep -nF 0.0.1 "$PORT" -- test/cli_test.dart test/tool/dev_test.dart
# ... and the twelve retaken screenshots and the adapted guide are tracked.
test "$(git -C "$P" ls-tree --name-only "$PORT" docs/images/ | grep -c '\.png$')" = 12
git -C "$P" cat-file -e "$PORT:docs/guide.md"
git -C "$P" cat-file -e "$PORT:docs/development.md"
```

### Phase 1: tag and worktrees

```bash
git -C "$C" tag -s ts-final -m "chord: the last TypeScript main (v0.71.0)" "$TS_MAIN"
git -C "$C" tag -v ts-final                       # signature verifies, or stop
git -C "$C" worktree add -b dart "$W" main
on_dart
```

### Phase 2: commit 1, the TS workspace reduced

```bash
on_dart
git -C "$W" mv src/channel.ts scripts/dev/release/channel.ts
git -C "$W" mv tests/channel_test.ts tests/scripts/dev/release/channel_test.ts
# Everything under tests/ but tests/scripts/ goes (Q391's answer does not touch it).
git -C "$W" ls-files -z tests | grep -zv '^tests/scripts/' | xargs -0 git -C "$W" rm -q --
git -C "$W" rm -q -- steps.ts .puppeteerrc.json scripts/format.ts scripts/mark.svg \
  scripts/dev/{tools,npm,registry,mark,screenshots,social,memory,jsx_dev_runtime}.ts \
  scripts/dev/screenshots_{proposal,team}.md scripts/dev/release/pins.ts \
  tests/scripts/dev/{npm,screenshots,social,tools,compile}_test.ts \
  tests/scripts/format_test.ts tests/scripts/dev/release/pins_test.ts
git -C "$W" rm -r -q -- src
# Edits (§(a), as amended): channel imports; scripts/dev.ts; scripts/dev/steps.ts
# without '.'; package.json (chord-workspace, private, workspaces
# ["packages/cursor-cloud-acp"]); bunfig.toml without [test]; tsconfig.json;
# tsconfig.json includes tests/; the four fixed tooling tests, the chord_steps.ts
# fixture and the dev_test.ts rewrite (framework draft, After the critic);
# scripts/AGENTS.md.
(cd "$W" && rm -rf node_modules && bun install && bun install --frozen-lockfile)
(cd "$W" && bun dev quality cursor-cloud-acp)
(cd "$W" && bun test ./tests/scripts ./lint)
git -C "$W" add -A          # W holds only this phase's changes; clean "$W" gated it
git -C "$W" commit -m "chore: reduce the TypeScript workspace to cursor-cloud-acp"
signed "$W"
clean "$W"
```

### Phase 3: commit 2, the port in

```bash
on_dart
# No TS doc moves (Q391): the whole TS docs/ goes, and the archive brings
# the port's, with the adapted guide (Q389) and the retaken images (Q392).
git -C "$W" rm -r -q -- docs
git -C "$P" archive "$PORT" | tar -x -C "$W"
# .gitignore: framework's union. The version is already 0.71.0 (Q396, CTUI-191).
(cd "$W/packages/chord_tui" && dart pub get) && (cd "$W" && dart pub get)
git -C "$W" diff --quiet -- pubspec.lock packages/chord_tui/pubspec.lock \
  || { echo "pub get changed a lock: stop" >&2; exit 1; }
(cd "$W" && dart test test/version_test.dart test/cli_test.dart)
git -C "$W" add -A
git -C "$W" commit -m "feat: chord in Dart, with its framework chord_tui"
signed "$W"
clean "$W"
```

Commit 2 copies the port's `docs/` whole; the TS `docs/` (CHD designs
and evidence, `docs/qa`, `docs/memory.md`, `docs/agent-capabilities.md`,
its decisions log, its guide and images) stays at `ts-final`.

### Phase 4: commit 3 (CI) and commit 4 (docs)

```bash
on_dart
# ci.yml: the cursor-cloud-acp job of §(b), with one more step after quality:
#   - run: bun test ./tests/scripts ./lint
# and check needing it; test/tool/workflow_test.dart as §(b).
(cd "$W" && actionlint .github/workflows/ci.yml && dart test test/tool/workflow_test.dart)
git -C "$W" add -- .github/workflows/ci.yml test/tool/workflow_test.dart
git -C "$W" commit -m "ci: one workflow for chord and cursor-cloud-acp"
signed "$W"

on_dart
# Only the lines that name the TypeScript workspace (section 6, commit 4):
git -C "$W" add -- AGENTS.md CONTRIBUTING.md docs/decisions.md \
  .chord/teams/*.md .github/pull_request_template.md
git -C "$W" commit -m "docs: cursor-cloud-acp beside chord"
signed "$W"
clean "$W"
```

### Phase 5: verification in W

```bash
on_dart
command -v bun && command -v node && command -v expect && command -v actionlint
cd "$W"
bun install --frozen-lockfile
(cd packages/chord_tui && dart pub get) && dart pub get
clean "$W"
dart analyze && (cd packages/chord_tui && dart analyze)
dart format --output=none --set-exit-if-changed .
actionlint .github/workflows/ci.yml
caffeinate -dimsu dart test
(cd packages/chord_tui && caffeinate -dimsu dart test)
caffeinate -dimsu dart test -t compile --run-skipped
(cd packages/chord_tui && caffeinate -dimsu dart test -t compile --run-skipped)
(cd packages/chord_tui && dart test -t publish --run-skipped)   # dry run of committed HEAD
bun dev quality cursor-cloud-acp
bun test ./tests/scripts ./lint
bun dev release --help
dart run tool/release.dart --help
clean "$W"
cd - >/dev/null
```

The full suites' own skips are whatever they are on main today
(platform-only cases, `lsof`), and they are reported with their reasons.

`git log --oneline main..dart` in `C` now shows exactly the four commits,
each signed. The lead reports `dart` and its head to main. Nothing is
pushed.

### Phase 6: the owner

```bash
set -euo pipefail
# Same start folder and variables as above.
git -C "$C" log --stat --show-signature main..dart          # review
git -C "$C" push origin ts-final dart
gh pr create -R IKatsuba/chord --base main --head dart \
  --title "chord in Dart" --body "<summary>"
# Wait for check on the PR. Do not merge on GitHub: rebase and squash
# rewrite the signed commits, and a merge commit adds one that is not the owner's.
git -C "$C" switch main
git -C "$C" merge --ff-only dart
git -C "$C" push origin main          # direct push to main is allowed (Q399)
gh run watch -R IKatsuba/chord "$(gh run list -R IKatsuba/chord --branch main -L 1 --json databaseId -q '.[0].databaseId')"

# Release 0.72.0, from C on main, nothing else releasing:
clean "$C"
test -z "$(ls -A "$C/.release" 2>/dev/null)"
test ! -e "$COMMON/chord-release.lock"
(cd "$C" && bun install --frozen-lockfile)    # prunes 0.71.0's node_modules
(cd "$C/packages/chord_tui" && dart pub get) && (cd "$C" && dart pub get)
clean "$C"
(cd "$C" && dart run tool/release.dart chord --bump 0.72.0)
#   npm asks five times: four platform packages, then @chorded/chord.
signed "$C"                                    # the bump commit
gh release view v0.72.0 -R IKatsuba/chord      # draft with four archives
gh release edit v0.72.0 -R IKatsuba/chord --draft=false

# The tap, from the owner's clone of IKatsuba/homebrew-tap:
TAP=<tap clone>
clean "$TAP"
git -C "$TAP" pull --ff-only
cp "$C/build/release/chord.rb" "$TAP/Formula/chord.rb"
git -C "$TAP" add -- Formula/chord.rb
git -C "$TAP" commit -m "chord 0.72.0"
signed "$TAP"
git -C "$TAP" show --stat HEAD                 # one file, Formula/chord.rb
ruby -c "$TAP/Formula/chord.rb"
git -C "$TAP" push origin HEAD
brew update && brew install ikatsuba/tap/chord && brew test chord && chord --version

git -C "$C" worktree remove "$W"
```

## 8. Risks and their checks

| # | Risk | Check |
| --- | --- | --- |
| 1 | The release refuses `--bump 0.72.0` while the held version (0.0.1) is unpublished | CTUI-191 sets 0.71.0 in both pubspecs, `lib/version.dart` and `pubspec.lock` (Q396; `chord_tui` goes 0.0.1 → 0.71.0 → 0.72.0), and the live-version tests read `version` (`test/cli_test.dart`, `test/tool/dev_test.dart`; the "chord v0.0.1" in `test/ui/app/wheel_window_test.dart` and `error_window_test.dart` is their fixture launches' version (`version: '0.0.1'` in the launch each imports: `window_layout_test.dart`'s for the wheel test, `window_fake_test.dart`'s for the error test), and stays); phase 0 gates both; `test/version_test.dart` in phase 3 |
| 2 | Users' shared state | same XDG paths and file formats both ways, upgrade and downgrade (settings, keybindings, notices, records v1, teams; file:line in the interface draft, section 10); in phase 5, the records the TypeScript chord wrote, pinned under `test/fixtures/records/` (`original.jsonl` with `original_oracle.json`, `replay_supported.jsonl` with `replay_oracle.json`) and read by `test/session/record_test.dart`, `sessions_test.dart`, `recording_test.dart` and `replay_test.dart`, and the settings/teams/notices tests. The live two-way interchange test (`record_interchange_test.dart`) needed the TypeScript chord and goes with parity (Q397). YAML 1.1 edge scalars in hand-written team files read as npm `yaml` read them: a test in CTUI-191 |
| 3 | npm `@chorded/chord` 0.72.0 over 0.71.0 | same `bin`, the same four exact optional platform packages, same shim; platform `files` carry `LICENSE` and `NOTICES` instead of FFmpeg's; 0.71.0's `chord upgrade` installs it. `npm_test.dart` (layout, manifests, the shim under Node) in phase 5; after publish `npm view @chorded/chord@0.72.0 bin optionalDependencies` and `npx -y @chorded/chord@0.72.0 --version` on macOS and Linux |
| 4 | Homebrew bun → Dart | there is no chord formula in the tap today; 0.72.0's `chord.rb` is the first. `ruby -c`, `brew install`, `brew test`, `chord --version` in phase 6 |
| 5 | Linux binary floor | compare the highest `GLIBC_` symbol of the 0.72.0 linux-x64 binary with 0.71.0's (`objdump -T`) |
| 6 | Release preflight and origin | `originIsRelease` wants origin `IKatsuba/chord`: true in `../chord` only, so the release runs there after the merge; main level with origin once pushed; `v0.71.0` and `cursor-cloud-acp-v0.{1,2}.0` exist and are not the forms checked; phase 6 gates `.release` empty and no lock |
| 7 | The shared release lock | both tools lock `<git common dir>/chord-release.lock` and exclude each other (TS uses `stale: Infinity`, so it never removes Dart's file); the one mismatch is Dart's raw `FileSystemException` when TS holds its directory. Releases run one at a time; the message is a backlog item |
| 8 | Signed commits on main | GitHub rebase or squash rewrites them; phase 6 fast-forwards main locally and pushes directly (Q399); `signed` after every commit, the bump's and the tap's included |
| 9 | History | `ts-final` keeps the TS history, for reference only (Q387); `dart` is four commits on top of TS main; this repository's history is not imported (owner's call, already made); the swap commit names the port commit it copied. Code comments citing `CHD-` keys and the original cite `ts-final` |
| 10 | Public repository loses the TS privacy test (no home paths in tracked files) | follow-up task: a Dart equivalent |
| 11 | User-visible differences | no FFmpeg; SIGUSR2 writes a report, no heap snapshot in the release binary; `OPENTUI_FORCE_*` stop working (Q393); listed in the release notes, headed "rewritten in Dart" (Q394) |

## 9. Tasks this design creates

- **Pre-swap task CTUI-191 (chorded-tui), the swap's gate:** parity and
  oracle tests removed with every Bun and TS-original dependency (Q397);
  live-version tests read `version`, 0.71.0 in both packages (Q396); a
  YAML 1.1 team-file read test; `tool/screenshots.dart`, the port of the
  TS screenshot tool through the fake, and all twelve `docs/images/`
  retaken with it (Q392); README from the TS pitch, `docs/development.md`,
  `docs/guide.md` adapted line by line, AGENTS.md, CONTRIBUTING.md,
  FEATURES.md and `TRADEMARKS.md` for the new home (Q387, Q389, Q390).
- **The swap run:** phases 0 to 5, after CTUI-191 is on main.
- **Follow-ups (backlog):** prune the TS release engine to the package
  (L2) and the dead ESLint blocks; a Dart privacy test; the Dart lock's
  message for a TS-held lock.

## 10. Owner questions (board, CTUI-190)

| Id | Question | Answer |
| --- | --- | --- |
| Q387 | `ts-final` binding or history only | history only: the Dart chord is its own spec |
| Q388 | board project after the swap | keep CTUI |
| Q389 | `docs/guide.md` | keep and adapt to the Dart chord |
| Q390 | README base | the TS pitch; development content to `docs/development.md` |
| Q391 | TS history in the tree | nothing moves (CHD designs, decisions, evidence, qa, memory stay at `ts-final`); the guide is the exception |
| Q392 | README screenshots | retake all, through the fake agent |
| Q393 | `OPENTUI_FORCE_*` | 0.72.0 release notes only |
| Q394 | release notes headline | "rewritten in Dart" |
| Q395 | root `package.json` name | `chord-workspace` |
| Q396 | version bootstrap 0.71.0, framework included | yes |
| Q397 | CI parity | none: parity and oracle tests removed before the swap |
| Q398 | CI triggers | main + pull requests |
| Q399 | landing `dart` with signed commits | direct push to main is allowed |
| Q400 | `.zed`, `.git-blame-ignore-revs` | keep both |
