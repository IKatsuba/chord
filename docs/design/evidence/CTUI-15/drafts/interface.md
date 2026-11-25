# CTUI-15 interface draft

This proposes the plain state contract CTUI-16–19 need. It builds no widget
and changes no key or wording. Source references below are relative to
`../chord`; line numbers describe the source read for this draft. Text mocks
are design sketches, not measured captures or visual acceptance.

## Call site first

The exact declarations belong to framework's draft. This illustrative Dart
shows the author-facing division; these are port components, not proposed
framework exports:

```dart
Widget build(BuildContext context) {
  final state = conversation.value;
  return Column(children: [
    Expanded(child: TranscriptView(
      entries: state.transcript.entries,
      turn: state.transcript.turn,
      expanded: expanded,
      controller: scroll,
    )),
    WorkingLine(turn: state.transcript.turn),
    PlanView(entries: state.transcript.plan),
    QueueView(prompts: state.queue),
    if (state.waitingPermission case final wait?)
      PermissionView(
        request: wait,
        active: permissionHasFocus,
        onChoose: (id) => conversation.answer(wait.id, Choose(id)),
        onReject: () => conversation.answer(wait.id, Reject()),
      ),
    PromptView(controller: draft, onSubmit: conversation.send),
    StatusView(connection: state.connection, facts: state.statusFacts),
  ]);
}
```

Subscribe outside `build`, unsubscribe on disposal. `send`, `cancel`, `answer`
are intents into the session/conversation owner; they do not perform ACP in a
widget. A UI tick supplies `now` to the pure elapsed formatter: the reducer
stores facts/timestamps, never a spinner frame or a once-per-second entry.
Original: `src/ui/status/Status.tsx:23-97`,
`src/ui/app/state.ts:1575-1584`, `src/session/enrich.ts:111-118`.

The app owns immutable entries, plan, turn, queue, request identity/options,
connection availability, results and permission receipts. The UI owns draft
text/cursor/undo and history navigation, expanded view, scroll/follow state,
permission highlight/request scroll/focus, and elapsed/spinner timers. Pure
helpers beside widgets own formatting, queue row limits/restoration, plan
folding, tool headlines/content summaries and permission choice/outcome
mapping. The conversation owns queue withdrawal/delivery; UI does not remove
queue entries optimistically on a keypress.

## Entry and state requirements (Q2)

All entries retain their turn identity and insertion order. Updating a tool
replaces that entry in place. Contiguous message chunks update the last block
only when kind, turn and message identity permit it; a tool/thought boundary
starts a fresh assistant block. Non-text assistant blocks draw no text in the
original (`src/session/transcript/messages.ts:9-54`). The list needs stable
entry identity and a changed entry value, so a streaming block remeasures
without losing the user's scroll. Do not identify an entry by its text.

| Kind | Plain data CTUI-16 needs | What the person sees |
| --- | --- | --- |
| user | turnId, original text | Submitted words, preserving line breaks; a queued prompt is not a user entry yet |
| assistant | turnId, text, optional messageId | `⏺` and Markdown, including partial streaming Markdown |
| thought | turnId, text, optional messageId | Dim italic `∴ Thinking…`; ctrl+o reveals the accumulated dim italic text |
| tool | turnId; call id, title?, kind?, status?, locations?, content?, rawInput?, rawOutput? | `⏺ Read(file)`, `Bash(command)`, etc.; title's multiline content wraps whole. Result under `⎿`; failed calls retain a textual failure, not colour alone |
| permission receipt | turnId, request's title?, chosen option? with id/name/kind | `Allowed <title> · <option name>` for allow_once/allow_always; `Rejected <title>` otherwise. Missing title becomes `the tool call`. Withdrawn requests leave no receipt |
| cancelled | turnId | `Interrupted by user` in error tone; only after an actual cancelled result, not merely Esc |
| stopped | turnId, reason | `Stopped: <reason>` for a completed result whose stopReason is not `end_turn`; ordinary successful end_turn adds no ending row |
| error | turnId, message, code? | Error-tone message; keep code as a fact, do not prefix invented diagnostic wording |
| warning | turnId, message | Warning-tone message; does not change the turn to failed |
| plan (historical) | turnId, entries[] with content/status/priority | A completed plan kept at its settlement position in the transcript; separate from the live plan checklist |

