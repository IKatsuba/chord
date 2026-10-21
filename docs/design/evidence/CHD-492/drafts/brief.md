# CHD-492 — brief

The lead's brief for the architects. The task is on the board (`board show
CHD-492`); the ship team's survey of today's code is its comment #9619.
Asked from Chorded, the terminal app chord runs in (its resume task is
CHRD-412). Drafts go in this folder only; the design goes to
`docs/design/CHD-492.md` and decisions to `docs/decisions.md`, both the
lead's.

## The problem

Chorded wants to reopen a chord window after its pane ends, as it does
Claude Code with `--session-id` / `--resume`. Today nothing it can hold
exists before chord quits cleanly:

- A session record (`records/<uuid>.jsonl`) starts only at the first
  prompt (decisions.md, "Resume on chord's own session record": "Nothing is
  written until a prompt is").
- The window record (`windows/w-<8 hex>.json`, `src/session/windows.ts`)
  is written in one place, the clean quit in `src/main.tsx`, and only when
  two or more tabs had a prompt (decisions.md, "A window record, and
  `--resume w-…`"). Its id is minted at quit.
- SIGHUP / SIGTERM (how a terminal app ends a pane) run `closeAll`, flush
  session records and re-raise; no window record and no resume line. SIGKILL
  and a crash keep session records up to the last line.
- ACP `session/new` takes no client-chosen `sessionId` (SDK 1.8.0, v1 and
  v2), so the agent's own id cannot be the launcher's.
- `chord --resume <sessionId>` itself restores reliably (12/12 in
  Chorded's VM run).

## What a person (and the launcher) sees and does

1. Chorded opens a pane running `chord <something naming an id it chose>`.
2. The person works: any number of tabs, including one, including tabs that
   never got a prompt; `/clear`, closing and opening tabs, reordering,
   switching the front tab.
3. The pane ends: ctrl+d, `/exit`, SIGHUP, SIGTERM, a crash, SIGKILL.
4. Later Chorded runs `chord --resume <that id>` (or the creating command
   again) and the window comes back as it last was: same tabs in order,
   same front, same directories and agents.

## Constraints

- **The one rule.** Anything parsed or written goes through what chord
  already uses (Cliffy for flags, zod for the record, the atomic
  write-and-rename of `saveSetting`). A library that does not do what is
  needed goes to the owner, not around.
- **Written decisions.** The ship team's shape overturns two: the window
  record written at quit, and only for two or more prompted tabs. Changing a
  written decision is the owner's call: the design proposes, names the
  options, and the lead hands the question to main.
- **Stored formats.** Existing `w-` records (`id`, `at`, `tabs` min 1,
  `front`) must still read. A record written by the new chord should read
  in the old one, or the design says why not.
- **Signals.** The exit paths of decisions.md "OpenTUI part 6" (renderer
  destroyed, agents reaped, die by the signal) stay; whatever is written on
  a signal fits in them and is bounded.
- **Tests never reach a real agent**: the fake agent in
  `tests/fixtures/fake_agent/` and the harness drive it; a signal and a
  SIGKILL must be testable.
- No new dependency unless a library is the answer.

## Non-goals

- Choosing the agent's own session id (not possible over ACP; revisit only
  if the SDK grows it).
- Restoring a tab's draft prompt, scroll position or unsent text.
- Restoring a never-prompted tab's agent-side session (no record exists).
- Chorded's side (CHRD-412) beyond the command it should call.
- `/resume`'s picker layout, except where a new kind of record must show.

## Questions to settle (all architects weigh in where it touches them)

Alternatives to weigh: (a) a launcher-given window id kept current from
start; (b) the window record also written in the signal path; (c) the ids
reported in the OSC 7501 record; (d) a client-chosen agent session id
(rejected up front, say so).

### protocol (records, ACP, what is stored)

1. The flag and the id format: `--window w-<id>`, a new `--session-id`,
   or `--resume` that creates when missing? What does a launcher may choose
   (`w-` + 8 hex only, or any `[0-9a-z]` the existing regex takes, a UUID)?
   How does it sit with `-r`, `-c`, `[agent]`, `-p`, Cliffy's optional
   value limit (decisions.md, "Windows in `/resume`")?
2. The record's schema: an empty window, a tab with no session yet, a
   "live"/"ended" mark, a writer pid. What keeps old records readable and
   new records readable by an older chord?
3. What a tab with no prompt is written as and restored to: a fresh session
   of its agent in its directory? Left out?
4. `/clear` in a tab: the tab's new session replaces the old in the record.
   A tab opened by `/resume` or `ctrl+x c`, a team or task agent: in or out?
5. Is the session record's "nothing until a prompt" kept?
6. OSC 7501: does reporting the window id there help, given the id must
   exist up front anyway? Is there a field for it?

### interface (screen, keys, state)

1. What a person sees: on start with a new id, on reopen, on reopen of a
   window another chord holds, on a record that cannot be written, on a
   tab left out. Screens as text at 120x40 and 80x24.
2. The quit message: does a window started with an id still print
   `Resume this window with:`, and for one tab, the session command or the
   window command?
3. Which state slices change (tab strip events that must cause a write) and
   where the pure "window as a record" function lives so a test reaches it.
4. `/resume`: a window record with one tab or none — listed, and how?
5. Any new key? (Probably none; say so.)

### runtime (processes, writes, failures, tests)

1. What is written when: at start, on each change (which events), coalesced
   how, the cost; at quit; on a signal; nothing possible on SIGKILL —
   what the last write on disk is then.
2. Two chords started on one id at once, or one started while another
   holds it: a lock (pid file, `O_EXCL`, `flock` through a library?), stale
   lock after SIGKILL, what the second one does.
3. Failure cases: state dir unwritable, disk full, a record half-written
   (rename keeps it whole?), a record naming a session record that is gone,
   an agent that can neither load nor resume, a directory gone.
4. Whether SIGHUP on a closing pane leaves time to flush; what the design
   must not depend on.
5. How each exit (clean, SIGHUP, SIGTERM, crash, SIGKILL) is tested
   against the fake agent, and `bun dev selftest`'s part.

## Output

Each architect writes `drafts/<role>.md`: answers by number, the options
weighed for each and the pick with its reason, what the owner must decide,
libraries tried. Read AGENTS.md, decisions.md's window, resume, record and
OpenTUI-exit entries, `src/session/windows.ts`, `src/main.tsx`'s quit and
signal paths, and the CLI in `src/cli*` before writing. No code.
