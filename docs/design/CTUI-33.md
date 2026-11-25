# CTUI-33: forms, links and subagent blocks

Scope (main settled it): S1 compaction notices, S2 live terminal output, S3
elicitation forms (form and url mode, the window's dialogs replacing
today's cancel, the `-p` bridge), S4 nested ACP subagents, core only. This
design covers what S3 and S4 draw: the framework's form widget (section 1),
the port's form, link and record (section 2) and the port's subagent
blocks (section 3). S1 and S2 add no new shape: they follow the original's
drawing, checked unit by unit beside it.

Sources: ../chord/src/ui/dialogs/form.ts, Form.tsx, Link.tsx,
src/ui/transcript/agents/subagents.ts, Agents.tsx, docs/guide.md
("Question, form and link headings", "-p", "Claude launches and
messages"), and the fake's `form`, `link`, `subagent`, `subagentcall` and
`claudesubagents` scenarios. Captures of the original are under
evidence/CTUI-33/, taken with `bun dev chord --fake --qa <name>` and the
scenario typed as the prompt; the qa directory is relabelled `~/project`.

Out, as main settled: the Questions dialog (CTUI-68), plan fold (CTUI-69),
logStep and the background view, monitors, task agents (M4) and the
CHD-434 notice. The original's `background  main's 2 agents running` row
under the status line, seen in every subagent capture, is the background
view and is not drawn here.

## 1. Framework: `Form`

A form is a column of fields with a label column, a value column, a
status mark, a note under a field, and a row of buttons; the keys move
between fields, edit the focused one and submit. Any terminal app asking
for settings, a login or a deploy target needs it, so it is built in
`lib/`, knows nothing of ACP or JSON Schema, and the port only feeds it.

### Call site

```dart
final form = FormController(
  fields: [
    TextFormItem(
      name: 'name',
      label: 'Project name',
      description: 'Lowercase, dashes allowed',
      required: true,
      validator: (text) => text.length < 3 ? 'At least 3 characters' : null,
    ),
    TextFormItem(name: 'email', label: 'Contact email'),
    NumberFormItem(
      name: 'replicas',
      label: 'Replicas',
      integer: true,
      initialValue: 2,
      required: true,
      validator: (text) => inRange(text, 1, 9) ? null : 'A whole number from 1 to 9',
    ),
    BoolFormItem(name: 'public', label: 'Public', initialValue: false),
    ChoiceFormItem<String>(
      name: 'region',
      label: 'Region',
      required: true,
      options: const [
        PickerItem(value: 'eu', label: 'Europe'),
        PickerItem(value: 'us', label: 'United States'),
      ],
    ),
    MultiChoiceFormItem<String>(
      name: 'tags',
      label: 'Tags',
      options: const [
        PickerItem(value: 'web', label: 'web'),
        PickerItem(value: 'api', label: 'api'),
      ],
    ),
    UnsupportedFormItem(name: 'when', label: 'When'),
  ],
);

Form(
  controller: form,
  maxRows: 14,
  autofocus: true,
  submitLabel: 'Accept',
  declineLabel: 'Decline',
  onSubmitted: (Map<String, Object> values) => answer(values),
  onDeclined: decline,
  onCanceled: cancel,
)
```

A Flutter developer reads `Form`, `validator` returning the message or
null, `initialValue`, `onSaved`-like callbacks and a controller as with
`TextField`. Flutter's fields are widgets placed by hand; a terminal form
lines its labels up in one column and scrolls by field, so the fields are
data handed to one widget, as `PickerItem`s are to `Picker`. Choice
options reuse `PickerItem<T>`.

### Types

- `sealed class FormItem` (foundation, `lib/src/foundation/form.dart`):
  `name` (the key in the values), `label`, `description` (nullable, shown
  under the field while it has the focus), `required` (default false).
  Subclasses:
  - `TextFormItem`: `initialValue` String?, `validator` `String? Function(String text)?`.
  - `NumberFormItem`: `integer` (default false), `initialValue` num?,
    `validator` `String? Function(String text)?` given the typed text.
    Only characters a number can hold are typed (`0-9 . + -`; no point when
    `integer`). Typed text that does not parse is a problem; its words are
    the validator's when it gives any, else `Not a number` / `Not a whole
    number`. The value submitted is a `num` (`int` when `integer`).
  - `BoolFormItem`: `initialValue` bool?. Value drawn `☒ Yes` / `☐ No`.
  - `ChoiceFormItem<T>`: `options` `List<PickerItem<T>>`, `initialValue`
    T?, `validator` `String? Function(T value)?`.
  - `MultiChoiceFormItem<T>`: `options`, `initialValue` `List<T>?`,
    `validator` `String? Function(List<T> value)?`. Values are kept in the
    options' order, whatever order they were ticked in.
  - `UnsupportedFormItem`: a field the app cannot ask for; drawn
    `can't be filled in here`, dim, never set.
- `FormData` (foundation, immutable): the fields, the values (unset fields
  absent), the focus (`FormFocus.field(index)`, `FormFocus.submit`,
  `FormFocus.decline`), the cursor, the open list's highlight, the fields
  whose problems show, and `refused`. Its methods are the reducer: one per
  action in the key table below, each returning the next `FormData`;
  `problems` (name → words), `toFix` (the count the button row shows),
  `values` (what submit sends), and `rows(int limit)` (the drawn rows, see
  Scrolling). Pure Dart, tested without a widget.
- `FormController extends ValueNotifier<FormData>`: what the app holds
  so a form left and come back to keeps its values, focus and cursor (the
  port keeps one per asking agent). `FormController({required fields})`
  opens with initial values and the focus on the first field, or on the
  submit button when there are none.
- `Form` (widget, `lib/src/widgets/form.dart`): draws the controller's
  rows, buttons and hint, and binds the keys through `Actions`.
  Parameters: `controller` (required), `onSubmitted` (required,
  `void Function(Map<String, Object>)`), `onCanceled` (required, Esc),
  `onDeclined` (nullable: without it there is no second button),
  `submitLabel` (default `Submit`), `declineLabel` (default `Decline`),
  `maxRows` (the field area's rows; unbounded when null), `autofocus`,
  `focusNode`, `enabled` (default true; false draws no `❯`, no
  highlight and no hint, keeping all state, as `Picker.enabled`),
  `showHint` (default true), `onLeave` (nullable: ↓ on the buttons calls
  it, for an app with something below to go to).

No JSON Schema in `lib/`: the port turns a schema into `FormItem`s and
validators (section 2).

### Validation, as the original's

- A problem is: a required field unset (`Required`), typed text that is
  no number, or the validator's message.
- Moving through the form never turns an empty required field red. A field
  the focus leaves with any other problem shows it from then on.
- Submit with problems is refused: every problem shows, the focus goes to
  the first field with one, and the button row counts them,
  `2 fields to fix`, in the error colour, until none is left. A field
  that shows its problem is checked on every keystroke, so the words go as
  soon as it is fixed.
- Flutter's `AutovalidateMode` is not copied: there is one behaviour, the
  above.

### What it draws

The field area, one block per field (`❯` gutter, status mark, label
column, gap of 2, value):

```text
❯ * Project name   ab█                         focused: ❯ and label bold, focus colour
                   At least 3 characters       a shown problem, error colour
  ⚠ Contact email  not-an-email                ⚠ error colour: problem shown
  ✔ Replicas       2                           ✔ dim: set and valid
    Traffic share  not set                     not set, dim
  ✔ Public         ☐ No
  * Region         not set                     * error colour: required, unset
    Tags           web, api
    When           can't be filled in here     dim
```

- Status column: `*` required and unset, `⚠` a problem shown, `✔` set and
  valid, blank otherwise. A focused field with a shown problem has its
  label in the error colour instead of the focus colour.
- The label column is the widest label, at most a third of the width.
- Under the focused field: its shown problem, else its description, dim,
  starting at the value column. Under any other field: its shown problem.
- The focused text or number field shows its text with the cursor as an
  inverse cell (an inverse space at the end).
- An open list replaces the value with `▾` and hangs its options under
  it at the value column, with their own `❯` gutter: a choice numbered,
  `❯ 1. Europe`, the held one ending ` ✔`; a multi-select ticked,
  `❯ ☒ web` / `  ☐ api`. The highlighted option is in the focus colour.

Then a blank row, the buttons, a blank row and the hint:

```text
  Accept   Decline     2 fields to fix
❯ Accept   Decline                          focus on submit: bold, success colour
  Accept ❯ Decline                          focus on decline: error colour
```

The hint names the keys for where the focus is. At a width of 100 cells
or more (and when it fits) the long form, else the short:

| Focus | Long | Short |
| --- | --- | --- |
| text, number | `Type to fill in · ↑↓ to move · Enter for the next · Esc to cancel` | `Type to fill in · ↑↓ to move · Esc to cancel` |
| boolean | `Space to toggle · ↑↓ to move · Esc to cancel` | same |
| choice, multi | `→ or Space to choose · ↑↓ to move · Esc to cancel` | same |
| unsupported | `↑↓ to move · Esc to cancel` | same |
| open choice list | `↑↓ to move · 1–3 or Enter to pick · ← to close the list · Esc to cancel` | `↑↓ · 1–3 or Enter to pick · ← to close · Esc to cancel` |
| open multi list | `↑↓ to move · Space to tick · Enter or ← to close the list · Esc to cancel` | `↑↓ · Space to tick · Enter or ← to close · Esc to cancel` |
| buttons | `←→ to switch · Enter to accept · Esc to cancel` (`decline` on Decline) | same |

`Enter to accept` uses the submit label lowercased; with no decline
button the buttons hint reads `Enter to <submit> · Esc to cancel`.

### Scrolling (narrow and short)

Given `maxRows`, the field area shows whole field blocks (field, open
list, note) from the first view from the top that holds the focused block
whole; a dim `↑ N more fields` / `↓ N more fields` row, indented 4, counts
what is out of view. The rows never cut inside a block. At 80x24 the
original's form of seven fields scrolls once a list is open:

```text
    ↑ 3 more fields
    Traffic share  not set
  ✔ Public         ☐ No
❯ * Region         ▾
                   ❯ 1. Europe
                     2. United States
                     3. Asia Pacific
    Tags           not set
```

Long values and labels are cut at the box edge, never wrapped.

The limit holds only as far as the original's `formRows` (form.ts) holds
it, and no further. Where one block is taller than `maxRows` (a choice
list opened with more options than rows), the view stops at the first
block that does not fit and draws only the count of what is below, so the
focused field and its list are not shown; a limit under one still gives
that one count row. Neither "at most `maxRows` rows" nor "the focused block
always in view" is promised then. CTUI-70 (low, backlog) takes it up; this
slice keeps the original's behaviour, as the lead settled.

### States

- Empty (no fields): the buttons alone, focus on submit.
- Focused, unfocused: `enabled: false` draws no `❯` or highlight and no
  hint; the port uses it while a form is held between turns or the agents
  list has the keys.
- Overflowing: as Scrolling, with its limits there (CTUI-70).
- Narrow: short hints; the label column at most a third of the width.

### Keys

Bound with `Actions`, each with a description, so the shortcuts panel
lists them. Ids are `form.<action>`, for a `Keymap` to move them.

| Where | Keys | Description |
| --- | --- | --- |
| any | `up`, `shift+tab` | Previous field |
| any | `down`, `tab` | Next field (on the buttons, `down` calls `onLeave`) |
| field | `enter` | Next field |
| any | `escape` | Cancel |
| text, number | printable, paste | Type (pasted line breaks become spaces) |
| text, number | `left`, `right`, `home`/`ctrl+a`, `end`/`ctrl+e` | Move the cursor |
| text, number | `backspace`, `delete`, `ctrl+u`, `ctrl+k`, `ctrl+w` | Delete |
| boolean | `space` | Toggle |
| boolean, choice, multi | `backspace`, `delete` | Clear |
| choice, multi | `right`, `space` | Open the list |
| open list | `up`/`k`, `down`/`j` | Previous option, Next option |
| open list | `left`, `escape` | Close the list |
| open choice | `1`–`9`, `enter` | Pick |
| open multi | `space` | Tick |
| open multi | `enter` | Close the list |
| buttons | `left`, `right` | Switch button |
| buttons | `enter` | Submit or Decline |

`shift+up`, `shift+down`, `pgup`, `pgdn`, `ctrl+o` and `ctrl+c` are not
bound: they stay the app's (the window scrolls with them). Text editing
uses `TextEditingController`'s operations rather than a copy of them.

### Example and tests

`example/form.dart` shows the fixture's seven fields with no agent;
`--narrow` starts it with `maxRows: 8`. Widget tests through
`package:chorded_tui/testing.dart` at 120x40 and 80x24 cover each kind,
the open lists, refused submit, scrolling and `enabled: false`; the
reducer is tested as plain Dart.

## 2. The port: form, link and record

The port keeps the original's file split: `lib/ui/dialogs/form.dart` maps
an elicitation to `FormItem`s and words; `lib/ui/dialogs/form_box.dart`
and `lib/ui/dialogs/link.dart` draw the boxes. Every visible difference
below from the original is listed at the end; there are none intended.

### Schema to fields

`fieldsOf(schema)` as form.ts: properties in the order sent; label is the
`title` or the property name; `description`; required from `required`;
kind from `type` (`string` with `enum`/`oneOf` is a choice, `array` of
`enum`/`anyOf` strings is a multi-select, `integer`, `number`, `boolean`;
anything else is `UnsupportedFormItem`); defaults as `defaultOf`.

Validation: the original asks zod (`z.fromJSONSchema`) and puts chord's
words on its findings. Per AGENTS.md the port tries the pub.dev package
**`json_schema`** (Workiva, 5.2.x, draft 2020-12, `validateFormats`) first:
build one schema per form from the field schemas, validate the values, and
map each error's keyword (the end of its `schemaPath`: `minLength`,
`maxLength`, `minItems`, `maxItems`, `pattern`, `format`, `enum`, `const`,
`minimum`, `maximum`) to the original's words (`wordsFor`, `numberWords`,
`FORMAT_WORDS`: `At least 3 characters`, `Pick at most 2`,
`Must match <pattern>`, `Not an email address, such as name@example.com`,
`Not a URL, such as https://example.com`, `Not a date, such as
2026-10-06`, `Not a date and time, such as 2026-10-06T14:30:00Z`,
`Not one of the choices`, `A whole number from 1 to 9`, …). A schema the
package cannot build leaves values unchecked, as the original. If
`json_schema` does not fit under `dart compile exe` or does not report the
keyword, developer stops and the lead takes the question to main, per the
package rule; the second candidate is `json_schema_builder`.

The validator for each `FormItem` is a closure over that one schema; the
framework never sees JSON Schema.

### The form box

As Form.tsx, in the permission box's place and frame (rounded, the focus
colour, padding 1, the same held/between/away handling as
`PermissionPrompt`):

