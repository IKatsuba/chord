# CHD-485 protocol draft: the built-in agent's side

The protocol architect's draft for the brief's Q1 (with runtime), Q3 and Q6,
sign-in in each Q1 option, MCP and chord's own MCP server, records and
models. Nothing here settles an owner question: each has options, evidence
and a recommendation.

Read: the brief, `AGENTS.md`, `src/session/AGENTS.md`, `docs/decisions.md`
(chord's own ACP layer, resume on chord's record, M4, chord's MCP server,
CHD-573 to CHD-581, CHD-575), `board show CHD-485` with its comments, and
`gate.md`. libfx 0.0.16 was read from `npm pack libfx@0.0.16` (paths below
are inside that package). ACP from `@agentclientprotocol/sdk` 2.2.0 as
`bun.lock` pins it.

Run: five scripts in a scratch project under `/tmp` (libfx 0.0.16 and
`@modelcontextprotocol/sdk` 1.x installed there), Bun 1.4.4, darwin-arm64,
from source, never compiled. Every model request went to a fake OpenAI Chat
Completions server on `127.0.0.1` through libfx's custom provider; no real
provider, sign-in or model was reached. The fake asks for one host tool,
then answers `done`, with a `usage` chunk each time.

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
- **F6. A durable agent's name is bound to its sessions and to one
  configuration per process.** A session runs only on an agent of the name
  that created it (README "Several agents"). Ran: a second `createFxAgent`
  with the same name on the same store in one process throws
  `FX_AGENT_NAME_IN_USE` when the tool list differs, when only the tools'
  `execute` closures differ, and when only `instructions` differ. Across
  processes, configurations may differ (a `checkpoint.mismatch` diagnostic
  only, README "Durability").
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
  804,527 bytes (it bundles undici and `@workflow/world-local`). Not tried
  under `bun build --compile`.
- **F8. The default durability is unusable compiled and wrong for chord.**
  With no `durability`, libfx picks `local()` in `$FX_SESSIONS_DIR` or the
  system temporary directory, loaded by `import(new URL("./durable/
  local.mjs", import.meta.url))` (`node.js:675-692`): the same pattern the
  gate found Bun does not embed, and a temporary directory loses sessions.
  chord must always pass `durability`.
- **F9. Crash mid-tool.** Ran: a process killed with SIGKILL while a
  non-idempotent tool ran; a second process's `session(id).resume()`
  emitted `tool_end {isError: true, content: "fx stopped while this tool
  was running, so it may have partly run. Check its effects before running
  it again."}`, told the model, and went on to `end_turn`.
- **F10. A prompt after a crash silently finishes the old turn first.**
  Ran: same crash, then `session(id).prompt("second")` without `resume()`.
  The interrupted turn ran on (a model call and a tool call that
  executed), and none of it appeared in the new prompt's turn view, which
  showed only its own turn. Only `session.stream(cursor)` would show it.
- **F11. Tool call ids.** Ran: `FxToolContext.executionId` equals the
  model's call id that `tool_start.id` carries (`call_1` both), and stays
  the same when a call runs again after a crash
  (`types/libfx.d.cts:138-150`).
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
  `chord_send_message`, `idempotent: false`, instructions empty.

## 2. Q1: how the agent reaches chord

### The finding that frames Q1

Both of chord's ACP sides already take a stream, not a process:

- the client side, `connectAgent(process: AgentProcess, options)`
  (`src/acp/connection.ts:258`), builds `acp.ndJsonStream(process.stdin,
  process.stdout)` (`:356`) over any `AgentProcess` (`src/acp/process.ts:
  34-60`); its tests already drive one by hand
  (`tests/acp/connection_test.ts:1125`);
- the agent side, `connectAgentApp(handlers, stream)`
  (`src/acp/agent_app.ts:127`), is what `chord acp` runs on.

