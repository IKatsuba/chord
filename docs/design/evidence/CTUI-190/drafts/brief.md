# CTUI-190 brief: the swap into ../chord

## The problem

The owner approved replacing the TypeScript chord app in the chord
repository (github.com/IKatsuba/chord, checked out at `../chord`, main
`577b58167`, v0.71.0) with this repository's tree: the Dart port at the
root and the framework under `packages/chord_tui/`. The TS main is tagged
`ts-final`; the swap is made on a branch `dart` in a worktree of `../chord`;
the owner reviews, merges and pushes, then releases 0.72.0 stable with
`dart run tool/release.dart chord --bump 0.72.0`.

`packages/cursor-cloud-acp` stays TypeScript, released to npm on its own
(`@chorded/cursor-cloud-acp`), because its Cursor SDK may not be packed into
a binary. Its toolchain must keep working after the swap.

This run is design only. Nobody writes to `../chord`: no tag, no branch, no
file. Reading it is expected.

## Who is affected and what they see

- A user upgrading `@chorded/chord` from npm or Homebrew gets 0.72.0, a
  Dart-compiled binary in place of a bun-compiled one, over the same
  state (`XDG_STATE_HOME`, settings, records, teams, notice dismissals).
- A contributor clones github.com/IKatsuba/chord and finds the Dart tree,
  `AGENTS.md` describing it, and a way to run the oracle/parity tests
  against `ts-final`.
- The maintainer runs `tool/release.dart` for chord and
  `bun dev release cursor-cloud-acp` for the package, from the same tree.

## Facts already found (verify, do not trust)

- Tracked top level of `../chord`: `.chord .git-blame-ignore-revs .github
  .gitignore .npmrc .prettierignore .prettierrc.json .puppeteerrc.json .zed
  AGENTS.md CODE_OF_CONDUCT.md CONTRIBUTING.md LICENSE README.md SECURITY.md
  TRADEMARKS.md bun.lock bunfig.toml docs eslint.config.ts lint package.json
  packages scripts src steps.ts tests tsconfig.json`. Untracked/ignored:
  `dist/ node_modules/ npm/ .release/ .claude/settings.local.json`. `.claude`
  exists on disk; check what of it is tracked.
- Both trees have `packages/`, `.chord/`, `.claude/`, `.github/`,
  `docs/FEATURES.md`, `docs/decisions.md`, `docs/design/`, `AGENTS.md`,
  `README.md`, `CONTRIBUTING.md`, the community files and `LICENSE`.
- Root `package.json` is `@chorded/chord` 0.71.0, private, bun workspaces
  `packages/*`, script `dev: bun scripts/dev.ts`, with the app's
  dependencies. Bun workspaces would now also see `packages/chord_tui`
  (no package.json).
- `packages/cursor-cloud-acp/steps.ts` runs `bun check`, `bun fmt`,
  eslint with its own config that imports `../../eslint.config.ts`
  (`forbid`, `shared`, `TOOLING`), `scripts/dev/covered.ts`, `bun test`,
  and build/smoke from `scripts/tools.ts`, which imports
  `scripts/dev/release/{build,lib,publish,sums}.ts` and
  `scripts/dev/steps.ts`, and `@modelcontextprotocol/sdk` (a root
  dependency). Its tests import `scripts/dev/steps.ts`.
- `.github/workflows/ci.yml` in `../chord`: jobs static, tests (3 shards),
  compile, node (bun 1.4.4 + Node 22.13, `bun dev quality cursor-cloud-acp`),
  and check, which branch protection requires by name.
- The port: `lib/distribution.dart` names `@chorded` and `IKatsuba/chord`;
  `tool/release/` mirrors `scripts/dev/release/`, including a preflight and
  `continue.dart` that check the branch level with `origin`; its CI is
  `.github/workflows/ci.yml` with its own `check` job; tests find the
  original through `CHORD_SOURCE`, else the sibling `../chord`.

## What the design must settle (from main)

1. Inventory: every top-level path of `../chord` at `577b58167`, and of
   `docs/` (guide.md, design/CHD-*, qa, images, memory.md,
   agent-capabilities.md), `npm/`, `dist/`, `scripts/`, `src/`, `tests/`,
   `lint/`, `steps.ts`, `package.json`, `bun.lock`, `tsconfig.json`,
   `eslint.config.ts`, prettier, `.zed`, `.release`, `.claude`, `.chord`,
   `.github`, the community files, `LICENSE`: each dropped, replaced by the
   port's, kept, or merged, with the reason.
