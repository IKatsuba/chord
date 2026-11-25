# CTUI-20: text truncation from the start (C1)

This design specifies only the additive framework function needed by the
start page. The port's start screen and its responsive steps follow the
original's Start.tsx and layout functions; they are not redesigned here.

## Call site and API

```dart
Text(truncateStart(title, availableCells));
Text(truncateStart(title, availableCells, ellipsis: '...'));

String truncateStart(String text, int width, {String ellipsis = '…'});
```

Export through the same public text surface as truncate. Naming and
arguments parallel that existing function. There is no new TextOverflow
mode: the port computes its directory string with cutPath before drawing
Text, as the original does.

The result takes at most width terminal cells. For nonpositive width it
is empty. Otherwise, text that fits is returned unchanged, including any
ANSI escapes, as truncate does. When text is cut, strip its ANSI escapes
and keep the longest contiguous suffix of whole grapheme clusters that
fits after the leading ellipsis. Measure both suffix and marker with the
framework's cell-width functions; never split a combining sequence,
joined emoji or wide grapheme to fill the budget. Stop at the first
preceding grapheme that cannot fit, rather than skipping it to take an
earlier one.

When the marker alone fills or exceeds the width, return its longest
whole-grapheme prefix that fits the cell budget. A two-cell marker cannot
be squeezed into one cell. An empty marker is valid and leaves the whole
budget for the suffix. These are cell budgets, not counts of characters
or UTF-16 units. No space, slash or path policy belongs in this function.

```text
Input         Width  Result
abcdef        4      …def
abcdef        1      …
abcdef        0      (empty)
abcdef        3      def       (ellipsis: '')
abcdef        2      ..        (ellipsis: '...')
界abc         3      …bc
abcdef        1      (empty)   (ellipsis: '界')
```

## Start-page use and appearance

The original's src/ui/pickers/mcp.ts cutPath first truncates at the start,
then looks for a retained slash after the marker. If that slash follows a
partial component and is not the last character, it keeps the marker and
suffix from the slash. Preserve that exact rule in the port; do not teach
the framework about paths. The original start page uses cutPath through
its version line, independently of whether the art is full, compact,
a single line or absent.

At 120x40 and 80x24, a fitting directory remains intact. A long directory
loses its least telling left side, retaining whole trailing components
when a slash survives. These are small illustrative string mocks, not
whole-window captures or runtime evidence:

```text
120x40, fitting:  project/packages/terminal
80x24, fitting:   project/packages/terminal
Either, cut:     …/packages/terminal
```

The framework function adds no focus, keys, selection, cursor, empty-state
message or narrow-window fallback. An empty string stays empty; overflow
is the leading marker plus suffix. A focused screen draws the same text.
C3's live comparison must prove the original's art-to-line-to-picker
steps and directory cutting at both standard sizes and smaller windows.

## Verification and why

C1 checks cover fitting/empty input, positive/zero/negative budgets,
leading-marker suffix retention, empty/custom/wide markers, ANSI input,
CJK, combining clusters and joined emoji. Every result must obey its cell
budget. This is terminal text measurement using the existing characters
package; no new dependency or package trial is required.

A separate function is the smallest addition beside truncate; the
original's cli-truncate position:start behavior supplies the direction.
The port retains its own separator-aware selection. Existing end/middle
truncation and callers remain unchanged.

## C4 prerequisite: Picker opening view and hidden-item count

The actual no-argument CLI comparison exposes two differences that the
three-agent preview cannot: the original opens with the first choices
visible above the preferred agent, and its more footer counts choices
outside the viewport on either side. Preserve framework defaults and add
these opt-in parameters, agreed with developer:

```dart
bool showInitialSelectionAtTop = true,
bool countHiddenItemsAbove = false,
```

The start page uses:

```dart
Picker<String>(
  items: agents,
  initialValue: preferred,
  showInitialSelectionAtTop: false,
  countHiddenItemsAbove: true,
  unhandledKeys: const {'pageup', 'pagedown', 'home', 'end'},
  onSelected: pick,
  onCanceled: cancel,
);
```

### Opening view

