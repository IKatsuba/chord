# CTUI-48 framework proposal

Design only. The public signatures below are proposed build contracts, not
implemented APIs. This member edits only this draft; the lead owns the final
design, decisions and commit.

## Authority and verified baseline

Read README, FEATURES, decisions, CTUI-1/2/4/5/6/9/47/50, the brief and the
current framework. Original authority is current `../chord` selection.ts,
Reply.tsx, code_pick.ts, scroll.ts and CHD-172/394/396. CHD-172's old exclusion
of joined Markdown wraps is superseded by CHD-396. Interface owns observed
original/port captures; this draft contains no claim of live selection proof.

Current seams matter:

- `TextLayout.Glyph.sourceOffset` already records flattened display grapheme
  offsets; wrapping retains them, tabs share an offset and synthesized
  ellipsis/middle dots have none. It is not yet a complete selection map.
- Markdown `_text` wraps with `_wrapMarkdownLine`, then `_lineSpans` turns
  those wraps into literal newlines. Reading the resulting Text alone loses
  the distinction between source hard breaks and screen soft wraps.
- Code and Diff expand tabs before layout; each line starts local offsets
  again. They need source-line and original-tab mappings, not arithmetic on
  highlighted spans or screen columns.
- ListViewportElement releases offscreen items; RenderListViewport measures
  unknown extents exactly, then releases measurement-only elements. Preserve
  that architecture and CTUI-49's correct complete extents.
- Mouse motion is currently rejected by InputParser; Listener has no capture.
  AppHost routes each report against current paint-child geometry. Reuse that
  traversal, including its clips, overlays and layout-pass stamp.

## Flutter comparison

