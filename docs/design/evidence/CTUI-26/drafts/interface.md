# CTUI-26 interface proposal

Design only. The existing port has no saved-session implementation. Captures
are sanitized observations of the original and current port, not proof of
implemented parity. See `../interface/README.md` for provenance, substitutions,
key sequences and evidence limits. No framework API addition is needed.

## Call site first

Proposed port-owned API, using the existing widget vocabulary:

```dart
ResumePicker(
  key: ValueKey('resume/$opening/${picker.everywhere}'),
  picker: picker,
  agent: launch.name,
  home: home,
  rows: listRows,
  room: room,
  starting: starting,
  onToggleScope: toggleResumeScope,
  onSelected: pickSession,
  onCanceled: starting ? cancelStartup : closeResumePicker,
);
```

`ResumePicker` is a proposed plain port widget in
`example/chord/lib/ui/pickers/pickers.dart`, not a new framework Picker or
file-store widget. `ResumePickerState` belongs beside the existing pure
settings picker state. Its snapshot contains sessions, cwd and everywhere.
The caller owns the opening identity, session snapshot and lifecycle; the
widget owns only focus and its existing Picker's highlight/viewport.

The custom row uses the existing `Picker<EarlierSession>` with
`searchable: false`, `showNumbers: false`, `wrapNavigation: false`,
`showInitialSelectionAtTop: false`, `countHiddenItemsAbove: true`.
Compose the caller-supplied original padded number and row content through
`itemBuilder`. No new query filter is introduced. Numeric selection remains
Picker's 1–9 behavior. Supply a wrapping Text builder; the default label
builder cuts and is unsuitable.

Within `itemBuilder`, an inner LayoutBuilder provides the actual row content
width after Picker's marker and any overflow edge column. When the available
title width beside the widest metadata is at least half the enclosing frame's
inner width, use Row(fixed-width metadata Text, Expanded(Text(title))).
Otherwise every row uses Column(metadata Text, Text(title)). This threshold
is list-wide, not a decision made separately for each title. The original's
`pickerLines` is the oracle. Number/metadata appear only on the first line;
continuation text hangs under the title in the wide case and under row content
in the stacked case. The selected style inherits through all wrapped lines.

Use existing Text shaping and Picker measurement once per layout. Do not
prewrap strings, derive manual heights, build a second text parser or pad
continuations into strings. Compute column widths, age labels, path labels
and title choices in pure Dart; actual wrapping stays with Text. Framework
architect confirms these primitives suffice. Any measured mismatch returns
to the owner before adding a workaround or new API.

The frame follows SettingsPicker: Box with rounded border, horizontal padding
one, title Text, bounded/clipped body, one gap, then hint Text. Use the
permission/focus palette role for border, bold title and selected content;
normal text for rows, dim description and hint. A missing permission color
uses the dim border role. Empty-body wording remains ordinary text. Keep
Esc/Ctrl+A available on a frame with no visible rows; omit Picker entirely
when its visible list budget is zero.

## Original behavior to preserve

Authoritative current sources under `../chord`:
`src/cli.ts`, `src/main.tsx`, `src/session/sessions.ts`,
`src/session/session.ts`, `src/ui/app/Start.tsx`, `start_layout.ts`,
`sessions.ts`, `state.ts`, `src/ui/pickers/Pickers.tsx`, `picker.ts`,
`state.ts`, `src/ui/header/header.ts`, and `docs/guide.md`.
CHD-445 documents wrapping/titles. CHD-174 is historical: its window-record
choices are superseded by the current single-session source and guide;
CTUI-26 does not bring legacy window records forward. CTUI-15 supplies the
Conversation/reducer record seam; CTUI-18/21/23 supply start layout, overlays,
Actions, settings frames and current header/transcript conventions.

