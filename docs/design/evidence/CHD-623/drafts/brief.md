# CHD-623 brief — `bun dev` for several packages

The lead's brief. The task is `board show CHD-623`; the owner's decisions
listed in it are fixed. Design within them; a choice that contradicts one,
or changes scope, comes back to the lead as a question for the owner with
options.

## The problem

`bun dev` (`scripts/dev.ts`, Cliffy) grew around one package. CHD-622 adds a
second, `@chorded/cursor-cloud-acp` under `packages/cursor-cloud-acp/` (a
Bun workspace; Node 22.13+ at run time; its design is on branch CHD-622,
`git show CHD-622:docs/design/CHD-622.md`, sections "The package in the
repository", "Each package's checks", "The release"). Today:

- `bun dev` commands: `chord`, `test`, `compile`, `npm`, `registry`,
  `mark`, `screenshots`, `riff-models` (leaves with CHD-621), `social`,
  `memory`, `selftest`, `release`. Some are chord's package's (compile,
  npm, selftest, release's stages), some the repository's (registry, mark,
  screenshots, social, memory), some both.
- `bun quality [--static]` and `bun lint` are root package.json scripts
  outside `bun dev` (`scripts/quality.ts`, `scripts/lint.ts`).
- `bun dev release [version|bump]` with stages `install, check, natives,
  compile, sign, selftest, notarise, pack, publish`, `--skip/--only/--from/
  --to`, `--channel`, `--dry-run`, and `--package <name>`: publish only one
  of chord's five npm packages (the `@chorded/chord` shim or one of its four
  platform packages), used to finish a stopped publish by hand.

## The owner's decisions (fixed, from CHD-622 and CHD-623)

1. Everything goes through `bun dev`.
2. A package is named by its npm name without the scope: `chord`,
   `cursor-cloud-acp`.
3. No default package. A release names its package, chord's too; a bare
   `bun dev release` releases nothing and says it is not clear which
   package to release.
4. The version or bump is `--bump`.
5. Every package defines its own steps in a file at its root, named close
   to what it holds: its checks and also its build, publish and other
   steps, in their order. A command run for a package runs only that
   package's steps.
6. The checks command: `bun dev check <package> [--static]` or `bun dev
   quality <package>`, either name.
7. `bun quality [--static]` becomes the checks command for chord; `bun lint
   --fix` becomes a `bun dev` command for a package; `bun dev test` stays
   chord's suite runner; CI calls the checks command per package; AGENTS.md,
   folder AGENTS.md files, CONTRIBUTING, the guide and comments follow in
   the same change.
8. Steps: chord = types, covered, eslint, format, lint/'s tests, and the
   suite when not `--static`, each leaving `packages/` out;
   cursor-cloud-acp = types, covered, eslint, format, tests, and when not
   `--static` its build with the not-bundled check and the Node 22 smoke on
   the packed tarball.
9. No GitHub release for a package other than chord.

## Open questions (the draft answers each: options, choice, why)

Q1. The whole command set: which commands take a package and which are the
    repository's; their names; how `bun dev --help` and each command's help
    read; no word meaning two things (today's `--package`, `check` in
    "check stage" vs `bun check`, `selftest` as a command and a stage, …).
Q2. The per-package file: its name (close to what it holds), its shape
    (data or code; typed by what), what `bun dev` reads from it, how it is
    found (root `package.json` + `workspaces`), where chord's lives (its
    package is the repository root), and that it is never shipped.
Q3. Publishing: stays a release stage, or becomes `bun dev publish
    <package>`; what replaces `--package` for finishing a stopped publish of
    one of chord's five npm packages.
Q4. How a release's stages map onto a package's steps; what a stage a
    package does not have does (and `--only/--from/--to/--skip` naming one);
    which guards (arm64 Mac, `gh`, CHD-547, branch level, tags, npm auth)
    belong to the release and which to a package's steps.

Also: what changes in `scripts/` (files, the runner, tests), CI's calls,
and the docs that follow; and how this lands before CHD-622 builds on it.

## Constraints

AGENTS.md (binding): the one rule (Cliffy for parsing, no hand argv
parsing or workarounds around it), `bun dev` arguments pass on as written,
tests for every script change in `tests/scripts/`, no private paths, signed
commits without trailers. Release rules already decided stay unless a
question above reopens them: CHD-395 (npm on node), CHD-547, CHD-577
(channels), the release on the owner's arm64 Mac.

## Non-goals

Code; the cursor-cloud-acp adapter itself (CHD-622); changing what chord's
release does for chord beyond naming and placement.
