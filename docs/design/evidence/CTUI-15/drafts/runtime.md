# CTUI-15 runtime draft: turns, queue, cancel, exit, the inbox, the tests

Runtime architect's draft. Owns the brief's Q1 (lifecycle), Q5, Q7 and the
runtime side of Q2 and Q3. Read against `../chord/src/session/session.ts`,
`conversation.ts`, `transcript/turn.ts`, `transcript/reducer.ts`,
`transcript/messages.ts`, `transcript/tools.ts`, `transcript/subagents.ts`
(`routed`, `sessionTree`), `permissions.ts`, `enrich.ts`,
`../chord/src/acp/connection.ts` and `traffic.ts` (`relayStream`,
`tapStream`), `../chord/src/ui/app/state.ts` and `keys.ts` (where Esc goes),
`../chord/docs/agent-capabilities.md`, the original's tests under
`tests/session/`, and the fake agent under `tests/fixtures/fake_agent/`.
The port's side: `example/chord/lib/acp/` (connection, rpc, traffic),
`lib/session/start_connection.dart`, `test/fixtures/fake.dart`,
`fake_harness.dart`.

Evidence, under `docs/design/evidence/CTUI-15/runtime/`:

- `capture.ts`: a Deno driver that runs the original's fake through bun
  with the port's M1 client capabilities (`{}`), and records every message
  both ways with milliseconds since spawn. Rerun with
  `deno run --allow-run --allow-read --allow-write --allow-env capture.ts
  ../chord . <scenario…>` from that directory.
- `<scenario>.jsonl`: `text`, `late`, `shell`, `bash`, `permission`,
  `twins`, `tools`, `unknown`, `turnfailed`, `error`, `crash`,
  `cancel-slow` (cancel after the first chunk), `close-ignorescancel`
  (cancel, then stdin closed a second later).
- `fold_cost.dart` and `fold_cost.txt`: what a literal port of
  `appendText` and `lastReplaced` costs in Dart.

## 1. Where the logic lives

The port keeps the original's split. It is what makes each part testable
without the others, and every later milestone (clear, resume, children,
teams) replaces a `Session` under one `Conversation`; merging them in M1
would be undone in M2.

| Port file (`example/chord/lib/session/`) | Original | Holds | Plain Dart? |
| --- | --- | --- | --- |
| `session.dart` | `session.ts` | `openSession`, `Session`: one agent, one ACP session; `prompt` returning a `Turn` (`result` never throws), `cancel`, `close`, `gone`, `exited`, `subscribe`; `agentEnv` | yes; owns the `Agent` |
| `inbox.dart` | the inside of `openSession` (`early`, `route`, `hear`, `held`, `updateIn`) | `SessionInbox`: the early buffer, exact-id routing, the hold until the first subscriber | pure, no `Agent`, no timer |
| `permissions.dart` | `permissions.ts` | `PermissionBridge`, `PendingPermission`, `rejection`, `allowOption`, `waitFor` | pure but for its tokens |
| `conversation.dart` | `conversation.ts`, cut to M1 | `Conversation`: send, queue, play, settle, interrupt, `cancelPrompt`, choose, reject, close; emits `ConversationEvent`s | yes; owns one timer |
| `enrich.dart`, `enrichers.dart` | same names | the chain, `Wire`, `Relay`, the M1 enrichers (Q3) | pure |
| `transcript/*.dart` | `transcript/*.ts` | the reducer, one module per kind (framework's draft owns the shape) | pure |
| `terminal_text.dart` | `terminal_text.ts` | only if the owner takes 7(B) below | pure |

`inbox.dart` is the one file with no original of its own: `session.ts`
keeps the same logic in closures. Split out, it is tested as a pure unit
with no process; CTUI-12 already named it.

The window holds no logic of these: it subscribes to the conversation's
events, folds them through `reduceTranscript` into the state it draws, and
dispatches `send`, `interrupt`, `choose`, `reject`. The window's own
fold (the original's `state.ts` `default:` branch: the queue's
`started`, scroll to the bottom on a prompt) is CTUI-16/17's.

Tests mirror the sources: `test/session/session_test.dart`,
`session_updates_test.dart`, `inbox_test.dart`, `permissions_test.dart`,
`conversation_test.dart`, `enrich_test.dart`, `enrichers_test.dart`,
`test/session/transcript/<module>_test.dart`, with the original's shared
helpers as `test/session/session_fake.dart` (`withSession`, `collect`),
`conversation_fake.dart` (a scripted `Session` for the conversation's unit
tests) and `test/session/transcript/fold.dart`.

### What `Session` keeps in M1

Of the original's forty members: `agent`, `cwd`, `id`, `permissions`,
`exited`, `gone()`, `subscribe()`, `prompt(text)` (no attachments,
mentions, links or resources), `cancel()`, `close()`, `withdraw()`.
Everything else is a later task's member on the same object (models,
modes, options, efforts, account, steer, title, fork, history, servers).

