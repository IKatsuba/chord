# CTUI-190 runtime draft: toolchain, CI, oracle, sequence, release

Owner of this draft: runtime. Scope: the brief's runtime questions (a) to
(e). Everything below was read at `../chord` main `577b58167` (= `v0.71.0`
= `origin/main`) and this repository's main `d9daa22d`. Claims marked
**proven** were run in a scratch export (`git archive 577b58167`, never
`../chord` itself); nothing was published, no npm login or whoami ran.

## Findings that change the plan

1. **The release refuses 0.72.0 unless the swap sets the version to
   0.71.0 first.** The port is at `0.0.1` (root and framework
   `pubspec.yaml`, `lib/version.dart`, `pubspec.lock`). Preflight step 2
   (`tool/release/preflight.dart`) refuses a new version while
   `@chorded/chord@<pubspec version>` is not on npm: `0.0.1` is not, so
   `--bump 0.72.0` dies with "@chorded/chord@0.0.1 is not published yet".
   The swap must write `0.71.0` into those four places (the framework too:
   `test/version_test.dart` holds them equal). Then `--bump 0.72.0` passes:
   `0.71.0` is published, `0.72.0` is above it and not on npm.
2. **`bun dev` crashes on `packages/chord_tui`** (proven). `bun install`
   ignores a workspace folder without `package.json` (proven: 617
   packages, exit 0), but `scripts/dev/steps.ts` `packages()` globs
   `packages/*` itself and reads each `package.json`: with
   `packages/chord_tui` present every `bun dev` command dies with ENOENT in
   `readManifest`. The root `package.json` must list
   `"workspaces": ["packages/cursor-cloud-acp"]` explicitly.
3. **`bun dev` treats the root as a package.** `packages()` starts with
   `'.'`, requires its name in the `@chorded/` scope and imports the root
   `steps.ts`, and `scripts/dev.ts` imports the root `steps.ts` statically
   for its default `chord` package. Both go: `packages()` lists the
   workspaces only, `devCommand` takes its packages without a default.
4. **No chord formula exists in the tap.** `IKatsuba/homebrew-tap` holds
   `Formula/flipbook.rb` and `Casks/roost.rb` only (public read through
   `gh api`). 0.72.0's `chord.rb` is chord's first formula: no Homebrew
   user moves from a bun binary to a Dart one. The brief's risk 7
   (formula migration) reduces to "a first formula installs and tests".
5. **The bunfig test preload points into `tests/`.** `bunfig.toml`
   preloads `./tests/colour.ts` for every `bun test`; once `tests/` goes,
   cursor-cloud-acp's tests would fail to start. The `[test]` section
   goes (the package uses no chalk).
6. **`src/channel.ts` is imported by six release modules** (`bump`,
   `preflight`, `publish`, `source`, `stages`, `version`), so one file of
   `src/` must survive: moved to `scripts/dev/channel.ts`.
7. **The two release tools share one lock path.** TS `lock.ts`
   (proper-lockfile, a directory) and Dart `tool/release/lock.dart` (an
   exclusive file) both lock `<git common dir>/chord-release.lock`. They
   exclude each other, which is right, but each reads the other's lock
   badly: Dart's `File.existsSync()` is false for TS's directory, so it
   rethrows a raw `FileSystemException` instead of "another release runs";
   proper-lockfile's stale check would try to remove Dart's file as a
   directory. Low risk (two releases at once in one clone); recorded as a
   backlog item, and the owner's steps run the two releases one after the
   other.

## (a) The TypeScript workspace cursor-cloud-acp needs

### What the package reaches outside its folder

Traced with a relative-import closure over every non-`src/` `.ts` file of
`packages/cursor-cloud-acp` (`steps.ts`, `eslint.config.ts`,
`scripts/tools.ts`, `tests/**`), plus `scripts/dev.ts` for `bun dev`:

| From the package | Reaches |
| --- | --- |
| `steps.ts` | `scripts/dev/steps.ts` (types); runs `bun scripts/dev/covered.ts`, eslint, `bun check`, `bun fmt`, `bun test` |
| `eslint.config.ts` | `../../eslint.config.ts` (`forbid`, `shared`, `TOOLING`) → `lint/style.ts` |
| `scripts/tools.ts` | `scripts/dev/release/{build,lib,publish,sums}.ts`, `scripts/dev/steps.ts`, `@modelcontextprotocol/sdk/types.js` |
| `tests/steps_test.ts` | `scripts/dev/steps.ts` (`isPublish`) |
| `tests/serve_test.ts` | runs `bun packages/cursor-cloud-acp/tests/fixtures/main.ts` from the root |

The release modules then pull in, transitively: `scripts/dev/release/*`
(all but `pins.ts`), `scripts/dev/compile.ts` (for `EVERY_PLATFORM` and
`loadedNative`; it imports the root `package.json` for `engines.bun`),
`scripts/targets.ts`, `scripts/macos/chord.entitlements` (read by
`sign.ts`), and `src/channel.ts`. `bun dev release` itself needs
`scripts/dev/release/{lib,stages,select}.ts`.

Bare packages the remaining tooling imports, all root dependencies today:
`@cliffy/command`, `@modelcontextprotocol/sdk`, `@zod/zod`, `globby`,
`proper-lockfile`, `semver`, `shell-quote`; dev: `eslint`, `@eslint/js`,
`@eslint-community/eslint-plugin-eslint-comments`, `eslint-plugin-react`,
`eslint-plugin-react-hooks`, `typescript-eslint`, `@typescript-eslint/utils`,
`jiti` (eslint loads a `.ts` config), `typescript`, `@types/bun`,
`@types/node`, `@types/proper-lockfile`, `@types/semver`,
`@types/shell-quote`. The package's own `package.json` keeps its runtime
dependencies (`@agentclientprotocol/sdk`, `@cursor/sdk`, ...).

