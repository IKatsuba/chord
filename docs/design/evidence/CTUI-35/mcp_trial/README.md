# mcp_dart trial against chord's MCP server

A reproducible comparison of one small MCP server built twice:

- `dart/bin/server.dart`: pub package `mcp_dart` 2.4.4 (pinned exactly,
  `dart/pubspec.lock` checked in), its `StreamableHTTPServerTransport`
  behind a `dart:io` `HttpServer` that does chord's admission.
- `ts/server.ts`: the original `@modelcontextprotocol/sdk` 1.32.2 and zod,
  used as `../chord/src/server/server.ts` and `../chord/src/server/tools.ts`
  use them (`WebStandardStreamableHTTPServerTransport`, stateful, one
  `McpServer` per initialize, `server.registerTool` with zod raw shapes,
  `Bun.serve` as `../chord/src/platform/serve.ts` calls it).

Both servers have the same admission layer, written as `server.ts` has it:
no or unknown bearer token is 401 `Unknown token`; an unknown
`Mcp-Session-Id` is 404 `Session not found`; a session opened with another
token is 403 `Session opened with another token`; a request without a
session id that is not an initialize request is 400
`No session; initialize first`; each body is
`{"jsonrpc":"2.0","error":{"code":-32000,"message":...},"id":null}`.

Two roles, one token each: `main` has `send_message {to, text}`,
`close_agent {to}` and `clear_agent {to}`; `task` has
`send_message {text}`. The handlers answer fixed values in chord's shapes:
`send_message` answers `JSON.stringify({delivered:'sent',to:'parser'},null,2)`;
`close_agent` with `to: 'gone'` refuses with
`No agent gone is open in this session; list_sessions names them` and
`isError: true`; `close_agent` otherwise says `<to> has already ended` with
`structuredContent: {ended: <to>}`; `clear_agent` says
`<to> (id a1) has a fresh session; it knows nothing of earlier turns.` with
`structuredContent: {cleared: <to>, id: 'a1'}`. Tool descriptions are
shortened to one sentence each, the same on both sides; the property
descriptions are chord's.

Each server prints one JSON line on stdout, `{url, tokens: {main, task}}`,
and nothing else. A line `revoke <token>` on stdin revokes a token as
`revoke()` in `server.ts` does (the token is refused, its sessions are
closed); the server acknowledges it on stderr with `revoked <token>`.

## Reproducing

From this directory, with `../chord` checked out beside the repository
root and its dependencies installed (`bun install` there):

```sh
deno run --allow-run --allow-read --allow-write --allow-env --allow-net \
  --allow-sys run.ts
```

`run.ts` runs `dart pub get` in `dart/`, then the same 46-step request
sequence against three servers: `dart run bin/server.dart`, a binary from
`dart compile exe` written to a scratch directory outside the repository,
and `bun --no-install server.ts`. It writes `results/dart.json`,
`results/dart_exe.json`, `results/ts.json`, each server's stderr as
`results/<name>.stderr.txt`, and `results/diff.md`, every JSON path where
`dart.json` and `ts.json` differ. It deletes its scratch directory and
`dart/.dart_tool/` when done.

`CHORD_SOURCE` selects another chord checkout (a worktree of this
repository has no `../chord` beside it), `CHORD_BUN` another bun.

How the TypeScript server reaches the SDK: bun resolves an ES module's bare
imports from the script's own directory upward and does not read
`NODE_PATH` for them; with no `node_modules` found it auto-installs, and in
a first attempt it loaded the SDK from bun's global cache next to
`../chord`'s `ajv-formats`, and every initialize failed with 500
(`TypeError: undefined is not an object (evaluating 'ajv.opts.code')`).
So `run.ts` copies `ts/server.ts` into the scratch directory beside a
`node_modules` symlink to `../chord/node_modules`, and runs bun with
`--no-install`. Nothing is copied into the repository. By hand:

```sh
mkdir -p <scratch>/ts_server
cp ts/server.ts <scratch>/ts_server/
ln -s "$PWD/<path to chord>/node_modules" <scratch>/ts_server/node_modules
(cd <scratch>/ts_server && bun --no-install server.ts)
(cd dart && dart pub get && dart run bin/server.dart)
```