Flutter's [SelectionArea](https://api.flutter.dev/flutter/material/SelectionArea-class.html)
configures [SelectableRegion](https://api.flutter.dev/flutter/widgets/SelectableRegion-class.html).
The latter turns gestures into selection events; containers aggregate leaf
render selectables through a registrar. Disabled containers exclude subtrees;
regions establish selection boundaries. Adopt those roles and familiar names,
with integer cell geometry. No Material toolbar, touch handles, magnifier,
gesture arena or extra compositing layers are required. Our SelectionArea is
one configured terminal region; a separate public SelectableRegion adds no
useful choice in this slice.

Flutter's [registrar](https://api.flutter.dev/flutter/rendering/SelectionRegistrar-class.html)
provides add/remove lifecycle. Here logical source registration survives a
virtual leaf's unmount, while its geometry does not. Flutter's
[keep-alive mixin](https://api.flutter.dev/flutter/widgets/AutomaticKeepAliveClientMixin-mixin.html)
retains lazy child state; we deliberately do not add keep-alives, slivers,
parent-data machinery or a second viewport. Source records provide retained
selection while live widgets stay bounded. The existing bounded frame scheduler
and paint tree suffice.

## Public selection surface

```dart
enum SelectionPhase { none, changing, finalized }

class SelectionPosition {
  const SelectionPosition(this.sourceId, this.offset);
  final Object sourceId;
  final int offset; // Grapheme insertion boundary in that source fragment.
}

class SelectionValue {
  final SelectionPhase phase;
  final SelectionPosition? anchor;
  final SelectionPosition? extent;
  final String text;
  final int generation;
  bool get hasText;
}

class SelectionController extends ChangeNotifier {
  SelectionController();
  SelectionValue get value;
  void clear();
  void dispose();
}

SelectionArea({Key? key, required SelectionController controller,
  required Style selectionStyle,
  void Function(SelectionValue)? onSelectionChanged,
  void Function(SelectionValue)? onSelectionFinalized,
  required Widget child});
SelectionContainer.disabled({Key? key, required Widget child});
```

Example: place one SelectionArea around the window, disable decorations,
status, shortcuts, completion and requests, and leave the prompt text and
transcript content participating. SelectionArea takes no focus. Controller
attachment is one live area at a time, validated after reconciliation like
TextAreaController; replacing/disposal detaches listeners and capture before
publishing callbacks. Nested areas form disjoint boundaries.

SelectionValue is immutable; lists/ranges used internally are immutable too.
Controller owns a pure reducer for press/extend/reconcile/finalize/clear.
Generation changes for semantic selection changes, not paint-only frames.
Notifications never run during layout/paint, and reentrant mutations drain
through the existing notifier pattern. Finalized fires once per matching
release, including an empty click, after current geometry resolution. It does
not mean copied. Clipboard operations, copy-on-select, retries, note timers,
quit precedence and the selection/copying app state remain port policy.

## Logical source provider and widget binding

A leaf's source means its selectable displayed content before soft wrapping,
not raw Markdown syntax. Use grapheme offsets consistently with the editors;
convert to UTF-16 only when slicing Dart strings, through cached boundaries.
Source IDs are stable logical identities, including a block/fragment path,
and cannot be recycled for different content. Revision denotes current content,
not new identity. Plain independent Text leaves get element-lifetime IDs.

The framework owns parsing, source extraction and shaping. The port only
composes eligible entry content and provides stable entry identity/order:

```dart
abstract class SelectionSource {
  factory SelectionSource.text({required Object id,
    required Object revision, required TextSpan text});
  factory SelectionSource.markdown({required Object id,
    required Object revision, required String text, bool growing = false});
  factory SelectionSource.code({required Object id,
    required Object revision, required String text});
  factory SelectionSource.diff({required Object id,
    required Object revision, required DiffView view});
  factory SelectionSource.group({required Object id,
    required Object revision, required List<SelectionSourceChild> children});
  Object get id;
  Object get revision;
  SelectionSource child(Object id);
}
class SelectionSourceChild {
  const SelectionSourceChild({required this.source,
    this.insetLeft = 0, this.insetRight = 0,
    this.separatorBefore = '\n'});
  final SelectionSource source;
  final int insetLeft, insetRight;
  final String separatorBefore;
}
class SelectionChildDelegate {
  SelectionChildDelegate({required int itemCount,
    required Object Function(int index) idAt,
    required int? Function(Object id) indexOfId,
    required SelectionSource Function(int index) sourceAt});
}
```

ListView.builder and ListViewport gain optional
`SelectionChildDelegate? selectionDelegate`. Counts must agree; duplicate IDs,
source IDs inconsistent with idAt and missing reverse lookup are errors.
Group insets are nonnegative cell counts and determine child shaping width;
separators are semantic content between eligible children, never inferred
from absolute screen y. Empty separator before the first child is implicit.
Nested groups express layout insets without involving app parsing. Hidden
folded portions are absent from the group, even when underlying data retains
them. Revisions include folding and any eligibility change.

Add `Text.fromSelectionSource(SelectionSource source, ...)`,
`Markdown.fromSelectionSource(SelectionSource source, ...)`,
`Code.fromSelectionSource(SelectionSource source, ...)` and
`Diff.fromSelectionSource(SelectionSource source, ...)`. Their remaining
parameters retain the current corresponding widget's presentation options;
source replaces text/model arguments and must have the matching kind.
Existing constructors remain available and automatically participate under an
area. Both constructor paths share the same internal source/shaping pipeline.
An EntryView receives the same source object returned by sourceAt and binds
its eligible children through source.child(id). No extraction/reparsing in
EntryView, no raw Markdown offset search and no second parser in the port.

Lifecycle is explicit:

1. Mount registers the leaf's logical ID and current source snapshot with
   the closest area; attach its render mapping separately. List children
   register provider identity/order through ListViewportElement.
2. For a drag crossing list indices, resolve the entire ordered interval
   between anchor and extent through the delegate, including never-mounted
   intermediate items. A jump across many rows must not omit those items.
   Only crossed sources are resolved/cached; do not build widgets to get text.
3. Virtual unmount removes geometry only. Retain selected logical sources,
   endpoints and provider lookup until clear/removal; do not retain elements.
   Measurement-only leaves never publish hittable geometry.
4. Every delegate update reconciles selected IDs/revisions. Resolve changed
   sources lazily using the same cached framework parser/model used by visible
   widgets. Preserve same-source offsets and clamp to current grapheme length.
   Revision alone never clears selection, including streamed append/reflow.
   A missing selected fragment contributes nothing; surviving ranges remain.
   Clear when no selected text remains or the selected logical root is removed.
5. Clear removes selected snapshots/cache leases; ordinary widget/model caches
   retain their existing bounds. Provider detachment drops all its selected
   sources, and area disposal drops all registration/capture state.

The source registry stores logical order and selection spans, not one screen
cell object per transcript character. Selected content may be large, but widget
retention remains viewport-bounded. No all-history parse is required on every
frame. Changed definitions keep MarkdownParser's existing whole-parse fallback.

## Mapping and serialization

Factor private pure shaping helpers out of widget-private layout, shared by
render objects and source resolution. Inputs are source, effective cell width
and existing presentation options. Results contain styled glyph rows plus
source fragment/range metadata, hard/soft break information and copy payload.
Every geometry entry includes source ID/revision and layout epoch. Preserve
current line-breaking algorithms; selection does not choose new wrap points.

| Content | Copied content and excluded cells |
| --- | --- |
| Text/Text.rich/Text.ansi | Flattened display text, stripped controls; soft wraps join, real newlines remain. Inline style boundaries do not split graphemes. Ellipsis/middle dots have no source and cannot expose hidden text. |
| Markdown paragraphs/headings/list item text | Display inline content, including currently shown link addresses. Soft wraps join with original spaces, source soft breaks normalize as parser already does, hard breaks remain. List/task markers and hanging insets do not copy. |
| Markdown quote paragraph | Paragraph source without quote bars/insets. |
| Normal Code and top-level/list code boxes | Original code lines, no line-number/mark gutters, continuation arrows, border, label or padding. Expanded tabs map back to one original tab. |
| Markdown table | Current port's rendered grid rows, borders and retained truncation glyphs included; never recover hidden table text. |
| Quote-contained code/list | Current port rendered code rows/borders or list markers retained, per the owner's CHD-396 exception. Quote's outer bar remains excluded. Use quote context in shaping; do not convert these to canonical code/list text. |
| Diff | Only selected displayed source rows in DiffView order, their code content; exclude number/sign gutters, gap marks and title furniture. Never join through omitted source ranges as though adjacent original lines; serialize displayed logical rows with newlines. |
| TextArea | Current controller text, grapheme boundaries, hard LF and tabs. Use TextAreaLayout's actual row map/rowOffset; placeholder and prompt furniture excluded. Editing/paste reconcile or clear as port lifecycle requires, never replace the draft with a selection range. |

Interblock gaps matching CHD-396 are explicit selectable one-space fragments:
`first\n \nsecond`. Tight list items/blocks use one newline, no extra blank.
Blank code lines remain source content even without a painted glyph. Source
ranges can cross excluded border rows, but a fresh press on furniture starts
nothing. A one-space gap itself can start/end a selection.

For clipped/ellipsized content, range resolution selects only exposed mapped
spans. Do not fill a discontinuity by taking one large substring between the
first and last visible offset. Dropped wrapping spaces are distinct: their
soft-break metadata permits source reconstruction between adjacent selected
runs, without making padding selectable. For table/quoted exceptions, copied
rendered text is stored as a distinct logical fragment projection at the
current width, never rewritten after copying.

Main approved crossing nested lists on one motion report. Do not reproduce
OpenTUI's extra event per nesting level. Preserve all already-approved port
wrapping/geometry differences; source fidelity does not authorize a redraw.

## Layout, paint, clipping and input freshness

SelectionArea is a transparent proxy: identical constraints down, identical
child size up. No selected state changes extents. Leaf layout exposes source
ranges alongside existing rows; Code/Diff include original line and tab maps.
Text alignment shifts mapping by the same offset used for paint. Mapping
traversal uses visitPaintChildren, reverse paint order and every effective
ancestor clip, including overlays, followers and zero-surface guards.

Only visible complete graphemes can be pressed. A wide glyph's two cells map
to one grapheme; a clipped half maps to neither. Extend to insertion boundaries
according to drag direction, preserving reverse selections. Selection paint
merges selectionStyle into glyph style before Canvas.put, so syntax and diff
tints survive unless the supplied selection style overrides them. Apply to
both cells of a wide glyph. Later paint naturally occludes highlight, and the
same clipping/occlusion rules reject covered hits. Do not postprocess the final
Buffer: it cannot distinguish furniture from semantic text. Renderer diffing
needs no new escape sequences or cell representation. Preserve CTUI-50 cursor
claims and overpaint invalidation.

Maintain an input-geometry epoch in BuildOwner/AppHost. Invalidate it for tree
rebuild requests, source revisions, scroll-controller mutation, width/height
change and geometry-affecting state, including controller changes with no
setState. A private ensure-current-input-geometry uses existing build/layout
and afterLayout settlement, at most two passes at last known terminal size,
without paint/terminal writes. Before down/up, captured movement after a
mutation, or an app copy snapshot, settle invalidated geometry then project
sources. A still-dirty/unresolved epoch after that bound cancels the operation;
never spin or use a stale row. Host exposes an internal synchronized snapshot
path to the area; the port does not invoke layout. Copy reads that snapshot,
not an old SelectionValue captured before a controller edit.

Projection runs after settled layout and before paint; public callbacks run
after resolution outside layout. Wheel/key movement during a drag reruns extent
resolution at the last pointer cell even without another physical motion.
No edge autoscroll or hover timer is introduced. Moving outside a source clamps
to the nearest eligible boundary within the active region, never into covered
or disabled subtrees; release elsewhere still finalizes through capture.

## Motion and capture

Extend MouseEventKind with `move` and `cancel`. Move carries the depressed
button and zero scrollDelta. Cancel is framework-synthesized using the last
position/button. Add Listener parameters:

```dart
PointerCaptureController? captureController;
void Function(MouseEvent)? onPointerMove;
void Function(MouseEvent)? onPointerCancel;

class PointerCaptureController {
  PointerCaptureController();
  bool get isCaptured;
  void capture();
  void release();
  void dispose();
}
```

A controller attaches to one Listener. capture() is valid only during its
primary down callback on the current hit route; otherwise throws StateError.
First valid deepest capture wins; ancestor capture requests cannot steal it.
It captures matching move/up to that listener independently of subsequent hit
bounds, with ordinary ancestor observation snapshotted once. Do not also
redispatch an up against a fresh target. Wheel retains normal fresh hit routing
and is never captured. release is idempotent and cancels an unfinished drag;
matching up ends capture before its callback, allowing reentrant next presses.
Detach, host disposal, terminal inactive/suspended and superseding primary down
cancel once; no callback to an already-disposed listener. Capture references
are host-local and cleared before app code runs. A missing terminal release
cannot be invented; next primary down cancels/restarts deterministically.

Use SGR 1006 with button-motion tracking 1002; no all-motion 1003. Follow
[xterm mouse tracking](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html):
recognize bit 32 as motion only with a supported depressed button, preserve
modifiers and consume unsupported reports. Retain parser fragmentation,
bounded malformed-input recovery and bracketed-paste opacity. Track acquired
1002 ownership alongside 1000/1006 through enter/suspend/resume/leave and partial
write failures. SelectionArea consumes only unmodified primary drags; native
modifier-selection remains terminal-owned. Terminal state cancellation reaches
host before releasing ownership, through existing runApp lifecycle wiring.

A code button uses the same capture seam: primary press/release on the same
still-visible button/version, no movement or outside release, invokes its
callback. A text drag ending there does not click it. Buttons are nonselectable
furniture. Keyboard Actions invoke the same callback independently of pointer.

## Held scrolling and code-action seam

Add `bool held = false` to ScrollState and `hold()`/`release()` to
ScrollController, with pure reduceHeld/reduceReleased counterparts. Match
current original scroll.ts: hold snapshots offset, disables following even
when fitting; measurement, bottom and downward steps cannot reenable following
while held. Release removes hold and restores fitting-state normalization.
The port owns wasFollowing/moved and explicitly toBottom() on release only
when original released() permits it. Shown selection retains sources, not a
scroll hold; it may follow new output after release. No mount retention flag.

Framework Markdown owns code descriptors derived from its parser model:

```dart
class MarkdownCodeBlock {
  final Object id; // Source root plus stable block path.
  final Object revision;
  final String text; // Canonical code, no structural final fence newline.
  final String? language;
  final bool complete;
}
// SelectionSource of Markdown kind:
List<MarkdownCodeBlock> get codeBlocks;
```

Descriptors include quote/list nesting and are available without mounting.
They do not include chord entry indices, keys, clipboard effects or run policy.
A private render registry attaches descriptor ID to current clipped box/quote
geometry. Expose widget configuration on Markdown's constructors:
`Object? selectedCodeBlock`, `void Function(MarkdownCodeBlock)? onCopyCodeBlock`.
A non-null callback enables [copy] for complete ordinary boxes; quote boxes
have keyboard identity but no button. Border sizing/hiding follows interface's
narrow geometry; there is no [run] or r binding in CTUI-48.

Port code_pick owns transcript eligible-entry discovery and total order,
combining framework source.codeBlocks for listed entries with currently
visible nonlisted descriptors. It caches unchanged entry descriptors, selects
newest visible/newest total, clamps arrows and ends mode per original. Source
model extraction and rendered geometry registry remain framework-owned.
Scrolling to an offscreen listed block resolves its framework-local row using
the shared shaper at actual inset width plus ScrollController.itemTop; recheck
its current visible geometry after normal layout. No giant mount or scan of
render objects across history. Future CTUI-25 may add run metadata/action at
this seam after its own owner decisions.

## Package fit and remaining gates

Existing maintained dependencies remain: characters 1.4.1, markdown 7.3.1,
highlighting 0.9.0+11.8.0 and dartdiff 1.0.0. No new parsing/highlighting/diff
implementation. Existing example/markdown.dart compiled successfully with
`dart --suppress-analytics compile exe` to a temporary native executable in
this design pass; it imports the framework and its pinned dependencies. The
executable was not run, and no real clipboard or terminal was used.

Package inspection found FencedCodeBlockSyntax returns the same AST for a
closed fence and an EOF-open fence; its closingFence variable is private.
Main approved extending the existing block-syntax recording adapter using
public parser state to record consumed closing fences, including nesting.
Do not add a handwritten fence scanner or duplicate the package grammar.
Record the trial and approval in the lead-owned decisions entry. Required
proof includes close-at-EOF, still-open EOF, appended closer, tildes, longer
closers, nested list/quote fences and indented code; still-open blocks have
neither buttons nor pick eligibility. Failure to obtain that metadata through
the approved adapter is a stop-and-report package gate, not permission for a
fallback scanner.

A remaining behavior comparison belongs to implementation acceptance: exact
partial-cell endpoint conventions and cross-entry separators need original
window tests/captures, not assumptions from OpenTUI internals. Interface owns
those observations. No changed raw Markdown serialization is authorized.

## Build units and failing-test acceptance

1. Source model, reducer and shared shaping: new foundation/selection.dart,
   text/selection.dart; adapt text/layout.dart, widgets/basic.dart,
   rendering/basic.dart, Code/Markdown/Diff/TextArea and exports. Tests must
   fail for synthetic newline leakage, tab expansion copied as spaces,
   grapheme splitting, invisible ellipsis ranges, quoted exceptions and
   omitted blank gap space. Compare same selected paragraphs at both widths.
2. SelectionArea/disabled registrar and provider: widgets/selection_area.dart,
   rendering/selection.dart, ListView/ListViewport binding, BuildOwner/host
   epoch settlement. Test a drag across never-mounted intermediate entries,
   reverse drags, append/clamp/remove, resize, overlay clipping, stale layout
   after scroll in the same input chunk, two-pass exhaustion and disposal.
   Assert bounded live widget count under 150+ appended entries and unchanged
   complete extents at one-row viewport; retaining a selection must not retain
   all previously mounted widgets.
3. Motion/capture and hold: keys.dart, parser.dart, listener widgets/rendering,
   host.dart, run_app.dart, terminal.dart, scroll_state/controller. Byte tests
   cover fragmented motion and cleanup of 1002; pure tests hold fitting and
   overflowing scroll through all paths. Widget tests cover outside release,
   fresh wheel route, capture cancellation and no button activation by drag.
4. Code descriptors, approved closure adapter, frame registry and [copy]
   configuration: text/markdown.dart and widgets/markdown.dart. Tests cover
   nested descriptors, open fences, hidden/folded nonlisted blocks, recycled
   source identities, exact source copy and offscreen reveal without keep-alive.
5. Port wiring belongs to interface/runtime units: source composition,
   copy-generation policy, Actions/help, code-pick reducer and themes. Fake
   clipboard only. Later implementation checks include framework/port static
   checks, relevant suites, AOT fixture coverage and retained original-versus-
   port terminal evidence at 120x40/80x24 in relevant themes.

Costs: existing renderer remains O(screen cells). Ordinary selection hit work
is O(visible mapped glyphs), with cached row indexes permitting row-local
lookup. First crossing resolves O(crossed source bytes + projected rows), not
O(history widgets). Selection serialization is O(selected bytes), performed
on semantic changes or copy; paint-only frames reuse it. Append reparses only
changed Markdown tail except existing definition invalidation. Selected source
storage is O(selected source bytes/ranges); visible mappings are O(visible
cells), metadata/caches obey existing model lifetimes. Exact extent measurement
and width-change costs remain CTUI-1's; this draft makes no constant-time
resize or all-history selection claim.
