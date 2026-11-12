# CHD-623 — runtime's draft: `bun dev` for several packages

runtime's answer to the brief's Q1–Q4 and its "Also". The owner's
decisions in `board show CHD-623` are taken as fixed; where a choice here
leans on one, it names it (D1–D9, the brief's numbering). Items marked
**OWNER** need the owner before code; each has options and a
recommendation.

Every parse shape below was tried on Cliffy 1.3.1 as installed
(`@cliffy/command`, a throwaway script, deleted): a `globalType` enum for
`<package>`, `release` with one subcommand per package and a stage enum of
its own, `globalOption`s on `release` reaching its own action when no
package is named, and `stopEarly` passing ESLint's `--fix` on after the
package. What Cliffy printed is quoted where it matters. Cliffy groups
options in help (`.group()`), not commands, so commands list in the order
they are declared.

## The principle

A word means one thing.

- **`<package>`** is always the first positional, and only ever a package of
  the repository by its npm name without the scope (D2): `chord`,
  `cursor-cloud-acp`. Today's `--package` (one of chord's five npm
  packages) goes, so the word has no second meaning (Q3).
- **A command that takes `<package>`** runs only that package's steps from
  its steps file (D5). Those are `quality`, `lint` and `release`.
- **chord's own tools** that have no counterpart in another package keep
  their names and take no `<package>`: `chord`, `test` (D7), `compile`,
  `npm`, `selftest`, `memory`. Their help starts with "chord's".
- **The repository's tools** take nothing: `registry`, `mark`,
  `screenshots`, `social`.
- **Stage names are the package's own** (Q4), so `compile` is only chord's
  `bun build --compile`, `selftest` only chord's binary self-test, and the
  check stage is called after the command it runs, `quality`, leaving
  `check` to Bun's native `bun check`.

## Q1. The command set

### Options

- **(a) Everything takes `<package>`**: `bun dev compile chord`,
  `bun dev test chord`, `bun dev selftest chord <binary>`. Uniform, but
  each of those has no second package to name: the positional would be a
  required word with one value, and D7 keeps `bun dev test` as it is.
- **(b) Only commands both packages have take `<package>`** (`quality`,
  `lint`, `release`); chord's tools and the repository's take none.
- **(c) A namespace per package**: `bun dev chord compile`,
  `bun dev cursor-cloud-acp quality`. Collides with `bun dev chord`, which
  runs chord, and reads every command twice.

**Choice: (b).** It adds a positional only where it chooses something, and
no existing command changes its argv except `quality`, `lint` and
`release`, which have to (D3, D6, D7).

**The checks command: `quality`** (D6 allows either). `bun check` is
Bun's native type check and is the `types` step inside the checks; `bun dev
check chord` would differ from it by one word and do six times as much.
`quality` keeps the word everyone already types. The release stage that
runs it is renamed `quality` too, so one word names one thing.

### The tree as help prints it

`bun dev --help` (Cliffy's layout, colours left out; `<package>`'s values
come from the packages found, Q2):

```
Usage:   bun dev
Description:

  chord's build, release and maintenance tools. A command that takes
  <package> runs that package's steps from its steps.ts and nothing else:
  chord or cursor-cloud-acp, its npm name without the scope.

Options:

  -h, --help  - Show this help.

Commands:

  quality      <package>              - A package's checks in its steps.ts's order, stopping at the first that fails.
  lint         <package> [args...]    - ESLint with a package's config over its files; the rest of the arguments are ESLint's.
  release                             - Release one package: release <package>. With none, releases nothing.
  chord        [args...]              - chord's: run it from source with React's production build.
  test         [args...]              - chord's suite with bun test, a worker per core.
  compile                             - chord's binary with bun build --compile into dist/<target>/chord.
  npm                                 - chord's five npm packages laid out in npm/ from dist/.
  selftest     <binary>               - chord's release self-test of one binary.
  memory                              - chord's long-run memory check.
  registry                            - Refetch the ACP Registry into src/registry.ts.
  mark                                - Rasterise scripts/mark.svg into src/ui/header/mark.ts.
  screenshots  [names...]             - Retake docs/images/ from chord on the fake agent.
  social                              - GitHub's social preview from docs/images into dist/.
```

`riff-models` leaves with CHD-621; if CHD-621 lands after this, it sits
among chord's tools until then, unchanged.

`bun dev quality --help`:

```
Usage:   bun dev quality <package>
Description:

  A package's checks, as its steps.ts lists them, run in order from the
  repository's root; the first that fails stops the run, is named, and
  its status is the command's.

Options:

  -h, --help    - Show this help.
  --static      - Only the steps steps.ts marks static: no suite, no build.

