# CHD-31 QA — 2026-10-07

Tested main at `d14c2ed`, after the reviewer's approval of return 2. The
designer-approved appearance and the owner's one-report/one-line wheel feel
were treated as settled. This commit adds evidence only.

## What ran

- `deno task check`: 1058 tests (20 steps), 0 failed, 5m22s. Process-table
  access was granted for fixture discovery and cleanup.
- `deno task compile`: passed; the macOS arm64 binary started against the
  fake agent and completed the narrow-terminal checks below.
- Source chord in an owned tmux server at 120×40, resized to 80×24; the
  compiled binary at 80×24 and 120×40. Working directory, configuration,
  state, and the fake-agent launcher were isolated under `/tmp/chd31-qa`.
  Input used tmux keys and literal SGR reports; no live agent was run.
- Fake-agent scenarios: `long`, `permission`, `form`, `error`, `slow`, and
  `hello`. Full check also exercises the fake-agent session layer and the
  pure mouse parser/mapping and actual Ink input path.
- Delayed bracketed-paste start/end markers and a mouse report split across
  reads, with 150 ms between writes; editor handoff through vi; keyboard
  interruption; Ctrl+C twice, Ctrl+D, SIGTERM, and SIGHUP.
- An isolated Deno/Ink component-error harness using production
  `withMouseModes`, to exercise Ink's crash cleanup independently.
- User-only `"mouse": false`, the same key in a project file, and compiled
  `-p text` with the fake agent.
- Native capability probes for Terminal.app and iTerm2.

## What was observed

Twelve wheel-up reports matched twelve Shift+Up presses byte for byte in
source at both sizes and in the compiled binary at 80×24. At 120×40 the
screen shows lines 155–187; at 80×24 it shows 171–187. Both say 13 lines
below and keep `a draft I am still typing` unchanged. Twelve down reports
from that position restore the bottom, line 200, and remove the indicator.
Up still recalls `long` at 120×40 and `hello` at 80×24.

The shortcuts panel names `pgup pgdn or wheel to scroll` at both sizes,
without adding a row at 80×24. A drag shows `shift + drag to select text`
alone below the prompt in tmux, then restores the model/status line after
three seconds. The passing unit tests cover iTerm2's option hint (including
LC_TERMINAL), Terminal.app's fn hint, and rebound/unbound page-key wording.
They do not prove native selection.

Clicks, right/middle buttons, motion, horizontal wheel, modified wheel, and
a valid delayed split report leave the draft intact. The modified and split
vertical reports scroll one line each. Permission scrolling keeps Allow
highlighted; mouse reports do not fill the form. Delayed paste framing
preserves pasted text and the following real wheel scrolls. Report-like
bytes inside a paste remain pasted content, rather than becoming wheel
actions. The external editor showed those preserved bytes as literal text.

While streaming, transcript rows stayed byte-identical between
`120-stream-anchor.txt` and `120-stream-later.txt`; the new-output indicator
grew from 10 to 29 lines below. Esc interrupted the turn. The intentional
fake-agent failure is visible as `The fake agent failed on purpose.`

Flags are recorded in this order: alternate screen, standard mouse, SGR
mouse, all-event mouse, cursor visible. `mouse_all_flag` tests 1003;
`mouse_any_flag` means any tracking mode and is not the right flag here.

| State | Flags |
| --- | --- |
| Source/binary running, both sizes | `1 1 1 0 0` |
| vi open, both sizes | `1 0 0 0 1` |
| Return from vi | `1 1 1 0 0` |
| Ctrl+C twice, Ctrl+D, SIGTERM, SIGHUP | `0 0 0 0 1` |
| Ink component-error harness after failure | `0 0 0 0 1` |
| User's `"mouse": false` | `1 0 0 0 0` |
| Project's `"mouse": false`, ignored | `1 1 1 0 0` |

vi owns the alternate screen while it is open. After exits the shell is
readable, the cursor is visible, and `stty -g` is byte-identical to the
pre-run value, after both normal quit and SIGHUP. SIGTERM stopped binary
PID 77525 and its fake agent 77564; SIGHUP stopped source PID 80500 and its
fake agent 80525. Final process inspection found no QA-owned agent, check,
or tmux server; an explicit server query returned no server running.
Prior orphan PID 78189 (`--hang config`) is already tracked by CHD-158 and
was left untouched.

The project mouse key is reported and ignored, as the capture shows. The
headless reply contains no mouse-mode escape. README wording matches the
design. The implementation reuses existing `@ansi-tools/parser`; the
documented library trials were `xterm-mouse` / `@ink-tools/ink-mouse`
(independent stdin listeners, forced modes, split loss, duplicate
coalescing), `@sorrell/ink-mouse` (file dependency), and
`@zenobius/ink-mouse` (Ink 5). No application code or dependency changed
during QA.

One injection trap was resolved before judging the result: tmux drops a
trailing semicolon from a `send-keys` argument. A Deno-native raw-input
probe showed that an intended split after `ESC[<64;10;` actually delivered
`ESC[<64;10`, making the report malformed. Splitting after
`ESC[<64;10;1`, then sending `0M`, gives the valid report and passes. The
malformed probe was not attributed to chord.

## Native checks still need the owner

The computer-use tool refuses Terminal.app for safety reasons and reports
iTerm2 unavailable. Native wheel/selection bypass and native editor or
exit lifecycle were therefore not exercised here. The owner's reported
successful trackpad scrolling is on the board; it is not independent QA
evidence for both terminals. The owner still needs to check option-drag in
iTerm2 and settle fn versus option in Terminal.app, including selection
and copying with capture active. CHD-36 stays separate; chord's own
selection remains CHD-177.

No new product finding or separate task was filed. Automated and tmux QA
passed; the native limitation is explicit in the handover to chd-lead.