Evidence: `src/session/transcript/types.ts:416-535`,
`src/ui/transcript/Transcript.tsx:143-168,827-859`,
`src/ui/transcript/tools/tools.ts:85-145,205-270,405-475`,
`src/ui/dialogs/permission.ts:132-145`,
`src/session/transcript/turn.ts:250-275`.

Tool content must retain ACP text blocks and diffs (`path`, `oldText`,
`newText`; null old text means creation), not flatten them into one string.
Diff calculation/highlighting belongs to the framework's Diff dependency
work, not CTUI-15. Preserve raw input/output for the pure presentation
helpers and later extensions; widgets must not inspect transport messages.
Tool status remains optional/unknown rather than guessed. Original merge
keeps omitted fields, replaces supplied content (including `[]`), accepts an
update before its initial call, and never regresses a finished known status
(`src/session/transcript/tools.ts:28-99`). The UI derives `ended` from turn
identity/state to avoid an old unfinished call saying it is still running
(`src/ui/transcript/tools/tools.ts:277-287`).

A live plan is `List<PlanEntry>` in agent order, with content, status and
priority. `[]` clears it; ordinary `plan` updates replace it. On turn end,
if every step is completed, append the historical plan entry and clear the
live plan; otherwise keep it above the prompt for the next turn. This is
ordinary M1 plan behaviour, not the deferred id-addressed plan protocol.
Evidence: `src/session/transcript/turn.ts:203-217`,
`src/session/transcript/types.ts:527-535,976-984`,
`src/ui/plan/plan.ts:1-14,41-82`. Plan-as-state-only would lose visible work
and is therefore insufficient.

### Permission request, distinct from its receipt

CTUI-18 needs an ordered pending list, not one replaceable nullable request.
Each wait has id, optional toolCallId/title/kind/locations/content/rawInput,
ordered options (optionId/name/kind), and arrival time. Keep `between` and
held/focus semantics available: a request arriving with no active prompt, or
still open after its turn settles, remains visible without stealing typing.
`ctrl+x a` attends it. Only the oldest is shown, and an answer identifies the
request, not the toolCallId: two requests for one tool are distinct.

When content is absent, retain rawInput and draw each key/value as the
original does, nested values compact JSON and string values unquoted. Show
proposed diffs above the answer row. Preserve optional generic permission
review `{outcome, reason}` and authoritative `deadlineAt` if supplied:
CTUI-18 explicitly requires the reason visible at 80x24. These are request
facts, not the deferred elicitation form or Codex Guardian tool protocol.
Do not fabricate a deadline, or decide permission outcome from the UI clock.
Evidence: `src/session/transcript/types.ts:748-770,798-805`,
`src/session/transcript/permissions.ts:17-104`,
`src/ui/dialogs/permission.ts:28-44,107-125,155-209`,
`src/ui/dialogs/Permission.tsx:68-74,180-219,232-239`.

The reason, options and reject hint are pinned. Only the request body
scrolls; the title's first row stays. A long title wraps into the scrollable
body. At 80x24 the transcript gives rows before choices or reason do; no
clipping away approval meaning. Existing design: `docs/design/CHD-246.md`,
`docs/design/CHD-158.md`; current source above is authoritative where that
older design's description of then-current behaviour differs.

## Session projections and intents (Q6)

Do not model cancelled/failed/gone as three new busy turn states. The
original busy turn union is idle/working/awaiting_permission/cancelling;
last result and connection status explain why work ended. A failed prompt
can leave a ready connection; gone prevents sends. This distinction is
necessary for retrying by entering a new prompt after a turn failure.

