# CHD-485 protocol draft: the built-in agent's side

The protocol architect's draft for the brief's Q1 (with runtime), Q3 and Q6,
sign-in in each Q1 option, MCP and chord's own MCP server, records and
models, with the protocol's part of Q7 (cost and the context gauge). Nothing
here settles an owner question: each has options, evidence and a
recommendation.

Revision 1 answers the critic's findings 1, 5, 6, 7, 8, 10, 11 and 16 and
the note on tool ids: section 6's open-turn rule (new trial, F16), section 2's
three Q1 options, section 3's S2 evidence and the CHD-435 question, section 2a
on cost, gauge and retries, section 4's name allocation, and F6, F7 and F11.

Read: the brief, `AGENTS.md`, `src/session/AGENTS.md`, `docs/decisions.md`
(chord's own ACP layer, resume on chord's record, M4, chord's MCP server,
CHD-573 to CHD-581, CHD-575), `board show CHD-485` with its comments, and
`gate.md`. libfx 0.0.16 was read from `npm pack libfx@0.0.16` (paths below
are inside that package). ACP from `@agentclientprotocol/sdk` 2.2.0 as
`bun.lock` pins it.

Run: scripts in a scratch project under `/tmp` (libfx 0.0.16 and
`@modelcontextprotocol/sdk` 1.x installed there), Bun 1.4.4, darwin-arm64,
from source. Every model request went to a fake OpenAI Chat Completions
server on `127.0.0.1` through libfx's custom provider; no real provider,
sign-in or model was reached. The fake asks for one host tool, then answers
`done`, with a `usage` chunk each time, and counts its requests.

## 1. What libfx gives the agent side, as found

Facts the options below lean on. "Ran" marks what a trial showed; the rest
is read.

- **F1. libfx's engine is itself an ACP agent.** `createFxEngine` starts
  fx-core with `args: ["acp"]` and talks ACP v1 to it over an in-memory
  line channel (`engine.js:1607-1615`, `initialize` at `engine.js:1792`).
  Ran: the core answers `initialize` as
  `{"agentInfo":{"name":"fx","version":"0.0.16"},"agentCapabilities":{"loadSession":true,…,"mcpCapabilities":{"http":false,"sse":false},"sessionCapabilities":{"list":{},"resume":{},"close":{}},"_meta":{"fx":{"steering":false}}},"authMethods":[]}`
  and sends `available_commands_update`, `tool_call`, `tool_call_update`,
  `agent_message_chunk`, `session_info_update` and `usage_update`.
- **F2. The public turn events are a narrow projection of that.**
  `FxTurnEvent` (`types/libfx.d.cts:245-253`) is `text_delta`,
  `reasoning_delta`, `user_message` (a steer joining), `tool_start {id, name,
  input | inputPreview}` and `tool_end {id, name, content?, isError}`.
  `normalizeTurn` (`engine.js:2076-2116`) drops the core's tool `kind`,
  `title`, `status: in_progress`, `usage_update`, `session_info_update`,
  `plan` and every content block past the first text. The raw ACP is
  reachable only as the diagnostic `onEvent` `{type: "acp.receive";
  message: unknown}` (`types/libfx.d.cts:287-288`): typed `unknown`, not a
  contract.
