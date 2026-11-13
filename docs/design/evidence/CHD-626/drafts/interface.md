# CHD-626 interface draft: parameters in `/model`, `/effort`, fast, `/config`

Interface architect's draft. It answers the brief's interface items: the
screens, their states, the keys and the shortcuts panel, the state slices,
and Q1, Q2 and Q4. Q3 (how an option is recognised as effort, fast or
context) is protocol's; this draft only says what the screen does with each
answer. Choices marked **(owner)** are the owner's to make.

## What was looked at

- chord today, `bun dev chord --fake --qa iface626` at 120x40: `/model` is a
  framed list ("Select model", one line of description, numbered models,
  `✔` after the one in use, "Enter to switch · Esc to close"); `/config` is
  two levels ("Settings": `Effort  Medium`, Enter → "Set Effort": `Low`,
  `Medium ✔`, `High`, "Enter to set · Esc to go back"). Pickers close on
  Enter; the agent's answer goes into the transcript as a note under the
  command, a refusal as a failed row (`conversation.ts` `setModel`,
  `setOption`).
- Claude Code 2.1.323 in tmux, no prompt sent:
  - `/model`: the list, then one line for the highlighted model,
    `◐ Medium effort (default) ←/→ to adjust`; → gives `● High effort`,
    `◉ xHigh effort`, `◈ Max effort` (Max adds a warning line under it),
    and stops at Max. The line stays when the highlight moves to another
    model. Hint: `Enter to set as default · s to use this session only ·
    Esc to cancel`.
  - `/effort`: "Effort", a rule with `▲` under the current stop between
    `Faster` and `Smarter`, the names `low medium high xhigh max` under it,
    "The default effort for this model", and `←/→ to adjust · Enter to
    confirm · s for this session only · Esc to cancel`; an `Ultracode off
    / Tab to toggle` beside it.
  - `/fast`: a panel "↯ Fast mode" (on this account it only explained that
    usage credits are needed).
  - Its keybindings (read from the binary's default table): context
    `ModelPicker` with `left: modelPicker:decreaseEffort`,
    `right: modelPicker:increaseEffort`, `s: modelPicker:thisSessionOnly`;
    context `EffortSlider` with `effortSlider:decreaseEffort` /
    `increaseEffort` on ←/→ and `effortSlider:toggleUltracode` on Tab;
    `Chat` with `meta+p: chat:modelPicker`, `meta+o: chat:fastMode`,
    `ctrl+x =` / `ctrl+x -`: `chat:increaseEffort` / `chat:decreaseEffort`.
- `src/ui/pickers/` (state, picker.ts, Pickers.tsx), `src/session/efforts.ts`,
  `config.ts`, `models.ts`, `src/ui/shortcuts/keys.ts` and `bindings.ts`,
  `src/ui/app/state.ts`'s key routing. ← in a picker does nothing today: only
  the background view reads ← (`app/state.ts` ~2195), so ←/→ are free in
  `/model` and `/config`.
- OpenTUI 0.6.x: `<tab-select>` and core's `SliderRenderable`; see
  "Components" below.

## The three things the screen needs from the session

The screen reads what the session layer gives it and recognises nothing on
its own. Per model in use, the session gives:

1. `efforts(): AgentEfforts | undefined` — exists (`thought_level`).
2. `fast(): AgentOption | undefined` — the option protocol's Q3 answer
   recognises as fast, or none. Until Q3 is settled, none for every agent,
   and everything below that reads it shows nothing.
3. `options(): AgentOption[]` — every select but mode and model, as today,
   effort and fast included (they stay listed, so a person can reach them
   from `/config` whatever Q3 decides).

A context window, where an agent offers one as an option, is one of the
`options()` rows; the screen gives it no place of its own unless Q3 gives
chord a way to know it (then it goes in the `/model` line's summary, after
effort, as Cursor does with `200K`).

## Q1. `/model`'s layout and keys

### Layout (recommended, for every agent)

The list stays as it is. Under it, one fixed line for the parameters
(**the settings line**), then the hint. The line has one row whatever is
highlighted, so moving the highlight never shifts the frame.

- **Model in use, with efforts**: `◐ Medium effort  ←/→ to adjust`, then
  the other options of the model in use as `Name  Value`, ` · ` between,
  then `Tab for all settings`. Cut at the right edge with `…`, effort
  first, as the status line drops the effort last.
- **Model in use, no efforts, other options**: `Fast  Off · Max mode  Off
  Tab for all settings`.
- **Model in use, nothing**: Q4.
- **Another model highlighted**: Q1's sub-question below.
- **Agent that sends no options at all** (the legacy `models` field only,
  or a `model` option and nothing else): no settings line, the frame is
  today's (A6).

The glyph before the effort is chosen by the effort's place in the agent's
list, never by its name: the first `○`, the last `●`, the middle ones `◐`
(and `◔`/`◕` on either side where there are five or more). The words are
the agent's name for the value, then `effort`. No `(default)`: ACP marks no
default value. **(owner)** whether to keep the glyph at all: it says "more
or less" from the order alone, which Claude's and Codex's lists keep
(low → max) but fx's does not (`auto` first, fx10).

Colours (`src/ui/theme/theme.ts` roles): frame, title, `❯`, the highlighted
row and the `▲`/`‹ ›` markers in `permission`; the description, settings
line words other than the value, and the hint dim (unpainted); the effort
glyph and value in plain text, in `permission` while a changed value waits
for Enter; the Max-style warning line, where an agent's value carries a
description, dim. Failures in the transcript in `error`.

### Keys in `/model`

| Key | Does | Rebindable |
| --- | --- | --- |
| ↑ ↓ j k, 1–9, Enter | as today | no (the list's own) |
| ← → | effort down / up one, stopping at either end, waiting for Enter | yes: `modelPicker:decreaseEffort`, `modelPicker:increaseEffort`, context `ModelPicker`, Claude Code's names and defaults |
| Tab | the model in use's settings, in place (A4) | yes: `modelPicker:settings`, chord's own name, context `ModelPicker` |
| Esc | close; nothing waiting is sent | `select:cancel` as today |

Claude Code's `s` (`modelPicker:thisSessionOnly`) has no counterpart: chord
has no saved default model, every pick is for this session.

Enter on the model in use sends only what changed (effort, and anything
changed under Tab) and closes; with nothing changed it closes, as Enter on
the model in use does today. Enter on another model switches it (and Q1b).

### Q1b. Another model highlighted: its effort before it is chosen

ACP gives a model's options only once it is in use, so the efforts of a
highlighted model that is not are unknown. Options:

- **A. Switch first.** The line reads `Haiku 5.5's effort and settings show
  once it is in use`; ←/→ and Tab do nothing there and leave the hint. Enter
  switches and the picker **stays open** on the switched model in a
  "switching…" row (A3b) until the agent answers with the new option set,
  then the line is live for it; Enter or Esc then closes. No value is ever
  sent that the agent did not offer for that model. One more Enter than
  Claude Code.
- **B. Carry over (Claude Code's feel).** The line keeps the efforts of the
  model in use while the highlight is elsewhere, with `asked for once Haiku
  5.5 is in use, if it offers High` (A3). ←/→ change it. Enter closes and
  switches; once the agent's new option set comes, chord asks for the same
  value id of the same `thought_level` option **only if the person moved
  it** and the new set offers that id; otherwise the transcript says
  `Haiku 5.5 offers no High effort; it is on Medium.` This matches ids the
  agent itself sent, not meanings, but it is two calls with a resent option
  set between them: runtime's sequence and protocol's race decide whether
  it is sound.
- **C. Codex's.** Enter switches and closes, then `/effort`'s picker opens
  by itself on the new model's efforts when it has some.

**Recommendation: B**, falling back to A's wording on the line for an
agent whose efforts come only from the legacy `models` path, if runtime
finds B's sequence sound; else A. **(owner)**: A, B or C.

### Q1c. Other parameters in `/model`

- **A. Summary on the line, Tab for all** (recommended, drawn): the line
  names each option of the model in use and its value; Tab opens them all as
  rows with ←/→ in place (A4, the same rows `/config` draws), Esc back to the
  list. Cursor's "Edit Parameters" without its radio groups (see
  Components).
- **B. Effort only in `/model`**; every other option only in `/config`.
- **C. One letter per recognised option** in `/model` (`f` for fast), as
  Claude's `s`: needs Q3 to recognise them and a key each; not recommended.

## Q2. `/effort` and fast

### `/effort`

A command of chord's (`ChordCommand` gains `effort`, "Change the agent's
effort for this session"). It opens its own framed picker (C1–C3): a rule
with `▲` under the effort in use, the agent's names for its efforts under
it, in the agent's order, spaced evenly. ←/→ move the `▲`; Enter sets and
closes; Esc closes. Where the names do not fit the width, a window of them
scrolls round the `▲` with `‹`/`›` at the cut ends (C3).

- No `Faster`/`Smarter` ends by default: ACP does not say the order means
  speed against depth, and fx's `auto` comes first. **(owner)** whether to
  draw them anyway for agents whose option is `thought_level` (Claude's,
  Codex's both are ascending).
- `/effort <name>` sets it directly, without the picker, when `<name>` is
  one of the agent's value ids or names, matched case-blind against what the
  person typed (not guessing the agent's meaning, matching its own words).
  **(owner)**: keep or drop the argument form (Claude Code has it).
- Agent or model with no efforts: no picker; a transcript note under
  `/effort`: `claude-acp offers no effort for Haiku 5.5.`, or for Cursor's
  default `cursor-cloud offers no effort for Cursor's default. /model to
  pick a model that has one.`
- Keys: ←/→ `effortSlider:decreaseEffort` / `increaseEffort`, context
  `EffortSlider`, Claude Code's names, rebindable; Enter fixed; Esc
  `select:cancel`. Claude's Tab (`effortSlider:toggleUltracode`) has no
  counterpart.

### Fast

- **A. `/fast` toggles** (recommended): a command of chord's, "Turn the
  agent's fast mode on or off". When the session gives a fast option with
  two values, Enter on `/fast` sets the one not in use and the transcript
  note says `Fast mode on for Opus 5.5.` / `off`. With more than two values
  it opens the `/model` Tab rows on that option. With none: `claude-acp
  offers no fast mode for Haiku 5.5.` Which two values are "on" and "off" is
  Q3's; the note uses the agent's own value names (`Fast mode: On`) until Q3
  says more.
- **B. Fast only on the `/model` line and in `/config`**, no command.
- **C. A and Claude Code's `meta+o` (`chat:fastMode`)** as a global key; see
  "The shortcuts panel".

The status line already shows model and effort; fast is not added there
(brief non-goal). **(owner)** if fast should show on the status line, it is
a follow-up decision about its layout.

## Q4. A model with no parameters (Cursor's default)

- **A. Say so on the settings line** (recommended, A5/B4):
  `Cursor's default has no effort or settings to change`, dim; ←/→ and Tab
  inert and out of the hint. `/effort` and `/fast` answer with the
  transcript notes above; `/config` says `cursor-cloud has no settings for
  Cursor's default.` with `/model to pick a model that has some.` (D3).
- **B. No line**: the frame grows a row when the highlight lands on a model
  in use that has settings: rows jump; not recommended.
- **C. Mark the row** (`Cursor's default · no settings`): impossible for
  models not in use, whose options are unknown; only possible for the one in
  use, where A already says it.

## `/config`

One level instead of two (D1, D2): each option a row, `Name  ‹ Value ›`,
then the values in the agent's order, dim, where the width has room (left
out at 80 columns, B3). ↑↓ j k move between rows; ←/→ change the highlighted
row's value, waiting for Enter, a `•` after a changed row; Enter sends every
changed row and closes (`Enter to set 2` counts them); Esc closes and sends
nothing. The second-level list and "Set Effort" go. A row's agent
description (ACP's `description`), where it has one, is the dim line under
the row while it is highlighted.

`/config` lists effort and fast too, so whatever Q3 decides, every option an
agent sends stays reachable. Boolean options (`SessionConfigBoolean`) are
rows with `‹ Off ›`/`‹ On ›` once protocol says chord takes them; the
screen needs nothing else for them.

Sending several changes at once while the agent resends its option set on
each (a changed effort may change the others) is runtime's to sequence;
what the screen needs is that a changed value whose option is gone or no
longer offers that value is reported, not sent: `Max mode is no longer
offered for GPT-5.5; not set.`

## States

| State | What shows |
| --- | --- |
| Loading (session not up) | no picker, as today (`modelPickerShown` needs `ready`); `/effort`, `/fast`, `/config` likewise |
| A permission asked | it takes the picker's place, as today |
| Setting | picker closed; nothing in flight on screen, as today; the status line changes when the agent reports |
| Switching (Q1 A only) | the picker open, `switching…` after the model, line blank, hint `Esc to close` (A3b) |
| Set | transcript note under the command: `⎿ Switched to Haiku 5.5 · High effort`, `⎿ Effort set to High`, `⎿ Fast mode on for Opus 5.5` |
| Failed | failed row in `error`: `Could not set Effort to High: <agent's message>` |
| Partial | two rows: `⎿ Switched to Haiku 5.5` and, in `error`, `Could not set Effort to High: …` |
| Option gone meanwhile | the open picker re-reads options on every update; a pending value no longer offered is dropped and the row shows the agent's current value |
| Narrow (80x24) | B1–B4, C2–C3, D2–D3: the line keeps one row, its summary cut with `…` before the effort; the list gives way first (CHD-545's `Body`) |

## The shortcuts panel

The panel is at its 40 lines (20 a column at 80x24), so new keys share
lines:

- `↑ ↓ or j k  to move between choices` becomes `↑ ↓ j k ← →  to move or
  change a value`; its `choices` gain `←`, `→`, and its `actions` name
  `modelPicker:decreaseEffort`, `modelPicker:increaseEffort`,
  `effortSlider:decreaseEffort`, `effortSlider:increaseEffort` so a rebound
  key is shown as bound. `/config`'s ←/→ are the list's own (fixed, in
  `choices`).
- Tab in `/model`: a `choices`-style entry folded into the `tab enter` line
  is wrong (that one is history search); a new line `tab  for a model's
  settings` costs one line. **(owner)**: take the line, or name Tab only in
  `/model`'s hint (it is a widget-owned key; the panel rule in AGENTS.md
  then needs the owner's exception).
- Global keys **(owner)**: Claude Code binds `meta+p` (`chat:modelPicker`),
  `meta+o` (`chat:fastMode`), `ctrl+x =` / `ctrl+x -`
  (`chat:increaseEffort` / `chat:decreaseEffort`, beside chord's `ctrl+x a`
  and `ctrl+x b` leader keys). Options: (i) none: `/model`, `/effort`,
  `/fast` are typed (recommended for this task, no panel line); (ii) all
  four with Claude's defaults, two panel lines (`alt + p  alt + o  for model,
  fast` and `ctrl + x = -  for more or less effort`), which needs two lines
  freed elsewhere; (iii) the actions in `bindings.ts` with no default key,
  bindable in the file only, if `bindings.ts` takes an empty `keys`.

`bindings.ts` gains contexts `ModelPicker` and `EffortSlider` in
`CONTEXTS`, Claude Code's names, so a block copied from
`~/.claude/keybindings.json` means the same. `tests/ui/shortcuts/keys_test.tsx`
then presses ← → Tab in `/model` and ← → in `/effort` and `/config`.

## State slices (`src/ui/pickers/state.ts`)

```ts
interface PickersState {
  // was `modelPicker: boolean`
  readonly modelPicker?: ModelPicker;
  // one level now: no `option`/`from`
  readonly configPicker?: { readonly pending: Readonly<Record<string, string>> };
  readonly effortPicker?: { readonly value: string };
  …
}

interface ModelPicker {
  /** The effort value id waiting for Enter; none while unchanged. */
  readonly effort?: string;
  /** Tab: the model in use's settings rows, with their own pending values. */
  readonly settings?: { readonly pending: Readonly<Record<string, string>> };
  /** Q1 A only: the model asked for, until its option set comes. */
  readonly switching?: string;
}
```

Actions: `model_effort_stepped {by: -1 | 1, efforts}`,
`model_settings_opened`, `model_settings_back`, `model_switch_asked {id}`
(A), `model_switch_answered` (A); `config_value_stepped {id, by, values}`;
`effort_picker_opened {value}`, `effort_stepped {by, efforts}`,
`effort_picker_closed`. `config_option_opened` and `config_picker_back` go.
`effortPickerShown` sits beside `configPickerShown` with the same rule
(session ready, no permission asked). The highlight stays the list's own
(`PickerList`), as today; the pending values are in state so reducers test
them.

Pure logic beside the components:

- `src/ui/pickers/params.ts` (new): `stepValue(values, current, by)`
  (clamped, no wrap, as Claude Code stops at Max); `effortGlyph(index,
  count)`; `settingsLine(efforts, options, pending, width)` → the line's
  spans, cut in order; `effortScale(efforts, current, width)` → the rule,
  `▲` column and names, windowed with `‹ ›`; `optionRows(options, pending,
  width)` → `/config`'s and Tab's rows, values list dropped when it does not
  fit; `changed(pending, options)` → what Enter sends, gone values dropped
  with their notes.
- `picker.ts`: `modelToAsk` stays; `optionChoices`/`valueChoices` go to
  `params.ts`'s rows.
- What is effort, fast or context stays in `src/session/` (Q3).

## Components

- Frames, rows, the line and the hint: OpenTUI's `box`/`text`/`span`
  through `theme/text.ts`, as every picker today; the list is `PickerList`
  (decisions: "OpenTUI part 2: The pickers").
- `/effort`'s scale: OpenTUI has no labelled-stops slider. Core's
  `SliderRenderable` is a scrollbar-style thumb on a track with no labels,
  driven by the mouse and not exported by `@opentui/react`. `<tab-select>`
  draws names in fixed-width tabs and moves on its own ←/→ while focused,
  with an underline row; CHD-1 (2026-10-15) found it unfit for the question
  box's steps for the same reasons (fixed width, own focus and keys, one
  colour a tab), and chord hears keys through `usePress` only (decisions,
  "OpenTUI part 8b"). The ship team tries `<tab-select>` first per the one
  rule; if it fails as in CHD-1, the scale is one `<text>` of spans, and
  the finding goes in `docs/decisions.md`.
- Cursor's radio groups in "Edit Parameters": OpenTUI has no radio group;
  the rows' `‹ Value ›` plus the dim list of values is the
  `PickerList`-style row drawn by hand, as the question box's options are.

## Screens

Whole windows, the session's other rows (agents list, status line's left
side) left out where they add nothing. The model names are illustrative.

**A1. `/model`, the model in use highlighted, effort in place** (120x40)

```text
  ▀▀▀▄   claude-acp · Opus 5.5
  ▄▀▀▀   ~/projects/app
  ▀▀     ? for shortcuts · /help

› fix the flaky login test

⏺ Done. The test waited on a timer the fake clock never fired; it now advances it.















╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Select model                                                                                                         │
│ Switch claude-acp's model for this session.                                                                          │
│                                                                                                                      │
│ ❯ 1. Default (recommended) ✔  Opus 5.5 · Best for everyday, complex tasks                                            │
│   2. Opus 5.5                                                                                                        │
│   3. Fable 5.2                                                                                                       │
│   4. Sonnet 5.5                                                                                                      │
│   5. Haiku 5.5                                                                                                       │
│                                                                                                                      │
│ ◐ Medium effort  ←/→ to adjust · Fast  Off · Ultracode  Off   Tab for all settings                                   │
│                                                                                                                      │
│ Enter to switch · ←/→ for effort · Tab for settings · Esc to close                                                   │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                                               Opus 5.5 · medium effort
```

**A2. → pressed once: a value waiting for Enter** (120x40)

```text
  ▀▀▀▄   claude-acp · Opus 5.5
  ▄▀▀▀   ~/projects/app
  ▀▀     ? for shortcuts · /help

› fix the flaky login test

⏺ Done. The test waited on a timer the fake clock never fired; it now advances it.















╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Select model                                                                                                         │
│ Switch claude-acp's model for this session.                                                                          │
│                                                                                                                      │
│ ❯ 1. Default (recommended) ✔  Opus 5.5 · Best for everyday, complex tasks                                            │
│   2. Opus 5.5                                                                                                        │
│   3. Fable 5.2                                                                                                       │
│   4. Sonnet 5.5                                                                                                      │
│   5. Haiku 5.5                                                                                                       │
│                                                                                                                      │
│ ● High effort  ←/→ to adjust · Fast  Off · Ultracode  Off   Tab for all settings                                     │
│                                                                                                                      │
│ Enter to set · ←/→ for effort · Tab for settings · Esc to close                                                      │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                                               Opus 5.5 · medium effort
```

**A3. Another model highlighted (Q1 option B, carry over)** (120x40)

```text
  ▀▀▀▄   claude-acp · Opus 5.5
  ▄▀▀▀   ~/projects/app
  ▀▀     ? for shortcuts · /help

› fix the flaky login test

⏺ Done. The test waited on a timer the fake clock never fired; it now advances it.















╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Select model                                                                                                         │
│ Switch claude-acp's model for this session.                                                                          │
│                                                                                                                      │
│   1. Default (recommended) ✔  Opus 5.5 · Best for everyday, complex tasks                                            │
│   2. Opus 5.5                                                                                                        │
│   3. Fable 5.2                                                                                                       │
│   4. Sonnet 5.5                                                                                                      │
│ ❯ 5. Haiku 5.5                                                                                                       │
│                                                                                                                      │
│ ● High effort  ←/→ to adjust · asked for once Haiku 5.5 is in use, if it offers High                                 │
│                                                                                                                      │
│ Enter to switch · ←/→ for effort · Esc to close                                                                      │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                                               Opus 5.5 · medium effort
```

**A3a. Another model highlighted (Q1 option A, switch first)** (120x40)

```text
  ▀▀▀▄   claude-acp · Opus 5.5
  ▄▀▀▀   ~/projects/app
  ▀▀     ? for shortcuts · /help

› fix the flaky login test

⏺ Done. The test waited on a timer the fake clock never fired; it now advances it.















╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Select model                                                                                                         │
│ Switch claude-acp's model for this session.                                                                          │
│                                                                                                                      │
│   1. Default (recommended) ✔  Opus 5.5 · Best for everyday, complex tasks                                            │
│   2. Opus 5.5                                                                                                        │
│   3. Fable 5.2                                                                                                       │
│   4. Sonnet 5.5                                                                                                      │
│ ❯ 5. Haiku 5.5                                                                                                       │
│                                                                                                                      │
│ Haiku 5.5's effort and settings show once it is in use                                                               │
│                                                                                                                      │
│ Enter to switch · Esc to close                                                                                       │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                                               Opus 5.5 · medium effort
```

**A3b. Q1 option A after Enter: switching, then live** (120x40)

```text
  ▀▀▀▄   claude-acp · Opus 5.5
  ▄▀▀▀   ~/projects/app
  ▀▀     ? for shortcuts · /help

› fix the flaky login test

⏺ Done. The test waited on a timer the fake clock never fired; it now advances it.















╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Select model                                                                                                         │
│ Switch claude-acp's model for this session.                                                                          │
│                                                                                                                      │
│   1. Default (recommended)  Opus 5.5 · Best for everyday, complex tasks                                              │
│   2. Opus 5.5                                                                                                        │
│   3. Fable 5.2                                                                                                       │
│   4. Sonnet 5.5                                                                                                      │
│ ❯ 5. Haiku 5.5  switching…                                                                                           │
│                                                                                                                      │
│                                                                                                                      │
│                                                                                                                      │
│ Esc to close                                                                                                         │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                                               Opus 5.5 · medium effort
```

**A4. Tab: every setting of the model in use, in place (cursor-cloud)** (120x40)

```text
  ▀▀▀▄   cursor-cloud · Claude 4.7 Sonnet
  ▄▀▀▀   ~/projects/app
  ▀▀     ? for shortcuts · /help























╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Claude 4.7 Sonnet settings                                                                                           │
│ Change cursor-cloud's settings for Claude 4.7 Sonnet.                                                                │
│                                                                                                                      │
│ ❯ Context    ‹ 200K ›      200K · 1M                                                                                 │
│   Thinking   ‹ High ›      Low · Medium · High                                                                       │
│   Max mode   ‹ Off ›       Off · On                                                                                  │
│                                                                                                                      │
│ Enter to set · ←/→ to change · Esc to go back                                                                        │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                                                      Claude 4.7 Sonnet
```

**A5. Cursor's default (Auto) in use: nothing to change (Q4 option A)** (120x40)

```text
  ▀▀▀▄   cursor-cloud · Claude 4.7 Sonnet
  ▄▀▀▀   ~/projects/app
  ▀▀     ? for shortcuts · /help




















╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Select model                                                                                                         │
│ Switch cursor-cloud's model for this session.                                                                        │
│                                                                                                                      │
│ ❯ 1. Cursor's default ✔                                                                                              │
│   2. Claude 4.7 Sonnet                                                                                               │
│   3. GPT-5.5                                                                                                         │
│   4. Composer 2                                                                                                      │
│                                                                                                                      │
│ Cursor's default has no effort or settings to change                                                                 │
│                                                                                                                      │
│ Enter to switch · Esc to close                                                                                       │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                                                       Cursor's default
```

**A6. An agent that sends no options besides its models** (120x40)

```text
  ▀▀▀▄   gemini · Gemini 3 Pro


























╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Select model                                                                                                         │
│ Switch gemini's model for this session.                                                                              │
│                                                                                                                      │
│ ❯ 1. Gemini 3 Pro ✔                                                                                                  │
│   2. Gemini 3 Flash                                                                                                  │
│                                                                                                                      │
│ Enter to switch · Esc to close                                                                                       │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                                                           Gemini 3 Pro
```

**B1. `/model` at 80x24** (80x24)

```text
  ▀▀▀▄   claude-acp · Opus 5.5
  ▄▀▀▀   ~/projects/app

› fix the flaky login test
⏺ Done.

╭──────────────────────────────────────────────────────────────────────────────╮
│ Select model                                                                 │
│ Switch claude-acp's model for this session.                                  │
│                                                                              │
│ ❯ 1. Default (recommended) ✔  Opus 5.5                                       │
│   2. Opus 5.5                                                                │
│   3. Fable 5.2                                                               │
│   4. Sonnet 5.5                                                              │
│   5. Haiku 5.5                                                               │
│                                                                              │
│ ◐ Medium effort ←/→ · Fast Off · Ultracode Off                               │
│                                                                              │
│ Enter to switch · ←/→ effort · Tab settings · Esc to close                   │
╰──────────────────────────────────────────────────────────────────────────────╯
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                              Opus 5.5 · medium
```

**B2. `/model` at 80x24, short of room (list cut, line and hint stay)** (80x24)

```text
  ▀▀▀▄   claude-acp · Opus 5.5
  ▄▀▀▀   ~/projects/app

› fix the flaky login test
⏺ Done.
a long answer
fills the
transcript
above
╭──────────────────────────────────────────────────────────────────────────────╮
│ Select model                                                                 │
│                                                                              │
│ ❯ 1. Default (recommended) ✔  Opus 5.5                                       │
│   2. Opus 5.5                                                                │
│ ↓ 3 more                                                                     │
│                                                                              │
│ ◐ Medium effort ←/→ · Fast Off · Ultracode Off                               │
│                                                                              │
│ Enter to switch · ←/→ effort · Tab settings · Esc to close                   │
╰──────────────────────────────────────────────────────────────────────────────╯
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                              Opus 5.5 · medium
```

**B3. Tab settings at 80x24 (values list dropped where it does not fit)** (80x24)

```text
  ▀▀▀▄   cursor-cloud · Claude 4.7 Sonnet
  ▄▀▀▀   ~/projects/app
  ▀▀     ? for shortcuts · /help








╭──────────────────────────────────────────────────────────────────────────────╮
│ Claude 4.7 Sonnet settings                                                   │
│                                                                              │
│ ❯ Context    ‹ 200K ›                                                        │
│   Thinking   ‹ High ›                                                        │
│   Max mode   ‹ Off ›                                                         │
│                                                                              │
│ Enter to set · ←/→ to change · Esc to go back                                │
╰──────────────────────────────────────────────────────────────────────────────╯
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                              Claude 4.7 Sonnet
```

**B4. Cursor's default at 80x24** (80x24)

```text
  ▀▀▀▄   cursor-cloud · Claude 4.7 Sonnet
  ▄▀▀▀   ~/projects/app
  ▀▀     ? for shortcuts · /help




╭──────────────────────────────────────────────────────────────────────────────╮
│ Select model                                                                 │
│ Switch cursor-cloud's model for this session.                                │
│                                                                              │
│ ❯ 1. Cursor's default ✔                                                      │
│   2. Claude 4.7 Sonnet                                                       │
│   3. GPT-5.5                                                                 │
│   4. Composer 2                                                              │
│                                                                              │
│ Cursor's default has no effort or settings to change                         │
│                                                                              │
│ Enter to switch · Esc to close                                               │
╰──────────────────────────────────────────────────────────────────────────────╯
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                               Cursor's default
```

**C1. `/effort` (claude-acp, five efforts)** (120x40)

```text
  ▀▀▀▄   claude-acp · Opus 5.5
  ▄▀▀▀   ~/projects/app
  ▀▀     ? for shortcuts · /help

› fix the flaky login test

⏺ Done. The test waited on a timer the fake clock never fired; it now advances it.




















╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Effort                                                                                                               │
│ claude-acp's effort for Opus 5.5, in the order it gives them.                                                        │
│                                                                                                                      │
│         ────────────────▲─────────────────────────────────────────                                                   │
│         Low        Medium        High        xHigh        Max                                                        │
│                                                                                                                      │
│ ←/→ to adjust · Enter to set · Esc to cancel                                                                         │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                                               Opus 5.5 · medium effort
```

**C2. `/effort` at 80x24 (fx: `auto` first, then the model's)** (80x24)

```text
  ▀▀▀▄   fx · claude-sonnet










╭──────────────────────────────────────────────────────────────────────────────╮
│ Effort                                                                       │
│ fx's effort for claude-sonnet.                                               │
│                                                                              │
│   ▲──────────────────────────────────────────                                │
│   Auto    Low    Medium    High                                              │
│                                                                              │
│ ←/→ to adjust · Enter to set · Esc to cancel                                 │
╰──────────────────────────────────────────────────────────────────────────────╯
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                    claude-sonnet · auto effort
```

**C3. `/effort` at 80x24 with more names than fit: the window around ▲** (80x24)

```text
  ▀▀▀▄   some-agent










╭──────────────────────────────────────────────────────────────────────────────╮
│ Effort                                                                       │
│ some-agent's effort for big-model.                                           │
│                                                                              │
│ ‹ ──────────────────────────▲──────────────────────── ›                      │
│ ‹ Minimal   Low   Medium   High   xHigh   Max      ›                         │
│                                                                              │
│ ←/→ to adjust · Enter to set · Esc to cancel                                 │
╰──────────────────────────────────────────────────────────────────────────────╯
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                      big-model
```

**D1. `/config`, one level: every setting with ←/→ in place (claude-acp)** (120x40)

```text
  ▀▀▀▄   claude-acp · Opus 5.5
  ▄▀▀▀   ~/projects/app
  ▀▀     ? for shortcuts · /help

› fix the flaky login test

⏺ Done. The test waited on a timer the fake clock never fired; it now advances it.


















╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Settings                                                                                                             │
│ Change claude-acp's settings for Opus 5.5.                                                                           │
│                                                                                                                      │
│ ❯ Effort      ‹ Medium ›    Low · Medium · High · xHigh · Max                                                        │
│   Fast        ‹ Off ›       Off · On                                                                                 │
│   Ultracode   ‹ Off ›       Off · On                                                                                 │
│   Agent       ‹ none ›      none · reviewer · planner                                                                │
│                                                                                                                      │
│ Enter to set · ←/→ to change · Esc to close                                                                          │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                                                               Opus 5.5 · medium effort
```

**D2. `/config` with two values changed, waiting for Enter** (80x24)

```text
  ▀▀▀▄   claude-acp · Opus 5.5
  ▄▀▀▀   ~/projects/app

› fix the flaky login test
⏺ Done.





╭──────────────────────────────────────────────────────────────────────────────╮
│ Settings                                                                     │
│                                                                              │
│   Effort      ‹ High › •                                                     │
│ ❯ Fast        ‹ On › •                                                       │
│   Ultracode   ‹ Off ›                                                        │
│   Agent       ‹ none ›                                                       │
│                                                                              │
│ Enter to set 2 · ←/→ to change · Esc to close                                │
╰──────────────────────────────────────────────────────────────────────────────╯
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                              Opus 5.5 · medium
```

**D3. `/config` with nothing to change (cursor-cloud on Cursor's default)** (80x24)

```text
  ▀▀▀▄   cursor-cloud · Claude 4.7 Sonnet
  ▄▀▀▀   ~/projects/app
  ▀▀     ? for shortcuts · /help










╭──────────────────────────────────────────────────────────────────────────────╮
│ Settings                                                                     │
│ cursor-cloud has no settings for Cursor's default.                           │
│ /model to pick a model that has some.                                        │
│                                                                              │
│ Esc to close                                                                 │
╰──────────────────────────────────────────────────────────────────────────────╯
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                                               Cursor's default
```
