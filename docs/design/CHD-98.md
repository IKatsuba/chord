# CHD-98 — Elicitation forms

During a turn, an agent can ask the person for structured input with ACP's
`elicitation/create`. The request is either a **form** (a JSON schema of flat
fields) or a **url** (a link the person is asked to open). chord shows it in the
prompt box's place, takes keys for each field, and answers `accept` with the
values, `decline`, or `cancel`.

The mocks are in `evidence/CHD-98/mock/`, at 120×40 and 80×24. Claude Code's own
dialog, which these mocks follow, is captured in `evidence/CHD-98/claude/`. Those
captures were taken from Claude Code 2.1.291 with a throwaway MCP server that sent
the request unprompted, so no prompt was sent to a model.

## What Claude Code does (the reference)

- The dialog **replaces the prompt box and the status line**. It sits under a
  full-width rule in the permission colour. The title is `MCP server "ref"
  requests your input`, then the message, then one row per field.
- Each field has a status column: `*` (required, empty), `✔` (has a valid
  value) or `⚠` (invalid). Then comes `Label: value`. Unset fields say `not
  set`; a focused empty text field says `Type something…`. Each field's
  description sits under it, dim, and **every field has a blank row after it**.
- Typing edits the focused text or number field in place, and the field is
  checked on every keystroke. `ab` in a field with a 3-character minimum is
  red before the person has finished typing.
- `→` opens an enum as a radio list (`◯`) under the field, and Space picks.
  A multi-select opens as a `☐`/`☒` list, Space ticks, Enter closes.
- Enter on a field moves to the next one. `Accept    Decline` sit at the
  bottom: ←/→ switch between them, and the focused one is green or red.
- Accept on an invalid form does nothing except move the focus to the first
  bad field.
- Esc answers `cancel`. Backspace unsets a field.
- At 80×24 the fields scroll, with `↑ 2 more above` and `↓ 4 more below`.
- After an accept or decline, **nothing is left in the transcript**.
- url mode: `MCP server "ref" wants to open a URL`, the message, the URL in
  full, and `Accept    Decline`.

What chord keeps: the shape, the status column, typing in place, inline lists,
Accept refused with a jump to the first problem, and Esc to cancel.

What chord changes, and why:

1. **No blank row between fields; one description shown at a time.** Claude
   Code's form is 22 rows for 7 fields, and at 80×24 only 3 fields fit. chord's
   form is 8 rows for 7 fields, so the whole form fits at 80×24. Only the
   focused field shows its description. Error lines always show.
2. **Labels in a column, values aligned.** This replaces `Label: value`, as
   `/config` does in chord. Values are easier to scan when they all start in
   the same column.
3. **Errors appear when the person leaves a field, not while they type.** After
   a field has shown an error, it is checked on every keystroke, so the error
   goes away as soon as the value is fixed. A required field that is empty is
   flagged only on Accept. Moving through the form never turns it red.
4. **Number fields refuse letters.** A key that cannot be part of the number is
   not typed: letters, and `.` in an integer field. Claude Code took `-l12`
   into an integer field.
5. **A record in the transcript.** chord already writes a line for each
   permission answer (`⎿  Rejected Write notes.txt`). An answered form gets one
   too, and ctrl+o expands it to show the values.
6. **Numbered list rows**, as in chord's permission prompt and pickers. `1–9`
   picks directly.
7. **url mode is a numbered choice and names the host.** The two-option
   choice looks like the permission prompt, and a `Opens example.com` line
   names the host, so a long or misleading URL cannot hide where it goes.

## Where it sits

The form takes the **prompt box's place**: the same rounded box in the
`permission` colour that the permission prompt and pickers use, directly above
the status line. Above it are the transcript and the working line, which says
`Waiting for your input… (3s)` (as `Waiting for permission…` does). The prompt
box is hidden while the form is open, so typing always goes to the field. Any
draft in the prompt box is kept and returns when the form closes. Queued `›`
rows stay under the working line.

The box's height is limited to **the window's height minus 7**. That keeps the
header and five rows of transcript visible: the person's prompt and the working
line. If the fields do not fit, they scroll inside the box, with dim
`↑ 3 more fields` / `↓ 1 more field` rows. The focused field is always
in view. An open list is always shown whole. At 80×24 the window has 8 field
rows, which is enough for the fake agent's 7 fields plus one description.

## The form

