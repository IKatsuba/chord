# CTUI-13: fake agent and the interim connection window

## Scope and decisions

Unit 5 connects the existing interim window only when `--agent-command`
is present. The command is passed to the CTUI-12 client, initialised, then
`session/new` opens in the process's current directory, with no MCP servers.
The dev runner supplies the original fake agent through that same option.
Without the option the window and its behaviour stay exactly as CTUI-11.
This is a port screen, not a new framework widget.

The owner's choice, relayed by the lead: `--agent-command <command>`
overrides the command; `[agent]` only names it. The developer runner is
`dart run example/chord/tool/dev.dart chord --fake`. It starts the port
with the name `fake` and an explicit command for the original's fixture.
The lead approved a minimal `Connected` receipt, with identity retained
in state but not drawn, and no new keys.

There is no transcript, prompt, permission UI, model display, retry,
authentication flow or session persistence here. CTUI-15/16 and the later
M1 screens own these. No prompt is sent to the agent. Unsupported permission
requests receive CTUI-12's cancelled outcome; no hidden interactive action
is introduced.

## Original and wording

Read against the original's `docs/guide.md` (startup options and developer
QA), `docs/design/CHD-241.md` (starting wording), and these source files:

| Part | Source in `../chord` | Use here |
| --- | --- | --- |
| Header | `src/ui/header/Header.tsx`, `header.ts` | Keep CTUI-11's compact header, `chord` bold and the rest dim |
| Starting | `src/ui/status/Status.tsx` | `Starting <agent>…`, dim; agent is the CLI name, `fake` in the runner |
| Start failed | `src/ui/app/App.tsx` | `<agent> did not start: <reason>` |
| Stderr details | `src/session/start_failure.ts` | `The end of its stderr:`, then `… +N lines` if cut, then indented tail lines |
| Gone | `src/acp/connection.ts` and CTUI-12 `AgentGone` | `The agent exited.` or `The agent exited: <stderr>` |
| Connected | No standalone receipt in the original | `Connected`, a minimal interim receipt approved by the lead |

Original connected captures: [120x40](evidence/CTUI-13/original-connected-120.txt)
and [80x24](evidence/CTUI-13/original-connected-80.txt), with matching `.ansi`
files. These are actual fake-agent runs, not acceptance evidence for the port.
The original shows its mark, model, directory, prompt and status line. The
port deliberately keeps the approved CTUI-11 interim shell, adds the
connection receipt, and draws none of that M1 interface. Its version is
0.0.1 rather than the original's version. Session ids and initialize's
agent name/version are not shown by the original's header either.

CTUI-12 does not expose the original's full structured `StartFailure`
classification. This interim screen uses the thrown reason as supplied;
it does not invent exit codes, retry advice or step-specific explanations.
If an `AgentGone` provides a structured tail, show that under the headline.
Avoid repeating the same stderr in both the headline and detail block:
use `The agent exited.` as the reason when the tail is shown separately.
Other failures use their message. Do not draw stack traces or the command,
except the original's own command-parse refusal (`src/acp/process.ts`),
which is kept word for word, including the command:

```text
fake did not start: The agent command "<command>" holds shell syntax; give a plain command line.
```

## Plain Dart state and events

The reducer and state belong under the port's `lib/ui/`, without widgets,
process handles or async effects. This is the shape, not implementation:

```dart
enum StartPhase { idle, starting, connected, failed, gone }

final class StartState {
  final StartPhase phase;
  final String? sessionId;
  final String? agentName;
  final String? agentVersion;
  final String? reason;
  final List<String> stderrLines;
  final int stderrCut;
}
```

`idle` means no override: no client starts and no status row is drawn.
`starting` covers spawning, initialize and session/new. `connected` is
reached only after session/new succeeds; its session id is required, and
its optional name/version come from `initialize.agentInfo` without
substituting the selected CLI name. Empty/missing identity fields stay
absent. `failed` means opening failed before a session became connected.
`gone` means the connected agent's exit was observed; retain its identity
and session id. An exit code alone never becomes a guessed error reason.

Events are `startRequested`, `sessionOpened(sessionId, agentName?,
agentVersion?)`, `startFailed(reason, stderrLines, stderrCut)` and
`agentExited(reason, stderrLines, stderrCut)`. Only `idle → starting`,
`starting → connected|failed`, and `connected → gone` change phase.
Late or duplicate results do not revive a failed/gone window. There is
one opening attempt per window. All collections are immutable snapshots.
The client supplies bounded stderr (CTUI-12's last six non-empty lines,
1024 characters per line, and count cut); the reducer parses no protocol.

