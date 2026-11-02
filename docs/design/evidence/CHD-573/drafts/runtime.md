# CHD-573 runtime draft: `chord acp`

Proposals only: `chord acp` does not exist. The owner has answered (comments on CHD-573);
section 8 lists what binds this draft, and one item left for the lead.
Line numbers are at this branch's head. Trial facts are from
`../sdk-trial/output/`, produced by `../sdk-trial/run.sh`. "Not verified" marks
what I did not run or read through.

## The package in one page

- **The gate passes.** `agent({ name })` runs the same under Bun and compiled in
  24 scenarios. No protocol helper is needed. Eight gaps are below; none is worked
  around.
- **Too large for one pull request; it goes as ordered tasks over three pre-releases.**
  Plain sessions first, which touch nothing in `src/ui/`. Children and teams need
  about 2800 lines moved out of a React hook, without behaviour change, first.
- **One process, one client connection, one agent runtime, several upstream
  sessions.** Each session is one `AgentsHost`: a main `Conversation` with its own
  children, tasks and monitors. They share one chord MCP server.
- **One way out,** whatever starts it: stdin EOF, a signal, stdout gone, an oversized
  line. One deadline, armed at its first line, covers all of it;
  past it every process group chord spawned is killed from one registry, and chord
  exits. Output still queued is abandoned: the drain is best effort.
- **stdout is written through one stream,** on `process.stdout.write`'s callback.
  Node's `Writable.toWeb` loses data here: 65,536 of 16 MiB. That stream holds a
  stalled writer and keeps the loop live; it does **not** bound memory, because the
  SDK retains what waits behind it. By the owner's R1 nothing ends a client that hangs
  while connected: it holds memory and agents until it is killed. A known limit.

## 1. The library gate

Target: Bun 1.4.4, SDK 2.2.0, darwin arm64. A minimal agent on `agent({ name })`
(`sdk-trial/agent.mjs`), driven with raw newline-delimited JSON over real pipes
(`client.mjs`), as source and as a `bun build --compile` binary. The trial
directory is outside the repository and reaches the SDK through a link to the
repository's `node_modules`, so it is the version `bun.lock` pins and nothing was
downloaded. The scripts are `.mjs` because tracked TS must be in `bun check`
(`scripts/dev/covered.ts`), and `docs/` is not. Linux and Windows were not run.

### What works

The compiled binary's results equal Bun's in all 24 scenarios (`bun.jsonl`,
`compiled.jsonl`, timings and memory aside).

| Scenario | Result |
| --- | --- |
| `initialize`, `session/new`, prompt with 5 updates | all updates before the answer, `end_turn`, clean stdout |
| `session/request_permission` round trip | answered, the turn goes on |
| `session/cancel` with a permission pending | `$/cancel_request` goes out, the client answers `cancelled`, the prompt `cancelled` |
| Prompt and `session/cancel` in one write, 20 tries | order kept, none hung |
| `$/cancel_request` for a running prompt | the handler's signal aborts, its answer goes out |
| stdin EOF, idle | `closed` resolves, exit 0 in about 50 ms, with or without `process.exit` |
| SIGTERM, prompt running | answered `cancelled` first when the handler waits for it, then exit |
| Extension request and notification (`_chord/*`) with a parser | answered. Unknown request -32601, unknown notification ignored |
| Handler throws; garbage line; JSON array | -32603 with `data.details`; -32700; the connection lives on |
| A request before `initialize` | -32600, plain app and router |

Negotiation (`negotiation matrix`):

| Asked | plain `agent()` | router v1 | router v2 | router both |
| --- | --- | --- | --- | --- |
| 0 | 1 | 1 | -32022 | -32022 |
| 1 | 1 | 1 | -32022 | 1 |
| 2, v2 shape | 1 | 1 | 2 | 2 |
| 3, v2 shape | 1 | 1 | 2 | 2 |
| 2, v1 shape | 1 | 1 | -32602 | -32602 |
| not a number | -32602 | -32602 | -32602 | -32602 |

v2 runs, but it is another lifecycle: the prompt answers `messageId` at insertion,
the turn ends in `state_update` `idle`, and `session/load` is -32601. That cost
belongs to question 5; runtime's interest is that v2's turn outlives its request,
which the turn table in section 3 would not fit.

### The gaps