True retains the existing opening policy: reveal the selected item's
first row at the top of the viewport. False starts from the beginning of
the list and scrolls only as far as needed to reveal the initial selection.
Thus a preferred fourth item in a fourteen-row viewport leaves the first
three items visible above it, without changing which item is selected.
A preferred item beyond that viewport is still revealed; it must not be
hidden merely to keep the first item visible. A selected item taller than
the viewport opens on its first row, as before.

This applies to the initial view when a positive layout budget first
becomes available. It does not choose the first value or reset selection
when the responsive page rebuilds. Subsequent navigation, resize and
filter/update behavior retain their existing policies; this is not an
instruction to scroll back to the first item on every frame. Empty items
remain empty. A zero-row initial layout must not consume the policy
before a real viewport can reveal the selection.

### More footer

False retains the existing below-only count and footer behavior. True
counts every choice with no visible row, above or below the settled
viewport. A partially visible multiline choice counts as visible once.
Use the existing dim `… +N more` wording and inset. In particular, the
footer remains at the bottom of a list whose only hidden choices are
above it, matching the original PickerList. Compute N from the actual
visible choices after reserving the footer's row; do not count a choice
once for each of its wrapped lines.

The existing constraints and exception for a highlighted item occupying
the whole viewport still apply: do not replace its only readable row with
a footer or invent room when there is none. No footer is needed when all
choices fit. Disabled, empty and filtered-empty presentation is unchanged.

### Keys and start-page scope

No new framework keys or descriptions. The original pickerKey takes
arrows/j/k, numbers and Enter, and ignores PageUp/PageDown/Home/End. The
start page omits Picker's bindings for those keys through the existing
unhandledKeys API, so they cannot move its viewport away from its
highlight. The literal on-screen hint retains the original's wording;
KeyHelp must not advertise omitted Picker actions.

Default agent offering is the port's pure policy, not a Picker feature.
Match the original's default offered list: omit own-CLI agents missing
from PATH, rather than showing all such agents as unavailable. This does
not change the registry or the explicit named-agent refusal route.

### Expected states and verification

At 120x40 and 80x24, the real list opens with claude selected in its
original position and preceding visible agents retained. At the last
choice, the outside-view footer is still present. At narrower heights the
viewport reveals the preferred choice rather than leaving it off screen.
Responsive transitions keep the selected agent.

Verify opt-in initial placement with a preferred item inside and beyond
the first viewport, a zero-budget first frame, a tall row and resize.
Verify default behavior is unchanged. Check above-only/below-only/both-side
hidden counts, partial multiline choices, footer row reservation and the
single-tall-item exception. In the actual start page, ignored scroll keys
leave the view unchanged, arrows still navigate, and cancel never starts
an agent. The final live recheck uses the real CLI and real inventory at
both standard sizes, rather than claiming the synthetic fixture proves
those routes.

## C4 follow-up: preserve the minimal view across resize and reset

This extends the opening-view section above, superseding its statement
that resize retains the old policy when showInitialSelectionAtTop is
false. The actual CLI kept preceding rows on first layout but lost them
when resized from 120x40 to 80x24. The original retains them while the
selection still fits. The lead settled the following opt-in behavior.

With showInitialSelectionAtTop:false, resize and remeasurement start from
the current viewport and move it only as far as needed to reveal the
selected item within the new budget, including any footer row. Keep the
selected value and the preceding rows in sight while they fit. Equivalent
item-list rebuilds do not reset the viewport to the selected item's top.
When items actually change, keep the selected value where it survives,
clamp the old view to the new content and minimally reveal that selection.
A query/result change retains the existing selection rules, with placement
still ensuring the selected result is visible.

Default true keeps the previous policy. Changing either viewport option
must settle placement against the effective footer budget so that the
selected item cannot be hidden by a newly reserved count row. Empty and
zero-budget states retain their existing input and geometry guarantees.

To share this placement with the widget, extend the existing pure helper:

```dart
PickerView openPickerView(
  List<int> heights,
  int highlighted,
  int budget, {
  int top = 0,
  bool countHiddenItemsAbove = false,
});
```

The optional top is the current first visible line among all result lines,
in the same units as PickerView.top. Placement clamps it and makes the
minimum movement needed to reveal highlighted, with the existing tall-row
and footer rules. The default zero preserves existing calls. The widget
passes its current top for the false policy on resize/measurement/reset;
no second placement algorithm is added to the widget.

