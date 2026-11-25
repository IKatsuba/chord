# CTUI-12 interface proposal

Scope: the port's ACP client, M0/M1. This adds no framework widget and no
screen in CTUI-12. The screen sketches below specify the data contract for
CTUI-15 and the later permission/transcript tasks; they are source-derived
schematics, not captured or visually accepted screens.

## I1 — the session author writes this

Keep the original's single ordered ingress: `onTraffic`, supplied before
starting the process. Do not add a broadcast `updates` stream that begins
only after `openAgent` returns. Agents send updates before `session/new`
answers, and even after a prompt answers. The session layer extracts
`session/update` from agent traffic, buffers before the session id is known,
then routes by exact id. It retains updates until its first subscriber is
installed, as the original does. It must neither drop these nor fold them
twice. A record subscriber and reducer share this ingress; a record format
is not this task's API.

Illustrative Dart, with protocol type names pending the framework
architect's package/type finding:

```dart
final permissions = PermissionBridge(); // session-owned, plain Dart
final inbox = SessionInbox();           // early updates + exact-id routing
final agent = await openAgent(
  command: start.command, // String or List<String>, no shell expansion
  env: start.env,
  cwd: directory,
  capabilities: m1Capabilities, // O2: owner's decision, below
  onTraffic: (traffic) {
    record.add(traffic); // nonthrowing; no async work on this callback
    inbox.hear(traffic);
  },
  onPermission: permissions.handle,
  signal: opening.signal,
);
try {
  final opened = await agent.newSession(
    NewSessionRequest(cwd: directory, mcpServers: const []),
    signal: opening.signal,
  );
  inbox.open(opened.sessionId, opened); // fold answer before early updates
  final unsubscribe = inbox.subscribe(conversation.fold);
  try {
    final result = await agent.prompt(PromptRequest(
      sessionId: opened.sessionId,
      prompt: [TextContent(text: draft)],
    ));
    conversation.finish(result.stopReason);
    // Interrupt action calls agent.cancel(opened.sessionId) while awaiting.
  } finally {
    unsubscribe();
  }
} finally {
  permissions.close();
  await agent.close();
}
```

`SessionInbox`, `PermissionBridge` and `conversation` illustrate the session
layer, not extra requirements on the connection class. The original's
`session/session.ts`, `permissions.ts` and `transcript/reducer.ts` are their
specification. Long-lived applications retain the subscription across turns
and close only when the session closes; this short call site owns one turn.
An open that fails must stop its own process, since the caller has no Agent
handle to close. A `session/new` failure is wrapped with that step before
closing; do not relabel it an initialize failure.

Proposed M0/M1 surface in `example/chord/lib/acp/connection.dart`:

```dart
abstract interface class Agent {
  int get pid;
  InitializeResponse get init;
  Future<AgentExit> get exited;
  String? gone();
  Future<NewSessionResponse> newSession(NewSessionRequest request,
      {CancellationSignal? signal});
  Future<PromptResponse> prompt(PromptRequest request,
      {CancellationSignal? signal});
  Future<void> cancel(String sessionId);
  Future<void> close();
}
```

`openAgent` takes command, env, cwd, required nonthrowing `onTraffic`, required
`onPermission`, explicit capabilities, optional start cancellation and stop
bounds. Runtime owns the cancellation primitive's final spelling; the
minimum needed is an immediate cancelled flag/reason and a once-only
withdrawal notification. This is not a widget or a global notifier.
`init` retains the whole initialize response including `_meta`. `gone()` is
null while connected and a possibly empty stderr tail once disconnected;
empty does not mean connected. `exited` means an observed process exit and
bounded stderr settlement, not merely stdout ending. `close()` is
idempotent and may throw `AgentExitError` when exit cannot be established.

Requests return Futures; updates do not return through `prompt`. Explicit
`cancel` first withdraws this session's waiting permissions, then sends a
notification. Its Future means the notification was sent, not that the
agent complied. The prompt settles with the agent's own response. Cancelling
an optional prompt signal also stops the local wait and asks the agent to
cancel; it must not claim a received `cancelled` stop reason. Check an
already-cancelled signal before sending anything. Retain late wire events
for traffic; the session owns whether a retired turn accepts them.

