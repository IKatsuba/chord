# CTUI-12 draft: the protocol side (framework architect)

Scope, as the lead set it: JSON-RPC 2.0 over newline-delimited stdio, the
message types, and the pub.dev packages (F1-F4), the protocol view of O2,
and what O1 (c) would add. The process, the stop ladder and the tests are
runtime's; the Dart surface of `Agent` is interface's. Nothing here touches
`lib/`: all of it is the port's, under `example/chord/lib/acp/`.

All trials ran in a scratch directory outside the repository, on Dart
3.13.5 (macos_arm64), against a scratch NDJSON agent written for the trial.
The reference is what the original pins: `@agentclientprotocol/sdk` 2.6.0
(bun.lock resolves `^2.6.0` to exactly 2.6.0), its `unstable` entry, and the
schema it ships, `schema/v1/schema.unstable.json` (JSON Schema 2020-12, 257
definitions; the stable `schema.json` has 183). `PROTOCOL_VERSION` is `1`.

## Summary

- **F1.** `json_rpc_2` 4.1.0 (tools.dart.dev) works under `dart compile exe`,
  takes requests from the other side, answers unknown methods -32601 and bad
  JSON -32700, and fails every pending request when the stream ends. It does
  not frame lines (we do, below it), has no way to stop one wait (the caller
  races the future), and **does not give a handler the request's id**, so the
  agent's `$/cancel_request`, which is how an agent withdraws a permission
  request, cannot reach the handler through its `Peer`. That is a gap the
  owner decides (Q1 below), with options.
- **F2.** Five Dart ACP packages exist; none fits: each lags the 2.6 schema,
  and the generated ones drop unknown update kinds, unknown enum values or
  unknown fields, one of them printing to the console. Proposal: the wire
  stays `Map<String, Object?>`, and hand-written Dart 3 **extension types**
  are zero-cost typed views over those maps for the ~30 types M0/M1 touch.
- **F3.** With views over the decoded map, unknown fields, unknown kinds and
  unknown enum values are kept by construction and round-trip byte-exact
  through `jsonEncode`; the session layer gets every update, known or not, as
  the original does.
- **F4.** Send `protocolVersion: 1`. The original ignores the version the agent
  answers; the schema says a client "should disconnect" on one it does not
  support. Q2 below asks whether the port follows the original or the schema.

## F1. JSON-RPC

### What the original does

The SDK's `ndJsonStream` frames: a byte buffer split on `\n`, each line
trimmed, empty lines skipped, a line capped at 32 MiB
(`DEFAULT_MAX_MESSAGE_BYTES`), bad JSON answered `-32700` with `id: null`, a
JSON array answered `-32600` "JSON-RPC batches are not supported", any other
non-object `-32600`. Those error replies are written beneath the tap, so
neither the bad line nor its reply reaches `onTraffic`. Writes are serialised
(one `JSON.stringify(message) + "\n"` after another).

`tapStream` sits above the framing and hands every message either way to
`onTraffic`, in wire order, before the SDK sees it. The agent's notifications
stop at the tap (the session layer reads them from the traffic); only
requests, responses and `$/cancel_request` go on to the SDK. So updates are
read raw, by the session layer, in wire order, and an update sent before a
reply reaches the subscriber before the reply's promise settles.

The SDK answers the agent's requests through registered handlers; a method
with no handler is answered -32601. It acts on the agent's
`$/cancel_request {requestId}` by aborting that request's signal, which
`answer()` in `connection.ts` turns into the fallback (`cancelled`). chord's
own requests are sent without a signal; `ask()` races the reply against the
caller's signal and the connection's end, so chord never sends
`$/cancel_request` itself.

### Packages tried

| Package | Version, date | What it is | Result |
|---|---|---|---|
| `json_rpc_2` | 4.1.0, 2026-02 | tools.dart.dev; Client, Server, Peer over a `StreamChannel` | Works; gaps below |
| `jsonrpc2` | 3.0.1, 2021-05 | SDK `<3.0.0` | Not usable (Dart 2 only) |
| `stream_channel` | 2.1.4 | tools.dart.dev; what `json_rpc_2` takes | Used with it |

The ACP packages (F2) each carry a JSON-RPC layer too; they are judged
there.

`json_rpc_2` trial: `Peer(StreamChannel<String>)` over a child's stdio, with
`utf8.decoder` + `LineSplitter` below it and the tap in that pipeline;
under `dart run`, and the `dart compile exe` binary gave the same events.

