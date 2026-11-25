# CTUI-21: the M1 window

Scope: replace the interim window with the original app layout, pure key
steps, quit, shortcuts, transcript failures and crash screen. CTUI-40 and
CTUI-14 share the branch but add no screen design here. No M2 features,
keybindings file or generated actions. Sources are ../chord/src/ui/app/,
src/ui/shortcuts/, and docs/design/CHD-468.md. CTUI-13, CTUI-17, CTUI-18,
CTUI-20 and docs/decisions.md retain their contracts unless changed below.
There is no CTUI-19 design file; CTUI-17 contains its theme extension design.

## 1. Framework boundary (first unit)

```dart
ErrorBoundary(
  onError: (error, stackTrace) => rememberCrash(error, stackTrace),
  errorBuilder: (context, error, stackTrace) => CrashScreen(
    error: error,
    stackTrace: stackTrace,
    onQuit: quitAfterCrash,
  ),
  child: const ChordWindow(),
)
```

Export ErrorBoundary from chorded_tui.dart. Constructor: const, key,
required Widget child, required Widget Function(BuildContext, Object,
StackTrace) errorBuilder, optional void Function(Object, StackTrace) onError.
Flutter has no subtree boundary widget: child, errorBuilder (as Image uses)
and onError use its usual naming; the framework supplies no error wording.

Catch synchronous descendant framework drawing failures: initial mount and
build, later rebuild, layout (including lazy children), and paint. The
nearest enclosing boundary replaces its failed child with errorBuilder's
widget, using the original object and stack. Remove failed subtree focus,
actions, timers and render objects before accepting fallback input. Notify
onError once per failure, outside layout/paint; do not repeatedly rebuild
the failed subtree. The fallback is latched until the boundary is removed
or its key changes. Updating child alone does not retry. An error thrown
by errorBuilder/onError or the fallback itself goes to an outer boundary,
then the existing root error path; it cannot loop in the same boundary.
Boundary-owned errors and asynchronous/session failures are not descendant
drawing errors. No global zone that turns a failed prompt into a crash.
No log is printed over the alternate screen by this boundary.

The fallback receives the boundary's parent context, with its surviving
Theme; it must not depend on inherited values inside the removed child.
App theme selection wraps the boundary so its error color survives.
Empty/focused/overflowing/narrow child states are unchanged until failure.
The boundary draws no frame, binds no keys and adds no shortcut itself.

Required framework checks: initial and subsequent build failures; layout,
lazy layout and paint failures; nearest nested boundary; same error/stack;
one callback; failed focus/actions removed; resize of fallback; key-based
replacement; fallback/callback failure escaping to outer/root; unrelated
async errors retain their existing path. Supply a small runnable framework
fixture for the API look at 120x40 and 80x24, including fallback resize.
Terminal rendering needs no external package.

### Port crash rows

Use pure crashRows(error, stackTrace, columns, rows) and CrashRow roles as
in original crash.ts. Top blank row; two-cell indented word-wrapped
error.toString in error color; stack frames dim and cut on the right with
Unicode …; blank; dim hint:

```text
  any key to quit · chord prints the error to stderr as it exits
```

At both 120x40 and 80x24 the intended port is the original capture's block,
with native Dart frames replacing JS frames. Main approved this difference:
keep native #N frame text, two cells before it, original cut/height rules;
do not invent JavaScript at frames. Error types/messages remain Dart's.
A no-stack thrown value has no frame rows. Preserve explicit newlines and
hard-break a word longer than width minus two. Frames never wrap.

When height runs short, port crash.ts's exact priority: remove bottom
frames, keep a dim `      … N more frame(s)` row where it fits; then drop
that count, blank rows (top first), then bottom message rows with … on the
last kept row; the hint goes last. Width/height zero must draw safely.
No crash title, frame, editor or status row. Blank remaining cells.

Any KeyEvent, including Enter/Esc/control/arrows, quits once. Paste and a
modifier alone do not. An ordinary Binding cannot represent any key:
use a fallback Focus key handler, with the documented any-key shortcut in
the port catalog. After terminal restoration and owned session shutdown,
print the original error and stack to stderr and exit 1, once. Session
prompt failures remain transcript entries and do not enter this screen.