| Situation | Required facts | Draw / permitted intent |
| --- | --- | --- |
| Empty, ready idle | ready connection, empty entries/queue/plan, idle turn | Empty transcript; focused prompt; no spinner. `send(text)` when nonblank |
| Working/streaming | turnId, since, entries, queue | `››› Working… (12s · esc to interrupt)`; typing and `send` queue behind the turn; `cancel()` on Esc |
| Waiting in turn | turnId, since, ordered waits | `››› Waiting for permission… (12s)`; choices take keys; `answer(id, chosen option or reject)`; Esc rejects the request, does not cancel the turn |
| Waiting between turns | retained waits, between=true, wait time, queue afterAnswer | Same box, initially unmarked; draft keeps keys; status `● permission asked between turns · ctrl+x a to answer`; attending changes focus only |
| Interrupting | turnId, original since, cancelledAt | `››› Interrupting… (12s)`; no premature idle, completed tool status or cancelled receipt. A silent agent stays here until a real result/exit/quit |
| Cancelled result | idle turn, cancelled receipt, ready connection | `Interrupted by user`; prompt restored from withdrawn queued texts followed by existing draft; no spinner |
| Failed prompt | idle turn, error entry, ready connection if still live | Error message; no spinner; new nonblank prompt can be sent |
| Agent gone mid-turn | connection gone, reason/tail, failed result, withdrawn waits | `The agent exited.` or supplied `The agent exited: <tail>` as error; stop working line when the prompt fails; retain transcript/draft; sending disabled |
| Agent gone while idle | gone connection separately from idle turn | Retain transcript and disable send; do not manufacture a failed turn merely to draw a notice. Idle exit visibility is an owner question below |

Working text/timing: `src/ui/status/status.ts:658-737`; turn shape:
`src/session/transcript/types.ts:902-974`. The ordinary in-turn permission
preserves turn.since (`permissions.ts:95-103`), so its counter is not
necessarily time since the request; timed requests use request.at and append
` · denied in <elapsed>` (`status.ts:725-727`). Keep both times available.
Source spinner is three animated `›` marks (`Status.tsx:23-45`), not the
board description's older `✻`. No new static spinner or elapsed wording.

A queued prompt needs turnId, full text and afterAnswer. Its first line is
shown with `…` if multiline; oldest first, newest excess folded to
`… +N more`. At 120x40 its limit is six rows; at 80x24 four. A prompt held
for a between-turn request says `› after your answer: <text>`.
`src/ui/prompt/queue.ts:88-130`. Interrupt withdraws the person's queue
before cancelling, and returns texts oldest-first then current draft joined
by newlines; it never replays these automatically after cancellation.
`src/session/conversation.ts:2471-2538`,
`src/ui/prompt/queue.ts:63-70`, `src/ui/app/state.ts:808-830`.
Expose a queue-withdrawn event/result containing the actual withdrawn texts
(or an atomic UI transition that can read them); ids alone after removing
them cannot restore the draft. History navigation and draft clearing remain
UI logic. `canSend` requires ready connection and text.trim().isNotEmpty
(`src/ui/app/state.ts:1579-1584`).

### Keys and scopes

Bind through Actions; panel descriptions below preserve the original words
where the feature exists. Disabled actions must not advertise an effect.

