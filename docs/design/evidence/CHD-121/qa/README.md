# CHD-121 independent QA

Tested implementation e63a7b6 on main a734253. Appearance was already
approved by the designer, including the five accepted mock differences.
CHD-212 remains the separate optional glyph-colour task.

## What ran

- `deno task check` on the current tree, with process access for fake-agent
  cleanup. Result is recorded in the QA handover on the task.
- `deno task compile`, then the resulting host binary in tmux at 80x24.
- Source TUI in an isolated tmux server at 120x40, resized with its sessions
  picker open to 80x24. All interaction used keys.
- Temporary HOME, separate source/compiled state directories and a scratch
  directory displayed as `~/src/app`. Agents were exclusively the repository's
  fake ACP fixture, with `--step-ms 100`. No real agent or model was used.
- `ps` before/after open-session resume and after each quit; terminal settings
  before and after; tmux alternate-screen/cursor flags; recorded terminal
  alternate-screen entry/exit bytes; isolated tmux server cleanup.

## What was observed

At 120x40, three sessions were open. The picker highlighted the waiting
permission tab, Enter selected it, and a digit selected another tab without
answering that permission. Esc restored the permission. `/resume` showed
`open in 1` and `open in 3`; selecting tab 1 preserved its transcript and the
same three fake-agent PIDs. `/model` changed tab 2 alone. `/clear` in tab 2
removed its transcript while tab 1 retained its prompt and reply.

A form with a draft email value and its validation error survived picker
open/Esc, and resizing the open picker to 80x24. The form draft and validation
error returned unchanged. The resize probe initially expected an input state
on the front row; correcting that probe to the documented `here` state passed.
There was no product defect.

At 80x24, the compiled binary independently passed picker Enter/digit
selection, `/resume` displaying and selecting `open in 1` with the same two
agent PIDs, `/model` isolation and `/clear` isolation. Its picker over a
permission switched to tab 2 while tab 1's permission remained pending;
returning and picker Esc restored the request.

Both source (after resizing) and binary showed `The fake agent failed on
purpose.`, interrupted a slow turn with Esc, and accepted another prompt
successfully. Both quits returned to the shell with identical terminal
settings, cursor visible, alternate screen off and no owned agent remaining.
The isolated tmux server was removed. `cleanup.txt` records runtime counts
and terminal checks. Plain captures and selected colour captures accompany
this report; all were checked for private paths before staging.

Library first: QA added only evidence. No component, renderer, parser,
protocol helper or dependency was written or needed. The implementation
reuses `PickerList`/`picker.ts`, `formatElapsed` and existing strip glyphs.
The earlier ink-select-input and @inkjs/ui trials are documented in
`docs/decisions.md`; no additional library trial was needed in this pass.

Judged: CHD-121 behavior, request/key ownership, fake-agent integration,
source resize, compiled narrow startup, interrupt/error handling and cleanup.
Not rejudged: approved appearance, `/new` and per-agent starting values
(CHD-122), or real-agent compatibility.

No blocking findings and no new follow-up tasks.