| Question | Finding |
|---|---|
| Frames NDJSON over a process's stdio? | No: it takes a channel of whole messages. Framing is ours, below it (a few lines). `LineSplitter` alone has no length cap and also splits on a bare `\r`; to match the SDK's 32 MiB cap the splitter is our own, on `0x0A`, over bytes. |
| Takes requests from the other side? | Yes (`registerMethod`, handlers may return a `Future`; they run concurrently, a pending permission did not hold up later updates). An unregistered method is answered `-32601 Unknown method "fs/read_text_file"`, with the whole request echoed in `data`. A notification with no handler is dropped silently. |
| Bad lines? | Bad JSON is answered `-32700` with `id: null`, as the SDK does. Arrays are taken as batches and answered as batches; ACP has none and the SDK answers them `-32600`. With `Peer.withoutJson` we decode, and can answer arrays `-32600` ourselves before it. |
| Cancel a wait? | No API. The caller races `sendRequest`'s future against its own signal; a late answer is then dropped. The pending entry stays until the answer or the close (bounded by the connection's life). This is what the original's `ask()` does too. |
| Fail every pending request when the stream ends? | Yes: stdout ending closes the peer and every pending request fails with `StateError: The client closed with pending request "session/prompt"`. A request after the close throws `StateError` at once. Our layer maps both to the agent's exit (`AgentGone`). |
| A handler's work when the stream ends? | Not told: the permission handler's future stays pending. Our layer aborts it, as the original's `closing` controller does. |
| Wire order for the tap? | The tap sits below it, on decoded messages, so it is wire order by construction. In the trial an update sent before the reply reached the handler before `sendRequest`'s future completed. |
| Writes to an agent that went? | Not its concern: a write to the child's stdin after the exit threw `SocketException: Broken pipe` out of an unguarded `IOSink` and killed the trial. The writer must guard `stdin` writes and `stdin.done` (runtime's R2). |
| Handler throws? | A non-`RpcException` is answered `-32000` with the Dart stack trace in `data`. Our handlers never throw to it (they answer the fallback), as `answer()` does. |
| `$/cancel_request` from the agent? | **Gap.** `Parameters` carries `method` and `value`, not the request's `id`, so a `$/cancel_request {requestId}` cannot be matched to the running handler through `Peer`. |

### Q1 for the owner: the agent withdrawing a request

The original's SDK aborts a permission (or elicitation, or plan) handler when
the agent sends `$/cancel_request` for it, and chord answers `cancelled`.
`json_rpc_2`'s `Peer` cannot do that. Options:

- **(A) `Peer` as it is.** A withdrawn permission stays on screen until the
  turn is cancelled, ends, or the agent closes. Differs from the original
  wherever an agent withdraws a request (which agents do is not checked
  here).
- **(B) `json_rpc_2`'s `Client` for chord's requests, our own dispatcher for
  the agent's.** `Client.withoutJson` over a channel we feed the responses
  to (this is how `Peer` itself is built: it splits incoming messages into
  responses and the rest), and about a hundred lines of ours for the agent's
  requests: match a handler by method, answer -32601/-32602/-32600, keep the
  id with the handler so `$/cancel_request` can abort it, answer the
  fallback on cancel, withdrawal or close. The package keeps ids, the
  pending map, error decoding and fail-on-close.
- **(C) Our own JSON-RPC layer**, both directions (about 250 lines with the
  framing), recorded in `docs/decisions.md` with the finding above.

Framework's recommendation: (B); it uses only `json_rpc_2`'s public API and
leaves ours to what it cannot do. (C) if the owner would rather not split a
package's role.

### The layer, whichever option

In words (names are proposals; interface owns the surface):

- `wire.dart`: bytes from the agent's stdout → lines (split on `\n`, `\r`
  trimmed, empty skipped, 32 MiB cap; a longer line fails the connection as
  the SDK's `MessageTooLargeError` does) → `utf8` decode (malformed bytes
  become U+FFFD, as the SDK's `TextDecoder` does) → `jsonDecode`; bad JSON,
  arrays and non-objects answered as the SDK answers them, untapped. Out:
  one `jsonEncode(message) + '\n'` per message, serialised, writes guarded.
- the tap: every decoded message either way, and stderr text, in wire order,
  to `onTraffic` as `Traffic.agent(map)`, `Traffic.chord(map)`,
  `Traffic.stderr(text)`. The map is the one the session layer reads, not a
  copy; nobody mutates it (views are read-only; the rule is written on
  `Traffic`).
