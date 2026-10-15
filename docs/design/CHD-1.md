# CHD-1: questions an agent asks the person

The owner's verdict: questions an agent asks through a form look broken.
This document sets out how claude and codex ask a question today, what
chord shows of it, and the layout for a question box. **The owner chose
option A** (2026-10-14): one question at a time. Each note is paired with
its question by the adapters' own marks, and every adapter's form is
brought to one canonical question shape by an enricher.

The captures of today are in `evidence/CHD-1/`, as text (`.txt`) and with
colour (`.ansi.txt`). Each directory is a `mktemp -d`. In the claude
captures the header's directory was rewritten to `/tmp/chord-qa.cndT`,
because the original path names the machine. The mocks are in
`evidence/CHD-1/mock/`. They are laid out to exact width by a script, as
the box and the status line under it. Above the box the window stays as it
is today. The example options' descriptions are invented, because the
capture shows only the labels.

Live runs, one prompt each, on the owner's account (2026-10-14):

- **claude** (claude-agent-acp 0.87.0, auto mode): `Use AskUserQuestion to
  ask me two short questions with options, then stop.`
- **codex** (codex-acp 2.1.1, `/config` Collaboration mode → Plan first,
  since `request_user_input` is offered only in Plan): `Ask me one
  multiple-choice question with your question tool, then stop.`
- **fake**: the `form` scenario, the baseline for any other schema.

## What each agent sends

The schemas are developer's reading of the adapters.