| Scope | Key | Action and description |
| --- | --- | --- |
| prompt, no active permission | Enter | send / `to send`; busy means enqueue |
| prompt | Shift+Enter, Alt+Enter, Ctrl+J; backslash then Enter | newline / `for a newline`; draft only |
| prompt at first/last visual row | Up / Down | history previous/next; otherwise textarea navigation |
| prompt with a draft | Ctrl+C | clear draft; no session cancellation |
| chat, excluding a permission with keys | Esc | cancel / `to interrupt or stop a command` (M1 binds the turn part) |
| transcript/app | Ctrl+O | toggle details/thought text, global expanded view; no reducer event |
| active permission choice | 1–9 | choose that agent option immediately; no renaming or invented option |
| active permission choice | Up/Down, j/k | `to move or change a value`; highlight only |
| active permission choice | Enter | `to pick the highlighted choice` |
| active permission choice | Esc | answer rejected / `to reject a permission` |
| held permission/app | Ctrl+X A | attend request; `to answer` in the box hint; does not answer by itself |
| overflowing permission request | PgUp/PgDn; Shift+Up/Down; Home/End | scroll request page/row/start/end; original transcript scroll actions redirected to the box |

Original descriptions/aliases: `src/ui/shortcuts/keys.ts:84-113,150-165,
314-318,373-396`; focus/scroll/draft precedence:
`src/ui/app/state.ts:1870-1873,1939-1985`; request keys:
`docs/guide.md:517-551`. Quit, shortcuts-panel and their Ctrl+C/Ctrl+D rules
belong to their M1 task, not a session method. Tab steering remains M2;
do not advertise `to send the oldest queued now` in M1.

## Fourteen enrichers: visible effect of omission (Q3)

The source order is `src/session/enrichers.ts:898-913`. This table separates
absence of a feature from an invisible omission; the recommendation is not
owner consent for a new difference.

| Enricher (source lines in enrichers.ts) | What disappears or changes without it | M1 recommendation |
| --- | --- | --- |
| subagentShape (311-376) | Old adapter subagents have no normalized agent row/state/work subtree | Defer with subagents; no own-session M1 difference |
| claudeSubagentName (286-308) | Claude task's title no longer supplies its expected display identity | Defer with subagents |
| toolCallFacts (157-203,924-940) | A permission omitting title/kind says `Tool call` instead of the known operation; later updates lack facts for normalization/presentation. Existing tool merge alone keeps old tool headline but cannot repair a separate permission | Include |
| codexMcpCall (768-811) | Codex MCP wrapper may show generic/title-derived headline instead of `<server> - <tool> (MCP)(arguments)`; this affects external MCP calls the agent already makes, not just chord's own server | Include for ordinary tool parity; defer chord-served linking |
| codexGuardianReview (813-824) | `Guardian reviewing…` normalization/hiding of approved review is lost; an approved safety-review call may remain as an ordinary visible tool | Owner scope choice; recommend include this display normalization for ordinary tools |
| rawOutputContent (826-895) | Calls with only rawOutput lose returned text; a completed call with nonzero exitCode may appear successful | Include, preserving agent-own-content priority and empty-refresh semantics |
| modeReadBack (205-277) | Empty mode-change replies leave the displayed mode stale | Defer: mode-changing intents are M2, no M1 request uses it |
| costFromTokens (40-124) | Missing provider cost stays absent rather than an estimate | Defer: costs excluded; do not fake zero |
| windowFromModel (126-155) | Context window size/percentage absent when agent omitted size | Defer estimation; read-only reported context is owner scope question |
| claudeQuestions (461-509) | AskUserQuestion loses canonical headers/choice plus own-answer presentation | Defer: elicitation is not M1 permission; CTUI-12 cancels it |
| codexQuestions (511-598) | request_user_input loses canonical question/note associations and timeout presentation | Defer with elicitation |
| droidQuestions (600-650) | Droid questions lose topic/choice/Other association | Defer with elicitation |
| opencodeQuestions (652-697) | Questions lose header/custom-answer association | Defer with elicitation |
| dimcodeQuestions (699-765) | Questions lose exclusive custom-answer-versus-choice mapping | Defer with elicitation |

