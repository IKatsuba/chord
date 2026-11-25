# CTUI-15: the session and transcript reducer

The design the ship team builds. How it was reached is in
`docs/design/evidence/CTUI-15/drafts/` (the brief and the framework,
interface and runtime drafts) and runtime's evidence in
`docs/design/evidence/CTUI-15/runtime/` (traffic captures from the original's
fake run with no client capabilities, and `fold_cost.dart`). Where this file
and a draft disagree, this file wins. The decisions are in
`docs/decisions.md`, under `CTUI-15:`.

## What it is for

chord's session layer for M1, as plain Dart with no widget in it: open a
session on CTUI-12's client, send prompts one turn at a time with a queue
behind the running one, cancel, answer permissions, hear the agent's updates
through the one ingress, and fold all of it into the transcript state that
CTUI-16 (transcript), CTUI-17 (prompt), CTUI-18 (permission) and CTUI-19
(plan, status) draw.

The original is the specification: `../chord/src/session/session.ts`,
`conversation.ts`, `permissions.ts`, `permission_review.ts`,
`agent_state.ts`, `enrich.ts`, `enrichers.ts`, `terminal_text.ts`,
`transcript/` and `src/ui/app/state.ts`, with their tests under
`tests/session/`. Everything below is cut from them; a difference from them
is named where it is made.

## Files

Port paths under `example/chord/`, named after the original's.

| File | Original | Holds |
| --- | --- | --- |
| `lib/session/transcript/types.dart` | `transcript/types.ts` | entries, `ToolCall`, `Terminal`, `TurnState`, `PermissionWait`, `TurnResult`, `Transcript`, `TranscriptAction` |
| `lib/session/transcript/text_run.dart` | none (see "Text that grows") | `TextRun` |
| `lib/session/transcript/entries.dart` | `transcript/entries.ts` | `appended`, `replacedAt`, `lastReplaced` |
| `lib/session/transcript/messages.dart` | `transcript/messages.ts` | `textOf`, `appendText` |
| `lib/session/transcript/tools.dart` | `transcript/tools.ts` | `mergeToolCall`, status order; `foldTerminals` in unit 10 |
| `lib/session/transcript/permissions.dart` | `transcript/permissions.ts` | `permissionRequested`, `permissionSettled` |
| `lib/session/transcript/turn.dart` | `transcript/turn.ts` | `prompted`, `cancelled`, `settle`, `disconnected` |
| `lib/session/transcript/reducer.dart` | `transcript/reducer.ts` | `reduceTranscript`, `applyUpdate`, the per-update catch |
| `lib/session/agent_state.dart` | `agent_state.ts` | `AgentState`, `stateOf`, `foldUpdate`, `withOptions` |
| `lib/session/permission_review.dart` | `permission_review.ts` | `permissionPresentation` (review and `deadlineAt` from `_meta["chord/permission"]`) |
| `lib/session/enrich.dart` | `enrich.ts` | `Enricher`, `Wire`, `enrich`, `heardFromChord`, `heardFromAgent`, `enricherRelay` |
| `lib/session/enrichers.dart` | `enrichers.ts` | `toolCallFacts`, `codexMcpCall`, `codexGuardianReview`, `rawOutputContent`, `m1Enrichers` |
| `lib/session/inbox.dart` | the closures in `openSession` | `SessionInbox` |
| `lib/session/permissions.dart` | `permissions.ts` | `PermissionBridge`, `PendingPermission`, `rejection` |
| `lib/session/session.dart` | `session.ts` | `Session`, `Turn`, `openSession`, `SessionOpener`, `agentEnv` |
| `lib/session/conversation.dart` | `conversation.ts`, cut to M1 | `Conversation`, `ConversationEvent`, `Delivery` |
| `lib/session/terminal_text.dart` | `terminal_text.ts` | unit 10, after its package trial |
| `lib/ui/app/state.dart` | `ui/app/state.ts`, the M1 slice | `AppState`, `reduceApp`, `ScrollEffect`, `scrollEffectOf` |
| `lib/acp/connection.dart` | `acp/connection.ts` | gains the optional `relay` (CTUI-12 amended) |

Tests at the same paths under `test/`, each the original's file of the same
name carried over for the cases M1 covers, with a line at its top naming the
cases left for later. Helpers: `test/session/transcript/fold.dart`
(`fold(actions)`, `described(transcript)`), `test/session/session_fake.dart`
(`withSession`, `collect`), `test/session/conversation_fake.dart` (a scripted
`Session`). There is no `plans_test.dart`: the original's `plans.ts` is
id-addressed plans, a non-goal; the base `plan` cases sit in
`reducer_test.dart`, as in the original.

## The layers

Three, as the original, so each is tested without the others and later
milestones add members rather than rewrite (M2 swaps a `Session` under one
`Conversation` for clear and resume):