```
╭──────────────────────────────────────────────────────────────────────────────╮
│ fake asks for input                                                          │  title: bold, permission
│ Set up the deploy target                                                     │  the request's message: plain, wraps
│                                                                              │
│ ❯ * Project name   █                                                         │  ❯ focus · status · label · value
│                    Lowercase, dashes allowed                                 │  focused field's description: dim
│     Contact email  not set                                                   │
│   ✔ Replicas       2                                                         │  a default counts as a value
│     Traffic share  not set                                                   │
│   ✔ Public         ☐ No                                                      │
│   * Region         not set                                                   │
│     Tags           not set                                                   │
│                                                                              │
│   Accept   Decline                                                           │
│                                                                              │
│ Type to fill in · ↑↓ to move · Esc to cancel                                 │  dim; changes with the focused field
╰──────────────────────────────────────────────────────────────────────────────╯
```

(`80-open.txt`. The 120×40 version is `120-open.txt`.)

- **Title.** `<agent> asks for input`. ACP does not name the MCP server, only
  the agent that relays the request. If the schema has a `title`, it goes after
  the agent name: `fake asks for input · Deploy`. If the schema has a
  `description`, it goes on a dim line under the message.
- **The message** wraps to the box's width. If the message is so long that
  fewer than 3 field rows would be left, it is cut with `…`. The transcript
  record still has the whole message.
- **The status column.** `*` means required and empty. `✔` means it has a valid
  value. `⚠` means invalid. A blank means optional and empty. The `*` changes
  to `✔` once the field is filled. The title stays the same.
- **Labels.** The label is the schema's `title`, or the property name if there
  is no title. The label column is as wide as the longest label, up to a third
  of the box; longer labels are cut with `…`.
- **Values, by kind:**

  | Schema                                 | Shown as                    | Edited by                                    |
  | -------------------------------------- | --------------------------- | -------------------------------------------- |
  | `string` (with `format`, `pattern`, length) | the text, cursor `█` when focused | typing in place; ←/→, home/end, Backspace   |
  | `number`, `integer`                    | the text as typed           | typing in place; keys that cannot be part of the number are not typed |
  | `boolean`                              | `☐ No` / `☒ Yes`            | Space                                        |
  | `string` with `enum` or `oneOf`        | the option's title          | → or Space opens a numbered list under it    |
  | `array` of `enum` / `anyOf`            | the titles, joined by `, `  | → or Space opens a `☐`/`☒` list under it     |
  | any other type                         | dim `can't be filled in here` | nothing; if it is required, Accept stays refused and the person declines |

- **Unset** is shown as dim `not set`. A focused empty text field shows only
  the cursor; the hint line says `Type to fill in`.
- **Defaults** from the schema are filled in when the form opens, and count as
  values (`✔`).
- **Focus** starts on the first field. If the schema has no fields (a plain
  "go ahead?"), the form is the message and the buttons, with the focus on
  Accept.

### A list open (enum, multi-select)

```
│     ↑ 3 more fields                                                          │
│   ✔ Traffic share  0.25                                                      │
│   ✔ Public         ☒ Yes                                                     │
│ ❯ * Region         ▾                                                         │
│                    ❯ 1. Europe                                               │
│                      2. United States                                        │
│                      3. Asia Pacific                                         │
│     ↓ 1 more field                                                           │
```

(`80-enum.txt`, `120-enum.txt`, `120-multi.txt`.) The list hangs in the value
column. `❯` and the highlighted row use the permission colour, as in
`/model`. The current value is marked `✔`. In an enum list, Enter or `1–9`
picks the option and closes the list. In a multi-select, Space ticks or unticks
the highlighted row, and Enter or ← closes the list. ← or Esc closes a list
**without** cancelling the form. Esc cancels the whole form only when no list is
open. A list longer than the space available scrolls the way chord's pickers
do.

### An invalid entry, refused in place

```
│ ❯ ⚠ Project name   ab█                                                       │
│                    At least 3 characters                                     │  error colour
│   ⚠ Contact email  ops@                                                      │
│                    Not an email address, such as name@example.com            │
│   ⚠ Replicas       12                                                        │
│                    A whole number from 1 to 9                                │
│   ✔ Traffic share  0.25                                                      │
│     ↓ 3 more fields                                                          │
│                                                                              │
│   Accept   Decline     4 fields to fix                                       │  error colour
```

(`80-refused.txt`, `120-refused.txt`.) Enter on Accept with any problem sends
nothing. Every problem field gets its `⚠` and its error line. The focus jumps
to the first problem, and the button row counts the problems, including those
scrolled out of view. When a field has an error, the error line takes the
place of its description. Fixing the value removes the error on the next
keystroke, and the count updates with it.

Error wording says what is wanted, in plain words:

| Rule                     | Line                                               |
| ------------------------ | -------------------------------------------------- |
| required, empty          | `Required`                                         |
| `minLength` / `maxLength`| `At least 3 characters` / `At most 20 characters`  |
| `pattern`                | `Must match ^[a-z-]+$`                             |
| `format: email`          | `Not an email address, such as name@example.com`   |
| `format: uri`            | `Not a URL, such as https://example.com`           |
| `format: date`           | `Not a date, such as 2026-10-06`                   |
| `format: date-time`      | `Not a date and time, such as 2026-10-06T14:30:00Z`|
| `integer` with bounds    | `A whole number from 1 to 9` (`… of 1 or more`, `… of 9 or less`) |
| `number` with bounds     | `A number from 0 to 1`                             |
| `minItems` / `maxItems`  | `Pick at least 1` / `Pick at most 2`               |

The check itself goes through a library (see the end of this sheet). These
lines are chord's wording for the library's results.

### On the buttons

(`120-ready.txt`, `80-ready.txt`.) `❯ Accept` is bold in the `success` colour.
`❯ Decline` is in the `error` colour. ←/→ switch between them. Enter on Accept
answers `accept`, with the values in their schema types: numbers as numbers,
booleans as booleans, enums as their `const`. Fields left unset are not sent.
Enter on Decline answers `decline`.

## After the answer: the transcript

The form closes, the prompt box returns with its draft, and the turn goes on.
The transcript gets one record, which is the permission answer's shape:

```
 ⏺ fake asked: Set up the deploy target
   ⎿  Answered · 7 fields                       success colour

 ⏺ Elicitation answer: accept                    ← the fake agent's echo
   {"name":"web-app","email":"ops@example.io","replicas":3,"ratio":0.25,
   "public":true,"region":"us","tags":["web","worker"]}
```

- `⎿  Answered · 7 fields` is in the success colour. `⎿  Declined` (Decline)
  and `⎿  Cancelled` (Esc, or ctrl+c) are in the error colour, like
  `Rejected`.
- If the request names a `toolCallId`, the `⎿` line goes under that tool
  call, as a permission's line does, and there is no separate `⏺`.
- ctrl+o shows the values, one per row, label and value, in the same columns
  as the form (`120-accepted-expanded.txt`).

Screens: `120-accepted.txt`, `80-accepted.txt`, `120-declined.txt`,
`80-declined.txt`, `120-interrupted.txt`.

## Esc and ctrl+c

- **Esc** answers `cancel` to the form. The turn goes on, because the agent
  decides what to do with a cancelled form. This is how Esc on the permission
  prompt answers that prompt and does not stop the turn.
- **ctrl+c** cancels the turn, as it always does. acpx aborts the open request
  through the handler's `signal`, and the form closes. The record says
  `⎿  Cancelled`, and the turn ends with chord's `Interrupted by user`. A form
  that closes because its signal aborted (the turn ended for any reason) leaves
  the same record.

## url mode

```
╭──────────────────────────────────────────────────────────────────────────────╮
│ fake asks you to open a link                                                 │  bold, permission
│ Sign in to Example to continue                                               │  the message
│                                                                              │
│   https://example.com/oauth/authorize?client=abc&state=9f2c                  │  link colour, whole, wraps; never cut
│   Opens example.com                                                          │  dim; the host is bold
│                                                                              │
│ ❯ 1. Open in the browser                                                     │
│   2. Decline                                                                 │
│                                                                              │
│ Enter to choose · Esc to cancel                                              │
╰──────────────────────────────────────────────────────────────────────────────╯
```

(`80-url.txt`, `120-url.txt`.) This is the permission prompt's shape: a
numbered choice where `1`/`2`, ↑/↓ and Enter work as they do there. **chord
opens nothing until the person presses a key.** Option 1 opens the URL with the
system's opener and answers `accept`; option 2 answers `decline`; Esc answers
`cancel`. The URL is printed whole, wrapping if it has to, and is never cut.
The record after an accept is `⎿  Opened <the URL in full>` in the link colour
(`120-url-opened.txt`). It sits outside any box, so someone without a browser
on this machine (for example over ssh) can copy it from the transcript. The
host line uses the URL's parsed hostname. A URL that does not parse, or that is
not `http`/`https`, gets `Not a web link` in the error colour, and only option
2 is offered.

## Keys

All of these go into `src/ui/keys.ts` under a "Forms" group, so the shortcuts
panel lists them.

| Key                | Where                         | Does                                           |
| ------------------ | ----------------------------- | ---------------------------------------------- |
| ↑ / ↓, shift+Tab / Tab | fields and buttons        | previous / next field                          |
| Enter              | a field                       | next field (the last field goes to Accept)     |
| typing             | a text or number field        | edits it in place                              |
| ← / →, home / end  | a text or number field        | moves the cursor                               |
| Backspace          | a text or number field        | deletes back; emptying the field unsets it     |
| Backspace          | a boolean, enum or multi-select | unsets it                                    |
| Space              | a boolean                     | toggles it                                     |
| → or Space         | an enum or multi-select       | opens its list                                 |
| ↑ / ↓, 1–9, Enter  | an open enum list             | moves; picks and closes                        |
| Space / Enter or ← | an open multi-select list     | ticks; closes                                  |
| ← or Esc           | an open list                  | closes it, form stays                          |
| ← / →              | the buttons                   | Accept / Decline                               |
| Enter              | Accept / Decline              | answers `accept` (if valid) / `decline`        |
| Esc                | anywhere, no list open        | answers `cancel`                               |
| ctrl+c             | anywhere                      | cancels the turn, which aborts the form        |
| 1 / 2, ↑ / ↓, Enter | url mode                     | open / decline                                 |

