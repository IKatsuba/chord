# CTUI-54: Picker work follows the visible rows

Main approved exact geometry with bounded visible widget work. Navigation
must not traverse all choices. A cold width may compute all exact scalar
heights once; measure and report that O(N) cost. This does not promise
O(visible rows) total resize. Arbitrary custom rows keep the existing exact
measurement fallback. No estimated heights or broader ListView redesign.

Read with CTUI-1, CTUI-8, CTUI-18, CTUI-22 and CTUI-26. The original screen
and key behavior is unchanged. This is terminal layout work; no new package
or matching algorithm is needed.

## Diagnosis and units

Developer found that Picker omits ListView.itemVersion, invalidating every
extent on a highlight rebuild. Merely supplying it leaves all-item version
and known-height scans. Picker additionally copies heights, reconstructs
prefix arrays, traverses physical lines and searches the selected value.
Highlight changes do not themselves rerun filtering.

1. U54a: immutable indexed Picker geometry and indexed highlighted result.
   Keep existing List<int>-taking pure helpers as compatibility wrappers;
   internal navigation reuses the indexed representation. Prefix sums are
   built once per height snapshot; visible-start lookup is logarithmic,
   hidden-item counts arithmetic. Never enumerate all physical lines.
2. U54b: narrow exact-extent/revision path on ListView.builder. Preserve
   existing behavior when it is absent.
3. U54c: Picker integration, actual resume composition and framework/port
   benchmarks. The port obtains heights through shared framework TextLayout
   shaping, with the same metadata/title split as its rendered rows.

U54a introduces no widget parameter. If reusable pure geometry needs a
public type because existing exported helpers consume it, use
`PickerGeometry`, documented as immutable indexed item heights; otherwise
keep the implementation private. Do not expose prefix arrays as mutable
lists or add a geometry controller.

## Minimal API

```dart
ListView.builder(
  controller: scroll,
  itemCount: rows.length,
  itemExtentBuilder: (index, width) => exactRows(rows[index], width),
  itemExtentVersion: rowsRevision,
  itemBuilder: buildRow,
);

Picker<String>(
  items: choices,
  itemExtentBuilder: (item, positions, contentWidth) =>
      exactChoiceRows(item, positions, contentWidth),
  itemExtentVersion: choicesRevision,
  itemBuilder: buildChoice,
  onSelected: choose,
  onCanceled: close,
);
```

Add nullable named parameters, default null:

```dart
// ListView.builder
int Function(int index, int width)? itemExtentBuilder,
Object? itemExtentVersion,

// Picker<T>
int Function(PickerItem<T> item, List<int> matchedPositions,
    int contentWidth)? itemExtentBuilder,
Object? itemExtentVersion,
```

`itemExtentBuilder` supplies an exact nonnegative whole-cell height, not an
estimate or maximum. ListView width is the final item width. Picker width
is the actual builder-content width after marker, number and edge gutters;
its returned height excludes Picker furniture. Zero width and zero-height
items remain legitimate geometry; reject negative heights. Callbacks are
pure: no IO, mutation, focus changes, widget mounting or notifications.
A negative callback height is rejected with ArgumentError. Picker projects
inside build, so that error uses the framework's normal build-error boundary
and presentation; it need not escape pumpWidget. ListView's render projection
uses normal render-error handling. A mounted measured height that disagrees
with its promise raises StateError through that render path. These checks
remain active in AOT. Do not add an error shuttle or silently rewrite exact
cached geometry. Failed Picker projection must disable effective choice rows,
navigation and acceptance immediately; recovery cannot replay a hidden choice.
Check initial failure and positive-to-negative-to-valid revision transitions.
ListView permits zero-height items; Picker retains its existing minimum
one-row marker/number furniture even when content height is zero.

A supplied nonnull `itemExtentVersion` is the caller's stable revision of
all extent-affecting inputs. Equality means those inputs are unchanged.
Changing data/order/count, callback semantics or captured mutable inputs
requires a new revision. Without that promise, retain conservative checking;
null never asserts that captured state is stable. Callback identity alone
must not silently override an explicit revision's contract on each inline
closure rebuild. Painting still receives current builders and styles.

Default Picker rows are exactly one row and need no caller callback.
Custom builders without exact extents retain exact widget measurement.
Picker owns revisions for its result mapping and configuration; an external
revision never masks its own query/order/gutter/width changes.

## Cache and invalidation