### Permission ownership and withdrawal

`onPermission(RequestPermissionRequest, CancellationSignal)` returns a
`Future<RequestPermissionResponse>`. The connection owns request correlation
and exactly one wire answer. The session bridge owns a stable local pending
id, raw request, sessionId, toolCall and options, and an idempotent completer.
The widget never receives a transport or writes JSON-RPC.

1. Publish a pending request only after checking withdrawal. Keep options
   in agent order, preserving optionId, name and kind. No invented choices.
2. Selection answers `selected` with that exact optionId. Unknown optionIds
   fail locally. Esc prefers reject_once, then reject_always, otherwise
   `cancelled`; Esc rejects a tool and lets the turn continue.
3. Turn cancellation, the agent's `$/cancel_request`, or closing wins the
   pending request once: client answers `cancelled`, immediately marks the
   request withdrawn, and the bridge removes the inline box and listeners.
   Reject a handler exception with the same fallback, not a hung request.
4. A late click/key/completer result after withdrawal changes neither screen
   nor wire. Two simultaneous requests stay distinct even for one tool id;
   oldest pending is shown first. Answering the first reveals the next.
5. Finishing a prompt is not itself permission withdrawal: requests may
   arrive between turns. Preserve their session identity and use the
   original's held/attention behavior when that screen is implemented.

Pure session state owns turn lifecycle, pending queue, prompt queue, agent
metadata, transcript and errors. Widget-local state owns highlighted option,
request scroll offset, focus and tool fold. A widget gets immutable view
state and dispatch callbacks. Withdrawal also releases the confirmation key
scope; it must never steal the next Enter intended for the prompt.

## I2 — what the reducer and screen need

All rows retain original notification sessionId, complete raw fields and
`_meta`; unknown fields and unknown kinds remain in traffic, without an
invented transcript line. A known partial tool update is not a complete
replacement object. M1 does not assume every content block is plain text.

| Input | What M1 consumes; later data retained |
| --- | --- |
| initialize response | protocolVersion for negotiation; complete agentInfo (name/title/version where supplied), agentCapabilities and authMethods; do not substitute agent-reported identity for the registry's chosen title everywhere. No automatic auth UI or authenticate call. |
| agentCapabilities | promptCapabilities for what content can be sent (M1 sends text); retain loadSession, sessionCapabilities, mcpCapabilities, auth and `_meta` for later gates. Absence is not support. |
| authMethods | On session/new -32000, use nonempty name and description to explain the offered sign-ins. Do not guess authentication from stderr words. |
| session/new response | sessionId for every request and route; seed modes/current mode, configOptions and models when supplied, preserving `_meta`. Modes/options editing is M2. Seed response first, then fold buffered updates in received order. |
| agent_message_chunk | append content to assistant message, respecting messageId when supplied; text goes through Markdown, other content is kept for later renderers. |
| agent_thought_chunk | same append semantics into thought entry; separate from assistant text, folded according to the original transcript view. |
| user_message_chunk | preserve in traffic; the original transcript reducer draws the local submitted prompt and ignores this kind. Do not duplicate the user's prompt. Replay/upstream consumption is later. |
| tool_call / tool_call_update | merge by toolCallId: optional title, kind, status, content, locations, rawInput/rawOutput, `_meta`; partial fields retain existing values. Terminal statuses never regress; update-before-call is valid. Content arrays replace when supplied, rather than append indiscriminately. |
| tool content | text/resource content remains intact; diff carries path, oldText and newText; locations carry path and line. M1 renders edits through Diff and tool output through its content renderer. Permission toolCall is partial too. |
| tool `_meta` | preserve terminal_info, terminal_output, terminal_output_delta, terminal_exit and terminal ids. Whole output replaces, delta appends, exit merges; O1 does not require a client-owned terminal. M3 live output rendering can read these without changing transport. |
| plan | legacy entries (content, priority, status) replace the plan if present; absent entries keep previous plan. This differs from plan_update/plan_removed by id. |
| available_commands_update | retain availableCommands name/description/input hint; missing list preserves previous state. M2 completion reads it. |
| current_mode_update | currentModeId updates observed mode and any matching mode config option; no M1 key to change it. |
| usage_update | retain used, size, cost amount/currency and `_meta` estimation markers. Numeric status/cost is M2 in FEATURES; M1 elapsed time/spinner is locally measured and must not infer usage or USD. |
| session_info_update / config_option_update | keep full payload; later title and model/config reducers consume them. Do not turn metadata into reply text. |
| unknown kinds | nonfatal, retained as raw traffic; M1 reducer leaves state unchanged. Never write schema warnings under the TUI. |
| prompt response | stopReason closes the submitted turn with the original outcome semantics; not an aggregate reply text. All message text already arrived through updates. |