### The reduced root (proven)

Kept as they are: `scripts/dev/steps.ts` (one line removed, below),
`scripts/dev/covered.ts`, `scripts/dev/compile.ts`,
`scripts/dev/release/*` but `pins.ts`, `scripts/targets.ts`,
`scripts/macos/chord.entitlements`, `eslint.config.ts`, `lint/style.ts`,
`.prettierrc.json`, `.prettierignore`, `.npmrc` (the `@jsr` registry
`@cliffy/command` comes from), `bunfig.toml` (less `[test]`).

Moved: `src/channel.ts` → `scripts/dev/channel.ts`; the six importers'
`'../../../src/channel.ts'` become `'../channel.ts'`.

Removed: `src/` (the rest), `tests/`, root `steps.ts`, `lint/config_test.ts`,
`lint/style_test.ts` (see open question R3), `scripts/dev/{tools,npm,
registry,mark,screenshots,social,memory,jsx_dev_runtime}.ts`,
`scripts/dev/screenshots_{proposal,team}.md`, `scripts/dev/release/pins.ts`,
`scripts/format.ts`, `scripts/mark.svg`, `.puppeteerrc.json`.

Edited:

- `scripts/dev.ts` (493 → 248 lines): only `quality`, `lint` and
  `release`; no `chordSteps` import, no `CHORD` default, no
  `qaDir`/`qaState`/`FAKE_STATE`, and `DevActions`/`RUN` without
  `compile`, `npm`, `registry`, `mark`, `screenshots`, `social`, `memory`,
  `selftest`, `chord`, `qa`, `test`. The examples that name `chord` are
  reworded to `cursor-cloud-acp`; the `RELEASE` text's "chord's runs on
  the owner's arm64 Mac" goes.
- `scripts/dev/steps.ts` `packages()`: the `'.'` entry is removed, so the
  root is not a package and its name is free of the scope rule.
- `package.json`:

  ```json
  {
    "name": "@chorded/workspace",
    "private": true,
    "license": "MIT",
    "type": "module",
    "workspaces": ["packages/cursor-cloud-acp"],
    "engines": { "bun": ">=1.4.4" },
    "scripts": { "dev": "bun scripts/dev.ts" },
    "dependencies": { "the seven above, at today's ranges" },
    "devDependencies": { "the fourteen above, at today's ranges" }
  }
  ```

  No `version`: it is never released. The name is an owner question (O1).
- `bun.lock`: regenerated by `bun install` (1559 → 881 lines), then
  `bun install --frozen-lockfile` from an empty `node_modules` passes
  (390 packages).
- `tsconfig.json`: `include` `["scripts/", "lint/", "eslint.config.ts"]`;
  `jsx`, `jsxImportSource`, `paths` and `files` go.
- `eslint.config.ts`: its default export's chord blocks (`src/session/**`,
  `src/**` forbids) are dead and go; `shared`, `forbid`, `TOOLING` stay.
  The react plugins in `shared` match nothing in the package and could go
  in a follow-up; kept now so the package's lint is unchanged.

Release stages that remain, by package: cursor-cloud-acp's own
(`install, quality, build, pack, publish`), as `bun dev release --help`
lists them. The chord-only code paths in `stages.ts`, `sign.ts`,
`notarise.ts`, `selftest.ts`, `pack.ts`, `compile.ts` stay compiled but
unreachable, because `build.ts`, `source.ts` and `stages.ts` import them;
pruning them to a generic release is a follow-up task, not part of the
swap (one change at a time; the swap keeps the package's release exactly
as tested).

Results in the scratch export, reduced tree plus this repository's tree
copied in and the merged `.gitignore` (below):

| Command | Result |
| --- | --- |
| `bun install --frozen-lockfile` | 390 packages, exit 0 |
| `bun dev quality cursor-cloud-acp` | types (14 + 51 files), covered, eslint, format, 310 tests pass, build, smoke: exit 0 |
| `bun dev lint cursor-cloud-acp` | exit 0 |
| `bun dev release --help` | stages `cursor-cloud-acp  install, quality, build, pack, publish` |
| `bun dev release` | "not clear which package to release ... (cursor-cloud-acp)", exit 1 |
| `dart pub get` (both), `dart analyze` (both) | no issues; root analyze 11 s with `node_modules/` present (it holds no `.dart`) |
| `dart format --output=none --set-exit-if-changed .` | 1530 files, 0 changed |
| `dart run tool/release.dart --help` | prints, exit 0 |
| `git status --porcelain --untracked-files=all` after all installs | empty |
| `dart test test/tool/{workflow,shards,npm,release}_test.dart test/fixtures/fake_test.dart test/registry_test.dart` | pass, 4 parity skips |

Not run: `bun dev release cursor-cloud-acp` in any form. Every run,
`--dry-run` included, authenticates npm after preflight; the package's
stage functions are covered by its own `tests/scripts/tools_test.ts`,
which passed inside quality, and by `build`/`smoke` in quality.

### npm names

After the swap, nothing in the tree claims `@chorded/chord` or
`@chorded/chord-<os>-<cpu>` but the port's `lib/distribution.dart`
(`npmPackage`, `platformPackage`) and `tool/npm.dart`: the root becomes
`@chorded/workspace` (private), the package is `@chorded/cursor-cloud-acp`,
`scripts/dev/npm.ts` (which laid out `npm/chord*`) is gone, and `npm/` is
ignored output. `bun.lock`'s workspace entry follows the root name. The
docs that still say `@chorded/chord` (README, guide) name the published
package, which is right.

### The merged `.gitignore`

