# CHD-623 — the release's state (runtime, follow-up for O4)

The owner's answer to O4: the release keeps its current state in a
gitignored folder, per package; every run reads it at start and continues
from what is left; that state, not inference from git and npm, is how any
stopped release is resumed, one stopped after npm published and before the
tag or the draft included. With O1 (publish stays the last stage), O2
(`--package` and `--npm` dropped: `release chord` publishes everything in
order), O3 (each package's own stages) and O5 (only `quality`, `lint`,
`release` take a package).

This draft replaces the "A run stopped after npm published" paragraph of
`docs/design/CHD-623.md` and its O4, and the `--npm` row. Everything else in
the merged design's release section stands.

## The rule in one line

A release writes down every change it makes to the world before and after
making it; a later run of the same package does what the state says is left,
and reads git, npm or GitHub only as a **guard** (refuse on a mismatch) or to
settle one **pending** act (killed between starting an act it cannot take
back and recording that it ended). Nothing is inferred from them otherwise.

## Where it lives

`.release/<package>/state.json` at the root of the checkout, `.release/`
added to `.gitignore`. One folder per package: chord's and
cursor-cloud-acp's states are independent files.

- Not under `dist/`. Nothing in `scripts/` removes `dist/` whole today, but
  `dist/` is build output by name: the owner, a `bun dev compile` or a
  future build step may wipe it, and pack already `rm -rf`s its own folder
  under `dist/release/`. A state that says "npm has four of five" must not
  share a lifetime with tarballs that can be rebuilt.
- The release's artifacts stay where they are (`dist/<target>/chord`,
  `dist/release/tgz/`, `dist/release/source/`); the state records their
  sums, so a wiped or rebuilt artifact is caught, never published.
- `git status --porcelain --untracked-files=all` does not list ignored
  files, so the clean-tree guard is unaffected.
- `git clean -fdx` and a fresh clone lose it, as they lose `dist/` (O-S1).

## Format

JSON, read and validated with zod (already a dependency); written whole to
`state.json.<pid>.tmp` in the same folder, fsynced, then `renameSync`d over
`state.json` (rename within one folder is atomic on the file systems the
release runs on; `source.ts` and `sign.ts` already rename into place). A
leftover `.tmp` is never read and is removed by the next write. A kill at any
point leaves the previous whole state or the new one.

```ts
/** The state of one package's release in progress. */
interface ReleaseState {
  readonly format: 1;
  readonly package: string; // 'chord'
  readonly version: string; // '0.70.0', '0.71.0-next.2'
  readonly channel: string | null;
  /** The branch it publishes from: main, or the channel's. */
  readonly branch: string;
  /** HEAD when the run that made this state started. */
  readonly base: string;
  /** The version commit, when the version was new. */
  readonly versionCommit?: {
    readonly state: 'pending' | 'made' | 'pushed';
    readonly sha?: string;
  };
  /** The commit the stages build from; the tag points here. */
  readonly built: string;
  /** Done stages, by name, with the sums of what each left for later ones. */
  readonly stages: Record<
    string,
    { readonly at: string; readonly outputs: Record<string, string> }
  >;
  /** Each npm name of the publish stage, in its order. */
  readonly npm: Record<string, 'pending' | 'sent' | 'answered'>;
  readonly tag?: { readonly state: 'pending' | 'made' | 'pushed' };
  /** chord only (githubRelease). */
  readonly draft?: { readonly state: 'pending' | 'made'; readonly url?: string };
}
```

`outputs` are paths relative to the root with their sha256: chord's
`compile` the four binaries, `sign` the two macOS ones as signed, `pack` the
five tarballs; cursor-cloud-acp's `build` its `dist/` files, `pack` its
tarball. That needs one field on the merged design's `Stage`:
`outputs?: (release, version) => readonly string[]`. `SHA256SUMS` stays as
pack writes it today; publish checks a tarball against the state's sum.

`format` is a literal: a state of another format is refused, naming the
file and both formats, and left untouched (O-S4). No migration code.

## When it is written

Order of a run, from the merged design, with the state in it:

1. Parse and validate; a bare `release` stops here, touching nothing.
2. **The lock** (`proper-lockfile`, on a file in git's common directory,
   so worktrees of one clone share it), held to the end.
3. **Read the state** of the named package. Only after the lock: two runs
   never read the same state.
4. With a state: the continuation guards (below). Without: today's fresh
   guards (machine, version, preflight, CHD-547, branch and tag when
   publishing).
5. npm authentication, `ready` of selected stages, as today.
6. The writes:

| Moment | Written before | Written after |
| --- | --- | --- |
| first change to the world (version commit, or first stage) | the state created: package, version, channel, branch, base, `built` = HEAD | — |
| version commit | `versionCommit: pending` | `made` with its sha; `built` = that sha |
| push of the version commit | — | `pushed` |
| each stage | — | `stages[name]` with `outputs` sums |
| each `npm publish` | `npm[name] = pending` | `sent` when npm exits 0; `answered` when `npm view` answers |
| the tag, made on `built` (`git tag -a <tag> <built>`) | `tag: pending` | `made`, then `pushed` |
| the draft (chord) | `draft: pending` | `made` with gh's URL |
| everything done | — | the folder removed; the version printed last, as today |

Which runs keep a state:

- **A run that publishes** (publish selected, not `--dry-run`) writes it
  from its first change on.
- **A run without publish at package.json's version** (no version commit)
  writes it: `--to pack` today, `--only publish` tomorrow continues from
  pack's recorded tarballs.
- **A run without publish with a new version** writes none: its version
  commit is dropped at the end, as today, so nothing it built belongs to a
  commit that will exist. Its signal handling (drop the held commit) is
  unchanged.
- **`--dry-run`** writes none and is refused while the package has a state
  (O-S2).

## How a run with a state behaves

A run finds a state for its package and continues it. "Left" means: the
selected stages not in `stages`, then, if publish is selected, the npm
names not `answered`, the tag not `pushed`, the draft not `made`.

**Continuation guards**, all before authentication:

- format is 1, package matches, the state validates;
- the tree is clean;
- `built` (and the version commit, when `pushed`) is an ancestor of HEAD;
- package.json's version at `built` is the state's version;
- while a stage before publish is left: HEAD **is** `built` (the stages
  build from it). Once only publish is left: HEAD may be a descendant,
  since publish uses recorded artifacts and tags `built`;
- when publish is left: the branch is the state's, level with origin; the
  tag does not exist here or on origin unless the state says `made` or
  `pushed`; `gh` signed in for chord;
- every recorded `outputs` sum still holds, checked before the first stage
  runs; a missing or changed file is refused, naming it and the stage that
  made it: `--from <that stage>` rebuilds.

**Pending acts** — the only reads that change the state:

| Pending | Read | Then |
| --- | --- | --- |
| `versionCommit: pending` | HEAD and HEAD's parent | HEAD is `base`: commit again. HEAD's parent is `base` and HEAD changes only package.json to the version: record it `made`. Anything else: refused |
| `versionCommit: made` | — | push it, if HEAD is it or a descendant; else refused |
| `npm[name]: pending` | `npm view name@version` | answers: `answered`. Does not: publish again (npm refuses a second publish of one version, so this cannot publish twice) |
| `npm[name]: sent` | waits as today (`waitPublished`) | `answered` |
| `tag: pending` | `git tag --list`, and `ls-remote` | here and on `built`: `made`; on origin and on `built`: `pushed`; absent: tag again; on another commit: refused |
| `tag: made` | — | push |
| `draft: pending` | `gh release view <tag>` | exists: `made`. Does not: create |