The hint line shows the keys that matter for the focused field:

| Focus                  | Hint (120 / 80)                                                                  |
| ---------------------- | -------------------------------------------------------------------------------- |
| text, number           | `Type to fill in · ↑↓ to move · Enter for the next · Esc to cancel` / without `Enter for the next` |
| boolean                | `Space to toggle · ↑↓ to move · Esc to cancel`                                   |
| enum, multi, closed    | `→ or Space to choose · ↑↓ to move · Esc to cancel`                              |
| enum list open         | `↑↓ to move · 1–3 or Enter to pick · ← to close the list · Esc to cancel` / `↑↓ · 1–3 or Enter to pick · ← to close · Esc to cancel` |
| multi list open        | `↑↓ to move · Space to tick · Enter or ← to close the list · Esc to cancel`      |
| buttons                | `←→ to switch · Enter to accept · Esc to cancel` (`to decline` on Decline)       |

## Colours (theme roles; nothing new)

| What                                            | Role                       |
| ----------------------------------------------- | -------------------------- |
| border, title, `❯`, focused label, list highlight | `permission`             |
| `*`, `⚠`, error lines, the fix count, focused Decline, `Declined`/`Cancelled` | `error` |
| focused Accept, `Answered`                      | `success`                  |
| the URL, `Opened <url>`                         | `link`                     |
| `✔`, `not set`, descriptions, hints, scroll markers, `Opens` | dim (SGR 2)   |
| message, labels, values                         | the terminal's own colour  |

A focused label is bold in the permission colour, or in the error colour if
the field is invalid. Because no text is painted except with these roles, the
form reads in both dark and light terminals, as CHD-87 says for the rest of
chord.

## Modes chord declares

`elicitationModes: ['form', 'url']`, on the runtime. These are the two modes
this sheet draws. acpx answers `cancel` to any other mode by itself.

## The fake agent

Two scenarios, in the same style as the others:

- **`form`** sends `elicitation/create` in form mode with the message `Set up
  the deploy target` and these fields, one of each kind:
  - `name`: string, `Project name`, required, 3–20 characters, described as
    `Lowercase, dashes allowed`
  - `email`: string, `Contact email`, format `email`
  - `replicas`: integer, `Replicas`, required, 1–9, default 2
  - `ratio`: number, `Traffic share`, 0–1, described as `Share of traffic sent
    here, from 0 to 1`
  - `public`: boolean, `Public`, default false
  - `region`: string `oneOf` Europe/United States/Asia Pacific (`eu`/`us`/`ap`),
    `Region`, required
  - `tags`: array of `enum` `web`/`api`/`worker`, `Tags`

  Then it replies `Elicitation answer: <action>`, followed by the content as
  one line of JSON when the action is accept.
- **`link`** sends url mode with `Sign in to Example to continue` and
  `https://example.com/oauth/authorize?client=abc&state=9f2c`, and replies the
  same way. QA should check only Decline and Esc against it, because option 1
  really opens a browser.

## Libraries

These are for the engineer to try first. I tried only the validation.

- **Validation: zod is already in the tree.** `z.fromJSONSchema` in jsr
  `@zod/zod` 4.6 builds a validator from the requested schema.
  I ran it on `{n: integer 1–9, e: email}` with `{n: 12, e: 'x'}` and it
  reported both issues, each with its path (`Too big: expected number to be
  <=9`, `Invalid email address`). The issue codes map to the lines in the
  table above. `ajv` is in the npm cache but not in `deno.lock`, so it would be
  a new dependency for the same job.
- **Form widgets to try:** `ink-form` 2.0.2 (Aug 2026; peers `ink >=4`,
  `react >=18`). Its v2 README says it dropped multi-select, and it draws its
  own section chrome, so check whether it can be made to look like this sheet
  before using it. `@inkjs/ui` 2.0 has `TextInput`, `EmailInput`, `Select`
  and `MultiSelect`. decisions.md passed over its `TextInput` and `Select`
  already (the ctrl keys, and the numbered rows). `ink-select-input`, which is
  in the tree, already draws chord's numbered lists, and
  `react-ink-textarea`, also in the tree, is chord's text input.