```text
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ fake asks for input                                                                                                  │
│ Set up the deploy target                                                                                             │
│                                                                                                                      │
│ ❯ * Project name                                                                                                     │
│                    Lowercase, dashes allowed                                                                         │
│     Contact email  not set                                                                                           │
│   ✔ Replicas       2                                                                                                 │
│     Traffic share  not set                                                                                           │
│   ✔ Public         ☐ No                                                                                              │
│   * Region         not set                                                                                           │
│     Tags           not set                                                                                           │
│                                                                                                                      │
│   Accept   Decline                                                                                                   │
│                                                                                                                      │
│ Type to fill in · ↑↓ to move · Enter for the next · Esc to cancel                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
```

(evidence/CTUI-33/original-form-120x40.txt; 80x24 in
original-form-80x24.txt, the same rows with the short hint.)

- Heading: the asker as the permission prompt names it, then
  `asks for input`, then ` · <schema title>` when the schema has one;
  ` · between turns` between turns.
- The message, wrapped to the box; cut with `…` where it would leave
  fewer than three rows for the fields.
- The schema's description, dim, one row, cut.
- A blank row, then `Form(maxRows: …)` with `submitLabel: 'Accept'`,
  `declineLabel: 'Decline'`, `onLeave` to the agents list where there is
  one.
