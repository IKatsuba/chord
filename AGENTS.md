# AGENTS.md

This file provides guidance for every coding agent and person working here.
It is binding.

## What this is

chord is a full-screen terminal client for coding agents that speak the Agent
Client Protocol. `README.md` is the pitch, `docs/guide.md` the whole of what it
does, `docs/FEATURES.md` is the map of what gets built and in which order,
`docs/decisions.md` is why the stack is what it is. Read the README,
`FEATURES.md` and `decisions.md` before the first change.

The repository is public-ready from the first commit: everything in it — code,
comments, docs, commit messages, test names — is in English, and nothing in it
names a private path, a key, or a person's machine. `tests/privacy_test.ts`
fails `bun dev quality chord` on any file git tracks that names a home directory,
the name of the home of whoever runs it, or a path in Claude Code's own
directory there other than its public settings files.

## The one rule

**Take a library before writing one.** Below the interface, chord's own ACP
layer (`src/acp/` and `src/session/`) on `@agentclientprotocol/sdk` is the ACP
client; on screen, OpenTUI (`@opentui/core` and its React bindings,
`@opentui/react`) and its components are the widgets.
Before writing a component, a parser, a renderer or a protocol helper, look for
a maintained one that runs under Bun and survives `bun build --compile`, try
it, and say in the handover what you tried. Writing our own is the answer only when the
library is shown not to fit, and that finding goes into `docs/decisions.md`.

When a library does not do directly what the task asks, do not write a
workaround around it on your own call: no rewriting its input, no guessing at
ambiguous input, no patching its behaviour. Stop and hand the owner the
question with the options, including changing what the task asks so the
library fits as it is. A trial recorded in `docs/decisions.md` is not the
owner's consent.

## Commands

```sh
bun install                    # the dependencies, as bun.lock pins them
bun dev chord [agent]           # run from source
bun dev chord riff              # sign in to a ChatGPT or Grok plan
bun dev chord --fake            # run against the scripted test agent
bun dev chord --fake riff       # riff on its fake provider
bun dev chord acp [agent]       # serve ACP v1 on stdin and stdout, no window
bun dev quality chord          # types, lint, format and all tests
bun dev quality chord --static # types, coverage, lint, format and lint/ tests
bun check                      # Bun's native type checker
bun dev test [args…]            # tests, a worker per core; Bun's test arguments
bun dev test -t '…'             # matching tests
bun dev test --changed          # uncommitted changes
bun dev test --changed=<commit> # since a commit
bun test --isolate --timeout=60000 ./tests/x_test.ts -t '…' # Bun's own runner
bun dev lint chord --fix        # what ESLint can fix
bun fmt                        # lay out the tree with Bun's native formatter
```

Arguments after `bun dev chord`, `bun dev test` and `bun dev lint chord` pass on
as written. An empty argument needs `--` (`bun dev test -- -t ''`);
the tool's own help does too (`bun dev lint chord -- --help`).

`bun dev test` reports the tests' status. `tests/timings.json` only places
files: Bun uses it to balance shards and start each worker's slowest files
first; an unlisted file takes the median. No refresh is required.
CI runs `static` (`bun dev quality chord --static`), three `tests` shards
(`--shard=1/3`, `2/3`, `3/3`) and `compile`. The required `check` job
passes only when all of them succeed. The libfx layout check covers the host's
installed package and every target's metadata locally; CI's static job installs
all platforms and sets `CHORD_LIBFX_ALL_TARGETS=1` to check all four packages.

The binary is built by Bun's compile API, Bun 1.4.4 or newer. Compilation
installs all target packages, then checks the pinned libfx layout for each
target it builds; a mismatch names the package and version and stops the build.
Build, release and maintenance commands share `bun dev <command>` (Cliffy):

```sh
bun dev compile           # this machine's binary into dist/<target>/chord
bun dev compile --all     # every release target
bun dev compile --install # this machine's binary into ~/.local/bin/chord
bun dev npm               # lay out npm/ from dist/
bun dev release chord [--bump <version|major|minor|patch|fix>] # owner's release
bun dev selftest <binary> # fake-agent CLI/window, riff on native and Wasm
bun dev registry          # refetch the ACP Registry into src/registry.ts
bun dev mark              # rasterise scripts/mark.svg into the header mark
bun dev screenshots       # retake docs/images/, including title pages and logos
bun dev screenshots logo  # the transparent dark and light README logos only
bun dev social            # GitHub's social preview from docs/images into dist/
bun dev memory            # long-run memory check; options in docs/memory.md
```

