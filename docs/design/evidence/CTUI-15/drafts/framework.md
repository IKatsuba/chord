# CTUI-15, framework draft: the shape of session and transcript state

Author: framework (architects). Answers the brief's Q4, the type half of Q1,
Q2 and Q3, and names my units for Q7. Lifecycle, ordering and the fake's
evidence are runtime's; what each screen reads is interface's. Where this
draft names a field "for interface" or "for runtime", it is their call.

Read for it: the brief; `docs/design/CTUI-1.md`, `CTUI-12.md`, `CTUI-13.md`;
`docs/decisions.md`; the port's `lib/acp/` (`schema.dart`, `traffic.dart`,
`connection.dart`), `lib/session/start_connection.dart`,
`lib/ui/start_state.dart`; the framework's `ListView`/`list_viewport.dart`,
`notifier.dart`, `run_app.dart`; and in `../chord`:
`src/session/{AGENTS.md,session.ts,conversation.ts,permissions.ts,enrich.ts,enrichers.ts,subagents.ts}`,
`src/session/transcript/{types,reducer,turn,messages,tools,permissions,entries,plans}.ts`,
`src/ui/app/state.ts` (where it calls `reduceTranscript`), and the test
file list under `tests/session/`.

## 1. How the original is cut, and what that means here

Three layers, and the port keeps all three:

1. **`Session`** (`session.ts`): one agent process and one ACP session.
   Holds the early buffer (`early`), routing (`routed(tree, n)` from
   `subagents.ts`), the held updates for the first subscriber (`held`), the
   permission bridge, and `prompt(text) → Turn` whose `result` never
   rejects (a failure is `TurnResult.failed`). No transcript in it.
2. **`Conversation`** (`conversation.ts`): turns, the queue (`#queued`),
   turn ids (`#lastTurnId = 'session'` for what comes outside any turn),
   cancel, and delivery. It emits `ConversationEvent`s, which are
   `TranscriptAction | {connected, connect_failed, queued, queue_withdrawn,
   closing, …}`. It holds no transcript either.