Both release tools refuse a dirty tree (`git status --porcelain
--untracked-files=all` in Dart, `git status` in TS), so each one's
output must be ignored for the other:

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
```

`.release/` holds `.release/chord/` (Dart) and
`.release/cursor-cloud-acp/` (TS): disjoint names. `../chord/.release` is
empty today.

## (b) The combined CI workflow

One `.github/workflows/ci.yml`: this repository's, unchanged job by job,
plus the original's cursor-cloud-acp job under its own name, since `node`
is taken by the npm shim test. `check` keeps its name, which branch
protection requires.

| Job | Runs | From |
| --- | --- | --- |
| `static` | setup-dart 3.13.5; pub get both; analyze both; format check; actionlint | port |
| `tests (1/3..3/3)` | each package's shard through `tool/shards.dart` | port |
| `compile` | expect; both packages' `-t compile --run-skipped` | port |
| `node` | Node 22.13; `dart test test/tool/npm_test.dart` | port |
| `release` | `tool/ci.dart linux-x64`, `linux-arm64` | port |
| `cursor-cloud-acp` | checkout (no credentials); setup-bun 1.4.4; Node 22.13; `bun install --frozen-lockfile`; `bun dev quality cursor-cloud-acp` | original's `node` |
| `check` | needs all six, `if: always()`, one `test ... = success` line per job | both |

The added job, as proven with actionlint 0 on the merged file:

```yaml
  cursor-cloud-acp:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
        with:
          persist-credentials: false
      - uses: oven-sh/setup-bun@v2
        with:
          bun-version: 1.4.4
      - uses: actions/setup-node@v4
        with:
          node-version: '22.13'
      - run: bun install --frozen-lockfile
      - run: bun dev quality cursor-cloud-acp
