# Contributing to chord

Thanks for wanting to help. Bug reports, ideas and pull requests are all
welcome.

## Reporting a bug or asking for a feature

Open an [issue](https://github.com/IKatsuba/chord/issues/new/choose). For a
bug, say which agent you ran (`chord agents` names them), chord's version
(`chord --version`), your OS and terminal, and what you pressed. A copy of the
screen as text helps most: a terminal's own copy, or
`tmux capture-pane -p` if you run chord in tmux.

A security problem goes to [SECURITY.md](SECURITY.md) instead, not to an
issue.

## Running chord from source

You need [Bun](https://bun.sh) 1.4.2 or newer.

```sh
git clone https://github.com/IKatsuba/chord && cd chord
bun install
bun run chord:fake    # chord against the scripted test agent, no account needed
bun run chord         # chord against your real default agent
```

The test agent in `tests/fixtures/fake_agent/` plays a scenario for a prompt
that names one: type `edit`, `permission`, `plan`, `subagent` or `team` to see
each part of the interface work.
`tests/fixtures/fake_agent/AGENTS.md` lists them all.

## Before you open a pull request

```sh
bun run check         # types, lint, formatting and every test
```

This is the full check, and CI runs it. Locally, choose checks that match
what changed, following [AGENTS.md](AGENTS.md#choosing-checks-for-a-change).
For prose-only changes, review the diff and check formatting of the changed
files; application tests are not needed. For code, run relevant tests and
static checks, using the full suite when the impact is broad. State which
checks you ran in the pull request. `bun run lint --fix` then `bun run fmt`
fixes most lint and formatting issues.

- Keep a pull request to one change. For behavior changes, add a test that
  would have failed without it when appropriate. Tests never reach a real
  model or a real agent: the interface is
  driven through `tests/ui/harness.tsx`, the session layer through the fake
  agent.
- A new action gets a key, and the shortcuts panel lists it
  (`src/ui/shortcuts/keys.ts`).
- Take a maintained library before writing your own parser, renderer or
  widget, and say in the pull request what you tried.
- Commit messages use conventional prefixes (`feat:`, `fix:`, `docs:`,
  `chore:`) and carry no trailers.
- Everything in the repository is in English and names no private path.

`AGENTS.md` is how the code is written, for people and coding agents alike,
and `docs/decisions.md` is why the stack is what it is. Read them before a
larger change, or open an issue first to talk it through.

## Screenshots

The README's screenshots are taken from chord itself, on the test agent, by
`bun dev screenshots` (tmux and Chrome). Retake what a change moves and
commit the images with it.

## Code of conduct

Everyone taking part is expected to follow the
[code of conduct](CODE_OF_CONDUCT.md).