| Entry | Behavior |
| --- | --- |
| New invocation | Normal new-session launch remains unchanged. |
| `-c`, `--continue` | Latest prompted session for selected/default agent in the invocation cwd; no agent picker. Missing: `No earlier <agent> session in <cwd> to continue.` |
| `-r <id>`, `--resume <id>` | Latest matching record selects its cwd; without explicitly named agent, record selects agent. Unknown id goes to selected/default agent with invocation cwd. A record owned by another explicit agent refuses: `Session <id> belongs to another agent (<agent>).` |
| Bare `-r`, `--resume` | No agent starts before the title-page choice. List initially shows selected/default agent's sessions in this directory. Ctrl+A exposes its sessions in every directory. Startup may open either directory. Esc exits with no session. |
| Bare resume outside a terminal | `--resume needs an id when not in a terminal`. |
| No sessions anywhere at startup | CLI validation error `No earlier <agent> session to resume.`; no empty global picker. |
| `/resume` | Read records afresh, excluding current session, for main's agent. Open initial local scope even if only remote directories have records. Empty globally: command report `No earlier <agent> session to resume, here or in any other directory.` |
| Read failure in `/resume` | Command report `Could not read the earlier sessions: <error>`. |
| Busy `/resume` | Command report `A turn is running. Wait for it to end, or press Esc to interrupt it, then /resume.` Use current bound cancel key; omit cancel clause if unbound. Recheck after asynchronous listing and on acceptance. |
| Cross-directory `/resume` pick | Close picker, keep current session, report `That session is in <shown cwd>. Quit and open it there with:` and the reopen command on its own line. Never change cwd underneath live settings/files/shell. |
| Same-directory pick | Close picker; return queued prompts to draft through current queue policy; replace main session beneath existing Conversation ownership; replay history into new transcript. Runtime draft defines cancellation/close ordering. |

Startup agent-command override affects default agent alone when no explicit
agent was supplied; preserve original record-agent mismatch refusal. Reopen
commands repeat the explicitly typed override (and explicitly typed
no-MCP flag when that feature exists), never record secrets/settings. This
slice must not silently add unrelated settings flags or headless support.

### Optional-id adapter

Owner approved a bounded token adapter before existing `args`, with no CLI
migration. Proposed pure result intent:

```dart
sealed class ResumeIntent { const ResumeIntent(); }
// Absent, PickEarlierSession, ContinueLatest, ResumeSessionId(id).
// Result also carries unchanged argv for the existing parser and a refusal,
// if the original would refuse the resume grammar.
ResumeArguments adaptResumeArguments(List<String> argv);
```

Use lead's retained `cli-trial/oracle.json` as the grammar oracle rather than
inferring semantics from conventional CLI expectations. Preserve bare/id/=id,
short forms, repeats, `-c` conflict, `--`, dash-leading ids and known-flag
ambiguity. In particular `--resume=c` and `--resume=-r` select the picker,
`--resume=` means absent, `--agent-command --resume` is a literal command
value, tokens after `--` are never adapted, and `-raaa` is unsupported.
Do not reinterpret another option's value. Parse errors retain existing
help/stdout, error/stderr and exit-2 conventions; previously approved help
layout differences remain. No new search option or package migration.

### Row content and scope

Newest first, stable on tied times according to original source ordering;
deduplicate by agent session id using its latest record. Title falls back to
first prompt; child name precedes it when present. Task provenance retains
original label policy even when opened independently as main; no runtime is
revived. Scope toggling remounts Picker so each list opens from top. Freeze
relative ages and label snapshot for that scope's opening: a ticking clock
must not move rows under the highlight. Resize lays out the same snapshot.

Original `lastUsed` uses six fixed units (365-day year, 30-day month, week,
day, hour, minute), flooring count; under a minute/future is `just now`,
English numeric:auto includes `yesterday`, invalid timestamp displays raw.
Lead owns retained package trials and owner-approved narrow original-label
port. Do not substitute timeago thresholds or localized wording.

In all-directory scope, age then optional `open now` then directory then
title are separated by two spaces; each column aligns to its widest cell
width. Directory column caps at 30 cells, uses existing homePath/cutPath
policies and drops leading complete segments. Local scope omits directory.
M4's `open now` navigation is not implemented here; keep the future open-id
seam explicit and empty for a single-main window, without invented children.