So the piece this task writes, **an ACP agent over libfx** (the SDK's
agent side, libfx under it), is the same module whichever way Q1 goes. Q1
only decides what carries its stream: a pipe to a child process, or an
in-memory pair in chord's own process. Everything downstream of
`connectAgent` (enrichers, the record, the reducer, permissions, cancel,
`chord acp`) stays as it is in both. That is why this draft does not
offer "in-process behind the session layer, beside the ACP connections"
as a second producer of transcript actions: it would duplicate what the
enricher chain, the record and `conversation.ts` do for ACP traffic
(`src/session/AGENTS.md`: every session's traffic runs through the
enricher chain), and the brief's first option is met by A below.

### The options

- **A. In-process, ACP over an in-memory stream.** The window (and `chord
  acp`, and `-p`) loads libfx and runs the adapter in its own process; an
  `AgentProcess` with in-memory streams, a synthetic `pid`, and a `stop`
  that closes the libfx agent, is handed to `connectAgent`.
- **B. A child process, ACP on stdio.** chord starts itself as the agent:
  `[execPath(), …, <flag or subcommand>]`, the way
  `resourceWorkerCommand` already does (`src/platform/resource_worker.ts:
  26-41`, `execPath` plus `main.tsx` from source, the binary alone
  compiled), and `openAgent` runs it like `fx acp` (`src/clis.ts:42-46`).
  Sub-question for the owner: a hidden flag (as `--chord-resource-worker`)
  or a visible subcommand that other ACP clients could run.

What differs, from the protocol's side (runtime owns processes, crashes and
memory):

| | A, in-process | B, child process |
| --- | --- | --- |
| Adapter and ACP surface | the same | the same |
| A native crash in libfx | takes the window down | the agent exits; chord's existing "agent gone" path |
| F6, one configuration per name per process | the main session and every built-in child or team member share the process: each needs its own store or name, and a session stays bound to that name | one session per process, as chord opens children today; the name can be one constant |
| `stop` and quitting | a close of libfx, no SIGKILL if it hangs | `AgentProcess.stop`, its bounds and SIGKILL |
| Credentials | read in the window | the child reads the store itself (concurrent writers: runtime's lock) |
| `--agent-command` and tests | a new seam for the in-memory pair | the fake agent's path as it is |

**Recommendation: B**, a hidden flag for the MVP. It keeps libfx's native
code out of the window, makes F6 a non-issue, and reuses spawn, stop,
stderr and "agent gone" whole. A remains open at no cost to the adapter:
the module is written over a `Stream`, and its tests run it over an
in-memory pair whichever way the owner chooses.

### The ACP surface the adapter offers (A and B alike)

`initialize`, answered as:

```json
{
  "protocolVersion": 1,
  "agentInfo": { "name": "chord-agent", "title": "chord", "version": "<chord's>" },
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
1692-1760`) whose only use is to be named in an `authRequired` refusal
(section 3); `authenticate` is not offered in the MVP.

| Method | What the adapter does with libfx |
| --- | --- |
| `session/new {cwd, mcpServers}` | reads the provider and credentials (section 3), opens the MCP clients (section 4), creates the libfx agent with chord's tools and the MCP tools, `await agent.newSessionId()` (F7), writes the session's sidecar (section 6), answers `{sessionId: "wrun_…", configOptions: [model, effort, mode]}`. No credential: JSON-RPC error `-32000` |
| `session/resume {sessionId, cwd, mcpServers}` | as new, on the sidecar's provider and model; then the open-turn rule (section 6) |
| `session/close` | closes the MCP clients and lets the session go (`agent.close()`) |
| `session/prompt` | `agent.session(id, { model: { id, effort } }).prompt(blocks, { messageId })`; reads the turn's events to the end, sends each as `session/update`, then `await turn.result` and answers (table below). Text, image and embedded resource blocks map one to one; a `resource_link` becomes a text block naming it |
| `session/cancel` | `session.cancel()` (`types/libfx.d.cts:885`); the turn ends `cancelled` |
| `session/set_config_option` | `model` or `effort` changes the sidecar and the next turn's session options (F12); `mode` is the permission mode (Q2, runtime's) |
| `_session/steering` | while a turn runs, `session.steer(text)`, answered `injected`; with none running and `idleBehavior: "promptRequired"`, answered `promptRequired` with nothing sent, as Claude's adapter does (`src/acp/connection.ts:90-108`). See open question P4 |
| `session/load`, `session/list`, `authenticate`, `logout` | not offered in the MVP: chord's record draws the past (section 6) and sign-in is chord's (section 3) |