Examples:

  chord's static checks           bun dev quality chord --static
  the package's whole checks      bun dev quality cursor-cloud-acp
```

A missing or unknown package is Cliffy's own refusal, as tried:
`Missing argument(s): package`, and `Argument "package" must be of type
"package", but got "x". Expected values: "chord", "cursor-cloud-acp"`.
That says which packages there are, so `quality` and `lint` need no words
of their own for it. `release` does (D3), below.

`bun dev lint <package> [args...]` has `.stopEarly()` as today's `bun lint`:
`bun dev lint chord --fix` passes `--fix` on (tried); `bun dev lint --fix`
is refused as an unknown package `--fix` (tried), and an empty argument
still needs `--`.

`bun dev release --help`:

```
Usage:   bun dev release
Description:

  Release one package, on the owner's machine: release <package>. Each
  package's stages are its own, from its steps.ts; see
  bun dev release <package> --help. With no package it releases nothing,
  does no preflight and no authentication, and says which packages there
  are.

Options:

  -h, --help              - Show this help.
  --bump     <version>    - An exact version above package.json's, or major, minor, patch or fix.
  --channel  <name>       - A pre-release on this channel, from the branch of that name.
  --dry-run               - Every stage but publish.

Commands:

  chord             - @chorded/chord and its four platform packages: install, quality, natives, compile, sign, selftest, notarise, pack, publish.
  cursor-cloud-acp  - @chorded/cursor-cloud-acp: install, quality, build, pack, publish.
```

`--bump`, `--channel` and `--dry-run` are `globalOption`s of `release`, so
`bun dev release --bump minor` still reaches `release`'s own action, which
says `release: not clear which package to release: bun dev release
<package> (chord, cursor-cloud-acp)` on stderr and exits 1 (tried: the
action receives `{"bump":"minor"}`). `bun dev release foo` is Cliffy's
`Unknown command "foo". Did you mean command "chord"?`.

`bun dev release chord --help` adds the stage options, typed by chord's
stage enum, and its stage list from each stage's `about` in steps.ts
(today's `RELEASE` text keeps its paragraphs, "package.json" becoming
"the package's package.json"):

```
Options:

  --skip  <stages>    - Leave these stages out (comma-separated).
  --only  <stages>    - Run only these stages (comma-separated).
  --from  <stage>     - Start at this stage.
  --to    <stage>     - Stop after this stage.
  --npm   <name>      - Publish only this npm package: @chorded/chord-darwin-arm64, … or @chorded/chord.

Stages:
  install    bun install --frozen-lockfile
  quality    bun dev quality chord
  natives    every platform's packages installed; the macOS native libraries signed
  compile    bun dev compile --all; each binary's kind checked with file(1)
  …
  publish    the four platform packages, a wait until npm answers for each, then @chorded/chord, the tag v<version> and a draft GitHub release
```

A stage of another package is refused by Cliffy, naming the package's
own (tried): `Option "--only" must be of type "stage", but got "compile".
Expected values: "install", "quality", "build", "pack", "publish"`.

### Today → new

| Today | New | Note |
| --- | --- | --- |
| `bun quality` | `bun dev quality chord` | D7; `scripts/quality.ts` goes |
| `bun quality --static` | `bun dev quality chord --static` | CI's static job |
| `bun lint [args…]` | `bun dev lint chord [args…]` | D7; `scripts/lint.ts` goes |
| — | `bun dev quality cursor-cloud-acp [--static]`, `bun dev lint cursor-cloud-acp [args…]` | CHD-622 |
| `bun dev release` | `bun dev release chord` | D3: a bare run releases nothing |
| `bun dev release minor` / `1.2.3` | `bun dev release chord --bump minor` / `--bump 1.2.3` | D4 |
| `bun dev release major --channel next` | `bun dev release chord --bump major --channel next` | |
| `bun dev release --only publish --package chord-linux-x64` | `bun dev release chord --only publish --npm @chorded/chord-linux-x64` | Q3 |
| `--package chord` (the shim) | `--npm @chorded/chord` | full npm names, so `chord` never means the shim |
| stage `check` | stage `quality` | Q4 |
| `--skip install,check` | `--skip install,quality` | |
| `bun dev chord`, `test`, `compile`, `npm`, `selftest`, `memory` | unchanged | chord's; help says so |
| `bun dev registry`, `mark`, `screenshots`, `social` | unchanged | the repository's |
| `bun dev riff-models` | goes with CHD-621 | |
| `bun check`, `bun fmt` | unchanged | Bun's own, called by steps |
| package.json `scripts.quality`, `scripts.lint` | gone; only `dev` | back to CHD-411 |

## Q2. The per-package file

### Name

Options: **`steps.ts`** (what it holds: the package's steps, D5), `checks.ts`
(CHD-622's: too narrow now that it holds the release's stages),
`dev.ts` (collides with `scripts/dev.ts`), `package.ts`, `release.ts`
(too narrow the other way). **Choice: `steps.ts`** at each package's root:
`steps.ts` at the repository's root for chord, whose package is the root;
`packages/cursor-cloud-acp/steps.ts`.

### Shape

Options:

- **(a) A TypeScript module whose default export `satisfies PackageSteps`**,
  a type `scripts/dev/steps.ts` exports. Checks are data (a name, an argv
  or a function, `static`); release stages carry functions, because
  chord's sign, notarise and pack are code in `scripts/dev/release/`, not
  argv.
- **(b) JSON or YAML of argv only.** Cannot hold chord's stages without
  each becoming a script of its own, spawned with its arguments as strings.
- **(c) package.json `scripts`** (CHD-622's rejected (b)): no step named on
  failure, Bun's node shim under every script.

**Choice: (a).** The type is `bun check`'s to enforce, and the file stays
data except where a stage is code.

```ts
// scripts/dev/steps.ts (types; the runner and discovery in the same module)

