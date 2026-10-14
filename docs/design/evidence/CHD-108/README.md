# CHD-108 QA evidence

Verified implementation `5e7b5ae` on `main`. These are tmux terminal text
captures of the compiled macOS arm64 binary produced by `deno task compile`.
No real agent or model was used. The invisible headless change was judged by
its behavior, not appearance.

## Isolation and reproduction

The binary was copied to `/tmp/chd108-qa/chord`. The repository's `deno.json`,
`deno.lock`, `tests/fixtures/*.ts`, and `src/session/context.ts` were copied
into matching paths under `/tmp/chd108-qa`. Deno and the binary were on PATH.
The shell used `/tmp/chd108-qa/work` as its working directory,
`XDG_CONFIG_HOME=/tmp/chd108-qa/config`,
`XDG_STATE_HOME=/tmp/chd108-qa/state`, and `NO_COLOR=1`.

```sh
export FAKE='deno run --quiet --allow-env --config /tmp/chd108-qa/deno.json /tmp/chd108-qa/tests/fixtures/fake_agent.ts'
```

Each command was typed with tmux literal keys, followed by Enter separately.
The headless acceptance captures label stdout, stderr and the saved result of
`echo $?`, taken immediately after chord. The working directory had no project
settings except for the two `03` captures, which used:

```json
{ "agents": { "fake": { "permissionMode": "plan" } } }
```

The `05` capture uses `CHORD_FAKE_NO_MODES=1`. The fake fixture's permission
request offers `allow` (`allow_once`), `always` (`allow_always`) and `deny`
(`reject_once`); its reply reports the actual selected option ID.

## Runs and observations

| Captures | What was run | What was observed |
| --- | --- | --- |
| 01 | Default `-p permission` | Refusal on stderr, `Permission: deny.` on stdout, exit 0. |
| 02 | `-p mode --permission-mode plan` | `Mode: plan.` from inside the prompt's turn, empty stderr, exit 0. |
| 03 | Project mode only, then a flag over it | In-turn `plan`, then `acceptEdits`, empty stderr, exit 0. |
| 04 | Unknown mode with a permission prompt | Exact offered-modes warning, permission refused, turn still ran, exit 0. |
| 05 | No advertised modes | Exact no-modes warning, permission refused, turn still ran, exit 0. |
| 06 | Skip-permissions, text and JSON | Allowed-title stderr line, option ID `allow`, exit 0; JSON stdout contains exactly one object. |
| 07 | Skip-permissions without `-p` | Exact validation error, exit 2, CLI help on stdout, no window. |
| 08 | Both flags, mode and permission prompts | In-turn `acceptEdits`; remaining permission selected `allow`, exit 0. |
| 09 | Unknown mode then agent error | Warning followed by the agent's error on stderr, partial reply on stdout, exit 1. |
| 10 | Headless stream at 120x40, resize to 80x24, Ctrl+C | Stream continued after resize; interrupt returned exit 130 and the shell. |
| 11 | Window startup in plan, mode/error prompts, resize, Escape, Ctrl+D | Shared starting-mode path worked; error shown; turn interrupted; quit restored the shell. No appearance judgment. |
| 12 | Permission fallback and listed setter refusal | `allow_always` selected when no `allow_once` exists; a request without allow options was refused; a listed mode refused by the setter preserved the agent's reason and ran the prompt read-only. |

The `12` probes use temporary fixture variants outside the repository:
`always.ts` removes the `allow_once` entry from the permission scenario;
`noallow.ts` also removes `allow_always`; `refusemode.ts` changes the
`locked.has(params.sessionId)` setter-refusal condition to `true`.
Everything else is the same SDK fake agent. No protocol helper was written.

## Terminal and process verification

`stty -g` before the runs matched after normal headless completion, Ctrl+C,
and window quit. tmux reported `alternate=0 cursor=1` after both interrupts
and quit. `/bin/ps -axo pid,ppid,command` found no process running the QA
scratch binary or fake fixtures after the terminal runs. The isolated tmux
server was removed after verification.

The implementation uses existing acpx/runtime `ensureSession`, `getStatus`,
`setMode`, permission callbacks and `approve-all`/`deny-all`, with ACP SDK
`PermissionOption.kind`. QA added no dependency or production code.

## Automated validation

- `deno task check`: types, lint and formatting passed; 723 tests passed
  (20 steps), zero failed, in 6m38s. Ran with process access because the
  sandbox denies `/bin/ps`, which fake-agent cleanup requires.
- `deno task compile`: passed for `aarch64-apple-darwin`; the resulting binary
  ran every terminal capture above.
- `deno test --allow-read --allow-write --allow-run --allow-env tests/privacy_test.ts`:
  seven passed, zero failed, with the evidence staged in the Git index.
- `git diff --cached --check`: passed.
- CHD-108 evidence scan: no private home path or username. A whole-doc scan
  also found unrelated untracked CHD-32 captures already covered by CHD-52;
  those were left untouched. No new finding task was needed.