For the last five, M1 shows no canonical question box with or without an
enricher because that request type is deliberately cancelled, not a
permission. Their later UI must not pretend they are ordinary permissions.
For toolCallFacts/rawOutputContent, retain the pure ingress normalization
seam and original `_meta['chord/filled']` provenance. `rawOutputContent`
requires per-session per-tool ownContent memory, not checking only the last
reduced content: synthetic content is different from agent-owned content.
The chain has ACP-shaped input/output, before every consumer; UI must never
fill missing fields itself (`src/session/enrich.ts:58-85,111-135`).

### Terminal `_meta` when not declared

No client terminal capability in M1 is fixed by CTUI-12. The fake checks that
explicitly (`tests/fixtures/fake_agent/client.ts:35-55`). A conforming adapter
sends ordinary one-shot text output instead: show it under `⎿` like any tool
result, with its actual tool status, no live terminal model required.

However, capability negotiation is not a proof that every adapter obeys it.
The original reducer *unconditionally* folds `terminal_info`,
`terminal_output_delta`, `terminal_output`, `terminal_exit`, and terminal
content references (`src/session/transcript/tools.ts:139-223`). Its UI shows
the last three terminal output lines, expanded by Ctrl+O, plus a failing
exit note (`src/ui/transcript/tools/terminal.ts:9-66`).
If M1 ignores undeclared terminal metadata, a metadata-only call has a
headline and `Waiting…`/`Running…` while active, `Failed` when failed, and
no result text when completed. A terminal content reference alone does not
supply text. `rawOutputContent` cannot recover absent rawOutput. If ordinary
text accompanies metadata it is still visible; do not also synthesize a
second duplicate text block. Evidence for fallback summary:
`src/ui/transcript/tools/tools.ts:430-475,527-529`.
This precise loss must be handed to the owner; it cannot be described as
all output arriving once for every adapter. Runtime owns adapter/fake
verification and may narrow which adapters actually expose the case.

## Text drawings at both required sizes

These show occupied rows; omitted rows are blank. Right edges are schematic:
every frame expands to the width minus outer padding. Both sizes use the
same strings, wrapping rather than cutting transcript/request text. These
are state projections for CTUI-15's consumers, not a replacement for the
later screen tasks' captures. Header/start-page content belongs to its task.

The following row substitutions describe *each* empty/focused, streaming,
waiting, interrupting, cancelled, error and gone state at 120x40 and 80x24:

| Region | 120x40 rows | 80x24 rows |
| --- | --- | --- |
| transcript viewport | 1–32 | 1–16 |
| blank separation | 33 | 17 |
| working or plan-summary line | 34 (blank when idle/no plan) | 18 (blank when idle/no plan) |
| blank gap | 35 | 19 |
| one-line focused prompt frame | 36–38 | 20–22 |
| status | 39 | 23 |
| bottom blank | 40 | 24 |

Empty and focused (both sizes, prompt rows above):

```text
[transcript empty]
╭────────────────────────────────────────────────────────────╮
│ ❯ ▏                                                        │
╰────────────────────────────────────────────────────────────╯
? for shortcuts
```

Prompt border: theme prompt/focus border; `❯` as original prompt marker,
text normal, cursor at draft position. Unfocused permission-wait prompt
keeps its text without taking keys. Empty transcript has no invented
`No messages` placeholder.

Streaming (both sizes, transcript rows at top, working at row 34/18):

```text
❯ Explain the change
∴ Thinking…
⏺ Read(src/example.dart)
  ⎿ Running…
⏺ The change begins with

››› Working… (12s · esc to interrupt)

╭────────────────────────────────────────────────────────────╮
│ ❯ Next question▏                                           │
╰────────────────────────────────────────────────────────────╯
```

User text normal; assistant normal Markdown; thought dim italic; tool name
bold with status-dependent glyph (pending dim, running pulse, failure error,
completed success); `⎿` dim; working label accent, elapsed dim, spinner mark
gradient. Ctrl+O adds the thought body beneath Thinking and reveals folded
Read/terminal output. Plain Bash text results remain whole and wrapped.