Updates the adapter sends, from libfx's events:

| libfx | ACP `session/update` |
| --- | --- |
| `text_delta` | `agent_message_chunk {content: {type: "text", text}}` |
| `reasoning_delta` | `agent_thought_chunk` |
| `user_message {id}` | nothing: chord drew the steer when it sent it |
| `tool_start {id, name, input}` | `tool_call {toolCallId: id, title, kind, status: "pending", rawInput: input, locations}`: title, kind and locations from chord's own table of its tools; an MCP tool titled `mcp__<server>__<tool>` with `kind: "other"` |
| the tool's `execute` begins (`executionId` = `id`, F11) | `tool_call_update {status: "in_progress"}`; a shell tool's output as `_meta.terminal_info`, `terminal_output_delta` and `terminal_exit` (the keys chord reads, `src/session/transcript/tools.ts:146-183`) |
| `tool_end {id, content, isError}` | `tool_call_update {status: "completed" or "failed", content}`: an edit's `diff` block from what chord's own edit tool recorded for that `executionId`, else the text |
| `turn.result.usage` | the prompt response's `usage {inputTokens, outputTokens, cachedReadTokens, cachedWriteTokens, thoughtTokens}` |

The title and diff come from chord's tools, which this draft does not
design (runtime's Q2, interface's Q8): what the protocol needs of them is a
lookup by `executionId` for the diff and terminal output, and a fixed
title, kind and locations per tool.

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

Not produced in the MVP, and why:

- `usage_update` (context used and size): no public source (F3). Options
  for the owner (O-U): none, so the status line shows no context gauge for
  this agent; per-call `inputTokens` from the documented hooks with the
  size unknown on plans; or the core's own `usage_update` read off the
  `acp.receive` diagnostic (F2), which leans on an undeclared message shape
  and is the kind of reach AGENTS.md sends to the owner first. Recommended:
  the first; chord's enricher fills a cost from tokens as it does for any
  agent with no price.
- `session_info_update` (the title): the core makes one (F1) but libfx
  does not pass it; chord titles a session by its first prompt anyway.
- `plan`: libfx has no plan event.

## 3. Sign-in in each Q1 option