2. cursor-cloud-acp: exactly what TS tooling stays (workspace root
   package.json, bun.lock, `scripts/dev.ts` reduced to quality, lint and
   release for this one package, `scripts/dev/steps.ts`, `covered.ts`,
   `scripts/dev/release/*` it needs, eslint and tsconfig, bunfig,
   prettier) and how `bun dev release cursor-cloud-acp` keeps working. The
   root package.json is no longer `@chorded/chord`'s app: its new name,
   privacy, and a check that no npm name clashes with the Dart release's
   packages (`@chorded/chord`, `@chorded/chord-<platform>`).
3. CI: one workflow combining the port's ci.yml with the node job, one
   aggregate `check` whose name branch protection keeps.
4. Oracle and parity tests: `CHORD_SOURCE` at a `ts-final` checkout; how CI
   gets it (fetch the tag into a second checkout, or skip with a reason);
   how a local run gets it (`git worktree add ../chord-ts ts-final` or
   similar). What changes in the tests' default lookup now that `../chord`
   is this repository.
5. Docs: AGENTS.md, README.md, CONTRIBUTING.md, docs/FEATURES.md rewritten
   for the new home, "the original at ../chord" becoming the `ts-final`
   tag. What happens to the original's `docs/guide.md`, `docs/design/CHD-*`,
   `docs/decisions.md`, `docs/FEATURES.md` and the board history.
6. The exact sequence, as commands: tag `ts-final`; `git worktree add -b
   dart`; removal and copy with excludes (`build/`, `.dart_tool/`,
   worktrees, `.release` state, `node_modules`, `dist`, `.DS_Store`,
   local settings); the commits; verification on `dart` (pub get, analyze,
   format, both suites, compile tags, cursor-cloud-acp quality,
   `tool/release.dart --help`); then the owner's steps: review, merge,
   push, CI, `dart run tool/release.dart chord --bump 0.72.0`, npm browser
   approvals, publishing the GitHub draft release, the Homebrew tap commit
   of `build/release/chord.rb`.
7. Risks and their checks: users' shared state; npm `@chorded/chord`
   0.72.0 over 0.71.0 (bin names, optional platform packages, the shim);
   the Homebrew formula moving from a bun binary to a Dart one; the release
   preflight's origin checks in a repository whose history changed under
   it; git history (`ts-final` keeps TS history; this repository's history
   is not imported, so the swap is one or a few commits on top of TS main).
8. Questions only the owner can settle, written as board questions.

## Constraints

- AGENTS.md is binding; it will itself be rewritten by the swap.
- Nothing in the design names a private path; `../chord` and the worktree
  names relative to it are fine.
- The design writes no code; the commands in it are what a later run
  executes.
- A choice that is the owner's (scope, dropping something the original
  ships, history import, package names) is listed as a question, not
  decided.

## Non-goals

- Building or running the swap. Tagging. Pushing.
- Porting cursor-cloud-acp to Dart.
- Changing the port's features.

## Open questions per architect

- framework (repository and build layout): the inventory, path by path;
  the merged tree's layout (`packages/chord_tui` beside
  `packages/cursor-cloud-acp`, docs folders, `.chord/teams`, `.claude`);
  the exclude list; what of the TS root config can be deleted without
  breaking the package (eslint's imports, tsconfig include lists, bun
  workspace seeing a Dart package); how `docs/design` and `decisions.md`
  of the two trees coexist.
- interface (people and words): what a user, contributor and maintainer
  see: README, AGENTS.md, CONTRIBUTING, FEATURES rewrites in outline; the
  fate of `docs/guide.md` (the port's user guide?) and the TS design
  history; issue templates, PR template, FUNDING; how a person gets the
  `ts-final` oracle locally; the npm and Homebrew user's upgrade from
  0.71.0, including state compatibility as a user experiences it.
- runtime (processes, CI, release, tests): the cursor-cloud-acp toolchain
  minimum and how `bun dev release cursor-cloud-acp` still runs; the
  combined CI workflow, job by job; CHORD_SOURCE in CI and locally and the
  tests' default lookup; the exact command sequence and verification; the
  release's preflight/origin/tag checks against the new history
  (`v0.71.0` tag exists, `cursor-cloud-acp-v*` tags, release state);
  npm/Homebrew mechanics of 0.72.0; risks with checks.