For interrupting, replace the working row with
`››› Interrupting… (12s)` at both sizes, retaining the same transcript and
restored draft. For a confirmed cancelled result, clear that row and append
`⎿ Interrupted by user` (error) to the transcript. For failed result, clear
that row and append `⏺ <agent's message>` (error). A warning uses the same
message block in warning tone and retains a running line if work continues.
For agent gone during a prompt, append `⏺ The agent exited.` (error), clear
the working row after its failure, preserve the frame/draft but disable send.
Long supplied errors wrap within the transcript viewport at both widths.

Waiting permission, 80x24; at 120x40 the same occupied bottom 16 rows are
rows 25–40, leaving rows 1–24 for transcript instead of 1–8. The short
request is identical at either size:

```text
 9  ››› Waiting for permission… (12s)
10
11  ╭────────────────────────────────────────────────────────╮
12  │ Edit src/example.dart                                  │
13  │   - old line                                           │
14  │   + new line                                           │
15  │                                                        │
16  │ Do you want to proceed?                                │
17  │ ❯ 1. Allow                                             │
18  │   2. Deny                                              │
19  │ Esc to reject                                          │
20  ╰────────────────────────────────────────────────────────╯
21  ╭────────────────────────────────────────────────────────╮
22  │ ❯ held draft                                           │
23  ╰────────────────────────────────────────────────────────╯
24  [status]
```

Numbers outside the frame are row coordinates, not visible text. Permission
border/title permission tone, selected choice accent, other choices normal,
reject hint dim, diff additions/removals Diff roles. Agent option names are
examples, always supplied by the agent. Reviewed request: replace the
proceed question with `The safety review held this:` (warning) and its
reason (normal), growing that pinned area and shrinking transcript/request
body. Failed review uses `The safety review could not run (<reason>).
Allow it yourself, or deny it.` (error). At 80x24 all reason/choice rows
remain readable, by allowing less transcript.

Between turns, use the same box in both drawings, without choice marker,
with asker `main · between turns` as supplied by the asker helper and hint
`ctrl+x a to answer`; draft retains its cursor. Bottom status contains
`● permission asked between turns · ctrl+x a to answer`. A subsequently
submitted prompt appears in queue as `› after your answer: …`.

Overflow/narrow, at 120x40 and 80x24: keep the same pinned title, reason,
choices and hint above the prompt; cap only request rows to at most 20 or
12 respectively and less if the remaining screen requires it. Body has:

```text
│ Edit src/example.dart                                    │
│ ── ↑ 8 lines above ────────────────────────────────────── │
│   <wrapped diff/input rows in remaining body room>         │
│ ── ↓ 23 lines below · pgdn to scroll ───────────────────── │
│                                                          │
│ Do you want to proceed?                                  │
│ ❯ 1. Allow                                               │
│   2. Deny                                                │
│ Esc to reject                                            │
```

Rules dim; counts describe *wrapped physical rows*, not source lines.
Do not store those counts in session state: width-dependent layout owns
them. At 80 columns a long title continues in the request body; at 120 more
fits on its first row. Proposed edits retain full old/new text at both
sizes so a later resize reflows without information loss.

Plan/queue at both sizes, above the request/prompt; a live checklist adds:

```text
Plan · 1 of 3 done
  ☒ Read the current implementation
  ◐ Update the reducer
  ☐ Run the tests
› Follow up once complete …
```

Between turns the summary is dim, completed steps dim, in-progress accent,
pending normal; working turns use the working line above the list. Plan row
limit 10 at 120x40, 6 at 80x24; first fold completed steps, then `… +N more`.
Queue limit 6/4; it folds newest entries, not oldest. Data is never removed
because rows did not fit (`src/ui/plan/plan.ts:41-82`,
`src/ui/prompt/queue.ts:88-130`).

## Consumer tests and implementation boundaries

