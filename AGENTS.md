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
fails `bun dev check` on any file git tracks that names a home directory,
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
bun dev chord --fake            # run against the scripted test agent
bun dev check                   # types, lint, fmt and all tests
bun dev check --static          # tsc, ESLint, Prettier and lint/'s own test
bun dev test [args…]            # tests, a worker per core; Bun's test arguments
bun dev test -t '…'             # matching tests
bun dev test --changed          # uncommitted changes
bun dev test --changed=<commit> # since a commit
bun test --isolate --timeout=60000 ./tests/x_test.ts -t '…' # Bun's own runner
bun dev lint --fix              # what ESLint can fix
bun dev fmt                    # lay out the tree with Prettier
```

Arguments after `chord`, `test` and `lint` pass on as written. An empty
argument needs `--` (`bun dev test -- -t ''`); the tool's own help does too
(`bun dev chord -- --help`).

`bun dev test` reports the tests' status. `tests/timings.json` only places
files: Bun uses it to balance shards and start each worker's slowest files
first; an unlisted file takes the median. No refresh is required.
CI runs `static`, three `tests` shards (`--shard=1/3`, `2/3`, `3/3`) and
`compile`. The required `check` job passes only when all of them succeed.

The binary is built by Bun's compile API, Bun 1.4.2 or newer. Build,
release and maintenance commands share `bun dev <command>` (Cliffy):

```sh
bun dev compile           # this machine's binary into dist/<target>/chord
bun dev compile --all     # every release target
bun dev compile --install # this machine's binary into ~/.local/bin/chord
bun dev npm               # lay out npm/ from dist/
bun dev release [version|major|minor|patch|fix] # the owner's release
bun dev selftest <binary> # check a binary on the fake agent, including tmux
bun dev registry          # refetch the ACP Registry into src/registry.ts
bun dev mark              # rasterise scripts/mark.svg into the header mark
bun dev screenshots       # retake docs/images/ from chord on the fake agent
bun dev memory            # long-run memory check; options in docs/memory.md
```

`bun dev release --help` lists its stages and selection flags. Give it the
version or bump instead of editing package.json's version by hand. A new
version needs `compile`; a publishing run commits and pushes it to main
before any stage. A dry run or run without publish drops its local commit
at the end. A dry run still submits to Apple; add `--skip notarise` to
leave that stage out. See `docs/guide.md` for failure and signal cleanup.

## How code is written

- **Bun runs chord.** `bun dev check` runs `tsc`, ESLint, Prettier and
  `bun dev test`. Tests use `test`, `describe`, `expect` and the fake timers of
  `bun:test`. Code outside `src/platform/` calls `node:` built-ins; that
  folder holds Bun's runtime calls. The binary embeds OpenTUI's native
  library for its target through Bun's compile API. Dependencies go in
  `package.json`; jsr packages come from `npm.jsr.io` under their own names
  (`bunfig.toml`, `.npmrc`). No `node_modules` checked in.
- **Versions are pinned for things that move.** A pre-1.0 package is
  exact-pinned (`@replit/codemirror-vim-core`); the rest use caret ranges, and
  `bun.lock` is committed.
- **The style is what the tools hold.** `tsconfig.json` holds the strict
  compiler flags, `eslint.config.ts` the lint rules, `lint/style.ts` what
  Prettier cannot express (blank lines, imports first), and
  `.prettierrc.json` the layout (80 columns, single quotes, JSX's too).
  `bun dev lint --fix` then `bun dev fmt` lays code out. A lint rule added
  to `eslint.config.ts` gets its snippet in `lint/config_test.ts`.
- **Logic lives where a test reaches it.** Reducers from runtime events to
  transcript state, key handling, history, completion, settings merge — pure
  modules with tests. Components only draw state and dispatch. `tests/`
  mirrors `src/`: a module's tests are at the mirrored path
  (`tests/settings_test.ts` for `src/settings.ts`).
  If a test's path differs from another only by case, add it to
  `tsconfig.json`'s `files`: tsc can skip it on a case-blind file system.
  `bun dev check --static` runs `scripts/dev/covered.ts`, which fails and
  names any tracked TS/TSX file left unchecked, with no exemptions.
- **Tests never reach a real model or a real agent.** Drive the UI through
  `tests/ui/harness.tsx`, on OpenTUI's test renderer; drive the session layer
  with a fake ACP agent in `tests/fixtures/` speaking the protocol over stdio. A live agent is for a
  person checking by hand, not for `bun dev check`.
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
A full `bun dev check` is not required before every commit.

- For prose-only documentation, repository metadata or agent instructions,
  review the diff and check formatting of the changed files. Check links or
  rendering when the change affects them. Do not run application tests,
  type checking or the full lint suite for these changes. Executable
  examples, configuration and scripts need checks for their behavior.
- For code changes, run the relevant tests and static checks for the affected
  code. For interface changes, also check the behavior and layout by hand
  where automated checks do not cover them.
- Use the full `bun dev check` for changes with broad impact, such as shared
  runtime behavior, dependencies or build and test configuration, or when
  targeted checks leave a concrete concern unresolved. Do not broaden or
  repeat checks without a reason tied to the change or a failure.

Report what was run, what passed or failed, and what was not checked. CI may
still run the full suite; that does not require repeating it locally for
an unrelated change.

## Checking the interface by hand

chord is a terminal program, so a check runs it in a real terminal of a known
size and reads the screen back as text. For captures, use
`bun dev chord --qa <name>`: it recreates the fixed `/tmp/chord-qa.<name>`,
never a directory from `mktemp -d`. A bare `--qa` uses `/tmp/chord-qa`;
an empty name is treated as no `--qa`.

```sh
tmux new-session -d -s chord-qa -x 120 -y 40 'bun dev chord --qa capture'
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