## Actions, keys and priority

| Key | Description / binding scope |
| --- | --- |
| `/resume` then Enter | Resume an earlier session; existing prompt submit/command dispatcher and completion catalog. No separate hotkey. |
| Up / k | Previous choice; focused Picker only, clamp at first. Tall selected choice reads one line at a time before changing choice. |
| Down / j | Next choice; focused Picker only, clamp at last; tall-choice policy as above. |
| Enter | Resume highlighted session; Picker acceptance enabled only while a visible row exists and picker owns current action. |
| 1–9 | Choose item 1–9; focused Picker numeric acceptance, result positions rather than visible page positions. |
| Ctrl+A | Toggle session directory scope; outer resume Actions, including empty/zero-row states. Description `Show sessions in all directories` or `Show sessions in this directory`. Takes precedence over prompt select-all only while shown. |
| Esc | `Close resume picker` in-window, `Cancel session selection` at startup. Live scope does not cancel the underlying turn. |
| Ctrl+C | Startup cancellation through startup Actions, preserving original startup cancel policy. Live window retains existing clear/arm/quit and cancel routing. |
| Ctrl+D | Existing window Quit; no session means no fabricated resume command on cancellation. |

Suppress Picker-owned Esc so outer Actions owns it. Suppress Picker's generic
scroll bindings (Home/End/PageUp/PageDown/shift variants) as existing port
settings pickers do; they must not become new resume navigation actions.
Keep Up/Down/j/k/Enter/digits in Picker Actions and include them in the staged
shortcut catalog while resume owns input. Add scope toggle and context close
descriptions there too. Startup retains the original compact hint; no new
shortcuts panel or `?` action is invented on that title page.

Hint verbatim when rows fit:
`Enter to resume · Ctrl+a for all directories · Esc to close` (live) or
`... · Esc to quit` (startup); everywhere changes to `for this directory`.
When no row fits, omit Enter. Hints do not add navigation wording the original
does not print. Source shortcuts still expose the navigation actions.

Permissions/forms have priority over a retained picker. Resume visibility
requires not closing and no outstanding asksPerson; unlike model settings,
a failed connection does not itself hide resume. Output streams beneath its
opaque floating frame; opening/closing does not change transcript viewport,
prompt, gap, status or scroll. Suspended input bindings cannot consume a
permission answer. Reappear with the same retained snapshot after asks clear;
only explicit scope change resets navigation.

## State and failure ownership

App passes data snapshot, cwd, scope, opening token, theme and active/visible
facts. Picker owns focus/highlight/scroll; page owns a settle-once latch, then
freezes focus immediately on pick/cancel. Pure logic owns filtering, ordering,
labels, refusals, request identities and adapter grammar. Async record reads
carry an asked token: clear, newer request, closing or session replacement
invalidates an old result. No widget does file IO or ACP.

On actual reopen: record-backed history wins for drawing; use agent load
replay only without record. Agent `session/resume` is preferred when offered
and a record exists, or load is unavailable; otherwise load. Unsupported
capability and failed load use existing StartConnection/AppState failure
presentation with the actual protocol error, never an invented successful
empty session. Repeated acceptance must not start two processes. Keep unknown
id, failed load and original agent-replay differences under runtime tests.

Resumed header is a separate missing port unit: existing compact header gains
`resumed · <age> · <title>` after help. Use original `headerLines`: absent age
is omitted; actual agent title wraps, fallback prompt is cut by existing
header row policy. Freeze opened title facts; later title updates do not
rewrite what the header opened with. Do not restore the large splash inside
the live transcript.

Owner-approved history omission notice: after supported replay and before new
live output, add exactly one window-only plain text line:
`Some saved history is not shown in this version.` Draw ordinary transcript
text with normal wrapping and left inset, no severity mark, no fake agent
name. Deduplicate per opening, not forever per id; do not append it to the
original record or agent history. Candidate original child/monitor notices
name specific runtimes and `/resume` behavior, so they do not fit a generic
unsupported-history omission. Notice is a deliberate approved port difference;
unsupported children/teams/monitors remain preserved opaque history, never
revived. No notice when nothing was omitted.