Live original captures: evidence/CTUI-21/original-crash-{120x40,80x24}.*.
They use the original CrashBoundary and renderer with a temporary throwing
child, matching tests/ui/app/Crash_test.tsx; deterministic fixture frames
avoid machine paths. No source in ../chord was changed. Target mocks:

```text
120x40                           80x24
                                 
  StateError: window failed         StateError: window failed
  #0 Throws (fixture.dart:1:1)      #0 Throws (fixture.dart:1:1)
                                 
  any key to quit · chord prints the error to stderr as it exits
```

Verify wrap, missing/long stacks and shrinking below the full block, keys,
paste, once-only quit and stderr after exit. Runtime acceptance is pending
developer handover; these target rows are a design mock.

## 2. Framework shortcuts access (second unit)

```dart
KeyHelp.builder(
  builder: (context, bindings, pendingChord) => M1Shortcuts(
    bindings: bindings,
    pendingChord: pendingChord,
  ),
)
```

Add a named KeyHelp.builder constructor, with key and required builder:
Widget Function(BuildContext, List<Binding>, List<KeyCombo>). Keep the
existing KeyHelp constructor and drawing defaults unchanged. This uses
the same FocusManager activeBindings and pendingChord as default KeyHelp;
apps do not reach through context.owner. Pass unmodifiable snapshots,
closest scope first, enabled entries only, shadowed identical chords
removed, same ordering as default KeyHelp. Rebuild when focus, bindings,
enabled state or pending chord changes. The builder gets all active
bindings, not only the pending-prefix matches; it decides presentation.
Binding and KeyCombo are already public; no second binding registry.

The port maps those bindings to its editorial catalog, retaining catalog
wording/order and only supported M1 actions. Main chose this original M1
subset over printing every editor command. Context-specific permission
bindings come from the same declarations the permission widget registers;
keep the catalog when help temporarily covers a permission. No copied key
map in the window. A test covers every registered app action with a catalog
entry and every catalog key with a real binding, across the M1 contexts.
Ordinary text editing and the crash screen's any-key handler are explicit
original exceptions, not missing app bindings. Do not claim raw text input
or cursor motion is an unlisted app action.

Framework checks: nearest/outer scope precedence, disabled and changed
bindings, focus changes, pending chord changes/cancel/completion, stable
snapshot immutability, default KeyHelp unchanged, builder disposal.
The API itself adds no keys, visual state or default geometry; custom
content owns its empty/overflow/narrow presentation at both sizes.

### U14a: unfinished chord timeout

Lead added the original's CHORD_WAIT_MS behavior to the framework:
`defaultChordTimeout = Duration(seconds: 3)`. A named Duration chordTimeout
parameter on runApp, AppHost, BuildOwner and FocusManager uses that single
default. An app can write `runApp(const App(), chordTimeout: const
Duration(seconds: 3))`; no second port timer or recognizer is introduced.
Each valid prefix restarts the wait. Completion, rejection, scope change
and disposal cancel it; expiry clears pending keys and updates KeyHelp.
This adds no action, shortcut or geometry. Developer uses fake_async1.3.3
as a dev dependency for timing checks; no runtime package is added.

## 3. Quit (third unit)

AppState holds quitArmed (false or ctrl+c); pure keys returns arm/quit/clear
steps. QUIT_WINDOW_MS is 2000. Empty means exactly the empty string, not a
trimmed draft: spaces are a draft. First Ctrl+C with an empty draft sets
quitArmed, closes help and starts one cancellable timer. A second Ctrl+C
before it lapses quits. At 2000 ms dispatch quit_disarmed; a later Ctrl+C
arms again. Cancel the timer on disarm, disposal and exit; stale timer
callbacks cannot disarm a newly mounted window.

Ctrl+C on a nonempty draft clears it and its failed-input state, restores
cursor to START, and disarms; it neither interrupts a turn nor arms quit.
The next Ctrl+C on that now-empty prompt is the first quit press. While a
turn is running with an empty next draft, the same two-press rule applies.
Esc remains the interrupt key. Ctrl+D with an empty draft quits immediately,
including during a turn or while help is open; with a draft it does nothing.
Do not let TextArea consume it as forward-delete in this window. On quit,
use existing owned shutdown before process exit; never simply exit a key
callback leaving an agent alive.