CTUI-15 tests state only: text/thought segmentation and message ids;
tool update-before-call, missing facts, monotonic status, content/diff
replacement; rawOutput and own-content precedence; ordered permission waits,
request identity, chosen/rejected/withdrawn receipts; live-to-historical
completed plans; queue withdraw/restoration inputs; cancelling versus actual
result, failure versus gone, and late updates without reactivating a settled
turn. Runtime owns routing/timing/fake scenarios. No screen golden belongs
in this reducer unit.

CTUI-16 later tests all entry kinds, wrapped tools/diffs, folded and expanded
thinking, stream growth with follow-bottom and a manually scrolled viewport.
CTUI-17 tests Enter idle/queued, multiline history, clear draft and Esc
restoration. CTUI-18 tests two asks for one call, no-content args, overflow
with pinned reason/options, held between-turn focus, number/arrows/Enter/Esc
and stale answers. CTUI-19 tests supplied times without sleeping, each
working-line state and completed/unfinished plans. Each screen test runs
120x40 and 80x24 with the original's text; a green reducer is not visual
acceptance.

## Answers and owner questions

- **Q2:** user/assistant/thought/tool/permission/cancelled/stopped/error/warning,
  plus historical plan entry and separate live plan. Keep permission waits
  ordered and separately answerable. Preserve title/kind/status, rich tool
  content, raw values, message identity and turn identity. Ignore unsupported
  own-session kinds through an explicit seam; do not flatten them into
  assistant text or route a subagent's work into the parent.
- **Q3:** include toolCallFacts, rawOutputContent and codexMcpCall; recommend
  codexGuardianReview for plain-tool rendering parity, subject to scope
  approval. Defer the other ten with their named milestones. Framework and
  runtime decide the minimal Wire storage/placement; presentation never
  duplicates normalization.
- **Q6:** read the projections/table above, dispatch send/cancel/answer only
  through the conversation, keep draft/focus/history/expanded/scroll local.
  Store timestamps and real lifecycle facts; format original words outside
  the reducer. Retain between-turn permission semantics required by CTUI-18.
- **Owner: CTUI-19 status scope.** Board asks model, effort, mode and context,
  but brief excludes their state. Options: (A) carry read-only reported facts
  in M1, postponing controls, estimates and cost; (B) explicitly accept a
  reduced M1 status line and defer all four. Recommend A for visible parity;
  no fabricated values, no mode-change action, no windowFromModel estimate.
- **Owner: undeclared terminal-only metadata.** (A) honor CTUI-12's no-live-
  terminal M1 cut, draw ordinary text fallback when sent, and explicitly
  accept blank completed results for metadata-only adapters; (B) extend M1
  to the original's terminal folding/rendering even without declaration.
  Recommend A to preserve the approved capability boundary, with the exact
  loss documented and adapter evidence from runtime; B costs the deferred
  terminal subsystem. No private metadata-to-text workaround by this team.
- **Owner: ordinary tool enrichers.** (A) include codexMcpCall and
  codexGuardianReview along with the two proposed enrichers, (B) defer them
  and accept generic/missing-argument MCP headlines and visible approved
  Guardian calls in M1. Recommend A: these alter tools already in CTUI-16,
  not only later chord MCP features. If B, list the differences explicitly.
- **Owner: idle agent exit notice.** Original disconnected reducer only
  updates subagents (`src/session/transcript/turn.ts:136-156`); CTUI-13
  measured no new idle exit notice but approved an interim Gone receipt.
  Options: (A) retain explicit CTUI-13 gone receipt in final M1, (B) match
  original's idle visible behaviour while still disabling send. Recommend A
  for continuity, but it needs approval as a visible difference; do not
  invent a failed turn to implement it.

The plan historical entry, original three-mark spinner, retained queue
restoration and between-turn focus above are corrections to the proposed
subset based on the original, not new product decisions. This draft makes
no package selection: it copies no parsing/diffing algorithm and delegates
package trials to the framework/runtime owners.