## Screen drawings and evidence matrix

Full observed screen files exist at 120x40 and 80x24. The following text
extracts describe composition, omitting blank rows, not literal replacement
captures. Geometry is inherited from current startLayout/overlay machinery.
All states use normal text, dim hint/description, permission border/title and
selected rows; errors use existing error role; waiting uses existing accent.

120x40 startup: full mark/wordmark/tagline, centered version line, 84-cell
resume frame. 80x24 startup: compact mark/wordmark, centered version line,
78-cell frame. The list caps at 14 rows on full step; selection and overflow
indicators use existing Picker. Both retain one gap before hint.

```text
120x40 focused local (frame centered)
                  ╭──────────────────────────────────────────────────────────────────────────────────╮
                  │ Resume a session                                                                 │
                  │ Pick one of fake's earlier sessions to open.                                     │
                  │                                                                                  │
                  │ ❯ 1.  1 hour ago  Inspect wrapping, history and session resume behavior ...       │
                  │                    [title continues under its start; never ellipsized]            │
                  │   2.  2 hours ago Saved session example 3                                         │
                  │                                                                                  │
                  │ Enter to resume · Ctrl+a for all directories · Esc to quit                       │
                  ╰──────────────────────────────────────────────────────────────────────────────────╯

80x24 focused all (frame width 78)
 ╭────────────────────────────────────────────────────────────────────────────╮
 │ Resume a session                                                           │
 │ Pick one of fake's earlier sessions to open.                               │
 │                                                                            │
 │ ❯ 1. just now      fixture-other                                            │
 │      Saved session example 1                                               │
 │   2. 1 hour ago    fixture-project                                          │
 │      Inspect wrapping, history and session resume behavior across a        │
 │      deliberately long saved session title with extra details 2            │
 │      … +16 more                                                            │
 │                                                                            │
 │ Enter to resume · Ctrl+a for this directory · Esc to quit                   │
 ╰────────────────────────────────────────────────────────────────────────────╯
```

The ellipsis in the first schematic is explanatory; actual titles wrap fully.
Sanitized directory labels are shorter than captured paths and therefore
cannot prove exact column widths; original width/threshold logic above is
required. Observed original-120-start and original-80-all retain actual line
breaks after sanitization.

| State | 120x40 drawing / 80x24 drawing | Evidence and required gate |
| --- | --- | --- |
| Empty local, remote exists | Same respective full/compact title pages; frame body `No earlier sessions in this directory.`; hint `Ctrl+a for all directories · Esc to quit`; no marker/list. | Both observed `original-*-empty-here`. Empty globally is CLI error, not this screen. |
| Focused local | Header + local age/title numbered rows + live/start hint. Titles hang under title column. | `original-120-start`, `original-80-here`; port absent. |
| Focused all | Add aligned directory metadata, titles stacked when half-width condition fails. | `original-120-all`, `original-80-all`. |
| Live overlay | Compact live header/transcript remains behind full-width rounded picker above unchanged prompt/status; description `fake's earlier sessions in this directory.` | `original-120-slash`, `original-80-slash`; every-directory `original-80-slash-all`. |
| Overflow | Existing `… +N more` and edge arrows; clipped tall selected row advances a line per Up/Down. At 80 rows stack sooner and list shrinks. | Observed in all-directory captures; complete tall-row traversal at both sizes remains ship gate. |
| Streaming beneath retained picker | Same overlay at both sizes, transcript streams beneath; accepted /resume during running turn reports refusal rather than opening. | Source-derived, not captured as simultaneous streaming+picker. Deterministic fixture required. |
| Waiting on person | At both sizes permission/form frame replaces resume, prompt/status keep rows; only permission keys active. When cleared, retained resume can reappear. | `original-*-permission` shows base permission at both sizes, not suspension/reappearance. Combined transition remains ship gate. |
| Reading records | Keep previous live screen and draft with token outstanding; no invented spinner/pending picker. | Source-derived; delayed-read capture/test required. |
| Cross-directory refusal | Command report `That session is in fixture-other. Quit and open it there with:` followed by wrapped reopen command; picker gone, prompt restored. | `original-80-elsewhere`; 120 case and quoting/override edge cases remain ship gates. |
| Reopen failure | Existing compact live header, preserved/replayed supported past as runtime ordering dictates, actual startup/protocol error, quit/retry navigation. Never splash success. | Source-derived; exact fake refusal captures at both sizes remain ship gates. |
| Resumed | Compact header plus resumed age/title, supported history, optional one omission line, empty live prompt/status. | Proposed port gate at both sizes; no port capture claims this. |
| Zero-row live picker | Title + scope/close hint remain, body cut from bottom; no Enter/navigation/digits; transcript/prompt still routed normally. | Source-derived; both-size tall-draft fixture required. |
| Narrow startup | Pure start steps lose art then title as current layout prescribes; frame clipped to terminal. | Actual 32x10 original clips bottom frame/hint. Preserve observation; no unapproved repair. Wider 120/80 are observed. |
| Unfocused / settled | No active highlight/keys after startup acceptance; retained overlay loses action eligibility beneath asksPerson. | Source-derived; double-pick and suspended focus tests required. |