**Guards that stay, on npm and git, outside pending acts:** an npm name the
state does not record as sent that npm already has is refused ("npm has
@chorded/chord-linux-x64@0.70.0, which this release did not publish"); a tag
the state did not make is refused. These replace today's skip of "already
published": a skip there was inference.

### Options with a state

| Option | Behaviour |
| --- | --- |
| none | every stage left, in order, then what is left of publish |
| `--bump <v>` | refused while a state is unfinished: "chord 0.70.0 is in progress (done: install … pack; npm 4 of 5): `bun dev release chord` continues it" — CHD-547's rule, from the state. An exact `--bump` equal to the state's version is the same as none |
| `--channel <c>` | must be the state's channel, else refused |
| `--skip <s>` | those stages are not run and stay not done |
| `--only <s>` / `--from <s>` | a selected stage already done is run again: it and every done stage after it are cleared from `stages` (written) before it runs. Refused for any stage before publish once any npm name is `sent` or further: npm has those bytes |
| `--to <s>` | stops after it; the state stays |
| `--dry-run` | refused while a state exists (O-S2) |
| publish selected, pack not done | refused: "publish needs pack's tarballs; pack is not done in chord 0.70.0" |

### Scenarios

| Situation | Outcome |
| --- | --- |
| No state, `release chord --bump minor` | fresh guards, state created, runs to the end, folder removed, version printed last |
| Killed by Ctrl+C in `compile` | `compile` not recorded; the next run starts at compile (install and quality are done) |
| SIGKILL mid-write | the previous whole state; the `.tmp` is ignored |
| Killed between `npm publish` exiting and `sent` written | `pending`; the next run asks `npm view`, records `answered`, goes on |
| Stopped after npm answered for all five, before the tag | next run (no options): guards (branch level, HEAD descends from `built`), tags `built`, pushes, drafts, removes the state |
| Tag pushed, draft failed | next run: `gh release view`, then creates the draft; the printed `gh` command of today is no longer the only way |
| Stopped before the tag, then a PR merged on main | HEAD descends from `built`, only publish left: the tag goes on `built`, not HEAD |
| Stopped before compile, then a PR merged | HEAD is not `built` and a build stage is left: refused (O-S5) |
| State's `built` not in HEAD's history (reset, rebase, squash) | refused, naming both shas |
| package.json at `built` says another version | refused |
| `--bump` while a state is unfinished | refused, naming the state's version and what is left |
| State of an older or newer format | refused, naming the file and the formats, file untouched |
| State whose everything is done (killed after the draft, before removal) | the run says "chord 0.70.0 is released", removes the state, and goes on as a run without one |
| cursor-cloud-acp's state in progress, `release chord` | independent: chord runs. The lock still allows one release at a time. chord's version commit moves HEAD, so cursor-cloud-acp's state, if a build stage is left, is refused afterwards (O-S5); if only publish is left, it continues |
| `dist/` wiped after pack | refused before the first stage, naming the missing tarball and `--from pack` (or earlier) |
| Tarball rebuilt by hand after pack | refused on its sum |
| State lost (`git clean -fdx`) with npm partly published | no state: the fresh guards refuse ("@chorded/chord-darwin-arm64@0.70.0 is on npm already"); finished by hand (O-S3) |
| A release begun by today's `bun dev` (no state), stopped | as the line above: one-time, at the switch |
| Second `bun dev release` while one runs | the lock refuses, naming the first's pid |

## What it replaces

- `preflight.ts`'s `mode: 'resume'` (a platform package on npm means
  resume) — gone; preflight is the fresh guards only, and "any npm name of
  the package has the version" is a refusal without a state.
- `stages.ts`'s resume branch (skip building, publish what is left) —
  replaced by "the stages left", from the state.
- `publish.ts`'s "already published: skip" — replaced by the state's `npm`;
  npm is read only for `pending`, and as the refusal guard above.
- `publish.ts`'s single-package path (`only`) — gone with `--npm` (O2).
- CHD-547 ("a new version only once package.json's is published") — with a
  state, the state's refusal; without one, kept as an npm guard, since a
  version commit pushed by a run whose state was lost is otherwise not seen.
- The failure lines that print `git tag …` / `gh release create …` to run
  by hand — kept as text, now ending "or run `bun dev release chord` to
  continue".
- `holdVersion`/`dropVersion` — unchanged for runs that keep no state.

## Module layout

