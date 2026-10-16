# chord's memory

How to look inside a running chord's heap, how to run the long-run memory
check, and what the check found (CHD-343).

## A heap snapshot of a running chord

```sh
kill -USR2 <pid>          # pgrep -f chord finds the pid
```

chord writes a snapshot of its JavaScript heap and goes on running; nothing
is drawn on screen. Two files land in `heaps/` in chord's state directory
(`$XDG_STATE_HOME/chord`, `~/.local/state/chord` by default), named by the
pid and the time:

- `chord-<pid>-<time>.heapsnapshot` — the heap, in V8's format
  (`Bun.generateHeapSnapshot('v8')`). Chrome's DevTools open it: Memory,
  Load, then the file. Two of them compare there (Comparison), or with
  memlab, as `bun run dev memory` does.
- `chord-<pid>-<time>.json` — taken right after it: the process's memory
  (`rss`, `heapUsed`, `external`) and JSC's own counts from `bun:jsc`'s
  `heapStats()`, among them every object type's count. A look at it needs
  no DevTools.

The snapshot collects garbage first, so what it shows is what was held.
Writing it takes a second or more on a big heap, during which the window
does not draw, and the process grows by about the snapshot's size while it
is written. A snapshot that failed leaves its error in `heaps/heap-error.txt`.
A second signal while one is being written is dropped.

What macOS counts for the process, swapped pages included:
`footprint -p <pid>`; `vmmap --summary <pid>` splits it by tag, JSC's heap
under `tag 240`.

## The long-run check

```sh
bun run dev memory                      # 10 minutes from source
bun run dev memory --minutes 30 --snapshots 6
bun run dev memory --binary dist/bun-darwin-arm64/chord
bun run dev memory --development         # React's development build
```

It runs chord in a tmux session of its own on the fake agent, in a
temporary directory with the fake team `bugfix`, chord's state and an empty
home and configuration (`HOME` and `XDG_CONFIG_HOME`), so whoever runs it
has no keybinding or setting of theirs change what typing `soak` and Enter
does, and sends `soak`: main hands the team a job its agents never finish, and main,
the lead, `tester` and `coder` take turn after turn, each streaming a
30-line markdown reply with a call, then messaging whoever asked. It
samples resident size, macOS's footprint and the bytes in the session
records (which grow as the transcripts do) every `--sample-seconds`, takes
`--snapshots` snapshots by `SIGUSR2`, the first after a minute's warm-up,
and has memlab compare the first with the last: what grew, by object type
and name, and the shortest path from a root to an example of each. The run's
directory is kept, with `report.txt`, and printed last.

It reads the turns each agent has taken from the records, and fails rather
than report an idle window: when main, the lead, `tester` and `coder` have
not each taken two streamed turns within two minutes of `soak`, or when no
agent takes a turn for a minute, it stops with the turns so far and the
screen. Ctrl+C or `SIGTERM` at any point ends its tmux session and waits
for chord and every fake agent under it to exit, signalling what has not
within ten seconds.

From source it runs chord as `bun run chord` does, with React's production
build; `--development` runs it as plain `bun src/main.tsx` does, with the
development build.

It is a script, not part of `bun run check`: memory that grows shows only
over minutes, and the check's tests end in seconds.

memlab's ids do not carry over between two of Bun's snapshots, so what grew
is told by counts and sizes per type and name, not object by object. An
object held only from native code (a callback `Bun.serve` keeps, a timer)
has no path from a root in the snapshot; memlab shows those without one.

## What it found (2026-10-12)

Three 8-minute runs side by side on an M-series Mac, 120×40, the fake at its
default pace: from source, from source with `NODE_ENV=production`, and a
binary from `bun run dev compile`. Each streamed about 4.2 MB of session
records.

| run             | footprint at 1 min → 8 min | JSC heap at 1 → 8 min | `Error` objects | `performance` |
| --------------- | -------------------------- | --------------------- | --------------- | ------------- |
| source          | 293 → 1,051 MB             | 88 → 244 MB           | 3,848 → 9,449   | +108 MB       |
| binary          | 333 → 979 MB               | 85 → 237 MB           | 3,903 → 9,031   | +108 MB       |
| source, prod    | 230 → 813 MB               | 82 → 214 MB           | 10 → 8          | none          |

Memory grows without bound in all three, and the growth has three holders:

1. **React runs its development build, from source and in the binary.**
   Fixed by CHD-344, below. Nothing set `NODE_ENV`, so `react-reconciler`
   loaded `react-reconciler.development.js`, which records a `performance.measure`
   for every component it renders (React 19's Performance Tracks), and
   nothing ever clears them: `globalThis.performance` itself held 12 MB a
   minute in and 90 MB after three, 108 MB more in the eight-minute runs. On
   top of that, a captured stack on every fiber (`FiberNode._debugStack`,
   the `Error` objects) and a `warnAboutAccessingKey` closure on every
   element's props. The production run has none of the three.
2. **Every transcript entry stays mounted.** With the production build, the
   heap still grows about 130 MB in seven minutes, by as much as the
   transcript in front: 71,000 more `FiberNode`s, and OpenTUI's
   `TextNodeRenderable`, `SpanRenderable`, `BoxRenderable`, `RGBA` and their
   buffers, held from the root fiber down through the transcript's box
   (its child 408 in the last snapshot). This is CHD-327's virtualisation:
   since then only the tail of the transcript in front is mounted, more
   only while the person scrolls back to it (docs/decisions.md, "CHD-327
   D").
3. **chord's MCP server keeps a session a client left without ending it.**
   Each `initialize` gets an `McpServer` with every tool and its zod schemas,
   kept in the server's `opened` map until the client sends DELETE or the
   caller's session closes. The fake opens a client a turn and closes it
   without DELETE, and 368 copies of the `monitor` tool's description, each
   under its `registeredTool`, piled up in seven minutes, with 18,000 zod
   objects. Held only from the handler `Bun.serve` keeps natively, they show
   no path from a root. A real agent that keeps one MCP connection a session
   leaks little this way; one that reconnects leaks a server each time.
   CHD-346 measured live Claude and Codex on 2026-10-16, from source in the
   production build at 120×40, about five minutes each: 18 `SIGUSR2`
   snapshots read with memlab's `getFullHeapFromFile`. Both kept the main
   MCP session id through seven turns calling `list_agents`/`list_sessions`,
   an Esc interruption and the turn after it. Every snapshot held one
   `McpServer` and one `monitor` description reference per live token, never
   two. An `open_agent` child and a second tab each added one; a finished
   `spawn_task` left none. Killing the second tab's adapter removed its
   server by token revocation. chord does not restart an exited adapter;
   `/clear` made a new token and session. Each run ended with three servers
   for three tokens: main, child and replacement.

   One server with its tools retained about 109–111 KB alone, or 38–105 KB
   each with several, where zod schemas and code are shared. Total
   `heapUsed` rose from 34 to 38 MB for Claude and 33 to 37 MB for Codex;
   that growth is not attributed to MCP. Each agent used at least four
   distinct MCP sessions plus the task's; none outlived its token. Exact
   initialize/DELETE counts were not measured, so whether the adapters
   send DELETE is unknown: every observed session end was by revocation.
   A dropped MCP stream was not provoked (Esc cancelled before an in-flight
   call), nor an adapter restart in place. The fake's pile-up did not appear
   in these cases. Open, not fixed: a reconnecting client can still leave
   a server until its token is revoked. The policy for letting it go is
   the owner's.

## After CHD-344 (2026-10-12)

`bun run chord`, `bun run chord:fake` and `bun run dev compile` now define
`process.env.NODE_ENV` as `"production"` (Bun's `--define`), so React loads
its production build from source and in the binary. Two 8-minute runs side
by side, as above:

| run    | footprint at 1 min → 8 min | JSC heap at 1 → 8 min | `Error` objects | `performance` |
| ------ | -------------------------- | --------------------- | --------------- | ------------- |
| source | 241 → 765 MB               | 82 → 219 MB           | 10 → 11         | none          |
| binary | 202 → 735 MB               | 75 → 212 MB           | 10 → 11         | none          |

Neither `performance` nor `_debugStack` appears among what grew. What
still grows is the second and third holder: `FiberNode`s and OpenTUI's
renderables for every entry mounted, and the `monitor` tool's description
once per MCP session left open.

The define is a substitution in the code Bun parses, not a variable set:
chord's environment, and the agents and commands it starts, never see
`NODE_ENV`. `bun test` does not define it, so the tests keep React's
development build and its warnings, and plain `bun src/main.tsx` runs the
development build too, for React DevTools (`DEV=true`) or a look at what
the development build checks.