- Room: the box takes at most `max(windowRows - 7, 12)` rows; the chrome
  is 8 rows plus the description's; the fields get what is left after the
  message.
- Held: the body folds under `… N more lines` with `ctrl+x a to answer`
  as the held permission does; `enabled: false`.
- The working line reads `››› Waiting for your input… (Ns)`.
- Accept sends `{action: accept, content}` with numbers as numbers;
  Decline sends `decline`; Esc (no list open) sends `cancel`.

States to capture against the original: opened (original-form-*),
invalid fields and an open choice list (original-form-invalid-list-120x40),
multi-select open (original-form-multi-120x40), refused Accept with
`2 fields to fix` (original-form-refused-120x40), focus on Accept
(original-form-accept-focus-120x40), scrolled at 80x24
(original-form-list-80x24).

### The link box

As Link.tsx, the permission box's shape:

```text
╭──────────────────────────────────────────────────────────────────────────────╮
│ fake asks you to open a link                                                 │
│ Sign in to Example to continue                                               │
│                                                                              │
│   https://example.com/oauth/authorize?client=abc&state=9f2c                  │
│   Opens example.com                                                          │
│                                                                              │
│ ❯ 1. Open in the browser                                                     │
│   2. Decline                                                                 │
│                                                                              │
│ Enter to choose · Esc to cancel                                              │
╰──────────────────────────────────────────────────────────────────────────────╯
```