Normalisation: tokens, session ids and other UUIDs are placeholders;
`text/event-stream` bodies are split into events with `data:` parsed as
JSON; of the response headers only `content-type`, `mcp-session-id`,
`mcp-protocol-version`, `allow`, `cache-control` and `www-authenticate` are
kept. Every request carries `Accept: application/json, text/event-stream`
and, once a session is open, `MCP-Protocol-Version: 2025-11-25`, unless the
case says otherwise. Key order is compared, as it is visible on the wire.

## Versions

| What | Version |
| --- | --- |
| Dart SDK | 3.13.5 (stable), macos_arm64 |
| mcp_dart | 2.4.4 (pinned; transitive: see `dart/pubspec.lock`) |
| bun | 1.4.4 |
| @modelcontextprotocol/sdk | 1.32.2 (`../chord/node_modules`) |
| zod | 4.6.7, imported as `@zod/zod` (`npm:zod@^4.6.5`) as chord does |
| Deno (runner) | 2.9.7 |

## Results

The compiled Dart binary answered exactly as `dart run` did. Identical on
both sides: the admission layer's answers (cases 01-04, 07, 11, 12, 40, 44,
45: same status, code, wording and `id: null`), the five tool answers
(17-21), an extra unknown argument (26: accepted and served by both,
neither schema has `additionalProperties`), the `required` arrays and their
order (`["to","text"]`), `execution: {"taskSupport":"forbidden"}` on every
tool, the negotiated `protocolVersion` `2025-11-25` and `serverInfo`, and a
GET stream on a session (37: neither sent response headers within 5 s).

Every difference, case by case (full detail in `results/diff.md`):