A thousand updates are folded in order into plain state; schedule at most
one pending UI frame. Coalesce redraws, never concatenate/drop unrelated
notifications in the transport. Permission withdrawal remains immediate.

## I3 — failures retain facts, screens retain wording

Use structured `AgentGone(exit?, stderrTail)` and JSON-RPC error code/message/
data/cause; the session wraps the current start step and configured package
pin. Stdout closure without exit must not be presented as a known exit.
These are current source words from `session/start_failure.ts` and
`acp/connection.ts` (older CHD-454 design pin wording has since changed):

| Fact | Screen words after `<agent> did not start: ` |
| --- | --- |
| connection closed, exit unknown | `it closed its connection before answering initialize.` (or `session/new`) |
| exit known | `it exited with code <n> before answering <step>.` |
| signal known | `it was stopped by <signal> before answering <step>.` |
| initialize refusal | `it refused initialize: <agent message>` |
| session/new -32601 | `it does not serve ACP sessions: not an ACP agent, or not at this version.` |
| other coded refusal | `it refused session/new: <agent message>` |
| no code, spawn error, -32000 | original error's own message; -32000 also gets sign-in explanation below |

The start headline is `⏺ <agent> did not start: <words>` in theme.error.
Below it: dim `⎿`, then plain `chord ran <pinned>, the version this chord
pins.`, if configured; `The end of its stderr:` if nonempty; tail lines
indented two cells, preceded by dim `… +N lines` / `… +1 line` if cut. Keep
stderr line indent and wrap under its column. The known zeroclaw -32602
way-on remains keyed to agent identity and code, not string matching.

During a turn, AgentGone's message is exactly `The agent exited.` when the
trimmed tail is empty, otherwise `The agent exited: <tail>`. The original
connection uses this even for an unknown exit; preserve its structured
closed-vs-exited fact for startup wording. Do not invent `Agent disconnected`
as replacement copy. Failed turns draw the error; user interruption draws
`Interrupted by user` and the cancelling status uses `Interrupting…`.

On -32000, retain agent message and initialize authMethods. The way-on is
`chord does not sign agents in. Sign in with <agent>'s own CLI in a terminal,
or set its API key where it offers one.` Present nonempty method names and
descriptions in agent order; no login button is added by CTUI-12. M2 auth
status is separate from the authentication methods list.

There is no automatic initialize/request/prompt timeout or original
`stopped answering` error string in `connection.ts`: waits end on a signal
or connection loss. Stop-ladder time bounds do exist. A silent live agent
is still working, interruptible/quittable, not known dead. If the task wants
an automatic startup or ignored-cancel deadline, the owner must select its
duration, cleanup behavior and copy. Expose cancellation so policy can be
added outside the client; do not quietly invent a timeout in this port.

## I4 — O2, capabilities are visible behavior

O1 is settled as (a): omit fs and terminal and return method-not-found to
such requests. Agents run their own tools. This is independent of terminal
output metadata capability. Option (c) would additionally require real fs
access policy plus terminal create/output/wait/kill/release lifetimes and
screen wiring; it is not a dormant M0 handler.

These effects are evidenced by current `acp/connection.ts`,
`docs/agent-capabilities.md`, CHD-629's notices design and fake-agent
scenarios; they are per adapter, not promises about all agents:

| Declaration | Declared | Omitted | Proposed M0/M1 |
| --- | --- | --- | --- |
| elicitation.form / elicitation.url | Supported agents may request form or URL interactions, requiring a cancellable UI and completion routing. | No general reply-text fallback is established. An unsupported unsolicited request must not hang; cancel safely. | Omit both until M3; call out reduced agent functionality, not equivalent fallback. |
| plan: {} | Codex sends plans by id via plan_update and plan_removed (markdown or file plan); legacy plan entries are a different shape. | Codex sends plan as reply text; adapters may still send legacy plan entries. | Omit unless owner brings id-based plan reducer/rendering into M1. M1 still consumes legacy plan. |
| session.compaction: {} | Claude/Codex send structured compaction updates and summary chunks. | Their fallback is a tool call, without the summary. | Omit until M3; retain fallback tool calls. |
| session.notices: {} | Claude/Codex move eligible reply-text messages to notice. Claude additionally drops info messages. | They retain reply-text fallback, including messages otherwise dropped. | Omit until notice entries are drawn. FEATURES places notifications in M3. |
| subagents: {} | Claude/Codex send separately identified subagent sessions and updates requiring routing and work views. | Claude stamps child work into parent under adapter `_meta`; Codex sends none of that work. | Omit until M3; no made-up nested UI in M1. |
| _meta.terminal_output_delta: true | Claude emits live output metadata; droid instead returns whole text output for this declaration. | Claude returns text blocks. droid/pi may send deltas under terminal_output, whose original interpretation remains whole-output replacement. | Omit until live output M3. Preserve metadata already sent, no per-agent correction. |
| fs / terminal | Agents may delegate files/processes to the client. | Original agents use their own tools. | Omit, owner settled O1(a). |

Proposed capability object is empty for M0/M1; this is a staged difference
from the original, **for the owner to confirm as O2**, not authorization to
hide declared updates. Alternative: bring each corresponding UI forward and
then declare it. In particular, `plan: {}` is not justified solely by M1's
word “Plan.” Keep cancellation-only fallback for unsolicited cursor/grok plan
requests even when no plan UI exists: original `plans.ts` notes that cursor
reads method-not-found as accepted. No request is accepted implicitly.

## Screen contract and keys

CTUI-12 draws nothing new; no widget screenshots or terminal run are claimed.
For consuming M1 tasks, these are excerpts positioned in a full 120x40 or
80x24 screen, with unshown transcript rows blank. Header/prompt/status remain
the original's; these sketches do not prescribe a new header or status copy.
Styles: body plain, hints/rules/thought text dim, focused permission border
and marker theme.focus, inactive border theme.border, error theme.error,
diff additions/removals theme.diff. No user text is interpreted as controls.

At **120x40**, empty/focused and streaming/overflow states respectively:

```text
[transcript: empty; available rows stay blank]
[prompt: focused, draft empty, cursor inverse]
[status: idle; no fabricated usage]

[transcript: assistant Markdown chunks, tool/diff rows; thoughts folded]
── ↓ 12 lines below · end to jump to the bottom ──────────────────────────
[prompt: focused draft retained while streaming]
[status: spinner and elapsed time, derived from turn state]
```

At **80x24**, the same state transitions use fewer transcript rows:

```text
[transcript: empty]
[prompt: focused, empty]
[status: idle]

[assistant Markdown wraps to inner width; tool paths/diffs wrap]
── ↓ 12 lines below · end to jump to the bottom ───────────────
[prompt: focused draft retained]
[status: spinner and elapsed time]
```

Waiting/focused permission at **120x40**, request short enough to fit:

```text
[preceding transcript, remaining rows]
╭────────────────────────────────────────────────────────────────────────╮
│ Write notes.txt                                                        │
│   content: notes                                                       │
│                                                                        │
│ Do you want to proceed?                                                │
│ ❯ 1. Allow once                                                        │
│   2. Deny                                                              │
│                                                                        │
│ Esc to reject                                                          │
╰────────────────────────────────────────────────────────────────────────╯
[prompt draft retained below; status awaiting permission]
```