The one-row status left slot, two cells in, replaces its ordinary hint:

```text
  Press ctrl+c again to quit
```

The armed message stands alone: suppress right-hand model, effort, mode
and context facts until it expires or clears. This corrects the initial
design after U13's original/port capture comparison; original Status.tsx
explicitly sets alone while armed. No modal, transcript entry, countdown,
bright border or extra row. The original
keeps arming until timeout or draft-clear; do not disarm merely on an
unrelated navigation key. The empty prompt retains focus and geometry.
Original screenshots at both sizes are original-armed-*; target text and
placement are identical, with the header difference resolved in section 7.

Required cases: exact deadline before/after, repeated arming, draft of
spaces, clear while armed, running turn, queued prompts, help closes on arm,
Ctrl+D on empty/draft, shutdown once, timer cleanup and late callback.

## 4. M1 shortcuts (fourth unit)

Port lib/ui/shortcuts/keys.dart holds the editorial catalog and pure
shortcutLine, inColumns, columnCount and panelRows. state.dart holds help,
panelOverflows and pending-key state, with pure toggle/close/overflow
reduction. Closing clears panelOverflows and its held scroll. No settings
file/keymap loader. Framework Actions owns chord recognition and its
pending timeout; do not run a second chord recognizer in the port.

Use this M1 subset, in original order. Keys are display names; each row
maps to its real Binding declarations and aliases, never a second handler.

| Display key | Original description retained for M1 |
| --- | --- |
| enter | to send |
| shift or \ + enter | for a newline |
| alt + ← → | to move by word |
| ↑ ↓ | for prompts |
| pgup pgdn | to scroll |
| shift + ↑ ↓ | to scroll a line |
| home end | for the top and the bottom |
| esc | to interrupt |
| ctrl + o | for verbose output |
| ctrl + c | to clear input |
| ctrl + d or ctrl + c | twice to quit |
| ctrl + x a | for what waits on you |
| 1–9 | to pick a choice |
| ↑ ↓ j k | to move or change a value |
| enter | to pick the highlighted choice |
| esc | to reject a permission |
| esc | to leave a picker or shortcuts |
| ? | for shortcuts |
| any key | to quit the crash screen |

Keep Ctrl+O already implemented by CTUI-16; do not build new verbose-view
features. The newline row covers Shift/Alt/Ctrl+Enter and Ctrl+J plus
backslash then Enter as CTUI-17 does. Page/Home/End include shifted twins.
Ordinary editing/undo stays available through framework Actions/KeyHelp
but off this editorial panel, as the original omits standard editor keys.
The crash row names the fallback's any-key handler, an explicit exception
to a finite Binding. Digits list only positions a nonempty picker can take.
Catalog coverage tests enumerate registered app actions over idle, running,
permission/held, help and start-picker contexts; every app binding must
map to a row, and every row key must reach its declared handler in at least
one applicable context. Account for aliases in grouped entries. A context
that cannot currently invoke a choice is not permission to remove that
supported M1 action from the global list. The same declarations feed actual
Actions and catalog lookup; do not keep a second executable key map.

Recorded differences, settled by main through the lead: remove unsupported
clauses instead of advertising dead actions. `↑ ↓ for prompts, agents,
background` loses agents/background until the M4 children/background tasks;
`esc to interrupt or stop a command` loses the shell clause until M2 bash;
`esc ← to leave a picker or shortcuts` loses ← (original Help and Select
bind only Esc), with background navigation restoring it in M4;
`↑ ↓ j k ← → to move or change a value` loses value-changing arrows until
CTUI-22 config options; `pgup pgdn or wheel to scroll` loses wheel until
terminal mouse input is implemented. Keep the original quit line verbatim:
its “twice” applies to Ctrl+C; Ctrl+D is immediate. Other omitted original
rows belong to M2/M3/M4 (commands, mentions, steering, history search,
selection, bash, modes, vim, images, editor, sessions, forms and children).
The compact header's `/help` alias likewise waits for slash commands.