| Case | Dart (mcp_dart 2.4.4) | TS (SDK 1.32.2) |
| --- | --- | --- |
| Every JSON answer, admission's included | `content-type: application/json; charset=utf-8` | `application/json;charset=utf-8` (admission, `Response.json`) or `application/json` (SDK) |
| Every SSE answer | `content-type: text/event-stream; charset=utf-8` | `text/event-stream` |
| 202 to a notification (09, 15, 42); 200 to DELETE (39) | empty body with `content-type: text/plain; charset=utf-8` | empty body, no `content-type` |
| JSON-RPC member order in SSE messages | `{"jsonrpc","id","result"}` | `{"result","jsonrpc","id"}` |
| Member order in transport HTTP errors with an id | `{"jsonrpc","id","error"}` | `{"jsonrpc","error","id"}` |
| 08, 14, 41 initialize result | `"capabilities":{"tools":{}}` | `"capabilities":{"tools":{"listChanged":true}}` |
| 13, 16 tools/list `inputSchema` | no `$schema`; properties as `{"description":...,"type":"string"}` | `"$schema":"http://json-schema.org/draft-07/schema#"` first; properties as `{"type":"string","description":...}` |
| 05 initialize, `Accept: application/json` only | 406, -32000 `Not Acceptable: Client must accept both application/json and text/event-stream`, `"id":1` | 406, same code and wording, `"id":null` |
| 06 initialize, `Content-Type: text/plain` | 415, -32000 `Unsupported Media Type: Content-Type must be application/json`, `"id":1` | 415, same code and wording, `"id":null` |
| 30, 31 wrong or no Accept on a session | 406, same wording as 05, no `id` member at all | 406, same wording, `"id":null` |
| 38 PUT on a session | 405, `Allow: GET, POST, DELETE`, -32000 `Method not allowed.`, no `id` member | 405, same header, code and wording, `"id":null` |
| 35 re-initialize on an open session | 400, -32600 `Invalid Request: Server already initialized`, `"id":21` | 400, same code and wording, `"id":null` |
| 29 malformed JSON on a session | 400, -32700 `Parse error`, `"data":"FormatException: Unexpected end of input (at character 19)\n{\"jsonrpc\": \"2.0\",\n                  ^\n"`, no `id` member | 400, -32700 `Parse error: Invalid JSON`, `"id":null` |
| 36 body without `jsonrpc` | 400, -32600 `Invalid Request`, `"data":"FormatException: Invalid JSON-RPC version: null"`, `"id":22` | 400, -32700 `Parse error: Invalid JSON-RPC message`, `"id":null` |
| 32 `MCP-Protocol-Version: 1999-01-01` | 400, -32022 `Unsupported protocol version`, `"data":{"requested":"1999-01-01","supported":["2026-07-28","2025-11-25","2025-06-18","2025-03-26","2024-11-05","2024-10-07"]}`, `"id":17` | 400, -32000 `Bad Request: Unsupported protocol version: 1999-01-01 (supported versions: 2025-11-25, 2025-06-18, 2025-03-26, 2024-11-05, 2024-10-07)`, `"id":null` |
| 34 batch `[ping, tools/list]` | 400 JSON, -32600 `Invalid Request: Batch JSON-RPC payloads are not supported`, no `id` member | 200 SSE, two events: `{"result":{},"jsonrpc":"2.0","id":19}` and the tools/list result with id 20 |
| 22 task calls `close_agent`; 27 unknown tool `no_such_tool` | JSON-RPC error `{"code":-32602,"message":"Tool 'close_agent' not found"}` | tool result `{"content":[{"type":"text","text":"MCP error -32602: Tool close_agent not found"}],"isError":true}` |
| 23 missing `text` | result `isError: true`, `Invalid arguments for tool 'send_message': JsonSchemaValidationException: Required property is missing: text (at )` | result `isError: true`, `MCP error -32602: Input validation error: Invalid arguments for tool send_message: Invalid input: expected string, received undefined at text` |
| 24 no `arguments` | `Invalid arguments for tool 'close_agent': JsonSchemaValidationException: Required property is missing: to (at )` | `MCP error -32602: Input validation error: Invalid arguments for tool close_agent: Invalid input: expected string, received undefined at to` |
| 25 `to: 5` | `Invalid arguments for tool 'close_agent': JsonSchemaValidationException: Value does not match schema type string (at to)` | `MCP error -32602: Input validation error: Invalid arguments for tool close_agent: Invalid input: expected string, received number at to` |
| 28 unknown method | -32601 `Method not found: no/such_method` | -32601 `Method not found` |

The task role's `send_message` schema, as each side lists it:

```json
{"type":"object","properties":{"text":{"description":"What to tell it","type":"string"}},"required":["text"]}
{"$schema":"http://json-schema.org/draft-07/schema#","type":"object","properties":{"text":{"type":"string","description":"What to tell it"}},"required":["text"]}
```

## Observed while building the Dart side

- `StreamableHTTPServerTransportOptions` has `onsessioninitialized` but no
  `onsessionclosed`. `McpServer.connect()` assigns `transport.onclose` to
  the protocol's own handler, so a hook set before `connect()` is replaced.
  In a first run with the hook set before `connect()`, a request after
  DELETE was answered by the closed transport (404 `Session not found` with
  `"id":23`) rather than by the admission layer (`"id":null`): the session
  had stayed in the admission map. `bin/server.dart` now chains its hook
  after `connect()`, and case 40 answers as the TS side does.
- mcp_dart's transport options default to `enableDnsRebindingProtection:
  true` (allowed hosts `localhost`, `127.0.0.1`, `::1`),
  `strictProtocolVersionHeaderValidation: true` and
  `rejectBatchJsonRpcPayloads: true`; the trial keeps the defaults. Requests
  to `127.0.0.1:<port>` were admitted.
- mcp_dart lists `2026-07-28` among its supported protocol versions (case
  32); the SDK's list ends at `2025-11-25`.
- `dart/` is a package of its own inside the repository tree, so the
  repository root's `dart analyze` analyzes it too; before `dart pub get`
  has been run in `dart/`, that reports 22 unresolved-import errors in
  `bin/server.dart`. `dart/analysis_options.yaml` keeps it from including
  the root's `package:lints` options, which it cannot resolve.