**G1. `Writable.toWeb(process.stdout)` has no backpressure and loses data.** With
nobody reading (`stall.mjs`, a `sleep` on the pipe's far end):

| stdout as | 256 MiB, awaited, nobody reads | Loop runs | `process.exit` after 16 MiB, slow reader | EOF then exit |
| --- | --- | --- | --- | --- |
| `Writable.toWeb` | "done" in about 80 ms, RSS 522-560 MiB | yes | **65,536 bytes arrive** | about 20 ms |
| `write(chunk, callback)` | held at the first full pipe | yes | all arrive | about 20 ms |
| `Bun.write(Bun.stdout)` | held | **no** | all arrive | **not in 3 s** |

Same on both targets. So: a `WritableStream` over `process.stdout.write(chunk,
callback)`, as `src/acp/process.ts:240-255` already wraps an agent's stdin and
`writeAll` wraps `-p`'s stdout (`src/main.tsx:104`). This builds the stream the SDK
takes; it changes nothing of the SDK's. It goes in `docs/decisions.md` so nobody
"simplifies" it. A test pins it (section 7).

**G2. The SDK has no output limit on stdio.** `ConnectionLimits`
(`dist/transports/connection.d.ts`: 64 MiB, 60 s) covers HTTP and WebSocket. With
G1's stream, an awaited send waits for ever on a client that stopped reading, and
everything unawaited queues in the SDK. There is also no public place to count that
queue for every class of output: G7. The owner's R1: not solved now, no rule and no SDK
issue. Section 8.

**G3. A cancelled outbound request stays pending.** `cancellationSignal` sends
`$/cancel_request` and settles nothing (`dist/core/jsonrpc.js:485-492`); a client
that does not answer leaves it pending until close (trial: no answer in 1 s). So
chord never waits on the client to finish a cancel: `Agent.cancel` answers
downstream itself (`src/acp/connection.ts:292-300,545`), and protocol's draft says
the same.

**G4. `close()` does not flush, and has no drain.** It aborts, and the write queue
then throws for whatever waits behind (`jsonrpc.js:511-527,747-751`). Whoever needs
an answer out waits on its own send first (section 4).

**G5. EOF closes the whole connection.** `receive()` ends at `done` and closes
(`jsonrpc.js:578`), so a client that half-closes stdin and keeps reading gets no
answer to a running prompt (trial: `answered: false`). A client that does this is
treated as gone. Keeping the writer open would need rewriting the stream's end,
which is a workaround: not proposed. The owner's R2 agrees: EOF means the client is gone.

**G6. One line over 32 MiB closes the connection,** by `MessageTooLargeError`
(trial: `closed`, exit), with no answer. `maxMessageBytes` is an option of
`ndJsonStream`, and chord's client side uses the default (`connection.ts:356`). I
would keep the default: the failure is plain, and a larger number only moves it.

**G7. No public boundary before the SDK's write queue, for every class of output.**
`sendMessage` chains each message in a closure on `writeQueue`
(`dist/core/jsonrpc.js:743-764`). A `Stream.writable` sees only the head, after the
one before it finished.

| Output | Sent by | Public point before the queue? |
| --- | --- | --- |
| Notifications, chord's requests | `client.notify`, `client.request` | yes: chord's own call |
| A handler's answer | the SDK, from what the handler returns (`jsonrpc.js:682-688`) | only the handler's own return: chord's code can count there |
| An error a handler throws | the SDK | likewise, at the throw |
| -32601, unknown method | the SDK (`jsonrpc.js:649`) | `onRequest('*')` could take these, by answering in chord's code |
| -32602, params that do not parse | the SDK, before the handler | **no** for a built-in method |
| -32600 before `initialize` | the SDK's gate (`v1/acp.js:44`) | **no** |
| -32700 and batch -32600 | `ndJsonStream`, on its own chain, past `Connection` (`core/stream.js:48-60`) | **no** |

`Connection`, `RequestResponder` and `ConnectionBuilder` are not exported from any
entrypoint; `connectionContextOf` is marked `@hidden`. So no public boundary covers
all of it. That is a library gap. The owner's R1 leaves it open and files nothing.

Measured, on the callback stream with nobody reading (`queue.mjs`, Bun; compiled alike):

| Output held | RSS |
| --- | --- |
| 256 MiB of unique notifications | 345-353 MiB |
| 160 MiB of responses from a handler | 417-491 MiB |
| The SDK's -32601, 500k requests of about 70 bytes | **1594-1772 MiB** |
| The SDK's -32602, 100k requests | 448-535 MiB |

The last two come from the client's own input, but about 3 KiB per queued message is
far above the message's size, so a byte count would understate memory badly anyway.

**Completed writes, by contrast, have a public place.** The `Stream` type is public and
chord already wraps it (`src/acp/traffic.ts`). A wrapper on `writable` sees each message
as it reaches the head, and when its write finishes, including a response by its `id`.
Handlers get no such promise, and a message still queued at `close()` never reaches the
wrapper (G4). So "this answer's write finished" can be awaited only with a bound.

**G8. A parse error stops input while stdout is blocked.** `ndJsonStream` awaits its own
error write inside the read loop (`core/stream.js:48,78`). With nobody reading, a
garbage line stops later input: the trial's note after them was never handled
(`laterInputHandled: false`), though valid requests alone do not block it. **Nor does the
SDK see EOF then**, so it never closes. Section 4 has what was measured.

Two facts for protocol, reported already: inbound params lose unknown fields and
keep `_meta`; outbound is not validated, so `_chord/custom` as a `sessionUpdate`
went out as sent.

### chord's own start

`chord_start.mjs` builds with `buildOptions`, as `bun dev compile` does, but not
through it: `compile` runs `bun install` first (`scripts/dev/compile.ts:147`), in a
checkout others share. HOME and XDG are empty directories of its own.

| Check | Bun | Compiled |
| --- | --- | --- |
| All of `src/main.tsx`'s imports loaded, then the trial agent, stdin at EOF: stdout bytes | 0 | 0 |
| Load time | 30 ms | 56 ms |
| RSS after load, against about 30 MiB for the trial agent alone | 90 MiB | 75 MiB |
| `console.log` or `stdout.write` patched; stdin raw | no | no |
| Signal listeners added at load | 0 | 0; 1 `exit` listener, not traced |
| `-p` on the fake agent: stdout | the reply alone | the reply alone |

So OpenTUI's load writes nothing and takes nothing. `chord acp` can be a Cliffy
subcommand in `main.tsx` with no lazy import; I would cut lazy loading as not worth
50 MiB until someone measures a reason. The first run of a new binary took 1.2-1.5 s
and later ones about 0.2 s, which looks like the OS's first-run check. Not verified.

Two traps on stdout:

- **Any `console.log` reaches stdout** as a non-JSON line (trial). In `src/`,
  outside `src/ui/`, only `main.tsx:718,742` print there, plus
  `platform/resource_worker.ts:188` in a process of its own. Agents, resource
  readers and monitors have piped stdio (`acp/process.ts:172-174`,
  `resource_process.ts:155-157`, `shell.ts:81-86`).
- **A Cliffy usage error prints the help to stdout** (5826 bytes, exit 2): `throw`
  calls `showHelp()` before the error (`@cliffy/command/command.js:1365`). The `acp`
  command uses Cliffy's own `.throwErrors()` and writes the message to stderr.

## 2. Who owns what today

| Thing | Owner | Below `src/ui/`? |
| --- | --- | --- |
| Agent process, group, stop bounds 2+2+2 s | `src/acp/process.ts:18-22,264-283` | yes |
| ACP client connection, pending asks, their cancel | `src/acp/connection.ts` | yes |
| One agent and one session; bridges for permission, form, plan | `src/session/session.ts:344`, `permissions.ts:97` | yes |
| A session's turn, queue, tasks, monitors, record | `Conversation`, `src/session/conversation.ts:399` | yes |
| Main and children as a list | `OpenAgents`, `open_agents.ts`, `window_agents.ts` | yes |
| chord's MCP server: one per window, tokens per caller | `src/server/server.ts:58` | yes; started in `main.tsx:609` |
| The tools' port, `WindowView` | declared `src/server/tools.ts:263` | **implemented in the hook** |
| Opening children, teams, tell, close, clear | `useSessions`, `src/ui/app/sessions.ts:437-2542` | **no** |
| What `-p` needs: one `Session`, every ask refused | `src/session/oneshot.ts:87`, `src/headless.ts:277` | yes |
| Reaping on a crash or signal | `closeOnForcedExit`, `src/ui/app/renderer.tsx:292` | **no** |
| Settings and MCP per directory (`readPlace`, `placeOf`) | closures in `main.tsx:473,505` | **no** (not `src/ui/`, but out of reach) |

### What has to leave, in what order

Measured by a script over `sessions.ts`: lines 309-2778 are 2470 lines, holding 13
`dispatch(` calls, 12 `useRef`, 1 `useEffect`, and only 2 reads of `all.`. Interface's
draft splits it the same way. The hook is already nearly a class. The risk is not
size but closures: `view` is "made anew with each draw" (`sessions.ts:2557`), and
whatever the moved code reads from a render must become a field or a call to the
port. That reading was not done line by line.

| Task | What | Size | Touches the window? |
| --- | --- | --- | --- |
| **1. Plain sessions**: CHD-574, CHD-576; next.0 | `chord acp`, stdio stream, turn table, one `Conversation` per session, the way out in `src/session/leaving.ts`, the groups registry in `spawnGroup` | about 800 lines and as many of tests (estimate) | no |
| **2. Down**: CHD-579; next.1 | The window's `closeOnForcedExit` and signal leave onto `src/session/leaving.ts`; `busyOf`, `settingPickedUp`; `readPlace`, `placeOf` to `src/session/place.ts` | under 300 moved | no behaviour |
| **3. The host**: CHD-580; next.1 | The hook's `sessions.ts:437-2542` and `view` (`:2561-2756`), and T4's typed commands (`:3049-3130`, `:3136-3237`, `:3380-3546`, about 340 lines, protocol.md "What stands in the way"), into `src/session/agents_host.ts`; the hook keeps its returns and turns the host's events into actions | about 2800 moved | yes, no change meant; `tests/ui/app/sessions_test.tsx` (1258 lines) stays as it is |
| **4. Children and teams**: CHD-581; next.2, with CHD-575, CHD-582 | `chord acp` on the host: server, tools, teams, monitors, a place per session, `_chord/session/state` | about 400 | no |

**Too large for one pull request.** It goes as these tasks, one at a time, in the owner's
three pre-releases. **The smaller first package is task 1**: any ACP client drives one agent
through chord, with records, enrichers and asks, but no chord MCP server, so no
children, teams or monitors beyond what the agent does by itself. Task 1 ships
alone without harm, and proves transport and shutdown before the risky move. The
task's goal names teams, so the milestone is not done before task 4.

Task 1 uses `Conversation`, not `Session` as `-p` does, because records and the queue
are there. Recording, as the owner's Q4 has it, is one injected constructor argument
(`sessions.ts:530`).

**Cut:** v2, `session/fork`, `_chord/teams/*`, lazy imports, agents' stderr on chord's
stderr.

## 3. Modules

```text
src/acp_agent.ts            runAcp(options): exit code. As headless.ts is to -p.
src/acp/agent_app.ts        agent({ name }) and its handlers; no logic of its own
src/acp/stdio.ts            the stream on stdout's callback; the wrapper that sees each write
src/acp/upstream_turns.ts   pure: protocol's request-to-turn table, as a reducer
src/session/leaving.ts      new in task 1, one way out, one deadline; the window joins in task 2
src/platform/process.ts     gains the registry of spawned groups (section 4)
src/session/place.ts        moved: a directory's settings and MCP servers
src/session/agents_host.ts  moved: main, children, teams, the tools' port; no React
```

Tests mirror each one. The registry goes in `src/platform/process.ts` only because
`spawnGroup` is there; nothing here is Bun's own. `bun build --compile` needs nothing new: the SDK's
`/unstable` entrypoint is already in the binary.

`runAcp` takes `input`, `output`, `stderr`, `open` and `exit`-free results, as
`runHeadless` does (`headless.ts:253`), so tests run it in-process. `main.tsx`'s
action is only its wiring.

Logic stays testable by being in pure modules:

- `upstream_turns` implements **protocol's table binding JSON-RPC requests to turn ids**,
  queued against running cancel and autonomous cycles included. The table is protocol's;
  this is its reducer and adds no rule. One runtime constraint on it: the handler must
  enter the request in the table synchronously, before any await, or a cancel can pass
  it (the trial's order held only because the SDK's dispatch reaches both handlers in
  order up to their first await). That keeps arrival order. It does not by itself give a
  prompt its identity: which turn a request is, comes from the table and from
  `Conversation`'s turn ids.
- The `stdio.ts` wrapper gives `written(id)`, which the drain awaits within its bound.

## 4. The way out

One `leave(reason)`, once. A later cause waits for it, as a second signal does in the
window (`renderer.tsx:301`).

```text
1. Arm the deadline, LEAVE_MS = 15000, before anything else and before any await. It
   covers the whole way out, drain and record flush included.
2. Refuse new work: new requests get -32603 "chord is closing".
3. If the connection lives (a signal; not EOF or EPIPE): send the answers
   upstream_turns gives for closing. Withdraw each ask.
4. At once, none behind another, each settled on its own:
   a. drain: await written(id) for those answers, at most DRAIN_MS = 500, then
      connection.close();
   b. each host's closeAll: stdin, SIGTERM, SIGKILL to each group, record flush
      (open_agents.ts:199, conversation.ts:2698-2731);
   c. chord's MCP server, the probes (runtimes.ts:80), the resource readers.
5. All settled: write each failure to stderr, SIGKILL what the registry still holds,
   clear the deadline, exit.
6. Deadline first: stderr names what had not settled, and each group by pid. SIGKILL
   every group in the registry at once, without waiting for it. Exit.
```

Server and readers do not wait behind hosts: a hung host must not keep a collector
alive until expiry. An agent's tool call after the server closes fails; it is being
stopped anyway.

Why 15 s: one agent takes at most 6 s (`process.ts:18-22`), and `Conversation.close`
awaits tasks before its own session (`:2714-2730`), so a hung task and a hung main take
12 s. Deeper nesting, or a blocked flush, meets the deadline.

**What the drain is.** Best effort. All that holds:

- A message whose write finished is in the pipe, and an exit after it loses nothing
  (trial, callback stream).
- A message at the head when the deadline or `DRAIN_MS` passes, or queued behind it, is
  **abandoned** by `process.exit`. On a stalled pipe that is everything queued: the trial's
  SIGTERM while blocked exits in about 55 ms on both targets, and nothing queued arrives.
- So a client gets its `cancelled` answers only if it is reading.

### Which registry covers which process

`Session.agentPids` will not do: it holds the live main agent's pid, added after
`initialize` and deleted when the root exits (`session.ts:440-441`). All chord's process
groups come from one function, `spawnGroup` (`src/platform/process.ts:61`), whose callers
are `acp/process.ts:169`, `shell.ts:81` and `resource_process.ts:153`. **There is no
registry today. Add one there, in task 1**: every group from spawn until nothing is left
in it.

| Process | Phase | Owner that closes it normally | Registry |
| --- | --- | --- | --- |
| Agent still starting | spawn to `initialize` | the open's signal (`session.ts:106`, `connection.ts`) | yes, from spawn |
| Main agent | running | `Session.close`, `process.ts:264-283` | yes |
| Exited leader's surviving group | after root exit | the stop's last SIGKILL (`process.ts:281`), only if a stop runs | yes: kept while `alive()` |
| A `/clear`ed or replaced session | retiring | `Conversation.#retiring` | yes |
| Task's agent | running, ended | `Conversation.#tasks`, `#endedTasks` | yes |
| Child, member (task 4) | running | `OpenAgents.closeAll` | yes |
| Runtime probe (task 4) | opened to read, closed | `Runtimes.close` | yes |
| Monitor's shell (task 4) | running, stopping | `#stopMonitors`, `runShell`'s reap (`shell.ts:62`: 2 s to SIGKILL) | yes |
| Resource collector (task 4) | a read, its close | `closeResourceGroup` (`resource_process.ts:83`) | yes |

Entry rules: added at spawn when a pid exists; at the leader's exit dropped if `alive()`
says the group is empty, else kept. Kept entries are rechecked at each spawn and at the
sweep. **Risk not removed:** a kept group that empties unseen could see its pgid reused
before the next check. `process.ts:281` already signals a group after its leader's exit,
but only at once. The window is left as it is: it may use the registry later.

### Failures in cleanup

Each settled failure goes to stderr with what failed: `closeAll`'s rejection with every
failure (`open_agents.ts:199`), `AgentExitError` with its pids (`process.ts:25`), reader
warnings (as `main.tsx:625`), a record's "could not keep" (`record.ts:1493`). None is
swallowed by the exit. stderr is not awaited: 64 MiB to a stderr nobody reads left the
loop answering (trial), so the deadline still fires.

Exit: EOF, 0 if cleanup was clean, else 1. A signal: dies by it after leaving, as the window
(`renderer.tsx:325`), expiry too. Oversized line or stdout gone: 1.

`process.exit` is called, not left to the event loop: a real host holds timers, a server
and monitors.

### Does each cause reach `leave` with no rule for a stuck client?

Trial `g8.mjs`, on the callback stream: stdout blocked by a reader that reads nothing, one
garbage line, so the read loop is stuck in its error write. Bun and compiled agree; ms are
from the action to the exit. `leave` here is the trial agent's own close and exit.

| Cause | Blocked, no garbage | Blocked, garbage | Reaches `leave`? |
| --- | --- | --- | --- |
| stdin EOF, client still holds stdout | 12-66 ms, `closed` | **SDK never sees it: no `closed`, not within 5 s** | not through the SDK |
| The same, with a second observer of `process.stdin`'s `end` | not run | 11-12 ms | yes |
| SIGTERM | as garbage | 55 ms | yes: the signal handler does not depend on input |
| SIGTERM after that unseen EOF | | 55 ms | yes |
| The reader of stdout goes, stdin stays open | | 11 ms: EPIPE, `closed` | yes |
| The client SIGKILLed, both pipes close | 11-12 ms | 11-12 ms: EPIPE, `closed` | yes |

Node's `process.stdin` does emit `end` and `close` while the web stream's reader is stuck
(`saw`, in `output/g8_*.jsonl`). So:

- **A client that dies is always seen,** garbage or not: its pipes close, and the write fails.
- **A signal is always seen.**
- **What the SDK misses is narrow:** a client that sent a malformed line, left stdout full,
  then closed stdin while something still holds stdout open. It needs a choice: section 8.
- **A client that hangs with its pipes open, reading nothing, is not a cause at all.** Nothing
  starts `leave`. Agents go on, memory grows in the SDK's queue, a cancel after a malformed
  line is not read. It ends when the client reads, closes, dies or chord gets a signal: until
  killed, in the owner's words.

**For the guide, the known limit:** a client that hangs while still connected holds chord's
memory and running agents until it is killed. While its stdout is full, a malformed line also
stops chord reading its input.

## 5. Concurrency

**One or many sessions per process.** Many, one `AgentsHost` each. `session/new`
starts one, `session/close` ends it. Protocol has `/clear` become `session/new`, so
refusing a second would break that. It is not tabs: the window keeps CHD-493's one
main, and this costs nothing beyond isolation that exists already: a `Caller` carries
its own `window` (`tools.ts:101`) and keys are per host. Shared: one `ChordServer`,
loaded agent table, resource readers, and `settingsBoxClaim`, which moves up so one
box shows at a time. Per session: `cwd`, hence its `Place`, and everything else.

| Situation | Outcome |
| --- | --- |
| `initialize` | Answers without starting an agent: `openSession` starts, initialises and opens together (`session.ts:344`), and a failed agent must not fail the handshake. Capabilities are protocol's |
| `session/new` | Starts the agent; answered when it is up. Its signal (`$/cancel_request`) gives up on the start (`session.ts:106`) |
| Two sessions' turns at once | Independent: own process, own queue. Their updates interleave on the one stdout, each whole, in the order sent |
| Second prompt in a session | Queued by `Conversation.send`, answered at its own turn's end |
| `session/cancel` | Running turn interrupted; prompts withdrawn and answered `cancelled` (`conversation.ts:2350`); agents' messages stay queued, as there |
| Cancel in a turn nobody prompted | Interrupts it. No request to answer |
| A turn nobody prompted (task report, monitor, message) | Updates go out with no request open. A prompt arriving then queues. Asks are forwarded all the same |
| A child's or task's permission | Protocol's mapping, the owner's A2: protocol.md Q2. At run time each is one request, settled alone |
| Several asks at once | All forwarded: each its own request, each settled alone. No serialising |
| A child opened while the session closes | Refused: `launchSignal` and `stale(caller)` hold (`sessions.ts:2552`) |
| Monitors firing with the client slow | A monitor's event is a turn; its updates queue like any other |
| Limits | `MAX_CHILDREN` 8 per session (`window_agents.ts:16`), as it is. No cap on sessions (the owner's R3) |

**Order.** One SDK write queue per connection, so one client stall holds every session's
output. Valid input keeps being read while stdout is stuck (trial), so a cancel still
works; after a garbage line it does not (G8), until the client reads, goes, or chord gets a
signal.

## 6. Failures

Each supported row has one named test. Files: `P` is `tests/acp_process_test.ts` (spawned,
real pipes), `A` `tests/acp_agent_test.ts` (`runAcp` in-process, real fake agent), `L`
`tests/session/leaving_test.ts`, `S` `tests/acp/stdio_test.ts`. Fake means
`tests/fixtures/fake_agent/`. The rows that are protocol's words (error codes) follow its
Failures table.

| Case | Outcome | Test and setup | Observed |
| --- | --- | --- | --- |
| stdin EOF, idle | `leave`, agents gone | P `eof idle`, `text` | exit 0; agent's group gone |
| stdin EOF, turn running, ask pending | No answer possible (G5); downstream `cancelled` | P `eof with an ask`, `permission` | exit 0; fake logs `cancelled`; record holds the turn |
| Client SIGKILLed | Pipes close, so EOF | P `client killed`: a parent script, SIGKILLed, spawns chord | chord gone; agent's group gone; record flushed |
| SIGTERM, SIGINT, SIGHUP, turn running | `cancelled` first, dies by the signal | P `signal in a turn`, three runs, `slow` | wire: `stopReason: cancelled`; exit signal; group gone |
| A signal with stdout already blocked | Queue abandoned, way out unhindered | P `signal while blocked`, `flood`, nobody reads | exit by signal within `DRAIN_MS` and stop bounds; group gone |
| stdout closed by the client | EPIPE closes (trial) | P `stdout closed`, `long` | exit 1; stderr line |
| Client hangs, pipes open, reading nothing | No rule (the owner's R1): chord stays, agents go on, until killed. Listed in the guide | `signal while blocked` above covers the kill | no exit until the signal |
| Client never answers an ask | Waits; cancel, EOF or close end it, chord answers downstream | A `ask unanswered, then cancel`, `permission` | prompt `cancelled` once; fake logs `cancelled`; a late answer changes nothing |
| Ask answered with an error | Refusal, stderr line | A `ask error`, `permission` | fake logs the reject option; turn goes on |
| Ask answered with an unknown option id | Refusal; `resolve`'s throw caught (`permissions.ts:136`) | A `ask invalid option`, `permission` | fake logs the reject option; process lives |
| Second prompt queued, then cancel | Each answered `cancelled`, the queued one never reaches the agent | A `cancel queued`, `slow` | two `cancelled`; fake logs one prompt |
| `session/close` with a turn running | Prompt settled exactly once, then the close | A `close active`, `slow` | one answer per id; group gone; later prompt -32002 |
| `session/resume` or `load` of an id open here | Protocol's answer; the open session unharmed | A `resume active`, `slow` | error per protocol; running turn still answers |
| A session id already open | An agent gives an id in use: refused, new process stopped, the first untouched | A `colliding ids`, new fake flag `--session-id` | `session/new` error; first session still answers |
| Replay on `session/load` | Gated as live; no asks; before the answer | A `replay gating`, a record fixture with a plan, client without `plan` | no `plan_update` on the wire; updates before the answer |
| Line over 32 MiB | Connection closes | P `oversized line` | exit 1; stderr line; group gone |
| Garbage or batches | -32700, -32600; lives on | A `garbage` | those errors; next prompt answered |
| Parse error with stdout blocked | Input stops (G8); a signal or the client's death still ends it | P `garbage while blocked`, `flood`: then SIGTERM, and a second run killing the client | later note unhandled; exit by the signal, 1 on EPIPE; group gone |
| The same, stdin closed, stdout held | By section 8's choice | P `eof while input stuck`, `flood` | as chosen: exit 0 and group gone, or no exit until a signal |
| Agent command missing or refused | `session/new` -32603, process lives | A `start fails`, a second session on a good command | error with `failureLines`; second answers |
| Agent needs login | -32000 | A `login`, `--auth-required` | code and `signInLines` in `data` |
| Agent hangs at start | Open until cancelled or EOF | A `start hangs`, `gatedCommand` | `$/cancel_request`: answered; group gone |
| Agent dies in a turn | Prompt -32603, monitors stopped | A `dies in a turn`, `crash` | error with last words |
| Agent dies between turns | Next prompt -32002; resume reopens | A `dies between turns`: the fake's pid killed | -32002, then `session/resume` answers |
| Agent ignores cancel | Prompt stays open, no timer, until `session/close` settles it once | A `cancel ignored`, new fake `ignorescancel` | no answer in a bounded wait; after close one answer; group gone by SIGKILL |
| Agent floods, client reading | Read and sent in order | A `long` | all chunks, in order, then the answer |
| Agent writes on stderr | Tail kept, not forwarded | P `agent stderr` | chord's stdout and stderr hold none of it |
| chord crashes (uncaught) | Stack on stderr, never stdout, way out runs | P `crash`: injected throw | exit 1; stdout parses; group gone |
| Deadline expires: a task or child | Registry SIGKILL, stderr names it | L `expiry, task`: agent with a stopped-ignoring group, short `LEAVE_MS` | exit within the deadline; group gone; names it |
| Deadline expires: a monitor (task 4) | The same | L `expiry, monitor`: `trap '' TERM` shell | the same |
| Deadline expires: a resource collector (task 4) | The same; readers not behind hosts | L `expiry, collector`: collector ignoring stdin and TERM, with a hung host | collector's close starts before the host settles; group gone |
| Deadline expires: blocked record flush | Exit, tail of the record lost, stderr says | L `expiry, flush`: a `Recording` whose `flushed` never settles (`record.ts:246`) | exit within the deadline; stderr names the record |
| Cleanup failure | On stderr; EOF exit 1 | L `failure kept`: a close that rejects | stderr has it; exit 1 |
| stderr closed | Harmless: an EPIPE there must not crash | P `stderr closed`, `2>&-` | exit 0 on EOF; stdout parses |
| stderr blocked | Loop goes on (trial) | P `stderr blocked`, nobody reads, an agent start failure repeated | prompts still answered; deadline fires |
| chord SIGKILLed | Agents see EOF; one ignoring it survives, in its own group | none: unsupported | not measured |
| A process that left its group (`setsid`) | Out of reach of the registry | none: unsupported | not measured |

**Task 4's rows, with outcomes** (A, on `AgentsHost`):

| Test, scenario | Observed |
| --- | --- |
| `chord tools`, `chordtools` | The agent's MCP calls answered; a second session's token sees only its own children |
| `task ask`, `taskask` | One request upstream, as protocol.md Q2 settles; fake logs the answer |
| `team runs`, `teamtask` | Lead and member groups exist; `session/close` leaves none |
| `child clears`, `agentclear` | Identity kept; late delivery refused, per `src/session/AGENTS.md` |
| `unprompted turn`, `taskwait`, `latesay` | Updates with no request open; `upstream_turns` answers nothing; a prompt then queues |

**A second `chord acp` in one directory.** Nothing to clash on, and no lock:
- MCP server on port 0, per process (`server.ts:130`).
- A record per session, a new UUID file (`record.ts:1245`); readers skip what they
  cannot read (`sessions.ts:97`).
- Settings writes are atomic.
- Two on one session id, by `load` or `resume` in both: both append to one record and
  the adapter decides. As two windows today. Not verified what an adapter does.
- Both editing one tree: as two windows. Not chord's to prevent.

**Process tree left behind.** What holds: on every way out that runs, every group chord
spawned has been stopped or has had SIGKILL from the registry, the group and not just the
leader. On expiry chord does not wait to see them reaped. What does not hold: chord itself
SIGKILLed or the loop blocked synchronously, when nothing runs; a process that left its
group; a pgid reused (section 4). A client killing only chord's pid is enough, since chord
leaves on the signal. Agents are not in chord's group, so a client signalling that group
does not reach them, and chord still stops them.

## 7. Test plan

Nothing reaches a real model, agent or provider.

**Pure, directly:**

- `tests/acp/upstream_turns_test.ts`: every order of prompt, cancel, turn end and
  closing gives each request one answer; a prompt queued and withdrawn; a turn nobody
  prompted answers nothing.
- `tests/acp/stdio_test.ts`: the stream on a real pipe nobody reads: a write stays
  pending, the loop runs, EOF exits. `written(id)` settles for a response, and not for
  one dropped at close, within its bound. **A test that fails if someone returns to
  `Writable.toWeb`:** exit after 1 MiB to a slow reader, all bytes arrive.
- `tests/session/leaving_test.ts`: section 6's `L` rows. `tests/platform/process_test.ts`:
  the registry from spawn, an exited leader's survivor kept, an empty group dropped.
- `tests/session/place_test.ts`: moved with its code.
- **`tests/session/upstream_conversation_test.ts`, task 1:** the adapter on a real
  `Conversation` and the fake agent, with no `src/ui/`: `text` gives updates then
  `end_turn`; `permission` asks and hears the answer; a queued prompt answers at its own
  turn's end. It also asserts `src/acp_agent.ts`'s static imports reach neither OpenTUI
  nor React.

**Upstream fixture:** `tests/fixtures/acp_client.ts`, new. Raw lines over a stream pair
or a process, so a test sees the wire: that every stdout line parses, what order things
came in. Not the SDK's client, which would hide a malformed message.

**Both sides:** section 6's matrix is the list. Beyond it, in `A`: a streamed reply (`text`,
`long`) in order; form and link, and a client without the capability (`form`, `link`,
`leftform`: declined, cancelled); `late` and `unknown` updates; a plan ask with no method
(`cursorplan`, `grokplan`: fake logs `cancelled`); `subagent` gated by capability.

New in the fake agent, each added to `tests/fixtures/fake_agent/AGENTS.md`: scenarios
`flood` (enough to fill the pipe, for the tests with stdout blocked) and `ignorescancel`,
flag `--session-id`. An agent dying
in a turn is the existing `crash` (`scenarios/agents.ts:709`). `tests/acp/connection_test.ts:1534`
covers today's downstream close only; `cancel ignored` is new.

**Spawned, real pipes:** `P`, `bun src/main.tsx acp --agent-command <fake>`: beyond the
matrix, stdout is ACP only, including with a usage error; a second process in one directory. `--changed` follows static imports only, so these must be named when
`src/acp_agent.ts` or `main.tsx` change (a known trap in this tree's tooling).

**The window, task 3:** `tests/ui/app/sessions_test.tsx` and the team tests stay
unchanged and pass. `tests/session/agents_host_test.ts` drives the host with no React.
Interface checks by hand through `tests/ui/harness.tsx` and tmux at 120x40 and 80x24.

**The binary:** `bun dev selftest` gains one step beside `-p`
(`scripts/dev/release/selftest.ts:136`): `chord acp` on the fake agent, one prompt, one
permission, EOF. CI's `compile` job does the rest.

**Lint:** a `no-console` rule for `console.log` in `src/session/`, `src/acp/`,
`src/server/`, with its snippet in `lint/config_test.ts`. With the spawned test, that
holds stdout. I would not patch `console.log` to stderr at run time: a stray write is
a bug to find, not hide.

### What stays unmeasured

- Any real ACP client: what it does with a slow `session/new`, its own timeouts, how
  soon it kills chord after closing stdin, if it reads stderr.
- Real agents through `chord acp`: out of this design's checks.
- Linux and Windows. The trial ran on one Mac. `process.kill(-pid)` is not on Windows
  (`platform/process.ts`), and G1's numbers may differ on Linux; the test in section 7
  runs on CI's Linux shards. The compile target on Windows was not run.
- Long runs: memory of many sessions. `bun dev memory` (`docs/memory.md`) has no acp mode.
- A stuck client's memory over time: no rule, so no bound. The trial's numbers are one Mac,
  one message size.
- Whether stderr stays non-blocking off macOS. A blocking stderr would hold the loop, and
  the deadline with it.
- Real upstream throughput with many agents on one stdout.

## 8. What the owner decided, and one choice left

From CHD-573's comments, as they bind this draft:

| Item | Decision | Here |
| --- | --- | --- |
| R1 | Not solved now: no rule for a client that stops reading, no SDK issue; the guide lists it | Section 4's known limit. No stall in `leave` |
| R2 | EOF on stdin means the client is gone; nothing hides EOF from the SDK | G5 |
| R3 | No session cap per process | Section 5 |
| R4 | A `WritableStream` over `process.stdout.write(chunk, callback)`, pinned by a test | G1, section 7 |
| Shutdown | 15 s over the whole way out, then groups killed; 500 ms best-effort drain | Section 4 |
| Q1, Q2, Q4, A2 | Protocol's sections carry them | The agent fixed per process; asks forwarded with no timer; recorded |

**The choice left: EOF with the read loop stuck (G8).** The owner's R1 and "shutdown as designed"
do not reach it, and the trial is not the owner's consent.

- **A (recommended):** `runAcp` also listens for `process.stdin`'s `end` and starts `leave`.
  It hides nothing from the SDK, which goes on reading as before, and hands no input to it. Trial:
  11-12 ms on both targets. Cost: a few lines and one test. Lines still inside the SDK at EOF may
  go unhandled, as they may at any EOF (R2).
- B: no second observer; the case joins the guide's known limit, ended by a signal.

## 9. Open questions

- The `exit` listener the compiled load adds: not traced. Harmless to the trial.
- Whether task 3's closures hold anything a render refreshes, beyond the 2 `all.` reads.
  CHD-580's first step is to read them; if many, the estimate is wrong, not the plan.
- Where `settingsBoxClaim` goes if a person is asked in two sessions at once.