/** One check: an argv run from the repository's root, or a function answering a status. */
export interface Check {
  readonly name: string;
  /** Run by `--static` too; the suite, a build and a smoke are not. */
  readonly static?: boolean;
  readonly run: readonly string[] | (() => number | Promise<number>);
}

/** One release stage, in the package's order; publish is the release's own. */
export interface Stage {
  readonly name: string;
  /** The line `bun dev release <package> --help` lists it with. */
  readonly about: string;
  /** Refused anywhere else, before preflight, when selected. */
  readonly machine?: { readonly platform: string; readonly arch: string };
  /** Found before any stage runs, after authentication (signing identity, notary). */
  readonly ready?: (release: Release) => void | Promise<void>;
  /** The stage that puts the version into what is published: a new version needs it. */
  readonly versioned?: boolean;
  readonly run: (release: Release, version: string) => void | Promise<void>;
}

export interface PackageSteps {
  readonly checks: readonly Check[];
  /** ESLint's argv for this package, before `bun dev lint`'s own arguments. */
  readonly lint: readonly string[];
  readonly release: {
    readonly stages: readonly Stage[];
    readonly publish: {
      /** Full npm names in publish order; the last is the package's main one. */
      readonly npm: readonly string[];
      readonly tag: (version: string) => string;
      /** Before the first npm publish (chord: the source archives rechecked). */
      readonly before?: (release: Release, version: string) => void;
      /** After the tag is pushed (chord: the draft GitHub release, D9). */
      readonly after?: (release: Release, version: string) => void;
      /** Whether `after` needs `gh`, so preflight checks it. */
      readonly gh?: boolean;
    };
    /** Package-specific preflight (chord: each pin in src/chorded.ts on npm, CHD-622). */
    readonly preflight?: (release: Release, version: string) => void;
  };
}

/** Bun running `bun dev`, for an argv: what the checks spawn today. */
export const BUN = process.execPath;
```

The release appends `publish` to the package's stages; it is the
release's own code (`scripts/dev/release/publish.ts`), told by
`release.publish` what to publish and how to tag. So the file says what
publishes and in what order (D5), and the npm wait, the per-package skip
of what npm has, the checksums and the terminal hand-over stay one
implementation, tested once.

### chord's `steps.ts`, in full

```ts
/**
 * chord's steps, run by `bun dev` (scripts/dev/steps.ts): its checks and
 * its release. Dev tooling, never shipped: no npm/ layout copies it and
 * src/ may not import it.
 */
import { BUN, type PackageSteps } from './scripts/dev/steps.ts';

const ARM = 'dist/bun-darwin-arm64/chord';
const X64 = 'dist/bun-darwin-x64/chord';
const ARM_MAC = { platform: 'darwin', arch: 'arm64' } as const;
// Every heavy module is imported when its stage runs, so parsing any
// `bun dev` command loads none of them.
const release = () => import('./scripts/dev/release/chord.ts');