At most three columns, read down each column before moving right.
inColumns uses ceil(entryCount / max(1, columnCount)). Choose the greatest
count up to three whose complete rows fit: left padding 2, column gaps 3,
column widths equal their widest line in terminal cells. No right padding.
If none fits, use one column. panelRows pads each cell to its column width,
joins by three spaces and trims trailing spaces. Entries are dim, one row
each, no title/frame/selection. Narrow content is cut at the edge, never
wrapped. No alignment based on UTF-16 length.

The panel floats over the lower transcript/working/plan rows. Its bottom
edge is immediately before the prompt's existing blank margin, so opening
it moves neither prompt nor transcript scroll. Fill the layer's background;
no transcript shows through its blank cells. A dim horizontal rule on top
starts at column 1 and ends one cell before the right edge. Available rows
are the anchor's actual distance from screen top, minus that one rule row.
The panel's left indent is two cells. Keep prompt and status visible.

Overflow uses the original permission requestView/requestStep/hiddenRows/
requestRule rules already ported for CTUI-18, with dim up/down hidden-row
rules and counts. Keys pageup/pagedown, shifted twins, shift+up/down,
home/end and shifted twins scroll the overflowing panel first, then an
active overflowing permission, otherwise transcript. A panel that fits
leaves scroll keys to the transcript. Resize recomputes columns and clamps
top; close/reopen starts at top. Zero room paints no rows and no fabricated
choice. An 80x24 M1 panel may fit: do not force overflow merely because
the full original panel overflows. Check overflow with reduced room or
narrower width using real supported rows.

`?` only toggles help on a draft exactly empty; otherwise it types literally.
Toggle/close preserves draft/cursor and prompt focus; `?` does not leak into
the draft. Esc closes help before rejecting permission or interrupting.
At an empty draft, the status left hint is `? for shortcuts`, two cells in,
using the existing StatusLine budget and dim style. Armed-quit and existing
higher-priority waiting notices replace it. With a draft the hint is absent.
The hint remains while help is open, as in the original captures.

Original help at 120x40 is three columns; at 80x24 it is two columns with
`── ↓ 5 lines below · pagedown to scroll ──` at its lower edge. These are
full-original baseline captures, not target M1 row counts. Source mock of
the same M1 target geometry at both sizes (exact columns derive from width):

```text
 ──────────────────────────────────────────────────────────────────────────────
  enter to send                         ctrl + o for verbose output
  shift or \ + enter for a newline      ctrl + c to clear input
  ...                                   ...

╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                              model · effort
```

Tests: catalog coverage both ways; column thresholds/cell widths/empty;
help toggle on empty versus spaces/text; draft/focus retained; dismissal
precedence; normal/armed/waiting status hints; all scroll destinations;
resize/clamp/reopen/zero room. Capture both sizes and real overflow.

## 5. Pure key steps (fifth unit)

example/chord/lib/ui/app/keys.dart owns the port's key decisions and ordered
effects; no Widget, FocusNode, controller, timer or session object enters it.
Keep the original names Step, KeyContext and keySteps. Dart uses sealed
Step subclasses and immutable final fields, as CTUI-15 does for actions.

```dart
final steps = keySteps(chord, KeyContext(
  state: state,
  history: history,
  rows: rows,
));
for (final step in steps) {
  play(step);
}
```

KeyContext holds current plain AppState (including draft/cursor, help,
permission/held and quit state), History and actual window rows. No vim,
images, home-directory lookup, child selection, splash or submitting-path
fields. Lead settled U9: keySteps accepts the framework Chord; a single
key is a one-combo Chord. Each Binding passes its registered chord, already
matched by Actions, so the port adds neither a terminal parser nor a second
chord recognizer. keySteps returns ordered List<Step>; no matching app
action returns an empty list and leaves text editing to TextArea.

Cursor is a typedef of int: the TextAreaController's grapheme offset,
not the original JavaScript UTF-16 line/column pair. Lead approved this
native coordinate difference. Keep a why-comment at the typedef explaining
that the steps and controller share one grapheme coordinate, avoiding a
second cursor representation and conversion. ShowDraft text/cursor and
history restoration use that same unit.