Retain only the current width/configuration generation: O(N) compact
heights, prefix sums and result/selection indexes, plus O(visible rows)
mounted widgets. No map of every visited width, query, theme or item list;
no old widget trees, old source snapshots or cumulative per-navigation
arrays. Disposal releases the cache. Returning to an earlier width may
recompute; it must not resurrect a stale generation.

| Change | Required effect |
| --- | --- |
| Highlight, viewport scroll, focus or enabled state only | Reuse heights/ranks; draw current visible styling; no all-item scan/copy |
| Filter text, filter implementation, item membership/order/value/label | Reconcile current ranking/selection and invalidate affected mapping/geometry before acceptance |
| New width, number-column digit count, showNumbers or overflow edge gutter | Recompute exact heights at final content width and reveal highlighted first line |
| Font-independent style colour only | Repaint current style; exact callback may reuse its promised geometry |
| Inherited wrapping/line limits, theme-dependent custom layout or builder inputs | Conservative custom path remeasures; explicit extent revision must change when its promised geometry changes |
| Footer/row budget/opening policies | Recompute viewport/footer placement using every active policy; reuse heights only if content width is unchanged |
| Item replacement/removal or disposal during notification | Cancel stale delivery/index use; accept only current result and mounted ownership |

Generic custom builders may depend on inherited context. Preserve their
conservative invalidation rather than inferring geometry from label equality.
No change to CTUI-22 onChanged timing, equality, reentrancy or disposal rules.
Keep the shared two-layout-pass budget and existing zero-room input guards.

## Appearance, states and keys

There is no new action, key, hint or visual state. Existing Actions and
KeyHelp descriptions remain complete. Up/down and j/k retain clamp/wrap
policy and read a selected tall row before leaving it. Page/home/end still
scroll only the viewport; digits and Enter accept current ranked positions
only with visible room. Filtering, disabled focus and unhandledKeys retain
CTUI-8/18/22 behavior.

These are API mocks at both 120x40 and 80x24, not runtime evidence; unused
cells are blank. Actual captures follow the exact U54c developer handoff.

```text
Focused                    Empty             Filtered empty
❯ 1. First choice          No choices.       No matches.
  2. Second choice

Overflow / narrow custom row
❯ 1. A wrapped choice     ↑
     continues here
  2. Next choice          ↓
    … +8 more
```

Preserve continuation insets, selected style across wrapped lines, hidden
choice counts, edge markers and tall-row footer suppression. At zero choice
rows omit navigation/acceptance, retaining only actions that can act; no
pending acceptance when room returns. Capture 120x40 and 80x24, narrow
wrapping/zero-room boundaries and dark/light/plain themes where relevant.
Compare actual resume against the original in matching states and sizes.

## Performance and correctness gate

Use 2,000 and 10,000 choices under AOT for both framework Picker and actual
ResumePicker. Keep a small control. Report source commit, runtime, dimensions,
row budget, corpus and counters. Separate first layout, cold resize to 80x24,
return resize to 120x40, unchanged frames, highlight redraw, dispatch and
scheduled-to-acceptance delay. Exercise navigation near the beginning,
middle and end, tall choices, and widths that change wrapping/gutters.

Deterministic reached tests must show that stable navigation performs no
all-item height/version/filter/selected-value scan or height snapshot copy;
widget builds/layouts scale with visible rows, with at most logarithmic
indexed lookup overhead. Exact callback cold resize may invoke N scalar
height projections once per final geometry generation; visible widget work
must remain bounded. Default fixed-height rows should avoid N widget work
on first layout and resize too. Custom fallback costs are labelled separately.

Record timing distributions and retained memory/counter bounds, not only a
single fast frame. Compare the real resume run with CTUI-26's retained
2,000-choice AOT baseline (about 25 ms navigation redraw, 33–35 ms resize).
No unmeasured universal millisecond threshold or performance pass follows
from this design. Residual cold projection hitches go to the lead with
measured options; never replace exact behavior to make a number pass.
Timing excludes disk scan, agent/reopen, PTY writes and physical display.

Correctness checks cover selection after reorder/filter/removal, callback
replacement/revision changes, repeated widths/themes, footer convergence,
empty/zero heights, tall rows and current onChanged behavior. Retain any
failure/fix evidence. Heavy runs require the lead's slot, run in background
under nice -n 19, and finish before another heavy command. Report cleanup
of benchmark roots/processes and owned tmux sessions.