- `scripts/dev/release/state.ts` (new): the zod schema, `readState(root,
  package)`, `writeState` (tmp, fsync, rename), `clearState`, and pure
  functions: `left(state, stages, selection)` (what runs, or why refused)
  and `cleared(state, from)`. No process, no git.
- `scripts/dev/release/continue.ts` (new): the continuation guards and the
  pending-act table, on `Release`'s `run` so fakes answer them.
- `preflight.ts`: the fresh guards only, by the package's main npm name and
  every npm name of its publish stage.
- `stages.ts`: lock → state → guards → stages, writing after each; removes
  the resume branch.
- `publish.ts`: takes the state, writes before and after each act; tags
  `built`.
- `scripts/dev/steps.ts`: `Stage.outputs`.

## Tests

Pure, in `tests/scripts/dev/release/state_test.ts`: the schema refusing a
missing field, an unknown format and a wrong package; `left` over every
selection option with a state (none, `--skip`, `--only`/`--from` clearing
later stages, refused after `sent`, publish without pack, `--dry-run`
refused); a done state reported as done; atomic write leaving the old file
when the rename never happens (write stopped before rename by an injected
fs), and a leftover `.tmp` ignored.

In a scratch root (`tests/scripts/dev/release/scratch.ts`) with fake `git`
remote, `npm`, `gh` and stage functions on PATH, parametrised over both
fixture packages (five npm names with a draft; one, without):

- a full run creates the state, records each stage and act, removes it;
- each stop point, by a fake that fails or a stage that throws once, then
  a rerun: after the version commit before push; after each stage; with
  `npm` pending (fake `npm view` answering, then not); after `sent` before
  `answered`; `tag: pending` with the tag present here, on origin, absent,
  on another commit; tag pushed and the draft failed; `draft: pending` with
  gh having it and not. Each rerun's fake log shows no act done twice and
  the tag on `built`;
- HEAD moved after only publish was left (tag on `built`) and with a build
  stage left (refused);
- `built` not an ancestor; package.json changed; a sum changed; an output
  missing;
- npm having a name the state did not send; a tag the state did not make;
- `--bump` with an unfinished state; a state of format 2;
- the two packages' states side by side, each continued alone;
- SIGTERM to a child run during a fake stage: the state holds the stages
  before it, no `.tmp` read.

No test reaches the real npm, GitHub or the network; the lock's test is the
merged design's.

## OWNER

- **O-S1. Where.** (a) `.release/<package>/` at the checkout's root,
  gitignored (recommended: the owner's words, visible, per worktree);
  (b) in git's common directory beside the lock (survives `git clean -fdx`,
  shared by worktrees, hidden); (c) under `dist/` (lost with a wiped
  `dist/`, while it may say npm has half a release).
- **O-S2. `--dry-run` while a state exists.** (a) refused (recommended: a
  dry run rebuilds and repacks, so it would replace artifacts whose sums the
  state records, and the real run would then refuse them); (b) allowed,
  reading and writing nothing, the next real run catching the changed sums.
- **O-S3. Clearing.** At the end of a full release the folder is removed
  (recommended; npm, the tag and the draft are the record). For an
  abandoned one: (a) by hand, `rm -r .release/chord`, which every refusal
  names (recommended: no new flag, and abandoning after npm published is
  the owner's judgement, not a command's); (b) a `--forget` flag, refused
  once any npm name is `sent`; (c) keep finished states as
  `.release/<package>/<version>.json` history.
- **O-S4. Another format.** (a) refused, file untouched (recommended: a
  release is rare, a migration is code for one run); (b) migrated forward.
- **O-S5. HEAD moved before a build stage ran** (a merge, or the other
  package's version commit). (a) refused; the owner runs `--from install`,
  which, while nothing is pushed or published, records HEAD as the new
  `built` (recommended); (b) refused with no way but clearing; (c) build
  from HEAD silently (tags what was built later than the version commit).
- **O-S6. A state lost with npm partly published.** (a) refused by the
  fresh guards, finished by hand (recommended: the owner rejected
  inference); (b) a flag that rebuilds a state from npm and git.
