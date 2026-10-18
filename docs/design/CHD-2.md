# CHD-2: Claude's background agents in the background view

The owner (Q26, 2026-10-18): with claude-agent-acp 0.93.0, Claude's
background agents become items in CHD-424's background view, and `x` stops
one through ACP's per-subagent `session/cancel` on the subagent's session
id, with no AIR. Background Bash (asyncTasks) stays out until the adapters
offer it without AIR (claude-agent-acp #1285, codex-acp #645).

This page adds one kind, `agent`, to [CHD-424](CHD-424.md). Everything
CHD-424 settles holds: the summary line, the view, its columns, its keys,
its order, clearing on the next prompt. Only what an `agent` item adds is
here. Its endings use CHD-432's U1 words for the same ends
([CHD-432](CHD-432.md), "U1: how a subagent's end reads").

## Today

Captured on the fake agent (`evidence/CHD-2/today/`): main ran `monitors`
then `subagent`. The subagents show only as their blocks in the transcript;
the summary line counts the two monitors and nothing else
(`standing-120x40.txt`), and the view lists the monitors
(`view-120x40.txt`, `view-80x24.txt`).

## Which subagents are items — open

**Open, with the owner (posted on CHD-2 by the lead).** The wire has no
background flag: claude 0.93 announces every running child with
`capabilities: {cancel: {}}`, foreground ones too, and its Agent tool now
runs agents in the background unless the model sets `run_in_background:
false`. This page is drawn on option (a), which the team recommends:

- **(a) Every subagent announced with `capabilities.cancel` is an `agent`
  item**, whichever agent sent it. A replayed subagent, which gets no
  capabilities, and codex's draft `subagent_spawned`, which has none, are
  not items. **Why:** it reads only the protocol, guesses at no tool's
  input, and is the same rule as `task`: every `spawn_task` task is an item
  though its `Agent(…)` block is in the transcript too.
- (b) Only a subagent whose launching Agent call has `rawInput`
  `run_in_background` not `false`, linked by `session_message.messageId`,
  which is the call's id. Claude-only, and reads one tool's input.
- (c) Only a subagent still running when its parent's turn ends. Wire-only,
  but an agent is not an item while the turn runs.

A subagent of a subagent is an item of its own when it is announced with
`cancel`. Its owner is the tab's agent whose session it came under (`main`,
a child or a member), as for every item.

## The item

| Column | `agent` |
| --- | --- |
| name | the subagent's `description` (Claude 0.93's short task), else its `title`, else `agent` |
| kind | `agent` |
| state with time | below |
| owner | as CHD-424 |

Kind words on the summary line: `agent`, `agents`, after `monitor` and
`task` in CHD-424's order (`KINDS` gets `agent`; `bash` stays out with
asyncTasks).

**`enter`** goes to the subagent's block in its owner's transcript, its
`Agent(…)` headline, or its own `├─` row in a group, as CHD-424 says for a
task. A subagent inside another's folded block goes to that block's
headline.

## States

| Wire | Row text | Colour | Summary group |
| --- | --- | --- | --- |
| `running` | `running 41s` (since its first update) | dim | running |
| `requires_action`, chord holds its permission | `● permission 13s` (since it asked) | warning | asking |
| `requires_action`, chord holds its form | `● input 13s` | warning | asking |
| `requires_action`, no request of its reaches the person | `● waiting 13s` | warning | asking |
| `idle`, `end_turn` | `✓ done in 2m 4s` | success | done |
| `idle`, `error` | `✗ failed after 1m 12s` | error | failed |
| `idle`, `cancelled` | `■ stopped after 30s` | dim | stopped |
| `idle`, no stopReason | `■ ended after 1m 2s` | dim | stopped |
| `unknown` | `? untracked 3m 2s` (its time stands at the update) | dim | untracked |
| chord's agent gone | `✗ disconnected after 4m` | error | failed |
| `x` pressed, no `idle` yet | `■ stopping 41s` (its time runs on) | dim | running |

- **`requires_action` with no request on screen** happens when its request
  came with no turn running and chord refused it (CHD-158). `● waiting`
  says it is held up without claiming chord shows what holds it. **Why
  asking, not running:** the summary line's first job is to say something
  waits; the agent does, even if chord cannot show why.
- **`■ ended`** goes with stopped, not done: Claude saw neither an end nor a
  cancel (a worker restart, or the stream ended), and green would claim one.
  The row's word, not the group's, tells it apart from a stop.