`bun dev release --help` lists each package's stages and selection flags.
Only `quality`, `lint` and `release` take a package, by its npm name without
the scope; each runs that package's `steps.ts`. chord's is at the repository
root. It defines checks, lint arguments and release stages, with publish last.
A bare `bun dev release` releases nothing. Use
`--bump <version|major|minor|patch|fix>` instead of editing the version by hand.
Add `--channel <name>` for
`<base>-<channel>.<n>`: bumps count from npm's latest stable; if package.json
holds that base on that channel, its number goes up, otherwise it starts at 0.
Labelled version arguments are refused. Names start with a lowercase letter,
then use lowercase letters, digits or hyphens; `latest`, `main` and semver
ranges are refused. A stable bump from a pre-release needs an exact version.
A fresh release refuses a different version while package.json's is not on npm.
Without `--bump`, `--channel` requires package.json already on that channel.

chord's stages are `install`, `quality`, `natives`, `compile`, `sign`,
`selftest`, `notarise`, `pack`, `publish`. Selecting `publish` requires
installed, signed-in `gh`, checked by `gh auth status` among the guards.
Every named release then requires npm authentication, including dry runs and
runs without publish. A failed `npm whoami` requires stdin and stdout
terminals for one plain `npm login`, then a successful `npm whoami` recheck.
Missing terminals, failed or cancelled login, signals or a failed recheck
stop release work. npm may open a browser and save credentials or registry
settings even in a dry run. Stage selection cannot skip authentication.
A new version needs `compile`; publishing requires the channel's branch,
or `main` for a stable release, level with origin, and commits and pushes
package.json alone as `chore: chord v<version>` before any stage.
A dry run still submits to Apple; add `--skip notarise` to leave that out.
`pack` fetches FFmpeg and zlib source into `dist/release/source/` with `curl`
and checks sums against OpenTUI's native package `FFMPEG-SOURCE.md`, even in
dry runs. Publishing rechecks those archives and needs `pack` done in this
run or the recorded state. It publishes all five npm packages in order;
channel packages use `--tag <channel>`, leaving `latest` unchanged. A channel
dry run prints its stages and npm publish arguments. After pushing the tag,
publish creates a draft GitHub release with the archives attached, marked
`--prerelease` for a channel. The owner writes its notes and publishes it.

A publishing run, or a run at package.json's version without `--dry-run`,
records progress in gitignored `.release/<package>/state.json`. Rerun
`bun dev release <package>` to continue stages, npm publishing, the tag or
the draft. It keeps its version commit on failure or a signal; runs without
state drop theirs. Unfinished state refuses `--bump` and `--dry-run`.
Changed outputs are refused with the stage to rerun from (after signing,
`--from compile`). State is removed on completion; abandon it by hand with
`rm -r .release/<package>`. A checkout-wide release lock never goes stale;
a lock left by SIGKILL, a crash or reboot is refused with its pid and path,
to remove by hand. See `docs/guide.md` for continuation guards and cleanup.

## How code is written

- **Bun runs chord.** `bun dev quality chord` runs native `bun check`,
  tracked-file coverage, ESLint, `bun fmt --check --ignore-pattern=packages/ .`,
  `lint/` tests and `bun dev test`. Tests use `test`, `describe`, `expect`
  and the fake timers of `bun:test`. Code outside `src/platform/` calls `node:` built-ins; that
  folder holds Bun's runtime calls. The binary embeds OpenTUI's native
  library, libfx's target addon and WebAssembly core, and fff's target library
  with its Worker. Linux builds use glibc. Dependencies go in `package.json`;
  jsr packages come from `npm.jsr.io` under their own names
  (`bunfig.toml`, `.npmrc`). No `node_modules` checked in.
- **Versions are pinned for things that move.** A pre-1.0 package is
  exact-pinned (`@replit/codemirror-vim-core`); the rest use caret ranges, and
  `bun.lock` is committed.