(original-link-80x24.txt, original-link-120x40.txt.) The URL whole, in
the link colour, wrapped; `Opens <host>` dim with the host bold; a URL that
is not http(s) reads `Not a web link` in the error colour and offers only
`1. Decline`. The choices are the framework's `Picker` as the permission
box uses it. Open runs the terminal service's URL opener, then answers
`accept`; Esc answers `cancel`.

### The record

Once answered, the box leaves a record in the transcript, as
`ElicitationRecord`:

```text
 ⏺ fake asked: Set up the deploy target
   ⎿  Answered · 6 fields
```

ctrl+o opens the values sent, labels in a column and values as the form
showed them (`Yes`/`No`, option titles):

```text
 ⏺ fake asked: Set up the deploy target
   ⎿  Answered · 6 fields
      Project name   abc
      Contact email  ops@example.com
      Replicas       2
      Public         No
      Region         United States
      Tags           web
```

Other endings: `Declined`, `Cancelled` (error colour), `Opened <url>`
(link colour) for an accepted link. A request out of a tool call hangs
its `⎿` row under that call with no `⏺ … asked:` row.
(original-form-record-120x40, original-form-record-expanded-120x40,
original-link-form-ended-120x40.)

### `-p`

As the guide: `initialize` declares `elicitation: {form: {}, url: {}}`;
each form is declined with `chord: <agent> asked: <message> — skipped (no
one to answer under -p)` on stderr; a link is cancelled. Questions forms
(CTUI-68) are out; until then a questions form under `-p` is a form.