M1 Step variants (names mirror original discriminators):

- Dispatch(AppAction action): pure reducer update, including armed/help/
  expanded/attention and scroll state actions.
- ShowDraft(String text, Cursor cursor): replace text and cursor together.
- History(History history): replace the pure history value.
- Send(String text): call the conversation's existing send/queue path.
- Interrupt(): withdraw queue/restore draft before cancellation through
  CTUI-15/17's existing path, exactly once.
- RejectPermission(String id): reject the shown, active request.
- ChoosePermission(String id, String optionId): choose the identified
  permission option through the existing conversation.choose path.
- ScrollRequest(ScrollStep step), ScrollPanel(ScrollStep step): apply to
  their owned scroll controller; transcript scrolling is a Dispatch step.
- Quit(): enter the existing once-only owned shutdown path.

Dart class names may be prefixed where History collides with its data type;
keep their semantic names in tests. Framework Actions remains responsible
for matching keys/chords, enabled scopes and descriptions. Binding callbacks
call keySteps with the press they represent and current context, then play
its steps; no second if/switch for key semantics in the window. TextArea's
own editor Actions retain ordinary editing and undo/redo. Submit, newline
continuation, history edges and untouched recall call pure submitSteps,
olderSteps/newerSteps beside keySteps; preserve CTUI-17's behavior rather
than reimplementing it in a widget callback. Framework handles unmatched
printable input once. Every app action in the catalog comes through this
module, including permission attention, help and expanded transcript.

Precedence: crash fallback is its own removed-tree path; in the normal
window Ctrl+C/D use section 3; Esc closes help before permission rejection
or turn interruption; scroll keys choose overflowing help, active overflowing
permission, then transcript. A held permission cannot answer/reject or take
focus until Ctrl+X A attends it; preserve CTUI-18's behavior. `?` toggles only
on empty. Permission digits/navigation/Enter remain the framework Picker's
Actions; chooseSteps receives the request id and selected option id and
returns ChoosePermission(id, optionId), rather than parsing those keys
again. Lead approved this effect variant in U9: it completes the pure
choice-intent requirement without moving picker navigation into the port. The window plays state changes before effects
that depend on them. For Esc interrupt, queued prompts return oldest first,
then existing draft, separated by LF; use one existing owner of withdrawal,
not both ShowDraft plus another independent restore.

### U14b: runtime printable-key delegation

Lead settled one framework seam before U14: TextArea adds nullable
`bool Function(KeyEvent)? shouldHandleKey`, default null (existing behavior).
It is read for the current event before printable insertion; false delegates
the printable key to enclosing Actions instead of editing the controller.
The predicate reads live controller state, not a value captured during build.

The port's `?` Binding stays registered and enabled. The prompt predicate
delegates `?` only when the controller text is exactly empty; with any draft,
including spaces, TextArea inserts native `?` with its normal cursor/undo
behavior. No dynamic Binding.enabled, stale build-time unhandledKeys switch,
manual question-mark insertion or undo workaround. The empty-draft app
binding reaches keySteps and toggles help without inserting text.

This replaces the initial design's disabled-binding clause. It must work
for `draft?` arriving in one input batch and for `?` immediately after a
Ctrl+C clear, before a rebuild. Framework tests cover live predicate reads,
unchanged default insertion and delegation; port tests cover those two
same-frame sequences, spaces, native insertion/undo and empty help toggle.
No new key or shortcut is introduced. The API gets its own fixture look
before reviewer; U14's panel screen remains a separate handover.

Leave up/down to visual-row movement until TextArea reaches a history edge.
No transient typed question mark or duplicate submit.