```text
stdout ─ framing ─ relay (enrichers) ─┬─ tap ─ onTraffic ─ record (later), SessionInbox.hear
                                      └─ route ─ answers; onPermission ─ PermissionBridge
Session      one agent, one ACP session: inbox, bridge, prompt → Turn
Conversation turns, queue, turn ids, settle wait; emits ConversationEvents
AppState     reduceApp folds events; reduceTranscript for every transcript action
```

- **The transcript reducer** knows nothing of the other three.
- **`Conversation`** holds no transcript. It only emits events.
- **The window** subscribes, folds with `reduceApp` into one
  `ValueNotifier<AppState>`, and dispatches `send`, `interrupt`, `choose`
  and `reject`.

### Events and actions: one legal boundary

`TranscriptAction` is sealed in `transcript/types.dart`. `ConversationEvent`
is sealed in `conversation.dart` and wraps an action, so the reducer's
library never imports `Conversation` and both hierarchies stay exhaustive:

```dart
// conversation.dart
sealed class ConversationEvent { const ConversationEvent(); }
/// A transcript action, as the reducer folds it.
final class Transcribed extends ConversationEvent { final TranscriptAction action; }
final class Connected extends ConversationEvent { final String sessionId; final AgentState state; }
final class ConnectFailed extends ConversationEvent { final String message; }
final class AgentStateChanged extends ConversationEvent { final AgentState state; }
final class Queued extends ConversationEvent { final String turnId; final String text; final bool afterAnswer; }
/// The person's queued prompts taken back, with their text, oldest first.
final class QueueWithdrawn extends ConversationEvent { final List<QueuedPrompt> prompts; }
final class Gone extends ConversationEvent { final String reason; final List<String> stderrLines; final int stderrCut; }
final class Closing extends ConversationEvent {}
```

`QueueWithdrawn` carries the texts, not only ids, so the prompt can put them
back ahead of the draft (`keys.ts`, `queue.ts`). `Gone` carries CTUI-12's
bounded stderr tail for the screens, beside the transcript's own
`DisconnectedAction`.

## State

### The shape: sealed classes, identity as the change signal

Transcript state is chord's own data, not a wire format, so it is sealed
classes with final fields and `const` constructors. Every `kind` and `type`
of `types.ts` becomes a subtype, and a screen's `switch` is exhaustive. ACP
data inside entries (content blocks, tool content and locations, permission
options, plan entries) stays CTUI-12's read-only views, so every field the
agent sent, `_meta` included, is kept.

- **No `==` overrides.** A reducer returns the identical object for
  anything it did not change, down to the entry, the list and the whole
  state, as the original does. That identity is what everything downstream
  reads:
  - CTUI-1's list: `itemVersion: (i) => (entries[i], expanded)`, a pointer
    compare per measured item each frame.
  - News: `!identical(before.entries, after.entries)`, the original's
    `withNews`.
  - The notifier: it fires only on a new object, so an update that changes
    nothing wakes nothing.
- **Tests compare by value** through `fold.dart`'s `described()`, an
  exhaustive switch: a new kind does not compile until it is described.
- **No `copyWith`.** Each module builds the next object with its
  constructor. Where a type is rebuilt often it gets a named method
  (`Transcript.withEntries`, `withTurn`).
- **No code generation.** `freezed` and `built_value` would bring
  `build_runner` for the very `==` this shape avoids.

### Lists: core `List`, copied on write

Writes go through `entries.dart`'s three writers. Each returns a fresh list
wrapped in `UnmodifiableListView`. Framework tried
`fast_immutable_collections` 12.0.0, `built_collection` 6.0.0 and
`collection` 1.19.1 under `dart compile exe`. None is cheaper on the hot
write, replacing the last entry: 11 µs for a copy at 10 000 entries against
20 µs for FIC's replace (AOT). So none is taken. The other lists in state
(plan, permission waits, queue) follow the same rule.

The budget is the benchmark's (unit 9, AOT): a 16 ms heartbeat stays on time
while the fake's `flood` and 1 000 updates a second fold at 10 000 entries.
If the benchmark misses it, the list's backing changes behind the same three
writers and no reducer changes; that change, with a package, is a new
decision.

### Text that grows: `TextRun`

A literal port of `appendText` (`last.text + chunk`) is quadratic in Dart,
because JavaScript's strings are ropes and Dart's `+` copies. Runtime
measured the fake's `flood` folding in 3 632 ms against 6 ms
(`runtime/fold_cost.txt`). So a reply's and a thought's text is a `TextRun`,
an immutable snapshot over a core `StringBuffer` that its successors share:

```dart
/// Text appended chunk by chunk; each snapshot is immutable and shares the buffer.
final class TextRun {
  static final empty = TextRun._(StringBuffer(), 0);
  /// This text with [more] after it. Appends in place when this is the
  /// buffer's latest snapshot; otherwise copies its own prefix first.
  TextRun plus(String more);
  /// The text, joined once per snapshot and cached.
  String get text;
  int get length;
}
```