The effect owner starts the client once outside `build`, awaits session/new,
observes exit, and sends events. Quitting cancels an opening and closes any
client already obtained through CTUI-12's close barrier and stop ladder.
`runApp` awaits `beforeExit` after restoring the terminal and before process
exit; the window closes its agent there, so the screen disappears immediately
and CTUI-12's stop ladder completes after it is gone.
A late open completing after disposal is closed, not drawn. Local shutdown
does not flash a failure or `gone` frame. A failed session/new also closes
the initialized client. No process survives the window's teardown.

## Drawing and keys

Keep the existing one-cell left and right padding, top alignment and
header ellipsis. With an override, row 2 is the status, row 3 the existing
`ctrl+c or ctrl+d to quit` hint. Failure details follow the hint, so the
quit keys never move or disappear behind diagnostics. With no override,
the hint remains row 2 and every later row stays blank.

Starting and connected use dim text. Failed and gone use the theme's
error style for the status headline, with no reliance on colour for their
meaning. Details use plain text, their heading dim. Each row is one
physical line, ellipsized to available cells, never wrapped. Show the
stderr heading only for a non-empty tail. Tail lines have two additional
leading spaces; the cut marker precedes them. The rest of the screen is
blank. At tiny heights clip details first; bindings still work even when
no text fits. Long reason/identity/directory values cannot push the quit
hint down. Escape sequences in agent text must not execute as terminal
controls; display it as text, not raw terminal output.

There is no focused input, highlight or empty content placeholder. Focus
stays on the same Actions scope. The existing `ctrl+c` and `ctrl+d`, each
with description `quit`, quit at once in every state. Other keys do
nothing. The key hint lists all this window's actions; a shortcuts panel
and the original's double-ctrl+c behaviour remain the later quit task.

## Text mocks, beside the original

The linked original captures are full-sized. The following mocks show
occupied rows; every omitted row is blank up to the specified height.
They apply at both 120x40 and 80x24, with the same content and left inset.
Use the real current directory at runtime; `/workspace/demo` below is
neutral mock text.

| Original, connected (both sizes) | Port, connected (both sizes) |
| --- | --- |
| Mark and `chord v<version>` | ` chord v0.0.1 · fake · /workspace/demo` |
| `fake · Fake Large with a 1M context window` | ` Connected` |
| QA directory and shortcuts hint | ` ctrl+c or ctrl+d to quit` |
| Empty transcript, prompt frame, model and effort at bottom | Blank through row 40 or 24 |

Starting, 120x40 and 80x24:

```text
 chord v0.0.1 · fake · /workspace/demo
 Starting fake…
 ctrl+c or ctrl+d to quit
```

Connected, 120x40 and 80x24:

```text
 chord v0.0.1 · fake · /workspace/demo
 Connected
 ctrl+c or ctrl+d to quit
```

Failed, 120x40 and 80x24:

```text
 chord v0.0.1 · fake · /workspace/demo
 fake did not start: The agent exited.
 ctrl+c or ctrl+d to quit
 The end of its stderr:
   Traceback (most recent call last):
   RuntimeError: scripted start failure
```

Gone, 120x40 and 80x24:

```text
 chord v0.0.1 · fake · /workspace/demo
 The agent exited.
 ctrl+c or ctrl+d to quit
```

For gone with stderr, use the same separate tail block as failed. With no
tail, failed still shows its supplied reason and has no details heading.
At 80 columns a long header/status ends with `…` on its own row; at 120
more of that same row is visible. A tail of six long lines occupies at
most eight rows including heading and cut marker, so it fits at both
required sizes. No diagnostic row steals the hint's row.

## Measured original comparison

The unit 5 visual check is recorded in
[evidence/CTUI-13/unit5-visual.md](evidence/CTUI-13/unit5-visual.md).
The original's held startup shows its centred splash and elapsed time;
this interim intentionally keeps only the Starting wording. Killing the
connected idle original fake produced no new visible exit notice in that
run; the interim explicitly draws the Gone receipt requested for this
unit. The receipt uses the ACP error's wording, not an observed identical
idle exit screen in the original.

## Handover and visual acceptance

Developer's unit handover names its commit, files and runner/scenarios.
Only then inspect the running port in designer-owned tmux sessions at
120x40 and 80x24. Save text and ANSI captures alongside the original
captures under `docs/design/evidence/CTUI-13/`. Check connected and a
startup failure, the visible starting state with the original's gated
command, and exit after connection using a bounded scripted child if the
fake cannot exit without a prompt. Do not add a scenario to the original.
Compare the whole screen to the original: every difference must be one
of the interim omissions above. Inspect narrow overflow and both quit keys;
close only owned sessions and children. Findings go to developer; a visual
pass goes to reviewer with the implementation commit and capture paths.
These mocks do not constitute that later visual pass.
