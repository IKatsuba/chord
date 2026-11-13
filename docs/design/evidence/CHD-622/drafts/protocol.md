# CHD-622 — protocol draft: the ACP surface of `@chorded/cursor-cloud-acp`

protocol's answers to P1–P5 of the brief. Sources: `@cursor/sdk` 1.3.1's
`.d.ts` files (read in a scratch directory outside the repository, nothing
run from it), https://cursor.com/docs/sdk/typescript, Cursor's Cloud Agents
API page for one URL form (named where used), ACP v1 as
`@agentclientprotocol/sdk` 2.2.0 types it, and chord's client side
(`src/acp/`, `src/session/`, `src/riff/adapter.ts` as the in-repository ACP
agent, `docs/design/CHD-435.md`). SDK type names are quoted as the
`.d.ts` files spell them.

`CROSS:` marks an item the lead settles with interface or runtime;
`OWNER:` marks a question for the owner, with options and a
recommendation. `OPEN:` marks a fact the types and docs do not settle and
that only a live run (an authorized manual check) or Cursor can answer.

## What the SDK gives, in short

- `Agent.create(options: AgentOptions): Promise<SDKAgent>` with
  `cloud: CloudAgentOptions` (`repos: Array<{ url; startingRef?; prUrl? }>`,
  `workOnCurrentBranch?`, `autoCreatePR?`, `envVars?`, `metadata?`, `env?`),
  `mode?: AgentModeOption` (`"agent" | "plan"`), `model?: ModelSelection`,
  `apiKey?`, `name?`, `agentId?`.
- `SDKAgent`: `agentId`, `model`, `send(message: string | SDKUserMessage,
  options?: SendOptions): Promise<Run>`, `close()`, `listArtifacts()`,
  `getUsage()`. `summarize()` is local only.
- `Run`: `stream(): AsyncGenerator<SDKMessage>`, `wait(): Promise<RunResult>`,
  `cancel()`, `conversation(): Promise<ConversationTurn[]>`,
  `supports(operation: RunOperation)`, `status: RunStatus`, `git?: RunGitInfo`,
  `usage?: TokenUsage`, `error?: RunError`. `steer?()` always answers
  `"revert_to_followup"` on cloud (docs).
- `Agent.resume(agentId, Partial<AgentOptions>)`, `Agent.get`, `Agent.list(
  ListAgentsOptions)` (cloud branch: `limit`, `cursor`, `prUrl`,
  `includeArchived`, `apiKey`, `teamId`) → `ListResult<SDKAgentInfo>`,
  `Agent.listRuns(agentId, { runtime: "cloud" })` → `ListResult<Run>`,
  `Agent.getRun(runId, { runtime: "cloud", agentId })`.
  `Agent.messages.list` is local only (`GetAgentMessagesOptions.runtime?:
  "local"`).
- `Cursor.me()`, `Cursor.models.list()` → `SDKModel[]` (= `ModelListItem`),
  `Cursor.auth.login/logout/status` taking `SdkLoginOptions.store?:
  SdkCredentialStore | null`.
- `SDKMessage` = `SDKSystemMessage | SDKUserMessageEvent | SDKAssistantMessage
  | SDKToolUseMessage | SDKThinkingMessage | SDKStatusMessage |
  SDKRequestMessage | SDKTaskMessage | SDKSummaryMessage | SDKUsageMessage`.
- Errors: `CursorSdkError` (`code`, `status`, `isRetryable`) and its
  subclasses `AuthenticationError`, `RateLimitError`, `ConfigurationError`,
  `IntegrationNotConnectedError` (`helpUrl`, `provider`), `AgentBusyError`,
  `AgentNotFoundError`, `NetworkError`, `UnknownAgentError`,
  `UnsupportedRunOperationError`.

One finding that shapes P1 and P5: **`SdkCredentialStore` is read only by
`Cursor.auth.login/logout/status`.** `AgentOptions`, `ListAgentsOptions`,
`GetRunOptions` and `CursorRequestOptions` take `apiKey?: string` and
otherwise resolve "explicit `apiKey`, then `CURSOR_API_KEY`, then the stored
login" — the stored login being the SDK's own file
(`getDefaultSdkAuthPath()`, `~/.cursor/sdk/auth.json`). Nothing in
`CursorConfigureOptions` plugs a store in for agent calls. So a keyring
store serves `login`, and the adapter itself must load the key from it and
pass `apiKey` on every call. That is the SDK's documented input, not a
workaround; the precedence it implies is in P5.