Main's settled pending-status line is `ctrl+x …  a the one that waits · esc
never mind`, with no right-hand model/effort/mode/context facts. Use the
framework pending snapshot and three-second timeout. Completion, rejection
or timeout restores the ordinary status line. Esc cancels only the pending
chord; it must not also interrupt a turn, close help or reject a permission.
The original's `b a code block` clause is omitted until code-block selection
lands, under the same M1 trimming rule as the panel. This clarifies the
initial design, which named pending keys without specifying their suffix.

Use the original pure leaderLine/leaderWidth policy, driven by live
KeyHelp active-binding snapshots: full wording, then short wording, then
drop whole items from the end until they fit. A standalone port LeaderLine
uses actual available status cells; do not send this rich line through
StatusLine's middle truncation. Held/follow-up key names are plain and the
descriptions/separators dim. At40 window columns (36 status cells), M1 says
`ctrl+x …  a waits`; at20 and12 columns, drop the a item and retain the held
prefix. Only the held prefix itself may clip when it cannot fit.

Main chose clipping-only behavior at12 columns: keep `ctrl+x …` where it
fits, rather than reproduce the original's `ct...…` rendering slip. This
recorded fix changes no key behavior. For future small visible slips of
the original with no behavior behind them, the lead settles the fix and
records it in decisions.md and the final report; no new main question is
needed under main's delegated policy.

Main also explicitly chose native `draft?` insertion when it arrives in one
input burst. The original may toggle help and restore an empty draft from
stale state in that case; the runtime controller predicate is a deliberate
fix of that slip, not a same-burst parity claim. Keep native insertion and
undo rather than recreating the original race. Main owns the decisions-log
entry for this choice.

Focused pure tests assert complete ordered steps for empty/draft/running/
permission/held/help and overflow states, Ctrl+C timing inputs (time owned
outside reducer), Ctrl+D, Esc priority, Ctrl+O, attention, every scroll alias,
question mark versus ordinary text, submit/continuation/history/queue and
unhandled keys. Widget tests prove the registered Actions reach these
steps once, without duplicate text edits, and catalog coverage matches them.

## 6. Failed-prompt error row (sixth unit)

A session/prompt failure already reaches ErrorEntry through CTUI-15's
ResultAction(turnId, TurnFailed(message, code)); FailedAction separately
appends ErrorEntry. There is no Failed ConversationEvent class. Keep these
existing reducer paths rather than adding a duplicate failure event or
error-entry implementation. The original drawing route is `failed` reducer
→ `kind: error` → TranscriptEntry Failure. Lead approved dropping U10 code;
U12 verifies the failed-prompt window against the original fake and fixes
geometry/styles only if that runtime comparison finds a difference.
Do not derive it from startup failure, thrown render errors or a widget's
local Future catch. Keep its ordering after user/reply/tool entries of that
turn, preserve message text, and append once. The transcript owns its
lifetime: typing/clearing a new draft must not delete historical failures.
Existing startup refusal and bounded stderr presentation keep their own path.

Failure uses normal transcript spacing (a blank row before the entry),
one-cell outer inset, red/error-role `⏺` in the two-cell marker gutter and
message after it. The message wraps as text in the remaining width, with
continuations under the message, never under the marker. Preserve explicit
newlines and the existing ANSI renderer's semantics; do not add `Error:`,
agent name, retry key, box or stack. Plain theme draws the same geometry
without color. Like every entry it participates in transcript measurement,
following, scroll and resize. No new action or shortcut.

Original and target at both window sizes, with blank remaining rows:

```text
 › error

 ⏺ About to fail.

 ⏺ The fake agent failed on purpose.
