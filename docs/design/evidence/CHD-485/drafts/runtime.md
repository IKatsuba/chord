# CHD-485 runtime draft: processes, build, tools, sign-in, credentials, tests

The runtime architect's answer to the brief's "runtime" section. It brings
options, evidence and recommendations for Q2 and Q4, the processes for Q1
(with protocol), and the evidence for Q9. It settles none of them.

Everything was read from libfx 0.0.16 as `npm pack libfx@0.0.16` unpacked it
into a new, empty scratch directory, and from vercel-labs/fx at tag `v0.0.16`
(commit `481104fd`). Every trial ran on darwin-arm64, Bun 1.4.4, in scratch
directories outside the repository, against fake `localhost` servers or an
injected `fetch`. No real model, provider or sign-in endpoint was reached.
Bun.secrets trials used a throwaway service name (`chord-trial-<uuid>`), and
everything they wrote was deleted afterwards and checked gone.

Revised once after the critic's findings, as the lead accepted them (2, 3,
4, 8, 9, 12, 13): the credential contract under the lock, sign-in in the
window in both Q1 options, logout against refresh, retries, the permission
contract, the listener's order, and Bun.secrets' scope. "Revision" below
marks what changed.

## What the trials found, first

These change the design more than anything else here.

1. **fx's own tools cannot be turned on through libfx.** The native core is
   fx's ACP server started with `args: ["acp"]` (`engine.js:1611`); libfx
   sends its host tools in `initialize` under `clientCapabilities.libfx`
   (`engine.js:1790-1797`), and with those the core's only tool of its own
   is the provider-run `web_search` (fx `src/acp/server.zig:63-66`,
   `2647-2661`). `createCore` takes no tool option (`node.js:358-369`). T1:
   the model request advertised exactly the host's two tools and nothing
   else. Every tool is chord's.