- **`? untracked`** is its own group, after failed and before running:
  `? 1 agent untracked`, dim. **Why its own:** it is neither running nor
  ended; counting it with either would say what Claude did not. A later
  `running`, `requires_action` or `idle` takes the row back to that state
  in place. On the next prompt it is cleared as an ended item; if it comes
  back after that, it comes back as an item in its start order.
- **`■ stopping`** stays until the subagent's `idle` comes. It counts as
  running on the summary line, as it still is.

The summary line, with an agent asking and one untracked, at 120 columns:

```
    background  ● 1 agent asking · ✗ 1 monitor failed · ? 1 agent untracked · 1 monitor and 2 agents running
```

## `x`

`x` on a running or asking `agent` row sends `session/cancel` with the
subagent's session id, at once, with no confirmation (Q19).

- **While the stop is pending**, the row reads `■ stopping 41s`, dim, and
  the `❯` stays on it. A second `x` does nothing. Its open permission box or
  form, if it had one, stays until Claude withdraws it, which the stop does.
- **When `idle` with `cancelled` comes**, the row reads
  `■ stopped after 43s`. The transcript says so in the subagent's own block,
  which ends `Cancelled` (U1); no line of its own is added, as the block is
  the agent's record.
- **When the stop ends otherwise**: an `idle` with `end_turn` or `error`
  that crosses the stop reads `✓ done in …` or `✗ failed after …`, as it
  came. Claude's word wins over the key's.
- **When the `session/cancel` is refused** (an error answer), the row goes
  back to its state, and the hint line says `could not stop: <message>`,
  the message's first line through `theme/Ansi.tsx` and cut to the width,
  until the `❯` moves. **Why the hint line:** it is where CHD-424 already
  says `this agent offers no stop`.
- **`x` on an ended row** does nothing (CHD-424). A row whose subagent lost
  `capabilities.cancel` since (a later update without it) says
  `this agent offers no stop`, as CHD-424 does.
- **Esc in the transcript** does not stop agent items: the parent's cancel
  leaves Claude's background children running (CHD-432's U2), and the
  items stay as they are. `x` in the view is the one stop.

`session/cancel` is a notification: Claude answers nothing, so "refused" is
reached only by an adapter that answers it as a request. For Claude the
pending state ends only with the `idle`.

## The view

At 120×40, one of each state, the `❯` on an agent just stopped:

```
 Background · 7 in this tab

    dev server errors      monitor                    running 4m 2s · 1 event          main
    Explore the parser     agent                      running 41s                      main
    Review the diff        agent                      ● permission 13s                 main
  ❯ Run the whole test     agent                      ■ stopping 1m 3s                 main
    suite
    Read the transport     agent                      ? untracked 3m 2s                parser
    tests
    Fix the tokenizer      task · fake · Fake Small   ✓ reported after 1m 12s          main
    Find the session       agent                      ✗ failed after 22s               main
    layer



























 ↑ ↓ to move · enter to go to its call · x to stop · esc to close
```

At 80×24, the same, CHD-424's narrow rules: names wrap in their column, a
task's model and runtime give way first, state and owner never drop:

```
 Background · 7 in this tab

    dev server errors   monitor  running 4m 2s · 1 event      main
    Explore the parser  agent    running 41s                  main
    Review the diff     agent    ● permission 13s             main
  ❯ Run the whole test  agent    ■ stopping 1m 3s             main
      suite
    Read the transport  agent    ? untracked 3m 2s            parser
      tests
    Fix the tokenizer   task     ✓ reported after 1m 12s      main
    Find the session    agent    ✗ failed after 22s           main
      layer











 ↑ ↓ to move · enter to go to its call · x to stop · esc to close
```

A refused stop, at 80×24, the hint line in place of the keys:

```
  ❯ Run the whole test  agent    running 1m 4s                main
      suite
…
 could not stop: Session not found
```

The standing screen at 80×24, the summary wrapped between groups:

```
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts             Fake Large with a 1M context window · 1% used
    background  ● 1 agent asking · ✗ 1 agent failed · ? 1 agent untracked ·
                1 monitor and 2 agents running · ✓ 1 task done
```

## Colour roles

No new role, as CHD-424: warning for asking, error for failed and
disconnected, success for done, dim for running, stopping, stopped, ended
and untracked, the permission role for the `❯`.

## Keys

None new. `x`, `enter`, `↑ ↓`, `esc` are CHD-424's, and the shortcuts
panel's `x to close an agent, stop background` already covers an agent
item.

## Not here

- Background Bash (asyncTasks): out until the adapters offer it without
  AIR.
- Claude's own cycle after a background agent ends, and a resumed session's
  background agents: CHD-426.
- A background agent's requests between turns: CHD-158.