```

See original-error-{120x40,80x24}.{txt,ansi}. The original `error` fake
scenario creates this state; `turnfailed` also supplies the model-overload
case. Verify message identity, single ordered row, long/multiline/Unicode
wrapping, plain/error colors, follow versus held scroll and resize. A turn
that fails keeps the window and prompt usable and never shows CrashScreen.

## 7. Window layout (last unit)

Main approved bringing the original compact header into this slice, using
CTUI-20's header/mark/path pieces. It is the transcript's first entry,
scrolling with it; remove the pinned interim `chord v… · agent · directory`
line. This supersedes CTUI-18's documented pinned-header difference.
No M3 splash, notification, title, theme chooser or resumed-session header.

Normal screen order, top to bottom, as App.tsx's M1 flow:

1. Expanded transcript viewport, with one cell of horizontal padding:
   compact startup header then transcript entries. Its below/new-lines
   indicator consumes the existing last viewport row when needed.
2. Working line, only while CTUI-19 says to show it, then bounded live plan,
   then the bounded queued prompts; all keep their existing rules.
3. Active permission prompt (or its held state), per CTUI-18, including its
   request scroll, choices and hint; no invented modal presentation.
4. Zero-height help anchor at the lower edge of those areas. Its overlay
   may cover earlier rows up to the screen top without resizing the
   transcript or pushing later rows. This is before the prompt margin.
5. The prompt's existing blank margin, rounded dim frame and TextArea,
   with CTUI-17's height/gutter/scroll rules; held permission leaves the
   prompt editable, active permission owns input as already specified.
6. Status row, height one, horizontal padding two: help/pending/armed/wait
   left, read-only model/effort/mode/context facts right, existing priority
   and width selection. No leftover interim quit hint or Connected row.

Header: one outer cell, the four-row original mark, three cells between
mark and text, available text width = columns − 2 − mark width − 3.
Four text rows: `chord v<port version>` (only chord bold), agent optionally
followed by ` · <started model>`, directory cut from the left at a path
boundary, `? for shortcuts`. Other header runs are dim; mark follows the
existing palette/plain policy. Cut text rows on the right as the original,
never substitute the large start-page wordmark. Read the initial model
from existing reported facts; do not grow a settings or model-selection
feature. The port version remains its own. Omit the original's ` · /help`
until the M2 slash-command task provides it (recorded M1 subset difference).

When transcript fits, its header starts at the top and unused cells stay
below its content. Once it overflows while following, keep the newest rows
at the bottom, so the header scrolls away. Scrolled back, retain the
original anchoring/follow/new-lines policy already implemented by CTUI-16.
Do not port mount.ts: the existing framework virtualization decision stands.
No extra spacer/header row remains pinned after the header leaves view.

Original / target schematic at both 120x40 and 80x24 (not a runtime result):

```text
original                              target M1
 █▄     chord v0.71.0                   █▄     chord v0.0.1
 ▀██▄   fake · <reported model>         ▀██▄   fake · <reported model>
 ▄██▀   <directory>                    ▄██▀   <directory>
 █▀     ? for shortcuts · /help         █▀     ? for shortcuts

 [transcript; blank rows while short]   [same placement/follow behavior]
 [working, plan, queue, permission]     [same M1 rows, when present]
 [help layer, when open]               [M1 catalog overlay, when open]

╭──────── full window width ────────╮  ╭──────── full window width ────────╮
│ › <draft>                         │  │ › <draft>                         │
╰───────────────────────────────────╯  ╰───────────────────────────────────╯
  ? for shortcuts       model/facts     ? for shortcuts       model/facts
```

At 120x40 prompt text width is 114 and its cap ten editable rows; at 80x24
it is 74 and cap eight. A one-row draft takes only one row, leaving the
transcript the rest. Actual parent constraints can reduce it. Existing
plan/queue/request caps adapt to window rows. Preserve CTUI-18's reason
and choice visibility instead of clipping to keep decoration. Extremely
short/zero-size windows use the already designed widgets' safe clipping
and no-focus-with-no-surface policies; do not add an independent window
minimum size or warning screen.

Look at empty/focused, running and streaming, failed prompt, armed quit,
help fitting/overflowing, long draft, active/held permission, queue and
plan, scrolled transcript and resize in both themes where color matters.
The whole composition must remain readable at both requested sizes.
Developer hands each exact screen commit and fixture/scenario to designer;
no unhanded code is reviewed. Passing looks go to reviewer with saved
captures, not directly to tester. This document does not assert the future
port has passed any look. No packages are needed for window composition,
app key decisions or reuse of existing cell layout APIs.

## Follow-ups

CTUI-19, narrow plan truncation: at20x40 a completed plan row shows
`☒Writ...hange` in the original and `☒ Writ...ange` in the port. Both
required sizes match. Lead settled that this is outside the current error
row/layout acceptance, does not block this slice, and changes nothing here;
main receives it as a follow-up. Evidence: u12-*-wrap-20x40 and its
side-by-side comparison. Do not silently alter the original's separator
policy in CTUI-21.