2. **The native core reads no AGENTS.md or skills from the workspace.** T1
   put a marker in `AGENTS.md` in the working directory and in `$HOME`: the
   system message held the host's instructions alone (49 bytes). The core
   is given `home: homedir()` and `workspaceRoot: process.cwd()`
   (`node.js:362-363`), undocumented in the types. Whatever chord wants the
   model to know of the project, it puts in `instructions` itself
   (protocol's to place).
3. **`fetch` is the whole network seam.** `fetch` is documented as
   "Replaces the global `fetch` for model and catalog requests"
   (`types/libfx.d.cts:440`); the engine sends every provider request
   through it (`engine.js:1458-1494`), the native core's own requests come
   back to JavaScript to be fetched (`node.js:445-530`), and the sign-in and
   refresh functions each take `{ fetch, signal }` (`chatgpt-sign-in.js:62,
   74, 101, 130`; `grok-sign-in.js:54, 78, 126, 132`; `chatgpt.js:33`;
   `grok.js:48, 70`). T3b and T3c ran a whole Codex-plan turn and a whole
   Grok-plan turn with no network: a fake `fetch` answered a minimal
   Responses API stream and the turn ended `end_turn` with the text.
4. **Before its first turn the core asks the network for a client
   version.** Codex: `GET https://registry.npmjs.org/@openai/codex/latest`,
   then `GET https://chatgpt.com/backend-api/codex/models?client_version=…`.
   Grok: `GET https://x.ai/cli/stable` (unanswered, the turn fails with
   `ProviderVersionUnavailable`), then the proxy's `/v1/models` and
   `https://api.x.ai/v1/language-models`. Seen through the injected `fetch`
   in T3b and T3c. The fake must answer these too.
5. **A persistent 5xx was still being retried at 300 s.** Revision: what
   was observed, no more. T7, native: with every model request answered
   500, a custom-provider turn sent 15 requests and a Codex-plan turn 16 in
   300 s, at 0, 0, 1, 3, 7, 15, 31, 61, 91, … 271 s. The backoff doubles to
   30 s and then repeats every 30 s. Neither turn ended by itself; the
   300 s cap cancelled both (`stopReason: cancelled`). In the code read:
   the JS edge tries each fetch twice (`engine.js:1477-1517`); fx's transport
   loop is capped by its `retry_count` (fx `src/gateway/client.zig:678,
   1512-1515`), but for agent-owned attempts that count is 1, and the
   agent-level retry policy that produced T7's schedule was not found in
   the files read. Whether it ever ends was not established. A 401
   refreshed once through the same `fetch`, called `onCredentials` with
   the rotated refresh token and retried (`subscription.js:238-252`; T3).
6. **Cancellation is prompt and does not wait for host tools.** T2, native:
   `cancel()` ended a turn in at most 11 ms with `stopReason: cancelled`
   whether the model hung, the stream was mid-reply, or a tool never
   settled; `close()` in at most 6 ms. A tool that ignores its `signal` is
   simply abandoned (`engine.js:1579` races it against the abort), so its
   work goes on in chord's process unless the tool itself stops it.
7. **On one macOS machine, Bun.secrets stopped settling under 20
   concurrent calls.** Scope: macOS Keychain, Bun 1.4.4, two separate
   processes on one machine; nothing else. T4b: 2, 5 and 10 concurrent
   `set`s on one name settled (the last write won). 20 concurrent `set`s:
   two settled, eighteen did not within 15 s, and every later
   `Bun.secrets` call in that process (`get`, `delete`, `set` on other
   names) did not settle within its own 15 s either, while the event loop
   stayed free (13,068 1 ms timer ticks in 15 s). A fresh process then read
   and deleted the entries normally. Unverified: Linux's Secret Service, a
   locked keychain, whether those calls would ever have settled, and where
   the threshold lies between 10 and 20. Calls one at a time never stuck
   (T4, T4b, every run). The design keeps the store's calls serial; it adds
   nothing else on this evidence.
8. **Bun's bundler cannot pick one addon per target from source alone.**
   Four per-platform modules behind `process.platform`/`process.arch`
   branches, or behind a `define`d constant, embedded all four addons
   (+34 MB on darwin-arm64). A compile plugin that resolves one virtual
   specifier to the target's `libfx.node` with `loader: 'file'` embedded
   only that one: 99,413,858 bytes on darwin-arm64 and 120,764,592 on
   linux-x64, the gate's sizes to the byte.
9. **`createFxAgent` without an explicit durability fails in the binary.**
   Its default loads `./durable/local.mjs` by `new URL(…, import.meta.url)`
   (`node.js:686-694`): compiled, `ERR_MODULE_NOT_FOUND
   '/$bunfs/root/durable/local.mjs'`. With `durability: local({ dir })`
   imported statically from `libfx/durable-local`, or `memory()`, a turn
   ended `end_turn` in the compiled binary. Its default directory is under
   the system's temporary directory (`node.js:675`), not chord's state.
10. **A binding to `localhost` can land on `::1` beside another sign-in's
    `127.0.0.1`.** T5b: with a second process holding `127.0.0.1:1455`
    (as fx or the Codex CLI would), `Bun.serve({ hostname: '::1', port:
    1455 })` succeeded, and a `fetch('http://localhost:1455/…')` from Bun
    reached the `::1` listener, not the holder. `hostname: 'localhost'`
    bound `::1` silently in the same case (T5).

## Processes in each Q1 option

Q1 is the owner's. The two options as the brief names them, and what runs
where in each.

### Q1-A: in-process, beside the ACP connections

```text
chord (one process)
├── OpenTUI, the session layer, chord's MCP server
├── libfx JS: engine, credential edge, sign-in calls
├── libfx native core: fx's ACP server, ~9 threads per engine (T2: 11 → 20)
│     or Wasm on the main thread when native cannot load
├── chord's host tools (read, edit, search) on the event loop
└── children: shells (src/shell.ts), MCP stdio servers, other agents' groups
```

- The engine speaks ACP to chord's code through an object, not a pipe: the
  session layer needs an `Agent` (`src/acp/connection.ts:114`) whose
  implementation wraps libfx (protocol's mapping). It has no `pid`, no
  stderr and no `exited` of a process; `exited` settles from libfx's
  `runtime.exit` (`engine.js:1712-1722`).
- **A crash of the native core is a crash of chord.** A segfault or abort
  in `libfx.node` takes the window down with the terminal in raw mode;
  chord's crash screen does not run for a signal it cannot catch. Nothing in
  libfx isolates it. A core that exits without crashing (`coreExited`,
  `node.js:563-566`) fails pending requests with `fx-core exited with code
  …` and the turn ends `error`; chord can open a new engine.
- A native load failure is not a crash: `backend: 'auto'` falls back to
  Wasm (`node.js:612-655`). T: with `TMPDIR` pointed at a missing
  directory, the compiled binary's native load failed (`dlopen … no such
  file`, Bun writes the addon there first) and Wasm loaded from the
  embedded bytes. A `noexec` temporary directory was not tried (no Linux
  container was available this run); it should fail the same way, at
  `dlopen`.
- Memory, T6 (Bun's `rss` on macOS): native, 13 MB before, +2 MB for the
  first engine and turn, under +1 MB each after. Wasm: +41 MB for the first,
  +1 to 6 MB each after, 53 MB still held after every `close()`.
- A blocking host call blocks the window: a tool must not do synchronous
  file work on a large tree; Bun.secrets calls stay asynchronous (T4b: the
  loop kept ticking).
- Quitting: `engine.close()` returned in at most 6 ms in every T2 case, a
  stuck tool included. The window's existing way out
  (`src/session/leaving.ts`, `LEAVE_MS` 15 s) needs one more step, each
  engine's `close()`, plus stopping the shells chord's tools started, which
  `spawnGroup`'s registry already covers (`src/platform/process.ts:175`).

### Q1-B: an ACP agent chord starts itself

```text
chord (window)                          chord <sub> (agent process, own group)
├── OpenTUI, sessions, MCP server  ACP  ├── libfx JS + native core (or Wasm)
└── spawnAgent → stdio ───────────────► ├── chord's host tools
                                        └── shells, MCP stdio servers
```

- The subcommand is `execPath()` (`src/platform/process.ts:199`) with a
  subcommand name, started by `openAgent` (`src/acp/connection.ts:241`) in
  its own process group like any agent. The existing stop bounds hold:
  stdin end, SIGTERM, SIGKILL, 2 s each (`src/acp/process.ts:18-22`), and
  `LEAVE_MS` needs no change.
- A native crash takes the agent process only: the window sees the
  connection go, `gone()` gives the stderr tail, and the person can start
  it again. This is the isolation Q1-A lacks.
- The agent process runs chord's binary again: it loads chord's whole
  module graph (CHD-573 says no lazy import; the subcommand's start is
  `chord acp`'s), plus the addon. Measured start of the engine was ~500 ms
  to the first tool call natively (T1), Wasm ~90 ms; the process's own
  start was not measured here.
- **Revision: sign-in runs in the window, as in Q1-A** (the lead's
  resolution, matching protocol's and interface's drafts). The window runs
  the sign-in screens, the loopback listener and the first store write.
  The child never signs in and never opens a listener. It reads the store,
  writes rotations back under the lock (the credential contract below),
  and tells the window when it could not. A child that finds no
  credentials ends `initialize` or the turn with ACP's `authRequired`
  (`src/session/sign_in.ts:9`), and the window offers sign-in, then starts
  the session again.
- Two windows, or a window and its children, are then several processes on
  one store entry: the cross-process lock (below) is needed in both
  options.
- `--fake`: the window starts the subcommand with a flag that swaps in the
  fake provider and the fixture store (see Tests); nothing else changes.

### What is the same in both

Tools, sign-in, credentials, the build and the tests below are the same
modules; only where `createFxEngine` is called differs. Q1-B adds one
entry (the subcommand's) and its ACP agent side; Q1-A adds one `Agent`
implementation. In both, sign-in is the window's.

**Runtime's view, not a recommendation for protocol's half:** isolation of
native crashes and unchanged stop bounds favour Q1-B; one process, no
second start and no second module graph favour Q1-A. I would take Q1-B for
the MVP because a fault in a 0.0.x native library then costs a session, not
the window.

## The build

### Embedded assets per target

| Target | Addon (embedded by the plugin) | Wasm |
| --- | --- | --- |
| bun-darwin-arm64 | `node_modules/@libfx/libfx-darwin-arm64/libfx.node` | `node_modules/libfx/fx-core.wasm` |
| bun-darwin-x64 | `node_modules/@libfx/libfx-darwin-x64/libfx.node` | same |
| bun-linux-x64 | `node_modules/@libfx/libfx-linux-x64-gnu/libfx.node` | same |
| bun-linux-arm64 | `node_modules/@libfx/libfx-linux-arm64-gnu/libfx.node` | same |

`libfx` names the platform packages in `node.js:96-101` and imports them by
literal specifier (`node.js:116-119`). Each package's `index.js` is
`export default new URL("./libfx.node", import.meta.url)` and its
`package.json` carries `os`, `cpu` and, on Linux, `libc: ["glibc"]`.
`scripts/dev/compile.ts:147` already runs `bun install --os=* --cpu=*
--libc=*` before compiling, which installs all four.

How the target's addon gets into the binary (finding 8), options:

- **B1. A compile plugin** in `scripts/dev/compile.ts` beside
  `jsxDevRuntime`: `onResolve` maps `chord:libfx-native` to the target's
  file, `onLoad` returns its bytes with `loader: 'file'`, so the import
  yields a `/$bunfs/root/…` path. One addon per binary. Tried (T, plugin2):
  native and Wasm both load in the compiled darwin-arm64 binary.
- **B2. A static import of all four** in one module: no plugin, +34 MB per
  binary (three dead addons).
- **B3. A generated module per target** written before each compile: the
  plugin's job done with a file on disk; more moving parts.

Recommendation: B1. It is a build mechanism in chord's own script, the
same kind as the existing plugin; it changes nothing in libfx.

From source (`bun dev chord`), the plugin does not run: the module in
`src/platform/` that hands libfx its assets passes none, and libfx finds
its own addon in `node_modules` (`node.js:194-215`). The compiled define
`CHORD_RESOURCE_COMPILED` (`scripts/dev/compile.ts:118`) already tells the
two apart; the virtual import sits behind it as a dynamic import, so source
never resolves it.

Always pass both: `nativeAddon` (the path) and `wasm` (the bytes, read from
the embedded path), with `backend: 'auto'`. Then glibc below 2.34 (the
gate), an unwritable or `noexec` temporary directory (finding above) and a
broken addon all land on Wasm. Which backend loaded is worth one line in
the agent's diagnostics: `getBackendInfo()` says it without starting
anything (`node.js:298-343`).

`createFxAgent` needs an explicit durability (finding 9); its directory is
protocol's Q6, under chord's state directory.

### The build check (the owner's condition)

"A libfx layout change must fail the build, not the binary." What can move:
the addon's name or directory, the platform packages' names, `fx-core.wasm`,
and libfx's own entry or API version. The check, in order of where it
fails:

1. **The plugin's resolve fails the build.** A missing file in an import
   fails `Bun.build` with `Could not resolve: "<path>"` for every target
   (tried: `libfx-renamed.node`, darwin-arm64 and linux-x64). The plugin
   checks the file exists before it answers, and names the package and
   version in its error.
2. **A pure check before compiling**, `scripts/dev/libfx_assets.ts`, run by
   `compile` and by a `lint/` or `tests/` test so CI's `static` job sees it
   without compiling:
   - every target's platform package is in `libfx`'s
     `optionalDependencies`, at libfx's own version;
   - its `index.js` still names `./libfx.node` (the literal above);
   - `node_modules/libfx/fx-core.wasm` exists and begins with the Wasm
     magic `\0asm`;
   - `libfx`'s `package.json` version is the one chord pins, and
     `libfxApiVersion` from `libfx/node` is 3 (`node.js:26`).
3. **`bun dev selftest <binary>`** (the release path already runs it on the
   fake agent) adds: the binary's built-in agent reports `native` on its
   own platform and finishes one turn on the fake provider, and with native
   disabled finishes one on Wasm. That catches what 1 and 2 cannot: an
   addon that is there but does not load.

1 and 2 fail before any binary exists; 3 fails before release. Pin libfx
exactly (`0.0.16`, pre-1.0 per AGENTS.md), so the layout only moves when
someone moves the pin and the check runs on that change.

## The tools (Q2, with interface for screens)

libfx and fx ship no tools a host can turn on (finding 1). The fx core does
have file, shell and permission machinery in Zig (`src/core/tooling/`,
`src/core/permissions/` at `v0.0.16`), but it is not exposed through the
library, and the README says so: "the native backend doesn't turn on fx's
built-in shell or file tools" (`README.md:580`). So chord writes host
tools, on libraries:

| Tool | Library | What chord writes | `idempotent` | `writes` |
| --- | --- | --- | --- | --- |
| `read` (file, range) | `node:fs`; `file-type` (in chord) to refuse binaries | limits, line numbers | true | false |
| `list` / `glob` | `globby` (in chord, `src/files.ts:12-21`, honours `.gitignore`) | limits | true | false |
| `search` (grep) | `globby` for files + JS `RegExp` per line | limits, context lines | true | false |
| `edit` (replace a unique string) | `diff` (in chord, `^9`) for the ACP diff; `node:fs` write | uniqueness check, write | false | true |
| `write` (whole file) | `node:fs` | — | false | true |
| `shell` | chord's `src/shell.ts` `runShell` (own process group, stop on abort, `KILL_AFTER_MS` 2 s, `GONE_AFTER_KILL_MS` 5 s) | output cap, timeout | false | true |

Tried for search: ripgrep has no maintained package that survives `bun
build --compile` without shipping a binary per target (`@vscode/ripgrep`
downloads one at install); not tried in a binary this run. JS search over
`globby`'s list is slower on huge trees but has no binary. That is a trial
the ship team runs before writing `search`; the finding goes to
`docs/decisions.md`.

No library was found for the edit tool's semantics (a unique-string
replacement, the shape Claude's and Codex's models are trained on); it is a
few lines over `node:fs` and `diff`. If the owner wants a patch-format edit
instead, `diff`'s `applyPatch` carries it.

**Ordering.** On native, idempotent calls of one response run up to 16 at
once, and a non-idempotent or `writes: true` call runs alone
(`README.md:273`; T1: two reads overlapped, two writes ran one after the
other). On Wasm every call runs one after another (T1). The table's flags
give reads in parallel, edits and shells alone.

**After a crash.** `idempotent: false` calls are never rerun; the model is
told the call may have partly run (`README.md:213`). That matches edits and
shells. MCP tools come `idempotent: false` (`README.md:299`).

**Where the permission prompt sits.** libfx grants nothing
(`README.md:271`): a host tool's `execute` is the only place. The prompt
runs inside `execute`, before any effect, and its wait is under the call's
`signal`: Esc cancels the turn, the signal aborts, the prompt is withdrawn
(chord's `answer`, `src/acp/connection.ts:268-302`, does the same for ACP
agents). `engine.js:1746-1757` also forwards a core
`session/request_permission` to an `options.onPermission`, but that option
is not in the types and the core sends none for host tools: not used.

**Which calls ask** (Q2, the owner's): options. Revision: each with the
scope of its "allow for this session" grant. A grant lives in the session's
memory, is never written to settings, and ends with the session.

- **P1.** `edit`, `write` and `shell` ask; `read`, `list` and `search`
  never ask. Grants: for `edit`/`write`, per path (the real path, below);
  for `shell`, the exact command string only.
- **P2.** P1, and `read`, `list` and `search` ask when their real path is
  outside the session's directory. Grants: an outside directory's real
  path covers what lies under it, for reads only; edits and writes keep
  P1's grants.
- **P3.** Everything asks. Grants per tool ("all reads this session"),
  except `shell`, which keeps exact-command grants, and `edit`/`write`,
  which keep per-path grants.

Recommendation: P2. Reads outside the project are how secrets leave, and
they are rare in normal work.

**Why no first-word or prefix grant for `shell`.** "Allow `git`" also
allows `git push --force` and `git -c core.sshCommand=… fetch`; "allow
`npm`" allows `npm publish`. Wrappers run anything: `env`, `xargs`,
`find -exec`, `sh -c`, `bash -c`, `timeout`, `nice`. And one command
string can hold several commands (`;`, `&&`, `|`, `$(…)`, backticks,
redirects). If the owner wants a prefix grant anyway, the minimum is:
parse with `shell-quote` (already a chord dependency, `src/acp/process.ts:2`);
refuse the grant for a command with any operator, substitution or
redirect; match whole tokens, never characters; and keep a list of
wrappers that are never granted. Even that leaves subcommands such as
`git push`, which is why P1 to P3 grant exact strings only.

**Paths are resolved at the effect, not at the ask.** Each file tool takes
`realpath` of its target when it runs, after the prompt, and decides
inside/outside and grant matches on that real path. A symlink inside the
project that points outside is outside. A path that does not exist yet
(`write`) is judged by its parent's real path. The prompt shows the path
as the model gave it and, when they differ, the resolved one. To narrow
the gap between the check and the open: open the real path, `fstat` the
handle, and compare `dev` and `ino` with a `stat` of the real path. On a
mismatch, refuse with a tool error. What remains is a swap of a parent
directory between `realpath` and `open`; that is acknowledged, not closed.

**An edit whose file changed while the prompt waited.** `edit` and `write`
record the target's SHA-256 (or that it is absent) when they build the
diff shown in the prompt. They re-read the file at the effect. If it
differs, they refuse with a tool error ("the file changed since this edit
was proposed; read it again") and write nothing. The model re-reads and
proposes again, and the next prompt shows the new diff. Re-asking with a
recomputed diff was considered: it shows the person a diff the model never
saw, so refusing is recommended.

| Case | Outcome |
| --- | --- |
| `read` of `link → /etc/…` inside the project, P2 | asks as outside; a grant is recorded for the real directory |
| Symlink retargeted between the prompt and the effect | judged on the new real path: outside means ask again or refuse; a `dev`/`ino` mismatch refuses |
| `edit` approved, file changed meanwhile | refused, nothing written, tool error to the model |
| `write` approved for a new file that appeared meanwhile | refused the same way |
| `shell` granted `npm test`, model asks `npm test && curl …` | asks: a different string |

**A stuck tool** (finding 6): every tool takes the `signal`. `shell` passes
it to `runShell(...).stop()`; file tools check it between steps. A tool
cannot outlive the turn by more than `shell`'s 7 s.

**Terminal output.** ACP's `terminal` content and chord's
`terminal_output_delta` (`src/acp/connection.ts:233`) are what chord's
reducer reads for other agents; the shell tool streams `onOutput` chunks as
those updates (protocol's mapping). Output is capped by chord for the
model and kept whole for the screen up to the transcript's own limits. fx's
Wasm host bridge caps a host result at 64 KiB
(`src/core/hosts/js_host_tools.zig:7`); the native path's cap was not read,
and the engine refuses a response frame above 8 MiB (`engine.js:1782-1784`).

**MCP servers from settings and chord's own MCP tools** go through
`libfx/mcp`'s `createMcpAdapter` with an `@modelcontextprotocol/sdk` client
(already a chord dependency) that chord owns and closes (`README.md:297`);
protocol owns which servers, `src/session/servers.ts` already chooses them.

## Sign-in

All four flows (ChatGPT and Grok, browser and device code) are libfx's
functions; chord adds the listener, the timers and the cancellation.
Revision: all of it runs in the window, in both Q1 options. The first
write of new credentials is the window's, under the same lock as refresh
and logout (below).

### The loopback listener (browser)

- Its life: opened after `startSignIn()` returns and before the address is
  shown or opened; closed when a callback request finishes the sign-in,
  when the person presses Esc, at a deadline, or when chord leaves.
  `server.stop(true)` closes it and its connections at once; T5: the port
  could be bound again immediately after.
- ChatGPT: port 1455 (`chatgpt-sign-in.js:12`), path `/auth/callback`.
  Grok: the port and path of `signIn.redirectUri`
  (`grok-sign-in.js:36-38, 50`).
- **Port taken, in this order** (revision: the order and the partial
  close):
  1. Bind `127.0.0.1:<port>`. On `EADDRINUSE` (T5: Bun throws `code:
     'EADDRINUSE'`): taken; nothing is open; stop.
  2. Bind `[::1]:<port>`. On `EADDRINUSE`: `stop(true)` the `127.0.0.1`
     listener first, then report taken (finding 10: another listener on
     either family can receive the browser). On `EADDRNOTAVAIL` or
     `EAFNOSUPPORT` (no IPv6 loopback): keep the IPv4 listener alone. On any
     other error: stop the IPv4 listener, then fail with the error.
  3. Only then show or open the address.

  Never bind `hostname: 'localhost'`. Taken → the owner's words: the port
  is taken, device code offered. Closing stops both listeners
  synchronously, in either order: neither stop waits on the other.
- Grok's random port (1024 to 65535) can also be taken. libfx picks it
  (`grok-sign-in.js:37`). chord closes whatever step 2 left open and calls
  `startSignIn()` again, up to three times, then fails with the last port
  named. This calls libfx's public API again; chord never chooses the port.
- What it answers: `GET` on the callback path only; anything else 404 and
  keeps listening (a browser asks for `/favicon.ico`). The callback's whole
  URL goes to `finishSignIn(signIn, url, { signal })`. A `state` mismatch
  (`*_SIGN_IN_STATE_MISMATCH`, a tab from an older sign-in) answers the
  page with the error and keeps listening; `*_SIGN_IN_DENIED` and
  `*_SIGN_IN_EXPIRED` end the wait with the error. The page says to go back
  to chord either way.
- Deadline: libfx sets none for the browser flow. Proposed 10 minutes, then
  closed and said so (open question 3).
- The page is answered only after `finishSignIn` settles, so a person who
  closes the tab early does not leave a half sign-in: the exchange still
  runs and the credentials are saved.

### Device code

- `startDeviceSignIn({ signal })`, then `completeDeviceSignIn(device, {
  signal })`: libfx's loop polls at the provider's interval, slows down for
  Grok's `slow_down` (`grok-sign-in.js:132-140`) and waits with an abortable
  timer (`oauth.js:57-64`). chord shows `userCode` and `verificationUrl`
  and a countdown to `expiresAt`.
- Expiry: ChatGPT's is 15 minutes counted by libfx
  (`chatgpt-sign-in.js:15, 105-110`), Grok's the server's `expires_in`
  (`grok-sign-in.js:85-96`); both throw `*_DEVICE_CODE_EXPIRED`. ChatGPT
  answers 403/404 while pending (`chatgpt-sign-in.js:117-120`), including,
  as libfx's error text says, when device code sign-in is off for the
  account: the failure only shows at expiry, with libfx's words about the
  security setting. Interface may want to say it up front.
- `*_DEVICE_CODE_UNAVAILABLE` on start (HTTP error or an answer libfx does
  not understand) ends at once with the error.
- Esc aborts the signal: `wait` rejects with an `AbortError`, the poll in
  flight is aborted; chord returns to the choice. Nothing to clean up.

### One sign-in at a time

One sign-in per provider per process; a second request joins the one
running. Across windows (sign-in is the window's in both Q1 options) nothing
prevents two ChatGPT browser sign-ins: the second sees 1455 taken and is
offered device code, which is the owner's rule.

### Where the logic lives

```text
src/riff/sign_in.ts          pure: the state machine (choosing, waiting,
                              port taken, device code, expired, failed,
                              cancelled, done) from events to state
src/riff/sign_in_run.ts      runs a flow: libfx calls, timers, signal,
                              the listener through a port
src/platform/loopback.ts      Bun.serve on 127.0.0.1 and ::1, taken or bound
```

(`src/riff/` is a placeholder name for the built-in agent's folder; its
name follows Q5.) `sign_in_run.ts` takes the libfx functions and `fetch`
as parameters, so tests give it fakes.

## Credentials and Bun.secrets (Q4)

### The store

`src/platform/secrets.ts` is the only caller of `Bun.secrets`:

- One service, one name per provider (`codex`, `grok`); the value is the
  JSON libfx returns (`accessToken`, `refreshToken`, `accountId`,
  `expiresAt`). One account per provider; switching account is sign out
  then sign in.
- **One queue per process** (revision: scoped to finding 7). Every call goes
  through one promise chain, one at a time. Calls one at a time never
  stuck in any trial. They are cheap: a `set` took 27 to 347 ms, a `get` 10
  to 45 ms (T4).
- **Every call bounded,** 20 s, as in the owner's other project. A bound is
  a timeout on the caller's wait, not a cancel: Bun.secrets has no abort,
  so the operation goes on. Revision: the rule for a late completion.
  - The queue stays strictly serial past a timeout. A timed-out operation
    still holds the head until it settles, and nothing behind it starts
    first. So order holds whatever the timeouts: a late write lands
    before the logout queued after it, and that logout's delete still wins.
  - A **read** whose caller timed out is dropped from the queue if it has
    not started; its caller has already been told "the credential store
    did not answer".
  - A **write or delete** whose caller timed out stays queued and runs in
    order. When it lands, late, its outcome raises a notice (saved, or
    failed). A write still goes through the compare-and-set below when it
    runs, so a late write after a logout is refused, not resurrected.
  - The earlier draft's "unusable for the process after any timeout" is
    dropped. A process whose head never settles simply times out each
    caller, and says so each time.
- A locked keychain or a headless access prompt can block (the owner's
  report on the board); the bound covers the caller. Unverified: a locked
  keychain, a keychain over ssh, Linux's Secret Service with or without a
  running service.
- No secret service (Linux without one): the first call fails; Q4 decides
  what follows.

### The credential contract under the lock (revision)

The earlier draft let `credentials()` return the process's memory copy.
That breaks `refreshLock`: libfx calls `credentials()` inside the lock to
see another process's rotation (`subscription.js:183-190`). Process A
rotates R to R2 and saves; process B takes the lock, its `credentials()`
returns its cached R, and B spends R a second time. T8 `naive` reproduced
it: with two independent caches, B's turns failed (`HostStreamFailed`)
after the provider refused the spent `r0`, eight times over two rounds.

Each process (a window, or a Q1-B child) holds one **credential cell** per
provider, `src/riff/credentials.ts` over the platform store:

- `cache`: the value this process last read from the store or saved to it.
- `base`: the value the store held when this process last read it under
  the lock, or last wrote it. A rotation's write is valid only against it.
- `unsaved`: true when this process rotated but its write failed.
- `account`: the `accountId` the session was opened with.
- `lockHeld`: true while this process holds the provider's lock.

**`credentials({ provider })`:**

1. If the cell is signed out: throw chord's `CHORD_SIGNED_OUT`, and the
   turn fails with it.
2. Under the lock (`lockHeld`), or with no cache: read the store
   (authoritatively, through the queue).
   - Absent: sign the cell out; throw.
   - Its `accountId` differs from `account`: sign the cell out as
     "account changed"; throw. The session is never moved to another
     account silently.
   - The cell is `unsaved` and the store still holds `base`: keep the
     cache. This process's rotation is the only live chain (the store's
     refresh token is spent), and it retries the write now, under the
     lock it holds.
   - Otherwise: `cache = base = store`'s value.
3. Outside the lock, with a cache: return the cache. A stale access token
   meets a 401; libfx refreshes; the refresh takes the lock, and step 2
   reads the truth (`subscription.js:238-252`).

**`onCredentials(next)`** is a compare-and-set, under the lock. If this
process already holds the lock (it is inside its own `refreshLock`), it
writes directly: `proper-lockfile` is not reentrant, so the cell's
`lockHeld` says when not to take it again. Otherwise it takes the lock.

1. `cache = next` at once. libfx has it already; this process keeps using
   it.
2. Read the store.
   - It holds `next`'s refresh token: done. Another session of this agent
     already saved it.
   - It holds `base`'s refresh token: write `next`; `base = next`;
     `unsaved = false`.
   - Absent (a logout) or another chain (a new sign-in): refuse the write;
     sign the cell out. libfx's request in flight finishes with `next`;
     the next `credentials()` throws.
3. On a write failure: `unsaved = true`; a notice (path below); **no
   throw**, since libfx awaits it inside the request
   (`subscription.js:173-178`) and the rotation already happened at the
   provider.

**`refreshLock({ provider }, refresh)`:** take the in-process mutex, then
the file lock (`proper-lockfile` in chord's state directory, stale time
above the 20 s store bound plus the refresh's own request); set
`lockHeld`; run `refresh`; clear `lockHeld`; release both. The in-process
mutex makes `lockHeld` mean "this process", not "some async chain in it".

**Sign-in** (the window's) writes under the lock unconditionally: it
starts a new chain, and every other cell's next lock read sees the new
value. If its account differs from theirs, those cells sign out with
"account changed".

**Proof, T8** (two independent cells, two engines, one backing store, one
lock directory; the fake provider rotates and refuses a spent token):

| Mode | Result |
| --- | --- |
| `naive` (cache under the lock) | B: `HostStreamFailed` both rounds; the provider refused spent `r0` eight times |
| `cas` (the contract above), 1 h tokens | A and B: `end_turn`; one rotation (`r0 → r1`, A saved); B read `r1` under the lock and spent nothing |
| `cas`, 1 s tokens (always due) | A and B: `end_turn` in both rounds. The provider still refused three stale tokens, and the turns recovered on libfx's retry. Cause: when the value read under the lock is itself within libfx's 5 min refresh skew (`subscription.js:13, 118-122`), libfx refreshes its own `current` rather than the value it just read (`subscription.js:185-190`). Real tokens last far longer than 5 min, so this needs two processes refreshing within one skew window of a fresh rotation. The cost is a refused refresh and a retry, not a sign-out. libfx's behaviour, not changed here |
| `logout` (below) | logout waited for A's refresh under the lock; the store ended absent; a late write (stale base) was refused; the store stayed absent |

### Logout against refresh (revision)

Sign-in, refresh and logout all take the provider's lock. Ownership: any
process may delete (logout); a process writes only by compare-and-set
against its `base` (above). So no write after a delete can bring a sign-in
back: T8 `logout` refused B's late write, and the store stayed absent.

Logout itself: take the lock, delete the entry, release, sign this
process's cell out, then stop this window's sessions on that provider.
Other processes do not hear of it until they look. When they look is the
owner's policy:

- **L1. Lazily.** Each process finds out at its next lock read or write,
  that is, its next refresh. Until then it keeps its cached access token
  and its turns go on. T8 `logout`: A's next turn after the logout ended
  `end_turn` with no check. This can last as long as the access token
  does.
- **L2. At each turn's start.** Before each prompt, the engine wrapper
  reads the store (through the queue, outside the lock, read only). If the
  store is absent or holds another account, the cell signs out and the
  prompt fails with `CHORD_SIGNED_OUT`: in Q1-A as a sign-in state on
  screen, in Q1-B as `authRequired`. Cost: one store read per prompt
  (10 to 45 ms on macOS, T4). T8: the turn-start check reported "signed
  out" right after the logout. A turn already running finishes.
- **L3. At once, everywhere.** The window that logs out tells the other
  processes. Its own children are reachable over ACP (a session cancel,
  then `authRequired`); other windows share nothing to signal through but
  the store and the lock directory, so it would need a watch on a marker
  file there. It does not revoke the tokens at the provider: libfx has no
  revoke call.

Recommendation: L2, plus an immediate cancel of the turns in the window
that logged out and in its own children (part of L3, with no new
channel). A turn running in another window finishes; its next prompt is
refused.

### The notice path from a child (Q1-B)

A child's `onCredentials` write failure, or a cell signing out, must reach
the window. Proposed: a chord extension notification from the child,
`_chord/credentials` with `{ provider, state: 'unsaved' | 'saved' |
'signed_out' | 'account_changed' }`, handled by the window's connection
(`src/acp/connection.ts`'s `acp.client` app) and shown as a notice. A
signed-out cell also fails its next prompt with `authRequired`, so even a
missed notification ends where sign-in is offered. The method's name and
shape are protocol's (CHD-575's extension rules). In Q1-A the cell calls
the window's notice function directly.

### Q4: beyond Bun.secrets, and with no credential store

Options, the owner's:

- **C1. Refuse.** No store, no built-in agent on ChatGPT or Grok; the
  words name the missing secret service. Safest, and what the owner's other
  project does unless given a file.
- **C2. An explicit 0600 file,** only when the person names it (a setting
  or flag), never chosen silently. chord writes it with `mode: 0o600`,
  atomically (temporary file and rename), and refuses to read one that is
  group- or world-readable. The same cell contract and lock cover it.
- **C3. Environment variables only.** A refresh token in the environment
  cannot be written back after rotation, so the next process fails once
  OpenAI rotates it. Workable only for Grok if xAI does not rotate, which
  was not checked.
- **C4. Memory for the process's life.** Sign in every start; nothing on
  disk.

The complete path for each Q1 × Q4 combination (revision):

| | Q1-A (in-process) | Q1-B (child process) |
| --- | --- | --- |
| C1 Bun.secrets | Window signs in, writes the keychain under the lock; its cell reads and writes it. Notices direct | Window signs in, writes the keychain. Each child's cell reads it (bounded, queued) and writes rotations by CAS under the lock. Notices by `_chord/credentials` |
| C2 0600 file | As C1, over the file | As C1, over the file; children read the path the window gives them on start (an argument, never the contents) |
| C3 environment | The window reads the variables; rotations live in memory only; the next start may fail after a rotation | The child inherits the variables; same rotation loss, per child |
| C4 memory | The window's memory is the store; the cell contract runs with no lock file needed (one process) | **Unsupported as is**: a child shares no memory with the window. To support it, the window would hand the credentials to the child over its ACP pipe (a chord request after `initialize`, never in argv or the environment, which other processes of the same user can read with `ps`), and the child would send every rotation back in `_chord/credentials` for the window to keep. The window becomes the store for its children; two windows cannot share. Cost: a credential channel in chord's ACP extensions, and tokens in a pipe |

Recommendation: C1 by default with C4 offered on the same screen ("sign in
for this run only") in Q1-A; in Q1-B, C4 only if the owner accepts the
pipe channel above, otherwise C1 alone (or C1 with C2). C3 is not
recommended because of rotation.

`--fake`/`--qa` never touch Bun.secrets: they get a fixture store
(AGENTS.md; `src/platform/AGENTS.md`).

## Failure scenarios

| Scenario | Expected outcome |
| --- | --- |
| Model never answers | Turn waits; Esc → `cancelled` in ≤ 11 ms (T2) |
| Provider answers 5xx persistently | libfx keeps retrying, every 30 s after 31 s, and was still retrying at 300 s (T7, finding 5). Status shows it (protocol's path, from `onEvent`'s `transport.*` events). Esc cancels. A host bound is the owner's (R1 to R3 below) |
| 401 | One refresh through `fetch`, `onCredentials`, retry (T3) |
| Refresh rejected (revoked) | `LIBFX_*_REFRESH_FAILED` ends the turn. Under the lock, chord deletes the entry only if it still holds the rejected refresh token (compare-and-delete), signs the cell out, and leads to sign-in (`authRequired` in Q1-B) |
| Grok account changed on refresh | `LIBFX_GROK_ACCOUNT_CHANGED` (`grok.js:90-92`): same as revoked |
| Tool ignores abort | Abandoned by libfx; chord's tools all honour `signal` |
| Shell started a daemon | `runShell` stops its group on abort; on quit the spawn registry SIGKILLs it |
| Native core exits | Pending requests fail; turn `error`; a new engine on the next prompt |
| Native core crashes | Q1-A: chord dies. Q1-B: the agent process dies, the window reports it |
| Native cannot load (glibc < 2.34, temp dir unwritable or `noexec`) | Wasm, serial tools; diagnostics name the backend |
| Neither loads | Start fails with `getBackendInfo()`'s reasons |
| Bun.secrets blocks | The caller times out at 20 s and is told; the operation keeps the queue's head until it settles; queued reads are dropped, queued writes and deletes run in order later and report |
| Store write fails after rotation | `unsaved`; the cache holds the only live chain; the write is retried at the next lock; notice (direct, or `_chord/credentials`); other processes that spend the old token fail and sign out |
| Two processes refresh at once | `refreshLock` serialises; the second reads the first's save under the lock (T8 `cas`) |
| Logout while another process refreshes | The logout waits for the lock; the refresh's CAS write lands first, then the delete; the store ends absent (T8 `logout`) |
| A late write after logout | Refused by CAS (store absent ≠ base); the cell signs out (T8 `logout`) |
| Sign-in to another account in another window | Other cells see another account at their next lock read (or turn start under L2) and sign out as "account changed" |
| `edit` file changed during the prompt | Refused, nothing written (permission contract) |
| 1455 taken (either family) | "port taken", device code offered |
| Grok's random port taken | `startSignIn()` again, three tries |
| Browser never comes back | 10 min deadline (proposed), listener closed |
| Device code expires | libfx's words; back to the choice |
| Esc during any sign-in wait | Signal aborts; listener closed; back to the choice |
| Quit during sign-in | Listener closed and signal aborted in the leave steps |
| Quit during a turn | `cancel()`, `close()` (≤ 6 ms, T2), MCP clients closed, shells stopped; within `LEAVE_MS` |
| Prompt above 8 MiB | `FX_INPUT_TOO_LARGE` before storing (`README.md:60`) |

## Testability

Nothing reaches a real model, provider or sign-in endpoint, by construction:
every libfx network call goes through a `fetch` chord passes (finding 3),
and every Bun.secrets call through a store chord passes.

### Seams

- **The model, custom provider.** `provider: { name, baseUrl:
  'http://localhost:<port>/v1', models }` (`README.md:396`) against a fake
  Chat Completions server, as the gate ran. Plays text, tool calls,
  parallel calls, hangs and slow streams (the trials' `fake.ts`).
- **The model, plan providers.** `provider: 'codex' | 'grok'` with a fake
  `fetch` that answers the version lookups (finding 4), the models list and
  a Responses API stream (T3b, T3c). This tests the real plan path,
  credentials and refresh included, with no network. The Responses fixture
  must cover tool calls and reasoning items too; T3b covered text only.
- **Sign-in.** The libfx functions with a fake `fetch` that plays
  `auth.openai.com` and `auth.x.ai` (token, device code, userinfo). The
  listener is driven by a real local `fetch` to its port; tests use a
  random port by giving `sign_in_run.ts` a sign-in whose redirect is on
  port 0's choice, never 1455 (a developer's Codex CLI may hold it, and
  tests run in parallel). One test asserts libfx's ChatGPT `url` still
  carries `redirect_uri=http://localhost:1455/auth/callback`, so a libfx
  change fails a test.
- **Time.** Device polling uses libfx's own timers (`setTimeout` in
  `oauth.js:60`); `bun:test`'s fake timers drive them; the listener's
  deadline is chord's timer.
- **Credentials.** A memory backing store implementing the platform
  store's interface, shared by two cell instances to play two processes,
  and a real `proper-lockfile` lock directory under the test's temporary
  directory; a fake backend that never settles for the queue's bounds.
- **Bun.secrets itself** is not reached by tests. A manual check on each
  platform, with a throwaway service name, belongs in the ship team's
  handover.

### Test plan, mirroring `src/`

| Module | Test | How |
| --- | --- | --- |
| `src/riff/sign_in.ts` (pure) | `tests/riff/sign_in_test.ts` | every transition, the interface's states |
| `src/riff/sign_in_run.ts` | `tests/riff/sign_in_run_test.ts` | fake `fetch`, real loopback on a random port, fake timers: success, state mismatch then success, denied, expired, Esc, deadline, port taken |
| `src/platform/loopback.ts` | `tests/platform/loopback_test.ts` | a holder on `127.0.0.1` and one on `::1`: both reported taken; `stop` frees the port |
| `src/platform/secrets.ts` | `tests/platform/secrets_test.ts` | over an injected backend, never `Bun.secrets`: calls strictly serial; a caller times out while its operation holds the head; a queued read past its timeout is dropped; a queued write and a later delete run in order after a late completion and the delete wins |
| `src/riff/credentials.ts` | `tests/riff/credentials_test.ts` | two independent cells (two store instances with their own caches, one backing store, one lock directory) and real libfx engines on a fake `fetch` whose token endpoint rotates and refuses a spent token, as T8: concurrent refresh spends once; the cache is not trusted under the lock; a write failure leaves `unsaved` and the retry at the next lock wins; logout racing a refresh ends absent; a late write after logout is refused; another account signs the cell out; L2's turn-start check |
| `src/riff/tools/*.ts` | `tests/riff/tools/*_test.ts` | in a temp directory; abort mid-call; limits; permission prompt withdrawn on abort; a symlink inside the project to a file outside asks as outside (P2); a symlink retargeted between the prompt and the effect is judged on the new real path; an edit whose file changed while the prompt waited is refused and writes nothing; a `write` whose new file appeared meanwhile is refused; a granted exact command does not grant a longer one |
| `src/riff/engine.ts` (libfx wiring) | `tests/riff/engine_test.ts` | fake Chat Completions server: a turn, parallel reads, serial writes, cancel with a hung model and with a stuck tool, close bounds, 5xx retry visible, backend reported |
| plan path | `tests/riff/plans_test.ts` | Codex and Grok with a fake `fetch`: a turn, 401 refresh, refresh rejected → sign-in |
| `scripts/dev/libfx_assets.ts` | `tests/scripts/dev/libfx_assets_test.ts` (or `lint/`) | passes on the installed tree; fails on a copied tree with the addon renamed, a platform package removed, the wasm missing, a version off |
| the window | `tests/ui/…` through `tests/ui/harness.tsx` | sign-in screens and keys (interface's list) over the pure state |

The engine tests load the real native addon from `node_modules` (and Wasm
with `backend: 'wasm'`), so they run libfx itself, not a mock of it; each
engine is closed in `afterEach`. They start ~9 threads per native engine
(T2) and take ~0.5 s for the first native turn (T1): fine for a handful,
heavy for many; `tests/timings.json` will place them.

### Fake agent and `--fake`/`--qa`

`tests/fixtures/fake_agent/` plays other agents over ACP; it does not cover
the built-in agent, whose logic is chord's own. In Q1-B the built-in agent
*is* an ACP agent, so the window's tests can start it under `--fake` as
they start the fake agent today. In Q1-A they open it in-process. Either
way, `--fake` and `--qa` give the built-in agent:

- the fake provider: a fixture Chat Completions server in
  `tests/fixtures/builtin_agent/` started in-process on port 0, with
  scenarios named like the fake agent's (`text`, `tools`, `edit`, `shell`,
  `hang`, `retry`);
- the memory credential store, already "signed in" to a fixture account,
  and a fixture sign-in (fake `fetch`, loopback on a random port) for the
  sign-in screens' captures;
- never Bun.secrets, never a real provider (`src/platform/AGENTS.md`).

No new fake ACP scenario is needed for Q1-A. For Q1-B, none either: the
subcommand under `--fake` plays the fixture provider.

### Compiled

`bun dev selftest <binary>` gains: the built-in agent, on the fixture
provider, answers one prompt with one tool call on native; then with native
disabled (`nativeAddon: false` through a test-only flag) on Wasm. CI's
`compile` job runs it for its target.

## Q9: what the sources say, quoted

No conclusion is drawn here.

**libfx's README:**

- "The sign-in uses the same OpenAI client as the Codex CLI, and the user's
  ChatGPT plan and OpenAI's terms apply to the turns." (`README.md:348`)
- "The sign-in uses the same xAI client as the fx CLI, and the user's Grok
  plan and xAI's terms apply to the turns." (`README.md:366`)

**libfx's code:**

- `chatgptClientId = "app_EMoamEEZ73f0CkXaXp7hrann"` (`chatgpt.js:8`); the
  authorize URL sets `codex_cli_simplified_flow: "true"` and `originator:
  "fx"` (`chatgpt-sign-in.js:31-33`).
- `grokClientId = "b1a00492-073a-47ea-816f-4c329264a828"` (`grok.js:7`);
  the authorize URL sets `referrer: "fx"` (`grok-sign-in.js:48`); scope
  `grok-cli:access api:access` (`grok-sign-in.js:11`).
- The core asks `registry.npmjs.org/@openai/codex/latest` and
  `x.ai/cli/stable` for a client version before its first request (T3b,
  T3c), and sends it as `client_version` to Codex's models endpoint.

**fx's README** was not re-read for this; the board's 2026-11-08 findings
quote it (fx itself listens on 1455/1457 and a random Grok port).

**The providers' published terms.** `openai.com/policies/terms-of-use/` and
`x.ai/legal/terms-of-service` answered HTTP 403 to a fetch; a retry with a
browser's user agent was refused by this session's permission rules and not
pursued. What a web search returned, from mirrors and trackers, unverified
against the live pages, so a person reads the live pages before any of this
is used:

- OpenAI's Terms of Use, as the search summarised them: account
  credentials may not be shared or made available to anyone else, and the
  account holder is responsible for all activity under it; a prohibition on
  "automatically or programmatically extract[ing] data or Output" (a
  December 2024 version, from a mirror).
- xAI's consumer Terms of Service, as the search summarised versions from
  2024 and 2025: "using bots to access" the Service is listed among
  prohibited activities; logging in through a third-party service is
  described as permitted. The enterprise terms prohibit sharing account
  access credentials with third parties.

Neither set, as found, names third-party clients signing in with another
product's OAuth client; whether that is covered is the question Q9 asks and
this draft does not answer.

## Open questions

1. Q1 (the owner's, with protocol): in-process or a subcommand. Runtime
   leans to the subcommand for crash isolation.
2. A host bound on a turn that only retries (finding 5), the owner's. It
   is chord's policy through `cancel()`; it never replaces libfx's retry
   loop or answers in its place.
   - **R1. None.** Esc only, in the window. `-p` and `chord acp` wait for
     the client's cancel or their own exit; a script can hang for as long
     as the provider is down.
   - **R2. Cancel after N consecutive failed attempts with no output**,
     counted from `onEvent`'s `transport.response` with a 429 or 5xx
     status and `transport.error` (a thrown fetch; a 500 is a response,
     not an error), and reset by any `transport.activity`
     (`engine.js:1495-1517, 1622`).
     The turn ends `cancelled` with chord's reason ("the provider failed N
     times in a row").
   - **R3. Cancel after T seconds with no output**, the same reset.
   - Where: the window could keep R1 (a person is watching and can press
     Esc) while `-p` and `chord acp` take R2 or R3 (no one may be
     watching).

   Recommendation: R1 in the window; R3 with T = 120 s for `-p` and
   `chord acp`, a setting with that default. In T7's schedule, 120 s
   covers six attempts.
3. The browser sign-in's deadline: 10 minutes proposed; libfx sets none.
4. Q4 (the owner's): C1, with C4 in Q1-A; in Q1-B, C4 only with the
   credential pipe described in the Q1 × Q4 table, else unsupported.
5. Q2 permissions (the owner's): P2 with exact-command shell grants
   recommended; the grant scopes are part of the question.
5a. Logout reaching other processes (the owner's): L2, plus cancelling the
   logging-out window's own turns and its children's, recommended.
5b. The notice from a child: `_chord/credentials` proposed; its name and
   shape are protocol's.
6. `search` on JS over `globby` or a ripgrep binary per target: a ship-team
   trial, recorded in `docs/decisions.md`.
7. Whether chord puts the project's `AGENTS.md` (and which others) into
   `instructions` (finding 2): protocol's to propose, the owner's to
   decide.
8. The npm registry and `x.ai/cli/stable` lookups (finding 4) go out on
   every engine's first turn: does the owner accept them, or ask upstream?
   chord cannot drop them without a `fetch` that answers in their place,
   which is a workaround of the kind AGENTS.md sends to the owner.

## What I read in libfx 0.0.16

`README.md:30, 56-61, 187-217, 260-275, 297-299, 330-346, 348, 352-376,
396, 402, 413, 512-523, 580`; `node.js:26, 68-125, 194-224, 298-343,
345-601, 612-655, 662-694`; `engine.js:146-226, 1458-1494, 1527-1590,
1605-1612, 1712-1797`; `fx-harness.js:17-58, 109-125, 193-204`;
`chatgpt-sign-in.js` (whole); `grok-sign-in.js` (whole); `oauth.js`
(whole); `chatgpt.js` (whole); `grok.js` (whole); `subscription.js:130-253`;
`bundled-asset.js` (whole); `types/libfx.d.cts:60-215, 420-480, 960-1010`;
the four platform packages' `package.json` and `index.js`. fx at `v0.0.16`:
`src/acp/server.zig:55-66, 815-840, 2600-2710, 2900-2930, 2960-2985`;
`src/core/hosts/js_host_tools.zig:1-60`.

## Libraries tried

- libfx 0.0.16: native and Wasm, source and compiled (darwin-arm64,
  darwin-x64 not re-run; linux-x64 compiled, not run).
- Bun's compile plugin (`onResolve` + `onLoad` with `loader: 'file'`).
- Bun.secrets (Bun 1.4.4, macOS Keychain).
- `proper-lockfile` 4.1.2 under Bun from source.
- `Bun.serve` for the loopback listener, both families.

## Trials (scripts kept outside the repository)

| | What | Result |
| --- | --- | --- |
| T1 | tools advertised, system prompt, overlap, native and Wasm | host tools only; no AGENTS.md; reads overlap natively, writes serial, Wasm serial |
| T2 | cancel and close: hung model, stuck tool, aware tool, slow stream | ≤ 11 ms cancel, ≤ 6 ms close; stuck tool abandoned; threads 11 → 20 |
| T3 | Codex plan, every request 401 then 500, fake `fetch` | npm lookup; refresh + `onCredentials`; 500 retried ≥ 7 times in 20 s |
| T3b/c | Codex and Grok plan turns on a fake Responses stream | `end_turn` with text, no network |
| T4/T4b | Bun.secrets timings and concurrency | serial fine; 20 concurrent wedge the process's store |
| T5/T5b | loopback binds | `EADDRINUSE`; `::1` bindable beside another's `127.0.0.1`, and `localhost` reaches it |
| T6 | memory per engine | native +2 MB, Wasm +41 MB first |
| T7 | every model request 500, custom and Codex, 300 s cap | 15 and 16 requests, backoff to 30 s then every 30 s; not ended at 300 s |
| T8 | two independent credential cells, one store, one lock dir, rotating provider: `naive`, `cas`, `logout` | naive spends a rotated token and fails; cas: one rotation, both turns end; logout: store ends absent, late write refused, turn-start check signs out |
| build | missing file import; per-target selection; plugin; durability in binary; unwritable TMPDIR | build fails; only the plugin embeds one addon; default durability fails compiled; Wasm fallback works |

## What I could not check

- Linux: glibc 2.31 fallback was the gate's; a `noexec` temp directory,
  Secret Service present and absent, and the compiled Linux binaries were
  not run (no container runtime this session).
- darwin-x64 under Rosetta, for anything beyond the gate.
- A locked keychain, or one reached over ssh.
- Whether xAI rotates refresh tokens.
- The Responses API stream for tool calls and reasoning on the plan
  providers (only text was played).
- `proper-lockfile` inside the compiled binary, and across real
  processes (T8 ran two cells in one process with one lock directory).
- Where the agent-level retry of T7 is capped, if anywhere.
- The permission contract's symlink and changed-file cases: specified,
  not tried.
- The live text of OpenAI's and xAI's terms (403).
- A native crash's effect, which would need a crashing addon.