| | How it asks | Each question | Its own answer | Required | Message |
|---|---|---|---|---|---|
| **claude** | `AskUserQuestion` → elicitation form, plus a tool call `Asking(for your input)` listing the questions | `question_<n>`: `title` = short header, `description` = question text (with one question, the text is the form's `message`), `oneOf` options with `title` and optional `description`; multiSelect as `array` of `anyOf` | `question_<n>_custom`, titled `Other`: "Type your own answer, or add a note to the option you chose above (optional)." | none | "Please answer the following questions." |
| **codex** | `request_user_input` → elicitation form, Plan mode only, **no tool call in the transcript**; times out on its own | `<id>`: `title` = question text, `description` = short header, `oneOf` options and sometimes `None of the above`; no options means a plain text question | `<id>_note`, "Additional answer or note", `_meta.codex.role: user_note` | every question | "Codex needs your input to continue." |
| **fake** `form` | elicitation form | one field of each kind (text, email, integer, number, boolean, `oneOf`, `array` of `enum`) | — | three | "Set up the deploy target" |
| **factory-droid** 0.236.0 | elicitation form, only to a client with `elicitation.form` | `question_<i>`: `title` = topic, `description` = question, `oneOf` `{const: "option_<k>", title: label}` and a last `{const: "other", title: "Other answer"}`; multi as `array` of `anyOf`, `minItems` 1, `uniqueItems`; no options means a string with `minLength` 1 | `question_<i>_other`, titled `<topic>: Other answer`, optional | every question | "Droid needs your answers to continue." |
| **opencode** (main HEAD) | elicitation form; without the capability the model is told to ask in its reply | `q<i>`: `title` = header, `description` = question, `oneOf` / `anyOf` with option descriptions | `q<i>_custom`, titled `(other)` | none | "Questions" |
| **zeroclaw** | elicitation form with `form`; else a permission request whose option ids are `choice-i` | one field, `choice` (`title` "Choice", `oneOf` `{const: "choice-i"}`), or `choices` as an array | none | `choice` | — |
| **qwen-code** 0.25.0 | `session/request_permission` with Submit / Cancel; the questions in `toolCall._meta.qwenQuestions` `[{question, header, options[{label, description}], multiSelect}]` | as listed there | — | — | — |
| **grok-build** 1.0.50 | extension request `x.ai/ask_user_question`, only when the session's `_meta` opts in, so a plain ACP client never gets it | — | — | — | — |
| **cursor** | extension request `cursor/ask_question` `{questions[{id, prompt, options[{id, label}], allowMultiple}]}`, answered with `selectedOptionIds` | as listed there | none | — | — |
| **dimcode** | elicitation form, as claude's, with `_meta.lody` | as claude's | `__custom_<i>` | — | — |
| **dirac** | elicitation form | one choice, `optionId`; its `Other answer` opens a second form with one `text` field | the second form | — | — |
| **minimax-code** | elicitation form; without the form capability a permission request | `<id>`: `title` = question, `description` = the step's description | `<id>__other` | — | — |
| **devin** | elicitation form, per its changelog; closed source | unknown | unknown | — | — |
| **poolside** | probably an elicitation form (medium confidence); closed source | unknown | unknown | — | — |
| **qoder** | permission request: the question as text, Allow / Reject only, so the answer picked cannot go back | — | — | — | — |
| **pi-acp** | permission request with `choice-<i>` options, for its extensions' selects only | — | — | — | — |
| **autohand** | permission request with select options, only under `AUTOHAND_PERMISSION_MODE=external` | — | — | — | — |
| **codebuddy-code** | extension request `_codebuddy.ai/question`, only to a client that declares it | — | — | — | — |
| **nova** | extension request `session/requestUserInput` | — | — | — | — |

The rows below claude's are developer's reading of each agent's published
source. Only claude, codex and the fake were run.

- **goose** and **fx** only pass MCP servers' elicitations on. These are
  forms of any schema, and keep today's table.
- **No question under ACP.** Any question these agents ask comes as plain
  reply text, which chord already shows:
  - gemini, cline and kilo turn their question tool off.
  - auggie and kimi decline the tool themselves. It shows as a tool call,
    and the model is told the person dismissed it.
  - github-copilot-cli declines it too (high confidence).
  - minion-code tells its model to ask in its reply.
  - openclaw has only exec approvals.
  - glm-acp-agent, sigit, deepagents and fast-agent never ask.
  - agoragentic has no sessions at all.
- **Unknown, closed source:** kiro and junie. Neither is installed here.
  One live prompt each would settle them.

How each of these maps onto the canonical shape is developer's, in "The
canonical question shape". An agent that asks through a form with marks of
its own gets an enricher. Any other form keeps the generic table.

What chord does today beyond the forms:

- **qwen-code.** chord shows a Submit / Cancel permission with no
  questions in it. Its answer wants a top-level `answers` object
  (`{"0": "text"}`), which ACP's permission response does not have.
  Showing the questions and sending that object is an owner's call: it is
  adapter-specific, and no box layout settles it.
- **grok-build and cursor.** Their extension requests are not answered as
  questions by chord. Whether chord should take either is out of this
  design.

Four form senders share one shape: claude, codex, factory-droid and
opencode. Each sends a choice field with its question, followed by a
free-text field that goes with it. They split title and description two
ways, though:

- claude, factory-droid and opencode put the short header in `title`.
- codex puts the question there.

factory-droid also carries its own `Other answer` as a last option, beside
its `_other` field. Its options' `const` is an id, not the label, so a
record must show the option's `title`. zeroclaw's single `choice` field
needs no pairing at all.

## What chord shows today

claude, `claude-open-120x40.txt`:

```
│ claude asks for input                                                                                                │
│ Please answer the following questions.                                                                               │
│                                                                                                                      │
│ ❯   Language   not set                                                                                               │
│                Which language should helper scripts use?                                                             │
│     Other      not set                                                                                               │
│     Verbosity  not set                                                                                               │
│     Other      not set                                                                                               │
│                                                                                                                      │
│   Accept   Decline                                                                                                   │
│                                                                                                                      │
│ → or Space to choose · ↑↓ to move · Esc to cancel                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ⏵⏵ auto mode on (shift+tab to cycle)                         Default (recommended) · medium effort · 4% context used
```

- **The options are hidden.** The question shows as a field set to
  `not set`. Its options open only on → or Space
  (`claude-options-120x40.txt`), as a dropdown, and their descriptions are
  dropped. Enter or ↓ on the field skips it.
- **The question text is a dim line under the focused field only.** With
  any other field focused, the form shows two headers, `Language` and
  `Verbosity`, and nothing to say what they ask.
- **Each `Other` floats.** Nothing ties it to its question, and its
  description ("add a note to the option you chose above") shows only
  while the field is focused (`claude-down1-120x40.txt`).
- **Rows drift right** once a dropdown has been open
  (`claude-closed-80x24.txt`, `claude-down3-120x40.txt`), and the fake's
  generic form does it too (`fake-form-region-80x24.txt`). Form.tsx keeps
  a stale indent on rows keyed by index.

```
│ Please answer the following questions.                                       │
│                                                                              │
│ ❯   Language   not set                                                       │
│                Which language should helper scripts use?                     │
│                    Other      not set                                        │
│                    Verbosity  not set                                        │
│     Other      not set                                                       │
│                                                                              │
│   Accept   Decline                                                           │
│                                                                              │
│ → or Space to choose · ↑↓ to move · Esc to cancel                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ⏵⏵ auto mode on (shift+tab to cycle)         Default (recommended) · 4% used
```

- **Accept and Decline** carry no mark until focused. After that, the hint
  is the only place that says what Enter does.
- **The record** reads `Answered · 2 fields` (`claude-answered-120x40.txt`).
  The second field is called `Other`, and only ctrl+o shows which question
  each answer went to. The adapter's own result line above it is cut in
  the middle of a sentence.

codex, `codex-options-80x24.txt` and `codex-filled-80x24.txt`:

```
╭──────────────────────────────────────────────────────────────────────────────╮
│ codex asks for input                                                         │
│ Codex needs your input to continue.                                          │
│                                                                              │
│   ✔ What would y...cus on next?Review existing work                          │
│                                ❯ ✔ Additional answer or note  tests first    │
│                                                                              │
│   Accept   Decline                                                           │
│                                                                              │
│ Type to fill in · ↑↓ to move · Esc to cancel                                 │
╰──────────────────────────────────────────────────────────────────────────────╯
  ⏵⏵ auto review mode on (shift+tab to cycle)          6.1 Sol · medium effort
```

- codex's question text is the field's label, so at 80 columns it is cut
  in the middle (`What would y...cus on next?`), and the value runs into
  it with no gap. The header (`Next step`) is the dim line.
- The record hangs under the prompt as `Answered · 2 fields`. codex shows
  no tool call, so nothing in the transcript says what was asked.
- The answer did reach both agents. claude replied "Got it: Deno
  (TypeScript) for scripts, and terse one-line replies." and codex replied
  "Review existing work, with tests first." **The flow works today. The
  problem is how it reads.**

## What the question box decides

- **When a form is drawn as questions.** A form is drawn as questions when
  an enricher has brought it to the canonical shape. Any other form, such
  as the fake's with its numbers and its boolean, keeps today's field
  table, with only the drifting indent fixed:

```
╭──────────────────────────────────────────────────────────────────────────────╮
│ fake asks for input                                                          │
│ Set up the deploy target                                                     │
│                                                                              │
│     ↑ 3 more fields                                                          │
│     Traffic share  not set                                                   │
│   ✔ Public         ☐ No                                                      │
│ ❯ * Region         ▾                                                         │
│                    ❯ 1. Europe                                               │
│                      2. United States                                        │
│                      3. Asia Pacific                                         │
│     Tags           not set                                                   │
│                                                                              │
│   Accept   Decline                                                           │
│                                                                              │
│ ↑↓ · 1–3 or Enter to pick · ← to close · Esc to cancel                       │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts            Fake Large with a 1M context window · medium effort
```

- **Which text field is a question's note. The owner chose 2, the
  adapters' marks.** claude,
  codex, factory-droid and opencode all send each note right after its
  question. These are the ways to tell a note from a plain text question:
  1. **By order.** A text field that follows a choice field is drawn as
     that question's `Note`. It uses no adapter names, but it is a reading
     of the order. It misses one case: codex's text question, the one with
     no options, is followed by a note too, and this rule would draw that
     note as a question of its own.
  2. **By the adapters' marks.** The marks are claude's `<key>_custom`,
     opencode's `q<i>_custom`, factory-droid's `question_<i>_other` and
     codex's `_meta.codex.role: "user_note"`, which is the only one of the
     four that is not a key suffix. This is exact, but it ties the box to
     four adapters and needs a change for every new one.
  3. **No pairing.** Every text field is a question of its own, titled by
     its own title, so claude's would read `Other`. This is the honest
     reading, and it looks the way the owner complained about.
- **Header and question text.** The question text is the body, and the
  short header is a label, drawn as a step chip. Each adapter's enricher
  knows which of `title` and `description` is which. Three of the four put the header in `title`: claude,
  factory-droid and opencode. codex alone swaps them.
- **Note.** The note is optional unless the schema requires it. Its
  description is shown dim in the empty field, as a placeholder. It does
  not replace a picked option. Both adapters send it alongside the pick.
- **Required.** A required question carries `*` on its label, as today.
  Sending with one unanswered is allowed only as Skip.
- **Colours** (`src/ui/theme/theme.ts`): the border and title in
  `permission`, as the permission prompt and today's form use. `❯` and
  the focused option in `permission`. A step's `✔` in `success`. Option
  descriptions, the note's placeholder and the hint are dim. The question
  text is bold, in the terminal's own foreground. `*` is in `warning`.
- **Esc** cancels the form, as today. For claude that aborts the tool.
  **Skip** is the form's Decline (claude reads it as skipped).
- **The record in the transcript** says what was asked and what was
  answered, one row per question. For claude it stands in for the
  adapter's cut result line under `Asking(…)`. ctrl+o restores every line
  of the adapter's result, each cut at the width as every tool's output
  already is. Wrapping them is a follow-up outside this slice. For codex
  the record is the only trace of the question:

```
 ⏺ Asking(for your input)
   ⎿  Language   Deno (TypeScript) (Recommended)
      Verbosity  Terse, one line

 › Ask me one multiple-choice question with your question tool, then stop.
   ⎿  codex asked · Next step  Review existing work · tests first
```

  A skipped question reads `skipped`, and a declined form `Skipped`. A
  cancelled form reads `Cancelled`, as today.

## The layout, option A (chosen): one question at a time

This is the layout of Claude Code's AskUserQuestion. A row of steps runs
along the top, one per question and then Submit, and the box below shows
one question as the permission prompt shows its choices: numbered, `❯` on
one of them, with each option's description dim under it. The note sits
under the options.

```
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ claude asks you 2 questions                                                                                          │
│                                                                                                                      │
│ ← ◉ Language   ○ Verbosity   ○ Submit →                                                                              │
│                                                                                                                      │
│ Which language should helper scripts use?                                                                            │
│                                                                                                                      │
│ ❯ 1. Deno (TypeScript) (Recommended)                                                                                 │
│      Runs from source with inline npm: and jsr: imports, no package manager                                          │
│   2. Python                                                                                                          │
│      Only where a library has no JS or TS equivalent                                                                 │
│                                                                                                                      │
│   Note  type your own answer, or add to the one picked (optional)                                                    │
│                                                                                                                      │
│ Enter to pick · 1–2 · ↑↓ to move · ←→ or Tab for the questions · Esc to cancel                                       │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ⏵⏵ auto mode on (shift+tab to cycle)                           Default (recommended) · medium effort · 4% context used
```

```
╭──────────────────────────────────────────────────────────────────────────────╮
│ claude asks you 2 questions                                                  │
│                                                                              │
│ ← ◉ Language   ○ Verbosity   ○ Submit →                                      │
│                                                                              │
│ Which language should helper scripts use?                                    │
│                                                                              │
│ ❯ 1. Deno (TypeScript) (Recommended)                                         │
│      Runs from source with inline npm: and jsr: imports, no package          │
│      manager                                                                 │
│   2. Python                                                                  │
│      Only where a library has no JS or TS equivalent                         │
│                                                                              │
│   Note  your own answer, or add to the one picked (optional)                 │
│                                                                              │
│ Enter to pick · ↑↓ · ←→ questions · Esc to cancel                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ⏵⏵ auto mode on (shift+tab to cycle)           Default (recommended) · 4% used
```

Keys:

- ↑ and ↓ move through the options and the note.
- Enter on an option picks it and goes to the next step. A digit picks
  that option and goes on.
- On the note, typing fills it and Enter goes to the next step.
- ← and → (and Tab or shift+Tab) move between steps without picking.
- Esc cancels.

The step chips mark where the person is: `◉` for the current step, `✔`
for one answered, `○` for one not yet answered.

The note focused, on the second question:

```
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ claude asks you 2 questions                                                                                          │
│                                                                                                                      │
│ ← ✔ Language   ◉ Verbosity   ○ Submit →                                                                              │
│                                                                                                                      │
│ How verbose should responses be?                                                                                     │
│                                                                                                                      │
│   1. Terse                                                                                                           │
│      One line where one line will do                                                                                 │
│   2. Detailed                                                                                                        │
│      Reasons and alternatives with each answer                                                                       │
│                                                                                                                      │
│ ❯ Note  Terse, one line▏                                                                                             │
│                                                                                                                      │
│ Enter for the next · ↑ to the options · ←→ or Tab for the questions · Esc to cancel                                  │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ⏵⏵ auto mode on (shift+tab to cycle)                           Default (recommended) · medium effort · 4% context used
```

multiSelect: the options are `[ ]` and `[✔]`, and Space toggles one.
Enter goes on, because a pick does not end a multi-choice question:

```
╭──────────────────────────────────────────────────────────────────────────────╮
│ claude asks you 2 questions                                                  │
│                                                                              │
│ ← ✔ Language   ◉ Checks   ○ Submit →                                         │
│                                                                              │
│ Which checks should run before a commit? (pick any)                          │
│                                                                              │
│ ❯ [✔] 1. Types                                                               │
│   [ ] 2. Lint                                                                │
│   [✔] 3. Tests                                                               │
│                                                                              │
│   Note  your own answer, or add to the ones picked                           │
│                                                                              │
│ Space to toggle · Enter for the next · ↑↓ · Esc to cancel                    │
╰──────────────────────────────────────────────────────────────────────────────╯
  ⏵⏵ auto mode on (shift+tab to cycle)           Default (recommended) · 4% used
```

Submit lists the answers and offers Send or Skip. With a required question
left unanswered, Send is not offered: the row says so, and the step's chip
stays `○`.

```
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ claude asks you 2 questions                                                                                          │
│                                                                                                                      │
│ ← ✔ Language   ✔ Verbosity   ◉ Submit →                                                                              │
│                                                                                                                      │
│ Language   Deno (TypeScript) (Recommended)                                                                           │
│ Verbosity  Terse, one line                                                                                           │
│                                                                                                                      │
│ ❯ 1. Send the answers                                                                                                │
│   2. Skip these questions                                                                                            │
│                                                                                                                      │
│ Enter to choose · ←→ or Tab for the questions · Esc to cancel                                                        │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ⏵⏵ auto mode on (shift+tab to cycle)                           Default (recommended) · medium effort · 4% context used
```

codex, with its one required question (`*`) and its note:

```
╭──────────────────────────────────────────────────────────────────────────────╮
│ codex needs your input to continue                                           │
│                                                                              │
│ ← * ◉ Next step   ○ Submit →                                                 │
│                                                                              │
│ What would you like to focus on next?                                        │
│                                                                              │
│ ❯ 1. Plan a change (Recommended)                                             │
│   2. Review existing work                                                    │
│   3. Explain a topic                                                         │
│   4. None of the above                                                       │
│                                                                              │
│   Note  Additional answer or note                                            │
│                                                                              │
│ Enter to pick · 1–4 · ↑↓ · ←→ questions · Esc to cancel                      │
╰──────────────────────────────────────────────────────────────────────────────╯
  ⏵⏵ auto mode on (shift+tab to cycle)           Default (recommended) · 4% used
```

```
╭──────────────────────────────────────────────────────────────────────────────╮
│ codex needs your input to continue                                           │
│                                                                              │
│ ← * ○ Next step   ◉ Submit →                                                 │
│                                                                              │
│ Next step  no answer yet, and codex needs one                                │
│                                                                              │
│   1. Send the answers                                                        │
│ ❯ 2. Skip these questions                                                    │
│                                                                              │
│ Enter to choose · ←→ questions · Esc to cancel                               │
╰──────────────────────────────────────────────────────────────────────────────╯
  ⏵⏵ auto mode on (shift+tab to cycle)           Default (recommended) · 4% used
```

A single question still gets a Submit step. Otherwise Enter would send the
answer before the note could be written. *Alternative:* on a single
question with no required note, Enter on an option sends it at once, as
the permission prompt does.

Why: it is the layout claude's own users already know, and each question
reads like a permission prompt, at full width. It is the tallest per
question (about 14 rows at 80×24) but never scrolls, because there is one
question on screen at a time. Its cost: the person sees one question at a
time, so the review comes at Submit.

## Not chosen: B and C

**B**, every question in one scrolling box, had all the answers in view,
but at 80×24 two questions with descriptions already scrolled. **C**, the
field table fixed, was the least to build, but it still read as a form and
kept the options hidden until opened. The mocks stay in
`evidence/CHD-1/mock/` (`B-*.txt`, `C-*.txt`).

## The canonical question shape

This section is developer's proposal, with the screen choices settled
here. Each adapter's enricher (`src/session/enrichers.ts`) leaves the
agent's request as it was sent. It only adds `params._meta["chord/questions"]`
and names that key in `chord/filled`.

Why under `_meta`:

- **ACP's shape both sides:** the request stays a valid ACP request
  whatever reads it.
- **No way back is needed:** the questions keep the agent's own field ids,
  so the window builds the answer in those ids.
- **One answer path:** whatever ignores the key, such as the generic form
  or an old record, still answers the same schema.

```ts
// _meta["chord/questions"]
interface Questions {
  agent: 'claude' | 'codex' | 'droid' | 'opencode' | 'dimcode' | 'dirac';
  questions: Question[];
}
interface Question {
  id: string;           // the field id of the pick, or of the text answer
  header?: string;      // the step chip's label
  text: string;         // the question itself, always set
  multiSelect: boolean;
  required: boolean;    // from requestedSchema.required
  secret?: boolean;     // codex's isSecret
  options: Option[];    // empty: a plain text question, answered in `id`
  own?: OwnAnswer;      // the free-text answer that goes with it
}
interface Option {
  value: string;        // the const sent back
  title: string;
  description?: string;
  preview?: string;     // claude's _meta preview
}
interface OwnAnswer {
  field: string;        // the free-text field id
  mode: 'beside' | 'instead' | 'withValue';
  value?: string;       // withValue: the option taken out of `options`
  placeholder?: string; // the field's description
}
```

### Marks per agent

| agent | keys on | header / question | own answer | mode |
|---|---|---|---|---|
| claude | `question_<n>` + `question_<n>_custom` titled `Other`, nothing else | title / description, or `message` for a lone question | `question_<n>_custom` | `beside` |
| codex | `params._meta.codex`; the note's `_meta.codex.role: "user_note"` + `questionId` | description / title | the note, by `questionId` | `beside` (see below) |
| droid | its message, `question_<i>` with consts `option_<k>`, `question_<i>_other` | title / description | `question_<i>_other`, with `other` taken out of the options | `withValue` |
| opencode | message `Questions`, `q<i>` + `q<i>_custom` titled `(other)` | title / description | `q<i>_custom` | `beside` |
| dimcode | `params._meta.lody.elicitation`; `__custom_<i>` with `customAnswerFor` | title / description | by `customAnswerFor` | `instead` |
| minimax-code | — | — | — | none in this slice: the generic form |
| dirac | one required `optionId` with the const `__dirac_other_answer` | `message` / none | the option itself; its text comes in a second form | `withValue`, no field |

The enrichers are tried in the order of the table, and the first whose
marks all match wins. The marks are exact: key patterns, `_meta` keys, and
fixed message strings. A matched form with a field the enricher cannot
place gets no `chord/questions` at all, so nothing a person must fill in
is ever hidden. Any doubt means no enricher, and the generic form.

### The answer

`answerOf(questions, picks)` (`src/session/questions.ts`) builds the
content in the agent's ids:

- the pick goes to `content[q.id]`, an array for multiSelect;
- the own text goes to `content[own.field]`;
- with `instead`, the pick is left out;
- with `withValue`, `own.value` is put in `q.id` too, or added to the
  array for multiSelect;
- a question with no answer is left out.

Send is `accept` with that content, Skip is `decline`, and Esc is
`cancel`. The schema's own constraints are still checked against
`requestedSchema` by today's zod path, which catches droid's `minLength`
and `minItems` and codex's `required`.

### What each part looks like

- **`beside`** (claude, opencode, codex): the `Note` row under the
  options, as in the mocks above. Typing in it keeps the pick, and both
  are sent.
- **codex is `beside`, always.** Developer proposed `withValue` on "None of
  the above" when that option is present. But the live run sent a pick
  *and* a note (`Review existing work` + `tests first`), and codex took
  both. A note bound to "None of the above" would lose that. So "None of
  the above" stays an ordinary option, and the note stays beside it.
- **`withValue`** (droid, dirac): the option taken out comes back as the
  last numbered row, with a text field inline: `3. Other answer: ▏`.
  Moving `❯` onto it and typing picks it. Picking any other option keeps
  the text but no longer sends it. Enter goes to the next step.

```
╭──────────────────────────────────────────────────────────────────────────────╮
│ droid needs your answers to continue                                         │
│                                                                              │
│ ← ◉ Storage   ○ Submit →                                                     │
│                                                                              │
│ Where should uploads be kept?                                                │
│                                                                              │
│   1. Local disk                                                              │
│   2. S3 bucket                                                               │
│ ❯ 3. Other answer: a shared NFS mount▏                                       │
│                                                                              │
│ Type your answer · Enter for the next · ↑↓ · Esc to cancel                   │
╰──────────────────────────────────────────────────────────────────────────────╯
  ⏵⏵ auto mode on (shift+tab to cycle)           Default (recommended) · 4% used
```

- **`withValue` with multiSelect:** the row is a checkbox, ticked exactly
  while its text is not empty. On that row every key types, Space
  included, so typing ticks it and clearing the text (Backspace, ctrl+u)
  unticks it. Space toggles only the option rows:

```
╭──────────────────────────────────────────────────────────────────────────────╮
│ droid needs your answers to continue                                         │
│                                                                              │
│ ← ✔ Storage   ◉ Formats   ○ Submit →                                         │
│                                                                              │
│ Which formats should be accepted? (pick any)                                 │
│                                                                              │
│   [✔] 1. PNG                                                                 │
│   [ ] 2. JPEG                                                                │
│ ❯ [✔] 3. Other answer: HEIC▏                                                 │
│                                                                              │
│ Type your answer · Enter for the next · ←→ questions · Esc to cancel         │
╰──────────────────────────────────────────────────────────────────────────────╯
  ⏵⏵ auto mode on (shift+tab to cycle)           Default (recommended) · 4% used
```

- **`instead`** (dimcode): it looks the same as `withValue`, but its last
  row reads `N. Your own answer: ▏`. Typing clears the pick, and picking
  clears the `❯` from the row (the text stays, and is not sent).
- **A plain text question** (no options): the body is a single text row,
  `❯ ▏`, with its placeholder dim.
- **`secret`** (codex): the text is drawn as `•`, one per character, and
  the record reads `(hidden)`.
- **codex's `autoResolutionMs`:** the title line says `answers itself in
  4:32`, right-aligned and dim, turning `warning` under 30 s. When the time
  runs out, codex withdraws the request, and chord sees that as it sees a
  cancel. The box closes, and the record reads `Timed out` only when the
  countdown had reached 0, and `Cancelled` otherwise. It never claims the
  agent answered, which chord cannot see.

```
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ codex needs your input to continue                                                            answers itself in 4:32 │
│                                                                                                                      │
│ ← ✔ Next step   ◉ Token   ○ Submit →                                                                                 │
│                                                                                                                      │
│ Paste the API token for the staging deploy.                                                                          │
│                                                                                                                      │
│ ❯ ••••••••••••▏                                                                                                      │
│                                                                                                                      │
│ Type your answer · Enter for the next · ←→ or Tab for the questions · Esc to cancel                                  │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ⏵⏵ auto mode on (shift+tab to cycle)                           Default (recommended) · medium effort · 4% context used
```

- **No header** (dirac, codex's header-less questions): the chip
  reads `Question 1`, `Question 2`, and so on. A lone question still gets
  its chip and the Submit step.
- **`preview`** (claude): not drawn in this slice. The option's title and
  description carry the choice. Previews are for a later task.
- **dirac's second form:** for v1, as developer leans, (a): the `{text}`
  form is drawn as a generic one-field form, as today. Option (b), which
  remembers the "Other" and folds the second form into the same step,
  can come later.
- **The record** reads each question's header and the picked option's
  *title* (droid's const is an id), then the own text after ` · `, as in
  the record mock above. An older record has no `questions` and draws as
  today. A form no adapter's marks read keeps none of its values in the
  file, as nothing says which of them is a token or a password: reopened,
  it reads accepted, with no values.

### Outside the forms (the owner's choices, 2026-10-14)

- **qwen-code, cursor and nova** go to a task of their own. qwen-code's
  answer needs a top-level `answers` that ACP's permission response does
  not have. cursor and nova ask through extension requests, which today
  get method-not-found. Until that task, qwen-code keeps today's Submit /
  Cancel.
- **minimax-code, devin and poolside** stay on the generic form: no
  enricher for them in this slice.
- **qoder:** today's permission box. The pick cannot go back.
- **pi-acp, autohand, zeroclaw as a permission:** these are ordinary
  permission options already, and work today.
- **codebuddy-code and grok** ask only a client that opts in, and chord
  does not.
- **`-p`** answers every form `decline`, so claude reads it as skipped
  and the turn goes on, as `-p` refuses permissions. It prints one
  stderr line per question, `claude asked: <question> — skipped (no one
  to answer under -p)`, and `claude asked: <message> — skipped` for a
  generic form.

### Settled while building unit 4

- **The heading** is `<agent> asks you N questions`, or `<agent> asks you
  a question` for one, for every agent. The agent's own message is not
  shown, except where it is claude's lone question text. Where the mocks
  read "codex needs your input to continue" or "droid needs your answers
  to continue", this heading is the one that holds.
- **Submit with a required question unanswered:** Send is drawn dim and
  the `❯` skips it. The summary row says `<header>  no answer yet, and
  <agent> needs one`. Enter on Skip declines.
- **A text row** (a note, an own answer, a typed question) is edited at its
  end, as today's form fields are: Backspace, ctrl+u and ctrl+w. ←→ still
  move between the questions.
- **A digit on a multiSelect** toggles that option and does not move on.
- **Enter on a typed question's row** goes to the next step.
- **Tab with nothing picked** moves on, and the step stays `○`.
- **The required `*`** stands before its step's chip (`* ◉ Next step`), in
  `warning`.
- **A step taller than the box's rows** (the owner's pick, 2026-10-15)
  shows a window of whole rows:
  - `↑ N more` and `↓ N more` count the options cut off, as the generic
    form and the pickers do;
  - the `❯` row is always in view;
  - an option's description is never shown without its title;
  - where the focused option's description still does not fit, it is cut
    at its end with `…`;
  - there is no scrollbar.

  OpenTUI's `<scrollbox>` was tried and did not fit: it starts mid-option
  and draws a scrollbar. `<tab-select>` did not fit the step chips either:
  it cuts names and loses the per-state colours.

## Keys and the shortcuts panel

The question box is a widget, like the permission prompt, so its keys are
the widget's own and are listed with the permission prompt's entries in
`src/ui/shortcuts/keys.ts`:

- ↑↓ — option
- 1–9 — pick
- Enter — pick / next
- ←→ Tab — question
- Space — toggle (multi)
- Esc — cancel

None of them is rebindable, as none of the permission prompt's is.