At **80x24**, overflowing/narrow permission (agent's actual labels replace
these example labels); the request gets at most half the window height and
shrinks before answers do. The title's first row is pinned, its continuation
scrolls with request rows. This follows CHD-246 and current permission.ts:

```text
╭──────────────────────────────────────────────────────────────────────────────╮
│ Write notes.txt                                                              │
│   content: first wrapped request rows                                         │
│   more proposed content                                                      │
│ ── ↓ 37 lines below · pagedown to scroll ──────────────────────────────────── │
│                                                                              │
│ Do you want to proceed?                                                      │
│ ❯ 1. Allow once                                                              │
│   2. Deny                                                                   │
│                                                                              │
│ Esc to reject                                                                │
╰──────────────────────────────────────────────────────────────────────────────╯
[prompt draft below; transcript yields space first]
```

At 120x40 with an overflowing request the same box has more request rows,
not extra options; the rules remain dim. At both sizes, moving focus away
keeps the choice/scroll position and removes the active marker. Withdrawal
removes the whole box, activates the next waiting request or restores the
prompt. An answered request produces the original `Allowed <title> ·
<option.name>` or `Rejected <title>` transcript outcome, not a second ask.

Error at **120x40**:

```text
⏺ Agent did not start: it exited with code 1 before answering initialize.
  ⎿  The end of its stderr:
       an agent diagnostic
[prompt/start-page recovery is owned by the M1 window]
```

Error at **80x24** (long diagnostics wrap in place):

```text
⏺ Agent did not start: it closed its connection before answering session/new.
  ⎿  The end of its stderr:
       a long diagnostic wraps under this column, preserving its own indent
       across the available inner width
```

A live silent/ignored-cancel state has no error box at either size; keep the
transcript/draft and `Interrupting…` until completion, failure or quit. Empty
permission options invent no allow; Esc still cancels the request. Very
small heights/many options need the original short-window rules in the
permission screen task, not a transport-level truncation.

Every consumer action binds through Actions and appears in KeyHelp/the
shortcuts panel; the client itself binds none:

| Scope | Keys | Action / description |
| --- | --- | --- |
| Chat | Enter | Submit prompt |
| Chat | Shift+Enter, Alt+Enter, Ctrl+J, Ctrl+Enter | Insert newline |
| Chat, working turn | Esc | Interrupt turn (agent.cancel) |
| Confirmation | 1–9 | Choose numbered permission option |
| Confirmation | Up/Down, k/j | Previous/next permission option |
| Confirmation | Enter | Choose highlighted option |
| Confirmation | Esc | Reject permission (takes precedence over Chat cancel) |
| Scroll, request overflowing | PageUp/PageDown, shifted twins | Scroll request one page |
| Scroll | Shift+Up/Shift+Down | Scroll one line |
| Scroll | Home/End, shifted twins | Scroll to top/bottom; request owns these while waiting |
| Chat, empty draft | ? | Show shortcuts |
| Global | Ctrl+C twice; Ctrl+D under original quit rules | Quit chord; session owns bounded close |

M2 adds mode/model/config mutations, auth status, load/resume/list/fork/title
requests, steering and headless/stdio serving; retain complete init and
session responses now so gating needs no transport redesign. M3 adds
elicitation handlers and completion, cursor/grok plan handlers, id-based
plans, compaction/notices/subagent reducers, and delta output UI, declaring
each capability only with its consumer. M4 adds child session routing,
permissions by exact child id, cancel with known descendant ids, relays and
host/upstream folds. These extend request methods, handlers and routing;
they do not replace traffic ingress or move ACP into framework lib/.

## Checks the shipping tasks need

CTUI-13 fake-only scenarios should prove update-before-newSession response,
update-after-prompt response, chunk ordering, tool partial/update-before-call,
permission selection/rejection/withdrawal/late answer, unknown notification
retention, initialize/new failures including stdout-close without exit, and
capability-specific fallback. Read the original fixture scenario names
rather than invent new scenarios under ../chord. Permission/transcript tasks
check both 120x40 and 80x24 with the framework tester; no real model or agent.
Package trials are the framework/runtime architects' evidence; this draft
makes no package claim and writes no protocol implementation.