`agentEnv` is in M1 although it looks like a detail: without
`CLAUDE_CODE_ENABLE_TODO_TOOLS=1` Claude Code leaves its task list tools
out for newer models and never sends a `plan`, so M1's plan checklist
would never show on Claude (`session.ts`, `agentEnv`; the port's
`fake_agent_test.dart` already passes it by hand).

`openSession` takes the opener as `StartConnection` does (`AgentOpener`),
so a test puts the fake harness's or an in-memory agent in its place.
CTUI-13's `StartConnection` becomes the window's caller of `openSession`
(its `StartState` events stay); that change is ship's, in the unit that
first draws a turn.

## 2. The inbox, on CTUI-12's one ingress

```text
stdout bytes ─ LineDecoder ─ (relay, if 3(B)) ─┬─ tap ─ onTraffic ─ SessionInbox.hear
                                               └─ route ─ chord's answers / AgentRequests (onPermission)
```

Everything here runs on one isolate, synchronously per line: the port's
`_framed` taps a message, then routes it, before the next line of the same
read is decoded. That gives the session layer these facts to build on:

1. An update read before a reply is heard (and folded) before the reply's
   future resumes its awaiter: the reply goes through `json_rpc_2`'s
   channel, which completes at least a microtask later.
2. Updates read after a reply but in the same stdout read are also heard
   before the awaiter resumes. Updates in a later read may come either
   side of it. Which one happens depends on how the pipe chunked the bytes,
   so nothing may depend on it (section 4, S12).
3. A permission request is handed to `onPermission` synchronously by the
   dispatcher (`AgentRequests.request` calls the handler before its first
   `await`), so it comes after every update read before it.
4. `agent.prompt()` enqueues `session/prompt` synchronously (no `await`
   before `ChordRequests.request` in `_Connection.ask`), so a cancel
   called right after it is behind it on the wire. M1 has no mention walk,
   so the original's "cancel before the prompt went" case (Q42) cannot
   happen; `Turn.sent` is still kept, resolved at once, as the seam for
   mentions.

`SessionInbox`, as `openSession`'s closures:

- `hear(Traffic)`: keeps only `Traffic.agent` messages that are a
  `session/update` notification as `updateIn` reads one (no `id`, `params`
  a map, `sessionId` a string, `update` a map whose `sessionUpdate` is a
  string). Nothing is validated beyond that; an unknown kind passes.
  Anything else is not the inbox's: `auth/status_update` and
  `elicitation/complete` are named seams for M2/M3, heard here later from
  the same tap.
- Before `open`: every update goes into `early`, whatever its session id.
- `open(sessionId, NewSessionResponse answer)`: seeds the answer first (the
  agent state, `stateOf(answer)`: modes and config options, read by no M1
  screen but kept so M2 adds readers, not plumbing), then routes `early`
  in order, then routes live.
- Routing is `routed(tree, notification)` ported as is from
  `subagents.ts`, with `SessionTree(root)` and an empty subagent set. M1
  declares no `subagents` capability, so no agent sends a
  `subagent_update` and the set stays empty; an update for any other
  session id is dropped (`heard: false`). Porting the 25 lines unchanged
  costs nothing and the subagents task adds no plumbing.
- `subscribe(listener)`: the first subscriber gets `held` (every update
  routed before it existed), in order, synchronously inside `subscribe`,
  then live updates. Later subscribers get only live ones, as the
  original. Returns the unsubscribe.
- `close()`: drops `early` and `held` and every listener; nothing after it
  is heard.

Bounds: `early` and `held` are not bounded, as the original's are not.
They hold what the agent sent in the milliseconds between `session/new`'s
answer and the conversation's subscribe; an agent that floods there is the
`flood` case, ended by the person closing.

## 3. Where the enricher chain sits (Q3, runtime side)