- **Cost.** Appending is amortised in the size of the chunk. `text` joins
  at most once per snapshot, which is once per frame for the entry being
  drawn.
- **Old snapshots.** A snapshot taken earlier still reads its own prefix.
  Appending to an old snapshot forks a copy rather than writing into the
  shared buffer.
- **Tests:** old-snapshot reads, a fork, and the flood's size folding within
  a bound.
- **Packages.** None: the core library's `StringBuffer` is the rope. This
  changes how the text is kept, not what it holds; the owner agreed.

### Entries

```dart
final class EntryIdentity { EntryIdentity(); }
sealed class Entry {
  const Entry(this.turnId, {EntryIdentity? identity});
  final String turnId;
  EntryIdentity get identity;
}
final class UserEntry extends Entry { final String text; }
sealed class ChunkEntry extends Entry { final TextRun text; final String? messageId; }
final class AssistantEntry extends ChunkEntry {}
final class ThoughtEntry extends ChunkEntry {}
final class ToolEntry extends Entry { final ToolCall call; }
/// How a permission was answered; a withdrawn one leaves none.
final class PermissionEntry extends Entry {
  final String? title; final acp.PermissionOption? option; final PermissionReview? review;
}
final class CancelledEntry extends Entry {}
/// A turn that ended with a stop reason other than `end_turn`.
final class StoppedEntry extends Entry { final String reason; }
final class ErrorEntry extends Entry { final String message; final int? code; }
final class WarningEntry extends Entry { final String message; }
/// A plan whose every step was completed when its turn settled.
final class FinishedPlanEntry extends Entry { final List<acp.PlanEntry> entries; }
```

#### Stable occurrence identity (CTUI-48 extension)

Main approved this minimal domain seam for selection across reducer revisions.
EntryIdentity is an opaque final class with a nonconst constructor, no payload
fields, no Entry references and no equality override. It is a local occurrence
token, not an agent ID, row index or persistent/serialized identifier. Entry
object identity remains the revision/change signal described above; the stable
occurrence token does not replace it for itemVersion or no-op detection.

Every concrete Entry constructor forwards the optional typed identity named
parameter while keeping existing const calls valid. The getter returns an
explicit token directly. An unissued const/raw fixture entry lazily receives a
token from a static weak Expando<EntryIdentity> keyed by that Entry; it never
returns the Entry itself as an ID. The weak fallback and tokens create no strong
historical Entry cache or back-reference chain.

Occurrence issuance belongs to entries.dart's existing writers:

- appended clones each newly appended occurrence with a fresh EntryIdentity,
  even when the incoming object is canonical const, already carries a token,
  was appended before or was removed and appended again. Appending one canonical
  const instance twice must produce distinct occurrence tokens. Entries already
  in the list remain the identical objects.
- replacedAt and lastReplaced represent a replacement of the same logical slot.
  Clone the incoming data with that old slot's token, rather than its incoming
  token. The next data object changes, but its occurrence identity survives.
- Use an exhaustive kind-preserving identity-only clone; preserve every current
  field/value, including nullable and num? agent values, without coercion or
  loss. It stores no reference to the old Entry. All current reducer writes,
  including noted command updates added after M1, use these writers rather
  than bypassing occurrence issuance/preservation.

Unchanged reducer actions still return identical state/list/Entry objects;
perform existing no-op checks before a write. Tests for newly written entries
compare described content and the required token relationship rather than
requiring the incoming object itself. Untouched-object identity checks remain.
This adds no general copyWith, widget state or identity inferred from contents.

Raw const Transcript construction does not normalize occurrence identity. If
it contains one canonical Entry twice, the fallback token is shared and the
selection delegate rejects the duplicate IDs. Do not silently reinterpret those
ambiguous occurrences or break const Transcript constructors to normalize them.
Fixtures needing distinct occurrences use appended or explicit distinct tokens.
Explicitly reused tokens are also rejected by the selection provider.

Tests cover fresh append IDs for duplicate/reused/canonical const inputs and
remove/reappend, same-slot token preservation across every current replacement
kind, explicit-token and weak-fallback stability, duplicate raw-transcript
rejection, unchanged payload/num? values and no-op object identity. Retention
checks must show that tokens/fallback bookkeeping retain no old Entry or
replacement-history chain; UI source caches keep only current revisions and
release removed entries. No new dependency is needed for opaque domain tokens.

`StoppedEntry` and `FinishedPlanEntry` were not in the brief's subset.
`turn.ts`'s `settle` writes them for M1's own inputs (`turn.ts:203-217,
250-275`), so leaving them out would have been a difference from the
original.

Left out, each a new subtype later with no existing one changed:
- `message`, `agent_message`, `subagent`, `item_ended` (subagents);
- `compaction`, `notice`, `elicitation` (M3);
- `shell` (bash mode);
- `report`, `note`, `team`, `team_part`, `left_open`, `monitors_left`,
  `forked`, `self_started` (commands, teams, monitors, records, steering).