## P1. The ACP surface

### `initialize`

```json
{
  "protocolVersion": 1,
  "agentInfo": { "name": "@chorded/cursor-cloud-acp", "title": "Cursor cloud", "version": "0.1.0" },
  "authMethods": [
    {
      "id": "cursor-login",
      "name": "Cursor login",
      "description": "Run `npx @chorded/cursor-cloud-acp login` in a terminal, or set CURSOR_API_KEY"
    }
  ],
  "agentCapabilities": {
    "loadSession": true,
    "promptCapabilities": { "image": true, "audio": false, "embeddedContext": false },
    "mcpCapabilities": { "http": false, "sse": false },
    "sessionCapabilities": { "list": {}, "resume": {}, "close": {} }
  },
  "_meta": { "steering": { "supported": false } }
}
```

- `authMethods`: CHD-435 draws `name` and `description` as they are, so the
  description carries the command. The id is the adapter's own.
- `image: true`: `SDKUserMessage.images` takes `{ data, mimeType }`.
- `embeddedContext: false`: `SDKUserMessage` holds text and images only.
  chord's `@` mentions arrive as `resource_link` blocks (`src/files.ts`)
  whose paths the prompt text already names; the adapter drops
  `resource_link` blocks and sends the text blocks joined as they come.
  The file is on the person's disk, not in the VM, so its content is not
  the agent's to read anyway; nothing is rewritten.