Recheck the real CLI at fresh 80x24 and 120x40 and through 120x40 to 80x24
and back: Claude stays selected and rows 1-3 remain above it where they
fit. Also check an equivalent items rebuild at the last item, real item
removal/reordering, and hidden-count option changes, with selection kept
visible after footer reservation. The original-inert scroll keys remain
omitted; this change adds no key or new visual state.

## B0d: terminal ownership across successive runApp calls

The lead settled this lifecycle after the real selector-to-interim route
cleared the screen and stopped accepting keys. Whoever creates a
StdioTerminal owns its permanent disposal. Keep the original's two render
runs; do not replace the port flow with a selector/window router inside
one runApp merely to avoid the ownership boundary.

### API

```dart
StdioTerminal({Stream<List<int>>? input});
Future<void> close(); // instance method on StdioTerminal
```

The optional byte stream defaults to stdin. It lets unit tests exercise
input ownership without reading real terminal input. It does not replace
stdout, geometry, raw-mode or alternate-screen behavior. Render/raw-mode
unit fixtures continue to use MemoryTerminal where appropriate.

close is idempotent and permanent: it cancels the terminal's backing
input subscription and waits for cancellation to complete. Repeated calls
must be safe, including calls while the first close is still completing.
The terminal cannot be resumed after permanent close. With an injected
stream, close cancels the subscription it owns; it does not close the
caller's StreamController. This is a StdioTerminal disposal API, not a
new disposal requirement on every caller-supplied Terminal implementation.

### runApp borrows a supplied terminal

Every runApp exits raw mode, leaves the alternate screen, restores cursor
and paste state, and unmounts its app on exit, whether it created or
borrowed the terminal. This means restoring the ordinary terminal state;
it does not mean leaving raw mode or the alternate screen active.

For a supplied StdioTerminal, the input source remains usable between
runs. runApp releases and awaits cancellation of only its per-run input
listener and other per-run subscriptions. The reusable broadcast input
pauses its backing byte-source subscription when its last listener leaves;
the next runApp listener resumes it. The per-run listener is distinct
from the terminal's permanently owned backing subscription. runApp never
permanently cancels that backing subscription or closes a terminal it was
given. This also avoids leaving the old app's key handler attached.

A runApp that creates its own StdioTerminal permanently closes it during
cleanup, as well as restoring display/raw state. Ownership must not make
beforeExit disappear on failure: preserve its existing after-unmount,
after-restoration contract and attempt cleanup even when another cleanup
step fails. No new app action or key is introduced.

```dart
final terminal = StdioTerminal();
try {
  await runApp(startPage, terminal: terminal, exitProcess: false);
  if (picked == null) return;
  await runApp(window, terminal: terminal, exitProcess: false);
} finally {
  await terminal.close();
}
```

Only one runApp uses a terminal at a time. The second run enters its own
alternate screen/raw mode and resumes input, then paints and receives
keys normally. The final owner close releases input so the VM can exit.

### The port owns one terminal for the invocation

bin/chord.dart creates one StdioTerminal, lends it to the startup selector
and then to the existing window, and permanently closes it on every exit:
Esc/Ctrl+C cancellation, refusal after a pick, normal window quit, error
cleanup and the forced-exit path. If a runApp can exit the process, the
owner must close the terminal in beforeExit before that exit; an outer
finally alone cannot cover a direct process exit. Forced exit likewise
must explicitly attempt owner cleanup before leaving the process. Closing
from more than one protected cleanup path is safe because close is
idempotent. Agent/process shutdown keeps its existing ownership and order.

The selected no-override Claude route must show exactly the existing
explicit `chord claude` interim window, accept its quit key and exit with
no child model/agent. The original selector is never used to launch a real
agent during this check.

### Verification

Use an injected byte stream to prove first-run delivery, pause between
runs, resumed second-run delivery, awaited per-run teardown, permanent
close cancellation, repeated close safety and no live backing input after
owner close. Keep tests terminal-free. Existing MemoryTerminal tests
still check enter/leave and first-result selection latching.

The required live recheck is the real CLI in tmux: select Claude into the
interim window, compare it with explicit `chord claude`, send a quit key,
and confirm the process and session exit. Also check selector Esc and
Ctrl+C, refusal after selection where reproducible, and cleanup evidence
for every exercised route. No headless result alone establishes the real
stdin handoff; the observed blank, key-dead transition must be gone.
