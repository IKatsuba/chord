# CHD-493 — brief

The lead's brief for the architects. The task is on the board (`board show
CHD-493`), milestone 0.58.0. Drafts go in this folder only, one file per
architect; the design goes to `docs/design/CHD-493.md` and decisions to
`docs/decisions.md`, both the lead's. Read from the code as it is on
origin/main (v0.57.0, `3f6f6656`), in this worktree.

## The problem

The owner's call, 2026-10-21: chord drops tabs. A chord process runs one
main session, with its children (long-lived agents, team members, task
agents, subagents, monitors) as today. Several sessions side by side are
the terminal's job (panes, Chorded), not chord's.

Tabs reach far: `src/session/tabs.ts` (1059 lines) holds the open
sessions, their children, the front, waits and attention order; it is
imported by `open_sessions.ts`, `sessions.ts`, `window_monitors.ts`,
`windows.ts`, `src/status.ts`, `ui/agents/agents.ts`, `ui/app/App.tsx`,
`ui/app/sessions.ts`, `ui/app/strip.ts`, `ui/pickers/picker.ts`,
`ui/status/status.ts` and `ui/transcript/spend.ts`, and their tests.
Several features grew a tab dimension on top of the per-session one, and
the person's names for things ("tab 2", `claude (2)`) are tab names.

## What goes (the owner's list, to confirm in detail from the code)

- the tab strip in the header (`ui/app/Strip.tsx`, `strip.ts`);
- the `ctrl+x` tab keys: `session:new` (`c`), `next`/`previous` (`n`/`p`,
  `ctrl+n`/`ctrl+p`), `goto1`–`9`, `list` (`w`), `close` (`k`), and what
  of `session:attention` (`a`) is about tabs;
- `/new` as "open a tab" (and `/new <agent>`);
- window records (`windows/w-<id>.json`, `src/session/windows.ts`), the
  window row in `/resume`, `Resume this window with:`;
- `--resume` taking several ids (`-r a -r b`);
- the per-tab state in `src/session/tabs.ts` and the UI's per-tab slices
  (draft, scroll, queue, place/directory per tab, bash command per tab…).

## What a person sees and presses afterwards

One session on screen, as chord with one tab looks today, with its agents
list, background view, permissions and forms. No strip. What replaces each
tab action, if anything, is the question: e.g. `/new` could become "end
this session and start a new one" (as `/clear` already is?), `/resume`'s
pick replaces the main session rather than opening beside, `ctrl+x a`
may still go to a child that waits. Quitting prints one resume command.

## Settle (each item names its owner; every architect may comment on any)

1. **What goes, exactly** — every file, action, setting, flag, message,
   record and doc that exists only for tabs. (runtime: session layer and
   CLI; interface: UI, keys, panel, settings; protocol: records, MCP, OSC)
2. **What each feature that names a tab becomes**:
   - the agents list and picking a child (interface);
   - the background view (CHD-487) (interface);
   - notifications (OSC 9/777/BEL, `tabName`, "behind" notices, waits
     folded per tab) (interface + runtime);
   - OSC 7501's root record folding every tab (CHD-382, Q68), its `title`
     from the front tab (CHD-491, Q111/Q119), and `chord_session`'s "front
     tab's id" (CHD-492) (protocol);
   - `/resume` (picker, "open in 2", opens beside, windows merged in the
     list, the start picker, `--continue`) (interface + runtime);
   - `/status`'s `Sessions:` line, `/new`'s per-agent startup
     (`startupOf`), the tenth-session refusal, the busy-close arming of
     `ctrl+x k`, ctrl+d/`/exit` arming with several open (interface +
     runtime);
   - the shortcuts panel and the leader line (`ctrl + x then a key for
     sessions`), keybinding files naming removed actions (interface);
   - settings that exist only for tabs, and settings "of the first tab's
     directory" (interface + runtime);
   - docs: README, `docs/guide.md`, `docs/FEATURES.md`, screenshots
     (`docs/images/tabs.png`), `docs/agent-capabilities.md` (interface).
3. **Old window records and old `--resume w-…` calls** — what chord does
   with `windows/` files on disk and with `chord --resume w-…`, `-r a -r
   b`, and a keybindings file binding a removed `session:` action
   (protocol for records; runtime for the CLI; interface for keybindings).
4. **CHD-445** (an agent's session title names the session in its tab, the
   agents list and /resume; owner decided 2026-10-18). CHD-491 already
   keeps/sends the agent's title (else the first prompt) in OSC 7501's
   `title`. Say what is left once tabs go, whether chord keeps the title in
   the session record, and whether CHD-445 should be rewritten or closed
   (protocol, with interface for where it would show).
5. **The order of units** for the ship team, each testable on its own and
   leaving `bun dev check` green; which tests go with the tabs, which are
   rewritten, which stay (runtime, with the others' input).

## Constraints

- **AGENTS.md is binding**: the one rule (take a library before writing
  one; a library that does not fit goes to the owner); every action has a
  key and a panel entry; logic in pure tested modules; tests never reach a
  real agent; `tests/` mirrors `src/`; the 90 s per-file timing budget
  (`tests/timings.json` changes when files go).
- **Written decisions are overturned by name.** Removing tabs overturns
  entries in `docs/decisions.md`; list each one you touch by its heading
  (e.g. 2026-10-06 "Several sessions: a tab list of chord's own…", "the
  strip, the leader line and the `session:` keys", "a session behind that
  needs the person"; 2026-10-07 "closing one, and quitting with several
  open"; 2026-10-08 "The sessions picker…", "`/new <agent>`…", "`-r <id>
  -r <id>`…", "A window record…", "Windows in `/resume`…"; 2026-10-21
  CHD-492's "until CHD-493, the front tab's"), and say what of it holds.
- **No silent workarounds**, no argv rewriting, no guessing at ambiguous
  input (the `-r` history in decisions.md).
- **Session records** (`records/<uuid>.jsonl`) are a stored format people
  already have (0.54.0 was the first release). Nothing that reads them may
  break.
- **No code, no live agent.** Read the code and tests; do not edit
  anything under `src/`, `tests/`, `scripts/`, `lint/`.

## Non-goals

- Several sessions in one process by another name (splits, a session
  switcher). The terminal does that.
- Changing children, teams, tasks, monitors, subagents beyond removing
  the tab level above them.
- CHD-492's carrier or Chorded's side; only the "front tab" wording goes.
- A launcher-given id, a lock, or anything Q120–Q123 superseded.

## Owner questions

The owner is asleep. A question that is the owner's (scope, changing what
the task asks, a stored format broken, a library not fitting) is not
decided by us: name it in your draft under "Owner questions" with options,
context and your recommendation, then design around the recommended
option and mark where the design depends on it. The lead puts each on the
board.

## Each draft

`protocol.md`, `interface.md`, `runtime.md` in this folder: your answers
to the items above that name you, with file and line references to
origin/main, the decisions you overturn by heading, and your owner
questions. Interface also draws the screens that change at 120x40 and
80x24 as text. Keep it to what the build needs.