export default {
  checks: [
    { name: 'types', static: true, run: [BUN, 'check'] },
    {
      name: 'covered',
      static: true,
      run: async () =>
        (await import('./scripts/dev/covered.ts')).covered({
          project: '.',
          outside: ['packages/'],
        }),
    },
    { name: 'eslint', static: true, run: [BUN, 'run', 'eslint', '.'] },
    { name: 'format', static: true, run: [BUN, 'fmt', '--check', '.'] },
    { name: "lint/'s tests", static: true, run: [BUN, 'test', 'lint/'] },
    {
      name: 'the suite',
      run: async () => (await import('./scripts/dev/tools.ts')).test([]),
    },
  ],
  lint: [BUN, 'run', 'eslint', '.'],
  release: {
    stages: [
      {
        name: 'install',
        about: 'bun install --frozen-lockfile',
        run: async (r) => (await release()).install(r),
      },
      {
        name: 'quality',
        about: 'bun dev quality chord',
        run: async (r) => (await release()).quality(r, 'chord'),
      },
      {
        name: 'natives',
        about: "every platform's packages installed; the macOS native libraries signed",
        machine: ARM_MAC,
        ready: async (r) => void (await release()).identity(r),
        run: async (r) => (await release()).natives(r),
      },
      {
        name: 'compile',
        about: "bun dev compile --all; each binary's kind checked with file(1)",
        versioned: true,
        run: async (r) => (await release()).compile(r),
      },
      {
        name: 'sign',
        about: 'both macOS binaries signed, verified and their entitlements compared',
        machine: ARM_MAC,
        ready: async (r) => void (await release()).identity(r),
        run: async (r) => (await release()).sign(r, [ARM, X64]),
      },
      {
        name: 'selftest',
        about: 'each macOS binary run on the fake agent, the window in tmux (the x64 one under Rosetta)',
        run: async (r) => {
          const { selftest } = await release();

          await selftest(r, ARM);
          await selftest(r, X64, 'x86_64');
        },
      },
      {
        name: 'notarise',
        about: "one zip submitted to Apple; each binary's cdhash found in Apple's log",
        machine: ARM_MAC,
        ready: async (r) => (await release()).notaryReady(r),
        run: async (r) => (await release()).notarise(r, [ARM, X64]),
      },
      {
        name: 'pack',
        about: 'the five packages laid out and packed, their sha256 recorded, the tarballs installed and checked',
        run: async (r) => (await release()).pack(r),
      },
    ],
    publish: {
      npm: [
        '@chorded/chord-darwin-arm64',
        '@chorded/chord-darwin-x64',
        '@chorded/chord-linux-arm64',
        '@chorded/chord-linux-x64',
        '@chorded/chord',
      ],
      tag: (version) => `v${version}`,
      before: …, // fetchedSource, as publish.ts calls it today
      after: …, // draftRelease, as today
      gh: true,
    },
    preflight: …, // CHD-622's pin check, added by CHD-622
  },
} satisfies PackageSteps;
```

(`…` marks a lazy import of the existing function, written as the stages
are; `scripts/dev/release/chord.ts` re-exports chord's stage functions so
the file imports one module. The npm list is the one `targets.ts` already
derives; ship may write `npm` from it if the steps-file import rule below
allows that one value import.)

### cursor-cloud-acp's `steps.ts`, in full

```ts
/**
 * cursor-cloud-acp's steps, run by `bun dev` on Bun (scripts/dev/steps.ts):
 * its checks and its release. Dev tooling, outside the package's `files`
 * and its Node tsconfig; never in the tarball.
 */
import { BUN, type PackageSteps } from '../../scripts/dev/steps.ts';

const HERE = 'packages/cursor-cloud-acp';
const lib = () => import('./scripts/release.ts');