### Tool calls and terminals

```dart
final class ToolCall {
  final String id;
  final String? title, kind, status;          // status only moves forward
  final List<acp.ToolCallLocation>? locations;
  final List<acp.ToolCallContent>? content;   // text, diffs, terminal refs, as sent
  final Object? rawInput, rawOutput;
  final String? guardian;                     // codexGuardianReview
  final McpCall? mcp;                         // codexMcpCall: server?, tool, input
  final PermissionReview? review;             // kept after the box closes
  final List<Terminal>? terminals;            // unit 10
}

final class Terminal {                        // types.ts Terminal
  final String id;
  final String output;          // as a screen would leave it; last OUTPUT_LIMIT (30 000) chars
  final TerminalCursor? cursor;
  final OpenEscape? escape;     // an escape the output so far ends inside
  final String? cwd;
  final bool exited;
  final num? exitCode;          // the agent's number, unchanged
  final String? signal;
  final bool truncated;
}
```

The merge is `tools.ts`'s, as written:
- a field an update leaves out is kept;
- supplied content replaces what was there, `[]` included;
- an update before its call is accepted;
- a finished status never moves back.

`foldTerminals` reads `_meta.terminal_info`, `terminal_output_delta`,
`terminal_output` and `terminal_exit` whatever was declared, as the original
(owner, Q2). Left out: `plan` (cursor and grok plans), `chord` (chord's MCP),
`asked` (elicitation), `cut` (steering).

### The turn, permission waits, results

```dart
sealed class TurnState {}
final class Idle extends TurnState {}
final class Working extends TurnState { final String turnId; final int since; }
final class AwaitingPermission extends TurnState {
  final String turnId; final int since;
  final List<PermissionWait> permissions;    // oldest first; the first is shown
  final bool between;                        // asked, or left open, with no turn running
}
final class Cancelling extends TurnState { final String turnId; final int since; final int cancelledAt; }

final class PermissionWait {
  final String id;                           // the bridge's, not the toolCallId
  final String? toolCallId, title, kind;
  final List<acp.ToolCallLocation>? locations;
  final List<acp.ToolCallContent>? content;
  final Object? rawInput;
  final List<acp.PermissionOption> options;
  final PermissionReview? review;            // _meta["chord/permission"].review
  final num? deadlineAt;                     // the agent's; never computed by chord
  final int? at;                             // when asked, for a request with a deadline
}
sealed class PermissionAnswer {}             // Chosen(optionId) | Rejected | Withdrawn

sealed class TurnResult {}
final class TurnAnswered extends TurnResult { final String stopReason; bool get cancelled; }
final class TurnFailed extends TurnResult { final String message; final int? code; }
```

The review and deadline are generic permission metadata that CTUI-18 must
draw (the reason visible at 80x24), so they are carried through
`permissionPresentation`, as the original's `waitFor` spreads them. This is
apart from Codex's Guardian tool. Left out: `cycle`, `subagentId`, `detail`,
`save`, `usage` and `signIn` on results.

### The transcript and the app

```dart
final class Transcript {
  final List<Entry> entries;
  final List<acp.PlanEntry> plan;      // each `plan` update replaces it; [] clears
  final TurnState turn;
  final Usage? usage;                  // usage_update: used, size as the agent says; no cost, no estimate
  final String? mode;                  // current_mode_update
}

final class AppState {
  final StartState start;              // CTUI-13's phases; gone set by `Gone`
  final AgentState agent;              // read-only: configOptions, modes, models as reported
  final Transcript transcript;
  final List<QueuedPrompt> queue;      // mirror of the conversation's, oldest first
}
AppState reduceApp(AppState state, ConversationEvent event);
ScrollEffect scrollEffectOf(AppState before, AppState after, ConversationEvent event);
```

**Status facts.** CTUI-19's model, effort, mode and context are the facts
the agent reports, read-only (owner, Q3):
- `AgentState` (`agent_state.ts`) is seeded from `session/new`'s answer and
  folded by `foldUpdate` on `config_option_update` and
  `current_mode_update`. The session keeps it, and `Conversation` emits
  `AgentStateChanged` after those kinds (the original's `STATE_UPDATES`).
- `Transcript.mode` comes from `current_mode_update`, as the original's
  reducer keeps it.
- `usage` comes from `usage_update`'s `used` and `size`.

There are no setters, no `windowFromModel` estimate and no cost.
`foldUpdate`'s `available_commands_update` branch comes with it, but no M1
screen reads `commands`; the slash menu is M2.

**Scroll.** Scroll is the framework's `ScrollController`, not state.
`scrollEffectOf` is the original's rule as a pure function: `bottom` on a
prompt, `news` when the entries list is new, else `none`.

### Actions

```dart
sealed class TranscriptAction { final String turnId; }
// PromptAction(text, at) · UpdateAction(update, at?) · PermissionRequestedAction(wait, at?, between)
// PermissionSettledAction(id, answer) · CancelAction(at) · DisconnectedAction(at?)
// ResultAction(result) · FailedAction(message) · WarnedAction(message)
```

Each is one `type` of `types.ts`, without its fields for messages, teams,
steering and subagents (`from`, `team`, `into`, `subagentId`, `unasked`).

`DisconnectedAction` changes nothing in M1: in the original it only ends
running subagents (`turn.ts:136-156`). It is emitted where the original
emits it, so M3 fills in `disconnected()` and no caller changes.

## The reducer

One module per kind, plain functions from `Transcript` to `Transcript`:

```dart
Transcript reduceTranscript(Transcript state, TranscriptAction action) => switch (action) { … };

Transcript _update(Transcript state, UpdateAction action) {
  try {
    return applyUpdate(state, action.turnId, action.update);
  } on Object {
    return state;          // updates are not checked on arrival (CTUI-12)
  }
}
```

- **`applyUpdate`** handles these kinds:
  - `agent_message_chunk` and `agent_thought_chunk`: `appendText`. A new
    `messageId`, or a tool or thought in between, starts a new block.
  - `tool_call` and `tool_call_update`: `mergeToolCall`.
  - `plan`: replaces the live plan.
  - `usage_update` and `current_mode_update`, for the status facts, as the
    original's reducer.
  - Anything else is `state`, identical.
- **`settle`** runs at a result:
  - `cancelled` adds a `CancelledEntry`.
  - Another non-`end_turn` stop reason adds a `StoppedEntry`.
  - A failure adds an `ErrorEntry`.
  - A live plan whose every step is completed moves into a
    `FinishedPlanEntry`.
- **The per-update catch** is in the reducer, so "one malformed update draws
  nothing and the next still draws" is a pure test. Every module builds its
  next state before returning it, so a throw cannot leave a partial write.
- **Where the original calls `subagents.ts`**, M1 writes the branch it takes
  with no subagents, with a one-line comment. There are five places:
  - `taskWaits` in `prompted`, `settle` and `permissionRequested`;
  - `endRunning` in `settle`;
  - `disconnected`, which returns `state`;
  - `permissionSettled`, which always appends to the session's entries;
  - `reviewedIn`/`changeSubagent`, reduced to the session's own review.

  M3 adds `subagents.dart` and changes those five places, nothing else.

## Enrichers on the transport

The owner chose the original's place (Q1, option b). `openAgent` and
`connectAgent` take an optional relay; CTUI-12's design is amended to match:

```dart
/// Turns each message either way into the messages the rest of chord reads.
abstract interface class Relay {
  List<Map<String, Object?>> fromAgent(Map<String, Object?> message);
  List<Map<String, Object?>> fromChord(Map<String, Object?> message);
}
Future<Agent> openAgent({…, Relay? relay});
```

- **From the agent.** In the connection, each decoded message goes through
  `relay.fromAgent`, then each result is tapped and routed in order. The
  tap, the inbox, the dispatcher and `onPermission` therefore see enriched
  messages, and a permission request's tool title is filled in before the
  bridge sees it.
- **From chord.** In the writer, `relay.fromChord` runs before the tap and
  the bytes, so `Wire.asked` knows what an answer answers.
- **Fail open.** A relay call that throws is caught per message, and the
  raw message goes on in its place. A test holds that.
- **No relay** means today's behaviour, and every CTUI-12 test stands.

`enricherRelay(chain)` holds one `Wire` per connection. In M1, `Wire` keeps
`asked` and each session's `tools` (`ToolFacts`: title, kind, own content).
`m1Enrichers` runs in the original's order: `toolCallFacts`, `codexMcpCall`,
`codexGuardianReview`, `rawOutputContent`. Each enricher:
- builds a new map and never writes the one it was handed;
- marks what it filled under `_meta["chord/filled"]`.

The other ten join the list with their tasks:
- `subagentShape` and `claudeSubagentName` with subagents;
- `modeReadBack` with mode setting in M2;
- `costFromTokens` and `windowFromModel` with costs;
- the five question enrichers with elicitation.

## The inbox

`SessionInbox` (`inbox.dart`) is pure: no `Agent`, no timer. It stands for
the closures in `openSession`.

- **`hear(traffic)`** keeps only agent messages that are `session/update`
  notifications as `updateIn` reads one; an unknown update kind passes.
- **Before `open`**, every update is held in `early`, whatever its session
  id.
- **`open(sessionId, answer)`:**
  1. seeds `stateOf(answer)` first;
  2. routes `early` in arrival order;
  3. routes live updates from then on.

  A buffered `current_mode_update` or `config_option_update` therefore
  lands after the answer and overrides it (a test).
- **Routing** is exact: `sessionId == id`. An update for another session is
  dropped. M3 replaces that one comparison with `routed` from
  `subagents.dart`.
- **Before the first subscriber**, routed updates are held. The first
  subscriber gets them in order, synchronously inside `subscribe`, then
  live ones. Later subscribers get only live ones.
- **`close()`** drops everything. Neither buffer is bounded, as in the
  original.

## Session

```dart
typedef SessionOpener = Future<Agent> Function({
  required Object command, Map<String, String>? env, required String cwd,
  required void Function(Traffic) onTraffic,
  required Future<acp.RequestPermissionResponse> Function(
      acp.RequestPermissionRequest, CancellationToken) onPermission,
  Relay? relay, CancellationToken? cancellationToken,
});

abstract interface class Session {
  String get agent; String get cwd; String get id;
  AgentState get state;                          // seeded from the answer
  PermissionBridge get permissions;
  Future<void> get exited;
  String? gone();
  void Function() subscribe(void Function(acp.SessionUpdate update) listener);
  Turn prompt(String text);
  Future<void> cancel();                         // agent.cancel(id)
  Future<void> close();
}
final class Turn {
  final String id;
  final Future<TurnResult> result;               // never throws
  final Future<void> Function() cancel;
}
Future<Session> openSession({required String agent, required Object command,
  Map<String, String>? env, required String cwd, SessionOpener open = openAgent,
  void Function(Traffic)? onTraffic, CancellationToken? cancellationToken});
```

- **Members.** M1 keeps ten of the original's forty. The rest are later
  members on the same object; none changes these.
  - `withdraw()` has no M1 consumer, since chord's own asks are out, so it
    is not ported.
  - `prompt`'s attachments, mentions, links and resources are optional
    parameters added later.
  - The subscriber's `subagentId` arrives in M3 as an optional positional
    parameter.
- **`SessionOpener`** replaces CTUI-13's `AgentOpener`, which takes no env
  and no relay. `openAgent` matches it, and so does the fake harness's
  adapter. `StartConnection` moves to it in the unit that first opens a
  session.
- **The traffic hook.** `onTraffic` is forwarded after the inbox, so the
  harness's recorder sits beside the session's own ingress.
- **`agentEnv`** is the original's: `CLAUDE_CODE_ENABLE_TODO_TOOLS=1` unless
  the person's environment sets it. Without it Claude never sends a `plan`.
  Tests cover the variable absent and set by the person.
- **The result never throws.** The agent's answer gives `TurnAnswered`. A
  JSON-RPC error gives `TurnFailed(message, code)`. `AgentGone` gives
  `TurnFailed('The agent exited.' | 'The agent exited: <tail>')`. Nothing
  invents a stop reason.
- **Cancelling is always `agent.cancel(sessionId)`**, never `prompt`'s
  token. CTUI-12 defines that token as dropping the agent's answer, and the
  turn must end `cancelled` in the agent's own words.

## Conversation: turns, queue, cancel, exit

The original's rules (`conversation.ts`), cut to the person's prompts.
`Conversation` reads time through an injected clock and waits through
`Timer`, so `fake_async` drives every case.

- **`send(text)`** returns false before the session is up and while closing.
  Otherwise the prompt plays at once when idle (no turn, no settle wait, an
  empty queue, no request waiting between turns). If not, it is queued, and
  `Queued` is emitted with `afterAnswer` when a request between turns holds
  it.
- **Play** emits `prompt`, calls `session.prompt`, and awaits the result.
- **After the answer**, with prompts queued, the turn stays drawn as running
  until the agent has been quiet for 1 000 ms (`QUIET_MS`), and at most
  5 000 ms (`SETTLE_LIMIT_MS`). Then comes the result, then the next queued
  prompt. With nothing queued, the result is emitted at once.
- **Stamping**: an update folds under `turn?.id ?? lastTurnId`, and
  `lastTurnId` starts as `'session'`. This is the original's bounded
  heuristic, and it inherits the original's limit: updates carry no prompt
  id. A late update that comes after the 5 s cap, or after the person sends
  again with nothing queued, folds under the new turn. The original's
  comment above `#quieten` says the same. Scripted tests hold both cases;
  nothing promises exact attribution.
- **`interrupt()`** (Esc while busy, with no permission on screen):
  1. withdraws the person's queue (`QueueWithdrawn` with the texts);
  2. if the turn is running: emits `cancel` (`Cancelling`, drawn
     `Interrupting…`), then `session.cancel()`;
  3. if the turn is in its settle wait: aborts the wait and emits the
     result at once, with no `session/cancel`.
- **`cancelPrompt(turnId)`** takes back one queued prompt, or stops the
  running one and leaves the queue alone.
- **`choose(id, optionId)` and `reject(id)`** emit `permission_settled` and
  answer the bridge. `reject` picks `reject_once`, else `reject_always`,
  else `cancelled`. Esc on a shown permission is `reject`, not `interrupt`
  (`state.ts`). An answered request between turns releases the queue after
  the same quiet wait.
- **A cancel the agent ignores** stays `Interrupting…` with no timer, as the
  original and CTUI-12. Esc again sends `session/cancel` again and changes
  no state. Quitting closes.
- **The agent going** (`session.exited`, not while closing):
  - `Transcribed(DisconnectedAction)` and `Gone(tail)` are emitted.
  - A running turn fails with `The agent exited…`, as one `ErrorEntry`,
    whichever of the result and the exit is heard first.
  - Each queued prompt then plays and fails the same way.
  - Send stays enabled after an idle exit, as the original's `canSend`. The
    next prompt is drawn and fails at once with the same words. Interface's
    disabled send was rejected for differing from the original.
- **`close()`** emits `Closing`, aborts the settle wait, and calls
  `session.close()` (CTUI-12's barrier and ladder). Nothing is emitted
  after it starts.
- **Errors in listeners.** An event listener that throws does not stop the
  others; the error goes to the zone. A throwing update is the reducer's
  catch, not the conversation's.

## What the screens read and dispatch

From the interface draft, which has the drawings at 120x40 and 80x24 and
the original's file and line for each:

| State | Read | Drawn (original's words) | Intents |
| --- | --- | --- | --- |
| idle, ready | `Idle`, `start.connected` | empty transcript, focused prompt | `send` |
| working | `Working.since` | `››› Working… (12s · esc to interrupt)` | `send` queues; `interrupt` |
| permission in turn | `AwaitingPermission`, first wait | `››› Waiting for permission… (12s)`, box with options, review reason | `choose`, `reject` (Esc) |
| permission between turns | `between: true` | box unmarked; `● permission asked between turns · ctrl+x a to answer` | attend (focus only), `choose`, `reject` |
| interrupting | `Cancelling` | `››› Interrupting… (12s)` | Esc again |
| cancelled | `CancelledEntry` | `⎿ Interrupted by user`; withdrawn texts back in the prompt | `send` |
| stopped, failed | `StoppedEntry`, `ErrorEntry` | `Stopped: <reason>`; the agent's message | `send` |
| gone | `Gone`, `ErrorEntry` if mid-turn | `The agent exited.` / `The agent exited: <tail>` | `send` (fails, as the original) |

The spinner is the original's three `›` marks (`Status.tsx:23-45`), not the
board's older `✻`. Elapsed time is formatted by the screens from `since` and
a UI tick; the reducer stores timestamps, never frames. Keys belong to the
screens' tasks and are bound through `Actions`. The interface draft's key
table is their starting point.

## Units for ship

Each lands with tests that fail without it, with `dart analyze`,
`dart format` and both suites clean.

| # | Unit | Files | Tests | Needs |
| --- | --- | --- | --- | --- |
| 1 | Transcript core | `types.dart`, `text_run.dart`, `entries.dart`, `messages.dart`, `turn.dart`, `reducer.dart` (prompt, chunks, plan, status facts, cancel, result, failed, warned, catch), `fold.dart` | `reducer_test`, `entries_test`, `text_run_test` (flood size within a bound) | — |
| 2 | Tool calls | `tools.dart` (merge, status order; `mcp`, `guardian`, `review` fields) | `tools_test` | 1 |
| 3 | Permissions in the transcript | `transcript/permissions.dart`, `permission_review.dart` | `transcript/permissions_test`, `permission_review_test` | 1 |
| 4 | The relay | `connection.dart`'s `relay` (both directions, fail open), CTUI-12 tests untouched | new connection tests | — |
| 5 | Enrichers | `enrich.dart`, `enrichers.dart` (the four) | `enrich_test`, `enrichers_test` subsets | 4 |
| 6 | Inbox and bridge | `inbox.dart`, `permissions.dart`, `agent_state.dart` | `inbox_test`, `permissions_test` | 3 |
| 7 | Session | `session.dart`, `SessionOpener`, `agentEnv`; the harness's `onTraffic`; `StartConnection` on `SessionOpener` | `session_test`, `session_updates_test` on the fake; memory cases | 5, 6 |
| 8 | Conversation and app state | `conversation.dart`, `ui/app/state.dart` | `conversation_test` (fake and scripted, `fake_async`), `state_test` | 1-3, 7 |
| 9 | Benchmark | `benchmark/acp_updates.dart` folding through 8 | heartbeat lateness, fold per update, Esc-to-cancelled during `flood`, heap at 10 000 entries, reported | 8 |
| 10 | Terminal output | package trial for the VT parser first (`xterm` and others, recorded in `docs/decisions.md`; a misfit goes to the owner); then `terminal_text.dart`, `Terminal`, `foldTerminals` | `terminal_text_test`, the terminal cases of `tools_test`, `session_updates_test` | 2 |

Units 1, 4 and 10's trial can start in parallel. CTUI-16 to 19 build on
unit 8.

## Tests

No test reaches a real model, agent or terminal.

- **Pure:** the reducer, `TextRun`, entries, tools, permissions, the inbox,
  enrichers. Each adds the port's identity claims: the identical state for
  an action that changes nothing; an untouched entry is identical; a
  malformed update (a `tool_call` without `toolCallId`, `entries` as a
  string) leaves the state identical and the next update draws.
- **Scripted** `Session` with `fake_async`:
  - the queue and its settle wait: nothing at 999 ms, plays at 1 000 ms;
    a chatty agent plays at 5 000 ms;
  - Esc during the wait;
  - an ignored cancel;
  - exit mid-turn, with result and exit in both orders, reducing to equal
    states;
  - an update after the cap, and after an immediate resend;
  - a throwing listener;
  - a request left open between turns.
- **Memory** (`connectAgent` over exact bytes), for what no fake scenario
  plays:
  - an update before `session/new` answers;
  - an update for another session;
  - exit between turns;
  - a request after `session/cancel` went;
  - one read holding `update, answer, update` against three reads, giving
    equal transcripts;
  - with a permission waiting, its `cancelled` answer before `session/cancel`
    on the wire;
  - a throwing relay.
- **The original's fake**, through CTUI-13's harness, tagged `fake_agent`.
  Each scenario and what it covers:

  | Scenario | Covers |
  | --- | --- |
  | `text` | the hold until the first subscriber |
  | `thought` | thoughts apart from the reply |
  | `todos` | the plan, with `agentEnv` |
  | `tools`, `calls`, `edit`, `rewrite` | tool calls, content, diffs |
  | `markdown`, `long` | long replies through the fold |
  | `bash`, `bashcut` | command output as text; cut calls |
  | `shell` | output under `_meta`, unit 10 |
  | `permission`, `twins`, `overlapask` | answer, reject, withdraw; two at once |
  | `leftask`, `mainbetween` | a request outliving its turn |
  | `slow` then cancel, `cancels` | interrupt; stray cancels |
  | `ignorescancel` | a cancel ignored, then close |
  | `error`, `turnfailed` | failed turns, the session goes on |
  | `crash` | exit mid-turn |
  | `late` then `text` | trailing updates, the settle wait |
  | `unknown` | unknown kinds and notifications |
  | `flood` | the benchmark |

  No scenario is added to the original.

## Out, and the seam each uses

| Out | Seam |
| --- | --- |
| records, resume, `session/load`, fork | members on `Session`; `entries.dart`'s writers take an in-place batch for a resumed past (`inBatch`) |
| subagents | the five reducer sites; the inbox's one comparison; the subscriber's optional `subagentId`; `subagentShape` and `claudeSubagentName` |
| models, modes and options as setters; steering; bash mode | members on `Session` and `Conversation`; `AgentState` already read |
| costs, estimates | `Usage.cost`, `costFromTokens`, `windowFromModel` |
| notices, compaction, elicitation, id-addressed plans | new entry subtypes, actions and enrichers |
| chord's MCP, teams, monitors | new entries, `ToolCall.chord` |
| declaring `_meta.terminal_output_delta` | the M3 task, on unit 10's fold |

## The critic's findings, resolved

1. **The event hierarchy cannot compile** across two libraries: accepted.
   Events wrap actions (`Transcribed`).
2. **The hot path**: accepted. `TextRun` for text. The list copy stays,
   with an AOT budget in the benchmark; runtime's 51 µs JIT figure is not
   comparable evidence for a persistent list.
3. **Review and deadline dropped**: accepted. They are carried through
   `permissionPresentation`.
4. **Enricher placement**: taken to the owner, who chose the relay. CTUI-12
   is amended.
5. **Terminal output and the extra enrichers**: taken to the owner, who
   chose the fold now (unit 10, with its package trial) and both
   enrichers, with `ToolCall.mcp` and `guardian`.
6. **Gone state**: accepted. The `Gone` event and the original's send rule;
   interface's disabled send is rejected for differing from the original.
7. **Stamping overstated**: accepted. The bounded heuristic is stated as
   the original's, with tests past the cap.
8. **The opener cannot take env**: accepted. `SessionOpener` with env and
   relay; `withdraw()` trimmed.
9. **Seeding the answer**: accepted. `open(id, answer)` seeds `AgentState`,
   because the owner took read-only status facts.
10. **Ownership**: accepted. One DAG (the units above); `ui/app/state.dart`
    in CTUI-15 (unit 8); `Conversation` emits only; the catch is in the
    reducer; no `plans_test`.

Nothing the critic raised was rejected.

From the drafts, settled by the lead:
- Runtime's port of `routed` with an empty tree is not taken. It is one
  comparison until subagents exist.
- Framework's two-place chain is superseded by the owner's choice.
- Interface's idle-exit receipt question is resolved by following the
  original: no new notice. CTUI-13's interim receipt goes when CTUI-16
  replaces the interim window.