Light/plain startup captures exist at both required sizes, in addition to
default palette captures. They establish role/geometry observations only.
Port implementation must gate dark/light/plain and long/non-ASCII titles,
paths and narrow edges. Tmux evidence does not prove physical cursor focus
appearance; no cursor behavior is changed by this design.

## Current port beside original

Original and port commits are pinned in the evidence README. The current port
has the standard compact fake window at both sizes but no resume picker,
record discovery or resumed header. `port-120-slash` / `port-80-slash` retain
a typed `/resume` draft and show no picker: these are evidence of typed command
availability only, not a demonstrated dispatch-refusal message. Current
`port-80-resume-flag` exits 2 with `Unknown option "--resume".` after help.
The `startup_choice.dart` resume parameter and framed start-layout branch are
future seams, not working resume flows. Do not credit them as implemented.

## Buildable units and tests

1. Pure summaries/labels/refusals and immutable resume intent. Port session
   modules mirror original `sessions.ts`; test empty/prompted-only discovery,
   latest/dedup/exclude-current/agent/cwd rules, first prompt/title/name and
   frozen age boundaries. Lead's approved relative-time fixtures are oracle.
2. Resume state, row composition and framed Picker. Terminal-free widget tests
   at 120x40 and 80x24 for local/all/empty/overflow/multiline/half-width branch,
   digits/clamps/tall reading, reset-on-scope, unchanged-on-resize and zero-room
   action gating. No new framework API; framework tests cover its primitives.
3. Resumed compact-header facts and plain omission line. Check long titled
   versus first-prompt fallback, absent metadata, single notice only when
   omitted, resize/rebuild dedup and no record write of notice.
4. Startup resume page and approved token adapter. Share current private title
   implementation in `ui/app/start.dart`, existing framed startLayout and
   settle-once focus latch. Test cancel means zero starts, any-directory pick,
   CLI original-oracle cases, known/unknown id and agent ownership failures.
5. Live command/reducer/session replacement. Add real `/resume` dispatcher
   handling, snapshot token and scope action; mount with existing anchored
   overlay machinery. Test busy/read/late-clear/late-close/late-session result,
   permissions priority, cross-directory report, queue return and exactly one
   accepted replacement. Runtime draft supplies transport/record correctness.
6. Live synthetic fixture plus compiled fake executable. Retain original/port
   paired frames and key logs at both sizes, all palette roles, resume/load
   failures, unknown id, omitted history, interrupted save and prompt-after-
   resume proving same agent session id. Clean all owned PTYs/processes.

No source edits, commits or independent task agents belong to this draft.
Remaining capture gaps above are implementation acceptance gates, not claims
that the design has achieved runtime parity. The one approved visible
compatibility difference is the omission line; package decisions and parser
oddities belong to the lead's final design and decisions entries.
