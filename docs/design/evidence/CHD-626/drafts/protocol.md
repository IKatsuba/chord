# CHD-626 — protocol draft: what agents send, how chord reads effort, fast and context

Author: protocol (architects). Scope: the agent's side of the brief's protocol
items. Read against `@agentclientprotocol/sdk` 2.2.0 (chord's pin),
`@agentclientprotocol/claude-agent-acp` 0.106.0 and
`@agentclientprotocol/codex-acp` 2.6.0 (both read from their npm tarballs on
2026-11-13), `packages/cursor-cloud-acp/src/config.ts`, `@cursor/sdk`'s
`options.d.ts`, `docs/agent-capabilities.md` and ACP's page "Session Config
Options" (agentclientprotocol.com/protocol/session-config-options).
"Owner" marks a choice that is the owner's.

## 1. What ACP itself gives

- `SessionConfigOption` is `select` or `boolean`, with `id`, `name`,
  `description`, `category`, `_meta` (SDK 2.2.0,
  `dist/v1/schema/types.gen.d.ts:1928-2063`).
- Reserved categories: `mode`, `model`, `model_config`, `thought_level`;
  `_`-prefixed ones are free. Categories "MUST NOT be required for
  correctness"; unknown ones are handled gracefully.
- ACP's page defines `model_config` as **"Model-related parameter, such as
  context size or speed/quality trade-off"** and says clients SHOULD render
  `model_config` options near the `model` selector. Array order is
  significant: earlier is higher priority, and order breaks ties within a
  category.
- **There is no category, field or `_meta` key in ACP that says "this is
  fast" or "this is the context window".** Both fall under one category,
  `model_config`, beside anything else model-related (Claude's `ultracode` is
  `model_config` too). Effort alone has its own category, `thought_level`.
- Boolean options reach a client only if it declares
  `clientCapabilities.session.configOptions.boolean: {}`; it then sets them
  with `{ configId, type: 'boolean', value: true|false }`
  (`SetSessionConfigOptionRequest`, `types.gen.d.ts:3550`). **chord declares
  no such capability** (`src/acp/connection.ts:228-234`), so Claude and Codex
  send fast as an `on`/`off` select today.
- ACP has no call that reads another model's options without switching to
  it. Claude's adapter serves the unstable "Session options" RFD
  (`session/options`, and `configOptions` on `session/new`/`load`/`resume`
  applied in list order), but `session/options` takes no model: it answers
  what a session would open with. chord's SDK 2.2.0 does not carry the RFD's
  types (the adapter is on SDK 2.6.0).

## 2. What each agent sends

Columns: option id · category · kind · when present · when resent.

### Claude's adapter (claude-agent-acp 0.106.0)

| id | category | kind | present | notes |
| --- | --- | --- | --- | --- |
| `mode` | `mode` | select | always | |
| `model` | `model` | select | when the gateway lists models | values include context lanes as separate models (`opus[1m]`); there is no context parameter |
| `effort` | `thought_level` | select | model `supportsEffort` | values `default` (unless AIR `recommendedValue`), then the model's levels (`low`…`max`) named `Low`, `Xhigh`… (`session-effort.js` `buildEffortConfigOption`) |
| `fast` | `model_config` | select `on`/`off`; boolean if the client declares it | current model supports fast | description carries why fast is unavailable (`session-fast-mode.js`); the SDK may flip it back (rate-limit), resent then |
| `ultracode` | `model_config` | select `on`/`off`; boolean if declared | model supports it and workflows on | (`session-ultracode.js`) |
| `agent` | none | select | custom agents configured | |

Resent: the whole set in each `set_config_option` answer
(`v1/acp-agent.js:5901-5949`, serialised per session); `config_option_update`
on changes from inside (plan exit, fast state, subagents). On a model switch
the effort the person pinned through ACP **carries to the new model if it
supports that level**; otherwise the new model's settings decide
(`effortForModelSwitch`).

### Codex's adapter (codex-acp 2.6.0)

| id | category | kind | present | notes |
| --- | --- | --- | --- | --- |
| `mode` | `mode` | select | always | |
| `collaboration_mode` | `collaboration_mode` (unprefixed, not reserved) | select | always | Default · Plan |
| `model` | `model` | select | models known | base model ids |
| `reasoning_effort` | `thought_level` | select | model has efforts | the model's levels |
| `fast-mode` | `model_config` | select `off`/`on`; boolean if declared | current model has the `fast` speed tier | session-wide flag kept across models; option hidden on a model without it |

Also the legacy `models` field with ids `model[effort]` (one entry per model
and effort) and `session/set_model`. chord prefers the `model` option and
ignores those. Resent: whole set in the answer **and** a
`config_option_update` when anything changed (`updateSessionConfig`). On a
model switch the current effort carries if the new model supports it, else
the model's default (`applyModelChange`).

### cursor-cloud-acp (ours)

| id | category | kind | present |
| --- | --- | --- | --- |
| `mode` | `mode` | select | always |
| `model` | `model` | select | always; `cursor-default` ("Cursor's default") while the agent's model is unset |
| `parameter:<id>` | **none** | select | one per parameter of the chosen model; none on Cursor's default or an unlisted model |

`@cursor/sdk`'s `ModelParameterDefinition` is `{ id, displayName?, values }`:
no kind, no category. The real ids Cursor returns are not recorded
(`config.ts` comment; the test ids `reasoning`/`context` are fixtures).
Resent in the `set_config_option` answer.

### Others (from `docs/agent-capabilities.md`, not re-read here)

| agent | effort | fast / speed | context | catch |
| --- | --- | --- | --- | --- |
| fx | `effort` `thought_level` (`auto` first) | `fast`, `ultrafast`, **category `model`** | — | `provider` is the first `model` select, so chord's `/model` sets the provider and fx's models, fast and ultrafast are unreachable (fx9) |
| cline | none over ACP | — | — | `provider` first of category `model`; auto-approve boolean |
| Cursor CLI (`agent acp`) | `thought_level` only with `_meta.parameterizedModelPicker`, else baked into model ids | other parameters' categories unrecorded | same | cu7 |
| codebuddy | `thought_level` | — | `context_window` (whether id or category not recorded) | cb7 |
| dirac | two `thought_level` selects | `inference_speed` (category unrecorded) | — | booleans sent without the capability |
| openclaw | `thought_level` | `fast_mode` (category unrecorded) | — | oc8 |
| devin | effort, category unknown | "speed" option | — | dv10/11 |
| autohand | `thinking_level` uncategorised | — | — | ah8 |
| kimi, goose, kilo, opencode, glm, grok, droid, pi, qwen, minimax, dimcode | `thought_level` | — | — | |
| gemini, auggie, qoder, zeroclaw, fast-agent | none over ACP | — | — | |

Every agent sends per-model options only for the current model, and resends
the set after a change (in the answer, by update, or both; qwen and Cursor
CLI only in the answer).

## 3. Recognising effort, fast and context (brief Q3)

Effort: **keep `thought_level` only** (decision B12). Two agents send two
`thought_level` selects (dirac). ACP says order breaks ties: take the first,
as `efforts.ts` does; the second stays in `/config`.

Fast and context have no ACP signal of their own. Options:

- **A. Group by category, name nothing.** Every `model_config` option (and
  any boolean) is a "model parameter": shown beside the model in `/model`
  (as ACP asks), set in place, listed under the model's name in `/config`.
  No `/fast` and no "context" row by meaning; the person sees the agent's
  own names ("Fast mode", "Ultracode"). Works with Claude and Codex today,
  with no guessing. A `/fast` command cannot exist under A.
- **B. A recorded table by agent and option id** (`claude-acp`/`fast`,
  `codex-acp`/`fast-mode`, later others) naming an option as fast. Not a
  guess from free text, but a list chord keeps per adapter version, which
  B12 refused for effort. Owner.
- **C. Our own `_`-category, sent by our package and asked upstream.**
  cursor-cloud-acp sends `_chorded/fast`, `_chorded/context` … only for
  Cursor parameter ids recorded from a live `Cursor.models.list()`; chord
  reads those. Claude and Codex would not send them unless they adopt it.
- **D. Upstream ask.** Propose to ACP reserved categories (or a
  `model_config` sub-kind in `_meta`) for speed and context window. Slow; no
  promise.
- **E. Treat any boolean `model_config` option as "the fast toggle".**
  Wrong for Claude, whose `ultracode` is also a boolean `model_config`.
  Rejected.

**Recommendation: A now, D filed, C for cursor-cloud.** A gives a person
fast and context wherever the agent marks them `model_config`, with the
agent's own labels, and keeps the no-guess rule. A dedicated `/fast` needs B
or an upstream answer: **owner's choice** whether `/fast` (i) is dropped,
(ii) toggles the only boolean-or-on/off `model_config` option when there is
exactly one and otherwise opens the parameters list (still a structural
guess; I advise against), or (iii) waits on B/D.

What stays in `/config`: everything that is not `mode`, `model`,
`thought_level` (first) or `model_config`, i.e. Codex's
`collaboration_mode`, Claude's `agent`, cursor-cloud's uncategorised
parameters until C, codebuddy's `sandbox`.

### What cursor-cloud-acp should send (ours)

1. Record the real ids: one authorised live `Cursor.models.list()` into
   `docs/agent-capabilities.md` (owner's account; owner).
2. Map recorded ids only: effort → `thought_level`; every other parameter →
   `model_config` (that is what ACP's page says they are). Unknown ids stay
   uncategorised. No `_chorded/*` category is needed for A; C is only
   needed if `/fast` by meaning is wanted.
3. On Cursor's default send nothing more: there is nothing to set, and the
   model row should say so (interface).
4. Declare booleans? Cursor parameters are value lists; keep selects.

## 4. Boolean options

Today chord drops booleans from `/config` (`config.ts` keeps selects) and
does not declare the capability; Claude and Codex fall back to `on`/`off`
selects, cline and dirac send booleans anyway, which chord cannot set.

- **A. Declare `session.configOptions.boolean: {}`** and handle booleans:
  `AgentOption` grows `kind: 'select' | 'boolean'`; `setOption` sends
  `{ type: 'boolean', value }`; the record's `state.options` widens to
  `Record<string, string | boolean>`. Records stay readable (old lines are
  strings); a newer line read by an older chord is a type change the
  owner should know of.
- **B. Keep selects only**, and show the booleans that arrive anyway as
  read-only.

**Recommendation: A.** Claude and Codex then send `fast` and `ultracode` as
real toggles; cline's auto-approve and dirac's `yolo` become settable,
which is a **permission-safety question for the owner** (a toggle that
skips every permission prompt). Proposed: show such a boolean in `/config`
with its agent description, no special key.

## 5. Setting a parameter of a model not yet chosen

ACP cannot. A model's options exist only while the session is on it, and no
call previews them (section 1). What the picker can do:

- **A. Only the current model's parameters are live.** On another
  highlighted model the row says the parameters come after it is chosen; ←/→
  does nothing there.
- **B. Remembered options.** chord keeps, per session, the last option set
  the agent sent while on each model (memory only, keyed by model id). ←/→ on
  a remembered model moves among those values; Enter sends:
  1. `set_config_option(model)`, await the answer, fold it;
  2. if the answer's `thought_level` option offers the picked value and it
     differs from `currentValue`, `set_config_option(effort)`; same for each
     changed `model_config` option, in the agent's order;
  3. each answer folded in turn. A value the new set no longer offers is not
     sent; the person is told which one was not applied.
  Models never visited behave as A.
- **C. Effort first, then model**, relying on carry-over. Claude carries a
  pinned effort if the new model supports it; Codex carries the current one;
  other agents are unknown. Rejected: depends on behaviour ACP does not
  state.
- **D. Parse Codex's legacy `model[effort]` ids.** Gives every model's
  efforts up front, but reads meaning into an id format. Rejected.
- **E. `configOptions` on `session/new`** (Session options RFD): applies only
  when a session opens; Claude only; SDK upgrade. Useful later for
  `--effort` at open, not for the picker.

**Recommendation: B, falling back to A.** It is what the agent itself told
chord, never invented. The order model → answer → parameters is required:
the parameter set depends on the model. Runtime owns the concurrency
details; from the protocol side:

- Claude serialises config changes per session, so a late
  `config_option_update` cannot interleave inside one set; Codex sends the
  update before answering. Folding by arrival order is correct for both; the
  answer is the authority for step 2.
- **The agent exits** between steps: model may be set, effort not; the next
  session's options come from `session/load`/`resume` and the record's
  `state` line (below).
- **A turn is running**: neither adapter refuses `set_config_option`
  mid-turn; Claude applies flag settings to the live query. Whether chord
  should send mid-turn is runtime's.
- **Refusal** (`-32602` unknown value, or Claude's "session ended"): the
  model step's failure stops the sequence; a parameter's failure leaves the
  model set and reports the parameter.
- **Cancelled picker** mid-sequence: requests already sent are not undone.

Remembered sets are per session and not recorded: they would go stale
across adapter versions and are cheap to relearn.

## 6. Reducer, state and record

- `AgentState` unchanged: `configOptions` as last answered/updated.
- New pure readers beside `effortsFrom`: `modelParametersFrom(options)` —
  the `model_config` options in agent order (selects and, under 4A,
  booleans); `optionsFromConfigOptions` then also leaves out the first
  `thought_level` and every `model_config` (they have homes elsewhere).
  Whether `/config` still lists them as well is interface's call.
- `rememberedOptions: Map<modelId, SessionConfigOption[]>` filled when an
  options set arrives with a `model` current value; lives in the session,
  not in `AgentState`'s fold of updates if that must stay pure — runtime.
- Record: no new entry type. The `state` line already keeps every option's
  current value by id (`record.ts` `stateEntry`), so effort and fast are
  recorded; under 4A its values may be booleans. Replay draws nothing from
  options (status line only), so a resumed session shows what the agent
  answers on load/resume.
- MCP tools (`src/server/tools.ts`): no change proposed. A
  `set_effort`/`set_model` tool is out of the brief.

## 7. fx's `fast` under category `model`

fx puts `provider`, `model`, `fast`, `ultrafast` all in category `model`.
chord takes the first `model` select as the model list, so it shows
providers; the rest are hidden. Recognising fx's `fast` as fast is
impossible without guessing. Options:

- **A. Leave fx as is** and record it; ask fx upstream to use `model_config`
  for `fast`/`ultrafast` and a `_provider` category (dirac already does).
- **B. Prefer an option with id `model` over the first of category `model`**
  when several share the category. It is an id rule (as `isModeOrModel`
  already uses ids); it fixes `/model` for fx and cline but still leaves
  fast/ultrafast unnamed. Owner: ids are what B12 avoids for effort.
- **C. Show every extra `model`-category select as a model parameter**
  (they are then near the model, as ACP asks for `model_config`).

**Recommendation: A, with C as a cheap structural improvement** (no id read,
no meaning named). B is the owner's.

## 8. Open questions for the owner

1. `/fast` without an ACP signal: drop it, wait on upstream, or a recorded
   per-adapter id table (3B)? (Recommend: parameters in `/model`, no `/fast`
   by meaning, upstream ask filed.)
2. Declare boolean options (4A), including permission-skipping booleans
   (cline auto-approve, dirac `yolo`) becoming settable?
3. One live `Cursor.models.list()` on the owner's account to record
   Cursor's parameter ids for cursor-cloud-acp's categories.
4. fx/cline: prefer id `model` among several `model` selects (7B)?
5. File an ACP issue for speed and context categories (3D)? Who files it.
