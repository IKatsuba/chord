# CHD-626 runtime draft: model and parameters together, at run time

The runtime architect's draft for CHD-626. It answers the brief's runtime
items: the order of ACP calls when a model and its parameters change
together, concurrency with a running turn and with option sets the agent
resends, failure and partial success, the module layout and its tests, and
the headless `--effort` path. Choices marked **(owner)** are the owner's;
the rest are recommendations for the lead to merge or overrule.

How effort, fast and context are recognised (Q3) is protocol's. This draft
needs only that some pure function maps an option set to the roles it
recognises (`effort`, and `fast`/`context` if the owner allows a rule) and
leaves the rest as plain options; it calls that function `rolesOf`.

## What the code does today

Read at `016d96388`:

- `Session.setModel` (`src/session/session.ts:775`) sends
  `session/set_config_option` on the `model` option, or the older
  `session/set_model`; `setOption` and `setEffort` (`:812`, `:836`) send
  `session/set_config_option`. Each replaces the session's config state with
  the answer's `configOptions` (`withOptions`), whenever the answer comes.
- `Conversation` (`src/session/conversation.ts:2776`, `:2820`) keeps **two
  separate chains**, `#modelChanges` and `#optionChanges`. A model change and
  an effort change asked one right after the other run concurrently: the
  effort's `set_config_option` can reach the agent before the model's, or
  be checked against the old model's option set. Nothing in the window asks
  both together today, so this has not bitten; the new picker would.
- Starting values already go in the right order: `#applyStarting`
  (`conversation.ts:3091`) asks model, then effort, then mode, one after
  another through `askStarting` (`src/session/starting.ts:71`), and checks
  the effort against what the agent offers **after** the model was set
  (`listedOnly`, `offered()` read at ask time). A refused effort is a note,
  never a failed start.
- No gate on a running turn: `/model` and `/config` send at once, mid-turn
  or not.
- `-p` asks effort, then mode (`src/session/oneshot.ts:136`), and never a
  model: `docs/guide.md` says "`--model` is for the window". So
  `chord -p --effort high` is checked against the agent's default model.
- The fake agent (`tests/fixtures/fake_agent/sessions.ts:129`) offers the
  same `effort` (`low`, `medium`, `high`, category `thought_level`) on both
  its models, answers `set_config_option` with the whole set, never resends
  on a model change, and has `--refuse-config`, `--config-delay`,
  `--no-config` and `--hang config`.

What agents do on a model change (from `docs/agent-capabilities.md`):
Claude's adapter offers `effort`, `fast`, `ultracode` per model [cl10];
Codex's `reasoning_effort` holds the model's own efforts and `fast-mode`
[cx11]; fx sends no `config_option_update` and answers with the new set
only [fx9]; cursor-cloud (ours) answers with the new model's parameters, and
the values one parameter may take depend on the others' current values
(`packages/cursor-cloud-acp/src/config.ts:89`, variants). So: **a model's
parameters are known only after the agent is on it, and one parameter's set
can change which values another may take.**

## 1. The order of calls when model and parameters change together

A *choice* is what the person confirms in one Enter: a model, optionally
with an effort (and any other parameter the design lets them change in
place). It runs as steps, each one ACP call, strictly one after another:

1. **Model**, if it differs from the current one: `set_config_option` on
   the model option (or `session/set_model`). Wait for the answer.
2. **Re-read** the option set: the answer's `configOptions`, or for an
   agent whose answer is empty, the set as updated by the
   `config_option_update` that came, or the enricher filled
   (`src/session/enrichers.ts:209`).
3. **Each parameter**, in the order the agent lists its options: find the
   option for its role in the *current* set (effort by `thought_level`;
   others by id only when the model did not change, see below). If the
   value is listed there, send `set_config_option`; wait; re-read. If the
   option or the value is not listed, skip it with a reason. Do not send a
   value the current set does not list: the agent would refuse it anyway,
   and for cursor-cloud an earlier parameter's set may have narrowed it.
4. One note for the whole choice (see section 3).

A parameter is carried across a model change **by role, never by id**: an
effort chosen for "the highlighted model" is looked up after the switch in
the new model's `thought_level` option by its value id. Claude's and
Codex's efforts share ids across models (`low`, `medium`, `high`…), so
this lands; where the new model lacks the value it is skipped with "Sonnet
offers low, medium, high". Uncategorised options (cursor-cloud's
parameters, fx's `fast`) are carried only if protocol's `rolesOf` gives
them a role; otherwise only the model is set and the parameter is left
as the agent chose. This is `askStarting`'s rule (listed only, read at ask
time), reused rather than written again.

### How a highlighted model's effort can be shown before it is chosen

ACP has no call to read or set another model's options: chord learns them
only by switching. Three ways, the first recommended:

- **A. Remember what was seen.** A pure per-conversation memory of the last
  option set seen on each model id (`seen.ts`, below). The picker shows the
  highlighted model's remembered effort and lets ←/→ move within its
  remembered values; Enter runs the choice above, and the value is
  re-checked against what the agent then sends. A model never visited in
  this conversation shows no parameters, or "after choosing" (interface's
  wording). Cost: nothing on the wire; may be stale (rechecked, so harmless).
- **B. Choose, then ask (Codex's way).** Enter sets the model; when the new
  set has an effort, the effort list opens. Two Enters, no memory, never
  stale. Fits A's "never visited" case as its fallback.
- **C. Probe.** Switch to each model, or open a throwaway `session/new`,
  to read its options. Rejected: it moves the live session's model (Claude
  and cursor-cloud may start work or bill on it), costs a session per
  model, and a hung probe blocks the picker.

A combined with B's fallback is the recommendation; which one the picker
shows is interface's, A's memory surviving resume is **(owner)** (it would
be a new field in the session record; recommended: no, memory lives in
the process).

## 2. Concurrency

### One chain per conversation

Replace `#modelChanges` and `#optionChanges` with one `#configChanges`
chain in `Conversation`. Every model, mode, effort, fast, `/config` and
picker choice joins it; a choice's steps run inside one link, so nothing
else lands between the model and its effort. The mode joins too: a mode is
per model for Claude (`auto` [cl9]), and today a mode set can overtake a
model set the same way.

- Two Enters in a row (person changes their mind): both run, in order; the
  last is what stays. No coalescing: dropping a queued choice is a policy
  chord would make up, and the queue is at most a few calls.
- `/effort`'s and the picker's ←/→ send nothing; only Enter sends. A fast
  toggle sends one call per press; its target value is fixed at the press,
  from the last value **asked for** (pending or reported), so two quick
  presses mean on, then off, as the person saw them.

### With a running turn

Keep today's behaviour: a choice is sent at once, mid-turn or not. ACP does
not forbid it; when the change takes effect (this turn's next model call,
or the next turn) is the agent's. chord shows what the agent reports, not
what was asked. Holding choices until the turn ends would be a new policy
**(owner)**; recommended: no, as `/model` and `/config` work mid-turn today.
A steered prompt is not affected: steering does not touch config.

### Option sets the agent resends