3. **The window's state** (`ui/app/state.ts`): `reduceApp` folds every
   event; the `default:` branch is `reduceTranscript(state.transcript,
   action)`, plus scroll news when `transcript.entries` is a new array and
   "to the bottom" on a prompt. The queue the prompt draws is a mirror
   folded from `queued`/`queue_withdrawn`/`prompt` events
   (`ui/prompt/queue.ts`'s `started`).

The transcript reducer (`transcript/`) is pure, one module per kind, and
knows nothing of the other three. That split is exactly what AGENTS.md asks
for (state and reducers plain Dart, widgets draw and dispatch), so the port
keeps it rather than merging for M1. Merging would save one class and cost a
rewrite at M2, when `Conversation` gains clear, steering, models and modes
and `Session` gains record, resume and auth.

## 2. The Dart shape of state (Q4)

### 2.1 Sealed classes with final fields

Transcript state is chord's own data, not a wire format, so the reason
CTUI-12 chose extension-type views (keep unknown fields, no copy, no
generated schema) does not apply. Compared:

| Shape | Exhaustive `switch` over kinds | Nominal kinds a screen names | Equality | Verdict |
| --- | --- | --- | --- | --- |
| `sealed class` + `final class` subtypes, `final` fields, `const` constructors | yes, checked by the analyzer | yes (`ToolEntry`, `Working`) | identity unless overridden | **chosen** |
| extension types over maps | no: erased, so `switch (entry) { ToolEntry() => … }` is a cast, not a check | yes, in name only | the map's identity | no: loses the exhaustiveness the screens need, and invites mutation of a shared map |
| records | only by shape; two kinds with the same fields are one type | no | structural, shallow (a `List` field compares by identity) | no |

Dart's sealed hierarchy is what Flutter's own code and its users reach for
(`sealed class` + pattern matching), and it maps one to one onto the
original's discriminated unions: `kind`/`type`/`status` strings become
subtypes.

ACP data inside entries (a tool call's `content`, `locations`, a
permission's `options`, a plan's entries, a chunk's `ContentBlock`) stays as
CTUI-12's views from `lib/acp/schema.dart`. They are read-only outside that
library already, so the transcript copies nothing out of the wire and keeps
every field the agent sent, `_meta` included, for the later tasks (diffs,
terminals, review) that read more of them.

No code generation. `freezed` and `built_value` would generate `copyWith`,
`==` and unions, but need `build_runner` and a generated-file step this
repository does not have; the classes here are small and few, and the
equality they would generate is the one this design avoids (2.3). Not
trialled, for that reason; if the owner wants generated data classes, that
is a decision of its own.

### 2.2 Immutable lists: core `dart:collection`, copy on write

Tried, all under `dart compile exe` (Dart 3.12, macOS arm64), in a scratch
package outside the repository: `fast_immutable_collections` 12.0.0,
`built_collection` 6.0.0, `collection` 1.19.1. All three build and run AOT.
Per-update cost of the two writes the reducer makes (mean of 1000, µs):

| Entries | copy + replace last | FIC `replace(last)` | copy + append | FIC `add` |
| --- | --- | --- | --- | --- |
| 1 000 | 1.5 | 2.0 | 3.3 | 0.1 |
| 10 000 | 11 | 20 | 21 | 0.1 |
| 40 000 | 179 | 182 | 355 | 0.8 |

`built_collection`'s `rebuild` copies on every write (20 000 writes at
10 000 entries: 214 ms, against 208 ms for plain copies and 193 ms for FIC).

The hot write is *replace the last entry*: every `agent_message_chunk`
grows the reply in place (`messages.ts`'s `lastReplaced`), and every
`tool_call_update` replaces its call. FIC's replace is no cheaper than a
copy (it flushes); only its append is. `built_collection` gains nothing. So
neither earns a dependency. The state uses `List<Entry>` built by
`entries.dart`'s three writers, as the original's `entries.ts`, each
returning a fresh list wrapped in `UnmodifiableListView` (one copy, a view
with no second copy; `List.unmodifiable` would copy twice):

```dart
/// `entries` with `more` after them.
List<Entry> appended(List<Entry> entries, Iterable<Entry> more);
/// `entries` with the one at [at] replaced by [entry].
List<Entry> replacedAt(List<Entry> entries, int at, Entry entry);
/// `entries` with their last one replaced by [entry].
List<Entry> lastReplaced(List<Entry> entries, Entry entry);
```

At M1's sizes (hundreds to a few thousand entries live) a chunk costs
microseconds; a flood of 1 000 updates a second at 10 000 entries spends
about 11 ms of each second copying. The original's `inBatch` (writing in
place while folding a resumed past of 40 000 actions, CHD-559) is the seam
for records and resume: it goes into `entries.dart` behind the same three
functions, and no reducer changes. This finding and the trial go to
`docs/decisions.md` (lead).

The same rule for the other lists in state (`plan`, `permissions`, the
queue): fresh and unmodifiable on each change, the same instance when
nothing changed.

### 2.3 Equality is identity, on purpose

No state class overrides `==`. A reducer returns **the same object** for
anything it did not change, down to the entry, the entries list and the
whole state, as the original does ("The same array when nothing is added: a
new one reads as news", `turn.ts`). That identity is the change signal
everything downstream uses:

- **CTUI-1's list.** `itemVersion: (i) => (entries[i], expanded)`, as in
  CTUI-1's call site. `RenderListViewport.checkVersions` runs over every
  measured item every frame and compares with `identical(v, old) || v ==
  old`. A record's `==` compares its fields with `==`; an entry without its
  own `==` compares by identity, so the check is a pointer compare per
  item. A structural `==` on entries would make it a deep compare of every
  measured entry (a tool call's diffs included) on every frame.
- **News.** `!identical(before.transcript.entries, after.transcript.entries)`
  is the original's `withNews` condition, unchanged.
- **Screens.** A `ListenableBuilder` that draws the plan or the turn can
  skip work when `identical(old.plan, new.plan)`; with the whole tree laid
  out every frame (decision "The whole tree is laid out and painted every
  frame") none needs to, but nothing stops one.

Tests compare by value through a helper, as the original's `assertEquals`
does: `test/session/transcript/fold.dart` (the original's `fold.ts`) holds
`fold(actions)` and `described(Transcript) → Object?`, an exhaustive switch
that turns state into maps and lists for `equals`. The switch being
exhaustive, a new kind fails to compile until the helper describes it.

### 2.4 Copying

No generic `copyWith`. Nullable fields make a generic `copyWith` unable to
clear a field, and the reducers' writes are few and specific: each module
builds the next object with its constructor, as the original spreads. Where
a type is rebuilt often with one field changed, it gets a named method that
says what it does (`Transcript.withEntries`, `Transcript.withTurn`,
`ChunkEntry.grown(text)`); `tools.dart`'s merge is written out field by
field, because its rule (an update's field wins only when given, a status
only moves forward) is not a copy.

### 2.5 How a screen notices a change

One `ValueNotifier<AppState>` per window, the framework's own
(`lib/src/foundation/notifier.dart`), as CTUI-13's `StartConnection.state`
already is. `Conversation` emits events; whoever owns the window's state
(runtime and CTUI-16 settle who) does `app.value = reduceApp(app.value,
event)`. The notifier tells listeners only when the value is a new object,
so an update that changed nothing (an unknown kind, an empty chunk, a late
result for another turn) wakes nothing. Frames coalesce already: a listener
marks a build, `scheduleFrame` draws at most once per frame interval, so a
burst of updates costs one frame, not one per update.

A stream was considered and not taken: the screens need the current value
at build time, which a `ValueListenable` gives and a stream does not, and
`decisions.md` puts `Listenable` first. A version counter beside the state
would duplicate what identity already says.

Scroll is the framework's `ScrollController`, not part of `AppState` (it is
in the original's). What the original's `reduceApp` does to scroll becomes
a pure function the window applies, so it is still tested without a widget:

```dart
/// What an event asks of the transcript's scroll: nothing, news, or the bottom.
enum ScrollEffect { none, news, bottom }

ScrollEffect scrollEffectOf(AppState before, AppState after, ConversationEvent event);
// bottom on PromptAction (the person asked to see it); news when
// !identical(before.transcript.entries, after.transcript.entries); else none.
```

The window's listener calls `scroll.toBottom()` or `scroll.markNews()`
accordingly; CTUI-1 already makes `markNews` a no-op while following.

## 3. Transcript types for M1 (Q2, types)

Everything in `example/chord/lib/session/transcript/types.dart`. Kinds, fields
and names follow `types.ts`; what M1 leaves out is listed after each, as the
seam.

### 3.1 Entries

```dart
/// One block in the transcript, in the order it first appeared.
sealed class Entry {
  const Entry(this.turnId);
  /// The turn it belongs to; keeps a late update out of the turn now in flight.
  final String turnId;
}

/// What the person sent.                                   types.ts 'user'
final class UserEntry extends Entry { final String text; }

/// A reply or a thought, chunks run on into one block.     'assistant' | 'thought'
sealed class ChunkEntry extends Entry {
  final String text;
  final String? messageId;      // a new id starts a new block
  ChunkEntry grown(String more);
}
final class AssistantEntry extends ChunkEntry {}
final class ThoughtEntry extends ChunkEntry {}

/// A tool call, merged from its `tool_call` and every update.  'tool'
final class ToolEntry extends Entry { final ToolCall call; }

/// How a permission request was answered; a withdrawn one leaves none. 'permission'
final class PermissionEntry extends Entry {
  final String? title;              // the call's title as the request named it
  final acp.PermissionOption? option; // none when Esc rejected
}

final class CancelledEntry extends Entry {}                 // 'cancelled'

/// A turn that ended for a reason other than `end_turn`.    'stopped'
final class StoppedEntry extends Entry { final String reason; }

/// A failed prompt, or a failure outside a turn.            'error'
final class ErrorEntry extends Entry { final String message; final String? code; }

/// Something chord carries on past.                          'warning'
final class WarningEntry extends Entry { final String message; }

/// A finished plan, moved from above the prompt as the turn's record. 'plan'
final class FinishedPlanEntry extends Entry { final List<acp.PlanEntry> entries; }
```

`FinishedPlanEntry`, not `PlanEntry`: the ACP view of one plan item is
`PlanEntry` in `schema.dart`, and both are in scope in the screens. Transcript
modules import the schema `as acp`.

`StoppedEntry` and `FinishedPlanEntry` are not in the brief's proposed
list but are what `turn.ts`'s `settle` writes for M1's own inputs
(`max_tokens`, `refusal`; a plan all `completed` at the turn's end), so
leaving them out would be a difference from the original.

Left out, each a new subtype later, no existing one changed: `message`,
`agent_message`, `subagent`, `item_ended` (subagents, M3); `compaction`,
`notice`, `elicitation` (M3); `shell` (bash mode); `report`, `note`,
`team`, `team_part`, `left_open`, `monitors_left`, `forked`,
`self_started` (commands, teams, monitors, records, steering). An exhaustive
`switch` in the screens then fails to compile until each draws the new
kind, which is the point.

### 3.2 The tool call

```dart
/// One tool call, merged from its `tool_call` and every update to it.
final class ToolCall {
  final String id;
  final String? title;                       // the agent's latest; none until given
  final String? kind;                        // acp ToolKind string
  final String? status;                      // pending, in_progress, completed, failed
  final List<acp.ToolCallLocation>? locations;
  final List<acp.ToolCallContent>? content;  // text, diffs, terminals, as sent
  final Object? rawInput;
  final Object? rawOutput;
}
```

Left out: `terminals` (live terminal output, M3: `foldTerminals` from
`_meta`), `mcp` (the `codexMcpCall` enricher), `cut` (steering), `guardian`
and `review` (permission review), `plan` (cursor/grok plans), `chord`
(chord's MCP), `asked` (elicitation). Each is a nullable field added to
`ToolCall` and one more line in the merge.

Terminal output under `_meta` while the capability is undeclared: the
transcript reads none of it in M1, since `foldTerminals` is out. If runtime
finds an adapter that sends `terminal_output` under `_meta` undeclared and
interface needs it drawn, porting `foldTerminals` and `Terminal` (with
`terminal_text.ts`) is its own unit; the type has room for it.

### 3.3 The turn

```dart
/// What the turn in flight is doing; times are epoch milliseconds.
sealed class TurnState { const TurnState(); }
final class Idle extends TurnState {}
final class Working extends TurnState { final String turnId; final int since; }
final class AwaitingPermission extends TurnState {
  final String turnId;
  final int since;
  final List<PermissionWait> permissions;   // oldest first; the first is on screen
  final bool between;                       // asked, or left waiting, with no turn running
}
final class Cancelling extends TurnState {
  final String turnId; final int since; final int cancelledAt;
}
```

`between` stays in M1: the original keeps a permission open past its turn's
answer ("now between turns", the owner's Q44, CHD-158) and the fake's
`leftask` and `mainbetween` play it, both in CTUI-12's M1 list. Left out:
`cycle` and `cycleSince` (the agent's own cycles, CHD-426, which come with
steering).

```dart
/// A permission request waiting on the person.
final class PermissionWait {
  final String id;
  final String? toolCallId;
  final String? title;
  final String? kind;
  final List<acp.ToolCallLocation>? locations;
  final List<acp.ToolCallContent>? content;
  final Object? rawInput;
  final List<acp.PermissionOption> options;
}

sealed class PermissionAnswer { const PermissionAnswer(); }
final class Chosen extends PermissionAnswer { final String optionId; }
final class Rejected extends PermissionAnswer {}
final class Withdrawn extends PermissionAnswer {}   // cancelled under it; leaves no entry
```

Left out of `PermissionWait`: `subagentId`, `at` (subagents, deadlines),
`review`, `deadlineAt`, `detail`, `save` (review and chord's own questions).

```dart
/// How a turn ended: the agent's answer, or why there was none.
sealed class TurnResult { const TurnResult(); }
final class TurnAnswered extends TurnResult {
  final bool cancelled;          // stopReason == 'cancelled', the original's status
  final String stopReason;
}
final class TurnFailed extends TurnResult { final String message; final String? code; }
```

Left out: `usage` (costs), `signIn` (auth). Both are fields added later.

### 3.4 The transcript

```dart
/// Everything a session's turns produced, as plain state the screens draw.
final class Transcript {
  final List<Entry> entries;
  final List<acp.PlanEntry> plan;   // the latest plan; each `plan` update replaces it, [] clears
  final TurnState turn;
  static const empty = Transcript._(entries: [], plan: [], turn: Idle());
}
```

Left out: `planId`, `planAsks` (id-addressed and cursor/grok plans, M3),
`usage`, `mode`, `asking` (elicitation), `served` (chord's MCP), and
`commands` (`available_commands_update`). `commands` is the one interface
may want back: it is one reducer line and feeds the slash menu, which is
M2 by the map; I leave it out unless interface's draft names a screen that
reads it in M1.

### 3.5 Actions

```dart
/// What the reducer folds. `turnId` keeps a late update from an earlier turn
/// out of the turn now in flight.
sealed class TranscriptAction { const TranscriptAction(this.turnId); final String turnId; }

final class PromptAction extends TranscriptAction { final String text; final int at; }
final class UpdateAction extends TranscriptAction { final acp.SessionUpdate update; final int? at; }
final class PermissionRequestedAction extends TranscriptAction {
  final PermissionWait permission; final int? at; final bool between;
}
final class PermissionSettledAction extends TranscriptAction {
  final String id; final PermissionAnswer answer;
}
final class CancelAction extends TranscriptAction { final int at; }
final class DisconnectedAction extends TranscriptAction { final int? at; }
final class ResultAction extends TranscriptAction { final TurnResult result; }
final class FailedAction extends TranscriptAction { final String message; }
final class WarnedAction extends TranscriptAction { final String message; }
```

Each maps to one `type` of `TranscriptAction` in `types.ts` (`prompt`,
`update`, `permission_requested`, `permission_settled`, `cancel`,
`disconnected`, `result`, `failed`, `warned`). `PromptAction` drops `from`,
`team` and `into` (messages, teams, steering). `UpdateAction` drops
`subagentId` and `unasked`.

`DisconnectedAction` is kept although in M1 it changes nothing: in the
original it only ends running subagents. `Conversation` emits it where the
original does, so M3 fills in `disconnected()` and touches no caller. What a
person sees when the agent goes mid-turn is the prompt's failure,
`TurnFailed('The agent exited: …')`, an `ErrorEntry` via `settle`, as the
original. `FailedAction` and `WarnedAction` are kept because runtime may
need them for a failure outside a turn (a `cancel` that fails with
`AgentGone`); if runtime's draft uses neither, drop them.

`ConversationEvent`, in `conversation.dart`:

```dart
/// What a conversation reports: a transcript action, or a fact of the session.
sealed class ConversationEvent { const ConversationEvent(); }
// TranscriptAction extends ConversationEvent, so every action is an event.
final class Connected extends ConversationEvent { final String sessionId; final int? at; }
final class ConnectFailed extends ConversationEvent { final String message; }
final class Queued extends ConversationEvent { final String turnId; final String text; final bool afterAnswer; }
final class QueueWithdrawn extends ConversationEvent { final List<String>? turnIds; }
final class Closing extends ConversationEvent {}
```

`Queued.afterAnswer` follows the original (a prompt held because the turn
waits on the person). The original's `afterCalls`, `steering`, `taken` and
`refused` are steering's. Which of these runtime's lifecycle needs is
runtime's to confirm; the hierarchy takes more without change.

## 4. The reducer (structure)

One module per kind, as `transcript/`; each is plain functions from
`Transcript` to `Transcript`.

| Dart file | Original | Holds in M1 |
| --- | --- | --- |
| `transcript/types.dart` | `types.ts` | 3 above |
| `transcript/entries.dart` | `entries.ts` | `appended`, `replacedAt`, `lastReplaced` (2.2); the `inBatch` seam |
| `transcript/messages.dart` | `messages.ts` | `textOf(ContentBlock)`, `appendText` |
| `transcript/tools.dart` | `tools.ts` | `mergeToolCall`, `nextStatus` (status only forward; once finished, nothing moves it back) |
| `transcript/permissions.dart` | `permissions.ts` | `permissionRequested`, `permissionSettled` |
| `transcript/turn.dart` | `turn.ts` | `prompted`, `cancelled`, `settle`, `disconnected`, `isCurrent`, `endingOf` |
| `transcript/reducer.dart` | `reducer.ts` | `reduceTranscript`, `applyUpdate` |

`plans.ts` is `plan_update`/`plan_removed` only, a non-goal; the base
`plan` update is two lines inside `reducer.ts`'s `applyUpdate`, and stays
there.

```dart
/// The next transcript after [action]; the same object when nothing changed.
Transcript reduceTranscript(Transcript state, TranscriptAction action) =>
    switch (action) {
      PromptAction() => prompted(state, action.turnId, action.text, action.at),
      UpdateAction() => _update(state, action),
      PermissionRequestedAction() => permissionRequested(state, …),
      PermissionSettledAction() => permissionSettled(state, …),
      CancelAction() => cancelled(state, action.turnId, action.at),
      DisconnectedAction() => disconnected(state, action.at),
      ResultAction() => settle(state, action.turnId, action.result),
      FailedAction() => state.withEntries(appended(state.entries, [ErrorEntry(…)])),
      WarnedAction() => state.withEntries(appended(state.entries, [WarningEntry(…)])),
    };

Transcript _update(Transcript state, UpdateAction action) {
  try {
    return applyUpdate(state, action.turnId, action.update);
  } on Object {
    // Updates are not checked on arrival (CTUI-12); a malformed one draws
    // nothing and the next still draws.
    return state;
  }
}

Transcript applyUpdate(Transcript state, String turnId, acp.SessionUpdate update) =>
    switch (update.kind) {
      acp.SessionUpdate.agentMessageChunk => appendText(state, turnId, assistant, …),
      acp.SessionUpdate.agentThoughtChunk => appendText(state, turnId, thought, …),
      acp.SessionUpdate.toolCall || acp.SessionUpdate.toolCallUpdate =>
          mergeToolCall(state, turnId, update),
      acp.SessionUpdate.plan => …,  // a list that is not there leaves the last one
      _ => state,                   // the prompt is drawn from what was sent; the rest not yet
    };
```

The per-update catch sits in the reducer, not in the session or the
connection, so "one malformed update draws nothing" is a pure test, and a
partial write cannot leak: every module builds its next state before
returning it, so a throw leaves `state` as it was. CTUI-12's `TrafficTap`
catch stays the outer guard. `user_message_chunk`, `available_commands_update`,
`current_mode_update` and `usage_update` fall into `_` in M1 (the original
handles the last three; seams in 3.4).

The original's top-level `self_started` handling in `reduceTranscript`,
`withEndLines` and `withPlan` are steering, subagents and cursor/grok plans:
not ported, nothing in their place.

### 4.1 Where the original calls `subagents.ts`, and what M1 writes there

No stub module. Each call is the branch the original takes when the session
has no subagents, written as that branch, with a one-line comment saying
M3 adds the rest. So M3 adds `subagents.dart` and changes these five places,
nothing else:

| Original | M1 |
| --- | --- |
| `turn.ts` `taskWaits` (in `prompted`, `settle`, `permissionRequested`'s `outside`) | not ported; `outside` is `between` alone |
| `turn.ts` `settle`: `endRunning(…, 'cancelled', …)` on a cancelled result | omitted |
| `turn.ts` `disconnected`: `endRunning` + `itemEndLines` | returns `state` |
| `permissions.ts` `permissionSettled`: a subagent's answer into its entries | always `appended` to the session's |
| `permissions.ts` `reviewedIn` / `changeSubagent` | omitted with `review` |

`reducer.ts`'s `childUpdate` (an `UpdateAction` with a `subagentId`) has no
M1 counterpart because `UpdateAction` has no `subagentId`.

## 5. Session, inbox and conversation (Q1, shape)

Lifecycle, ordering and failure are runtime's; this is where each piece
sits and what its surface is.

### 5.1 `lib/session/session.dart`: `Session`, `openSession`, the inbox

```dart
/// A prompt sent: its id, how it ended, and the way to stop it.
final class Turn {
  final String id;
  /// Settles with the agent's answer, or [TurnFailed] with why there was none; never throws.
  final Future<TurnResult> result;
  /// Asks the agent to stop it; [result] then says cancelled, when the agent says so.
  final Future<void> Function() cancel;
}

/// One agent process and one ACP session in it, until [close].
abstract interface class Session {
  String get agent;                 // the CLI name
  String get cwd;
  String get id;                    // the agent's session id
  PermissionBridge get permissions;
  Future<void> get exited;
  String? gone();                   // the end of its stderr once gone; null while up
  /// Hears every update for this session from now on; those before the first
  /// listener are handed to it first. Returns the way to stop listening.
  void Function() subscribe(void Function(acp.SessionUpdate update) listener);
  Turn prompt(String text);
  Future<void> close();
}

Future<Session> openSession({
  required String agent,
  required Object command,
  required String cwd,
  AgentOpener open = openAgent,     // CTUI-13's seam, for tests
  CancellationToken? cancellationToken,
});
```

M1's members out of `Session`'s forty: `agent`, `cwd`, `id`, `permissions`,
`exited`, `gone`, `subscribe`, `prompt` (text only), `close`. The rest are
seams that add members, none that changes these: `record`, `resumed`,
`history` (records, resume), `elicitations`, `plans` (M3), `agentPids`,
`agentState`, `takesImages`, `takesEmbeddedContext`, `steers`, `account`,
`subscribeAccount`, `forks`, model/mode/config setters, `chordServer`,
`heldBack` (M2-M4). `prompt`'s `attachments`, `mentions`, `links`,
`resources` are optional parameters added later. The subscriber's second
argument (`subagentId`) is added by M3 as an optional positional parameter;
existing listeners keep compiling.

The inbox. The original's is closure state inside `openSession`; the port
makes it a class in the same file, so it is tested without a process
(`test/session/session_updates_test.dart`, the original's file for these
cases):

```dart
/// The session's one ingress: holds updates until the session's id is known,
/// keeps only that session's, and holds them again until the first listener.
final class SessionInbox {
  /// Every crossing, as `onTraffic` hands it; never throws.
  void hear(Traffic traffic);
  /// The session is [sessionId]: the buffer is routed now, in arrival order.
  void open(String sessionId);
  /// As [Session.subscribe].
  void Function() subscribe(void Function(acp.SessionUpdate update) listener);
}
```

- `hear` takes only `AgentTraffic` whose `method` is `session/update`
  (`updateIn` in the original); everything else is the recorder's.
- Before `open`, it buffers (`early`). `open` routes the buffer, then live
  updates route as they come. The `session/new` answer itself is
  `openSession`'s return value, so "the answer first, then the buffer"
  (CTUI-12) holds by construction: `open` runs after the answer is read
  and before `openSession` returns.
- Routing is exact: `notification.sessionId == id`. The original asks
  `routed(tree, n)` from `subagents.ts`, where the tree grows by
  `subagent_update`. M1 builds no tree: the comparison is one line in
  `SessionInbox`, and M3 puts `routed` in `lib/session/subagents.dart` in
  its place, with the `subagentId` it returns passed to listeners.
- With no listener yet, routed updates are held (`held`); `subscribe` hands
  them over first, then live ones, synchronously, in order.

The inbox hears through the session's enricher relay when there is one
(5.3); its input type does not change.

### 5.2 `lib/session/permissions.dart`: the bridge

The original's `PermissionBridge` and `PendingPermission`, on CTUI-12's
`onPermission(request, token)`:

```dart
/// A permission request the agent waits on, until the person answers.
final class PendingPermission {
  final String id;                 // the bridge's own, stable; becomes PermissionWait.id
  final String sessionId;
  final acp.ToolCallUpdate toolCall;
  final List<acp.PermissionOption> options;
  final acp.RequestPermissionRequest raw;
  final CancellationToken token;   // cancelled when it stops mattering
  void resolve(String optionId);
  void reject();                   // the agent's reject option, else `cancelled`: rejection()
}

final class PermissionBridge {
  Future<acp.RequestPermissionResponse> handle(
      acp.RequestPermissionRequest request, CancellationToken token);
  void Function() subscribe(void Function(PendingPermission request) listener);
  List<PendingPermission> pending();
  void close();
}

acp.RequestPermissionResponse rejection(List<acp.PermissionOption> options);
```

`AbortSignal` becomes CTUI-12's `CancellationToken`, which the connection
already merges from `$/cancel_request`, the session's cancel and closing.
`allowOption` is `--dangerously-skip-permissions`'s, not M1's.
`Conversation` turns a pending request into `PermissionRequestedAction`
(with a `PermissionWait` built from it) and its settlement into
`PermissionSettledAction` (`Chosen`, `Rejected`, or `Withdrawn` when the
token was cancelled first), as `conversation.ts`'s `waitFor` does.

### 5.3 `lib/session/enrich.dart`, `enrichers.dart` (Q3, the type)

If M1 builds the chain (interface says what is lost without each; runtime
places it), it is the original's type, over CTUI-12's decoded maps:

```dart
/// One message the agent sent, in ACP's shape, as decoded.
typedef Message = Map<String, Object?>;

/// Turns one message the agent sent into the messages chord reads in its place.
typedef Enricher = List<Message> Function(Message message, Wire wire);

/// What the chain knows: chord's open requests and each session's facts.
final class Wire {
  final Map<String, Asked> asked;            // by request id, as JSON-typed
  final Map<String, SessionWire> sessions;   // by session id
  static const empty = …;
}
final class SessionWire { final Map<String, ToolFacts> tools; }
final class ToolFacts { final String? title; final String? kind; final bool ownContent; }

List<Message> enrich(List<Enricher> chain, Message message, Wire wire);
Wire heardFromChord(Wire wire, Message message);
Wire heardFromAgent(Wire wire, Message message);
const filled = 'chord/filled';   // the `_meta` key naming what chord filled
```

`SessionWire` in M1 keeps only `tools`; the original's `agent`, `usage`,
`agentCost`, `estimate`, `total` come with the enrichers that read them
(costs, windows, modes). An enricher builds a new map; it never writes the
one it was handed, since `Traffic` shares it (CTUI-12).

M1's candidates are `toolCallFacts` and `rawOutputContent`; the other
twelve join `enrichers` (the list) with their tasks. Note for runtime and
the lead: in the original the chain is a `Relay` on the transport, so it
runs before the SDK hands a permission request to its handler, and
`toolCallFacts` fills the request's `toolCall` title. CTUI-12's connection
has no relay: `onTraffic` is a tap and `onPermission` gets the request
unenriched. Without changing CTUI-12, the session owns one `Wire` and runs
the chain in two places: on each `AgentTraffic` before the inbox, and in
`PermissionBridge.handle` on the request before it is published. That keeps
the original's result (the request the screen sees is filled in) with
CTUI-12 untouched. The alternative is a `relay` parameter on `openAgent`,
a change to a fixed contract; I do not recommend it for M1.

Within the transcript, `toolCallFacts` adds nothing for updates:
`mergeToolCall` already keeps a title or kind a later update leaves out.
It matters for the permission prompt's title and for the record (a
non-goal). That is for interface to weigh.

### 5.4 `lib/session/conversation.dart`

```dart
/// A session's turns, one at a time, the prompts that wait behind the one
/// running, and everything they report as events.
final class Conversation {
  Conversation({
    required Future<Session> Function(CancellationToken token) open,
    required void Function(ConversationEvent event) emit,
    int Function() now = _epochMillis,     // injected for tests
    String Function() newTurnId = _uuid,   // injected for tests
  });
  void start();
  /// Sent now, or queued behind the running turn.
  Delivery send(String text);              // enum Delivery { sent, queued }
  /// Cancels the running turn; queued prompts of the person's are withdrawn.
  void interrupt();
  Future<void> close();
}
```

The turn-id rule, from the original: each prompt gets a fresh id; an update
is folded under the turn on screen, else the last turn's id, else
`'session'`. The queue's rules, cancel's, and what happens on exit are
runtime's (Q5); this surface is what they act through. Screens never see
`Conversation` beyond `send`, `interrupt` and the pending permissions'
`resolve`/`reject`.

### 5.5 `lib/ui/app/state.dart`: the window's M1 slice

As the original's `ui/app/state.ts`, plain Dart:

```dart
/// What the window draws, folded from conversation events.
final class AppState {
  final StartState start;          // CTUI-13's: starting, connected, failed, gone
  final Transcript transcript;
  final List<QueuedPrompt> queue;  // the mirror of Conversation's queue, oldest first
}

AppState reduceApp(AppState state, ConversationEvent event);
ScrollEffect scrollEffectOf(AppState before, AppState after, ConversationEvent event);
```

`reduceApp` passes every `TranscriptAction` to `reduceTranscript`, folds
`Queued`/`QueueWithdrawn` and `PromptAction` into `queue` (the original's
`ui/prompt/queue.ts` `started`), and `Connected`/`ConnectFailed` into
`start`. Whether `start` stays CTUI-13's `StartState` or is folded into
`AppState` directly is interface's and CTUI-16's call; the shape works
either way. If the lead prefers CTUI-15 to stop at `lib/session/`, this
file moves to CTUI-16 unchanged.

## 6. Files and tests

```text
example/chord/lib/session/
  session.dart            Session, openSession, Turn, SessionInbox
  permissions.dart        PermissionBridge, PendingPermission, rejection
  enrich.dart             Enricher, Wire, enrich, heardFrom*        (if built)
  enrichers.dart          toolCallFacts, rawOutputContent, enrichers (if built)
  conversation.dart       Conversation, ConversationEvent, Delivery
  transcript/
    types.dart  entries.dart  messages.dart  tools.dart
    permissions.dart  turn.dart  reducer.dart
example/chord/lib/ui/app/
  state.dart              AppState, reduceApp, ScrollEffect, scrollEffectOf

example/chord/test/session/
  session_test.dart  session_updates_test.dart  permissions_test.dart
  enrich_test.dart   enrichers_test.dart
  conversation_test.dart  conversation_entries_test.dart
  transcript/
    fold.dart                       fold(actions), described(transcript)
    reducer_test.dart  entries_test.dart  tools_test.dart  permissions_test.dart
example/chord/test/ui/app/state_test.dart
```

Each test file is the original's of the same path, carried over for the
cases M1 covers; a case for a left-out kind is not ported, and the file
says which were left at its top, so the next milestone ports them. The
original has no `messages_test.ts` or `turn_test.ts`: those cases live in
`reducer_test.ts`, and stay there. Added beyond the original, because the
port's shape makes them claims: a reducer returns the identical state for
an action that changes nothing (an unknown update kind, an empty chunk, a
result for a turn not current with nothing to write); a malformed update
(a `tool_call` without `toolCallId`) leaves the state identical and the
next update still draws; `entries` returned by the reducer cannot be
mutated; an entry not touched by an action is identical before and after.

## 7. Cost

- Per update: one reducer pass, O(1) for a chunk except the entries copy
  (11 µs at 10 000 entries, AOT); a tool update adds a scan from the end
  for its id (`findLastIndex`, as the original), usually a few entries.
- Per frame: the list's `checkVersions` is a pointer compare per measured
  item (2.3); the screens rebuild from one notifier as every frame does.
- Per burst: one frame per frame interval, however many updates
  (`scheduleFrame`).
- Memory: one transcript, shared structurally between successive states;
  only the entries list and the changed entry are new per update.

## 8. Units for ship (mine)

Each lands with tests that fail without it.

1. **Transcript types, entries, messages, turn and reducer core.** `types.dart`,
   `entries.dart`, `messages.dart`, `turn.dart` (prompted, cancelled,
   settle with `StoppedEntry`, `CancelledEntry`, `ErrorEntry` and the
   finished plan, disconnected as identity), `reducer.dart` (prompt,
   chunks, `plan`, cancel, result, failed, warned, the per-update catch),
   `fold.dart`. Tests: `reducer_test`, `entries_test` subsets.
2. **Tool calls.** `tools.dart`; `tools_test` subset (merge, late, twice,
   before the call, status order).
3. **Permissions in the transcript.** `transcript/permissions.dart`,
   `AwaitingPermission` with `between`; `transcript/permissions_test`
   subset.
4. **Enricher chain** (only if Q3 says build): `enrich.dart`, `toolCallFacts`,
   `rawOutputContent`; `enrich_test`, `enrichers_test` subsets.
5. **Session and inbox.** `session.dart`, `permissions.dart` (bridge);
   `session_updates_test`, `session_test`, `permissions_test` subsets,
   in-memory and scripted (runtime's plan).
6. **Conversation.** `conversation.dart`; `conversation_test`,
   `conversation_entries_test` subsets and the fake's scenarios (runtime's
   plan).
7. **The window's slice.** `ui/app/state.dart`; `state_test` (fold, queue
   mirror, scroll effect).

1-3 depend on nothing but `schema.dart` and can go in parallel after 1's
types; 5 needs 3's `PermissionWait`; 6 needs 1-5; 7 needs 1 and 6's events.

## 9. Answers

**Q4 (mine).** Sealed classes with final fields and `const` constructors for
transcript state; ACP data inside entries stays CTUI-12's views. Lists are
core `List`s, copied on write by `entries.dart` and exposed as
`UnmodifiableListView`; `fast_immutable_collections` 12.0.0 and
`built_collection` 6.0.0 were tried under `dart compile exe` and give no gain
on the hot write (replace last). No `==` overrides: identity is the change
signal, kept by reducers that return the same object when nothing changed.
A screen notices through one `ValueNotifier<AppState>`; the list learns
which entries changed through `itemVersion: (i) => (entries[i], …)`, a
pointer compare; news is a new entries list; both rules are pure
(`scrollEffectOf`).

**Q1 (shape).** Keep the split: `Session` (connection to one ACP session:
inbox, bridge, `prompt → Turn`), `Conversation` (turns, queue, ids, events),
the window's `AppState` (folds events, calls `reduceTranscript`). The inbox
is a class in `session.dart`, before any subagent routing; M1 routes by exact
id, and M3 replaces that one comparison with `routed` from
`subagents.dart`.

**Q2 (types).** Entries: user, assistant, thought, tool, permission,
cancelled, stopped, error, warning, finished plan; the plan, the turn and
the waiting permissions as state. Actions: prompt, update, permission
requested and settled, cancel, disconnected, result, failed, warned.
`subagents.ts` calls become the no-subagent branch at five named sites, no
stub module. `_meta` terminal output: not read in M1; `ToolCall` takes a
`terminals` field when it is.

**Q3 (type).** `Enricher = List<Message> Function(Message, Wire)` over
decoded maps, as the original; `Wire` with only `tools` in M1. If built, it
runs in the session layer twice over one `Wire`: on traffic before the
inbox, and on a permission request in the bridge; CTUI-12 stays as it is.

## 10. Questions

For the lead, not the owner (decisions of shape within the brief):

- **`lib/ui/app/state.dart` in CTUI-15 or CTUI-16.** Recommend CTUI-15
  (unit 7): it is the only place `reduceTranscript` is called and the only
  test that proves the events fold into what the screens read.
- **`commands` in `Transcript`.** Recommend out of M1 unless interface names
  an M1 screen that reads it.

For the owner, one, with options. It is a difference from the original
only if Q3 decides to build the chain:

- **Where the enricher chain runs.** The original runs it on the
  transport, before the permission handler. CTUI-12's contract has no hook
  there.
  - (a) The session layer runs it twice over one `Wire`: on updates before
    the inbox, and on permission requests in the bridge. CTUI-12 stays as
    it is; the recorder (a later task) taps raw traffic, so the record would
    hold what the agent sent, not what chord filled in, unless the record
    task also taps after the chain.
  - (b) Add a `relay` to `openAgent`, as the original's `Relay`, so
    everything after the transport (tap, routing, the permission handler)
    reads enriched messages. A change to CTUI-12's fixed contract.
  - (c) Do not build the chain in M1; fold raw updates. The permission
    prompt then shows no title where the agent's request leaves it out and
    a tool call that sends only `rawOutput` shows no output, until the
    chain lands.

  Recommendation: (a) for M1, with the record task deciding later whether
  it moves to (b).