- **F3. Usage.** A turn's `result.usage` is `FxUsage` (`types/libfx.d.cts:
  256-262`): input, output, cache read and write, reasoning tokens, summed
  over the turn's model calls (ran: 100+120 input became 220). Per model
  call, the documented `hooks` give `model.end.data.usage`
  (`types/libfx.d.cts:405-408`). No public event carries the context
  window's size or fill; the core's own `usage_update {used, size}` is only
  in F2's diagnostic (ran: `{"used":122,"size":100000}`, `size` from the
  custom provider's `models` map).
- **F4. Stop reasons.** `end_turn`, `max_output_tokens`, `max_model_turns`,
  `refused`, `cancelled`; a durable turn adds `error` (with `FxErrorSummary
  {name, message, code?}`, `types/libfx.d.cts:29-33`) and `unknown`
  (`types/libfx.d.cts:797-809`). Ran: an effort the model does not offer
  ends a durable turn `error` with code `LIBFX_MODEL_UNSUPPORTED_EFFORT`;
  on an engine, `prompt` throws it.
- **F5. Two shapes of agent.** `createFxAgent` (durable: sessions, a store,
  `session.steer`, `cancel`, `resume`, `stream(cursor)`, per-session model;
  `types/libfx.d.cts:740-756, 865-905`) and `createFxEngine` (one
  conversation, `persistence` or `checkpoint`, model fixed at creation;
  `types/libfx.d.cts:596-609`).
- **F6. One configuration per agent name per store in a process; many
  sessions per agent.** One durable agent owns any number of sessions, and
  each `agent.session(id, options)` brings its own `context`, `instructions`
  and `model` (`types/libfx.d.cts:758-772`). What must be one per name on
  one store in a process is the agent's configuration: `claimName` compares
  every option but `onEvent` deeply, functions and non-plain objects by
  identity (`durable.js:905-944`). Ran: a second same-name agent on the same
  store threw `FX_AGENT_NAME_IN_USE` when its tools differed, when only its
  tools' `execute` closures differed, and when only its agent-level
  `instructions` differed. So sessions that differ only in per-session state
  (model, instructions, `context` that a shared tool reads to find the
  session's own resources) share one agent; sessions with **different tool
  catalogs** (different MCP servers) or a **different provider or
  credentials callback** need different names or stores (`local({ dir })`'s
  store is its directory, `durable/local.mjs` `store: "local:<dir>"`). A
  session runs only on an agent of the name that created it (README
  "Several agents"). Across processes, configurations may differ (a
  `checkpoint.mismatch` diagnostic only, README "Durability").
- **F7. `local()` durability runs in the process, under Bun.** Ran:
  `createFxAgent({ durability: local({ dir }) })` (`libfx/durable-local`, an
  exported entry, `types/durable-local.d.ts:8-18`) ran a turn with a tool,
  opened no listening socket, made no request but the model's, ran no
  `lsof` (the bundled Workflow World has a port probe,
  `durable/local.mjs:190`, not reached), and wrote 32 files, 108 KB, for one
  short turn under `dir` (`runs/`, `steps/`, `events/`, `streams/`,
  `.locks/`); a second turn from a second process made it 58 files, 192 KB.
  Session ids are `wrun_…`. `agent.newSessionId()` gives one before the
  first prompt, and `session(id).prompt` accepted it. The JavaScript is
  804,527 bytes (it bundles undici and `@workflow/world-local`). Compiled:
  the critic built a static `libfx/durable-local` import with the Wasm
  embedded under Bun 1.4.4's `--compile` and ran a 16-tool durable turn from
  outside `node_modules`, and runtime saw the same; both on darwin-arm64,
  Wasm backend only. Native and the other targets were not run compiled
  with `local()`.
- **F8. The default durability is unusable compiled and wrong for chord.**
  With no `durability`, libfx picks `local()` in `$FX_SESSIONS_DIR` or the
  system temporary directory, loaded by `import(new URL("./durable/
  local.mjs", import.meta.url))` (`node.js:675-692`): the same pattern the
  gate found Bun does not embed, and a temporary directory loses sessions.
  chord must always pass `durability`, imported statically (F7).
- **F9. `session.resume()` runs the open turn.** It does not inspect: it
  starts a delivery that resumes the harness (`durable.js:2966-2968`,
  `startTurn("resume")`; `harness.resume` at `durable.js:2059`). Ran: after a
  SIGKILL while a non-idempotent tool ran, `resume()` emitted `tool_end
  {isError: true, content: "fx stopped while this tool was running, so it
  may have partly run. Check its effects before running it again."}`, asked
  the model again and ran the tool again before `end_turn`. The critic's
  fixture saw two model requests and an idempotent tool rerun.
- **F10. A prompt after a crash silently finishes the old turn first.**
  Ran: same crash, then `session(id).prompt("second")` without `resume()`.
  The interrupted turn ran on (a model call and a tool call that
  executed), and none of it appeared in the new prompt's turn view, which
  showed only its own turn.
- **F11. Tool call ids.** Ran: `FxToolContext.executionId` equals the
  model's call id that `tool_start.id` carries, and stays the same when a
  call runs again after a crash (`types/libfx.d.cts:138-150` documents
  both). The critic ran 16 parallel idempotent calls whose `execute` began
  before the consumer read their `tool_start`: every `executionId` matched
  its `tool_start.id`.
- **F12. Models.** `listModels({ apiKey })` lists AI Gateway's catalog only
  (`engine.js:601-608`, `types/libfx.d.cts:79-85, 1064`). The core fetches
  Codex's `/backend-api/codex/models` and Grok's `/v1/models` itself
  (`chatgpt.js:11`, `grok.js:11-12`) and exposes neither. A subscription
  or custom provider requires a model id (`engine.js:199-205`). Effort is
  `"default" | "low" | "medium" | "high" | "xhigh" | string`
  (`types/libfx.d.cts:39`), checked against the model's catalog entry,
  which is not exposed either. Ran: `agent.session(id, { model: "fake-2" })`
  switched the next turn's model with the history kept.
- **F13. Credentials.** Subscription providers take `credentials()` and
  `onCredentials()` callbacks (`types/libfx.d.cts:645-658`); libfx refreshes
  near expiry and once after a rejection, and masks tokens in errors
  (README "Where credentials go"). With `provider` left out (Gateway),
  libfx reads `AI_GATEWAY_API_KEY` and `VERCEL_OIDC_TOKEN` from the
  environment by itself (`node.js:700-713`).
- **F14. Permissions inside libfx are not public.** The engine answers the
  core's `session/request_permission` through `options.onPermission`
  (`engine.js:1746-1757`), which no type declares. Host tools get no
  permission step from libfx: "libfx orders the calls but grants nothing
  itself" (README "Tools").
- **F15. MCP.** `createMcpAdapter(client, { prefix })` (`types/mcp.d.ts:
  22-46`) takes an `@modelcontextprotocol/sdk` v1 client the host owns
  (transport, auth, elicitation and close are the host's). Ran, over the
  SDK's in-memory transport: a server tool `send_message` became
  `chord_send_message`, `idempotent: false`, instructions empty. Naming
  (`mcp.js:58-70`): `prefix + tool.name`, every character outside
  `[A-Za-z0-9_-]` made `_`, cut to 64, and `_2`, `_3`, … added on a clash
  **inside this one adapter only**. The returned tools follow `listTools`
  order (`mcp.js:59`, a `map` over the catalog) and do not carry the
  original name.
- **F16. A session cancel stored before the resume ends a dead process's
  open turn without a model request or a tool run.** Ran, eight times: a
  SIGKILL during a tool (idempotent four times, not idempotent four times);
  then, in a new process, `await session.cancel()` and then
  `session.resume()` (six runs) or, with no resume, the next prompt (two
  runs). Counts, by the fake server and by the tool: 0 model requests and 0
  tool executions for the dead turn in every run; `resume()` ended
  `cancelled` with the dead turn's `messageId` (a non-idempotent call's
  `tool_end isError` was its one event; an idempotent one emitted none); the
  next prompt then made exactly its own 2 requests and 1 execution. On a
  session with no open turn, `cancel()` then `resume()` ended `idle` with 0
  requests, and the next prompt ran normally: the cancel was spent, not
  held for the next turn. How: `cancel()` stores a session cancel
  (`durable.js:3074-3076`); folding the log marks the open turn
  `cancelOpen` (`durable.js:450-453`); the delivery that picks the session
  up calls `harness.resume` (`durable.js:2059`) and, in the same
  synchronous run of `drive`, `turn.cancel()` (`durable.js:2265`). Inside
  the engine, `resume` writes the core's recovery `session/prompt` at once
  (`engine.js:1270-1272, 2418`) and `cancel` writes `session/cancel` right
  behind it and aborts every tool's signal (`engine.js:2340-2360`). So the
  guarantee is observed and follows from the code's order, not documented:
  the core receives a recovery prompt immediately followed by its cancel,
  and that no model request leaves between the two is fx-core's behaviour,
  not a libfx contract. The README documents `cancel()` only as "Cancels
  the running turn".

## 2. Q1: how the agent reaches chord

### What exists

- **The client side takes any producer of an `Agent`.** `Agent`
  (`src/acp/connection.ts:114-206`) is an interface: `pid`, `init`,
  `steering`, `exited`, `gone()`, and the requests. `openAgent` makes one
  over a spawned process (`:241-252`); `connectAgent` over any
  `AgentProcess` (`:258`, `src/acp/process.ts:34-60`), which its tests drive
  by hand (`tests/acp/connection_test.ts:1125`).
- **The enricher chain is a `Relay` on the traffic, not on serialization.**
  `relayStream(stream, relay)` and `tapStream` (`src/acp/traffic.ts:17-90`)
  work on parsed `AnyMessage` objects; `connectAgent` puts them between the
  SDK's `ndJsonStream` and the SDK (`connection.ts:356-362`). What
  `src/session/AGENTS.md` requires is that every session's traffic runs
  through the enricher chain on the relay, and that state, record, window,
  `-p` and `acp` read only what it leaves.
- **What the session does with `pid`:** `session.ts:460-461` adds it to
  `live` and removes it on `exited`; `live` is the session's `agentPids`
  (`:630`), read in `src/` by nothing else today (tests read it). Shutdown's
  SIGKILL sweep is the registry of groups `spawnGroup` made (decisions.md,
  CHD-573 R1), which an in-process agent is not in.
- **The agent side takes a stream:** `connectAgentApp(handlers, stream)`
  (`src/acp/agent_app.ts:127`), what `chord acp` runs on.
- **chord already starts itself:** `resourceWorkerCommand`
  (`src/platform/resource_worker.ts:26-41`): `execPath()`, plus `main.tsx`
  from source, the binary alone compiled.

### The options

- **A1. In-process, a direct `Agent`.** A module implements `Agent` over
  libfx: requests become libfx calls, and libfx's events become ACP
  messages handed to the same `Relay` and `onTraffic` subscriber, in order,
  with no JSON-RPC framing. It must reproduce what `connectAgent` does
  around the SDK today: the relay and tap order (an update reaches the
  subscriber before its prompt's answer settles, `traffic.ts:51-62`);
  `answer`'s rule that a permission, form or plan the person has not
  answered is answered `cancelled` when the turn is cancelled or the agent
  closes (`connection.ts:270-307`); the "offered" checks (`:473-478`, used at `:566`); and
  `ask`'s rule that a request withdrawn by its signal never reaches the
  agent (`:384-430`). A second implementation of those, kept in step with
  the first.
- **A2. In-process, ACP over an in-memory pair.** The adapter is an ACP
  agent on the SDK's agent side (`connectAgentApp`), joined to
  `connectAgent` by an `AgentProcess` whose `stdin` and `stdout` are an
  in-memory byte pair. Everything from the relay up is unchanged; the cost
  is JSON serialization of every message both ways, and an `AgentProcess`
  to write.
- **B. A child process, ACP on stdio.** The same adapter as A2, run by
  chord started as itself (`[execPath(), …, <flag or subcommand>]`, as the
  resource worker), opened by `openAgent` like `fx acp` (`src/clis.ts:
  42-46`). Sub-question: a hidden flag, or a visible subcommand other ACP
  clients could run.

| | A1 | A2 | B |
| --- | --- | --- | --- |
| Adapter code | libfx to `Agent` and to ACP-shaped messages | libfx to an ACP agent (SDK agent side) | as A2 |
| Through the relay | yes, by hand | yes, unchanged | yes, unchanged |
| Duplicated client logic | `answer`, `ask`, offered checks, tap order | none | none |
| `pid` | none real: a value nothing may ever signal; today only tests read `agentPids`, and any future signal to it would hit chord itself if it were `process.pid` | as A1 | the child's |
| `exited` | settles when `close()` has closed libfx and its MCP clients; libfx's core exit (`engine.js:1712-1722`) rejects turns, it does not end the agent | as A1 | the child's exit |
| `gone()` | the libfx error that ended it, in place of stderr | as A1 | the child's stderr tail |
| A native crash in libfx | ends the window | ends the window | the child exits; "agent gone" |
| F6 | the window's main, built-in children and team members share the process: same provider and same MCP catalog share one agent; any difference needs its own name or store | as A1 | one session per process, as chord opens children today; one constant name |
| Stop and quitting | `close()` of libfx, no SIGKILL if it hangs, not in the spawned-group sweep | as A1 | `AgentProcess.stop`, bounds, SIGKILL |
| Credentials | read and refreshed in the window | as A1 | the child reads and writes the store (runtime's lock) |
| Tests | a new seam beside the fake agent | the adapter over an in-memory pair | the fake agent's path, plus the same adapter tests |

**Recommendation: B**, a hidden flag for the MVP: it keeps libfx's native
code out of the window, makes F6 one constant name, and reuses spawn, stop,
stderr and "agent gone" whole. A2 is the in-process option at the least
cost, since B's adapter is A2's; A1 is allowed by the relay rule but
duplicates the client's request and cancellation logic. The adapter is
written over a `Stream` and tested over an in-memory pair whichever is
chosen.

### The ACP surface the adapter offers (A2 and B; A1 the same calls without the wire)

`initialize`, answered as:

```json
{
  "protocolVersion": 1,
  "agentInfo": { "name": "riff", "title": "riff", "version": "<chord's>" },
  "authMethods": [
    { "id": "chatgpt", "name": "ChatGPT plan", "description": "Sign in to ChatGPT in chord" },
    { "id": "grok", "name": "Grok plan", "description": "Sign in to Grok in chord" }
  ],
  "agentCapabilities": {
    "loadSession": false,
    "promptCapabilities": { "image": true, "audio": false, "embeddedContext": true },
    "mcpCapabilities": { "http": true, "sse": true },
    "sessionCapabilities": { "resume": {}, "close": {} },
    "_meta": { "steering": { "supported": true } }
  }
}
```

The name and title wait on Q5. `authMethods` are `agent`-type entries
(ACP's default, `@agentclientprotocol/sdk` `v1/schema/types.gen.d.ts:
1692-1760`); whether `authenticate` is answered depends on the sign-in
option (section 3).

| Method | What the adapter does with libfx |
| --- | --- |
| `session/new {cwd, mcpServers}` | reads the provider and credentials (section 3), opens the MCP clients and allocates tool names (section 4), creates the libfx agent with chord's tools and the MCP tools, `await agent.newSessionId()` (F7), writes the session's sidecar (section 6), answers `{sessionId: "wrun_…", configOptions: [model, effort, mode]}`. No credential: JSON-RPC error `-32000` |
| `session/resume {sessionId, cwd, mcpServers}` | as new, on the sidecar's provider and model; then the open-turn rule (section 6) before answering |
| `session/close` | closes the MCP clients and lets the session go (`agent.close()`) |
| `session/prompt` | `agent.session(id, { model: { id, effort } }).prompt(blocks, { messageId })`; reads the turn's events to the end, sends each as `session/update`, then `await turn.result` and answers (table below). Text, image and embedded resource blocks map one to one; a `resource_link` becomes a text block naming it |
| `session/cancel` | `session.cancel()` (`types/libfx.d.cts:885`); the turn ends `cancelled` |
| `session/set_config_option` | `model` or `effort` changes the sidecar and the next turn's session options (F12); `mode` is the permission mode (Q2, runtime's) |
| `_session/steering` | while a turn runs, `session.steer(text)`, answered `injected`; with none running and `idleBehavior: "promptRequired"`, answered `promptRequired` with nothing sent, as Claude's adapter does (`src/acp/connection.ts:90-108`). See P4 |
| `session/load`, `session/list`, `logout` | not offered in the MVP: chord's record draws the past (section 6) |

Updates the adapter sends, from libfx's events:

| libfx | ACP `session/update` |
| --- | --- |
| `text_delta` | `agent_message_chunk {content: {type: "text", text}}` |
| `reasoning_delta` | `agent_thought_chunk` |
| `user_message {id}` | nothing: chord drew the steer when it sent it |
| `tool_start {id, name, input}` | `tool_call {toolCallId: id, title, kind, status: "pending", rawInput: input, locations}`: title, kind and locations from chord's own table of its tools; an MCP tool titled `mcp__<server>__<tool>` from section 4's map, `kind: "other"` |
| the tool's `execute` begins (`executionId` = `id`, F11) | `tool_call_update {status: "in_progress"}`; a shell tool's output as `_meta.terminal_info`, `terminal_output_delta` and `terminal_exit` (the keys chord reads, `src/session/transcript/tools.ts:146-183`) |
| `tool_end {id, content, isError}` | `tool_call_update {status: "completed" or "failed", content}`: an edit's `diff` block from what chord's own edit tool recorded for that `executionId`, else the text |
| `turn.result.usage` | the prompt response's `usage {inputTokens, outputTokens, cachedReadTokens, cachedWriteTokens, thoughtTokens}` |

**The id-keyed merge.** Every tool call is keyed by `(sessionId, turn's
messageId, toolCallId)`, never by position: libfx's `tool_start` and chord's
`execute` callback for the same id (F11) arrive in either order, and
idempotent calls run up to 16 at once on native (README "Tools"). The first
of the two for a key sends `tool_call`; the second only adds what it knows
(`in_progress`, `rawInput`). A second `tool_start` for a key already
started is suppressed. A `tool_start` with `inputTruncated: true` sends
`rawInput: null` and the `inputPreview` as text content; the full input
comes from `execute`, which always gets it (`types/libfx.d.cts:251-252`).
Terminal output and a diff that `execute` produces after `tool_end` was
read, or for a key whose turn has ended, are sent as a further
`tool_call_update` while the turn is open and dropped after the prompt is
answered, so nothing of a turn follows its answer. A key is forgotten when
its turn's prompt is answered.

How a turn ends:

| libfx `stopReason` | ACP answer |
| --- | --- |
| `end_turn` | `end_turn` |
| `max_output_tokens` | `max_tokens` |
| `max_model_turns` | `max_turn_requests` |
| `refused` | `refusal` |
| `cancelled` | `cancelled` |
| `error`, code `LIBFX_CHATGPT_REFRESH_FAILED`, `LIBFX_GROK_REFRESH_FAILED`, `LIBFX_GROK_ACCOUNT_CHANGED`, or a 401 from the provider | JSON-RPC error `-32000` (`authRequired`), the message libfx gave |
| `error`, anything else | JSON-RPC error `-32603` with libfx's message and `data: {code}` |
| `unknown` | as `error`; it only comes from a turn a dead process left (section 6) |

Not produced, and why: `session_info_update` (the core makes a title, F1,
libfx does not pass it; chord titles a session by its first prompt), `plan`
(libfx has none). `usage_update` and retries: section 2a.

## 2a. Cost, the context gauge and retries

### Cost (the protocol's part of Q7)

What chord does today for any agent that gives tokens and no cost:
`costFromTokens` (`src/session/enrichers.ts:53-128`) runs on the relay,
before the record, and on each prompt answer with `usage` and a model the
price data knows (`@pydantic/genai-prices`, `src/session/prices.ts:1-28`)
synthesizes a `usage_update` with `cost` (the session's estimate so far) and
`used` (from the turn's tokens, `contextFrom`, `prices.ts:35-39`), marked
`_meta["chord/filled"]`; `windowFromModel` (`enrichers.ts:130-155`) then
fills `size` from the same data. So with nothing changed, a plan session
gets an API-price cost and a gauge, recorded, summed by `/cost` and sent to
`chord acp`'s clients. The adapter cannot stop that by itself.

- **Q7-a. No synthesized cost; the cost is unknown.** The adapter marks its
  usage as a plan's: `_meta["chord/billing"]: "plan"` on the prompt
  answer's `usage` and on any `usage_update` it sends. `costFromTokens`
  passes a session so marked (it sets the session's `agentCost`-like flag in
  `enrich.ts`'s wire state, `enrich.ts:67-69, 450-453`), never writing a
  numeric zero. Provenance: the record keeps the marked answers and updates
  whole, as it keeps every update; an older chord reading the record sees
  no cost, which is what it shows for an agent with none. Consumers:
  - the status line (`src/ui/status/status.ts`): no amount, the plan named
    instead (interface's words);
  - `/cost` and its tables (`src/ui/transcript/spend.ts`, `spend_table.ts`,
    `reports.ts`, `src/session/turn_costs.ts`): tokens shown, cost "unknown
    (plan)"; a total over sessions that include one says it is partial,
    never adds a zero;
  - `-p` (`src/session/oneshot.ts`): no cost line, or "unknown (plan)";
  - `chord acp`'s clients: the answer's `usage` and the marker, no `cost`;
  - team and run summaries that sum children's costs: partial, as `/cost`.
- **Q7-b. The estimate, marked.** `costFromTokens` runs as for any agent
  (`chord/filled: ["cost"]` is the provenance it writes already), and every
  consumer above shows it as an API-price estimate, not a charge; the
  record, `/cost` and clients agree with each other, and the words must not
  say a plan charges nothing.

**Gauge.** Under Q7-a no `usage_update` is synthesized, so there is no gauge
unless the adapter sends one. Options: **g1** none; **g2** the adapter sends
`usage_update {used}` after each model call from the documented hooks'
`model.end.data.usage` (input plus output of that call, F3), with `size`
left out for `windowFromModel` to fill from the price data when it knows the
model, marked filled, and no gauge when it does not; **g3** the core's own
`usage_update` from the `acp.receive` diagnostic (F2, an undeclared shape:
owner's consent first). Under Q7-b, the enrichers' gauge from the turn's
summed tokens reads fuller than it is after a turn of several requests
(`prices.ts:30-34` says so). **Recommendation: Q7-a with g2**; the lead
merges Q7 with interface's draft.

### Retries

libfx reports a failing model request's retries only as diagnostics:
`onEvent` `transport.retry {attempt, nextAttempt, elapsedMs, error}` and
`transport.error` (`types/libfx.d.cts:300-301`); the turn's events say
nothing meanwhile. How long it retries is runtime's evidence and the bound
is the owner's.

- **The path to the window.** The adapter turns each `transport.retry` into
  an ACP notification of chord's own, `_chord/session/retrying {sessionId,
  attempt, nextAttempt, elapsedMs, error}`, and the next model output or the
  turn's end into `_chord/session/retrying {sessionId, attempt: null}`. In B
  and A2 it goes over the wire; the tap hands it to the subscriber
  (`traffic.ts:64-90`, notifications stop at the tap, the SDK never sees
  them); in A1 it is handed to the subscriber directly. The window shows it
  in the status line (interface's). It is not recorded: it is the state of
  a turn, not part of it. libfx's error text is already masked of
  credentials (F13).
- **`-p`:** one stderr line per retry, "the provider failed (…); retrying,
  attempt n", and the turn's end as for any agent: an `error` ends with
  `-32603`, `-p` exits non-zero.
- **`chord acp`'s clients:** CHD-575 sends every `_chord` notification to
  every client (decisions.md, "extension notifications are unconditional"),
  so the notification is forwarded under main's session id; a client that
  ignores it sees a turn with no updates until the end, as with any slow
  agent. Adding it to `_meta["chord/acp"].extensions` is a CHD-575-style
  version entry (`session/retrying`: 1).
- **Alternative:** no notification; the window shows only the elapsed turn
  time it shows today. Simpler, and a person waits on a provider that keeps
  failing without knowing why.

## 3. Sign-in in each Q1 option

### What ACP and chord have

- ACP v1 `authMethods` are `agent` (the client calls `authenticate
  {methodId}`) or `terminal` (the client runs the agent's program in an
  interactive terminal; `clientCapabilities.auth.terminal` opts in), and
  `logout` (`v1/schema/types.gen.d.ts:1650-1760, 3090-3215`).
- **ACP elicitation is request-scoped as well as session-scoped.**
  `CreateElicitationRequest` is "tied to a session (optionally a tool call)
  or a request" (`v1/schema/types.gen.d.ts:795-820`), and URL mode takes
  either scope (`:1305`, `ElicitationRequestScope {requestId}` at `:856`).
  So during `authenticate`, the agent can send `elicitation/create {mode:
  "url", requestId: <authenticate's id>, url, message}` for the browser or
  the device page, and `elicitation/complete` when it is done.
- chord's client already takes an elicitation without a `sessionId`
  (`src/acp/connection.ts:320-337`). What refuses one at start is chord's
  own: `Elicitations` answers `cancel` when nobody on screen is subscribed
  (`src/session/elicitations.ts:128-131`), and before a session exists
  nothing is. chord never calls `authenticate`, and `-32000` at start
  becomes `SignInNeeded` with the agent's methods
  (`src/session/sign_in.ts:9, 63-88`; `src/session/session.ts:563-570`),
  shown with "chord does not sign agents in" (`sign_in.ts:105-108`, CHD-435).

### The options

- **S1. chord's own sign-in, outside ACP.** The window runs libfx's
  `libfx/chatgpt` and `libfx/grok` steps (the owner's settled flows) and
  stores the credentials; the agent only reads them. Without them,
  `session/new` and `session/resume` answer `-32000` with the two methods;
  for this agent only, chord's start failure opens the sign-in screen
  instead of `wayOn`'s words. A refresh that fails mid-session ends the turn
  `-32000`, which the window turns into the same screen. Changes: a
  sign-in module and screen in the window; `start_failure`'s branch for this
  agent. In A1/A2 the screen and the agent share a process; in B the child
  reads the store at `session/new` and writes back refreshed credentials
  (`onCredentials`, F13), which needs runtime's lock.
- **S2. ACP `authenticate` with request-scoped URL elicitation.** The
  agent advertises `chatgpt-browser`, `chatgpt-device`, `grok-browser`,
  `grok-device` as `agent` methods and runs libfx's flow inside
  `authenticate`: it sends a URL elicitation tied to that request (the
  browser address, or the device page with the code in `message`), listens
  on the loopback address itself for the browser way, answers
  `authenticate` when the credentials are stored, and an error (`-32000`
  with "port 1455 is taken", expiry, denial) otherwise. Changes in chord's
  client: on `-32000` from this agent, the window picks a method (the same
  screen's choices) and calls `authenticate`, which `connectAgent` does not
  offer today; `Elicitations` (or the start path) must hold a listener for
  request-scoped elicitations during start, where today it cancels with
  nobody subscribed; the window's HTTP/HTTPS check on URL elicitations
  applies; Esc becomes `$/cancel_request` on `authenticate` plus the
  elicitation's `cancel` answer, and the agent closes its listener. UX: the
  same screens (choose, wait on browser, device code, failure), drawn from
  the elicitation's `url` and `message` instead of local state; opening the
  browser stays the window's. Benefits: the flow lives where the
  credentials are used (B's child owns them, no cross-process lock for
  sign-in itself); another ACP client of B's visible subcommand could sign
  in through it.
- **S3. ACP `terminal` auth.** The agent advertises a `terminal` method
  running `chord <sign-in>`; a client that declares `auth.terminal` runs it.
  chord's window would have to suspend its screen to run itself; it mainly
  serves other clients of a public subcommand.

**Recommendation: S1** for the MVP: no change to `connectAgent`'s surface or
to `Elicitations`' startup rule, and the same agent works under `-p` and
`chord acp` with no new protocol. S2 is the protocol-clean way if B's
subcommand becomes public.

### For the owner: the CHD-435 exception

CHD-435 settled that chord does not sign agents in; its words say so
(`sign_in.ts:105-108`), and CHD-573 kept sign-in out of `chord acp`
(decisions.md, "the client answers", Sign-in A). The built-in agent needs
**"chord signs its own agent in, and only its own"**. Question: is that
exception accepted, and what does each place get?

- **The window:** the sign-in screen (S1 or S2).
- **A child process (B), or a child or team member of the built-in kind:**
  never signs in itself; it reads the credentials the window stored and,
  without them, refuses `-32000`. A child opened while the person is
  signed out fails to start with chord's start failure, as any agent
  without a login does.
- **`-p`:** `-32000` printed as today, with this agent's line "run chord
  and sign in" instead of `wayOn`'s.
- **`chord acp`'s clients:** under S1, `-32000` with the methods and the
  same words; the client cannot sign in through chord. Under S2, `chord acp`
  could forward `authMethods` and `authenticate` for this agent only, which
  reverses CHD-573's Sign-in A for one agent.

Sign-out and switching (interface's keys): sign-out deletes the store's
entry; a running session keeps its credentials until its next refresh or
the next start fails `-32000`. Switching provider is a new session (P2).

## 4. MCP, and chord's own MCP server

The adapter offers `mcpCapabilities {http: true, sse: true}`, so
`serversFor` (`src/session/servers.ts:50`) gives it the settings' servers
and chord's own, like any agent. For each server in `session/new`, in the
order given: an `@modelcontextprotocol/sdk` client (`package.json`:
`^1.32.1`) with `StdioClientTransport`, `StreamableHTTPClientTransport` or
`SSEClientTransport` by the entry's type, its `headers` and `env` as ACP
gives them; then `createMcpAdapter(client, { prefix: "" })`.

### Names: allocation and the original-name map

libfx resolves clashes inside one adapter only, and its names cannot be read
back into `mcp__<server>__<tool>` (F15). So chord allocates every
model-facing name itself, over all servers, from inputs it supplies:

1. **The catalog, from the host's own client.** The client passed to
   `createMcpAdapter` is chord's wrapper around the SDK client, whose
   `listTools` records each page's tools in order (the `McpClient` shape is
   the host's to supply, `types/mcp.d.ts:9-20`). After the adapter
   resolves, `tools.length` must equal the recorded catalog's length and
   each `tools[i].name` must equal libfx's own rule applied to
   `catalog[i].name` (sanitized, cut to 64, an in-server suffix); otherwise
   the server is refused with a held-back reason, never guessed at. This
   leans on the adapter returning tools in catalog order (`mcp.js:59`),
   checked on every server rather than assumed.
2. **The prefix, unique per server.** `base = sanitize(server.name)` (every
   character outside `[A-Za-z0-9_-]` made `_`), cut to 24; the prefix is
   `base + "__"`. Servers are taken in `session/new`'s order (chord's own
   comes last, as `serversFor` orders it); a `base` already taken by an
   earlier server becomes `base_2`, `base_3`, … (cut so the prefix stays
   within 27 characters).
3. **The full name, unique across everything.** Names are reserved first
   for chord's own built-in tools (runtime's Q2 list); then for each server
   in order and each tool in catalog order: `name = (prefix +
   sanitize(tool)).slice(0, 64)`; on a clash with any taken name, `_2`,
   `_3`, … replaces the end to stay within 64. The tool object passed to
   libfx is the adapter's with `name` replaced (tools are the host's input to
   `createFxAgent`).
4. **The map.** `modelName → {server: server.name, tool: catalog[i].name}`,
   both original, is the only way back: the ACP `title` is
   `mcp__${server}__${tool}` from it, and `rawInput` is the call's input.

Two fixtures the ship team tests:

- **Two servers that sanitize alike:** `my.tools` and `my tools`, each with
  a tool `run`. Prefixes `my_tools__` and `my_tools_2__`; model names
  `my_tools__run` and `my_tools_2__run`; titles `mcp__my.tools__run` and
  `mcp__my tools__run`.
- **Truncation, in and across servers:** servers `srv.a` and `srv a`
  (both sanitize to `srv_a`), each with tools `t` + 70×`x` + `1` and `t` +
  70×`x` + `2`. Prefixes `srv_a__` and `srv_a_2__`. In each server both
  prefixed names cut to the same 64 characters, so the second takes `_2`:
  four model names, `srv_a__txx…x` and `srv_a__txx…_2`, `srv_a_2__txx…x`
  and `srv_a_2__txx…_2`, each 64 long; the map gives four titles,
  `mcp__srv.a__t…1`, `mcp__srv.a__t…2`, `mcp__srv a__t…1`,
  `mcp__srv a__t…2`. As prefixes are unique and at most 27 characters, two
  servers' names can only meet through a prefix clash, which step 2
  prevents; step 3's global check also covers chord's reserved names.

chord's own server is HTTP with a bearer token per session
(`src/server/server.ts:148-151`). It then works **with no special path**:
the token says who calls, chord serves the request and records a `served`
line, and `chordCallOf` ties it to the agent's `tool_call` by `MCP_TITLE`
and `rawInput` (`src/session/transcript/chord.ts:23, 53`), as for Claude's
adapter. `MCP_TITLE` reads the server up to the first `__`
(`^mcp__(.+?)__(.+)$`), so a settings server whose name contains `__`
reads back wrong in that regex; chord's own server's name (`chord`,
`chord-2`, …) never does. So the built-in agent can `spawn_task`,
`open_agent`, `send_message`, `run_team`, monitor, and be a team member or
lead, as far as Q2 lets it; children it opens are whatever runtime they
name.

Caveats:

- Every MCP tool comes `idempotent: false` (F15), which libfx runs alone
  and, after a crash, never reruns (F9). For chord's read-only tools
  (`list_agents`, `get_budgets`, `list_monitors`, …) the adapter could set
  `idempotent: true`; a choice per tool, runtime's Q2.
- In A1/A2, F6: sessions in the window's process with different MCP
  catalogs need their own agent names or stores.
- A server's elicitation is the host's (F15): the MCP client's elicitation
  handler can relay to ACP `elicitation/create`, which chord's client
  answers. The MVP may decline instead (P5).

## 5. Q3: providers

Settled: ChatGPT (`provider: "codex"`) and Grok (`provider: "grok"`).

- **P-a. Plans only.** The test seam (a fake Chat Completions server) is a
  custom provider chosen only by `--fake`, `--qa` and tests, never by
  settings.
- **P-b. Plus AI Gateway by key.** The only provider with a model list
  (F12). The key goes in the same store; libfx must always get an explicit
  `apiKey`, as with none it reads `AI_GATEWAY_API_KEY` and
  `VERCEL_OIDC_TOKEN` itself (F13), which `--fake` and tests must never do.
- **P-c. Plus a custom Chat Completions server from settings.** A
  `baseUrl` (HTTPS, or HTTP on localhost only), a `models` map with context
  windows, and a key (F13; README "Custom providers"). Its key is never
  refreshed.
- **P-d. Both b and c.**

**Recommendation: P-a** for the MVP: the owner's goal is a person with a
plan and nothing else; b and c each add settings, a key screen and their
own failures, and either can follow without a protocol change, as the
provider is the sidecar's (section 6). Under Q7-a, b and c would be priced
(they charge per token), so the billing marker is the provider's, not the
agent's.

## 6. Q6: records and resume

What exists:

- **chord's record** (`src/session/record.ts`): the agent's id, name and
  directory on its first line (`:40-55`), then every prompt and every
  `session/update` whole, each turn's result and tokens, config values when
  they move. It is what `--continue`, `--resume` and `/resume` list and
  draw, and what `chord acp` serves (CHD-573). With an agent offering
  `session/resume`, chord draws the past from it and the agent replays
  nothing (decisions.md, "Resume on chord's own session record").
- **libfx's store**: the conversation the model sees, with tool results,
  images and open turns (F5, F7, F9).

So two truths, as with Claude's and Codex's adapters today: **chord's record
is the truth of what was shown; libfx's store is the truth of what the model
knows.** No record format change is needed: the session id is the agent's
(`wrun_…`), config moves go in as `config_option_update` lines, and the
provider, account id, model, effort and mode the agent needs to reopen go in
a sidecar of the agent's own beside libfx's store (a JSON file per session),
because `session/resume` carries no configuration and libfx's store keeps
no provider (README: "Every process passes its own model, credentials,
tools…"). Q7-a's marker, if chosen, is a `_meta` key inside lines the record
already keeps.

### The store, options

- **R1. `createFxAgent` with `local({ dir })` under chord's state
  directory.** libfx owns journal, crash recovery, steer, cancel and
  per-session model (F5, F7, F12). Costs: 0.8 MB more JavaScript (F7,
  compiled and run on darwin-arm64 Wasm); many small files per turn (F7);
  F6 in A1/A2; nothing in libfx deletes a session.
- **R2. `createFxEngine` with a `Persistence` store chord writes.** The
  interface is libfx's (`load`, `append` fenced on `expected`,
  `saveCheckpoint`; README "Without sessions"), the reference is
  `createMemoryPersistence`; ran: a second engine on the same store
  continued the history. chord writes the file store, its fencing and an
  image store; a model change means a new engine on the same store; steer
  and cancel move to the turn object; no `stream`. An engine with an open
  turn exposes `resume()` and nothing to discard it either (`engine.js:
  1961-1981`): the open-turn problem below is the same, not checked by trial.
- **R3. `createFxEngine` with `checkpoint()` after each turn.** No open turn
  ever survives a crash (the model's view loses the turn; chord's record
  still shows it), and a checkpoint is capped at 4 MiB (README "Images"),
  past which a session cannot be saved.
- **R4. `memory()`.** Nothing survives the process. Listed to be refused.

**Recommendation: R1**, the directory under chord's state directory, never
the default (F8).

### A turn a dead process left open

`session.resume()` runs the open turn (F9), and a prompt runs it unseen
first (F10). The public API has no call that tells whether a turn is open
without starting work. What decides before any model request or tool run
is the order of two public calls: `await session.cancel()` first, then
`resume()` (F16). The options:

- **T1. Continue it.** `session.resume()` alone, as a turn nobody prompted:
  its updates go out as the agent's own turn (CHD-575's `agent` origin).
  Spends the plan and reruns idempotent tools without the person's word
  (F9).
- **T2. Cancel it, by the public order.** On every `session/resume`, before
  answering: `await session.cancel()`, then `session.resume()` read to its
  result. `cancelled` with a `messageId` means a turn was open and is now
  ended: the adapter sends its events (a non-idempotent call's `tool_end
  isError`) as `tool_call_update`s and a line saying the interrupted turn
  was cancelled; `idle` means none was, and the cancel is spent (F16). Pinned
  by a fake-crash test in chord's suite that counts model requests and tool
  executions for both kinds of tool and fails when either is above zero:
  F16 is observed, follows from libfx's code order, and is not a documented
  guarantee, so a libfx upgrade that changes it must fail that test, not a
  person's session.
- **T3. Leave it.** The next prompt runs it unseen (F10). Listed to be
  refused.
- **T4. Ask upstream** for a call that inspects an open turn or discards it
  without the core (upstream changes are outside this design; it can be
  filed beside T2).

If the owner does not accept F16 as observed behaviour pinned by a test, the
limitation is: **libfx 0.0.16's public API cannot guarantee that reopening a
crashed session runs nothing.** Then the options are T1 (accept that it
runs, shown), R3 (no open turn ever survives, at the cost of the model
forgetting the crashed turn and the 4 MiB cap), or T4 and waiting.

**Recommendation: T2 with its pinned test**, and T4 filed.

### `--continue` and `--resume`

Unchanged: the newest record in the directory for this agent's name; chord
sends `session/resume` with its id; the adapter reads the sidecar, opens
libfx's session, applies T, and answers with `configOptions` as they were.
A record whose libfx session is gone (the directory deleted) is refused,
and chord says it in its existing words ("it cannot resume session …",
`src/session/session.ts:589`). A resume on another signed-in account than
the sidecar's is P3.

## 7. Models and effort

- **Model list, options (O-M):** M1, a list per provider in chord's
  source, edited by hand like the frozen registry, with the plan's default
  first; M2, free text only; M3, fetch the providers' model endpoints with
  the person's credentials (a provider client of chord's own: a non-goal,
  and Codex's is a private backend path); M4, ask upstream for `listModels`
  on Codex and Grok. **Recommendation: M1**, M4 filed when the owner agrees.
- `/model` is the `model` config option (`type: "select"`), applied to the
  next turn through `agent.session(id, { model })` (F12): a running turn
  keeps its model.
- **Effort:** an `effort` select of `default`, `low`, `medium`, `high`,
  `xhigh` (F12). Which a model offers cannot be read (F12); a level it does
  not offer ends the turn `error` (F4), which the adapter answers with
  `-32603` and the code, and resets the option to `default` with a
  `config_option_update`. Alternative: no effort option in the MVP.

## 8. Failure cases

| Case | What happens |
| --- | --- |
| The agent exits (B), or libfx's core exits (`runtime.exited`, `engine.js:1712-1722`) | B: chord's "agent gone" path, its stderr's last words; the libfx turn is open in the store; the next resume applies T. A1/A2: the core's exit rejects the turn; the adapter answers `-32603`; a native crash ends the window |
| A turn is cancelled | `session.cancel()`; each running tool's `signal` aborts; a permission ask chord holds is answered `cancelled` by chord (`connection.ts:270-307`); the turn ends `cancelled`. A cancel that reaches the adapter before its prompt is stored: libfx stores nothing and ends `cancelled` (README "Sessions") |
| An update arrives late | libfx's turn view ends before `result` resolves; the adapter answers the prompt only after the last event and drops tool output that comes after (section 2's merge), so nothing of a turn follows its answer. A title model call can outlive the turn (README "Instrumentation hooks"), but sends no turn event |
| A tool's `execute` begins before its `tool_start` is read | the id-keyed merge (section 2) |
| A crash mid-tool | the call ends failed with libfx's words under T2 (F16) |
| The provider keeps failing | `_chord/session/retrying` while libfx retries; then the turn's `error` (section 2a) |
| Credentials refresh fails mid-session | the turn ends `error` with the refresh code; `-32000` (section 2) |
| A steer races the turn's end | P4 |
| Two chord processes resume one session | libfx fences writers (`local()`: a session held by a live process; README "Durability"); the second's prompt waits behind the first's turn, while each chord appends its own record lines, as for any agent today. T2's cancel from the second would cancel the first's running turn: the adapter applies T2 only when libfx's store shows no live holder, which the public API does not expose (P6) |

## 9. Reducer actions, state and record

No new reducer action. The adapter sends only updates the reducer already
folds (`agent_message_chunk`, `agent_thought_chunk`, `tool_call`,
`tool_call_update` with `diff` content and the terminal `_meta` keys,
`config_option_update`, and under g2 `usage_update`) and prompt results with
`usage`. New and not recorded: `_chord/session/retrying` (window state, the
interface's slice). The record's format does not change; Q7-a adds a `_meta`
key inside lines it already keeps. Sign-in state is the window's.

## 10. Questions

For the owner (each with options above):

- **Q1** (with runtime): A1, A2 or B; in B, a hidden flag or a public
  subcommand. Recommended B, hidden.
- **CHD-435's exception:** chord signs its own agent in, and what the
  window, children, `-p` and `chord acp`'s clients each get (section 3).
- **Sign-in**: S1, S2 or S3. Recommended S1.
- **Q3**: P-a to P-d. Recommended P-a.
- **Q6**: R1 to R4; T1 to T4, and whether F16, observed and pinned by a
  test, is enough. Recommended R1, T2 with its test, T4 filed.
- **Q7** (merged by the lead with interface's): Q7-a or Q7-b; gauge g1, g2
  or g3. Recommended Q7-a with g2.
- **Retries:** `_chord/session/retrying`, or nothing. Recommended the
  notification. The bound on retrying is the owner's (runtime's evidence).
- **O-M** models: M1 to M4. Recommended M1 (M4 filed).
- **P2**: switching provider inside a session, or only by a new session.
  Recommended a new session: the provider is the libfx agent's, fixed at
  creation (`types/libfx.d.cts:740`).
- **P3**: resuming a session after signing in to another account of the
  same provider: allowed, refused, or asked. libfx's Grok refresh already
  refuses a changed account (`grok.js:90-91`).
- **P5**: MCP elicitation from the settings' servers: relayed to chord's
  form, or declined in the MVP.

For the lead and critic, not the owner's:

- **P4**: `_session/steering` when a turn is just ending: libfx makes a
  steer that misses the turn the next turn (README "Sessions"), so
  `injected` can be wrong. The `user_message {id}` event tells when it
  joined; whether the adapter waits for it or answers at once needs
  runtime's view.
- **P6**: T2 with two live chord processes on one session: whether the
  adapter can tell a dead holder from a live one before cancelling. In B
  with one process per session and chord's own "session open elsewhere"
  checks it may not arise; not checked.
- Whether `embeddedContext: true` is right: libfx takes `resource` blocks
  (`types/libfx.d.cts:97-99`), not checked against what chord sends for
  `@` mentions.

## 11. What was read, tried, and not checked

Read in libfx 0.0.16: `README.md`; `types/libfx.d.cts` 26-90, 136-275,
283-331, 390-480, 540-920, 1060-1067; `types/chatgpt.d.ts`,
`types/grok.d.ts`, `types/mcp.d.ts`, `types/durable-local.d.ts` whole;
`engine.js` 120-235, 601-650, 1270-1300, 1590-1830, 1961-1990, 2060-2175,
2340-2425; `durable.js` 440-460, 900-946, 2040-2140, 2212-2280, 2955-2975,
3070-3100; `mcp.js` whole; `chatgpt.js`, `grok.js` whole;
`chatgpt-sign-in.js` 1-40; `grok-sign-in.js` 33-50; `node.js` 660-718; the
tail and port probe of `durable/local.mjs`.

Read in chord: `src/acp/connection.ts` 27-420, `src/acp/traffic.ts`,
`src/acp/process.ts` 30-62, `src/session/session.ts` 440-630,
`src/session/enrichers.ts` 50-175 and 895-915, `src/session/prices.ts`
1-40, `src/session/elicitations.ts` 115-140, `src/session/sign_in.ts`,
`src/session/servers.ts` 1-80, `src/session/record.ts` 1-140,
`src/session/transcript/chord.ts` 1-60, `src/session/transcript/tools.ts`
146-200, `src/acp_agent.ts` 1730-1790, `src/platform/resource_worker.ts`
20-60; the SDK's `v1/schema/types.gen.d.ts` auth and elicitation types.

Libraries tried: libfx 0.0.16 (`createFxEngine` with
`createMemoryPersistence`, `createFxAgent` with `memory()` and `local()`,
`libfx/mcp`), `@modelcontextprotocol/sdk` 1.x (`McpServer`, `Client`,
`InMemoryTransport`), all against the fake server. Trials of F16: eight
crash-and-reopen runs and one no-open-turn run.

Not checked:

- Compiled, beyond F7's darwin-arm64 Wasm runs by the critic and runtime:
  native, the other targets, and the MCP client transports.
- Real providers: Codex's and Grok's model ids, effort levels, usage fields,
  retry behaviour and error codes on a real 401; whether a plan reports
  cache and reasoning tokens.
- F16 under a slow core or a native backend's timing: the trials ran from
  source on the default backend on one machine.
- R2's open-turn behaviour by trial.
- Claude's and Codex's adapters' own source: their tool shapes are taken
  from what chord's code says of them (`src/acp/connection.ts:210-226`,
  `src/session/transcript/chord.ts:44-60`).
- `local()` under many sessions: file count, disk growth, and the 250 ms
  poll's latency (`pollMs: 250` in `durable/local.mjs`) beyond short turns.
- Bun.secrets in a child process (B) while the window holds the same entry.
