# CTUI-190 framework draft: repository and build layout

Read as the brief asks for this role: the inventory of `../chord` at
`577b58167`, the merged tree, the copy and its excludes, the TypeScript root
config that stays for `packages/cursor-cloud-acp`, and how the two trees'
docs, teams and local folders coexist. Facts below were checked by reading
and by trials in scratch copies outside both repositories; nothing was
written under `../chord`.

## Summary

- The swap is a replacement of everything TS-app-shaped (`src/`, `tests/`,
  `steps.ts`, most of `scripts/`, the app's dependencies) by the port's
  tracked tree, plus a **reduced** TS root kept only for
  `packages/cursor-cloud-acp`.
- Only 18 tracked paths exist on both sides; 7 are byte-identical, the rest
  take the port's version (one, `.gitignore`, must be a union). No path under
  `docs/design/`, `test(s)/`, `lib`/`src`, `tool`/`scripts` or `packages/`
  collides: CHD-* and CTUI-* keys never meet.
- Two hard breaks found by trial, each with a small fix:
  1. `bun dev` dies on any command once `packages/chord_tui` exists: its
     package finder globs the workspace pattern `packages/*` and reads every
     folder's `package.json` (ENOENT). Fix: the workspace list names
     `packages/cursor-cloud-acp` alone.
  2. `bun test` in the package fails while `bunfig.toml` preloads
     `./tests/colour.ts`, which leaves with `tests/`. Fix: drop the
     `[test] preload`.
- A third, structural: `bun dev`'s finder always counts the root `.` as a
  package that must have a `steps.ts` with a publish stage and an `@chorded/`
  name. With the TS app gone the root has nothing to publish. Fix trialled:
  the finder counts `.` only when a root `steps.ts` exists (a one-line
  change in `scripts/dev/steps.ts`), and the root `steps.ts` is deleted.
- With those three, the trialled reduction passes
  `bun dev quality cursor-cloud-acp` in full (types, tooling types, covered,
  eslint, format, 310 tests, build, smoke) beside the port, while
  `dart pub get`, `dart analyze` (root and framework) and
  `dart format --set-exit-if-changed .` stay clean in the same tree.
- The copy should come from `git archive` of the port's committed `main`,
  not a filesystem copy: it carries tracked files only, so build output,
  tool caches, worktrees, local settings and the maintainer's uncommitted
  edits are left out by construction; the remaining exclude list is short.

## Method (commands, temp paths omitted)

```sh
git -C ../chord ls-tree --name-only 577b58167          # top level
git -C ../chord ls-tree -r --name-only 577b58167 > ts.txt
git ls-files > port.txt                               # this repo, CTUI-190
comm -12 <(sort port.txt) <(sort ts.txt)              # exact collisions
git -C ../chord archive 577b58167 | tar -x -C <scratch>
# in <scratch>: git init, commit, bun install --frozen-lockfile,
# bun dev quality cursor-cloud-acp (baseline: passes)
mkdir -p packages/chord_tui && echo 'name: chord_tui' > packages/chord_tui/pubspec.yaml
bun dev quality cursor-cloud-acp     # fails: ENOENT packages/chord_tui/package.json
# then the reduction below, bun install (lock rewritten), quality again: passes
git -C <this repo> archive main | tar -x -C <scratch>  # the port over it
dart pub get && dart analyze && dart format --output=none --set-exit-if-changed .
(cd packages/chord_tui && dart pub get && dart analyze)
bun dev quality cursor-cloud-acp     # passes again, exit 0
```

The import graph from `packages/cursor-cloud-acp` into the root was taken
by a small Deno walker over static and dynamic relative imports (output in
"The package's reach into the root").

## Inventory of `../chord` at 577b58167

Verdicts: **drop** (gone from the tree; still at `ts-final` and in history),
**port** (replaced by the port's file of the same role), **keep**
(unchanged), **reduce** (kept, cut down), **merge** (both sides' content).

### Top level

| Path | Verdict | Reason |
| --- | --- | --- |
| `.chord/` | port | see `.chord/teams` below |
| `.git-blame-ignore-revs` | keep | names two reformat commits of TS history; history stays, so it stays valid and harmless |
| `.github/` | port + merge | see below |
| `.gitignore` | merge | union; the port's alone would let `git add -A` take `node_modules/` (19 269 files in the trial) and `packages/cursor-cloud-acp/dist/` |
| `.npmrc` | keep | `@jsr` registry: `@cliffy/command` (kept, used by `scripts/dev.ts` and `release/select.ts`) installs from it |
| `.prettierignore` | keep | still used by `bun fmt` on the package; `docs/`, `*.md`, `dist/`, `npm/` lines stay true |
| `.prettierrc.json` | keep | the package's format check |
| `.puppeteerrc.json` | drop | only for `puppeteer-core`, used by `scripts/dev/screenshots.ts` (dropped) |
| `.zed/settings.json` | keep | Prettier as formatter for JS/TS/TSX; still true for the package; owner may drop (question 7) |
| `AGENTS.md` | port | rewritten for the new home (interface's outline) |
| `CODE_OF_CONDUCT.md` | keep | identical on both sides |
| `CONTRIBUTING.md` | port | port's version, rewritten for the new home |
| `LICENSE` | keep | identical |
| `README.md` | port | port's README; it needs `docs/images/` (below) |
| `SECURITY.md` | keep | identical |
| `TRADEMARKS.md` | port, fixed | port's names `example/chord/lib/ui/header/mark_rows.dart`, a path that no longer exists; it is `lib/ui/header/mark_rows.dart` |
| `bun.lock` | reduce | rewritten by one non-frozen `bun install` after `package.json` is cut (617 → 390 installed packages in the trial); frozen from then on |
| `bunfig.toml` | reduce | drop `[test] preload = ["./tests/colour.ts"]` (break 2); keep `linker = "hoisted"`, the `@jsr` scope and `[run] bun = true` (eslint runs on Bun through it) |
| `docs/` | merge | see below |
| `eslint.config.ts` | keep (reduce optional) | the package imports `shared`, `forbid`, `TOOLING` from it; its default export's `src/**` blocks become dead but harmless |
| `lint/` | keep | `lint/style.ts` is the `style` plugin `shared` loads; `lint/style_test.ts` and `lint/config_test.ts` pass in the reduced tree (60 pass) |
| `package.json` | reduce | not the app any more; see "Root package.json" |
| `packages/` | merge | `cursor-cloud-acp` stays; `chord_tui` arrives |
| `scripts/` | reduce | see below |
| `src/` | drop → port | the app; the port's `lib/` and `bin/` replace it. One file is needed by the kept release tooling: `src/channel.ts` (see scripts) |
| `steps.ts` | drop | chord's TS checks and bun-compile release; the Dart release is `tool/release.dart`. Needs the finder change (break 3) |
| `tests/` | drop → port, partly kept | the app's tests; the port's `test/` replaces them. `tests/scripts/dev/**` test the kept release tooling: see scripts |
| `tsconfig.json` | reduce | `include: ["scripts/", "lint/", "eslint.config.ts"]`; drop `jsx`, `jsxImportSource`, `paths` (convert-layout) and the `files` list of `.tsx` tests |

Untracked in `../chord` (never part of a commit, absent from a fresh
worktree): `dist/`, `npm/`, `node_modules/`, `.release/` (empty in the
owner's checkout at the time of reading, so no unfinished TS release state),
`.claude/settings.local.json`, `.claude/worktrees/`.

### `docs/`

| Path | Files | Verdict | Reason |
| --- | --- | --- | --- |
| `docs/FEATURES.md` | 1 | port | the port's map; the TS one (OpenTUI, `src/registry.ts` rows) describes the TS build |
| `docs/decisions.md` | 1 | port; TS's moved or dropped | owner question 2; both are append-only logs of different builds (TS 8 957 lines, port 4 384) |
| `docs/guide.md` | 1 | keep (interface decides wording) | the user guide; 20 places in the port already cite it as the spec; 42 lines name `bun`/`src/` and need the port's words |
| `docs/agent-capabilities.md` | 1 | keep, paths fixed | facts about agents over ACP, independent of the build; its `src/registry.ts`/`src/clis.ts` become `lib/registry.dart`/`lib/clis.dart` (both exist) |
| `docs/memory.md` | 1 | drop (question 3) | TS heap tooling (`bun dev memory`, memlab); the port has `lib/platform/heap.dart` and its own decisions entries |
| `docs/images/` | 12 | keep | the port's README already links `logo-dark/light`, `team`, `start`, `edit`, `permission`, `agents`, `subagents`, `proposal`, `resume` and tracks none of them; without this folder the README breaks |
| `docs/design/CHD-*.md` | 105 entries, ~1.9 MB | keep (question 1) | no name collision with CTUI-*; the port's files cite CHD keys in 99 files (11 under `lib/`); keeping makes those resolve in-tree |
| `docs/design/evidence/CHD-*` | 9 660 files, ~151 MB | question 1 | captures of the TS app; no collision with `evidence/CTUI-*` |
| `docs/qa/` | 11 901 files, ~49 MB | question 1 | TS QA captures |

Deleting history-only folders shrinks the working tree, not the clone:
the TS history stays (pack 178 MiB), so every blob remains in `.git`.
The choice is about what a contributor sees, not about size.

### `scripts/` (37 files)

`bun dev` must keep `quality`, `lint` and `release` for the package. The
walker's closure from the package (`steps.ts`, `scripts/tools.ts`,
`eslint.config.ts`, its tests) plus `bun dev`'s `release` path
(`release/lib.ts`, `release/stages.ts`) and `covered.ts`:

```
scripts/dev/steps.ts         scripts/dev/covered.ts
scripts/dev/compile.ts       scripts/targets.ts
scripts/dev/release/{authenticate,build,bump,continue,lib,lock,notarise,
  pack,preflight,publish,select,selftest,sign,source,stages,state,sums,
  version}.ts
src/channel.ts               package.json (JSON import by compile.ts)
lint/style.ts                eslint.config.ts
```

`release/stages.ts` imports every stage module, chord's too (compile,
natives, sign, notarise, selftest, source archives), so they stay unless
`stages.ts` is pruned. Two levels:

- **L1, for the swap (trialled):** keep every `scripts/dev/release/*` but
  `pins.ts` (it imports `src/chorded.ts`, used only by chord's preflight);
  keep `compile.ts`, `targets.ts`, `scripts/macos/chord.entitlements`
  (`sign.ts` reads it); move `src/channel.ts` to
  `scripts/dev/release/channel.ts` and point its six importers at it
  (`bump`, `preflight`, `publish`, `source`, `version`, `stages`; two tests too); cut `scripts/dev.ts` to `quality`, `lint`, `release` and its
  help. Drop `scripts/dev/{mark,memory,npm,registry,screenshots,social,
  tools,jsx_dev_runtime}.ts`, `screenshots_{proposal,team}.md`,
  `scripts/format.ts`, `scripts/mark.svg`. `scripts/AGENTS.md`: reduce to
  the three commands.
- **L2, later task:** prune chord-only stages from `stages.ts`, then drop
  `compile.ts`, `targets.ts`, `notarise`, `sign`, `selftest`, `source`,
  the entitlements. Not needed for the swap; more edits, more risk.

The kept tooling's own tests are under `tests/scripts/` (27 files).
Restored into the reduced tree, 557 pass; 4 files fail only on imports of
dropped files: `tests/channel_test.ts` and `release/publish_test.ts`
(`src/channel.ts` path), `release/stages_test.ts` (chord's root
`steps.ts`), `compile_test.ts` (needs `react`). Recommendation: keep
`tests/scripts/dev/{covered,steps}_test.ts` and
`tests/scripts/dev/release/*_test.ts` (minus `pins_test.ts`) at the same
paths, fix the four, and run them from the package's or a root tooling
check, else the release code the package depends on loses its tests.
Where they run is runtime's call; that they exist is layout's.

`scripts/dev.ts`'s `chord`/`test`/`qa`/`compile`/`npm`/`registry`/`mark`/
`screenshots`/`social`/`memory`/`selftest` commands go: their Dart
counterparts are `tool/dev.dart`, `dart test`, `tool/release.dart`,
`tool/npm.dart`. After the cut, root `bun check` over the reduced
`tsconfig.json` reported errors only in the not-yet-cut `scripts/dev.ts`
(10, all TS2307 on dropped modules); every other kept file type-checks.

### `.github/`

| Path | Verdict |
| --- | --- |
| `FUNDING.yml`, `ISSUE_TEMPLATE/{bug,config,feature}.yml` | keep: identical on both sides |
| `pull_request_template.md` | port: differs in two checklist lines (AGENTS.md section name; screenshots via `bun dev screenshots` → captures at 120x40 and 80x24) |
| `workflows/ci.yml` | merge: the port's jobs plus the TS `node` job, one `check` (runtime's design). `test/tool/workflow_test.dart` reads this file and must learn the node job |

### `.chord/teams`

Both trees track exactly `architects.md` and `ship.md`; same names,
different text (port: +105/−84 and +208/−181 against TS). The port's
replace them; they say "beside ../chord", so they are rewritten with
AGENTS.md. The maintainer's local, untracked `.chord/teams/scratch-pair.md`
is not in `git archive` and does not travel.

### `.claude`

Tracked on neither side. Local only: `.claude/worktrees/` (TS checkout),
`settings.local.json`, `scheduled_tasks.lock` (port checkout). Nothing to
merge; the union `.gitignore` covers `.claude/settings.local.json` and
`.claude/worktrees/`. A shared tracked `.claude/settings.json` is out of
scope.

### `lint/`, `.zed`

Covered above: `lint/` stays whole (3 files); `.zed` stays.

### `packages/`

`packages/cursor-cloud-acp` (42 files) stays untouched. Its links to the
root are exactly: `eslint.config.ts` (`../../eslint.config.ts`),
`steps.ts` and `tests/steps_test.ts` (`../../scripts/dev/steps.ts`),
`scripts/tools.ts` (`release/{build,lib,publish,sums}.ts`,
`dev/steps.ts`), `@modelcontextprotocol/sdk` (a root dependency),
and the hoisted `node_modules`. `packages/chord_tui` arrives beside it;
neither tool sees the other once the workspace list is narrowed (bun) and
since pub reads only `pubspec.yaml` (`chord_tui` is a path dependency, no
pub workspace).

## Name collisions, file by file

`comm -12` of both `ls-files` lists: 18 paths.

| Path | Same bytes | Result |
| --- | --- | --- |
| `.github/FUNDING.yml` | yes | either |
| `.github/ISSUE_TEMPLATE/bug.yml` | yes | either |
| `.github/ISSUE_TEMPLATE/config.yml` | yes | either |
| `.github/ISSUE_TEMPLATE/feature.yml` | yes | either |
| `CODE_OF_CONDUCT.md` | yes | either |
| `LICENSE` | yes | either |
| `SECURITY.md` | yes | either |
| `.github/pull_request_template.md` | no | port |
| `.github/workflows/ci.yml` | no | merged (runtime) |
| `.gitignore` | no | union |
| `.chord/teams/architects.md` | no | port, rewritten |
| `.chord/teams/ship.md` | no | port, rewritten |
| `AGENTS.md` | no | port, rewritten (interface) |
| `CONTRIBUTING.md` | no | port, rewritten (interface) |
| `README.md` | no | port (needs `docs/images/`) |
| `TRADEMARKS.md` | no | port, path fixed |
| `docs/FEATURES.md` | no | port |
| `docs/decisions.md` | no | port; TS's per question 2 |

No directory-level surprises: `test/` vs `tests/`, `tool/` vs `scripts/`,
`lib/` vs `src/`, `docs/design/CTUI-*` vs `CHD-*`,
`docs/design/evidence/CTUI-*` vs `evidence/CHD-*` are disjoint. Neither
tree tracks symlinks or submodules, and neither has `.gitattributes`
(so `git archive` applies no `export-ignore`).

## The merged tree

```text
.chord/teams/{architects,ship}.md    the port's, rewritten
.github/                             port's; ci.yml with the node job
.gitignore                           union (below)
.git-blame-ignore-revs .npmrc .prettierignore .prettierrc.json .zed/
AGENTS.md CONTRIBUTING.md README.md TRADEMARKS.md    the port's, rewritten
CODE_OF_CONDUCT.md LICENSE SECURITY.md               unchanged
analysis_options.yaml dart_test.yaml pubspec.yaml pubspec.lock
bin/ lib/ test/ tool/ benchmark/     the port
docs/
  FEATURES.md decisions.md           the port's
  guide.md agent-capabilities.md     kept, wording for the port
  images/                            kept (README)
  design/CTUI-*.md evidence/CTUI-*   the port's
  design/CHD-*  evidence/CHD-*  qa/  per question 1
packages/
  chord_tui/                         the framework (pub)
  cursor-cloud-acp/                  unchanged (bun, npm)
package.json bun.lock bunfig.toml tsconfig.json eslint.config.ts
lint/                                the package's TS root
scripts/dev.ts scripts/dev/          quality, lint, release only
```

The TS root files are not moved under a subfolder: the package's
`../../eslint.config.ts`, `../../../scripts/...` imports and the hoisted
root `node_modules` fix them at the root. Moving them (e.g. into
`packages/cursor-cloud-acp/tooling/`) is possible later but edits the
package itself, which the brief keeps unchanged.

`.gitignore`, merged:

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

`packages/chord_tui/.pubignore` repeats what git ignores; it already lists
`.dart_tool/ build/ *.exe .release/ .DS_Store`, and none of the TS-only
lines can occur inside that folder, so it needs no change.

## The copy and its excludes

Source of truth: `git archive main` of this repository (after CTUI-190 and
anything else is merged), extracted over the `dart` worktree of `../chord`
after the dropped paths are removed with `git rm`. Why not `rsync`/`cp` of
the checkout:

- it takes tracked files only: `.dart_tool/`, `build/`, `example/` (an
  ignored local folder in the main checkout), `packages/chord_tui/.dart_tool/`,
  `.claude/`, `.DS_Store` and any worktree are out without being listed;
- it takes the committed state: the maintainer's uncommitted `.gitignore`
  edit and the untracked `.chord/teams/scratch-pair.md` do not leak in;
- it is reproducible from a commit id, which the swap commit can name.

The trial copy was 13 839 files, 74 MB (54 MB of it
`docs/design/evidence/`).

What `git archive` would still bring and must be excluded or replaced
after extraction:

| Path | Action |
| --- | --- |
| `.gitignore` | overwritten by the union above |
| `docs/decisions.md`, `docs/FEATURES.md`, `AGENTS.md`, `README.md`, `CONTRIBUTING.md`, `TRADEMARKS.md`, `.chord/teams/*`, `.github/pull_request_template.md`, `.github/workflows/ci.yml` | the port's, then rewritten in their own commits |

Nothing else needs excluding. If the owner instead prefers a filesystem
copy, the exclude list is: `.git`, `.dart_tool/`, `**/.dart_tool/`,
`build/`, `example/`, `.release/`, `.claude/`, `node_modules/`, `dist/`,
`*.exe`, `.DS_Store`, and every untracked file (`git ls-files --others`).

Order inside the `dart` worktree, as a later run executes it:

```sh
git rm -rq src tests steps.ts .puppeteerrc.json docs/memory.md \
  docs/FEATURES.md docs/decisions.md            # decisions: per question 2
git rm -q scripts/dev/{mark,memory,npm,registry,screenshots,social,tools,jsx_dev_runtime}.ts \
  scripts/dev/screenshots_{proposal,team}.md scripts/format.ts scripts/mark.svg \
  scripts/dev/release/pins.ts
git checkout HEAD -- tests/scripts/dev        # if kept (scripts section)
git -C ../chorded-tui archive <port-main> | tar -x -C .
# then: .gitignore union, package.json/bunfig/tsconfig/dev.ts/steps.ts finder edits,
# channel.ts move, bun install, commit
```

## Root `package.json`

Trialled shape:

```json
{
  "name": "<owner question 5>",
  "private": true,
  "license": "MIT",
  "type": "module",
  "workspaces": ["packages/cursor-cloud-acp"],
  "engines": { "bun": ">=1.4.4" },
  "scripts": { "dev": "bun scripts/dev.ts" },
  "dependencies": {
    "@cliffy/command": "npm:@jsr/cliffy__command@^1.3.1",
    "@modelcontextprotocol/sdk": "^1.32.1",
    "@zod/zod": "npm:zod@^4.6.5",
    "globby": "^16.2.4",
    "proper-lockfile": "^4.1.2",
    "semver": "^7.8.6",
    "shell-quote": "^1.8.3"
  },
  "devDependencies": {
    "@eslint-community/eslint-plugin-eslint-comments": "^4.8.1",
    "@eslint/js": "^10.0.1",
    "@types/bun": "^1.4.4",
    "@types/node": "^26.6.6",
    "@types/proper-lockfile": "^4.1.4",
    "@types/semver": "^7.8.0",
    "@types/shell-quote": "^1.7.5",
    "@typescript-eslint/utils": "^8.72.2",
    "eslint": "^10.15.0",
    "eslint-plugin-react": "^7.37.5",
    "eslint-plugin-react-hooks": "^7.1.1",
    "jiti": "^2.7.0",
    "typescript": "npm:@typescript/typescript6@^6.0.2",
    "typescript-eslint": "^8.72.2"
  }
}
```

- No `version`: nothing releases the root.
- The workspace list is explicit; a glob would meet `packages/chord_tui`
  again (break 1).
- React's two ESLint plugins stay because `shared` turns their rules on;
  without `react` installed the `version: 'detect'` setting caused no
  failure in the trial. Dropping the react rules from `shared` is an
  ESLint-config edit for a later task.
- npm name clashes: the Dart release publishes `@chorded/chord` and
  `@chorded/chord-{darwin,linux}-{arm64,x64}`; the TS release publishes
  `@chorded/cursor-cloud-acp`. With the finder change the root's name is
  never read by `bun dev`, and `private: true` keeps npm from publishing
  it, so any name that is none of those six is safe. Keeping
  `@chorded/chord` there would not publish anything but would put two
  manifests named `@chorded/chord` in one tree (this and
  `build/release/npm/chord/package.json` during a release); not
  recommended.

## How the two trees' records coexist

- **`docs/design/`:** one folder, two key spaces. CTUI-n are the port's,
  CHD-n the TS app's; `evidence/<key>/` likewise. A new design keeps using
  CTUI-n (the board project). Nothing renames.
- **`docs/decisions.md`:** the port's is the live log. The TS log is not
  appended to again. Options in question 2.
- **`docs/FEATURES.md`:** the port's.
- **Board history:** the board lives outside the repository; CHD (TS) and
  CTUI (port) keys stay distinct, so references from either tree's files
  remain unambiguous.
- **`.release/` and the release lock:** the Dart release keeps
  `.release/chord/`, the TS release `.release/cursor-cloud-acp/`; no
  overlap. Both take their lock at the same path,
  `<git common dir>/chord-release.lock` (Dart: an exclusively created
  file; TS: proper-lockfile's directory). Each refuses while the other's
  exists, so the two releases exclude each other; the error text names the
  other's path. A note for runtime, not a change.

## Hand-offs to the other drafts

- runtime: tests and oracle scripts that read `../chord` or `CHORD_SOURCE`
  (`test/registry_test.dart`, `test/fixtures/fake.dart`,
  `test/fixtures/fake_test.dart`, `test/tool/dev_test.dart`,
  `test/benchmark/record_scan_tester_test.dart`,
  `test/fixtures/prices/tester_probe.mjs`,
  `test/fixtures/steering_recovery/original_probe.ts`,
  `packages/chord_tui/test/text/fzf_golden.mjs` with
  `git -C <source> ls-files src tests`, `tool/genai_prices.dart` reading
  `../chord`'s `node_modules`): after the swap the sibling `../chord` is
  the Dart tree itself, so the default lookup finds no `src/`.
- runtime: where `tests/scripts/dev/**` run (root tooling check or the
  package's); `test/tool/workflow_test.dart` and the merged `ci.yml`.
- interface: 82 tracked files outside `docs/design/evidence/` name
  `../chord`; most are comments and design history that stay as written,
  the binding ones are AGENTS.md, README.md, CONTRIBUTING.md, FEATURES.md,
  `.chord/teams/*`, `dart_test.yaml` and `benchmark/acp_updates.dart`.
- One prunable worktree is registered in `../chord`'s git; pruning it is
  the owner's, before `git worktree add -b dart`.

## Cost

Per swap: one `git archive` (~74 MB extracted), one `bun install`
rewriting `bun.lock`, `dart pub get` in both Dart packages. Per CI run
afterwards: the node job installs 390 packages instead of 617. Per
contributor clone: unchanged (history keeps every TS blob).

## Owner questions

1. **TS design and QA history in the tree.** Keep `docs/design/CHD-*.md`
   (1.9 MB; the port cites CHD keys in 99 files), and separately
   `docs/design/evidence/CHD-*` (151 MB) and `docs/qa/` (49 MB) in the
   working tree, or drop them and point at `ts-final`? Recommendation:
   keep the CHD design notes, drop CHD evidence and `docs/qa/` (dropping
   them does not shrink the clone; it only declutters).
2. **The TS `docs/decisions.md`.** (a) keep it as
   `docs/decisions-ts.md` (or `docs/history/decisions.md`), frozen;
   (b) drop it, cite `ts-final:docs/decisions.md`; (c) append it below the
   port's log. Recommendation: (a), since port decisions and CHD designs
   cite its entries by title.
3. **`docs/memory.md`** (TS heap tooling): drop, or keep rewritten for
   `lib/platform/heap.dart`? Recommendation: drop.
4. **Tooling reduction level.** L1 (keep chord's bun release modules so
   `stages.ts` imports resolve; smallest edit) for the swap, L2 later?
   And keep `tests/scripts/dev/**` (with four import fixes) so the release
   code `cursor-cloud-acp` relies on stays tested? Recommendation: L1 and
   keep the tests.
5. **The root `package.json` name.** Private, never published, never read
   by `bun dev` after the finder change. Proposal: `chord-repository`
   (unscoped, so it cannot be mistaken for an `@chorded` package), or
   `@chorded/repository`. Must not be `@chorded/chord` or
   `@chorded/chord-<platform>`.
6. **`scripts/dev/steps.ts` change.** The finder counting `.` only when a
   root `steps.ts` exists is a behaviour change of the TS tooling (today a
   missing root `steps.ts` is an error). Alternative: a root `steps.ts`
   for a do-nothing root package, which the finder's rules forbid (a
   release needs a publish stage). Agree to the one-line change?
7. **`.zed/` and `.git-blame-ignore-revs`.** Keep both (recommendation),
   or drop `.zed/` as editor-specific?

## After the critic: the kept tooling tests

The lead's decisions, applied exactly in a fresh scratch export of
`../chord` at `577b58167` (`git archive | tar -x`): the finder's `'.'`
entry removed unconditionally, no root `steps.ts`; `src/channel.ts` moved
to `scripts/dev/release/channel.ts` and its six importers pointed at
`'./channel.ts'`; `eslint.config.ts` unchanged; runtime's reduced
`package.json` (`@chorded/workspace`, `workspaces:
["packages/cursor-cloud-acp"]`, seven dependencies, fourteen dev
dependencies); `bunfig.toml` without `[test]`; `tsconfig.json` reduced;
`scripts/dev.ts` edited only enough to load (its `../steps.ts` import and
the `CHORD` default's stages removed); a `packages/chord_tui/pubspec.yaml`
present. Everything under `tests/` outside `tests/scripts/` removed, but
`tests/channel_test.ts`, which moves (below).

### Dropped (8 files)

| File | Why |
| --- | --- |
| `tests/scripts/dev/npm_test.ts` | tests `scripts/dev/npm.ts`, dropped |
| `tests/scripts/dev/screenshots_test.ts` | `screenshots.ts` and `src/`, dropped |
| `tests/scripts/dev/social_test.ts` | `social.ts` and `src/`, dropped |
| `tests/scripts/dev/tools_test.ts` | `scripts/dev/tools.ts`, dropped |
| `tests/scripts/format_test.ts` | `scripts/format.ts`, dropped |
| `tests/scripts/dev/release/pins_test.ts` | `release/pins.ts` and `src/chorded.ts`, dropped |
| `tests/scripts/dev/compile_test.ts` | tests chord's bun compile: the OpenTUI `jsxDEV` shim (`jsx_dev_runtime.ts`, dropped; needs `react`) and OpenTUI native selection (needs `@opentui/core` installed). Trimmed to what loads, 8 of 10 cases still fail on the missing `@opentui/core`; the 2 left (`cursorInputs`, `EVERY_PLATFORM`) are not worth a file. `compile.ts` stays only as an import of `build.ts`/`source.ts` |
| `tests/scripts/dev_test.ts` | see "dev_test.ts" below: not dropped by choice, rewritten with `dev.ts` |

### Kept as they are (17 files, pass unchanged)

```
lint/config_test.ts                          33
lint/style_test.ts                           27
tests/scripts/dev/covered_test.ts            18
tests/scripts/dev/release/authenticate_test.ts 14
tests/scripts/dev/release/build_test.ts       3
tests/scripts/dev/release/bump_test.ts        3
tests/scripts/dev/release/lib_test.ts         9
tests/scripts/dev/release/lock_test.ts        7
tests/scripts/dev/release/notarise_test.ts    7
tests/scripts/dev/release/pack_test.ts        6
tests/scripts/dev/release/scratch_test.ts     2
tests/scripts/dev/release/select_test.ts     17
tests/scripts/dev/release/selftest_test.ts    5
tests/scripts/dev/release/sign_test.ts       10
tests/scripts/dev/release/source_test.ts     14
tests/scripts/dev/release/state_test.ts      31
tests/scripts/dev/release/version_test.ts    74
```

plus the helper `tests/scripts/dev/release/scratch.ts` (not a test).

### Kept with a fix (4 files)

1. **`tests/channel_test.ts` → `tests/scripts/dev/release/channel_test.ts`**
   (moved beside the module it tests). One import:
   `'../src/channel.ts'` → `'../../../../scripts/dev/release/channel.ts'`
   (Prettier then wraps the import). 49 pass.
2. **`tests/scripts/dev/release/publish_test.ts`.** Two imports:
   `'../../../../src/channel.ts'` →
   `'../../../../scripts/dev/release/channel.ts'`;
   `import chordSteps from '../../../../steps.ts'` →
   `'./fixtures/chord_steps.ts'` (the fixture, below). Its cases use only
   chord's publish entry (npm names, `v{version}`, `githubRelease`). 70 pass.
3. **`tests/scripts/dev/release/stages_test.ts`.** It drives
   `runRelease` (state, resume, guards, bump, channel, publish) through
   chord's full stage list; pointing it at cursor-cloud-acp's `steps.ts`
   would rewrite most of its 186 cases (other stage names, no `machine`,
   `ready`, `githubRelease`), and would lose the cases the package's list
   cannot reach. So it keeps chord's list as a fixture:
   - `import chordSteps from '../../../../steps.ts'` and
     `const STEPS = new URL('../../../../steps.ts', import.meta.url)` →
     `'./fixtures/chord_steps.ts'`;
   - `import { CHORDED_AGENTS } from '../../../../src/chorded.ts'` goes,
     with the `beforeEach` loop that wrote each pinned agent into the fake
     npm's `published/` (it served only chord's pins preflight, which the
     fixture no longer has).
   No case is dropped; 186 pass.
4. **`tests/scripts/dev/steps_test.ts`.** 7 of 27 cases assumed the root
   is a package. Each, precisely:
   - "the root alone is chord, by its npm name without the scope" →
     "the root is never a package, steps.ts or not": `pkg('.', ...)`,
     `expect(await packages(root)).toEqual([])`.
   - "the root, then its workspaces' packages in order" → "its
     workspaces' packages in order, the root not among them": expected
     folders lose `'.'`.
   - "two packages of one name are refused": `packages/a` and
     `packages/b` both `@chorded/a`; message
     `"packages/b: @chorded/a is also packages/a's name"`.
   - "a steps file that does not load is named": the broken `steps.ts` is
     `packages/a/steps.ts` under a root with `workspaces: ['packages/*']`;
     message `'packages/a/steps.ts: broken on purpose'`.
   - "a type error in a package's tooling fails its quality, never
     chord's" → "... never another's": the root's passing `types` check
     moves into a second workspace package `packages/fine` (`@chorded/fine`,
     the same `bun check` over the root `tsconfig.json`);
     `const [acp, fine] = await packages(root)`, `run(fine)` is 0,
     `run(acp)` is not.
   - tester "workspace objects honor exclusions ...": expected names
     `['a']`.
   - tester "discovery imports definitions without running checks or
     stages": the lazy `steps.ts` is `packages/a/steps.ts` under a root
     with workspaces; `packages(root)[0]` is `a`.
   27 pass.

**The fixture**, new:
`tests/scripts/dev/release/fixtures/chord_steps.ts` is today's root
`steps.ts` with its three `./scripts/dev/...` imports rewritten to
`../../../../../scripts/dev/...` and its `preflight` (pins) removed;
nothing else. It is a test fixture only: nothing under `scripts/` imports
it, and `bun dev` never finds it (it is not a workspace).

### `dev_test.ts`

`tests/scripts/dev_test.ts` (1 176 lines, 68 cases) tests `scripts/dev.ts`'s
whole CLI with `chord` as its package argument throughout, and imports
`strip-ansi` (not in the reduced `package.json`). It cannot be fixed apart
from runtime's cut of `dev.ts`, so it was not run in this trial. The
rewrite, in the same commit as the `dev.ts` cut:
- keep the describes `quality`, `lint`, `release`, `a bare release`,
  `release --bump`, `release --channel`, `tester: release parsing
  boundaries`, `tester: CHD-577 channel argument boundaries`, `tester:
  direct lint process boundaries`, `tester: CHD-623 package command
  boundaries`, and from `tester: CHD-411 forwarding boundaries` its `lint`
  case only;
- drop `compile`, `memory`, `chord`, `test`, `selftest`, `tester:
  migrated command boundaries`, and `a fake or QA run keeps chord's state
  off the person's (CHD-616)`;
- the package argument `chord` becomes `cursor-cloud-acp`, and
  `devCommand` gets its package list passed (no default any more); the
  expected enum text `"chord", "cursor-cloud-acp"` becomes
  `"cursor-cloud-acp"`;
- `import stripAnsi from 'strip-ansi'` → `Bun.stripANSI` (present in Bun
  1.4.4: checked, `Bun.stripANSI('\x1b[31mx\x1b[0m')` is `"x"`), so no
  dependency returns.

### One command, from the root

```sh
bun test ./tests/scripts ./lint
```

Trial: **612 pass, 0 fail, 21 files** (20 test files above plus
`channel_test.ts` moved; `dev_test.ts` set aside), about 150 s on an
arm64 Mac, most of it `stages_test.ts` and `publish_test.ts` running
scratch repositories. `dev_test.ts`, once rewritten, joins the same
command.

Alongside, in the same tree:

- `bun dev quality cursor-cloud-acp`: exit 0, 310 pass.
- `bunx eslint tests lint` (root config, unchanged): clean.
- `bun fmt --check tests lint scripts/dev`: clean after Prettier wraps the
  two long channel imports.
- `bun check` with `tsconfig.json`'s include widened to
  `["scripts/", "tests/", "lint/", "eslint.config.ts"]`: the kept tests
  and the fixture type-check; the only errors left are the 10 in the
  not-yet-cut `scripts/dev.ts`. So the reduced `tsconfig.json` should list
  `tests/` too, or the kept tests go unchecked (runtime's reduced list
  omits it).

Where this command runs (a root `bun dev` check has no home once the root
is not a package: a CI step in the node job, or a check in
cursor-cloud-acp's `steps.ts`) is runtime's call.
