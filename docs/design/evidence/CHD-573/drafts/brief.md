# CHD-573 brief: `chord acp`

## The problem

chord today is an ACP client with a window, plus `chord -p`, a one-turn script
mode. Nothing but chord's own window can drive the agents and teams chord runs.
`chord acp` runs chord with no interface as an ACP agent on stdin and stdout:
any ACP client starts it as a child process and drives, through it, what chord
runs. Toward those agents chord stays the ACP client it already is.

Two ACP connections meet in one process: upstream chord is the agent, downstream
chord is the client. Most of the design is what crosses between them, and what
of chord's own (children, teams, monitors, records, chord's MCP server) has an
ACP method at all.

## What a person sees and presses

Almost nothing: `chord acp` draws nothing and takes no keys. A client starts it.
What a person sees if they run it by hand in a terminal is an open question for
`interface`.

## Constraints

- AGENTS.md binds, the one rule above all. `@agentclientprotocol/sdk` 2.2.0 is
  the library; try its agent side (`agent({ name })`) under Bun and in a
  compiled binary before proposing any protocol helper. A gap goes to the owner,
  through the lead. No workaround on a trial alone.
- Transport for this milestone is stdio only.
- stdout carries only ACP. Whatever chord writes today outside the window must
  not reach it.
- `src/session/` and `src/acp/` import nothing from `src/ui/`. What `chord acp`
  needs from `src/ui/` must move down, not be imported.
- Session records are a stored format; older records must still read back. The
  window's sessions are recorded and `-p`'s are not; where `chord acp`'s stand
  is part of question 4.
- Every session's traffic runs through the enricher chain. A child's permission
  request goes to the person today, never to the parent agent.
- Tests reach no real model, agent or provider: fake ACP stdio fixtures only.
- Live agents stay out of this design's checks.

## Non-goals

- HTTP, WebSocket or any transport but stdio.
- Code. This is planning: the tasks waiting on CHD-573 implement the result.
- Tabs or several main sessions per process as a window feature.
- Anything about products or uses outside chord. No draft names any; the goal is
  only that any ACP client can drive chord. Argue from the protocol and the code.

## The owner's questions

These six are the owner's and no draft settles them. Each architect writes, for
the ones assigned below: what the code and SDK establish, with `file:line`, the
options, and a recommendation with its reason. The lead sends them to main; the
answers come back before the design is merged.

1. Which agent and which team `chord acp` runs, and who chooses them.
2. Who answers a permission or an elicitation, and what happens when the client
   cannot.
3. Whose filesystem and terminal capabilities the agent sees: the client's,
   chord's or both.
4. What session list, load and resume mean here, and how they relate to chord's
   saved records.
5. Which ACP protocol version is offered: the SDK ships v1 and a draft v2.
6. How extensions are named, versioned and advertised, and which ones this
   milestone includes.

Any other ACP gap or proposed extension is treated the same way: evidence,
options, recommendation, no decision.

## What each architect answers

### protocol, `drafts/protocol.md`

- The method table: every ACP agent-side method and notification in v1 stable
  and unstable, and in v2 as far as it differs. For each: answered or not, with
  what, and what crosses to the downstream agent.
- How downstream traffic maps upstream: updates, tool calls, plans, modes and
  config options, commands, usage, subagent updates, elicitation, steering,
  session ids (chord's or the agent's). What the enricher chain's `_meta` means
  to a client that did not ask for it.
- `initialize` both ways: what chord advertises when it depends on an agent not
  started yet, and what it does with the client's capabilities.
- `mcpServers` a client passes in `session/new`, beside chord's and the
  settings'. What `src/session/servers.ts` does with them.
- Which chord features have no ACP method (children, teams, monitors, chord's
  slash commands, `get_budgets`, resume across records) and so need an extension,
  or stay reachable only as the agent's own MCP tools. List each with the reason.
- Questions 1 to 6: evidence, options, recommendation.

### interface, `drafts/interface.md`

Small on purpose, since `chord acp` draws nothing. Answer only:

- What the extraction from the UI layer means for the interface: what leaves
  `src/ui/`, what the window then calls, and what stays and why.
- What a person sees if they run `chord acp` by hand in a terminal, including
  stdin being a terminal, at 120x40 and 80x24, and how they leave it.

### runtime, `drafts/runtime.md`

- **The library gate, done first and reported to the lead at once:** a minimal
  agent on the SDK's `agent({ name })` under Bun and from `bun build --compile`,
  driven by a scripted client over real pipes. Cover `initialize`, `session/new`,
  `session/prompt` with streamed updates, a `session/request_permission` round
  trip, `session/cancel`, stdin EOF and SIGTERM, a pending request at shutdown,
  and both v1 and v2 negotiation. Also try chord's own binary's way of starting
  (`src/main.tsx`) to see if OpenTUI's load or anything else writes to stdout.
  Trial files live in a new directory outside the repository, written from there
  without running build tools from a downloaded path; put the scripts and their
  output under `docs/design/evidence/CHD-573/sdk-trial/`, which you own, with no
  private paths. Touch nothing in `src/`.
- Who owns sessions, teams, pending requests and lifecycle today, across
  `src/session/`, `src/acp/`, `src/server/`, `src/headless.ts`,
  `src/session/oneshot.ts`, `src/main.tsx` and `src/ui/app/`. What has to leave
  the UI layer, in what order, and how large that is. Say plainly if it is too
  large for one milestone and what a smaller first package would be.
- Processes and concurrency: one or many upstream sessions per process, and what
  a turn, a child, a team and a monitor do when several run at once.
- Failure and shutdown: upstream EOF and signals, the downstream agent dying or
  failing to start or sign in, a client that never answers, pending requests,
  the process tree left behind, stdout backpressure, a second `chord acp` in one
  directory.
- The test plan through fake ACP fixtures, on both sides, and what stays
  unmeasured.
- Evidence toward questions 1, 2 and 4 from the runtime's side.

## How to work

- Read AGENTS.md, `src/AGENTS.md`, `src/session/AGENTS.md`, `docs/FEATURES.md`,
  and in `docs/decisions.md` the entries "chord's own ACP layer", "The transport
  on the SDK" and "`chord -p` runs one turn", then what your part touches.
- Write only your own file. Do not commit: the lead commits the drafts by path.
  Other runs share this working tree, so leave the git index and branch alone.
- Cite `file:line` for what the code establishes; mark what you did not verify.
- Be finite: one concrete package, not a survey. Say what you would cut.
- English, no private paths.
- When your draft is written, tell the lead by `send_message`, alone, in five
  lines or fewer.