ACP v1 has `authMethods` of two kinds: `agent` (the client calls
`authenticate {methodId}`, and the agent does the rest) and `terminal` (the
client runs the agent's program with given arguments in an interactive
terminal; `clientCapabilities.auth.terminal` opts in), and `logout`
(`v1/schema/types.gen.d.ts:1650-1760, 3090-3215`). Neither kind gives the
agent a way to show a person an address or a code while `authenticate`
runs, and chord's client declares neither (`src/acp/connection.ts:
228-234`). chord's start reads `authRequired` (`-32000`) into
`SignInNeeded` with the agent's `authMethods`
(`src/session/sign_in.ts:9, 63-88`; `src/session/session.ts:563-570`),
and today says "chord does not sign agents in" (`sign_in.ts:105-108`).

- **S1. chord's own sign-in, outside ACP.** The window runs libfx's
  `libfx/chatgpt` and `libfx/grok` steps (the owner's settled flows) and
  stores the credentials; the agent only reads them. Without them,
  `session/new` and `session/resume` answer `-32000` with the two methods
  in `authMethods`; chord's existing start failure becomes, for this
  agent only, the sign-in screen instead of `wayOn`'s words. A refresh that
  fails mid-session ends the turn `-32000` (section 2), which the window
  can turn into the same screen. `-p` and `chord acp` print what
  `signInLines` prints today, with the words changed to "run chord to sign
  in" (CHD-573 kept sign-in out of `chord acp`).
  - In A: the screen and the agent share a process; credentials can pass in
    memory, and only the store is shared with other processes.
  - In B: the child reads the store at `session/new` and writes back
    refreshed credentials (`onCredentials`, F13); the window and children
    write the same entry, which needs runtime's lock.
- **S2. ACP `authenticate`, and a side channel for the address and code.**
  The window calls `authenticate {methodId: "chatgpt-device"}`; the agent
  runs the flow and has to show the code: through an `elicitation/create`
  in URL mode (chord's client takes it, `connection.ts:320-337`, but it is
  session-scoped and no session exists before sign-in), or through a
  `_chord/…` extension. Both bend a request meant for something else, and
  in A the agent is in the window's process anyway.
- **S3. ACP `terminal` auth.** The agent advertises a `terminal` method
  running `chord <sign-in>`; a client that declares `auth.terminal` runs
  it. chord's window would have to suspend its screen to run itself; it
  would mainly serve other ACP clients running B's visible subcommand.

**Recommendation: S1 in both options**, with the `-32000` refusal as the
one way the agent says it needs a sign-in, so the same agent works under
`-p` and `chord acp` with no new protocol. S3 is a later step if the owner
makes B's subcommand public.

Sign-out and switching (interface's keys): sign-out deletes the store's
entry; a running session keeps its credentials until its next refresh or
the next start fails `-32000`. Switching provider is a new session (open
question P2).

## 4. MCP, and chord's own MCP server

The adapter offers `mcpCapabilities {http: true, sse: true}`, so
`serversFor` (`src/session/servers.ts:50`) gives it the settings' servers
and chord's own, like any agent. For each server in `session/new`:

- the `@modelcontextprotocol/sdk` client chord already depends on
  (`package.json`: `^1.32.1`), with `StdioClientTransport`,
  `StreamableHTTPClientTransport` or `SSEClientTransport` by the entry's
  type, its `headers` and `env` as ACP gives them;
- `createMcpAdapter(client, { prefix })` (F15) makes its tools; the model
  sees `<prefix><tool>`, limited to 64 letters, digits, `_` or `-`
  (`types/libfx.d.cts:191-205`), so a prefix is derived from the server's
  name; the ACP `title` stays `mcp__<server>__<tool>`.

chord's own server is HTTP with a bearer token per session
(`src/server/server.ts:148-151`). It then works **with no special path**:
the token says who calls, chord serves the request and records a `served`
line, and `chordCallOf` ties it to the agent's `tool_call` by
`MCP_TITLE` and `rawInput` (`src/session/transcript/chord.ts:23, 53`), as
for Claude's adapter. So the built-in agent can `spawn_task`, `open_agent`,
`send_message`, `run_team`, monitor, and be a team member or lead, as far as
Q2 lets it; children it opens are whatever runtime they name.

Caveats for the owner and runtime:

- Every MCP tool comes `idempotent: false` (F15), which libfx runs alone
  and, after a crash, never reruns (F9). For chord's read-only tools
  (`list_agents`, `get_budgets`, `list_monitors`, …) the adapter could set
  `idempotent: true`; that is a choice per tool, runtime's Q2.
- In A, F6 makes MCP awkward: the tool list is the agent's, per process,
  and two built-in sessions in one process with different servers need two
  names or two stores.
- A server's elicitation is the host's (F15): the MCP client's elicitation
  handler can relay to ACP `elicitation/create`, which chord's client
  answers. The MVP may decline instead; listed as P5.

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
  `baseUrl` (HTTPS, or HTTP on localhost only), a `models` map with
  context windows, and a key (F13; README "Custom providers"). Its key is
  never refreshed.
- **P-d. Both b and c.**

**Recommendation: P-a** for the MVP: the owner's goal is a person with a
plan and nothing else, b and c each add settings, a key screen and their
own failures, and either can follow without a protocol change, as the
provider is the sidecar's (section 6).

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

So two truths, as with Claude's and Codex's adapters today: **chord's
record is the truth of what was shown; libfx's store is the truth of what
the model knows.** No record format change is needed: the session id is
the agent's (`wrun_…`), config moves go in as `config_option_update`
lines, and the provider, model and effort the agent needs to reopen go in
a sidecar of the agent's own beside libfx's store (a JSON file per
session: provider, account id, model, effort, mode), because `session/
resume` carries no configuration and libfx's store keeps no provider
(README: "Every process passes its own model, credentials, tools…").

### The store, options

- **R1. `createFxAgent` with `local({ dir })` under chord's state
  directory.** libfx owns journal, crash recovery, steer, cancel and
  per-session model (F5, F7, F9, F12). Costs: 0.8 MB more JavaScript (F7),
  to be checked under `--compile` by runtime; many small files per turn
  (F7); F6 in option A; nothing in libfx deletes a session.
- **R2. `createFxEngine` with a `Persistence` store chord writes.** The
  interface is libfx's (`load`, `append` fenced on `expected`,
  `saveCheckpoint`; README "Without sessions"), the reference is
  `createMemoryPersistence`; ran: a second engine on the same store
  continued the history. chord writes the file store, its fencing and an
  image store; a model change means a new engine on the same store; steer
  and cancel move to the turn object; no `stream`.
- **R3. `createFxEngine` with `checkpoint()` after each turn.** The
  simplest; a crash loses the open turn from the model's view (chord's
  record still shows it), and a checkpoint is capped at 4 MiB (README
  "Images"), past which a session cannot be saved.
- **R4. `memory()`.** Nothing survives the process: a resumed session
  draws its past and the model has forgotten it. Listed to be refused.

**Recommendation: R1**, the dir under chord's state directory, never the
default (F8). R2 is the fallback if runtime finds `local()` does not
survive `--compile` or its file count is a problem.

### A turn a dead process left open (F9, F10)

On `session/resume`, the adapter asks libfx whether a turn is open
(`session.resume()` ends `idle` when none is). If one is:

- **T1. Continue it at once**, as a turn nobody prompted: its updates go
  out before or after the resume answer, under a turn chord draws as the
  agent's own (CHD-575 names the `agent` origin). Spends the plan without
  the person's word.
- **T2. Cancel it** (`session.cancel()`), and say so in a line; the
  person's next prompt starts clean. libfx's store keeps what the dead
  process stored, chord's record what it drew.
- **T3. Leave it**: the next prompt silently runs it first, its tools
  included, unseen (F10). Listed to be refused.

**Recommendation: T2.** Nothing runs that the person did not ask for after
a crash, and nothing runs unseen.

### `--continue` and `--resume`

Unchanged: the newest record in the directory for this agent's name; chord
sends `session/resume` with its id; the adapter reads the sidecar, opens
libfx's session, applies T, and answers with `configOptions` as they were.
A record whose libfx session is gone (the directory deleted) answers
`-32002`-style "session not found" through chord's existing "it cannot
resume session" words (`src/session/session.ts:589`). A resume on
another signed-in account than the sidecar's is P3.

## 7. Models and effort

- **Model list, options (O-M):** M1, a list per provider in chord's
  source, edited by hand like the frozen registry, with the plan's
  default first; M2, free text only; M3, fetch the providers' model
  endpoints with the person's credentials (a provider client of chord's
  own: a non-goal, and Codex's is a private backend path); M4, ask upstream
  for `listModels` on Codex and Grok (upstream changes are out of this
  design; it can be filed). **Recommendation: M1**, M4 filed when the owner
  agrees.
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
| The agent exits (B), or libfx's core exits (`runtime.exited`, `engine.js:1712-1722`) | B: chord's "agent gone" path, its stderr's last words; the libfx turn is open in the store; the next resume applies T. A: the core's exit rejects the turn; the adapter answers `-32603`; a native crash ends the window |
| A turn is cancelled | `session.cancel()`; each running tool's `signal` aborts; a permission ask chord holds is answered `cancelled` by chord (`connection.ts:270-307`); the turn ends `cancelled`. A cancel that reaches the adapter before its prompt is stored: libfx stores nothing and ends `cancelled` (README "Sessions") |
| An update arrives late | libfx's turn view ends before `result` resolves; the adapter answers the prompt only after the last event, so nothing of a turn follows its answer. A title model call can outlive the turn (README "Instrumentation hooks"), but sends no turn event |
| A tool's `execute` begins before its `tool_start` is read | the adapter keys by id and sends `tool_call` on whichever comes first (F11); idempotent tools may run 16 at once on native (README "Tools") |
| A crash mid-tool | F9: the call ends failed with libfx's words, under T's rule |
| Credentials refresh fails mid-session | the turn ends `error` with the refresh code; `-32000` (section 2) |
| A steer races the turn's end | P4 |
| Two chord processes resume one session | libfx fences writers (`local()`: a session held by a live process; README "Durability"); the second's prompt waits behind the first's turn, while each chord appends its own record lines, as for any agent today |

## 9. Reducer actions, state and record

None new. The adapter sends only updates the reducer already folds
(`agent_message_chunk`, `agent_thought_chunk`, `tool_call`,
`tool_call_update` with `diff` content and the terminal `_meta` keys,
`config_option_update`) and prompt results with `usage`. The record keeps
what it keeps for any agent; its format does not change. Sign-in state is
the window's (interface's slices), not the transcript's.

## 10. Questions

For the owner (each with options above):

- **Q1** (with runtime): A or B; in B, a hidden flag or a public
  subcommand. Recommended B, hidden.
- **Sign-in**: S1, S2 or S3. Recommended S1.
- **Q3**: P-a to P-d. Recommended P-a.
- **Q6**: R1 to R4, and T1 to T3. Recommended R1 and T2.
- **O-M** models: M1 to M4. Recommended M1 (M4 filed).
- **O-U** context gauge: none, hooks, or the diagnostic. Recommended none.
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
- Whether `embeddedContext: true` is right: libfx takes `resource` blocks
  (`types/libfx.d.cts:97-99`), not checked against what chord sends for
  `@` mentions.

## 11. What was read, tried, and not checked

Read in libfx 0.0.16: `README.md`; `types/libfx.d.cts` 26-90, 136-275,
283-331, 390-480, 540-920, 1060-1067; `types/chatgpt.d.ts`,
`types/grok.d.ts`, `types/mcp.d.ts`, `types/durable-local.d.ts` whole;
`engine.js` 120-235, 601-650, 1590-1830, 2060-2175; `chatgpt.js`,
`grok.js` whole; `chatgpt-sign-in.js` 1-40; `grok-sign-in.js` 33-50;
`node.js` 660-718; the tail and port probe of `durable/local.mjs`.

Libraries tried: libfx 0.0.16 (`createFxEngine` with
`createMemoryPersistence`, `createFxAgent` with `memory()` and `local()`,
`libfx/mcp`), `@modelcontextprotocol/sdk` 1.x (`McpServer`, `Client`,
`InMemoryTransport`), all against the fake server. `@agentclientprotocol/
sdk` 2.2.0 was read for auth and stop reasons, not run.

Not checked:

- Anything compiled: `libfx/durable-local` and the MCP client transports
  under `bun build --compile` (runtime's build check).
- Real providers: Codex's and Grok's model ids, effort levels, usage
  fields and error codes on a real 401; whether a plan reports cache and
  reasoning tokens.
- Claude's and Codex's adapters' own source: their tool shapes are taken
  from what chord's code says of them (`src/acp/connection.ts:210-226`,
  `src/session/transcript/chord.ts:44-60`), not re-read.
- `local()` under many sessions: file count, disk growth, and the 250 ms
  poll's latency (`pollMs: 250` in `durable/local.mjs`) beyond one short
  turn (133 ms end to end from source, the engine's load included).
- Bun.secrets in a child process (B) while the window holds the same
  entry.