In the original the chain is a `Relay` on the transport, between the
framing and the tap (`connection.ts`: `tapStream(relayStream(wire, relay),
onTraffic)`): the tap, the SDK's routing, the permission handler and the
record all see the enriched messages, and the chain hears chord's own
messages (`fromChord`) before they are written, which is how `Wire.asked`
knows what an answer answers. CTUI-12's connection has no relay: the tap
and the router see the raw message.

Options:

- **(A) Enrich on the ingress, in the session layer.** `onTraffic` runs
  `fromChord`/`fromAgent` and hands the inbox what comes out. Updates are
  enriched; but a permission request reaches `onPermission` raw through
  the dispatcher, so `toolCallFacts` (the one M1 enricher the interface
  draft wants for permissions) needs a second application in the bridge,
  reading the same `Wire`, and the record (later) would keep raw traffic
  where the original keeps enriched. Two places to keep in step.
- **(B) An optional `relay` on `openAgent`/`connectAgent`, at the
  original's place.** In `_framed`: `for (m in relay.fromAgent(message))
  { tap(m); route(m); }`; in the writer: `relay.fromChord(message)` before
  the tap. Additive: no relay means today's behaviour, and every CTUI-12
  test stands. One place, the original's.
- **(C) No chain in M1.** The reducer folds raw updates; `mergeToolCall`
  already keeps a title and kind across updates that drop them, so the
  loss is the permission box saying `Tool call` where an adapter's request
  omits title or kind, and `rawOutput` not shown as content (interface
  draft, table under Q3).

Recommendation: **(B)**, if the interface's enrichers are taken; (C) if
none is. A throw inside an enricher must not break the pipe: the relay
call is caught per message and the raw message goes on in its place
(fail open, nothing lost), and a test holds that. (B) touches CTUI-12's
fixed contract, so it is the lead's or the owner's call, not this team's
alone; see the owner questions.

## 4. Turns, queue, cancel, exit: the rules and every case

### The conversation's state, as the original's fields

`#session`, `#turn` (`{id, turn}` while a prompt runs), `#queued` (the
person's prompts in order, each with `afterAnswer` when held behind a
request between turns), `#settling` (the wait for a turn's trailing
updates), `#lastTurnId` (starts `'session'`), `#heardAt`, `#endedAt`,
`#sealed`, `#permissions` (the requests on screen, with `between`),
`#closing`. M1 leaves out messages (`from`), steers, tasks, monitors,
cycles, costs, the record, `#ahead`, notes and team parts; each is a later
field on the same class, and none changes the rules below for the
person's prompts.

### The rules, ported as they are

- **send(text)**: false before the session is up or once closing. Plays at
  once if nothing holds the queue (`#idle()`: no turn, no settling; the
  queue empty; no request waiting between turns), else queues it and emits
  `queued` (with `afterAnswer` if a request between turns holds it).
- **play**: emits `prompt` (the turn is `working` from now), calls
  `session.prompt`, awaits `turn.result`. The result never throws: the
  agent's answer gives `completed` with its `stopReason` or `cancelled`
  for `stopReason: cancelled`; a JSON-RPC error gives `failed` with its
  message and code; `AgentGone` gives `failed` with `The agent exited.` or
  `The agent exited: <tail>`. The client never invents a stop reason.
- **After the answer**: the turn is sealed. If prompts are queued, it stays
  on screen as running while `#quieten` waits for the agent to be silent
  `QUIET_MS` (1000 ms) after its last update, at most `SETTLE_LIMIT_MS`
  (5000 ms) in all, so trailing updates fold under their own turn and
  the queued prompt reads as waiting behind it. Then `result`, then the
  next queued prompt plays. With nothing queued there is no wait: `result`
  at once.
- **Stamping**: every update is folded under `#turn?.id ?? #lastTurnId`.
  An update after `result` therefore folds under the turn that just ended,
  never under the next prompt.
- **interrupt()** (Esc when busy and no permission is shown; ctrl+c in a
  form): the person's queued prompts are withdrawn (`queue_withdrawn`; the
  window puts their text back in the prompt box ahead of the draft, as
  `keys.ts` does); the turn is sealed and chord's own asks withdrawn. If a
  turn is running and not settling: `cancel` (the turn becomes
  `cancelling`, drawn `Interrupting…`), then `turn.cancel()`, which is
  `agent.cancel(sessionId)`. If the turn is settling: with the queue now
  empty the settle wait is aborted and `result` comes at once; no
  `session/cancel` is sent, as the agent has already answered.
