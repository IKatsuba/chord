# CHD-573 protocol draft: `chord acp`

Proposals only: nothing here exists, and the six questions stay the owner's.
Line numbers are at this branch's head. SDK facts are from
`@agentclientprotocol/sdk` 2.2.0's schemas and `dist/`; trial facts are from
`../sdk-trial/output/`. Adapter facts are from `docs/agent-capabilities.md`, read
from their source, not run: live agents stay out of this design. "Not verified"
marks what I read past or could not establish.

**The owner's frame.** The design targets a client that declares `subagents` and
chord's extensions. Private extensions on top of ACP are the normal way. No refusal,
gate or text fallback is built for a client that declares less: it gets what plain ACP
carries, and the guide says so. Questions the owner has not answered stay options.

**The owner's principle.** chord absorbs every agent's specifics, and `chord acp` shows no
differences between agents. "This agent lacks X" is decided inside chord, reusing what the
window already does. See "What chord absorbs".

**Decided by the owner, 2026-11-02** (also on CHD-573's comments): Q1 agent A and team T4; Q2 A;
Q3 A; Q4 A with session id A; Q5 A; Q6's form, and its set without an agent list; T4's forms
including `/team list` and `/team new`, N1 and R1; V2; G3 A; G4 B. **Still open:** I1, G5 and
what else is marked as a recommendation below.

## The package in one page

- One `chord acp [agent]` process runs one agent runtime and one client
  connection, on SDK `agent({ name })` from `/unstable`, ACP v1 both ways.
- Each upstream session is one `Conversation` (`src/session/conversation.ts:399`),
  so it has what the window's has: the enricher chain, the record, the queue,
  chord's MCP server, tasks, teams. `openSession` alone, as `-p` uses it
  (`src/session/oneshot.ts:90`), has none of the last four.
- Session ids: the agent's for main (decided), a composite for a child. A second live
  session with the same id takes an alias, so no agent gets a limit ("Session ids").
- Modes, models and efforts reach a client one way, as config options ("Current state").
- A plan an agent asks about is an ask like any other ("By kind").
- What `initialize` says of images is open (I1): no draft assumes a probe.
- chord declares its full set downstream, as the window does, so a record is the
  same whichever client wrote it (G1, recommended).
- The client answers permissions and forms. Agents keep their own files and
  terminals.
- `session/list`, `load` and `resume` are chord's records, as `/resume` reads them.
- Everything is forwarded as it comes, a turn nobody prompted and a late update too.
- Teams by T4's commands; children and turn state by `subagent_update`, with
  `_meta["chord/agent"]`; two notifications and three requests for the rest (Q6).

Library gate, from the trial: `agent()` runs under Bun and compiled, and the
surface below needs no protocol helper. Three facts bind this draft: outgoing
messages are not validated, an unknown update kind goes out as sent; incoming
params are parsed, so `_meta` survives and unknown top-level fields do not
(`unknownKept: false`); `console.log` in a handler does reach stdout.

## Method table

"Static" means chord can honour it whatever the agent is.

### What the client calls on chord

| Method | v1 | Answer | Crosses to the agent |
| --- | --- | --- | --- |
| `initialize` | stable | yes; see below | nothing, or a probe `initialize` under option (c) |
| `authenticate` | stable | no, -32601; `authMethods: []` | nothing. `Agent` has no such call (`src/acp/connection.ts:114-206`); chord does not sign agents in (`src/session/sign_in.ts:2`). Gap G3 |
| `logout` | stable | no; not advertised | nothing |
| `session/new` | stable | yes | spawn, `initialize`, `session/new` (`session.ts:426,480`) |
| `session/load` | stable | yes, static; replays from the record | `session/resume` when recorded, else `session/load` (`session.ts:841`) |
| `session/resume` | stable | yes, static; no replay | the same |
| `session/list` | stable | yes, static; chord's records | nothing |
| `session/close` | stable | yes, static | `Conversation.close()`: stops the process. The record stays |
| `session/delete` | stable | no; not advertised | nothing. No code deletes a record today, and that is not this task's to start |
| `session/set_mode` | stable | yes, for a client that calls it; chord never offers `modes` | `Conversation.setMode`'s queue (`:2581`), never `Session` directly; see "Current state" |
| `session/set_config_option` | stable | yes, string values; `type: "boolean"` is -32602 | by the option: `Conversation.setMode`, `setModel` or `setOption`, each on its queue; answered with the whole `configOptions` after it |
| `session/prompt` | stable | yes | `Conversation.send`, bound synchronously; see "Turn ownership" |
| `session/cancel` | stable | yes | `Conversation.interrupt` (`:2350`), or `stopSubagent` for a child with `capabilities.cancel` |
| `$/cancel_request` | stable | a prompt's cancels that prompt alone | `Conversation.cancelPrompt`, new; see "Turn ownership". The SDK aborts the handler's signal (trial) |
| `session/fork` | unstable | no; not advertised | cut: `openSession` has `fork`, but the window's caller rules for a fork sit in `useSessions` (`src/ui/app/sessions.ts:3317`) |
| `providers/*` | unstable | no; not advertised | nothing |
| `mcp/message` | unstable | no | `acp` MCP transport not advertised, so never needed |
| `session/set_model` | not in the schema | no: not needed | an agent's own, used by `Session.setModel` (`session.ts:720-745`) behind the `model` config option every client sees (G4 B) |
| `_session/steering` | adapters' own | no; not advertised | G5, open |
| `_chord/agents/send`, `_chord/agents/close`, `_chord/monitors/stop` | chord's | yes, in next.2 | Q6 |

### What chord calls on the client

| Method | Sent | When |
| --- | --- | --- |
| `session/update` | yes | see "Traffic" |
| `session/request_permission` | yes | always; ACP has no capability for it |
| `elicitation/create` | yes | as asked. A client that answers with an error is `cancel` |
| `elicitation/complete` | yes | for a link forwarded |
| `fs/*`, `terminal/*` | never | Q3 |
| `mcp/message` | never | |
| `_chord/session/state`, `_chord/monitors/changed` | notifications, in next.2 | Q6 |

### v2, as far as it differs

Upstream v2 would be a translator, not a switch. From the schemas: no
`session/load` (`session/resume` takes `replayFrom`), no `session/set_mode`,
`auth/login` and `auth/logout`, no `fs/*` or `terminal/*` at all, `initialize`
takes `info` and `capabilities`, and updates differ (`state_update`,
`agent_message`, `tool_call_content_chunk`, `terminal_update`,
`terminal_output_chunk`). A prompt's answer inverts: the trial's v2 turn answers
`{messageId}`, then says `stopReason` in an idle `state_update`. See Q5.

## `initialize` both ways

### Upstream: the client's request

```json
{"protocolVersion":1,"clientCapabilities":{"elicitation":{"form":{}},"plan":{},"subagents":{},"session":{"compaction":{}}},"clientInfo":{"name":"x","version":"1"}}
```

chord keeps `clientCapabilities` for the connection and ignores `fs` and
`terminal`. An `initialize` repeated later is not re-read; the first set is what
sessions already opened on.

### Upstream: chord's answer

```json
{
  "protocolVersion": 1,
  "agentInfo": { "name": "chord", "version": "<manifest>" },
  "authMethods": [],
  "agentCapabilities": {
    "loadSession": true,
    "promptCapabilities": { "image": true, "audio": false, "embeddedContext": false },
    "mcpCapabilities": { "http": true, "sse": true },
    "sessionCapabilities": { "list": {}, "resume": {}, "close": {} }
  },
  "_meta": {
    "chord/acp": {
      "version": 1,
      "extensions": { "session/state": 1, "agents": 1, "monitors": 1 },
      "agent": { "name": "codex" }
    }
  }
}
```

What holds whatever the agent is: `loadSession`, `list`, `resume`, `close`, as chord
answers them. `audio` and `embeddedContext` are false ("Prompts").
`mcpCapabilities` is true for HTTP and SSE: chord takes both and `serversFor` holds
back what the agent does not, with a reason. That matters on Codex, where SSE
reaching it fails `session/new` (`cx24`); it is held back first.

**`promptCapabilities.image` is the one that does not hold.** Nothing establishes it
for an arbitrary runtime, and the example's `true` is option (b)'s. The lead has
recommended a static answer with no probe to the owner; the question (I1) is open.

| | What | Cost |
| --- | --- | --- |
| a | Static, conservative: `image: false` for every agent | true for all, and images are unavailable through `chord acp`, on Claude and Codex too (`cl11`, `cx12`) |
| b | Static `image: true`, with an owner-approved refusal per call: an image to a session whose agent does not take it is -32602 before it goes (`Session.takesImages`, `session.ts:236`). The real answer also goes on the session's answer, `_meta["chord/acp"].image` | false for some agents, against the schema's "the client adapts"; the failure is visible, never a silent drop, and costs one request. A client that reads the `_meta` avoids it |
| c | A bounded probe: `openAgent` then `close` (`connection.ts:241-259,455-464`), no `session/new` | one extra start per process, and a wait. Needs a bound: 15 s, named here as new, since `PROBE_MS` (`src/server/runtimes.ts:14`) is 60 s and would hold `initialize` as long. Needs a `cwd` before any session supplies one: the process's, with that directory's settings, so a session elsewhere can start another command (CHD-466). So it is a snapshot, and the real session can still differ, needing (b)'s refusal anyway. Possible only with one agent per process (Q1). On a miss or time-out, `image: false` and `_meta["chord/acp"].agent.error`, the real failure coming at `session/new` |

**Recommendation: (b), under the principle too: this is what the window does.** It refuses a
pasted image in the agent's name, "${agent} does not take images" (`src/ui/app/terminal.ts:281-285`),
reads an image's path only when `state.takesImages` (`src/ui/app/keys.ts:514,1038`), and learns that
from `prompt_capabilities` after the session opens, `true` until then (`src/ui/app/state.ts:1134`). So
-32602 with those same words is the window's refusal, and `_meta["chord/acp"].image` on the
session's answer is its `prompt_capabilities`: one field, the same shape for every agent, which
a client reads to hide its attach key. **It cannot be absorbed:** a model that cannot see an
image cannot be made to. The window invents nothing either, and sending the file's path instead
would be new per-agent behaviour.
(c) buys one field at the price of a start and a wait, and still needs (b)'s refusal;
(a) gives up images on the two agents that matter most.
`initialize` fails for no downstream reason under any of them. **Not measured:** a
cold `npx` start against a client's `initialize` timeout, which only (c) depends on.

### Downstream: G1, compared again

`CLIENT_CAPABILITIES` is a constant (`connection.ts:228`). The mirror existed so a
client that takes less would get each adapter's fallback. That is the protection the
frame removes, so:

| | What | For | Against |
| --- | --- | --- | --- |
| F | Chord's full set always, as today: no change to `connection.ts` | a record is the window's whichever client wrote it. droid's and pi's output stays whole on a later resume, as chord keeps asking for the delta (`connection.ts:222-226`, `dr12`). No option on `openSession`. One behaviour to test | a client that declares less loses what comes only by those kinds: a Codex plan arrives as `plan_update`, not reply text; with `terminal_output_delta` a Claude command's live output is under `_meta`, its output once at the end (`cl12`), in `content` where `rawOutputContent` finds `rawOutput` (`enrichers.ts:840`) |
| M | Mirror the client's | that client gets each adapter's fallback text | a record is as poor as the client was: a plan drawn as text in the window, droid's and pi's output as its last chunk on resume. An option through `openSession`, a second behaviour per adapter, read and not run |

**Recommendation: F.** Its loss falls only on a client outside the target, which gets what
plain ACP carries; M's falls on the record, for everyone, later. **Record consequence:** none.
Records stay byte-for-byte what the window writes, and droid's short output on resume is
gone as a loss. `session.configOptions.boolean` stays undeclared, as now
(`types.gen.d.ts:4093-4098,4126-4135`): `Session.setOption` takes strings, so a boolean
`session/set_config_option` is -32602.

## Traffic

Everything is read after the enricher chain. No new reducer action or state:
`chord acp` adds a pure mapper beside the reducer, not in it.

```ts
// src/session/upstream.ts, proposed; pure, tested by table.
upstream(event: ConversationEvent, at: { session, client }): Outgoing[]
```

The state it needs is small: client capabilities, the session table, the bindings of
"Turn ownership", the state last sent of "Current state", and pending asks by chord's
id, so a withdrawn ask can send `$/cancel_request`, which the trial's agent side can
send.

| Event from `Conversation` | Upstream |
| --- | --- |
| `update`, the session's own | `session/update` with the upstream id, the update whole, `_meta` included |
| `update` with `subagentId` | the same, under the child's composite id |
| `prompt`, `queued`, `result`, `queue_withdrawn`, `cycle_started`, `self_started`, `disconnected` | "Turn ownership" |
| `permission_requested`, `elicitation_requested` | Q2 |
| `permission_settled` with `withdrawn` | `$/cancel_request` for the pending request |
| `plan_requested` | `session/request_permission`; see "A plan ask" |
| `plan_settled` with `withdrawn` | `$/cancel_request` for the pending request |
| `connected` | answers `session/new`, `load` or `resume`; see "Current state" |
| `connect_failed` | error on the same; see Failures |
| `warned`, `failed` outside a turn | stderr always, and `notice`. Held-back servers also go on the answer as `_meta["chord/held_back"]`. A `failed` for a set the client asked is that request's error instead |
| `modes`, `model`, `options` | "Current state": `config_option_update` when the one shape moved |
| `commands` | nothing; the update was forwarded |
| `monitors` | `_chord/monitors/changed` (Q6) |
| `mode_asked`, `mode_answered`, `noted`, `closing`, `resumed`, `prompt_capabilities` | nothing: the window's |

I read `#updated` far enough to see the update emitted (`conversation.ts:3013`) but
not every path in it. **Not verified:** that nothing there holds or reshapes an update
the client needs.

### What is not sent

"Everything is forwarded" meets the schema in one place. It says an agent MUST NOT send
some kinds to a client that has not declared them: subagent updates ("the client must
advertise this capability before"), and notices ("MUST only send notices when the Client
advertised"). The frame's two sentences pull apart here: "everything is forwarded", and "gets
what plain ACP carries".

| | What | Effect |
| --- | --- | --- |
| V1 | Forward literally everything | no code. chord breaks those MUSTs for a client that declared less; a v1 client's SDK reports what it cannot parse as an error (`docs/decisions.md:2101`) |
| V2 | One check, the same live and on `session/load`: `subagent_update`, `session_message`, `session_message_chunk` and a child's traffic need `subagents`; `plan_update` and `plan_removed` need `plan`; compaction kinds need `session.compaction`; `notice` needs `session.notices`; a kind the v1 schema lacks never goes | conforms: that client gets what plain ACP carries. Dropping only, with no refusal, translation or text fallback. A loaded window record loses those kinds for it, as a live one would. The record keeps all of it |

**Decided: V2.** It is what "plain ACP" means, about ten lines by estimate, and no target client
ever meets it. Whichever is chosen, `available_commands_update`'s T4 merge is separate.

### By kind

- **Message and thought chunks, tool calls, `plan`:** whole.
- **Plans by id:** whole, under V2's check.
- **Terminal output:** `_meta.terminal_*` whole, as the reducer reads it: `terminal_output_delta`
  appends, `terminal_output` replaces (`src/session/transcript/tools.ts:176-183`). See "What chord
  absorbs".
- **Modes and config:** "Current state".
- **Commands:** `available_commands_update` whole until 1.0.0-next.2; under T4 the
  mapper merges chord's `team` and `new` into each root update.
- **Usage:** `usage_update` whole, `chord/filled` marking a cost chord worked out.
  `PromptResponse.usage` comes from `TurnResult.usage`, which is `tokensOf`'d
  (`session.ts:664`), and is mapped back field by field. Claude sends its cost at
  the turn's end (`cl20`), Codex sends none (`cx20`), so chord's estimate is what a
  Codex client sees.
- **Plans cursor and grok put to the person** (`src/acp/plans.ts:11`): an ask like any other,
  below ("A plan ask").
- **Late updates:** forwarded when they come, under the session (L).

### A plan ask

The window shows the plan and asks (`PlanBox`, `src/ui/app/App.tsx:1704-1721`), with choices by agent
(`src/ui/dialogs/plan.ts:17-27`), and writes the answer in that agent's words
(`planResponse`, `src/session/plan_asks.ts:16-39`). All of that already sits below the interface but
the choices. So `plan_requested` goes up as a permission, which every client can answer:

```json
{"method":"session/request_permission","params":{"sessionId":"…","toolCall":{"toolCallId":"<wait.toolCallId>","title":"<name, or Plan>","content":[{"type":"content","content":{"type":"text","text":"<overview, plan, todos and phases as markdown>"}}]},"options":[{"optionId":"accepted","name":"Yes, accept the plan","kind":"allow_once"},{"optionId":"kept","name":"No, keep planning","kind":"reject_once"}]}}
```

| Client answers | `answerPlan` |
| --- | --- |
| `accepted` | `{ type: 'accepted' }` |
| `kept` | `{ type: 'kept' }` |
| `left`, grok's third option, also `reject_once`, as `reject_always` could be remembered | `{ type: 'left' }` |
| `cancelled`, an error, an unknown id | `{ type: 'cancelled' }`, **never a yes** |

The labels move with `plan.ts`'s list. Its text is one small function, for every agent. The record
is the window's: `plan_asked` and `plan_answered` already (`src/session/record.ts:141-147`). **The one
loss:** the window's note on "keep planning" (`plan.ts:63`) has no place in a permission's answer.
An elicitation form could carry it, but not every client takes forms, and a note is optional in both
agents' answers (`plan_asks.ts:25-33`). The person's next prompt says it instead.

### Current state

**One shape, for every agent: config options.** Today's adapters differ: modes by a `mode` config
option or the older `modes` (`src/session/modes.ts:24-52`), models by a `model` option or the older
`models` with `session/set_model` (`src/session/models.ts:23-47`), efforts only by the `thought_level`
category (`src/session/efforts.ts:26`), and Codex's `set_mode` answers with nothing (`session.ts:751`).
Readers for all of it exist. So chord's answers and updates carry one `configOptions`, built by one
pure function from `AgentState`:

- the agent's select options, as `optionsFromConfigOptions` reads them (`src/session/config.ts:26-31`);
  boolean ones never, as the window shows none;
- an option `mode`, category `mode`: the agent's own if it has one, else made from `modesFrom`;
- an option `model`, category `model`: likewise, from `modelsFrom` (G4 B).

`modes` is never sent, and an agent's `current_mode_update` becomes a `config_option_update`. An agent that
offers no modes has no `mode` option: **a thing it lacks is absent, not differently shaped.**

**At start.** The answer to `session/new`, `load` or `resume` is built at `connected`, not from the
agent's raw answer: `#applyStarting` (`conversation.ts:2813`) may have moved the mode or model since.
`Session` keeps state raw in `AgentState` (`agent_state.ts:18-25`) and exposes it parsed, so it gains a
read of it, and of the answer's `_meta`. Updates heard before `connected` are written after the answer;
any already in it repeat an absolute value.

**After a set.** The mapper keeps what it last sent per session. On `modes`, `model`, `options` (`#report`,
`:2750-2782`) or any forwarded config or mode update it rebuilds the options, and sends
`config_option_update`, whole, only if they differ, marked `chord/filled` when chord made it and not recorded.
So an agent that changes config only in responses, one that answers `set_mode` with nothing, read back
by `modeReadBack` (`enrichers.ts:214`), and one that sends updates all look the same.

| Client asks | Answer | State arrives by |
| --- | --- | --- |
| `session/set_config_option` | the whole `configOptions`, after that op | the answer |
| `session/set_mode` | `{}`, v1's shape | `config_option_update` |
| refused | the agent's error on that request | nothing: state did not move |

**Who serialises.** `Conversation`, on its existing `#modeChanges`, `#modelChanges`, `#optionChanges` queues
(`:2590,2628,2657`). A handler never calls `Session.setMode` or its kin: that would overlap a queued change and
`#applyStarting`. `set_config_option` goes by the option: `mode` to `setMode`, `model` to `setModel`, which
each take both ways already (`session.ts:720-766`), others to `setOption`. The queues do not order against each
other, as in the window. Required change: the three methods return `Promise<void>` that rejects on refusal, keeping
today's events. The window's `failed` and `noted` for that op are dropped upstream.

### `_meta` to a client that did not ask

Forward it. `_meta` is the protocol's room for what the peer may ignore, the keys
are namespaced, and they say something true: `chord/filled` is the only way a
client can tell chord's cost estimate from the agent's. The keys become a surface
once sent: `chord/filled`, `chord/named_by_title`, `chord/subagent_draft`,
`chord/mcp`, `chord/guardian`, `chord/questions`, `chord/task`, `chord/spent`,
`chord/stopped`. **Say in `docs/guide.md` that they are informational and
unversioned.** A client reading `cost` without `_meta` takes an estimate for the
agent's figure. The alternative, stripping, costs a second pass and gains nothing.

### Session ids

**Decided: A.** ACP's ids are opaque, and each agent process issues its own (`session.ts:426,485`), so two
may return the same id, and a child's may equal a root's. Main's upstream id is the agent's (`Session.id`,
`session.ts:168`), so `session/list`, `load` and `--resume` name one thing, and the table's key is exact.
The id a client passes to `session/load` must equal the id `session/list` gave it.

**Under the principle, refusing a collision would give one kind of agent a limit others lack, and that can be
absorbed within A.** Today's choice was: a `session/new` whose id is live is an error, so an agent with
per-process counter ids (each first session `s1`) gets one session per `chord acp`. Instead such a session
takes an **alias**, `s1~2`: upstream only, in the table, never recorded, no format change. Every agent gets as
many live sessions. `session/load` or `resume` of a live id stays -32602, for every agent, as two processes on
one agent session are not known to work.

**What stays:** an alias is not listed and does not reload, as it is not in a record. But that agent's own records
already collide: `sessionById` takes the latest of a name (`src/session/sessions.ts:424-425`), and its id means
nothing to a new process. The window has this too. Which real agents do so was not surveyed. No owner question
is needed unless they want it named.

A **child gets a chord-issued composite id scoped to its main**:
`<main>/<child>`, with chord's child id (`src/ui/app/sessions.ts:1048,1571`), stable
over a clear (`src/session/AGENTS.md`), or the adapter's subagent id; a child's own
subagent is `<main>/<child>/<id>`. It is looked up exactly in the table, which holds its
`Conversation` and downstream id, and never parsed, so a `/` in an agent's id does no
harm. The mapper rewrites every id leaving: the notification's `sessionId`, a
`subagent_update`'s `sessionId`, a `session_message`'s sender and recipient, a
permission's and form's `sessionId`. On the way in, a `session/cancel` by composite id
goes to `stopSubagent` with the downstream id. Records hold downstream ids as now, and
replay composes them the same way. **Not verified:** how a task's relay names a nested
subagent; the rule is by whichever `Conversation` reports it.

A long-lived child or team member has no `subagent_update` today, since it has its
own row in the window. chord sends one on its immediate parent, with
`_meta["chord/agent"]` and `capabilities.cancel` (Q6); a task's exists already, with
`chord/task`. The schema fits: "reusable child sessions as restricted ACP sessions". These
are synthesised events the record does not keep, as it keeps no such child row now.

### Prompts

`Conversation.send` takes text, images and `mentions`, paths it walks itself
(`:1054`, `session.ts:647`). The client's blocks need a mapping:

| Block | Goes as |
| --- | --- |
| `text` | joined, in order, as `text` |
| `image` | `Attachment`, if the agent takes images |
| `resource_link` | a new `links` argument, sent as given. The schema makes it baseline, so a client may send it to any agent |
| `resource`, `audio` | `audio` and `embeddedContext` are not advertised; one sent anyway is -32602 |

`Recording.sent` takes `images` and `links` (`conversation.ts:255`), so the record
format is untouched.

A second `session/prompt` while one runs is queued, as the window's is, and answered
when its own turn ends. ACP's text assumes one at a time; a compliant client will not
see this, but one may, so each binding below is exact.

### Turn ownership

This table is the contract for runtime's `upstream_turns` (`drafts/runtime.md`), which
implements it.

**The problem.** `send` returns a boolean and mints its turn id inside
(`conversation.ts:1054-1077`), and `#enqueue` emits `prompt` or `queued` before returning
(`:2019-2050`), so a JSON-RPC request cannot learn its id. Take a monitor's turn running
with prompts A and B queued, and A then cancelled: guessing by arrival order answers the
wrong request.

**The binding.** In the `session/prompt` handler, with no `await` before it:

```ts
const turnId = crypto.randomUUID();

turns.bind(requestId, turnId);      // before send: send emits synchronously
if (!conversation.send(text, text, images, [], { turnId, links })) {
  turns.unbind(requestId);          // not up, or closing: sessionNotFound
}
```

**What changes on `Conversation`,** all additive:

| Change | Why |
| --- | --- |
| `send` takes an optional `turnId` and `links` | the binding; "Prompts" |
| `queue_withdrawn` gains `turnIds` | `interrupt` (`:2361-2373`) says only that some went |
| `cancelPrompt(turnId)`, new | one prompt alone: below |
| `setMode`, `setModel`, `setOption` return a promise | "Current state" |

**Cancelling.**

| Client sends | Target | What happens |
| --- | --- | --- |
| `$/cancel_request` | a queued prompt | `cancelPrompt` takes it out of `#queued`, nothing goes to the agent; answered `cancelled`. Others untouched |
| `$/cancel_request` | the running prompt | `cancelPrompt` does `interrupt`'s running half: seal, cancel plans, withdraw asks, `turn.cancel()`. The queue stays and runs next. Answered on its `result` |
| `session/cancel` | the session | `interrupt`, as Esc: every client prompt queued is withdrawn, the running turn cancelled whoever began it, a cycle ended. Messages stay queued and run after (`:2359-2363`), as in the window |
| either | a request already answered | nothing |

**Events and state.** Per session: `running`, `{ turnId, origin }` or none, and the
bindings. `origin` is `client`, `message` or `agent`. A state change goes as
`_chord/session/state` from next.2; before that the "state" below sends nothing.

| Event | Condition | Binding, state | Sends |
| --- | --- | --- | --- |
| `queued` | any | none | nothing. A row may repeat for a turn, as a steer's reasons change (`:1373`) |
| `prompt` | bound | running: client | state |
| `prompt` | unbound, no `into` | running: message | `user_message_chunk` with `_meta["chord/from"]`, state |
| `prompt` | `into` set: a message steered into a running turn (`:1535-1542`) | no change: it starts no turn and gets no `result` | `user_message_chunk` with `_meta["chord/from"]` |
| `prompt` | while a cycle is running | replaces it: a prompt takes a cycle over with no `result` for the cycle (`:3491-3493`) | as the rows above |
| `result` | bound | unbind, running: none if it was this turn | the request's answer: `stopReason` and `usage`, or the error for `failed`; state idle |
| `result` | unbound | running: none if it was this turn | state idle. Covers message turns and `#endCycle` (`:3129`) |
| `queue_withdrawn` | `turnIds` | unbind each bound | each answered `cancelled` |
| `cycle_started` | | running: agent, unless a turn runs; `#beginCycle` needs idle (`:3086-3092`) | state |
| `self_started` | a steer the agent took as a turn of its own (`:1501-1517`), cancelled at once | running: agent. It has no `result`: the held message's `prompt` follows and replaces it; if `interrupt` withdraws a taken one instead, `queue_withdrawn` with no turn running sets none | state |
| `cancel` | | none | nothing; the `result` says it |
| `disconnected` | | running: none. Bound and running: its `result` is `failed`. Bound and still queued: answered `sessionNotFound`, unbound | state idle |
| close, `session/close`, leaving | | every binding answered `cancelled` | |

A `result` waits out `#quieten` while anything is queued (`:3565-3567`), up to 5 s, so
A's answer can lag behind its turn with B behind it. **Not verified:** whether `#advance`
on a dead session plays what is queued, which the `disconnected` row answers first.

### L: traffic after a prompt's answer

**L1 holds: forward at once.** The prompt answers on the turn's `result`, and what the
agent sends later goes when it comes, as "Turn end costs nothing" decided
(`docs/decisions.md:2107`). L2 and L3 are gone, and with them any new holding of the answer.
`#quieten` stays only where it is today, behind a queued prompt (`conversation.ts:3565-3567`).
A client that declares the extensions files updates by session, not by prompt, and
`_chord/session/state` tells it what is running. The guide says plainly that updates may
follow an answer, and that a turn may start with no prompt pending, with asks in it.

A client that declares less may read a late chunk as the next reply, or not show a turn
nobody prompted; an ask between turns then holds the queue (`:3233-3250`) until
`session/cancel`. Those are the frame's accepted losses.

### `mcpServers` from `session/new`

`serversFor(agent, caps, userServers, chord, none)` (`servers.ts:50`) already does
what is needed. `chord acp` calls it with `userServers` =
`mergeServers(settings-and-.mcp.json, client's)`:

- **Precedence:** the client's are the nearest layer, as `mergeServers`
  (`src/mcp.ts:283`) has a later list replace an earlier one by name.
- **chord's own** still goes last, renamed `chord-2` if a client's takes the name.
- **`mcpServers: false`** for the agent holds back the client's too, with chord's.
- **Transport:** held back per `mcpCapabilities`, names and reasons kept, reported
  in `_meta["chord/held_back"]`. An `acp` transport server is refused -32602:
  chord does not bridge `mcp/message`, even for an agent that advertises it.
- **Load and resume** take the list again (`session.ts:852`).
- **Children** get the place's list today (`src/ui/app/sessions.ts:669`); I would keep the
  settings' only. A client's server goes to the session it named. **Open.**

`cwd` decides the settings and `.mcp.json` read, and differs per session where the
window has one `place`. Runtime carries that.

## What has no ACP method

| Feature | Today | ACP | Proposal |
| --- | --- | --- | --- |
| Start a child or task | `spawn_task`, `open_agent` tools | seen by `subagent_update`, none to start | the agent's MCP tools; `/new` (T4) |
| Team list, run, stop, show | `list_teams`, `run_team`, `/team` | none | T4: chord's own commands, from 1.0.0-next.2 if the owner confirms; the agent's MCP tools by words too. `_chord/teams/*` dropped |
| A person writes to a child | the window's row | `session/prompt` on a child is not granted: `SubagentSessionCapabilities` has `cancel` alone | `_chord/agents/send` (Q6) |
| Close, clear a child | tools, keys | `cancel` only | `_chord/agents/close` (Q6); clear by the tool, in words |
| Monitors | `monitor` tools; the `monitors` event | none | `_chord/monitors/changed`, `_chord/monitors/stop` (Q6). An event comes as a turn nobody prompted |
| Budgets | `get_budgets` | `providers/*` is not this | tool |
| `/mcp`, `/agents` lists | window; `list_agents` | none | `_meta["chord/held_back"]`, tool |
| Slash commands | `src/ui/app/commands.ts` | `available_commands_update` is the agent's list, and a command is prompt text | T4 adds `team` and `new`, merged on the way out. `/clear` is `session/new`, `/resume` is `session/list` and `load`, `/model` and shift+tab are config options. Any other text starting with `/` goes to the agent as typed |
| Turn state outside a prompt | the window's state | v2 `state_update` only | `_chord/session/state` |

Reason for the tools: a person asks main, as in the window, main calls them, and
`Caller` already gives `role: 'person'` (`src/server/tools.ts:71`). A question
`settings` or `propose_team` puts to the person goes `askPerson` then
`permission_requested` (`src/ui/app/sessions.ts:2703`), so it reaches the client like any
other.

## T4: chord's commands in the agent's list

The owner's option, not settled until they have this assessment. `chord acp` adds its
own commands to `available_commands_update`, takes such a prompt and runs it itself,
without sending it to the agent, in the window's forms. Asking in words still works. It
lands in 1.0.0-next.2 and reverses "chord's own slash commands are not added".

**Verdict.** It works, and ACP has the shape for it: a command is prompt text beginning
`/`. Four things do not hold as stated:

1. **A run leaves no prompt pending.** `/team run` answers once the run has started, and
   its work, asks and reports follow with none pending. That is U1; a client that declares
   the extensions follows it by `subagent_update` and `_chord/session/state`.
2. **`/new <agent>` opens an idle agent.** Its first prompt comes from a view chord acp does
   not have: from `_chord/agents/send`, or from main.
3. **The typed commands cannot stay on the window's side** of the hook, as interface's
   draft has them. CHD-580 grows.
4. **`/team show` has no text today,** and its running half reads window state.

### Which commands

| Form | In the window | Without a window | Proposal |
| --- | --- | --- | --- |
| `/team run <name> <job>` | `runTyped` (`src/ui/app/sessions.ts:3136`): the run `run_team` starts, main told by `aside` ahead of its next prompt | means the same. Needs `teamNamed` (`:3123`), `runTeamAt` (`:1679`), `Conversation` | **in** |
| `/team stop <run>` | `stopTyped` (`:3380`): closes the lead and members by `closeByPerson` (`:3049`) | means the same. Words change: "the list under the prompt" (`:3393`) and "/resume lists it" (`src/ui/teams/teams.ts:134`) name window things. The run's name comes from `/team run`'s reply | **in** |
| `/team show <name>` | `showTyped` (`:3415`) returns data that `SavedTeam` and `RunningTeam` draw (`src/ui/teams/Teams.tsx:90-110`) | saved team: its file, description, agents, as new text. A running one: job, lead, each agent open or not. Its state and headline read the window's `AppState` (`stateOf`, `:3774`, used at `:3490-3494`) with `agentState`, `agentMark` and `headline` from `src/ui/`, and its `receipt` branch reads main's transcript (`:3428`). No reducer state exists per child without a window | **in, reduced:** no state, headline or receipt in this milestone |
| `/new <agent>` | `newTyped` (`:3184`): a child on `open_agent`'s terms, `idle: true`, then `sessions.pick` and `showFront` (`:3218-3219`) go to it, and the person's first prompt in its view starts it (Q187) | opens the child; "goes to it" means nothing. There is no view, and ACP grants no prompt on a child (`SubagentSessionCapabilities` has `cancel` alone). It stays idle until `_chord/agents/send`, or main's `send_message`, which the `aside` tells main it can (`:3224`) | **in, as a choice below** |
| `/team`, `/team list` | a picker (`src/ui/app/commands.ts:235-241`) | not in the owner's forms, yet refusals say "/team lists them" (`teams.ts:120`, `sessions.ts:3152`) and a client otherwise cannot learn a name but by asking in words. Text from `listTeams` (`:3102`) | **recommended in** |
| `/team new <words>` | `sendToMain` with `newTeamPrompt` (`commands.ts:243`) | a prompt with a preamble. Not in the owner's forms | **owner's call;** without it, `teamCommand` needs a refusal in its place. Recommended in: the parser has it, and it is a normal turn |

**Decided: N1, as the window, an idle child; the reply says so.** `_chord/agents/send`
makes it useful, so `/new <agent> <words>` and leaving `/new` out are no longer needed.
"One agent per process" (Q1 A) must mean **main**: `/new codex` under a Claude main, and any
team file naming other runtimes, open children on other runtimes (`startRefusal`, `:551`).
If it means every agent, teams do not work.

The rest stay out: `clear` is `session/new`; `resume` is `session/list` and `load`;
`model`, `config` and shift+tab are config options; `fork` is cut; `cost`, `context`,
`status` read window state (`commands.ts:174-190`); `help`, `theme`, `vim`, `mcp`,
`exit` have nothing to act on. Those names go to the agent as typed, unlike in the
window.

Listed as ACP gives them, with an unstructured `input.hint`
(`types.gen.d.ts:3257-3265`):

```json
{"name":"team","description":"Show and run teams of agents","input":{"hint":"list | run <name> <job> | show <name> | stop <run>"}}
{"name":"new","description":"Open a new agent beside main","input":{"hint":"<agent>"}}
```

### A name both offer

The window: chord's wins and the agent's is left out of the list, "as listing both would
offer one that cannot be picked" (`src/ui/prompt/commands.ts:112-117`), and `submitted`
looks at chord's first (`:379`). The same rule fits, on two reserved names only, `team`
and `new`. A person cannot reach the agent's own `/new` through chord, as in the window.

**The merge survives every update because it is in the mapper, not in state.**
`foldUpdate` replaces the list whole (`src/session/agent_state.ts:55-58`), so an adapter's
later update would drop additions kept there. Instead, `AgentState.commands` and the
record stay the agent's own, and the mapper rewrites each root `available_commands_update`
on the way out: the agent's without the two names, then chord's. Three cases follow:

- **An agent that sends none:** chord sends its own list once the session's answer is
  written.
- **A child's update:** not merged, as a child takes no command.
- **Replay:** each recorded update goes through the same rewrite.

### How a result reads

In the `session/prompt` handler, before `send`: the blocks are read as "Parsing" below,
and a command never binds a turn.

```json
{"method":"session/update","params":{"sessionId":"…","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"Team bugfix started. Its lead is @lead-1; /team stop lead-1 ends it."},"_meta":{"chord/command":{"name":"team","failed":false}}}}}
{"id":7,"result":{"stopReason":"end_turn"}}
```

- **A refusal reads the same,** with `failed: true`, in `teamRefusal`'s or `open_agent`'s
  words. It is not a JSON-RPC error: nothing failed at the protocol's level, and the window
  too says it as a line under the command. It is not `stopReason: "refusal"`, which the
  schema defines as the agent's, with consequences for the next prompt.
- **No `user_message_chunk`, no usage:** no model ran. `_chord/session/state` does not
  move for the command itself; it does when the run's report starts a turn.
- **Chunks after the answer:** none. The reply is written before it.

**What the record holds today:**

| Command | Line | On resume |
| --- | --- | --- |
| the text typed | none: it never reaches `Conversation` | nothing |
| `run`, `new`, succeeded | `ran`, by `ranTyped` (`record.ts:1098`) | **draws nothing** (`conversation.ts:217-221`, `src/ui/app/state.ts:749`). It serves only to know which agents were left open (`record.ts:571`) |
| `stop` | `closed` (`record.ts:1100`) | the same |
| the line under it, a refusal, `show` | none: `team_shown` is dispatched straight to the window (`commands.ts:212`) | nothing |

`#add` also holds lines until the first prompt (`record.ts:1450`), so a session whose
only act is `/team run` writes no record: as in the window, but likelier for a client
driving by commands. `summaryOf` reads a `served` run receipt (`src/session/sessions.ts:139-146`),
not `ran`, so it stays unlisted too.

| | Replay | Effect |
| --- | --- | --- |
| R1 | As the window: `session/load` shows nothing of a command | no format change. A loaded session lacks those lines; the children's own records and the `aside` in main's next prompt stay |
| R2 | An additive record line for the command and its reply | replay is complete. A stored-format addition the window would ignore or start drawing |

**Decided: R1.** **Not verified:** whether `aside`'s wrapped text shows in a
replayed `prompt`; `recordActions` was not read for it.

### What stands in the way

- **Parsing.** The window's rule is `^/(\S+)(?:\s+([\s\S]*))?$` on the trimmed draft
  (`src/ui/prompt/commands.ts:377`), and the file imports `fzf` and the menu. chord acp needs
  that one regular expression, on the first text block, with only `team` and `new` taken.
  A prompt with other blocks beside the text gets a refused line: `/team run` takes words
  alone, and dropping an image silently would be worse. As in the window, literal `/team`
  cannot reach the agent. A client that sends a bare command name gets the `list` form.
- **During a turn: it runs at once, never queues.** The window gates only `send` on
  `context.submitting`; a chord command goes straight to `run_command`
  (`src/ui/app/keys.ts:482-507`). So a command overtakes queued prompts, and its `aside`
  reaches the next `send`, not one already queued (`conversation.ts:1066`). A compliant
  client will not send it while its own prompt is pending, so `/team stop` waits on that
  prompt, or on `session/cancel`; a turn nobody prompted does not block it.
- **Cancel.** `session/cancel` aborts a run still starting, as `interrupt` aborts launches
  (`conversation.ts:2355`), and does not stop a run: only `/team stop` does, as Esc does not
  in the window. **Not verified:** what `runTeamAt` returns on that abort; the reply is its
  error, or `cancelled` if the request was cancelled.
- **The job.** `/team run` refuses without one (`teams.ts:60-64`). It goes to the lead as
  its prompt, to main in `ranNote` by `aside`, and into the record in `ran`'s `input`.
- **Asks and reports, no prompt pending.** A lead's and member's asks come from their own
  turns, so they do not hold main's queue as a between-turns ask does. They reach a client
  under composite ids with none of its prompts pending. A lead's report starts a main turn
  (`origin: message`) that costs money.
- **The window side of the hook.** Interface's draft keeps the typed commands in the hook,
  and asked for this second look. They cannot stay: next.2 needs them with no React.

  | Goes to `agents_host` | Stays in the window |
  | --- | --- |
  | `runTyped`; `stopTyped` with `closeByPerson` less its `redraw`; `newTyped` with `pick` and `showFront` as a callback; `teamNamed`, `listTeams`; `showTyped`'s file and run data, about 340 lines (`:3049-3130`, `:3136-3237`, `:3380-3546`) | `forkTyped`; the state, mark and headline overlay on `showTyped`; every draw of `TeamShown` |

  The lead should square this with interface and runtime, whose host range ends at `:2542`.

### Where it falls

| Task | Milestone | T4's part |
| --- | --- | --- |
| CHD-574, CHD-576 | 1.0.0-next.0 | none. `/team` goes to the agent as typed, and changes meaning at next.2; the guide says so |
| CHD-579 | 1.0.0-next.1 | `teamCommand`, `ranNote`, `stoppedLine`, `teamRefusal` move out of `src/ui/teams/teams.ts`, which imports `@cliffy/table` and `../agents/glyphs.ts`, with their window words a parameter, as `runTeamAt` already takes `'/team lists them'` (`:3152`) |
| CHD-580 | 1.0.0-next.1 | **grows** by the table above, no behaviour change. Otherwise CHD-581 moves them, touching the window in next.2 against its "on the session layer" |
| CHD-581 | 1.0.0-next.2 | T4 itself: the parser, the merge, the replies, `show` and `list` as text. Its acceptance's "a client without the needed capability gets the approved outcome" becomes "what plain ACP carries" |
| CHD-575 | 1.0.0-next.2 | **not T4:** these are ACP's own commands, no extension. See "Milestones" |
| CHD-582 | 1.0.0-next.2 | verifies and documents the forms |

## Failures

| Case | Upstream |
| --- | --- |
| Agent command missing, refused | `session/new`: -32603 with `stepWords`, `failureLines` in `data` (`headless.ts:316`) |
| Agent needs a login | -32000 `authRequired` (`RequestError.authRequired`), its words and `signInLines` in `data`; `authMethods` empty, so the client tells a person what to run |
| Agent exits in a turn | the prompt: -32603 with its last words (`AgentGone`, `connection.ts:599`). `TurnResult.error.code` kept where the agent gave one. A `session/update` cannot say this |
| Agent exits between turns | next prompt: `RequestError.sessionNotFound`, -32002. `session/resume` on the id reopens it. `notice` if declared |
| A request after that, or to a closed session | `sessionNotFound` |
| Turn cancelled | `stopReason: "cancelled"`, as the schema requires. Asks are answered `cancelled` downstream by `Agent.cancel` (`connection.ts:545`), and chord sends `$/cancel_request` upstream |
| Client answers an ask with an error | `conversation.reject(id)`, which answers `rejection(options)` downstream (`permissions.ts:52`) |
| Client answers with an unknown `optionId` | validated against the retained options **before** `choose`; invalid goes to `conversation.reject(id)`. Catching is not enough: `choose` removes the ask and emits `permission_settled` as chosen first (`conversation.ts:2437,3423-3438`), and only then does `resolve` throw (`permissions.ts:135-137`), leaving the ask gone, downstream pending and a false answer recorded |
| Client never answers | waits, as the window does for the person; no chord timeout, and Claude and Codex have none (`cl14`, `cx14`). The SDK does not settle a pending request on cancel (trial: no answer in 1 s), so chord must not wait on the client: `Agent.cancel` answers downstream itself (`connection.ts:292-300,545`), and the turn ends on the agent's answer |
| Client's stdin ends with asks open | all withdrawn; runtime's shutdown |
| Update for a session closed | dropped |
| Starting model, mode refused | as the window: `failed` becomes a `notice` or stderr; `model` required fails `session/new` (`conversation.ts:2964`) |
| `load` with another `cwd` than the record's | -32602 naming the record's. The window refuses too (`src/session/sessions.ts:382`) |
| `load` of an id with no record | goes to the agent as `sessionById` does (`src/session/sessions.ts:419`) |
| An id of another agent's record | -32602: `ResumeError`'s words (`src/session/sessions.ts:434`) |
| Record cannot be written | `FileRecording.failed` becomes `failed`, so a `notice` or stderr; the session goes on (`record.ts:1206`) |

## What the record keeps

Nothing new and no format change: `FileRecording` hears what it hears in the window
(`src/ui/app/sessions.ts:530`). Prompts by `sent`, updates enriched, answers by the same
`permission_settled` and elicitation lines. Synthesised child `subagent_update`s
stay out, as noted: the record shows what the agent sent. **Recommended by Q4, not settled.**

## The owner's questions

### Q1. Which agent and which team, and who chooses

Established: a `Session` is one process and one agent (`session.ts:160`);
`CLAUDE_ADAPTER` and the cost tables key on the agent per session; `-p` takes it
from argv and settings (`src/main.tsx:337`). Nothing in ACP names an agent.
Teams are read on request and run by `run_team`; no start flag exists, only the
`teamSelection` setting (`main.tsx:495`) and the typed `/team run`.

| | Agent | Effect |
| --- | --- | --- |
| A | Fixed per process: `chord acp [agent]`, with `--agent-command` and settings' default as `chord` has them | the person who configures the client chooses; `initialize` option (c) stays possible; the list is one agent's |
| B | Per session: `_meta["chord/agent"]` on `session/new`, default from argv | extension; rules out `initialize` option (c); list across agents |
| C | A config option `agent` on `session/new`'s answer, set before the first prompt | native-looking, no extension; a change replaces the process and the session id, which `set_config_option`'s shape cannot say; a session is opened for nothing |

| | Team | Effect |
| --- | --- | --- |
| T1 | None chosen: main runs them by `run_team`, as asked in a prompt | no new surface; a person drives by words. Stays under T4 |
| T2 | `--team <name>` | a run per session, at start; new to chord; a job must come from somewhere |
| T3 | `_chord/teams/run` | a client button; an extension to keep |
| T4 | **The owner's, replacing T1 to T3:** chord's own commands in the agent's list, run by chord (`/team run\|stop\|show <name>`, `/new <agent>`); words still work. In 1.0.0-next.2 | see "T4" |

**The owner has answered agent A,** one agent per process, which must mean main: see
"T4". **On teams, T4 as the owner chose it.**

### Q2. Who answers a permission or an elicitation, and when the client cannot

Established: `-p` refuses all and declines forms (`oneshot.ts:109-130`), since
nobody is there. A `chord acp` client is someone. `session/request_permission` has
no capability, so every client can receive one; it may answer badly. A child's goes
to the person, never the parent agent (brief), and a task's comes in the parent's
session (`tasks.ts:5`). `PendingPermission` drops the request's `_meta`, and
`waitOf` keeps less than a form's request (`elicitations.ts:46`), so the forward
needs the raw request kept beside them, or `chord/questions` is lost.

| | Permission | Effect |
| --- | --- | --- |
| A | Forward to the client, always | the client is the person. No chord policy to bypass |
| B | A: plus `--dangerously-skip-permissions` and `--permission-mode` as `-p` has | the second is a starting value, which is safe; the first lets whoever writes a client's config allow all |
| C | Refuse as `-p` | a session that can do little |

With `subagents` declared, a child's request stays under the child's own id, as the
SDK's contract says it identifies the child "in all ACP messages"
(`types.gen.d.ts:3746-3750`); chord sends the composite. Without it, the ask cannot name a
session the client knows, and forwarding under the root id ties a child's `toolCallId` to
main's identity, with title and content perhaps absent (`types.gen.d.ts:140-144`).

| | Child's ask, no `subagents` | Effect |
| --- | --- | --- |
| A2 | `conversation.reject(id)`, and a stderr line | one branch in the mapper. The child's call is refused and the agent hears it; an ask can never wait unseen, holding a turn |
| A0 | Forward anyway under the composite id; an error answer becomes `reject` | no branch, but a client that ignores an unknown id never answers, and the turn waits on it for good |

**Recommendation: A2.** It is what is left with no special work. **A3 is gone** (chord's tools
open children for every client), **A1a is gone,** and **the shared refusal check is gone,**
with T4's table of outcomes.

Elicitation: forwarded raw, whatever the client declared. An error answer is `cancel`. A mode
chord does not know is cancelled already (`connection.ts:323`). An elicitation scoped to a
request, not a session, is cancelled: no request here is the client's.

**Decided: A. Recommended beside it: `--permission-mode` only, and A2.** A client that never answers holds
that one ask; `session/cancel` still ends the turn, by chord's own answer downstream (Failures).

### Q3. Whose filesystem and terminal capabilities

Established: chord declares neither (`connection.ts:218`). Claude's adapter has no
caller for `readTextFile` or `writeTextFile` (`cl24`); Codex's shows ✗ · ✗ in the
capability table. Others use them "if declared" (`docs/agent-capabilities.md:331`).
Draft v2 has no `fs/*` or `terminal/*` at all. Declaring them would make an agent's
edits go through the client, for agents that take it.

| | What | Effect |
| --- | --- | --- |
| A | chord's: none declared; agents use their own tools on chord's machine | as the window and `-p`. A client with unsaved buffers does not get them read. Client capabilities ignored |
| B | The client's: forward `fs/*`, `terminal/*` both ways, by session and child | a relay to write for methods v2 drops; `terminal` content changes under the reducer; no effect on Claude and Codex |
| C | Both: chord answers for a client that lacks them | chord becomes a file and terminal server: nothing gained over A |

**Decided: A.** Stdio means client and chord share a machine; unsaved
buffers are the one loss, and a client can put them in a prompt.

### Q4. Session list, load and resume, and the records

Established: chord's records are the store `/resume` reads (`src/session/sessions.ts:75,306`).
`reopen` prefers `session/resume` with a record, as it replays nothing, and draws
from the record (`session.ts:841`). `history()` gives a past as actions, recorded or
replayed (`:210`). Claude and Codex list too (`cl6`, `cx6`), and `-p` records
nothing.

| | Records | list | load, resume |
| --- | --- | --- | --- |
| A | On, as the window | chord's: `earlierSessions(records, { agent, cwd })`, `title` from `sessionLabel`, `updatedAt` from `lastUsedAt`; no `parent` | load: the record's past as updates, then the answer. resume: no replay. Downstream as `reopen` does |
| B | Off, as `-p` | forwarded to the agent | forwarded: tasks' work and senders lost, chord's cost estimates gone, `-r` in the window has no record |
| C | On, and merged with the agent's | two cursors merged; ids chord never saw | as A, else forward |

Under A, a session opened by `chord acp` opens in the window with `chord <agent>
-r <id>`, and the other way. Mapping `load`'s past: `prompt` to
`user_message_chunk`, `update` as live, the rest (`served`, `ran`, `asked`, `usage`)
dropped. Under V2 the same check applies as live. A task's work comes under its id from its own record
(`session.ts:493-500`). `disconnected` drops.

A's limits: every session in the list is by this runtime; `cwd` omitted means every
directory, as `/resume` scoped out; `nextCursor` is omitted and the whole list comes
in one answer, `readRecords` reading each file (`src/session/sessions.ts:75`, cost not
measured). Sessions the agent has that chord never recorded are not listed, but load
by id still reaches them. Two processes on one session: `earlierSessions` shows it
once; what an adapter does is unknown.

**Decided: A, with session id A.** The brief's "the window's are recorded and `-p`'s are not"
turns on whether anyone may come back to the session. Here they may.

### Q5. Which protocol version

Established: chord's client side imports `/unstable` and asks v1
(`connection.ts:459`). Claude's and Codex's adapters negotiate both; most other
agents v1 only (table `A1`). The README calls both v2 entrypoints experimental, and
`AgentProtocolRouter` `@experimental`. Trial: plain `agent()` answers 1 to 0, 1, 2
and 3, v2-shaped or not; a non-number is -32602. A v2-shaped client then decides
whether to disconnect, as the schema tells it. The full matrix is runtime's.

| | Upstream | Effect |
| --- | --- | --- |
| A | v1, full (`/unstable`), which is what a client that declares them needs | no translator. Unstable fields can change in any SDK release, and `2.2.0` is caret-ranged, so a move is a code change `bun check` should see |
| B | v1 stable entrypoint only | no subagents, `plan_update`, `usage`; chord's own client types are `/unstable`, and the migration guide says one entrypoint per app, with apps linked only over a transport allowed to differ |
| C | v1 and v2 by the router | a v1-to-v2 translator (see the table above): prompt answers invert, `load` goes, and the draft may change incompatibly in any release |

**Decided: A, downstream unchanged.** Revisit when v2 stops being a draft.
`_chord/session/state` is shaped to become v2's `state_update` then.

### Q6. Extensions: naming, versions, advertising, and this milestone's

Established: the v1 schema's extensibility is methods and modes beginning `_`, and
`_meta`. In use, `_session/steering` with `_meta.steering.supported` in `initialize`
(`connection.ts:584`); chord's `_meta` keys are `chord/<name>` (`enrich.ts:39-56`).
Trial: custom requests and notifications work on `agent()`; unknown methods get
-32601; a client ignores unknown notifications by the SDK's default. Others use their
own prefix (`_lody/*`, `_goose/unstable`; `x.ai/*` without the underscore).

**Naming. Decided:** `_chord/<noun>/<verb>`, matching `chord/` keys.

**Versions. Decided:** one integer per extension under `_meta["chord/acp"].extensions`; a
break takes a new integer, a method's new optional field does not.

**Advertising and declaring.** chord: `initialize`'s `_meta["chord/acp"]`, shown above. A
client: `clientCapabilities._meta["chord/acp"]` with `{ "extensions": { "session/state": 1,
"agents": 1, "monitors": 1 } }`, surviving the SDK's parse (trial). chord branches on nothing in
this milestone: it sends the notifications to every client, which ignores what it does not
handle (SDK default). The declaration is the version a future break selects on, and is
what the guide calls "a client that declares them".

**What a client needs to show and drive agents and teams.** From what the window does:

| The window | From | `subagent_update` carries | Missing |
| --- | --- | --- | --- |
| Name, role | `AgentRow` (`src/ui/agents/agents.ts:22`) | `title`, `description` | |
| Runtime, model, effort | `agentRows` (`src/ui/app/sessions.ts:3633`) | no | `_meta["chord/agent"]` |
| Nesting under a lead | `teamRows` (`agents.ts:243`) | yes: sent on the immediate parent, and a member's parent is its lead (`record.ts:48-52`) | the team's name, in `_meta` |
| Folding, order, picking, attention | `listRows`, `attend` | not protocol | the client's layout |
| Working, idle, asking | `agentState` (`agents.ts:87`) | `state`: `running`, `idle` with `stopReason` and `usage`, `requires_action` | |
| Exited, failed to start, a failed turn | `failureFor` (`agents.ts:70`) | `unknown` at best | `_meta`: `gone`, `failed` |
| Closed | `closed` in `WindowAgents` | no: "idle does not terminate the child", and no field ends one | `_meta`: `closed` |
| Unseen marks | `AgentWait.unseen` (`src/session/waits.ts`) | what the person has seen is the client's | |
| Elapsed times | `formatElapsed` | the client's clock, from arrival | |
| Tasks in the background list | `taskItems` (`src/ui/background/background.ts:220`) | yes, with `chord/task`, `chord/spent`, `chord/stopped` | |
| Monitors in it | `monitors` event (`conversation.ts:232`) | no | a notification |
| Stop a monitor | `stopBackground` (`sessions.ts:2927`), `stopMonitorIn` | no | a method |
| A person writes to a child | `send` (`sessions.ts:3800`) | no: a child's prompt is not granted | a method |
| Stop a child's turn | keys | `session/cancel` with `capabilities.cancel` | |
| Close a child | `closeByPerson` (`sessions.ts:3049`) | no | a method |
| Clear a child | `clearChild` (`sessions.ts:2327`) | no | **cut:** `clear_agent`, in words |
| Main's turn state with no prompt | | `state` is for children | a notification |
| Team run, stop, show, list; `/new` | | | T4 |

**The set, decided without an agent list.** Two notifications, three requests and `_meta["chord/agent"]`:

```json
{"method":"_chord/session/state","params":{"sessionId":"…","state":"running","origin":"message"}}
{"method":"_chord/session/state","params":{"sessionId":"…","state":"idle"}}
{"method":"_chord/monitors/changed","params":{"sessionId":"…","running":[{"id":"m1","description":"…","command":"…","startedAt":0,"timeoutMs":0,"events":2}],"ended":[{"id":"m2","…":"…","end":{"kind":"exit","code":0},"endedAt":0}]}}
{"id":1,"method":"_chord/agents/send","params":{"sessionId":"<main>/<child>","prompt":[{"type":"text","text":"…"}]}}
{"id":1,"result":{"delivery":"sent"}}
{"id":2,"method":"_chord/agents/close","params":{"sessionId":"<main>/<child>"}}
{"id":2,"result":{"closed":["lead-1","tester"]}}
{"id":3,"method":"_chord/monitors/stop","params":{"sessionId":"…","id":"m1"}}
{"id":3,"result":{"id":"m1","events":2}}
```

```json
{"sessionUpdate":"subagent_update","sessionId":"<main>/<child>","title":"tester","description":"…","state":{"state":"running"},"capabilities":{"cancel":{}},"_meta":{"chord/agent":{"runtime":"codex","model":"…","effort":"…","team":"bugfix","role":"member","gone":"exited","failed":"…","closed":true}}}
```

- **`state`** takes ACP's own words, including `requires_action` on an open ask, and goes
  for main alone; a child's is on its `subagent_update`. It is chord's derived from the same
  table as "Turn ownership": `prompt` running, `result` idle, an ask `requires_action`.
- **`send`** is the person's prompt to that child, the blocks mapped as "Prompts", answered
  `sent` or `queued` at once; the turn is seen by `subagent_update`. It takes no turn binding.
  Unknown or closed: -32002.
- **`close`** answers what it closed, a lead's members with it, and says so by `closed` on each.
- **`monitors/changed`** is the event as it is, whole, per session, composite ids for a child's.
- **No list of agents, and no changes notification.** One connection, one process: a client
  has seen every announcement since the session began, and `subagent_update` already is the
  change. It would only restate them.

| | Set | Effect |
| --- | --- | --- |
| 0 | None; `_meta` only | children are seen but not written to or closed but by words; no turn state, no monitors |
| 1 | The set above | **decided:** the window's list and background, driven |
| 2 | 1, plus `clear`, `_chord/teams/*`, an agent list | duplicates T4 and the announcements |

**The record: nothing new.** All of this is derived from events, and no extension's data is
written. A child's own record stays under `parent` (`record.ts:48-52`), monitors'
history in `served` calls as today.

**On `session/load`:** nothing is running, so no `state` but idle and no monitors. A task's
work replays as `subagent_update` and its traffic, from the record, as in the window. A
long-lived child's past does not replay: its `subagent_update`s are not recorded and it is not
running. It is named on the answer as `_meta["chord/left_open"]`, from `LeftOpen`
(`record.ts:565-585`), as the window's `leftOpenLine` says (`agents.ts:1068`), and the
agent is told as in the window. Drawing those pasts would be `childPasts` (`session.ts:496`)
synthesised into announcements: cut.

## Other gaps, same form

- **G1. Full set downstream.** Above; recommend F.
- **V. What is not sent. Decided: V2.**
- **G3. Sign-in. Decided: A.** No agent sign-in through the client; the error says what to run.
- **G4. `session/set_model`-only agents. Decided: B,** by "Current state".
- **G5. Steering. Open; the owner will be asked.** The window: Tab sends the oldest queued prompt into the running
  turn (`steerQueued`, `conversation.ts:1156`), where the agent advertises it (`#steerable`, `:1228`); otherwise it stays
  queued and the status line says why. Agents differ: `_session/steering` on Claude and Codex, own methods or refusals
  elsewhere, and on gemini and cursor a second prompt would kill the first (`ge13`, `cu15`), which the queue already absorbs.

  | | What a client sees | Effect |
  | --- | --- | --- |
  | S1 | Prompts only. Every agent queues; no steer at all | uniform and no work. On Claude and Codex a person cannot steer. Other agents' messages are still steered inside chord, by `tell` |
  | S2 | `_session/steering` where the agent offers it | a difference shown, against the principle |
  | S3 | `_chord/session/steer` for every agent: `{"delivery":"sent"}` into the turn, or `{"delivery":"queued"}` as the next, through `send` then `steerQueued` | one call, reusing the window's path. **The timing still differs:** only the answer's word says so. A queued one then starts a turn with no request waiting: an unbound `prompt`, `origin: client` |

  **Recommendation: S3.** It is the window's Tab with no new per-agent code, and the true word is what cannot be
  absorbed: an agent with no steering cannot take words mid-turn. `steerQueued` takes the oldest of the person's queue,
  so a bound `session/prompt` queued ahead would go first: S3 must steer its own entry, a small change there.
  Extension, so CHD-575. S1 is the fallback, if the owner wants fewer extensions.

## What chord absorbs

Everything else where an agent's difference could reach a client. "Same" means every agent, one shape, reusing what exists.

| Item | The window today | The client sees | Verdict |
| --- | --- | --- | --- |
| Images | refuses by name (`terminal.ts:281`) | I1 | **cannot:** a model's sight |
| Steering | G5 | G5 | timing only |
| Plan asks | `PlanBox` | an ask | absorbed, less the note |
| Counter ids | collide in records | an alias | absorbed live; records as today |
| Modes, models, effort | `modesFrom`, `modelsFrom`, `effortsFrom` | config options | absorbed. Names and values stay the agent's; an agent offering none shows none |
| Cost | `costFromTokens` (`enrichers.ts:63`) estimates from tokens and price, `chord/filled` | `usage_update.cost`, same | absorbed where tokens exist |
| Window size | `windowFromModel` (`:130`) | `usage_update.size`, same | absorbed where the model is known |
| Usage itself | nothing on cursor or droid (`dr20`, `docs/agent-capabilities.md:317`) | no `usage_update` | **cannot:** the data does not exist. As the window |
| Tool titles, kinds, output | `toolCallFacts`, `rawOutputContent` (`:162,840`) | same | absorbed as the window does; a `rawOutput` an agent omits stays absent (`ge9`) |
| Forms' questions | five readers into `chord/questions` (`:466-705`) | `_meta`, same | absorbed |
| Commands | agent's list | T4's merge sends a list even from an agent that sends none | absorbed. The list's content stays the agent's |
| Sign-in | `asSignIn`, by the protocol's code alone (`sign_in.ts:63`), `signInLines` | -32000, chord's line after the agent's words | absorbed in shape; the agent's words stay its own. An agent failing another way gets `startFailed`'s, as the window |
| Subagents, shape | `subagentShape` (`:321`) makes Cursor's and older Codex's draft `subagent_spawned` standard | `subagent_update`, same | absorbed |
| Subagents, state words | a draft's `completed`, `failed`, `cancelled`, `disconnected` kept, read by `subagentStateOf` (`transcript/subagents.ts:621`) | the mapper turns them to ACP's `idle` or `unknown`, with `_meta["chord/agent"].failed` | absorbed, one small map |
| Subagents, naming | `chord/named_by_title` on Claude's (`enrich.ts:39`) | `_meta` forwarded | shape same; a client wanting the task reads that key |
| Subagents, stamped | Claude stamps children into its parent only without `subagents`; chord always declares it (F) | never arrives | absorbed by G1 F |
| Subagents, none | gemini, droid, dirac and goose run them as one call (`dr19`, `ge14`, `di19`, `go20`) | one tool call | **cannot:** the agent does not expose them. As the window. chord's own tasks and children are the same on every runtime, which is the real answer |
| Other private kinds | grok's and dimcode's own notifications, unread (`gr19`, `dm19`) | nothing, under V2 | dropped, as the window |
| `session/resume`, `load` | `reopen` picks (`session.ts:841`), record draws | both offered, same | absorbed. **Cannot:** an agent with neither cannot continue a conversation it alone holds; the window's "cannot resume" words |
| MCP transports | `serversFor`, `heldBackLine` (`servers.ts:50,125`) | `_meta["chord/held_back"]`, `notice`, stderr | same shape. **Cannot, by reuse:** chord's server is HTTP, so an agent without HTTP has no chord tools (`pi19`), though T4's commands still run. A stdio bridge is new code: cut |
| `resource_link` | sent as given | same | absorbed: each adapter reads it its own way, unseen by the client (`cl11`, `cx12`, `pi9`) |
| Audio, `embeddedContext` | window sends neither | false for every agent | uniform at the lowest; nothing to absorb |
| dimcode's notice | `NoticeGate` (`src/ui/app/sessions.ts:393-395`), a box; `-p` says it on stderr (`oneshot.ts:169-179`) | `notice` and stderr, once, from `dimcodeAtRisk` and `DIMCODE_WORDS` (`src/notices.ts:18,51`). A dismissal honoured; none made, as there is no key | existing per-agent code. It warns of approvals bypassed, so it must not be lost |
| Terminal output | reducer folds both keys (`tools.ts:176-183`) | `_meta` as sent, read one way | **not absorbed, by the owner's earlier choice:** pi's deltas under `terminal_output` show as the last chunk, in the window too (CHD-456, `connection.ts:222-226`); droid gives text at the end. Fixing either is per-agent code that the window lacks |
| Permission options | agent's list | the agent's list | **cannot:** which options exist is the agent's. `rejection` works on any (`permissions.ts:52`) |
| What cancel stops | Claude foreground only (`cl17`), droid the turn | `stopReason: "cancelled"`, same | shape same; background work is the agent's |

## Cut

Fork, delete, providers, steering, `authenticate`, `_chord/teams/*` (T4 takes their place), a `session/list`
cursor, merged agent lists, `additionalDirectories` and `systemPrompt` (no `Session`
path, not advertised), client `_meta` on `session/new` (not forwarded: chord's
`openingMeta` is what goes).

## Tests, protocol's side

Runtime owns the plan. These reach no real agent:

- `tests/session/upstream_test.ts`: the mapper by table, each event; V2's check by capability.
- Replay: a window record loaded, the same check holding; `left_open` on the answer.
- Ids: two processes both returning `s1`; nested duplicates under two children and two
  mains; loading one id twice; a cancel by composite id reaching the right child.
- Turns, each with distinct request ids (`tests/acp/upstream_turns_test.ts`, against
  the table): a monitor's turn with A and B queued, then `$/cancel_request` on A; on B;
  `session/cancel` withdrawing both; the running prompt cancelled alone with B going on;
  a cycle taken over by a prompt, and ended by its marker; a message steered into a
  client's turn, one refused, and `self_started`; the agent gone with one running and
  one queued; `send` returning false.
- A plan ask (`cursorplan`, `grokplan`): each option mapping to `answerPlan`; a cancelled, erroring or
  unknown answer never a yes; withdrawn with its turn; in the record as the window's.
- One shape: an agent with legacy `modes` and `models`, one with config options, one that answers
  `set_mode` with nothing, each giving the same `configOptions`; setting a made option by id.
- A second session returning a live id takes an alias, and both route; `load` of a live id refused.
- A draft-shaped subagent's words reaching a client as `idle` or `unknown`; dimcode's notice once.
- Permissions: a child's ask with `subagents` under its composite id; without, A2 settling
  downstream with a stderr line.
- An unknown `optionId`: settles downstream as a rejection, and records only that.
- Traffic after an answer: delayed cost and content forwarded in order; an unsolicited turn with
  a permission, and `_chord/session/state` around it; an agent cycle.
- Extensions: each method and notification, on the fake agent's team scenarios; `send` to an idle
  `/new` child; `send` and `close` on a closed or unknown id; a lead's close taking its members;
  `subagent_update` carrying `gone` and `closed`; a client ignoring them all still whole.
- Current state: an agent that changes config only in responses, after `set_mode` and
  `set_config_option`; a startup mode or model override reflected in the answer; an
  update heard before `connected` written after the answer; a refusal moving nothing;
  a set during a running start, ordered by the queue.
- `initialize`, per the option chosen: under (b), an image to an agent without them is
  -32602 and the answer's `_meta` agrees. Under (c), a missing probe, a hung one at its
  bound, and a real session's capabilities differing from those advertised. All on the
  fake agent.
- Both sides on fixtures: a scripted ACP client over `chord acp --agent-command` on
  the fake agent. Scenarios exist for most of it (`permission`, `form`, `link`,
  `plan`, `cursorplan`, `compact`, `costwaitlate`, resume and load).
- Record round trip: a session by `chord acp`, opened by the window's `recordActions`;
  a window session listed and loaded by `chord acp`; a pre-existing record fixture.
- `serversFor` with client servers: precedence, `chord-2`, `mcpServers: false`.
- T4: the merge surviving a later adapter update, an agent that sends none, and a name
  both offer; each form's reply and refusal; a command during a running turn overtaking a
  queued prompt; a prompt with an image beside `/team run`; a run's asks and report with
  no prompt pending; nothing of a command replayed by
  `session/load`; a session whose only act is `/team run`, unrecorded as in the window.

## Removed under the owner's frame and principle

Each of these existed only to protect a client that declares less, and has left this draft:

- U2's table, and U1 to U3 as options: U is U1.
- L2 and L3, and any holding of an answer for quiet.
- `held` for `LEFT_MONITORS_TOLD`, and its `Conversation` change.
- Interrupting an agent's own cycle, dropping its updates, rejecting its asks.
- Rejecting asks between turns.
- The section "What a client can rely on", with its guarantees.
- The mirror: its table, the option on `openSession`, the client's `terminal_output_delta`
  key, droid's and pi's loss, the fake agent's mode for an undeclared capability.
- The outbound gate as a design part: its boolean filter, its `{}` replay test. V2 is what
  may remain of it, and is the owner's.
- The notices gate as a fallback: stderr always, `notice` under V2.
- `-p`'s form fallback for an undeclared elicitation mode; only an error answer's `cancel` is left.
- A3 and its tools' refusals, A1a, and the shared refusal check.
- T4's "Clients without children": its outcome table, refused lines, the narrowed list and hint.
- N2 and N3 for `/new`, as `_chord/agents/send` makes the window's form useful.
- The fixture client that finishes its prompt UI at the result, as a guarantee: it stays as a
  traffic test only.
- The clients' declaration as a switch: chord reads it for nothing in this milestone.
- Answering every plan `cancelled`: replaced by "A plan ask".
- Refusing a `session/new` whose id is live: replaced by the alias.
- `modes` upstream, and `current_mode_update` as a separate way.

## Milestones

**The principle's items fall in CHD-574,** as a plain session of any agent shows them: one
`configOptions`, the plan ask, the alias, subagent state words, dimcode's notice.

**1.0.0-next.0, CHD-574 and CHD-576: no extension.** A plain session runs no chord children, no
chord MCP server and no monitors, so the sources of a turn nobody prompted are only an agent's own
cycle (`session.ts:257`), whose updates are forwarded. `_chord/session/state` would add little
there; `subagent_update` for an agent's own subagents is plain ACP, with composite ids. So the
turn table runs with its "state" sending nothing, and `initialize` advertises no extensions.
CHD-576's body asks for "a public reference for the extensions": at next.0 the guide says there are
none yet; the reference moves to CHD-582, which has it too. V2's check, if chosen, is in CHD-574.

**1.0.0-next.1, CHD-579 and CHD-580: no change from the extensions.** `send` uses
`Conversation.send` on the child, `close` is `closeByPerson`, already in T4's move, and
`monitors/stop` is `stopMonitorIn`, in `src/session/` (`window_monitors.ts`). T4 still grows
CHD-580 by about 340 lines. **The window side of that is still to square with interface and
runtime.**

**1.0.0-next.2.**

| Task | Holds |
| --- | --- |
| CHD-581 | chord's MCP server, children, teams; `subagent_update` for long-lived children with `_meta["chord/agent"]`, because children cannot be seen otherwise; T4 |
| CHD-575 | `_chord/session/state`, `agents/send`, `agents/close`, `monitors/changed`, `monitors/stop`, and `session/steer` if the owner takes S3; advertising; `left_open`. **Waits on CHD-581,** which the board does not say: it waits only on CHD-574 |
| CHD-582 | the extension reference, the guide's "a client that declares them" and what plain ACP carries, the compiled binary. Waits on CHD-575, as it does |

## Unmeasured, and open

- A cold agent start against a client's `initialize` timeout, under option (c) only.
- `initialize`'s `image`: open with the owner.
- Whether any agent chord runs issues per-process counter ids: now only about their records.
- Whether `#advance` plays what is queued on a dead session.
- What `runTeamAt` returns when `session/cancel` aborts a run still starting, and how a
  replayed `prompt` shows `aside`'s text (T4).
- `readRecords` cost on a large store, for `session/list`.
- Two processes on one agent session.
- Whether a child's client-supplied MCP servers should follow it (the `mcpServers`
  section).
- I1 and G5: for the owner.
- Whether `Conversation` holds any update `#updated` should pass (Traffic).