The agent may send `config_option_update` at any time (Claude's adapter on
a model change, cursor-cloud after a run picks a model on "Cursor's
default"), and the answer to chord's call may arrive after such an update.
Today `withOptions(state, answered)` takes the answer whenever it lands, so
an answer that arrives after a newer update rolls the state back.

Rule, in `session.ts`: each `config_option_update` bumps a counter; a
`set_config_option` answer is applied only if no update arrived since its
request went out. An update that came first is at least as new as the
answer (the agent sent it after acting on the request or for a reason of
its own); a set that agents send both ways ends the same. With one chain
there is one request in flight, so this is the only interleaving left.

The steps of a choice re-read the set before each call (section 1), so a
resend in the middle (a new model's options replacing the old) is what the
next step checks against. An open picker re-reads too: `#report` already
emits `options` and `model` on every change; the picker's slice follows
the new set and keeps the highlight on the same model id (interface's
state).

### A hung or slow agent

`set_config_option` has no timeout today, and `--hang config` shows the
chain then holds every later change. cursor-cloud's answers go over the
network. Recommendation: no request timeout in this task; the picker closes
on Enter, and the status line shows the value as "setting" until the
answer (interface's slot). A hung agent is left to `/clear`, close and
quit, which kill its process group as today; nothing here adds a wait to
close. A timeout that drops a step and moves on would leave chord not
knowing which value holds, so it needs the late-answer rule above and is
**(owner)** if wanted.

### Several sessions

Each conversation has its own chain and its own `seen` memory. Children and
team members started with `effort` through chord's MCP tools keep
`askStarting` as now. `chord acp` relays its client's
`set_config_option` as is and gets none of this: the composite choice is
the window's.

## 3. Failure and partial success

Steps run to the end; a refused step does not undo earlier ones.

| Case | Outcome |
| --- | --- |
| Model refused | Stop; nothing else sent. `Could not switch to <model>: <reason>` as today. |
| Model set, effort refused (`--refuse-config`) | Model stays. One note: `Switched to <model>; could not set effort to <value>: <reason>. On <reported>.` |
| Model set, effort not offered by the new model | Model stays; note `…; <model> offers no effort` or `…offers low, medium`. Not red: nothing failed. |
| Model set, a later parameter refused after an earlier one set | Earlier ones stay; note names each set and each refused. |
| Effort alone (`/effort`, ←/→ on the current model) refused | `Could not set effort to <value>: <reason>`, as `/config` notes today. |
| Agent answers with an empty set (Codex's mode) | Read back through the enrichers as today; the step counts as done. |
| Agent exits mid-choice | The chain's pending call rejects with the exit; the note says what was set before; the conversation's exit handling is unchanged. |
| Session replaced (`/clear`, resume) mid-choice | `#current(session)` is false: remaining steps are not sent, nothing is noted on the new session. |

Undo after a partial failure (set the model back) is **(owner)**; it is
another call that may fail too, and the person asked for the model.
Recommended: keep the model, say so.

## 4. Modules and tests

`tests/` mirrors `src/`. Pure where the logic is.

| Module | Pure | What | Tests |
| --- | --- | --- | --- |
| `src/session/choice.ts` (new) | yes | `nextStep(choice, options, done)`: from a choice and the current option set, the next `set_config_option` (configId, typed value), a skip with its reason, or done; and `choiceNote(steps)`, the one-line outcome. | `tests/session/choice_test.ts`: option-set fixtures shaped as Claude's, Codex's, fx's (answer-only, `fast` under `model`) and cursor-cloud's (dependent variants, Auto with none); effort carried by value across models; value missing after switch; boolean values. |
| `src/session/seen.ts` (new) | yes | Per-model memory of the last option set seen, keyed by model id; a reading is stored when the session reports a set while on that model. | `tests/session/seen_test.ts`. |
| protocol's recognition (`rolesOf`) | yes | Role of each option; protocol's draft. | Its own test. |
| `src/session/session.ts` | no | Late-answer rule; `setOption` takes a typed value (`id` or `boolean`) for boolean options. | `tests/session/session_test.ts` with the fake agent: an update after the request, then the answer; the state keeps the update. |
| `src/session/conversation.ts` | no | One `#configChanges` chain; `choose(choice)` drives `nextStep` and emits the note. | Conversation tests on the fake agent, below. |
| `src/ui/pickers/state.ts` | yes | Interface's slices. | Interface's. |

### Fake agent

New flags in `tests/fixtures/fake_agent/` (documented in its `AGENTS.md`),
no new runtime dependency:

- `--per-model-config` (`CHORD_FAKE_PER_MODEL_CONFIG=1`): `fake-large`
  offers `effort` `low`/`medium`/`high`/`max` and a `fast` option;
  `fake-small` offers `low`/`medium` only. A model set answers with the new
  model's set; the effort keeps its value where the new model lists it,
  else falls to `medium`.
- `--resend-on-model` (`CHORD_FAKE_RESEND_ON_MODEL=1`): also sends the new
  set as `config_option_update` before answering, as Claude's adapter does;
  with `--config-delay` it plays the late answer.
- `--refuse-config` narrowed or widened to name what it refuses, e.g.
  `--refuse-config effort` (keeps today's bare form meaning effort).
- `--hang config-effort`: hangs only effort sets, so a model set answers and
  the chain then waits, for the "setting" state and close-while-pending.
- A play `resendsconfig` that sends a `config_option_update` mid-turn,
  for the picker open during a turn.

For cursor-cloud's dependent parameters and its Auto, use its own offline
fixture (`packages/cursor-cloud-acp/tests/fixtures/main.ts`) in a
conversation test, rather than teaching the fake agent Cursor's variants.

### Window tests

Through `tests/ui/harness.tsx`: ←/→ on a highlighted model then Enter sends
model then effort in that order (the fake agent records the order it got
the calls; the test reads it from the transcript or a gate file); a model
never visited shows interface's fallback; the partial-success note's text;
a resend while the picker is open keeps the highlight; the keys in
`tests/ui/shortcuts/keys_test.tsx` for whatever interface adds.

## 5. Headless `--effort`, `--fast` and settings

`-p` keeps `--effort` as is: asked after the session opens, checked against
what the agent offers then, a refusal on stderr and the turn going on. It
asks no model, so it gains nothing from the composite choice and needs no
change. One observation for the lead: a settings `model` + `effort` pair
written for the window is checked under `-p` against the agent's default
model and may be refused there; whether `-p` should take `--model` is
outside this task **(owner)**.

`--fast` (and `agents.<name>.fast` in settings) is **(owner)** and depends
on Q3: it needs a rule that recognises fast without guessing. If the owner
gives one, it is one more `StartingAsk` after effort, `listedOnly`, a
refusal a note, never a failed start, in the window, `-p` and the MCP
tools alike. Recommended: none in this task; Claude Code and Codex take
fast as a per-session toggle, and chord can add the flag once fast is
recognisable. A settings default effort per model is a non-goal of the
brief and is not needed by anything above.

## Open questions

1. **(owner)** Keep the model when its parameter is refused, or set it back?
   Recommended: keep, and say so.
2. **(owner)** Hold a choice made during a turn until the turn ends?
   Recommended: no, as today.
3. **(owner)** A timeout on `set_config_option`? Recommended: none now.
4. **(owner)** Does the per-model memory of seen parameters survive resume
   (a record field)? Recommended: no.
5. **(owner)** `--fast` and a `fast` setting, once Q3 allows recognising
   fast. Recommended: not in this task.
6. **(owner)** Should `-p` take `--model` (then the composite order applies
   there too)? Outside this task.
7. For interface: A (remembered parameters) or B (choose, then ask) as the
   picker's behaviour for a model with no remembered set.