- **cancelPrompt(turnId)**: a queued prompt is withdrawn alone; the running
  one is stopped as an interrupt stops it, the queue behind it untouched.
  Kept in M1 because CTUI-17's queue may take one prompt back; the
  interface decides whether a key reaches it.
- **choose(id, optionId) / reject(id)**: settle the request on screen
  (`permission_settled`), answer the bridge (`reject` picks `reject_once`,
  else `reject_always`, else `cancelled`, as `rejection()`), then
  `#release()`: an answered request between turns lets the queue go after
  the same quiet wait.
- **The agent going**: once `session.exited` settles and the conversation
  is not closing, `disconnected` is emitted under the current stamp.
- **close()**: `closing`; the settle wait aborted; chord's asks withdrawn;
  `session.close()` (CTUI-12's barrier and ladder). Nothing is emitted to
  the window after `close()` starts, as `StartConnection._dispatch` already
  does.

Do not cancel a turn through `agent.prompt`'s `cancellationToken`.
CTUI-12 defines that token as ending the local wait at once with the
token's exception and dropping the agent's answer; the original's
`Turn.cancel()` only tells the agent and keeps waiting for its answer, so
the turn ends `cancelled` in the agent's own words. The session calls
`agent.cancel(sessionId)` and never passes a token to `prompt`.

### The cases

Each row: what happens in the port, what the person sees (wording is the
interface draft's), and the test that holds it. "Fake" means the original's
fake agent through CTUI-13's harness; "memory" means `connectAgent` over an
in-memory `AgentProcess` writing exact bytes; "unit" means the
conversation over a scripted `Session` with `fake_async`, or the reducer
alone.

| # | Case | Outcome | Test |
| --- | --- | --- | --- |
| S1 | A prompt while a turn runs | `queued`; nothing goes to the agent; one turn at a time | unit; fake `slow` |
| S2 | Two queued, the turn answers | turn still drawn running until 1 s of silence (at most 5 s), then `result`, then the first queued plays; the second waits for that turn | unit (fake_async: 999 ms nothing, 1000 ms plays; a chatty agent: plays at 5000 ms) |
| S3 | An update after the answer, nothing queued | `result` at once; the late chunk folds under the ended turn, into the same reply (no ending entry for `end_turn`) | fake `late` (`late.jsonl`: the chunk comes 15 ms after the answer) |
| S4 | The same with a prompt queued | the late chunk stays with `late`, the queued prompt gets only its own; the original's `conversation_test` "a reply's chunks after the answer stay with it" | fake `late` then `text` |
| S5 | Esc during that wait | queue withdrawn, no `cancel` emitted and no `session/cancel` sent, `result` at once | fake `late` then `text`, the original's "an answered turn stays on screen…" |
| S6 | Esc on a running turn | `cancelling`; `session/cancel` queued; the agent answers `cancelled`; a `cancelled` entry | fake `slow`, fewer than 100 chunks after the cancel (`cancel-slow.jsonl`: the answer comes in the same millisecond) |
| S7 | A permission is shown and the person presses Esc | the window routes Esc to `reject`, not to `interrupt` (`state.ts`): the request is answered with its reject option and the turn goes on | fake `permission`, reject; the original's `session_updates_test` "a rejected permission request reaches the agent as its reject option" |
| S7b | ctrl+c (or `interrupt()`) while a permission waits | `agent.cancel` first answers the request `cancelled` (CTUI-12's fallback, enqueued synchronously), the bridge's token fires, the request is withdrawn (`permission_settled`, `withdrawn`); then `session/cancel`. On the wire the permission's answer precedes `session/cancel` | memory (byte order); fake `permission` then cancel, the original's "cancelling a turn withdraws its pending permission request" |
| S8 | The agent ignores the cancel | the turn stays `cancelling` (`Interrupting…`) with no timer, as the original and CTUI-12 (no request timeout). A second Esc sends `session/cancel` again and changes no state. New prompts queue behind it. Quitting closes: the ladder ends the agent, the prompt fails `AgentGone`, nothing is drawn after the close began | fake `ignorescancel` (`close-ignorescancel.jsonl`: no answer after the cancel; stdout ends only when stdin closes); the original's "closing comes back and kills an agent whose turn ignores its cancel" |
| S9 | The agent exits mid-turn | stdout ends, every waiting request fails; the prompt's result is `failed` with `The agent exited: <tail>`; `session.exited` settles and `disconnected` is emitted. The two may come in either order (both wait for the last words); the transcript ends the same either way: one error entry, the turn idle, the agent gone. Each queued prompt then plays and fails at once with the same words, one after another, each after the quiet wait | fake `crash` (`crash.jsonl`: `fatal: out of memory reading tests/parse/fixtures/huge.json` on stderr, stdout ends, no answer); unit: both orders of `result` and `disconnected` reduce to equal states |
| S10 | The agent exits between turns | `disconnected`; the next `send` draws the prompt and then `failed` with `The agent exited…` at once (`ask` checks the connection before writing) | memory (stdout closed while idle); the original has no fake case |
| S11 | The turn fails (`error`, `turnfailed`) | `failed` with the agent's message and code (`-32603`); the agent is still up (`gone()` null); the next prompt runs; a queued prompt is released | fake `error`, `turnfailed`; the original's "a failed turn says why, and the session takes the next prompt", "goose's turn_failed ends the turn failed…", "CHD-624 U3: failed turns release the prompt queue" |
| S12 | Ordering: the answer and its neighbours | updates before the answer are always folded before `result`; after it, either side, under the same stamp; the final transcript is the same | memory: one read holding `update, answer, update`, against three reads; equal transcripts |
| S13 | A throwing update (a `tool_call` with no `toolCallId`, `content` that is not a map, a `plan` whose `entries` is a string) | the conversation folds each update inside a `try`; on a throw the state stays as it was, the update is dropped, and an injected `onError` hears it (default: nothing). The next update draws | unit, and memory through the whole stack; CTUI-12's caught `onTraffic` is the second net, not the first |
| S14 | A throwing listener (a screen's) | the state is assigned before listeners hear it; one listener's throw does not stop the others and goes to the zone's handler | unit |
| S15 | Updates before `session/new` answers | held in `early`, routed after the answer is seeded | memory only: the fake never does this (CTUI-12, Q4) |
| S16 | An update for another session id | dropped | memory (the fake's `strayer` cases send none in M1's scenarios) |
| S17 | Updates before the first subscriber | handed to it in order inside `subscribe`; a second subscriber gets only live ones | unit; fake `text`: `available_commands_update` comes 7 ms after the answer (`text.jsonl`) |
| S18 | An unknown update kind, an unknown notification | passes the inbox, folds to the same state | fake `unknown` (`future_update`, `_fake/notice`) |
| S19 | A flood | each chunk folds in time proportional to the chunk, not to the reply so far (section 5); Esc stops it within the cancel's round trip | fake `flood` in the benchmark; cancel latency reported |
| S20 | Close mid-turn | the waiting permission answered `cancelled`, the prompt fails `AgentGone`, the group gone within the ladder; no state after close | fake `slow`, close after the first chunk; the original's "closing mid-turn ends the turn and the agent" |
| S21 | Close while opening | as CTUI-13: the opening token, a late open closed, not drawn | already CTUI-13's; kept |
| S22 | A permission left open as its turn ends (`leftask`, `mainbetween`) | it stays on screen, now between turns; queued prompts say they wait for the answer (`afterAnswer`); answering releases them after the quiet wait | fake `leftask`, `mainbetween` |
| S23 | Two requests at once (`twins`, `overlapask`) | distinct; oldest shown first; each answered alone | fake `twins`, `overlapask` |
| S24 | A request that arrives after `session/cancel` went but before the answer | gets a fresh token and is shown, as the original's transport does; the agent's answer to the cancel then withdraws nothing it did not already | memory |

## 5. Performance and memory

A literal port of the reducer's text fold is quadratic in Dart. JavaScript
concatenates strings as ropes; Dart's `a + b` copies. `appendText` does
`last.text + text` per chunk, and `appended`/`lastReplaced` copy the entry
list per update. Measured under `dart run` (`fold_cost.txt`):

| Fold | Literal port | Parts kept, joined once |
| --- | --- | --- |
| 10 000 chunks of 8 B into one reply | 17 ms | 0 ms |
| the fake's `flood`, 1 024 chunks of 64 KiB | 3 632 ms | 6 ms |
| 1 000 updates to the last of 10 000 entries, list copied each time | 51 ms | n/a |

3.6 s of the main isolate on one turn holds every frame and the cancel
that would stop it. 51 ms for a thousand updates between two frames at
10 000 entries is three frames. So, as a requirement on the framework
draft's state shape (Q4), not a shape of its own:

- folding one update costs time in the size of the update, amortised: a
  reply keeps its chunks (or an append-only buffer whose immutable
  snapshots share it) and is joined at most once per frame, when drawn;
- the entry list is a structure whose append and last-replace do not copy
  it (a persistent list, or an append-only backing with immutable views);
- the window is told of a change once per frame, not once per update; the
  reducer still runs per update, in order, synchronously.

A turn's text and the entry list grow for the whole session, as the
original's do; terminal output, if folded, is cut to the original's
`OUTPUT_LIMIT`. No isolate: decoding a 64 KiB line and folding it are each
under a millisecond once the fold is linear; the benchmark decides.

The benchmark, extending `example/chord/benchmark/acp_updates.dart` (no
terminal): the CTUI-12 runs (10 000 updates in one burst, 1 000 a second
for 10 s, the fake's `flood`) now folded through the conversation and
reducer into transcript state, reporting a 16 ms heartbeat's lateness, the
fold's time per update, Esc-to-`cancelled` latency during the flood, and
the heap after a 10 000-entry session.

## 6. Timers, subscriptions and who ends them

| Thing | Owner | Ended by |
| --- | --- | --- |
| the settle wait (`#quieten`'s timer) | `Conversation` | the wait ending, interrupt, `cancelPrompt` emptying the queue, close |
| `session.exited` listener | `Conversation` | fires once; ignored once closing |
| the inbox's subscription | `Conversation` | close |
| the bridge's subscription and each request's token | `Conversation`, `PermissionBridge` | an answer, the turn's cancel, `$/cancel_request`, `bridge.close()` in `session.close()` |
| the agent | `Session` | `close()`, CTUI-12's ladder; the forced way out through `owned` |

The conversation reads time through an injected clock (a `Stopwatch` by
default) and waits through `Timer`, so `fake_async` drives every quiet
wait in the unit tests; the fake agent's tests never wait on the 1 s quiet
except where the case is the wait itself (S4, S5).

## 7. Terminal output under `_meta` while nothing is declared (Q2, runtime side)

CTUI-12 wrote that with `_meta.terminal_output_delta` undeclared, command
output arrives "as a text block, once". That holds for some adapters and
not for others:

| Agent | Undeclared, a command's output comes as | Source |
| --- | --- | --- |
| Claude's adapter | a `content` text block at the end (a fenced `console` block) | `agent-capabilities.md` (`connection.ts` comment); the fake's `bash`: `bash.jsonl`, no `_meta` at all |
| droid, autohand | text, the whole output so far on every update | `agent-capabilities.md` dr26, ah12 |
| **Codex's adapter** | **`terminal` content naming an id, and the output only under `_meta.terminal_output_delta`, sent to every client** | `agent-capabilities.md` cx13 and the Zed convention; the fake's `shell`: `shell.jsonl`, five `terminal_output_delta` pieces with SGR colour, `\r` progress and an OSC 8 link, then `terminal_exit` with code 1 |
| **pi** | **`_meta.terminal_info`, `terminal_output` (a delta under the whole-output name), `terminal_exit`, sent to every client** | `agent-capabilities.md` pi10, pi22 |

The original's reducer folds these keys whatever was declared
(`transcript/tools.ts`, `foldTerminals`, through `terminal_text.ts`'s VT
parser). So on Codex and pi, an M1 that ignores `_meta` shows a command
call with no output at all, only its status. That is the interface draft's
owner question on terminal metadata; this is the evidence for it. The
choice changes the units: (B) brings `terminal_text.ts` (539 lines, a
VT500 parser state machine, constant memory per terminal) into M1, and
whether that parser is the framework's (`lib/src/text/` already reads
ANSI) or the port's is the framework draft's call.

## 8. The test plan

No test reaches a real model, agent or terminal. Every fake test runs the
original's fake through CTUI-13's finder, tagged `fake_agent`, skipped
with a reason when bun or the checkout is missing; every agent closed in
`tearDown` with `fakeStopBounds`, and its pid proven gone (the original's
`withSession`).

### What the harness needs

`startFake` installs the recorder as the only `onTraffic`. The session
layer opens its agent itself, so the harness gains a way to hand the
session's own `onTraffic` in beside the recorder (an `onTraffic` parameter
forwarded after `run.traffic.add`), and `openSession`'s injected opener
calls it. A fixture change, in the first unit that opens a session on the
fake.

### The original's tests, file by file

| Original | Port | Carried | Left, and why |
| --- | --- | --- | --- |
| `transcript/reducer_test.ts` | `transcript/reducer_test.dart` | prompt, chunks, thought, tool calls, plan, cancel, result in each status, `disconnected`, unknown kinds | subagents, compactions, notices, usage, modes, commands, shell, chord's calls, `self_started`, forks |
| `transcript/tools_test.ts` | `transcript/tools_test.dart` | merge, status only forward, title and kind kept, content and diffs, `rawOutput` | terminal cases only under 7(B) |
| `transcript/permissions_test.ts` | `transcript/permissions_test.dart` | requested, settled (chosen, rejected, withdrawn), oldest first, left open between turns | subagent and task waits, elicitations |
| `transcript/plans_test.ts` | `transcript/plans_test.dart` | the base `plan`, a finished plan moving into the transcript at the turn's end | `plan_update`, `plan_removed`, plan asks |
| `transcript/entries_test.ts` | `transcript/entries_test.dart` | all | none |
| `transcript/fold.ts` | `transcript/fold.dart` | helper | |
| `transcript/{chord,compactions,notices,shell,subagents}_test.ts`, `past.ts` | none | | non-goals |
| `permissions_test.ts` | `permissions_test.dart` | all but CHD-608's presentation block | permission review presentation (Codex Guardian, later) |
| `session_test.ts` | `session_test.dart` | a failed turn and the next prompt; exit mid-turn with its last words; a slow turn stopped by `turn.cancel()` and by `session.cancel()`; closing mid-turn; stray cancels counted (`cancels`); the scenario from the command line; closing kills an agent that ignores its cancel; an open given up | modes, models, options, mentions, MCP, fork, account, sign-in, Guardian, embedded resources, prompt suggestions |
| `session_updates_test.ts` | `session_updates_test.dart` | text in chunks, thought, a tool call's states under one id, an edit's diff, permission chosen, rejected, withdrawn by a cancel, a plan's entries, the task list env; `bashcut` both ways (Claude's lines for cut calls) | plans by id, proposals, compactions, usage and modes; the two terminal tests only under 7(B) |
| `conversation_test.ts` | `conversation_test.dart` | late chunks stay with their turn; an answered turn stays while a prompt waits and Esc takes it back; turn_failed ends the turn and the next runs; failed turns release the queue | starting model/mode/effort, sign-in, tasks, messages, steers, servers, close-during-start for models, records |
| `conversation_entries_test.ts` | none | | initial config entries: models are a non-goal |
| `enrich_test.ts`, `enrichers_test.ts` | same names | the relay's mechanics and the tests of the enrichers M1 takes | the other enrichers |

The conversation's unit tests over a scripted `Session` (the original
splits these between `conversation_test.ts` and its fakes) carry S1, S2,
S5, S8, S9 (both orders), S13, S14, S17 and S22 with `fake_async`, so the
quiet waits take no wall time.

### The fake's scenarios, and what each covers

| Scenario | Covers |
| --- | --- |
| `text`, `--no-usage` | chunks into one reply; the hold until the first subscriber |
| `thought` | thoughts apart from the reply |
| `todos` | the base `plan` (with `agentEnv`) |
| `tools`, `calls`, `edit`, `rewrite` | tool call states, content, diffs |
| `markdown`, `long` | long replies through the fold (CTUI-16 draws them) |
| `bash`, `bashcut` | Claude-style command output as text; cut calls |
| `shell` | Codex-style output only under `_meta` (7) |
| `permission`, `twins`, `overlapask` | answer, reject, withdraw; two at once |
| `leftask`, `mainbetween` | a request outliving its turn; the queue held behind it |
| `slow` then cancel, `cancels` | interrupt; stray cancels |
| `ignorescancel` | a cancel ignored, then close |
| `error`, `turnfailed` | failed turns, the session goes on |
| `crash` | exit mid-turn, last words |
| `late` (+ `text` queued) | trailing updates, the settle wait, Esc in it |
| `unknown` | unknown kinds and notifications |
| `flood` | the benchmark, cancel during it |

Cases no scenario plays stay in memory, as CTUI-12's owner chose for the
same kind (Q4): an update before `session/new` answers, an update for
another session, exit between turns, a request after `session/cancel`,
byte-level ordering (S12, S7b). No scenario is added to the original.

## 9. The units, in order

Each lands with tests that fail without it, and leaves `dart analyze`,
`dart format` and both test suites clean.

1. **Inbox.** `inbox.dart` and `inbox_test.dart`: `updateIn`, early
   buffer, seeding, exact-id `routed`, hold until the first subscriber,
   close. Pure; no process.
2. **Reducer, M1 kinds.** `transcript/` per the framework draft, with the
   carried transcript tests; the linear fold (section 5) proven by a test
   that folds the flood's size in bounded time, and the benchmark's fold
   run.
3. **Permission bridge.** `permissions.dart` and its tests; the window not
   yet involved.
4. **Session.** `session.dart` over the inbox and bridge: open, prompt,
   cancel, close, `gone`, `exited`, `agentEnv`; the harness's `onTraffic`;
   `session_test.dart` and `session_updates_test.dart` on the fake, the
   memory cases S10, S12, S15, S16, S24.
5. **Enricher chain** (if Q3 takes any): the relay per 3(B) or (A), the
   chosen enrichers, their tests. Before 4 if (B), as 4 opens through it.
6. **Conversation.** Send, queue, play, settle, interrupt, `cancelPrompt`,
   choose, reject, disconnected, close; unit tests with `fake_async` and
   `conversation_test.dart` on the fake.
7. **Benchmark.** `acp_updates.dart` folding through 6; numbers recorded in
   the handover.
8. **Terminal output** (only if 7(B)): `terminal_text.dart` (or the
   framework's), the terminal fold in `tools.dart`, the two terminal tests.

CTUI-16 to 19 then build on 6: the window replaces CTUI-13's
`StartConnection` with a conversation, and draws.

## 10. Answers

- **Q1 (lifecycle).** Keep `Session` (one connection, one ACP session) and
  `Conversation` (turns, queue, delivery) apart, as the original; the
  inbox is its own pure file under the session, at the place of
  `openSession`'s closures; `routed` and `SessionTree` ported unchanged
  with no subagents. `Session` keeps eleven members in M1 (section 1).
- **Q2 (runtime side).** Codex and pi send command output only under
  `_meta` whatever is declared; Claude, droid and autohand send text
  (section 7, with captures). An M1 that ignores `_meta` draws Codex's and
  pi's commands without output.
- **Q3 (runtime side).** The chain belongs where the original puts it,
  between framing and tap, through an optional `relay` on CTUI-12's
  connection (3(B)); fail open per message.
- **Q5.** The rules of section 4, as the original's: one turn at a time;
  a queue that waits for a turn's trailing updates (1 s quiet, 5 s at
  most) only when something is queued; Esc withdraws the queue and cancels
  through `agent.cancel`, never through `prompt`'s token; a permission
  shown takes Esc as a reject; a cancel ignored stays `Interrupting…`
  until the agent answers, goes or the person quits; an exit fails the
  turn with the agent's last words and then each queued prompt; late
  updates fold under the last turn; a throwing update is dropped alone.
- **Q7.** Section 8 and the units of section 9.

## 11. For the owner

1. **The enricher chain's place (touches CTUI-12's contract).**
   (A) enrich on the session's ingress and again in the permission bridge;
   (B) an optional `relay` parameter on `openAgent`/`connectAgent`, at the
   original's place, additive; (C) no chain in M1. Recommended: **(B)** if
   any enricher is taken, (C) otherwise.
2. **Terminal output under `_meta`** (the interface draft asks the same;
   this adds the evidence). (A) M1 ignores it, and Codex's and pi's
   commands show no output until the live terminal output task; (B) port
   the original's fold now (`foldTerminals`, `terminal_text.ts`), which
   reads the keys whatever is declared, and draw the last lines as the
   original does; declaring the capability stays the M3 task's. (C)
   declare `_meta.terminal_output_delta` in M1 too. Recommended: **(B)**:
   it is the original's reducer as written, it adds no capability, and
   without it M1 on Codex is visibly broken; (C) changes what Claude sends
   and reopens CTUI-12's staged decision.

Nothing else here differs from the original. The linear fold (section 5)
changes how state is kept, not what it holds or shows.