## 3. The port: subagent blocks

As subagents.ts and Agents.tsx; the shapes are the original's, so this
lists them with their captures and nothing new.

### A lone subagent

```text
 ⏺ Agent(Run the whole test suite)
   ⎿  Bash(bun dev test)
```

While it runs: its latest three call headlines under `⎿`, then a dim
`+N more tool uses (ctrl+o to expand)` counting earlier ones; before its
first call, `Initializing…`. Ended: one line,
`Done (1 tool use · 2s)`, `Failed`, `Cancelled`, `Disconnected`, `Ended`
or `Untracked`, the word never colour alone. The marker pulses while it
runs and takes its ending's tone. ctrl+o opens the launch prompt and its
work, indented under it, and an end note (the error, or why there is no
cause). (original-subagentcall-done-120x40,
original-subagent-expanded-120x40.)

### Spawned back to back: the tree

```text
 ⏺ Running 2 agents… (ctrl+o to expand)
   ├─ Agent(Find the session layer) · 5 tool uses
   │  ⎿  Write(notes/routing.md) · waiting for permission
   └─ Agent(Find where tool calls are drawn on screen and how they fold) · 2 tool uses · 0s
      ⎿  Failed
```

Header: `Running N agents…` while any runs, `N agents finished` when all
completed, else `N agents ended · 1 failed, 1 cancelled`, worst first.
Each row: `Agent(<title>)`, ` · N tool uses`, ` · <time>` once ended; a
row too wide wraps after a ` · ` and continues under the title's first
letter (at 80x24: `· 2 tool uses · 0s` on its own line, indented 6). Under
it, its current call (the one a permission waits on first, with
` · waiting for permission`), dim `Initializing…` before any, or its ending; a
failure's message follows on the next line at Claude's
(`API Error: 529 Overloaded`). (original-subagent-group-running-120x40,
-80x24, original-subagent-done-120x40, original-claudesubagents-120x40.)

### Claude launches and messages

```text
 → to Agent(Run the tests)
   ⎿  Run bun test and report what fails.
```

`← from Agent(<title>)` for a message back. A launch prompt folds after six
rows behind ctrl+o. A call referring to a known subagent shows
`Agent(<title>)` above its own output, once per referenced subagent.

### The asker row and the status line

A subagent's permission box opens with `Agent(<title>) asks`, nested ones
joined by ` › `, the names bold (original-subagent-permission-*). When the
turn ends with subagents still at work the status line's left side reads
`1 agent still running` / `N agents still running`
(original-subagent-still-running-120x40, -80x24).

## Differences from the original

None intended. Two points the slice leaves out, as main settled, and one
the lead settled in:

1. The `background  …` row under the status line (background view): out.
2. The Questions dialog: out (CTUI-68); a questions-shaped form draws as a
   form until then.
3. In, as the lead settled: after a subagent that outlived its turn ends,
   the transcript gains `✓ <launch prompt> · agent · done in 2s`
   (original-subagent-done-120x40), as `itemEndLines` in the original's
   src/session/transcript/subagents.ts draws it for ACP subagents; part of S4.