- `mcpCapabilities` all false, and `mcpServers` from `session/new`,
  `session/load` and `session/resume` are not passed on: a stdio command or
  a loopback URL from chord's machine means nothing in Cursor's VM, and
  cloud MCP (team settings) is Cursor's. ACP requires stdio support to be
  accepted; the adapter accepts and does not forward them.
  `CROSS:` (runtime/interface) chord's own table should mark `cursor cloud`
  as taking no MCP servers (CHD-441/CHD-620's `noMcpServers`), so chord says
  its servers are held back instead of the adapter silently dropping them.
- `_meta.steering.supported: false`, as riff sends it: cloud `steer()` always
  reverts to a follow-up (docs), so chord queues instead.
- No `session/fork` (no SDK call copies a cloud agent's conversation), no
  `session/delete` (`Agent.delete` is irreversible; not asked for).
- `authenticate`: see `OWNER: O1`.

### `session/new`

Order of work, each step refusing with its own words (P4 lists them):

1. **Key.** Resolve the key (P5). None anywhere → `authRequired`.
   Otherwise `Cursor.me({ apiKey })` once: an `AuthenticationError` (expired
   90-day login key, revoked key, Team Admin key) → `authRequired` with the
   SDK's message. This makes CHD-435's block appear at start, as the brief
   asks, not on the first prompt.
2. **Git.** In `cwd`, with git itself (`CROSS:` runtime picks the way:
   `node:child_process` running `git`, or a library such as `simple-git`):
   - not a work tree → refuse;
   - `HEAD` detached → refuse ("check out a branch"); the owner's rule names
     the current branch, and a detached HEAD has none;
   - the branch's upstream (`@{upstream}`, i.e. `branch.<b>.remote` and
     `branch.<b>.merge`) missing → refuse "push the branch"; a repository
     with no remote at all → refuse "no remote";
   - **pushed** = `git merge-base --is-ancestor HEAD @{upstream}`: every
     local commit is on the remote-tracking ref. Local only, no network.
3. **Repository URL.** The upstream remote's URL (`git remote get-url
   <remote>`), turned into Cursor's form by `hosted-git-info` (npm's own
   maintained parser): for a host it knows (GitHub, GitLab, Bitbucket,
   sourcehut) its `https()` form without `.git` (`https://github.com/o/r`,
   the form Cursor's docs show); for any other host the remote URL as git
   has it, for Cursor to accept or refuse in its own words. No URL
   rewriting of our own.
4. **Create.** `Agent.create({ apiKey, mode, model?, cloud: { repos: [{ url,
   startingRef: <upstream branch name> }], workOnCurrentBranch: false,
   autoCreatePR: false } })`. `startingRef` is the upstream's branch name
   (`branch.<b>.merge` without `refs/heads/`), which may differ from the local
   name. See `OWNER: O2` on `workOnCurrentBranch`/`autoCreatePR`.
5. **Answer** `{ sessionId: agent.agentId, configOptions }` (P3). The ACP
   session id **is** the cloud agent's `bc-…` id: the adapter keeps no
   mapping, and a session reopens from any machine.
6. **The first message** (owner's decision 5), sent right after the answer
   (P2 gives its form). `CROSS:` runtime: the notification must be written
   after the `session/new` response, never before; chord draws an
   `agent_message_chunk` outside a turn as plain assistant text
   (`conversation.ts` stamps it; only agents with `startsOwnCycles()` open a
   cycle), so no chord change is needed — interface confirms the screen.

`OPEN:` whether `Agent.create` for cloud reaches Cursor at once or only on
the first `send()` ("cloud agents auto-generate a name from the first
prompt" hints the latter). The design does not depend on it, but if it is
lazy, the link in the first message 404s until the first prompt, and a
repository Cursor cannot reach (`IntegrationNotConnectedError`) is refused
on the first prompt, not at start. `Cursor.repositories.list()` could check
reach at start, but it lists GitHub only and needs URL matching; not
proposed.

### `session/prompt`

One `agent.send(message, options)` per prompt; one cloud agent per session.

```ts
send({ text, images }, {
  mode,                   // only when the person changed it since the last send
  model,                  // only when changed: model overrides are sticky
  idempotencyKey,         // a fresh UUID per prompt, so a retried request is not a second run
})
```

The adapter iterates `run.stream()` and maps each `SDKMessage` (P2). When the
stream ends it reads `run.wait()` for `RunResult` and answers:

| `RunResult.status` | ACP answer |
|---|---|
| `finished` | `{ stopReason: "end_turn", usage }` |
| `cancelled` | `{ stopReason: "cancelled", usage }` |
| `error` | JSON-RPC error, message from `RunResult.error.message` (`code` in `data`) |

`usage` is ACP's `Usage` from `RunResult.usage` (`TokenUsage`):
`inputTokens`, `outputTokens`, `cachedReadTokens` ← `cacheReadTokens`,
`cachedWriteTokens` ← `cacheWriteTokens`, `thoughtTokens` ←
`reasoningTokens`, `totalTokens`. chord reads it as every agent's
(`src/session/usage.ts`).

No `usage_update`: ACP's `UsageUpdate` needs `used` and `size` (the context
window), and the SDK gives no window size. Cost: `agent.getUsage({ runId })`
returns `UsageCost`, "eventually consistent", lagging after the run.
`OPEN:` whether to send a late `usage_update` with only `cost` — not
possible, `used`/`size` are required — so cost is not served in v1.

A `send()` that throws `AgentBusyError` (a run started on cursor.com or
another machine still runs) → JSON-RPC error with the SDK's message plus the
agent's link; chord shows it as a failed turn.

### `session/cancel`

`run.cancel()` on the session's current run. A cancel that arrives while
`send()` has not yet resolved is held and applied as soon as the `Run`
exists. Updates the stream yields after cancel are still forwarded until
the stream ends (ACP allows them before the prompt's answer); the answer is
`stopReason: "cancelled"` when `RunResult.status` is `cancelled`, else what
the status says (the run may have finished first). A `cancel()` that throws
is not an error of the turn: the answer follows `run.wait()`.

### `session/list`

`Agent.list({ runtime: "cloud", apiKey, cursor, limit })`, archived left out
(the SDK's default). Each `SDKAgentInfo` whose `repos` holds the cwd's
repository URL (normalized the same way, by `hosted-git-info`, on both sides)
becomes:

```json
{ "sessionId": "bc-…", "cwd": "<request cwd>", "title": "<SDKAgentInfo.name>",
  "updatedAt": "<ISO of lastModified>",
  "_meta": { "cursorCloud": { "status": "finished", "repos": ["https://github.com/o/r"] } } }
```

ACP's `cwd` filter is optional; `SessionInfo.cwd` is required and an
`SDKAgentInfo` has no cwd. Without a `cwd` the adapter lists for its own
process cwd. The SDK's `nextCursor` is passed through; since the filter is
the adapter's, a page may be short or empty with a cursor (ACP allows it).

Which agents: `OWNER: O3`. Note for the lead, `CROSS:` interface: chord's
`/resume` and `--resume` list **chord's own records** (`src/session/sessions.ts`),
never `session/list`; `session/list` reaches `chord acp` clients and chord's
MCP tools. So cloud agents started on cursor.com or another machine do not
appear in chord's own resume list, whatever O3 says, unless chord changes —
which the owner's "no change in chord" rules out for now.

### `session/resume` and `session/load`

Both: `Agent.resume(sessionId, { apiKey })` (the `bc-` prefix routes it to
cloud), then `Agent.get(sessionId, { apiKey })` for `SDKAgentInfo` and
`Agent.listRuns(sessionId, { runtime: "cloud", apiKey, limit: 1 })` for the
latest `Run`. Answer `{ configOptions }`, then the first message again, now
with the latest run's state (P2, P4). The agent's current model is
`SDKAgent.model`; its mode is not readable from the SDK (`OPEN:`): the
adapter shows `agent` until the person picks one.

- `session/resume` replays nothing; chord takes it whenever its record
  holds the past (`reopen` in `src/session/session.ts`), so it is chord's
  path.
- `session/load` replays: every run, oldest first (`Agent.listRuns` paged,
  ordered by `Run.createdAt`), each `run.conversation()` where
  `run.supports("conversation")`, mapped from `ConversationTurn`:
  - `agentConversationTurn.userMessage.text` → `user_message_chunk`;
  - `steps[]`: `assistantMessage` → `agent_message_chunk`;
    `thinkingMessage` → `agent_thought_chunk`; `toolCall` (the typed
    `ToolCall` union) → `tool_call` with status `completed`, or `failed`
    when its `result.status` is `"error"`, drawn as P2 draws live calls;
  - `shellConversationTurn` → a `tool_call` of kind `execute`, title the
    command, `rawOutput` its `ShellOutput`;
  - a run that does not support `conversation` (`unsupportedReason`) → one
    `agent_message_chunk` naming it, never a guess at its content.
  `OPEN:` the order of `Agent.listRuns` and whether `conversation()` works
  on every finished cloud run; the docs only say it renders "the run's
  structured history".

A run still `running` at reopen: see P4 ("finished or running while no one
watched").

### `session/close`

`agent.close()` (local handle only; the cloud agent stays, as it does when
chord quits). Answer `{}`.

### `session/set_config_option`

P3.

## P2. The stream mapping

Every text the adapter sends carries a `messageId`: one UUID per SDK
assistant message, per thinking message, and one per adapter line (first
message, `task`, `request`, status, end-of-run). chord's `appendText`
continues an entry only while the ids match or one is missing
(`src/session/transcript/messages.ts`), so without ids an adapter line would
glue onto the agent's text.

| SDK event | ACP `session/update` |
|---|---|
| `system` (`SDKSystemMessage`) | none drawn. Its `model`, when it differs from the option's current value, → `config_option_update` (P3). |
| `user` (`SDKUserMessageEvent`) | none live (it echoes the prompt chord already drew). In `session/load` replay → `user_message_chunk`. |
| `assistant` (`SDKAssistantMessage`) | each `TextBlock` → `agent_message_chunk` `{ type: "text", text }`. `ToolUseBlock`s are not drawn: the same call comes as a `tool_call` event. |
| `thinking` (`SDKThinkingMessage`) | `agent_thought_chunk` with `text`. |
| `tool_call` (`SDKToolUseMessage`) | first sight of a `call_id` → `tool_call`; later → `tool_call_update`. Below. |
| `status` (`SDKStatusMessage`) | `CREATING` → one adapter line "Cursor is starting the agent's machine…" (the docs: CREATING "covers VM provisioning and repo cloning", which can take a while with nothing else on screen). `RUNNING` → none. Terminal ones end the turn through `run.wait()`; `status.message`, when present, → an adapter line. |
| `task` (`SDKTaskMessage`) | `text` (with `status` in front when present) → an adapter line as `agent_message_chunk` with its own `messageId`. |
| `request` (`SDKRequestMessage`) | an adapter line, owner's decision 6: "Cursor's agent is waiting for input or approval (request `<request_id>`). It cannot be answered from here; open https://cursor.com/agents/<agentId> to answer it." Never answered. |
| `summary` (`SDKSummaryMessage`) | `running` → adapter line "Cursor is summarizing the conversation"; `completed`/`error` → none, `fallback: true` → a line saying so. |
| `usage` (`SDKUsageMessage`) | none drawn; summed for the prompt answer when `RunResult.usage` is absent. |

`SDKMessage` kinds the adapter does not know (a later SDK) are passed over.

### The first message

`agent_message_chunk`, not a `session_info_update` (chord does not draw one)
and not `_meta` (the owner wants it seen with no chord change):

```json
{ "sessionUpdate": "agent_message_chunk", "messageId": "…",
  "content": { "type": "text",
    "text": "Cursor cloud agent on github.com/o/r, starting from branch `feature/x`.\nhttps://cursor.com/agents/bc-…" } }
```

On resume/load it says the agent's repository and its latest run's state
(running, finished with branch/PR, error with its message).

The link: no SDK type carries a web URL for an agent. Cursor's Cloud Agents
API documents `"url": "https://cursor.com/agents/bc-…"` on its agent object;
the adapter builds `https://cursor.com/agents/<agentId>` from that form.
`OWNER: O4`.

### The end of a run

Before the answer, one adapter line from `RunResult.git.branches[]`
(`RunGitBranchInfo`: `repoUrl`, `branch?`, `prUrl?`): "Pushed to `<branch>`
on `<repo>`" and the PR link when there is one, then
`agent.listArtifacts()` (`SDKArtifact`: `path`, `sizeBytes`) as a list of
paths when non-empty. This is how the person sees the result (decision 7);
nothing is pulled.

### `tool_call`

The docs mark `args` and `result` unstable; `SDKToolUseMessage` types them
`unknown`. The SDK's `ToolCall` union (`ShellToolCall`, `ReadToolCall`,
`EditToolCall`, …) types the same tools in `ConversationStep`, and
`AgentOptions.tools` says tool names are "the same names carried by
`tool_call` stream events". The adapter uses those names and nothing else:

```json
{ "sessionUpdate": "tool_call", "toolCallId": "<call_id>",
  "title": "shell: npm test", "kind": "execute", "status": "in_progress",
  "rawInput": { "command": "npm test" } }
```

- `toolCallId` = `call_id`. `status`: `running` → `in_progress`,
  `completed` → `completed`, `error` → `failed`.
- `kind` by `name`, only for names in the SDK's `ToolType`/`ToolName`
  vocabulary: `shell` → `execute`; `read` → `read`; `edit`, `write` → `edit`;
  `delete` → `delete`; `grep`, `glob`, `ls`, `semSearch` → `search`;
  `webFetch` → `fetch`; anything else → `other`.
- `title` = `name`, plus `: <value>` when the one field the SDK's own type
  names for that tool is present and a string: `command` (`ShellArgs`),
  `path` (`ReadArgs`, `EditArgs`, `WriteArgs`, `DeleteArgs`, `LsArgs`),
  `pattern` (`GrepArgs`), `globPattern` (`GlobArgs`), `description`
  (`TaskArgs`). Any other
  shape gives the bare name. No other field is read.
- `rawInput` = `args`, `rawOutput` = `result`, as they come. When
  `truncated.args`/`truncated.result` is set, `_meta.cursorCloud.truncated`
  says so.
- No `locations`: paths are in Cursor's VM, not under the person's cwd;
  chord would draw them as local files. No `content` diff: ACP's `diff`
  needs `oldText`/`newText`, and the SDK's `EditSuccess` gives a
  `diffString` only.
  `CROSS:` interface — how chord draws a tool call with only `title`,
  `kind`, `rawInput` and `rawOutput`, and whether an edit's `diffString`
  should go as a text `content` block instead (it is the SDK's own text,
  not ours).
- `updateTodos` additionally → `plan` from `UpdateTodosArgs.todos`
  (`TodoItem`: `content`, `status`): `pending` → `pending`, `inProgress` →
  `in_progress`, `completed` → `completed`. `cancelled` has no ACP status:
  `OWNER: O5`.

`OPEN:` whether a cloud `assistant` event carries a new piece of text or the
whole message so far. The types do not say. Pieces concatenate correctly;
whole-so-far snapshots would draw the text repeated. The adapter assumes
pieces (as the `onDelta`-free `stream()` examples read), and the first
authorized live check confirms it before the package ships. If they are
snapshots, the fix is one `messageId` per assistant message with the
latest text only — which ACP has no "replace" for: that would go back to the
owner.

## P3. Modes, models, artifacts, env vars

### Choice: config options

chord reads `mode` and `model` from `configOptions` first
(`src/session/modes.ts`, `models.ts`) and riff serves them that way.
`session/set_mode` and the unstable `set_model` are not served.

```json
"configOptions": [
  { "id": "mode", "name": "Mode", "category": "mode", "type": "select",
    "currentValue": "agent",
    "options": [ { "value": "agent", "name": "Agent" }, { "value": "plan", "name": "Plan" } ] },
  { "id": "model", "name": "Model", "category": "model", "type": "select",
    "currentValue": "default",
    "options": [ { "value": "default", "name": "Cursor's default" },
                 { "value": "<json ModelSelection>", "name": "<ModelVariant.displayName>" } ] }
]
```

- **Mode** (`AgentModeOption`). Changing it answers at once with the new
  options; it is sent as `SendOptions.mode` on the next `send()` only, since
  "omit `mode` to keep the conversation's current mode" (docs). A change
  while a run is going applies to the next prompt. shift+tab walks it.
- **Model** from `Cursor.models.list()` at `session/new`/`resume`.
  `"default"` stands for leaving `model` out, which the SDK documents for
  cloud ("the server resolves the caller's configured default"); it is not
  an invented model. Each `ModelListItem` with `variants` gives one option
  per `ModelVariant` (`displayName`, its `params`), the value being the
  `ModelSelection` `{ id, params }` as JSON; one without variants gives one
  option, `{ id }`, named `displayName`. Variants come from the SDK as they
  are; the adapter does not pick which parameter is "effort", so no
  `thought_level` option. `CROSS:` interface on how long the `/model` list
  gets; `OWNER: O6` if variants are too many.
  A change goes as `SendOptions.model` on the next `send()` ("per-run model
  overrides are sticky") and applies from the next run; a running run
  keeps its model (`Run.model` "fixed once the run starts").
  After a run, `SDKSystemMessage.model` / `RunResult.model` names what ran;
  a different value → `config_option_update`.
- A failed `Cursor.models.list()` (network) leaves only `"default"`; the
  session still opens.
- **Artifacts**: listed in the end-of-run line (P2). No download: ACP has no
  file transfer to the client, and pulling results is a non-goal.
- **Env vars** (`CloudAgentOptions.envVars`, `CloudSendOptions.envVars`): not
  served. ACP has no field for them, and secrets typed into a prompt are not
  the way in. Out of scope for v1.
- **`metadata`** (`CloudAgentOptions.metadata`): not set, unless O3 picks
  "this adapter's agents only".

## P4. Errors and refusals

ACP error objects; chord shows `<agent> did not start: <message>` for
start refusals and a failed turn for prompt errors. The words below are
proposals; `CROSS:` interface owns how they read on screen.

| Case | When | ACP | Message |
|---|---|---|---|
| No key at all | `session/new`/`load`/`resume` | `-32000` authRequired | "Not signed in to Cursor." (CHD-435 adds the `authMethods` line) |
| Key refused (`AuthenticationError`: expired, revoked, Team Admin key) | `Cursor.me` at start; any call later | `-32000` | the SDK's message as it is |
| Not a git work tree | `session/new` | `-32602` invalid params | "`<cwd>` is not in a git repository; Cursor cloud agents work on a pushed branch." |
| No remote | `session/new` | `-32602` | "This repository has no remote. Push it to GitHub or another host Cursor reaches, then start again." |
| Detached HEAD | `session/new` | `-32602` | "No branch is checked out. Check out a branch and push it." |
| No upstream / not pushed | `session/new` | `-32602` | "Branch `<b>` is not pushed. Push it (`git push -u`) and start again." / "…has commits not on `<remote>/<b>`. Push them and start again." |
| `IntegrationNotConnectedError` | `Agent.create` or first `send` | `-32603` at start, prompt error later | the SDK's message and `helpUrl` |
| `RateLimitError` (quota, usage limit) | `send`/stream | prompt error | the SDK's message; no automatic retry |
| `AgentBusyError` | `send` | prompt error | the SDK's message and the agent's link |
| `AgentNotFoundError` | `resume`/`load` | `-32002` resource not found | the SDK's message |
| archived (`ConfigurationError`, code `agent_archived`) | `resume`/`load`/`send` | `-32602` | the SDK's message |
| `NetworkError` mid-stream | `run.stream()` throws | prompt error | "Lost the connection to Cursor; the agent keeps running there: <link>. Reopen the session to see where it got to." |
| Other `CursorSdkError` | any | `-32603` | the SDK's message, `code`/`requestId` in `data` |

Notes:

- No message parsing: every class above is an SDK class or code. A Team
  Admin key is not told apart from other refused keys; the SDK's own message
  says what it is.
- **Network loss.** The adapter does not reattach on its own. `Agent.getRun`
  and a second `stream()` exist, but "cloud SSE streams retain backlog for a
  window", so a reattached stream may replay events already drawn, and
  nothing in `SDKMessage` (no sequence number) lets the adapter drop them
  without guessing. `OWNER: O7` if the owner wants a reconnect.
- **A cancelled turn**: P1.
- **The adapter exits** (chord quits or the process dies): the cloud run
  goes on in Cursor's VM; nothing to send. `CROSS:` runtime owns what the
  person is told when chord quits during a run.
- **Late updates.** After a prompt's answer the adapter has stopped reading
  that run's stream; nothing late reaches chord. A run started elsewhere
  while the session is open is not watched (`AgentBusyError` on the next
  prompt says so).
- **Finished, failed or still running while no one watched.** At
  `resume`/`load`, the latest `Run` from `Agent.listRuns`: its `status`,
  `git` and `error` go into the first message. If it is still `running`,
  the first message says so with the link, and a prompt is refused with
  `AgentBusyError` until it ends. Following that run live is possible
  (`Agent.getRun(...).stream()` and updates outside a turn), but chord would
  draw it as an agent turn the person did not start: `OWNER: O8`.

## P5. Local state and the credential store

- **Agent state.** Cloud agents "persist state server-side, so `local.store`
  applies to local agents only" (docs). The adapter always passes
  `runtime: "cloud"` to `Agent.list`/`listRuns`/`getRun` and resumes only
  `bc-` ids, so neither the `node:sqlite` store nor `JsonlLocalAgentStore` is
  opened. The adapter keeps **no state of its own**: the session id is the
  agent id, mode and model choices live in memory for the process.
  chord's record keeps what it keeps for any agent; nothing new.
- **`SdkCredentialStore`** (`auth/credential-store.d.ts`):
  ```ts
  interface SdkCredentialStore {
    load(): Promise<StoredSdkCredentials | undefined>;
    save(credentials: StoredSdkCredentials): Promise<void>;
    clear(): Promise<void>;
  }
  interface StoredSdkCredentials {
    version: 1; backendUrl: string; apiKey: string;
    apiKeyExpiresAtMs?: number; email?: string; createdAtMs: number;
  }
  ```
  The keyring store keeps the whole `StoredSdkCredentials` as one JSON
  secret (one keychain entry, service `@chorded/cursor-cloud-acp`); a
  missing or foreign-shaped entry loads as `undefined`, as
  `FileCredentialStore` does. `login` is `Cursor.auth.login({ store,
  apiKeyName: "chord cursor cloud" })`; `logout` and `status` take the
  same store (`SdkLogoutOptions.store`, `SdkAuthStatusOptions.store`).
  `CROSS:` runtime owns the keyring library and the headless fallback (R5);
  the interface above is all the store must satisfy.
- **Which key a call uses.** The SDK's order is "explicit `apiKey`, then
  `CURSOR_API_KEY`, then the stored login". To keep `CURSOR_API_KEY`
  working as the SDK reads it, the adapter passes `apiKey` only when
  `CURSOR_API_KEY` is unset and the keyring holds an unexpired key
  (`apiKeyExpiresAtMs`); otherwise it passes none and the SDK resolves.
  Passing none means the SDK may still use its own file
  (`~/.cursor/sdk/auth.json`) if another SDK program logged in there:
  `OWNER: O9`.

## Questions for the owner

- **O1 — ACP `authenticate`.** chord never calls it. Other ACP clients may.
  (a) Answer it with an error naming the `login` command. (b) Run
  `Cursor.auth.login({ store })` from the adapter: the browser opens, the
  URL goes to stderr, nothing touches stdout. Recommend **(a)** for v1: the
  owner put sign-in in the package's `login` command, and (b) opens a
  browser from a process the person may not have started by hand. Decision
  9 ("serve whatever ACP methods the SDK supports") leans to (b); the
  owner's call.
- **O2 — Where the agent pushes.** `workOnCurrentBranch` (push to the
  person's branch) and `autoCreatePR`. Recommend **both false**: the agent
  pushes a new branch of its own, the person's branch is never written by a
  remote run, and decision 7 (the person decides) means no PR unasked. The
  person can still tell the agent to open one.
- **O3 — Which agents `session/list` returns.** (a) Every cloud agent on the
  key's account for this cwd's repository, whoever started it (cursor.com,
  another machine, this adapter). (b) Only agents this adapter created,
  tagged with `CloudAgentOptions.metadata`. (c) Every cloud agent on the
  account, any repository. Recommend **(a)**: cloud agents are server-side
  and "reattaching from anywhere returns the same conversation"; the
  repository filter keeps the list to the cwd. Either way chord's own
  `/resume` shows only chord's records (P1).
- **O4 — The link.** No SDK type has a web URL. (a) Build
  `https://cursor.com/agents/<agentId>`, the form Cursor's Cloud Agents API
  returns as `url`. (b) No link; name the agent id only. Recommend **(a)**:
  it is Cursor's own documented form; the owner's decision 5 asks for a
  link.
- **O5 — A cancelled todo.** ACP plan entries are `pending`, `in_progress`,
  `completed`. (a) Leave cancelled todos out of the `plan` (they stay in the
  tool call's `rawInput`). (b) Send no `plan` at all for `updateTodos`, only
  the tool call. (c) Show them as `completed`. Recommend **(a)**; (c) says
  something untrue.
- **O6 — Model variants.** If `Cursor.models.list()` gives many variants per
  model, the `/model` list grows long. (a) One option per variant
  (proposed). (b) One option per model, the server choosing params.
  Recommend **(a)** unless the first live check shows a list too long to
  use; then (b).
- **O7 — Reconnect after network loss.** (a) None: the turn fails, saying
  the agent keeps running, and reopening shows the state (proposed). (b)
  Reattach with `Agent.getRun(...).stream()` and accept that events may be
  drawn twice. Recommend **(a)**.
- **O8 — A run still going at reopen.** (a) Say so in the first message and
  refuse prompts until it ends (proposed). (b) Follow it live as updates
  outside a turn. Recommend **(a)**: (b) makes chord draw a turn nobody
  started there.
- **O9 — The SDK's own login file.** With no `CURSOR_API_KEY` and nothing in
  the keychain, the SDK falls back to `~/.cursor/sdk/auth.json`, which
  another SDK program may have written. (a) Accept it: it is the SDK's
  documented order. (b) Avoid it, which needs the adapter to override where
  the SDK looks (a workaround the one rule forbids without the owner).
  Recommend **(a)**.

## Open facts for the first live check

Each needs an authorized run against Cursor, with a tiny prompt:

1. Whether `assistant` events are pieces or snapshots (P2).
2. Whether `Agent.create` reaches Cursor before the first `send()` (P1).
3. `Agent.listRuns` order and `run.conversation()` on finished cloud runs
   (P1).
4. Whether a cloud agent's mode can be read back after `resume` (P1).
5. How many variants `Cursor.models.list()` gives (O6).