- routing, from the tap: a message with `id` and `result`/`error` → the
  pending request; with `id` and `method` → the agent's request → a handler;
  a notification → `session/update` to the updates sink, `$/cancel_request`
  to the handler it names, anything else to the traffic alone (kept, not
  dropped, as the original's tap does).
- the agent's requests M0/M1 answer: `session/request_permission` (the
  session layer's handler; `cancelled` on turn cancel, withdrawal, close).
  Everything else, `fs/*` and `terminal/*` included, is answered -32601
  (O1 (a)), as the SDK answers a method with no handler.

Cost per message: one `jsonDecode` of the line, one map lookup to route, no
copy; the tap and the reducer read the same map. Views cost nothing at run
time (extension types are erased). A thousand small updates a second is a
thousand decodes; batching them into frames is the reducer's and the
framework's (R5).

## F2. Types

### Dart ACP packages tried

Each was fetched from pub.dev and read; the two most complete were driven
against the scratch agent.

| Package | Version, date | Tracks | Finding |
|---|---|---|---|
| `dart_acp_sdk` | 0.1.1, 2026-07 | official schema at commit `67ab340` (2026-07-29), stable v1 + unstable overlay | Builds under `dart compile exe` (8 MB binary). Lacks 2.6's `notice`, `compaction_update`, `compaction_summary_chunk`, `subagent_update`, `session_message*`, `subagents`, `session/set_title`, `auth/status`. Driven: an unknown update kind is dropped before the handler; an unknown `ToolKind` value is dropped from the tool call; unknown fields are dropped on decode. One author, no likes. |
| `acp_dart` | 0.5.0, 2026-09 | TS SDK **1.5.0** | Keeps an unknown update as `UnknownSessionUpdate(rawJson)`. Driven: a `tool_call` with an unknown `kind` throws in decode, the whole update is lost, and the package prints `Error handling notification session/update: …` to the console, which in a full-screen app lands on the window. Drops unknown fields of `initialize`'s answer. Lacks `subagents`, `subagent_update`, `session_message*`, `set_title`, `auth/status`. |
| `acpd` | 1.0.0, 2026-08 | stable v1 only | No unstable surface (no `plan` capability, `plan_update`, `subagents`, `session/fork`); its stdio transport is a second package, `acpd_io`. Read, not driven. |
| `acp` | 0.1.0-rc.3, 2026-04, unlisted | ACP v0.12.0 schema | Far behind 2.6; pre-release and unlisted. Read, not driven. |
| `dart_acp` | 0.1.1, 2025-11 | an early spec | A client plus CLI with its own workspace jail, terminals and an MCP dependency (`mcp_dart`); behind 2.6. Read, not driven. |

None follows the schema the original pins, and the two typed ones that lose
information on decode would make the port drop what the original keeps.
Updating one to 2.6 is that package's maintainer's work, not ours.

### Generating types from the schema

- **`dart_acp_sdk`'s own generator** (`tool/schema/generate.dart`, 6 258
  lines, json_serializable underneath), pointed at 2.6's `schema.json` and
  `schema.unstable.json` with its manifest and drift list reconciled: it
  stops at `Unsupported schema keyword "x-deserialize-default-on-null" at
  #/$defs/AuthMethodTerminal/properties/args`, a keyword 2.6 added. Its
  output for the July schema (21 015 lines of models for v1 unstable) does
  build under `dart compile exe`, so generated Dart from this schema family
  is feasible; that generator is not ready for 2.6.
- **quicktype** (`-s schema -l dart`): not run; installing it through `npx`
  was refused in this environment. From what quicktype's Dart target is generally
  known to emit (not verified here): `fromJson`/`toJson` classes that drop unknown fields and
  map enums to Dart enums that fail on unknown values, which is the
  information loss above. If the owner wants it tried, it needs that
  permission.
- **`json_serializable`** is a code generator for classes we would write, not
  a schema reader; it drops unknown fields unless every class carries a
  catch-all, and `_meta` is free-form anyway.
- **A generator of our own** (schema → extension types): not worth it for the
  M0/M1 set; worth weighing at M2/M3 when the set grows (sessions, modes,
  models, elicitation, subagents). Recorded as a later option, not a
  workaround.

### Proposal: maps on the wire, extension types as views

The original reads updates raw from the traffic, typed by TypeScript's
structural types, which are views too: nothing is checked, nothing is
dropped. Dart 3's extension types give the same in Dart:

```dart
/// One `session/update` notification's `update`, any kind.
extension type const SessionUpdate(Map<String, Object?> json) {
  String get kind => json['sessionUpdate'] as String;
}

/// A `tool_call` update.
extension type const ToolCall(Map<String, Object?> json)
    implements SessionUpdate {
  String get toolCallId => json['toolCallId'] as String;
  String? get title => json['title'] as String?;
  String? get toolKind => json['kind'] as String?;   // unknown values stay
  Map<String, Object?>? get meta => json['_meta'] as Map<String, Object?>?;
}
```

Tried: decode, `switch (update.kind)`, read through the view, `jsonEncode`
back: the line round-trips byte for byte with an unknown field, an unknown
enum value and `_meta` in it, under `dart compile exe`.

- **Hand-written** for what M0/M1 read and write: `InitializeRequest`,
  `InitializeResponse`, `ClientCapabilities`, `AgentCapabilities`,
  `Implementation`, `AuthMethod`, `NewSessionRequest`, `NewSessionResponse`,
  `PromptRequest`, `PromptResponse` (`stopReason` a string), `ContentBlock`,
  `SessionNotification`, `SessionUpdate` and its M1 kinds (`ContentChunk`
  for the three chunk kinds, `ToolCall`, `ToolCallUpdate`,
  `ToolCallContent`, `Diff`, `ToolCallLocation`, `Plan`, `PlanEntry`,
  `AvailableCommandsUpdate`, `AvailableCommand`, `CurrentModeUpdate`,
  `UsageUpdate`), `RequestPermissionRequest`, `PermissionOption`,
  `RequestPermissionResponse`, `CancelNotification`. About thirty, each a
  constructor that builds the map and a getter per field read.
- **Enums are strings** with named constants (`StopReason.endTurn =
  'end_turn'`), so an unknown value is still a value.
- **`_meta`** is `Map<String, Object?>?` on every view that has it; the
  original's readings (`steering.supported`, `terminal_output`) are getters
  in the session layer, not the schema.
- **Unstable parts** are views like the rest, marked in their `///` line as
  unstable in ACP 2.6, and added when the milestone that draws them comes.
- **Checking**: a field the port relies on that is missing or of the wrong
  type throws a `TypeError` at the read. Requests from the agent are checked
  at the edge (the permission request's `sessionId`, `toolCall.toolCallId`,
  `options`), answered -32602 when they fail, as the SDK's zod check does;
  updates are not checked on arrival (the original does not check them) and
  the reducer reads them defensively.
- **Tests**: each view against the JSON fixtures of the original's tests and
  fake agent; a round-trip test that every fixture line re-encodes to
  itself.

Later milestones add views and handlers (session/load, resume, list, fork,
set_title, auth/status, set_mode, set_model, set_config_option,
`_session/steering`, elicitation, cursor's and grok's plans, `subagent_update`,
compaction, notices); none changes the wire, the routing or the existing
views.

## F3. Unknown fields and unknown update kinds

- **Unknown fields**: kept, since the view reads the decoded map; written
  back as they came where the port passes a message on (the session record,
  `chord acp` relays in M2/M4).
- **Unknown update kinds**: reach `onTraffic` and the updates stream like
  any other; `SessionUpdate.kind` is the string; the reducer's `switch` has
  a default that keeps the update for the record and draws nothing (how the
  original's reducer treats one is interface's to confirm).
- **Unknown enum values** (a new `ToolKind`, `StopReason`, status): kept as
  strings; the screen falls back where the original falls back.
- **Unknown methods from the agent**: requests answered -32601,
  notifications kept in the traffic and otherwise ignored.

## F4. Protocol version

`initialize` sends `protocolVersion: 1` (ACP v1, what the SDK's
`PROTOCOL_VERSION` is), `clientCapabilities` (O2), and `clientInfo: {name:
'chord', version: <the port's version>}`. The agent answers the version it
picked: ours if it supports it, else its latest. The original reads neither
`init.protocolVersion` nor any error code for it; the schema says a client
"should disconnect, if it doesn't support this version". ACP has an error
`-32022` "Unsupported protocol version" (with `requested` and `supported` in
`data`) that an agent may answer `initialize` with; that already surfaces as
a failed `initialize`, so the start fails with the agent's message.