- **The style is what the tools hold.** `tsconfig.json` holds the strict
  compiler flags, `eslint.config.ts` the lint rules, `lint/style.ts` what
  the formatter cannot express (blank lines, imports first), and
  `.prettierrc.json` the layout (80 columns, single quotes, JSX's too).
  `bun dev lint chord --fix` then `bun fmt` lays code out. A lint rule added
  to `eslint.config.ts` gets its snippet in `lint/config_test.ts`.
- **Logic lives where a test reaches it.** Reducers from runtime events to
  transcript state, key handling, history, completion, settings merge — pure
  modules with tests. Components only draw state and dispatch. `tests/`
  mirrors `src/`: a module's tests are at the mirrored path
  (`tests/settings_test.ts` for `src/settings.ts`).
  If a test's path differs from another only by case, add it to
  `tsconfig.json`'s `files`: `bun check` can skip it on a case-blind file
  system. `bun dev quality chord --static` runs `scripts/dev/covered.ts`,
  which names and fails any tracked TS/TSX file left unchecked, with no exemptions.
- **Tests never reach a real model, agent or resource provider.** Drive UI
  through `tests/ui/harness.tsx` and sessions with fake ACP stdio fixtures.
  Resource access is explicit: tests use fixture collectors; omitted access
  stays disabled. `--fake`/`--qa` never fall back to official readers. Live
  agents and providers are for authorized manual checks, outside
  `bun dev quality chord`.
- **Comments say why, not what.** A doc comment on a type says what it is for.
- **Every action has a key.** Nothing on screen needs a pointer. A new action
  names its key in the same change, and the shortcuts panel (`?` on an empty
  prompt) lists it: an entry in `src/ui/shortcuts/keys.ts`, and, if a person may
  rebind it, an action in `src/ui/shortcuts/bindings.ts` that `keyCommand` matches
  and the entry names. `tests/ui/shortcuts/keys_test.tsx` checks
  against it every key `keyCommand` answers and every key the prompt and the
  permission prompt widgets act on; a widget-owned key needs its test too.
- **Commit messages carry no trailers** — nothing after the body. Conventional
  prefixes (`feat:`, `fix:`, `docs:`, `chore:`) with a scope where it helps.

## Choosing checks for a change

Run checks that match the changed files and the behavior they can affect.
A full `bun dev quality chord` is not required before every commit.

- For prose-only documentation, repository metadata or agent instructions,
  review the diff and check formatting of the changed files. Check links or
  rendering when the change affects them. Do not run application tests,
  type checking or the full lint suite for these changes. Executable
  examples, configuration and scripts need checks for their behavior.
- For code changes, run the relevant tests and static checks for the affected
  code. For interface changes, also check the behavior and layout by hand
  where automated checks do not cover them.
- Use the full `bun dev quality chord`, locally or in pull request CI, for broad
  changes (shared runtime behavior, dependencies, build or test configuration)
  or concrete concerns left by targeted checks. Do not broaden or repeat
  checks without a reason tied to the change or a failure.

Report what was run, what passed or failed, and what was not checked. CI may
still run the full suite; that does not require repeating it locally for
an unrelated change.

## Checking the interface by hand

chord is a terminal program, so a check runs it in a real terminal of a known
size and reads the screen back as text. For captures, use
`bun dev chord --fake --qa <name>`: it recreates `/tmp/chord-qa.<name>` and
its sibling `/tmp/chord-qa.<name>.state` for chord's state, never a directory
from `mktemp -d`. A bare `--qa` uses `/tmp/chord-qa` and `/tmp/chord-qa.state`;
an empty name is treated as no `--qa`. Without `--qa`, `--fake` uses
`/tmp/chord-fake`, made if missing and kept across runs so sessions resume.
`--qa` takes precedence. These runs set only `XDG_STATE_HOME`: records,
riff's store, sidecars and provider record stay out of the person's state;
config, data and cache are unchanged. Plain `bun dev chord` keeps the
person's XDG state. For riff on its fake provider, use
`bun dev chord --fake --qa <name> riff`. Both flags select riff's fake
provider and come before `riff`. `CHORD_RIFF_QA_SIGN_IN` selects offline
sign-in outcomes documented in the guide; never use a live sign-in for QA.
Fake/QA riff reads no user `AGENTS.md` or home skills.

```sh
tmux new-session -d -s chord-qa -x 120 -y 40 'bun dev chord --fake --qa capture'
tmux send-keys -t chord-qa 'hello' Enter
tmux capture-pane -t chord-qa -p        # the screen as text; -e keeps colours
tmux kill-session -t chord-qa
```

Use a session name of your own and always kill it afterwards. Check at least
one narrow size (80×24) as well as a wide one. A check against a live agent
spends the owner's account: keep prompts tiny and say in the handover that you
did it.

## Folder rules

Folders with rules of their own have an `AGENTS.md`: `src/`,
`src/platform/`, `src/session/`, `src/ui/`, `tests/`,
`tests/fixtures/fake_agent/` and `scripts/`. Read the one for the folder you
change; `src/session/AGENTS.md` also covers `src/acp/`. Codex loads
`AGENTS.md` only from the root down to its working directory, not for a file
it edits deeper.
