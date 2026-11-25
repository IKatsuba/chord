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

You need Dart 3.12 or newer. The scripted fake agent runs with Dart.

```sh
git clone https://github.com/IKatsuba/chord && cd chord
dart pub get
(cd packages/chord_tui && dart pub get)
dart run tool/dev.dart chord --fake # scripted test agent
dart run tool/dev.dart chord        # your real default agent
```

The Dart test agent under `test/fixtures/fake_agent/` plays a scenario
for a prompt that names one: type `edit`, `permission`, `plan`, `subagent`
or `team` to see each part of the interface work. Its scenario names are
listed in `test/fixtures/fake_agent/main.dart`.

## Before you open a pull request

```sh
dart analyze
(cd packages/chord_tui && dart analyze)
dart format --output=none --set-exit-if-changed .
dart test
(cd packages/chord_tui && dart test)
```

Run static checks and relevant tests, following [AGENTS.md](AGENTS.md#tests).
For prose-only changes, review the diff and check formatting of the changed
files; application tests are not needed. For code, run relevant tests and
static checks, with the full suite locally for broad changes. State which
checks you ran in the pull request. `dart format .` fixes formatting;
`dart analyze` runs types and lints.

[CI](.github/workflows/ci.yml) runs on `ubuntu-latest`: both packages are
analyzed, formatting and actionlint are checked, each suite runs in three
shards, and both `compile` tags run with `expect`. It also tests the npm shim
with Node 22.13, builds linux-x64 natively and cross-compiles linux-arm64.
The aggregate `check` requires all jobs to pass. Darwin builds run in the
maintainer's local release.

- Keep a pull request to one change. For behavior changes, add a test that
  would have failed without it when appropriate. Tests never reach a real
  model or a real agent: the interface is
  driven through `package:chord_tui/testing.dart`, the session layer through
  the fake agent.
- A new action gets a key, and the shortcuts panel lists it
  (`lib/ui/shortcuts/bindings.dart`).
- Take a maintained library for non-terminal code before writing your own,
  and say in the pull request what you tried.
- Commit messages use conventional prefixes (`feat:`, `fix:`, `docs:`,
  `chore:`) and carry no trailers.
- Everything in the repository is in English and names no private path.

`AGENTS.md` is how the code is written, for people and coding agents alike,
and `docs/decisions.md` is why the stack is what it is. Read them before a
larger change, or open an issue first to talk it through.

## Screenshots

Check screen changes at 120x40 and 80x24, following [AGENTS.md](AGENTS.md#tests).
Use `dart run tool/dev.dart chord --fake` for captures without
a real agent. Retake what a change moves and commit the captures with it.

## Code of conduct

Everyone taking part is expected to follow the
[code of conduct](CODE_OF_CONDUCT.md).