**Q2 for the owner (via main):** an agent that answers `protocolVersion: 2`.
(a) As the original: carry on (every v1 agent today answers 1). (b) As the
schema: close the agent and say "The agent speaks ACP v2; chord speaks v1."
Framework's recommendation: (a), the port follows the original; (b) is a few
lines when the owner wants it.

## O1: fs and terminal

Under (a): no `fs`, no `terminal` in `clientCapabilities`; `fs/read_text_file`,
`fs/write_text_file` and `terminal/create|output|release|wait_for_exit|kill`
(all stable in 2.6) are answered -32601, which is what the SDK does with no
handler; command output is drawn from the tool call's `_meta.terminal_output`
as the original does (session layer). Nothing in the wire layer is specific
to them.

(c) would add: `fs: {readTextFile: true, writeTextFile: true}` and
`terminal: true`; handlers for the seven methods; a file read with
`line`/`limit` and a write, both inside the session's directory; a terminal
manager (a process per `terminalId`, output kept to `outputByteLimit` with
`truncated`, exit status, kill, release); tool-call content of type
`terminal` drawn live from it; and the agents then sending file I/O and
commands through chord instead of their own tools, which changes what the
transcript shows and how `terminal_output` `_meta` is used. It is a feature
of its own (M-later), not a wire change.

## O2: the client capabilities, protocol view

What each is in ACP 2.6's schema (what an agent sends either way is
interface's and runtime's list):

| Capability | Where | 2.6 status | What the schema says it allows | Original declares |
|---|---|---|---|---|
| `fs.readTextFile`, `fs.writeTextFile` | `ClientCapabilities.fs` | stable | `fs/read_text_file`, `fs/write_text_file` requests | no |
| `terminal` | `ClientCapabilities.terminal` | stable | all `terminal/*` requests | no |
| `auth.terminal` | `ClientCapabilities.auth` | stable | `terminal` entries in `authMethods` | no |
| `elicitation.form`, `elicitation.url` | `ClientCapabilities.elicitation` | stable | `elicitation/create` in that mode, `elicitation/complete` | yes, both |
| `session.notices` | `ClientSessionCapabilities` | stable | live `notice` updates | yes (unless told not to) |
| `session.compaction` | `ClientSessionCapabilities` | stable | id-addressed `compaction_update`, `compaction_summary_chunk` | yes |
| `session.configOptions.boolean` | `ClientSessionCapabilities` | stable | `type: "boolean"` config options and their `set_config_option` | no |
| `plan` | `ClientCapabilities.plan` | **unstable** | `plan_update`, `plan_removed` updates | yes |
| `subagents` | `ClientCapabilities.subagents` | **unstable** | `subagent_update`, session-directed `session_message*`, restricted child sessions; "must advertise before the agent sends" them | yes |
| `_meta.terminal_output_delta` | `ClientCapabilities._meta` | not in the schema | an adapter convention (Claude's adapter) for command output as `_meta` on the tool call | yes |

Notes for the decision: `notices`, `compaction` and elicitation, which the
task's wording may treat as unstable, are stable in 2.6; only `plan` and
`subagents` are unstable. `_meta.terminal_output_delta` is outside the
schema and costs nothing on the wire; it decides whether command output
arrives as `_meta` or as text. The plain `plan` update (the entries list)
needs no capability. Whatever O2 decides is one function,
`clientCapabilities()`, as in the original, and the views take every kind
either way.

## What changes in existing files

None in `lib/`, `test/` or the framework. In the port: new files under
`example/chord/lib/acp/` (the wire, the routing, the views, the connection;
names are interface's and runtime's to settle with the lead) and their tests
under `example/chord/test/acp/`; `example/chord/pubspec.yaml` gains
`json_rpc_2` and `stream_channel` under options (A) or (B), nothing under (C).
`docs/decisions.md` (the lead's) gets: the Dart ACP packages tried and why
none is taken; the types as maps with extension-type views; Q1's answer;
Q2's answer.

## Open questions

- **Q1** (owner): the agent's `$/cancel_request` and `json_rpc_2`'s `Peer`;
  options (A), (B), (C) above; recommendation (B).
- **Q2** (owner): an agent answering a protocol version other than 1; (a) as
  the original, (b) as the schema; recommendation (a).
- **Q3** (lead): whether to try quicktype after all (needs permission to
  install it through `npx`); the proposal does not depend on it.
- **Q4** (lead, with runtime): the original never taps malformed lines or the
  `-32700`/`-32600` replies to them; the port does the same unless the
  session record wants them.
