# CTUI-15 brief: the session and transcript reducer for M1

Lead: architects 3. Worktree: `../chorded-tui-worktrees/CTUI-15`, branch
`CTUI-15`. Every member reads, writes and commits there, never in the main
checkout and never on `main`.

## The problem

The port can start an agent and open a session (CTUI-12 client, CTUI-13
startup window) but cannot talk to it. M1 needs, as plain Dart with no
widget in it, under `example/chord/lib/session/`:

- a session object that sends prompts, cancels, and hears the agent's
  updates through CTUI-12's single ingress (`onTraffic`);
- the early-update buffer and exact-session-id routing CTUI-12 assigned
  here (`docs/design/CTUI-12.md`, "One ingress for updates": the
  `session/new` answer first, then buffered updates, held until the first
  subscriber);
- a pure transcript reducer that folds the prompt, `agent_message_chunk`,
  `agent_thought_chunk`, `tool_call`, `tool_call_update`, `plan`, permission
  requests and answers, a cancel, the turn's result and the agent going
  away into transcript state;
- the turn and the prompt queue (one turn at a time; prompts typed while a
  turn runs wait), cancel (Esc), and the agent exiting mid-turn.

The original is the specification: `../chord/src/session/session.ts`
(`Session`, `openSession`), `conversation.ts` (`Conversation`: turns,
queue, delivery), `transcript/` (one module per kind; `reducer.ts`,
`types.ts`, `turn.ts`, `messages.ts`, `tools.ts`, `plans.ts`,
`permissions.ts`, `entries.ts`, `subagents.ts`), `permissions.ts`,
`enrich.ts`, `enrichers.ts`, and `src/ui/app/state.ts` where the window
calls the reducer. Its tests: `tests/session/transcript/*`,
`tests/session/session_test.ts`, `session_updates_test.ts`,
`conversation_test.ts`, `conversation_entries_test.ts`, `permissions_test.ts`,
`enrich_test.ts`, `enrichers_test.ts`. Read `src/session/AGENTS.md` too.

The original's cut is far larger than M1: `Session` has about forty
members (record/replay, auth, models, modes, config, servers, costs),
`types.ts` about thirty entry kinds, `conversation.ts` is 4 300 lines, and
there are fourteen enrichers. M1 needs a small, honest subset, with the
seams to the rest named so later milestones add to it rather than rewrite
it.

## Who stands on it

- CTUI-16 transcript: replies (markdown), thinking, tool calls, edits as
  diffs, in the scrolling list.
- CTUI-17 prompt: multiline, history, queue, interrupt.
- CTUI-18 permission: inline choice, numbers and arrows, Esc rejects.
- CTUI-19 plan, status line, spinner with elapsed time, errors.

What an author of those screens writes: read an immutable transcript state
(entries, the running turn, the queue, the plan, the waiting permission),
listen for changes, and dispatch intents (`send(text)`, `cancel()`,
`answer(permission, option|reject)`). Nothing in the screens touches ACP.

## Constraints

- AGENTS.md binds: logic where a test reaches it; state and reducers plain
  Dart; the port follows the original (keys, states, wording, order); any
  difference from the original is the owner's, not ours.
- CTUI-12's contract is fixed: one ingress, extension-type views over the
  wire, `onTraffic` must not throw, per-update catch in the reducer,
  `cancel()` means queued, `prompt()` settles only with the agent's answer,
  no client capabilities declared in M1 (so `_meta.terminal_output_delta`
  is not declared and terminal output arrives as a text block once).
- Tests never reach a real agent: pure reducer tests carried over from the
  original's, the session through in-memory processes, scripted children,
  and the original's fake agent through CTUI-13's harness
  (`example/chord/test/fixtures/fake.dart`, `fake_harness.dart`).
- A maintained package before our own code for anything not about the
  terminal (immutable collections, for instance); say what was tried.
- The design must be cut into units ship can build one at a time, each with
  tests that fail without it.

## Non-goals (name the seam, build nothing)

Records and resume, `session/load`, fork, children, teams, monitors,
subagents (Claude's `_meta` stamping), costs and usage, models, modes and
config options, steering, bash mode, notices, compaction, elicitation
forms, id-addressed plans (`plan_update`/`plan_removed`), live terminal
output, `-p` and `chord acp`, chord's own MCP calls (`transcript/chord.ts`).

## Open questions, and who answers

1. **The M1 session surface; where a turn and the queue live.** Which of
   `Session`'s members M1 needs; whether the port keeps the original's
   split (`Session` = connection to one ACP session, `Conversation` =
   turns, queue, delivery) or merges them for M1; where the early buffer
   and routing (`SessionInbox`) sit relative to `subagents.ts`'s
   `routed`/`sessionTree`. *framework* (shape), *runtime* (lifecycle).
2. **The Entry and action subset.** Which kinds of `types.ts` M1 draws
   (proposed: user, assistant, thought, tool, permission, cancelled,
   error/warning, plan as state) and which `TranscriptAction`s; how
   `turn.ts`'s and `permissions.ts`'s calls into `subagents.ts` become
   stubs; what happens to terminal output an adapter sends under `_meta`
   while the capability is undeclared. *framework* (types),
   *interface* (what each screen needs from each kind), *runtime* (the
   `_meta` evidence from the fake and the adapters).
3. **Enrichers.** Which of the fourteen in `enrichers.ts` M1's screens
   need (candidates: `toolCallFacts` for a title/kind a later update drops,
   `rawOutputContent`), whether the enricher chain and its `Wire` are built
   in M1 or the reducer folds raw updates, and the seam for the rest.
   *interface* (what is visible without each), *runtime* (where the chain
   sits on the ingress), *framework* (its type).
4. **The Dart shape of transcript state.** Sealed classes with final
   fields, extension-type views (as CTUI-12 chose for the wire), or
   records; equality, copying, immutable lists, how a screen notices a
   change (a `ValueListenable`, a stream, a version counter) and how the
   list knows which entries changed (CTUI-1's virtualised list re-measures
   entries). *framework*.
5. **Turns, cancel, exit and ordering.** One turn at a time and the queue's
   rules as the original's; Esc while a permission is waiting; a cancel the
   agent ignores; the agent exiting mid-turn or between turns; an update
   after the prompt answered; `onTraffic` ordering versus the prompt's
   future; a throwing update. *runtime*.
6. **What each M1 screen reads.** For CTUI-16 to 19: the fields, the
   states (idle, running with elapsed time, waiting on a permission,
   interrupting, cancelled, failed, agent gone), and the intents each
   dispatches, with the original's wording. *interface*.
7. **The test plan.** Which original tests carry over file by file, which
   fake scenarios (CTUI-12 lists them: `text`, `thought`, `todos`, `tools`,
   `calls`, `edit`, `permission`, `twins`, `slow` then cancel,
   `ignorescancel`, `error`, `turnfailed`, `crash`, `late`, `flood`, …)
   cover what, and how the units are cut. *runtime*, with all three
   naming their units.

## Drafts

- `framework.md`: the state's Dart shape, the reducer's structure (one
  module per kind, as the original), the session/conversation split, the
  file layout under `example/chord/lib/session/` with its tests, the
  packages tried.
- `interface.md`: what CTUI-16..19 read and dispatch, per entry kind and
  per state, with the original's words; what is lost without each enricher.
- `runtime.md`: turn and queue lifecycle, cancel, exit, ordering, the
  inbox, enricher placement on the ingress, the `_meta` terminal output
  finding, the test plan against the fake, and the cut into units.

Each draft ends with its answers to the questions above it owns, and any
question it believes is the owner's, with options and a recommendation.