export default {
  checks: [
    { name: 'types', static: true, run: [BUN, 'check', '-p', HERE] },
    {
      name: 'covered',
      static: true,
      run: async () =>
        (await import('../../scripts/dev/covered.ts')).covered({
          project: HERE,
          inside: [`${HERE}/`],
          outside: [`${HERE}/steps.ts`],
        }),
    },
    {
      name: 'eslint',
      static: true,
      run: [BUN, 'run', 'eslint', '--config', `${HERE}/eslint.config.ts`, HERE],
    },
    { name: 'format', static: true, run: [BUN, 'fmt', '--check', HERE] },
    { name: 'tests', run: [BUN, 'test', `./${HERE}/tests/`] },
    { name: 'build', run: async () => (await lib()).build() },
    { name: 'smoke', run: async () => (await lib()).smoke('scratch') },
  ],
  lint: [BUN, 'run', 'eslint', '--config', `${HERE}/eslint.config.ts`, HERE],
  release: {
    stages: [
      {
        name: 'install',
        about: 'bun install --frozen-lockfile',
        run: async (r) =>
          (await import('../../scripts/dev/release/build.ts')).install(r),
      },
      {
        name: 'quality',
        about: 'bun dev quality cursor-cloud-acp',
        run: async (r) =>
          (await import('../../scripts/dev/release/build.ts')).quality(
            r,
            'cursor-cloud-acp',
          ),
      },
      {
        name: 'build',
        about: 'bun build --target=node --packages=external into dist/; nothing bundled, by the metafile',
        versioned: true,
        run: async () => void (await lib()).build(),
      },
      {
        name: 'pack',
        about: 'npm pack into dist/release/cursor-cloud-acp/, its sha256 recorded, the tarball installed by Node 22.13+ and run',
        run: async (r, version) => (await lib()).pack(r, version),
      },
    ],
    publish: {
      npm: ['@chorded/cursor-cloud-acp'],
      tag: (version) => `cursor-cloud-acp-v${version}`,
      // No GitHub release (D9): no `after`, no `gh`.
    },
  },
} satisfies PackageSteps;
```

`HERE` paths run from the repository's root (below). The package's
`scripts/release.ts` (build, pack, smoke) is CHD-622's to write; the steps
it calls are D8's list.

### What `bun dev` reads, and how it finds the files

At start, before parsing, `scripts/dev/steps.ts`'s `packages(root)`:

1. reads the root `package.json`: its name, and its `workspaces` patterns,
   expanded by globby (already a dependency) to folders with a
   `package.json`;
2. names each package by its npm name without `@chorded/` (D2); a name
   outside the scope, two packages with one name, or a package with no
   `steps.ts` stops `bun dev` naming the folder;
3. imports each `steps.ts` (default export), root first, then by name.

The names feed `<package>`'s `EnumType`; each package's stage names feed
its `release` subcommand's. Everything else in a steps file (argv,
functions) is used only when its command runs.

**A broken steps file stops every `bun dev` command**, `bun dev chord`
included, since all are imported to build the tree. Options: accept it
(a steps file is checked by `bun check` in its package's `quality` and in
CI before it can reach main, and the error names the file); or build
`release`'s subcommands lazily, which Cliffy does not offer for a
command's types without peeking at argv by hand (refused by the one rule).
**Choice: accept**, and keep the files cheap to import: a test reads each
`steps.ts`'s imports and allows only `scripts/dev/steps.ts` as a value
import (types and dynamic `import()` aside), so parsing `bun dev` still
loads no release module, as `scripts/dev.ts`'s comment promises today.

**Never shipped.** chord's `npm.ts` writes named files only; a test in
`tests/scripts/dev/npm_test.ts` already lists the package's files and gains
"no `steps.ts`". cursor-cloud-acp's `files` is `dist`, `README.md`,
`LICENSE`; its pack stage's check of the tarball's file list (CHD-622)
names `steps.ts` among what must be absent. ESLint forbids `src/**` and
`packages/*/src/**` to import any `steps.ts` or `scripts/`.

**Which project checks it.** A `steps.ts` runs on Bun, as `bun dev`'s, so
both are in the root `tsconfig.json` (`include` gains `steps.ts` and
`packages/*/steps.ts`) and outside the package's Node project. chord's
`covered` counts `packages/*/steps.ts` as chord's; the package's leaves it
out (`outside` above). This is the one exception to "chord's checks leave
`packages/` out" (D8), and it is the steps file's own nature, not the
package's code: **OWNER-light**, see open question 3.

## Q3. Publishing

### Options

- **(a) A release stage only, as today.** `bun dev release <package>
  --only publish` publishes what an earlier run packed.
- **(b) Its own command, `bun dev publish <package>`**, and no publish
  stage: a release ends at pack, a second command publishes.
- **(c) Both**: the stage, and `bun dev publish <package>` as another name
  for `release <package> --only publish`.

**Choice: (a).** Publishing is not separable from what the release guards
around it: CHD-547's version rule, the version commit pushed before any
stage and dropped by a run without publish, the branch level with origin,
the tag check, npm authentication, resume. Under (b) the version commit
would have to survive between two commands, or `publish` would repeat all
of preflight and the commit logic: the same guards in two commands, or a
release that leaves a commit for another command to drop. (c) is two
names for one action, which the brief asks to avoid. Today's two real
uses, a whole release and finishing a stopped one, are `bun dev release
chord` and `bun dev release chord` again (it resumes), with
`--only publish` for a dry run's tarballs.

**OWNER-1 (the owner asked about `bun dev publish`).** Options (a), (b),
(c) above. Recommendation (a), for the reason above.

### What replaces `--package`

Options: **(i) `--npm <name>` on `release chord` only, taking the full npm
name** (`@chorded/chord-linux-x64`, `@chorded/chord`); (ii) the same with
unscoped names (`chord-linux-x64`, `chord`): `--npm chord` would then mean
the shim while `release chord` means the whole package, one word twice;
(iii) drop it: a stopped publish already resumes by rerunning, publishing
only what npm lacks, so `--package` is needed only to publish one platform
package ahead of the others, which nothing in the release asks for.

**Choice: (i).** It keeps an existing owner's tool under an unambiguous
name. The option is declared only on a package whose `publish.npm` has
more than one name, so `release cursor-cloud-acp --npm …` is Cliffy's
unknown option. Its rules stay today's: it needs `publish` among the
stages, conflicts with `--dry-run`, and a single platform package leaves
tagging to the run that publishes the last.

**OWNER-2.** (i), (ii) or (iii). Recommendation (i); (iii) if the owner
has not used `--package` since CHD-395 and is content with resume alone.

## Q4. Stages and steps

### Options

- **(a) One stage enum for every package** (CHD-622's table): `install,
  check, natives, compile, sign, selftest, notarise, pack, publish`; a
  package fills the stages it has. `--only/--from/--to` naming one it
  lacks is refused, `--skip` of one ignored. Words bend: cursor-cloud-acp's
  `bun build --target=node` is "compile", its Node smoke "selftest".
- **(b) Each package's stages are its own**, named and ordered in its
  `steps.ts` (D5), with `publish` appended by the release. `release
  <package>` is a subcommand per package whose stage `EnumType` is that
  package's, so a stage the package does not have cannot be named: Cliffy
  refuses it and lists the package's (tried, quoted under Q1). "What a
  stage the package does not have does" stops being a question.

**Choice: (b).** D5 says each package defines its steps in their order;
(b) is that, with nothing to refuse by hand and no word with two meanings.

**OWNER-3.** (a) as CHD-622's design wrote it, or (b). Recommendation (b);
CHD-622's stage table then becomes the two `steps.ts` files above.

### Selection

`selectStages(stages, options)` keeps today's rules over the package's
list: `--only` conflicts with `--skip/--from/--to` (Cliffy's `conflicts`),
`--from`/`--to` bound by the package's order, `--dry-run` removes publish,
`--dry-run --only publish` and an empty selection refused, `--npm` needs
publish.

### What is the release's and what is a package's

The release (`scripts/dev/release/`, one implementation, tested once) owns
everything about a version reaching npm, parametrised by the package's
name, folder and `release.publish`:

| Guard or duty | Owner | Per package |
| --- | --- | --- |
| a stage's `machine` (arm64 Mac) | the stage, checked by the release first, over selected stages only | chord's natives, sign, notarise; none for cursor-cloud-acp |
| a clean tree, untracked files included | release | the whole tree, for any package |
| version, `--bump`, `--channel` (CHD-412, CHD-577) | release | the package's `package.json`; bumps on a channel count from npm's latest of the package's main npm name |
| a new version needs a `versioned` stage | release | chord: compile; cursor-cloud-acp: build |
| CHD-547: no other version while the package's own is not on npm | release | against the main npm name (`publish.npm`'s last) |
| main npm name already at the version: refused | release | as today |
| resume: an earlier npm name at the version, the main one not | release | chord as today; cursor-cloud-acp has one name, so never resumes this way (open question 2) |
| the package's own preflight | the package (`release.preflight`) | chord: CHD-622's pins |
| branch level with origin, when publishing | release | main, or the channel's branch |
| no tag here or on origin | release | `publish.tag(version)` |
| `gh` signed in | release, when `publish.gh` | chord only (D9) |
| npm authentication, every run | release | both |
| signing identity, notary credentials | the stage's `ready` | chord's |
| the version commit `chore: <package> v<version>`, pushed or dropped; signals | release | chord's message unchanged; cursor-cloud-acp commits its `package.json` (and `bun.lock` if it records the version: open question 4) |
| checksums of packed tarballs before publish | release | the files `pack` recorded |
| npm publish, `--tag <channel>`, the wait for each, the main one last | release | `publish.npm`'s order |
| the tag, pushed | release | `publish.tag` |
| a draft GitHub release | the package (`publish.after`) | chord only (D9) |

Order of a run, unchanged for chord: parse → machine guard of selected
stages → version → preflight (release's, then the package's) → npm
authentication → `ready` of selected stages → version commit (pushed if
publishing) → stages in order → publish. A dry run on a channel prints
each of `publish.npm`'s npm arguments, as today.

### The check stage

The release's `quality` stage calls the same runner as `bun dev quality
<package>` in process (not `bun quality` spawned, as `build.ts` does
today), with `static: false`. chord's release never runs
cursor-cloud-acp's checks and the reverse (D5).

## Run-time behaviour

Every step runs from the repository's root, as `tools.ts`'s `spawn` does
today, with the terminal handed over. One `bunfig.toml` (the jsr registry,
`[run] bun = true`) and one `node_modules` apply; a package's argv names
its paths from the root (`packages/cursor-cloud-acp/...`). Running from the
package's folder would depend on how Bun finds `bunfig.toml` from a
subfolder, which nobody has checked: open question 5.

| Scenario | Expected |
| --- | --- |
| a check exits non-zero | the run stops; stderr `quality <package>: <step> failed with status <n>` (today's CHD-467 line with the package); `bun dev` exits `n` |
| a check dies by a signal | status 128 + its number, as `spawn` answers today |
| Ctrl+C during `quality` | the foreground group gets SIGINT: the step's child ends, `bun dev` ends 130; nothing to clean but the smoke's scratch (next row) |
| the smoke stopped half way | its scratch is a fixed `dist/smoke/cursor-cloud-acp/`, emptied at its start, never `mkdtemp`: a killed run leaves at most one folder that the next run clears |
| no Node, or one below 22.13, for the smoke | the step fails saying which `node` it found past Bun's (CHD-395's finder, moved from `release/lib.ts` to a module both use) and which it needs; status 1 |
| Ctrl+C, SIGTERM, SIGHUP during a release | today's `holdVersion`/`dying` for every package: an unpushed version commit dropped; stages from a steps file run inside it |
| SIGKILL during a release | as today: the guide's `git reset --keep HEAD~1` |
| a broken `steps.ts` | every `bun dev` command stops at start naming the file (Q2) |
| a workspace with no `steps.ts`, out of scope, or a duplicate name | `bun dev` stops at start naming the folder |
| `bun dev release` with no package, any global options | stderr names the packages, exit 1; no network, no git, no npm |
| two releases at once in one checkout | not supported, as today: the second's preflight finds the first's commit or push (tree, branch level). No lock |
| `bun dev quality chord` while `packages/` is broken | passes: chord's steps leave `packages/` out (D8) except the steps files' type check |
| `bun dev quality cursor-cloud-acp` on CI's static job | static steps need no Node; the `node` job (CHD-622) runs the whole |

Nothing here needs `bun build --compile` or `src/platform/`: the steps
and the runner are dev tooling on Bun, outside the binary.

## Also

### Files in `scripts/`

- `scripts/dev.ts`: the tree above. `devCommand(actions, packages)` takes
  the found packages so a test passes fake ones. `quality` and `lint`
  join `DevActions`; `release`'s action gains the package's name.
- `scripts/dev/steps.ts` (new): the types, `BUN`, `packages(root)`
  (discovery), `quality(steps, { static })` (today's `tools.check`,
  generalised), `lint(steps, args)`.
- `scripts/dev/tools.ts`: `check` and `lint` leave for `steps.ts`; `chord`,
  `test`, `qaPlace` stay.
- `scripts/quality.ts`, `scripts/lint.ts`: deleted; package.json's
  `scripts` keeps `dev` alone.
- `scripts/dev/covered.ts`: `covered({ project, inside?, outside? })`,
  from the CLI as today for no arguments.
- `scripts/dev/release/`: `select.ts` takes the package's stage names;
  `stages.ts` runs a package's stages instead of its own `steps` record;
  `preflight.ts`, `version.ts`, `bump.ts`, `publish.ts` take a `Releasing`
  record (name, folder, `release.publish`) instead of chord's constants;
  `lib.ts`'s `PACKAGES`/`PLATFORMS` become chord's `publish.npm`; a new
  `chord.ts` re-exports chord's stage functions; `build.ts`'s `check`
  becomes `quality(release, name)` on the runner.
- `steps.ts` at the root (new); `tsconfig.json`'s `include`; `eslint.config.ts`'s
  import boundary, with its snippet in `lint/config_test.ts`.

### Tests (`tests/` mirrors; no fake ACP scenario needed)

Nothing here talks ACP, so no `tests/fixtures/fake_agent/` scenario. The
release's tests keep the scratch repository and npm, sleep and plutil
faked on PATH (`tests/scripts/dev/release/scratch.ts`).

- `tests/scripts/dev_test.ts`: every route through the tree with two fake
  packages (one with five npm names, one with one): `quality`, `--static`,
  `lint` passing `--fix` and `--`; Cliffy's refusals for a missing or
  unknown package; bare `release` with and without `--bump`, nothing run;
  `--only` with another package's stage refused; `--npm` absent on a
  one-name package; `--bump` values; `bun dev --help` lists the commands
  with chord's marked. `quality_test.ts` and `lint_test.ts` fold in here.
- `tests/scripts/dev/steps_test.ts`: discovery from scratch roots (root
  only; root + workspaces; no `steps.ts`; wrong scope; duplicate);
  the runner in order, stopping at the first failure with its status and
  line, `--static`'s filter, function steps, a signal's status; and each
  tracked `steps.ts` imports no value module but `scripts/dev/steps.ts`.
- `tests/steps_test.ts` (for the root `steps.ts`): chord's checks are D8's
  six in order with their `static` marks; none names `packages/` as an
  input; the stages are today's nine, `check` renamed `quality`; `npm` is
  the platform packages then `@chorded/chord`, matching `targets.ts`.
- `tests/scripts/dev/release/select_test.ts`, `stages_test.ts`,
  `preflight` and `publish` tests: parametrised over chord and a fixture
  one-name package: machine guard only for selected stages that declare
  it; `versioned` required for a new version; `gh` only with `publish.gh`;
  tag form; commit message; CHD-547 against the main npm name; dry run's
  printed arguments; `--npm`.
- `tests/scripts/dev/covered_test.ts`: `inside`/`outside`.
- `tests/scripts/dev/npm_test.ts`: no `steps.ts` in chord's layout.
- cursor-cloud-acp's own `packages/cursor-cloud-acp/tests/steps_test.ts`
  (D8's seven, their marks): CHD-622's.

### CI

```yaml
static:  bun dev quality chord --static      # env CHORD_LIBFX_ALL_TARGETS=1, as today
tests:   bun dev test --shard=n/3            # unchanged (D7)
compile: bun dev compile                     # unchanged
node:    bun dev quality cursor-cloud-acp    # CHD-622 adds it, setup-node 22.13
check:   needs every job above
```

### Docs that follow, in the same change

AGENTS.md (the command block, "How code is written", "Choosing checks"),
`scripts/AGENTS.md` (its first and release paragraphs), `tests/AGENTS.md`
where it names a command, CONTRIBUTING.md, `docs/guide.md`'s release
section, `docs/memory.md`, `.chord/teams/ship.md` (names
`bun quality --static` five times; a team file every ship run reads),
`scripts/dev/memory.ts`'s and `covered.ts`'s comments, `RELEASE` in
`scripts/dev.ts`. `docs/design/CHD-533.md` and other past designs stay as
written. Test data that merely contains the words (`tests/fixtures/
markdown.ts`) is checked case by case, not rewritten blindly.

### Landing before CHD-622

CHD-623 lands first, alone, with one package: the root `steps.ts`, the
discovery (which finds no `workspaces` yet and offers `chord` only), the
runner, `release chord`, CI's static job, and the docs. The multi-package
paths are tested on fixture packages in scratch roots, so nothing waits
for cursor-cloud-acp. CHD-622 then adds `"workspaces"`, its package, its
`steps.ts`, CI's `node` job, and chord's pin preflight, without touching
`bun dev`'s tree. In 0.70.0 the order is CHD-623, then CHD-622, then the
package's 0.1.0, then chord.

## Open questions

1. **OWNER-1** publish: stage (recommended), command, or both (Q3).
2. **OWNER-2** `--package`'s replacement: `--npm <full name>` (recommended),
   unscoped, or dropped (Q3). Related, for the lead: CHD-622 says a
   cursor-cloud-acp run whose version npm has but whose tag is missing
   resumes by tagging. Under chord's rules, unchanged here, a main npm name
   at the version is refused, and publish's own failure already prints the
   manual `git tag` command. I recommend the same rule for both packages,
   no tag-only resume; this contradicts CHD-622's text and needs the lead's
   call or the owner's.
3. **OWNER-3** stages per package (recommended) or one shared enum (Q4).
   Light, for the lead: the steps files are type-checked by chord's
   project, the one place chord's checks reach into `packages/` (Q2).
4. Does `bun.lock` record a workspace's version, so a cursor-cloud-acp
   version commit must update it, and by what (`bun install
   --lockfile-only`, or `bun pm version`)? Ship checks before writing
   `bump.ts`'s package path; if Bun has no command that does it, it comes
   back as a question, not a lock rewritten by hand.
5. Steps run from the repository's root. Whether running from a
   package's folder would pick up the root's `bunfig.toml` was not tried
   and is not needed by this design.
6. `bun dev npm` stays chord's layout command. With a second package
   published to npm the name reads wider than it is; renaming it (say,
   folding it into chord's `pack` stage only) is possible but not asked
   for. The lead may put it to the owner or leave it.