```

and `check`: `needs: [static, tests, compile, node, release,
cursor-cloud-acp]` with `test '${{ needs.cursor-cloud-acp.result }}' =
success` appended.

Triggers stay the port's (push to `main`, pull requests): the original
also pushed `next`, its pre-release channel branch; the Dart release takes
no pre-release label, and cursor-cloud-acp channel releases are rare. Owner
question O4.

Test consequences (run against the merged file: exactly these three fail
before the edit):

- `test/tool/workflow_test.dart`
  - "has its six jobs": seven, `cursor-cloud-acp` before `check`.
  - "check needs every job": the list gains `cursor-cloud-acp`.
  - "uses only checkout, setup-dart, setup-node and actionlint": gains
    `oven-sh/setup-bun@v2`; the test's name follows.
  - New: "cursor-cloud-acp installs the frozen lock and runs its quality on
    Bun 1.4.4 and Node 22.13", asserting its runs, both versions and
    `persist-credentials: false`.
  - The header comment names the original's node job as the source.
- `test/tool/shards_test.dart`: none. `tool/shards.dart` lists
  `*_test.dart` under a package's `test/` only; the TS tests are
  `packages/cursor-cloud-acp/tests/*.ts`.
- `test/tool/ci_test.dart`: none. `tool/ci.dart` builds the Dart targets
  only.

An optional `parity` job is described under (c); owner question O3.

## (c) The oracle once this tree is `../chord`

### Where the port looks for the original today

- `test/fixtures/fake.dart` `findOriginal()`: `CHORD_SOURCE`, else
  `<parent of the main checkout>/chord`, checked for a marker file.
  `originalSource` (marker `src/registry.ts`) and `originalFake` (marker
  `tests/fixtures/fake_agent/main.ts`, plus bun and the installed SDK) are
  built from it.
- Readers of `originalSource`: `test/registry_test.dart`,
  `test/node_semver_test.dart`, `test/notify_session_var_test.dart`,
  `test/tool/npm_test.dart` (also reads `npm/` laid out by the original's
  `bun dev npm`).
- Readers of `originalFake`: `test/fixtures/fake_agent/parity_test.dart`,
  `test/fixtures/fake_harness.dart`, `test/node_semver_test.dart`,
  `test/notify_session_var_test.dart`,
  `test/platform/resource_worker_test.dart`,
  `test/platform/resources_readers_test.dart`,
  `test/session/codex_resources_test.dart`,
  `test/session/record_interchange_test.dart`,
  `test/ui/shortcuts/layout_keys_test.dart`, `test/yaml_stringify_test.dart`,
  `benchmark/records.dart`.
- Own lookups with the same `../chord` default: `benchmark/record_scan.dart`
  (`findOriginal`, marker `src/session/sessions.ts`),
  `tool/genai_prices.dart` (`_sibling`), `test/fixtures/prices/tester_probe.mjs`
  (`?? '../chord'`).
- Text only: `tool/dev.dart`'s `--fake` help says "the fake agent in
  ../chord/tests/fixtures/fake_agent/", stale already (the dev runner uses
  the Dart fake); fixture manifests (`steering_recovery`, `records/scale`)
  record `../chord/...` with a commit or sha256 as provenance and stay.

### What the default means after the swap

For a main checkout named `chord`, `<parent>/chord` is the checkout
itself. It holds no `src/registry.ts`, so every parity case skips with
"No chord checkout at <itself>; clone github.com/IKatsuba/chord there",
which is wrong advice. The same in CI: the runner checks out into
`.../chord/chord`, so the sibling is the checkout. Nothing breaks; the
reason misleads, and parity silently never runs.

Before the merge, in the `dart` worktree, the lookup still finds
`../chord`'s main checkout, which is TS at `577b58167` = `ts-final`: the
verification run gets real parity by accident. After the owner merges, it
does not.

### The proposed lookup

1. `CHORD_SOURCE`, as today (relative to cwd, marker checked, no fallback
   when wrong), and refused when it resolves to this repository's own main
   checkout or package directory: "CHORD_SOURCE is this repository; point
   it at a checkout of the ts-final tag".
2. Else `<parent of the main checkout>/chord-ts`, the marker checked.
3. Missing: "No ts-final checkout at <parent>/chord-ts; from the main
   checkout run `git worktree add --detach ../chord-ts ts-final` and
   `bun install --frozen-lockfile` in it, or set CHORD_SOURCE to a
   ts-final checkout."

`tool/genai_prices.dart` `_sibling` and `tester_probe.mjs` take the same
default (`chord-ts`). `tool/dev.dart`'s help names the Dart fake.

Locally: one detached worktree of the tag beside the main checkout,
`../chord-ts`, made once; `bun install` there gives the TS fake its SDK.
A worktree keeps one object store; a clone works as well through
`CHORD_SOURCE`.

CI, two options (owner question O3):

- Skip (default, today's behaviour): parity cases skip with the reason
  above; CI proves the port alone.
- A `parity` job: checkout (no credentials), `git fetch --no-tags --depth=1
  origin tag ts-final` (anonymous fetch of a public repository), `git
  worktree add --detach ../chord-ts ts-final`, setup-bun 1.4.4,
  `bun install --frozen-lockfile` in it, setup-dart, `dart pub get` both,
  then `dart test` over the parity files listed above. `check` would
  need it. Cost: one more runner, the TS install (about 600 packages).

Tests that change with the lookup, in a ship task on this repository
before the swap (the lookup is right in both homes, and this way the swap
copies tested code):

- `test/fixtures/fake_test.dart`: the default is `<parent>/chord-ts`;
  a `CHORD_SOURCE` equal to the main checkout is refused with its reason;
  the missing reason names the worktree command; the worktree-of-the-main
  case keeps finding the main checkout's sibling.
- `test/fixtures/fake.dart`, `test/registry_test.dart` (doc comment),
  `benchmark/record_scan.dart`, `tool/genai_prices.dart`,
  `test/fixtures/prices/tester_probe.mjs`, `tool/dev.dart`, and their
  tests (`test/tool/dev_test.dart` help text,
  `test/benchmark/record_scan_tester_test.dart` reason text if asserted).

## (d) The sequence

Paths: `../chord` is the original's main checkout; `W` =
`../chord-worktrees/dart`; `T` = `../chord-ts`; `P` = this repository's
main checkout; `<port>` = the reviewed commit of this repository's `main`
being swapped in. Every commit signed by plain `git commit`, no trailers,
explicit paths or `git add -A` inside `W` only.

### 0. Preconditions

```sh
git -C ../chord status --porcelain --untracked-files=all   # empty
git -C ../chord fetch origin
test "$(git -C ../chord rev-parse main)" = 577b58167672e12c999aeaf4eed2a1a988513dc2
test "$(git -C ../chord rev-parse origin/main)" = "$(git -C ../chord rev-parse main)"
git -C ../chord rev-parse -q --verify refs/tags/ts-final && exit 1   # absent
git -C ../chord ls-remote --exit-code origin refs/tags/ts-final refs/heads/dart && exit 1
ls -A ../chord/.release        # empty
git -C P ls-tree -r --name-only <port> \
  | grep -E '(^|/)(build|\.dart_tool|\.release|node_modules|dist|worktrees)/|\.DS_Store|settings\.local\.json' \
  && exit 1                    # the port tracks no excluded path
```

### 1. Tag, worktrees

```sh
git -C ../chord tag -s ts-final -m "chord: the last TypeScript main (v0.71.0)" 577b58167
git -C ../chord worktree add -b dart ../chord-worktrees/dart main
git -C ../chord worktree add --detach ../chord-ts ts-final
(cd ../chord-ts && bun install --frozen-lockfile)
```

### 2. Commit 1, the TS workspace reduced (on `dart`, in `W`)

```sh
git mv src/channel.ts scripts/dev/channel.ts
git rm -r -q src tests steps.ts lint/config_test.ts lint/style_test.ts \
  scripts/dev/tools.ts scripts/dev/npm.ts scripts/dev/registry.ts \
  scripts/dev/mark.ts scripts/dev/screenshots.ts scripts/dev/social.ts \
  scripts/dev/memory.ts scripts/dev/jsx_dev_runtime.ts \
  scripts/dev/screenshots_proposal.md scripts/dev/screenshots_team.md \
  scripts/dev/release/pins.ts scripts/format.ts scripts/mark.svg \
  .puppeteerrc.json
# edits from (a): the six channel imports, scripts/dev.ts, scripts/dev/steps.ts,
# package.json, bunfig.toml, tsconfig.json, eslint.config.ts, scripts/AGENTS.md
rm -rf node_modules && bun install && bun install --frozen-lockfile
git add -A -- scripts package.json bun.lock bunfig.toml tsconfig.json eslint.config.ts
bun dev quality cursor-cloud-acp          # must pass before committing
git commit -m "chore: reduce the TypeScript workspace to cursor-cloud-acp"
```

The tree at commit 1 has no app, and cursor-cloud-acp's quality passes:
the package's history stays bisectable.

### 3. Commit 2, the port in

```sh
# the framework's inventory: what of the original's docs, community files,
# .github, .chord, .zed and .git-blame-ignore-revs is dropped or replaced
git rm -r -q -- <the inventory's drop and replace lists>
git -C P archive <port> | tar -x -C .
# merged .gitignore from (a); the version to v0.71.0's, as the release needs:
#   pubspec.yaml, packages/chord_tui/pubspec.yaml, lib/version.dart -> 0.71.0
(cd packages/chord_tui && dart pub get) && dart pub get   # rewrites pubspec.lock
git add -A
git status --porcelain --untracked-files=all | grep -v '^[AMDR] ' && exit 1
git commit -m "feat: chord in Dart, with its framework chord_tui"
```

`git archive` copies only what `<port>` tracks, so `build/`,
`.dart_tool/`, worktrees, `.release`, `node_modules`, `dist`, `.DS_Store`
and local settings never come along (the precondition proves none is
tracked); uncommitted changes in `P` cannot leak in either.

### 4. Commit 3, CI and docs for the new home

```sh
# .github/workflows/ci.yml: the cursor-cloud-acp job and check (b)
# test/tool/workflow_test.dart: the (b) changes
# AGENTS.md, README.md, CONTRIBUTING.md, docs/FEATURES.md: the interface draft's
git add -- .github/workflows/ci.yml test/tool/workflow_test.dart AGENTS.md \
  README.md CONTRIBUTING.md docs/FEATURES.md
git commit -m "ci: one workflow for chord and cursor-cloud-acp"
```

(Docs may be their own `docs:` commit; the lead decides with interface.)

### 5. Verification in `W`

```sh
export CHORD_SOURCE="$(cd ../chord-ts && pwd)"
git status --porcelain --untracked-files=all                    # empty
bun install --frozen-lockfile
(cd packages/chord_tui && dart pub get) && dart pub get
dart analyze && (cd packages/chord_tui && dart analyze)
dart format --output=none --set-exit-if-changed .
actionlint .github/workflows/ci.yml
caffeinate -dimsu dart test
(cd packages/chord_tui && caffeinate -dimsu dart test)
caffeinate -dimsu dart test -t compile --run-skipped
(cd packages/chord_tui && caffeinate -dimsu dart test -t compile --run-skipped)
(cd packages/chord_tui && dart test -t publish --run-skipped)    # dry run only
bun dev quality cursor-cloud-acp
bun dev release --help
dart run tool/release.dart --help
dart test test/version_test.dart                                 # 0.71.0 everywhere
git status --porcelain --untracked-files=all                    # still empty
```

With `CHORD_SOURCE` at `ts-final`, the parity cases run instead of
skipping: registry, npm manifests and shim (`npm_test.dart` needs `bun
dev npm` run in `T` first for its manifest case, else that one case
skips), the fake's TS parity, record interchange both ways, YAML,
semver, layout keys. Each skip left is reported with its reason.

### 6. The owner's steps

```sh
git -C ../chord log --stat --show-signature main..dart          # review
git -C ../chord push origin ts-final dart
gh pr create -R IKatsuba/chord --base main --head dart ...       # CI runs, check must pass
# merge keeping the three signed commits (rebase or fast-forward; not squash)
git -C ../chord switch main && git -C ../chord pull --ff-only
# wait for check on main
cd ../chord
bun install --frozen-lockfile       # prunes the old TS node_modules
(cd packages/chord_tui && dart pub get) && dart pub get
dart run tool/release.dart chord --bump 0.72.0
#   preflight: clean tree, 0.71.0 on npm, 0.72.0 on none of the five names,
#   @chorded/cursor-cloud-acp@0.2.0 on npm (it is), origin = IKatsuba/chord
#   for fetch and push, main level with origin/main, no v0.72.0 tag, gh signed in
#   bump commit "chore: chord v0.72.0", pushed to origin main
#   publish: npm asks for approval five times (four platform packages, then
#   @chorded/chord); Enter, then approve in the browser, each time
gh release view v0.72.0 -R IKatsuba/chord           # draft, archives attached
gh release edit v0.72.0 -R IKatsuba/chord --draft=false
# tap: build/release/chord.rb -> <tap checkout>/Formula/chord.rb
git -C <tap checkout> add Formula/chord.rb && git -C <tap checkout> commit -m "chord 0.72.0" && git -C <tap checkout> push
brew update && brew install ikatsuba/tap/chord && brew test chord && chord --version
git -C ../chord worktree remove ../chord-worktrees/dart
```

cursor-cloud-acp's next release, from the same checkout, is
`bun dev release cursor-cloud-acp --bump <v>`, never at the same time as
chord's (finding 7).

## (e) Release mechanics and risks

| Risk | What happens | Check |
| --- | --- | --- |
| Version floor | 0.0.1 → release refuses (finding 1) | `dart test test/version_test.dart`; `grep -n '^version' pubspec.yaml packages/chord_tui/pubspec.yaml` say 0.71.0 |
| Origin checks on the new history | `originIsRelease` wants origin `IKatsuba/chord`: true in `../chord`, false in this repository, so the release runs only from `../chord` after the merge. The history is TS main plus three commits, so `main` level with `origin/main` holds once pushed; `v0.71.0` and `cursor-cloud-acp-v0.{1,2}.0` exist and are not the forms checked (`v0.72.0`, `cursor-cloud-acp-v<next>`) | `git -C ../chord ls-remote origin refs/tags/v0.72.0` empty; the release's own preflight |
| `.release` state | Dart `.release/chord/`, TS `.release/cursor-cloud-acp/`; a leftover TS `.release/chord/state.json` would be read as Dart's | `ls -A ../chord/.release` empty before the release (it is today) |
| Shared lock | finding 7 | releases one at a time; backlog item for a lock both read |
| npm `@chorded/chord` 0.72.0 over 0.71.0 | 0.71.0: `bin {chord: bin/chord.js}`, four exact optional platform packages, no `engines`, platform packages `os`/`cpu` only. `tool/npm.dart` writes the same fields; platform `files` carry `NOTICES` in place of the FFmpeg/zlib licence files, since no OpenTUI native library (and so no FFmpeg) is linked | `npm_test.dart` with `CHORD_SOURCE` and `bun dev npm` in `T`; after publish `npm view @chorded/chord@0.72.0 bin optionalDependencies`, `npx -y @chorded/chord@0.72.0 --version` on macOS and Linux |
| Linux binary floor | bun's binary and Dart's AOT binary may need different glibc; musl was unsupported before and stays so | on the linux-x64 archive: `objdump -T chord \| grep -o 'GLIBC_[0-9.]*' \| sort -uV \| tail -1`, against the same of 0.71.0's `@chorded/chord-linux-x64` |
| GitHub release assets | 0.71.0's carried the FFmpeg and zlib sources; 0.72.0's carry the platform archives the formula downloads | `gh release view v0.72.0` lists four archives; the formula's URLs resolve |
| Homebrew | first formula (finding 4); stable only | `brew install ikatsuba/tap/chord`, `brew test chord` |
| Users' shared state, upgrade | the port reads the original's records, settings, teams and notice dismissals under the same XDG paths | `record_interchange_test.dart` (original writes, port appends, original reads, port resumes) and the settings/teams/notices parity cases, all with `CHORD_SOURCE` at `ts-final` |
| Downgrade | `npm i -g @chorded/chord@0.71.0` reads what 0.72.0 wrote | the interchange test's "original reader" half; anything the port writes that 0.71.0 does not know is listed by interface, not assumed |
| Push of the bump commit | `--bump` pushes `chore: chord v0.72.0` straight to `origin/main`, as 0.71.0's did; protection that requires `check` on direct pushes would refuse it | owner confirms the bypass still applies after the swap |
| TS leftovers in the owner's checkout | ignored `node_modules/`, `dist/`, `npm/` from 0.71.0 stay; ignored, so preflight passes | `git status --porcelain --untracked-files=all` empty in `../chord` before the release |

## Test plan

- Pure: `findOriginal` cases in `test/fixtures/fake_test.dart` (default
  `chord-ts`, self refused, reasons); `test/version_test.dart` at 0.71.0;
  `test/tool/workflow_test.dart` for the seven jobs, `check`, actions.
- TS: cursor-cloud-acp's own suite through `bun dev quality
  cursor-cloud-acp`, unchanged (its `steps_test.ts` asserts the same
  checks); in CI by the new job.
- Parity: the listed files with `CHORD_SOURCE` at `ts-final`, locally in
  the verification, and in CI if O3 says so.
- No real model, agent, npm login or publish in any of it; the release
  is exercised by its recording-runner tests and `--help` only.

## Owner questions

- **O1.** The root `package.json`'s name: `@chorded/workspace` (private,
  never published), or another. It must not be `@chorded/chord` or
  `@chorded/chord-<os>-<cpu>`.
- **O2.** The framework's version jumps from 0.0.1 to 0.71.0 in the swap
  and 0.72.0 at the release, since the two share a version (AGENTS.md):
  confirm, as the release refuses anything below 0.71.0.
- **O3.** CI parity against `ts-final`: skip with a reason (today's
  behaviour), or a `parity` job that fetches the tag, installs it with bun
  and runs the parity files, required by `check`.
- **O4.** CI triggers: the port's (`main`, pull requests) or the
  original's (`main`, `next`, pull requests).
- **O5.** Merging `dart`: through a pull request so `check` runs before
  `main` moves (recommended), and with rebase or fast-forward so the three
  signed commits stay as they are.
- **O6.** Whether the bump commit's direct push to `main` still bypasses
  branch protection, as for 0.71.0.

## Open questions for the lead

- **R1.** The lookup change (c) is a code change to this repository: a
  ship task before the swap (recommended), or part of the swap's commits.
- **R2.** Pruning the release modules' chord-only paths (`sign`,
  `notarise`, `selftest`, `pack`, `compile`) out of the TS workspace: a
  follow-up task, not in the swap.
- **R3.** `lint/style_test.ts` tests the custom ESLint rules the package
  uses, and only the root `steps.ts` ran it. Dropping it leaves the rules
  tested only through the package's lint; keeping it needs a check that
  runs it, which changes cursor-cloud-acp's `steps.ts` and its
  `steps_test.ts`. Framework's or the lead's call.
- **R4.** The two release locks (finding 7): one shared format, as a
  backlog task.

## After the critic

This section replaces §(d) and corrects finding 7 and parts of §(a), as
the lead decided after the critic. Where the two differ, this section
holds.

### Decisions taken over

- The finder drops `'.'` (as in §(a)).
- `src/channel.ts` moves to `scripts/dev/release/channel.ts`, not
  `scripts/dev/channel.ts`. The six release importers import
  `'./channel.ts'`, and the tooling tests import `'../release/channel.ts'`
  or the equivalent from their own folder.
- `eslint.config.ts` stays unchanged.
- `lint/*_test.ts` and `tests/scripts/**` are kept. Framework lists them
  and the one root command that runs them; below it is written
  `<tooling tests command>` (for example `bun test ./tests/scripts ./lint`).
- `.gitignore` is framework's union, `.claude/worktrees/` included.
- The root `package.json`'s name is `<root-name>`, an owner question. The
  recommendation is `chord-workspace`: unscoped and private.
- The oracle checkout is `../chord-ts`. The lookup change is a ship task
  on this repository's `main` **before** the swap (R1, yes). Pruning the
  TS release modules is a follow-up task (R2, yes).

### Finding 7, corrected

TS `lock.ts` passes `stale: Number.POSITIVE_INFINITY` (and `update: 2 **
31 - 1`), so proper-lockfile never treats a lock as stale and never
removes Dart's `chord-release.lock` file. While Dart holds the lock, TS's
`mkdir` fails with EEXIST, which is a correct refusal. The only mismatch
is the other way round. While TS holds the lock (a directory), Dart's
`File(...).createSync(exclusive: true)` throws, and `File.existsSync()`
is false for a directory, so Dart rethrows a raw `FileSystemException`
instead of "another release runs". The two still exclude each other. The
swap changes nothing here: there is a gate below, and a backlog item for
the message.

### Literal versions that break on the bootstrap

The swap writes `0.71.0`, and every later release bump moves it on. Tests
that compare **live** output with a literal `0.0.1` must read the held
version instead: `version` from `package:chord/version.dart`, which
`test/version_test.dart` already ties to both `pubspec.yaml` files.
`grep -rnF 0.0.1` over `test/`, `tool/`, `benchmark/` and the framework,
less addresses and injected values, found:

| File:line | Today | Becomes |
| --- | --- | --- |
| `test/cli_test.dart:252` | `'chord 0.0.1\n'` | `'chord $version\n'` |
| `test/cli_test.dart:254` | `'0.0.1\n'` | `'$version\n'` |
| `test/cli_test.dart:336`, `:338` | `'0.0.1\n'` | `'$version\n'` |
| `test/cli_test.dart:364`, `:365` | `'chord 0.0.1\n'` | `'chord $version\n'` |
| `test/tool/dev_test.dart:464` | `'chord 0.0.1\n'` (runs `tool/dev.dart chord -- --version`) | `'chord $version\n'` |
| `test/ui/app/wheel_window_test.dart:136` | `shows('chord v0.0.1')`, with no version injected | `shows('chord v$version')` |
| `test/ui/app/error_window_test.dart:162`, `:171` | the same | `shows('chord v$version')` |

These are left as they are, because they inject the version they then
assert: every `version: '0.0.1'` passed to a start, splash or window model
in `test/ui/**`, and `test/tool/release/{notices,selftest}_test.dart`
(recording runners). The same goes for `test/upgrade_brew_test.dart:354`
(registry fixture data) and
`test/fixtures/failed_start_escape/baseline_61d012c/*.txt`, a historical
capture that no test reads.

These edits are made in commit 2, as decided. They are equally right in
this repository today, so the lead may fold them into the pre-swap ship
task with the lookup change. Commit 2 would then change only version
numbers.

### The script plan

It runs from one stated starting directory: the folder that holds `chord/`
and `chorded-tui/` side by side. Phases 0 to 5 are the swap run. Phase 6
is the owner's. Each phase is meant to be pasted as a whole into one bash
shell. Nothing pushes before phase 6.

```bash
#!/usr/bin/env bash
set -euo pipefail
# Start: the folder holding chord/ and chorded-tui/.
test -d chord/.git && test -d chorded-tui/.git
P=$PWD/chorded-tui
C=$PWD/chord
W=$PWD/chord-worktrees/dart
T=$PWD/chord-ts
TS_MAIN=577b58167672e12c999aeaf4eed2a1a988513dc2
PORT=$(git -C "$P" rev-parse main)   # the reviewed port commit; pin it by hand if main moves
COMMON=$(git -C "$C" rev-parse --path-format=absolute --git-common-dir)

clean()  { test -z "$(git -C "$1" status --porcelain --untracked-files=all)"; }
signed() { git -C "$1" cat-file commit HEAD | grep -q '^gpgsig' \
             || { echo "unsigned HEAD in $1: stop" >&2; exit 1; }; }
on_dart(){ test "$(git -C "$W" symbolic-ref --short HEAD)" = dart \
             || { echo "W is not on dart: stop" >&2; exit 1; }; }
# Exit 2 = no such ref on origin; 0 = it exists; anything else = transport error.
absent_on_origin() {
  local rc=0; git -C "$C" ls-remote --exit-code origin "$1" >/dev/null || rc=$?
  case $rc in 2) ;; 0) echo "$1 exists on origin: stop" >&2; exit 1 ;;
              *) echo "ls-remote failed ($rc): stop" >&2; exit 1 ;; esac
}
```

#### Phase 0: gates

```bash
clean "$C"
git -C "$C" fetch origin
test "$(git -C "$C" rev-parse main)" = "$TS_MAIN"
test "$(git -C "$C" rev-parse origin/main)" = "$TS_MAIN"
! git -C "$C" rev-parse -q --verify refs/tags/ts-final
! git -C "$C" rev-parse -q --verify refs/heads/dart
absent_on_origin refs/tags/ts-final
absent_on_origin refs/heads/dart
test ! -e "$W" && test ! -e "$T"
test -z "$(ls -A "$C/.release" 2>/dev/null)"
test ! -e "$COMMON/chord-release.lock"
clean "$P"
# The port tracks no path the copy must leave out.
! git -C "$P" ls-tree -r --name-only "$PORT" \
  | grep -E '(^|/)(build|\.dart_tool|\.release|node_modules|dist|worktrees)/|\.DS_Store|settings\.local\.json'
# The pre-swap ship task is in: the oracle lookup defaults to chord-ts.
git -C "$P" grep -q "'chord-ts'" "$PORT" -- test/fixtures/fake.dart
```

#### Phase 1: tag and worktrees

```bash
git -C "$C" tag -s ts-final -m "chord: the last TypeScript main (v0.71.0)" "$TS_MAIN"
git -C "$C" tag -v ts-final                       # signature verifies, or stop
git -C "$C" worktree add -b dart "$W" main
git -C "$C" worktree add --detach "$T" ts-final
test "$(git -C "$T" rev-parse HEAD)" = "$(git -C "$C" rev-parse 'ts-final^{commit}')"
(cd "$T" && bun install --frozen-lockfile)
# For npm_test's manifest case: the original's npm/ laid out from its binaries.
(cd "$T" && bun dev compile --all && bun dev npm)
test -f "$T/npm/chord/package.json"
on_dart
```

#### Phase 2: commit 1, the TS workspace reduced

```bash
on_dart
git -C "$W" mv src/channel.ts scripts/dev/release/channel.ts
git -C "$W" rm -r -q -- src tests/fixtures tests/ui tests/session <the rest of tests/ but tests/scripts> \
  steps.ts scripts/dev/tools.ts scripts/dev/npm.ts scripts/dev/registry.ts \
  scripts/dev/mark.ts scripts/dev/screenshots.ts scripts/dev/social.ts \
  scripts/dev/memory.ts scripts/dev/jsx_dev_runtime.ts \
  scripts/dev/screenshots_proposal.md scripts/dev/screenshots_team.md \
  scripts/dev/release/pins.ts scripts/format.ts scripts/mark.svg .puppeteerrc.json \
  <framework's further TS drop list>
# Edits (§(a), as amended): channel imports; scripts/dev.ts; scripts/dev/steps.ts
# without '.'; package.json (<root-name>, private, workspaces
# ["packages/cursor-cloud-acp"]); bunfig.toml without [test]; tsconfig.json;
# tests/scripts/** and lint/*_test.ts kept and passing; scripts/AGENTS.md.
(cd "$W" && rm -rf node_modules && bun install && bun install --frozen-lockfile)
(cd "$W" && bun dev quality cursor-cloud-acp)
(cd "$W" && <tooling tests command>)
git -C "$W" add -A          # W holds only this phase's changes; clean "$W" gated it
git -C "$W" commit -m "chore: reduce the TypeScript workspace to cursor-cloud-acp"
signed "$W"
clean "$W"
```

#### Phase 3: commit 2, the port in

```bash
on_dart
# The TS decisions move aside before the port's docs/decisions.md lands,
# so git records a rename and blame follows it.
git -C "$W" mv docs/decisions.md docs/decisions-ts.md
git -C "$W" rm -r -q -- <framework's drop and replace lists>
git -C "$P" archive "$PORT" | tar -x -C "$W"
# .gitignore: framework's union. Version bootstrap to v0.71.0's:
sed -i '' 's/^version: 0\.0\.1$/version: 0.71.0/' "$W/pubspec.yaml" "$W/packages/chord_tui/pubspec.yaml"
sed -i '' "s/^const version = '0\.0\.1';$/const version = '0.71.0';/" "$W/lib/version.dart"
# The literal-version tests above read `version`, unless the ship task did it.
(cd "$W/packages/chord_tui" && dart pub get) && (cd "$W" && dart pub get)   # rewrites pubspec.lock
(cd "$W" && dart test test/version_test.dart test/cli_test.dart)
git -C "$W" add -A
git -C "$W" commit -m "feat: chord in Dart, with its framework chord_tui"
signed "$W"
clean "$W"
```

The one difference from the lead's list: the `git mv` of
`docs/decisions.md` is in commit 2, not commit 4. It has to happen before
the port's file lands, and the extract is in commit 2. Commit 4 edits
`docs/decisions-ts.md` only if the owner's answers ask for that.

#### Phase 4: commit 3 (CI) and commit 4 (docs)

```bash
on_dart
# ci.yml: the cursor-cloud-acp job of §(b), with one more step after quality:
#   - run: <tooling tests command>
# and check needing it; test/tool/workflow_test.dart as §(b).
(cd "$W" && actionlint .github/workflows/ci.yml && dart test test/tool/workflow_test.dart)
git -C "$W" add -- .github/workflows/ci.yml test/tool/workflow_test.dart
git -C "$W" commit -m "ci: one workflow for chord and cursor-cloud-acp"
signed "$W"

on_dart
# Each file below is staged only if the owner's answers keep or rewrite it:
git -C "$W" add -- AGENTS.md README.md CONTRIBUTING.md docs/FEATURES.md \
  docs/guide.md docs/agent-capabilities.md docs/decisions-ts.md TRADEMARKS.md \
  .chord/teams/*.md .github/pull_request_template.md
git -C "$W" commit -m "docs: chord's home is the Dart tree"
signed "$W"
clean "$W"
```

#### Phase 5: verification in W

```bash
on_dart
export CHORD_SOURCE=$T
test "$(git -C "$T" rev-parse HEAD)" = "$(git -C "$C" rev-parse 'ts-final^{commit}')"
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
<tooling tests command>
bun dev release --help
dart run tool/release.dart --help
# Parity against ts-final, skips printed:
mkdir -p "$W/build"
dart test --reporter expanded \
  test/registry_test.dart test/node_semver_test.dart \
  test/notify_session_var_test.dart test/tool/npm_test.dart \
  test/fixtures/fake_agent/parity_test.dart test/fixtures/fake_test.dart \
  test/platform/resource_worker_test.dart test/platform/resources_readers_test.dart \
  test/session/codex_resources_test.dart test/session/record_interchange_test.dart \
  test/ui/shortcuts/layout_keys_test.dart test/yaml_stringify_test.dart \
  2>&1 | tee "$W/build/parity.log"
! grep -E 'Skip:' "$W/build/parity.log"
clean "$W"
cd - >/dev/null
```

Allowed skips in the parity run: none. Each of those files skips only on
`originalSource`, `originalFake` or `originalSkip` (no checkout, no bun,
no SDK), on `node` missing from PATH, or on `npm/` not being laid out, and
phases 1 and 5 assert all of those. A skip that shows up anyway is a
finding to report, not something to wave through.

The full suites' own skips are whatever they are on main today
(platform-only cases, `lsof`), and they are reported with their reasons.

`git log --oneline main..dart` in `C` now shows exactly the four commits,
each signed. The lead reports `dart` and its head to main. Nothing is
pushed.

#### Phase 6: the owner

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
git -C "$C" push origin main          # if protection refuses a direct
                                      # fast-forward push: owner question O5
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
# T stays: it is the oracle for later parity runs.
```

`sed -i ''` above is the macOS form, for the owner's machine. The swap run
can also make those three version edits by hand. Any variant has to pass
the `test/version_test.dart` gate that follows it.
