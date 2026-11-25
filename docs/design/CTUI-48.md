# CTUI-48: selection and copy in the window

This is the design ship builds, in units S1–S7 below. No selection code is
implemented by this design commit. The brief and three architecture drafts
remain in [the evidence directory](evidence/CTUI-48/drafts/brief.md).
This document supersedes draft suggestions where they differ.

The framework supplies selection, source mapping, pointer capture and held
scrolling. The port supplies copy policy, key precedence, notes and code-pick
state. Nothing reaches ACP, records or agents. No host clipboard implementation
is added: CTUI-9's OSC 52 write means **sent**, never confirmed copied.

## Authority, scope and observed baseline

Original inspected/captured: `577b58167672e12c999aeaf4eed2a1a988513dc2`.
Port baseline: `7e3da14f248b7fdf27c3c483a461617c2c557217`.
Authority is current `../chord/src/ui/app/{selection,terminal,state,keys,timers}.ts`,
App.tsx, transcript/{code_pick,scroll,markdown}.ts, Reply.tsx and current tests.
CHD-396 supersedes CHD-172's early wrapped-copy prose; CHD-394 supplies buttons
and code picking. Read those current sources rather than porting old sketches.

Main settled these boundaries:

- Selection, `[copy]`, ctrl+x b, arrows, c and Esc land here. `[run]`, r and
  its help clause wait for CTUI-25; that task adds prompt insertion policy at
  the code descriptor/action seam, without changing selection serialization.
- `TranscriptWindow` gains `bool copyOnSelect = true`. CTUI-29 later seeds it
  from the user's settings file; no agent `/config` option or new command.
- Highlight is slate 66 dark, 152 light. NO_COLOR uses inverse only, an
  explicit difference from the original's slate exception.
- Keep CTUI-1 virtualization and the existing approved Code wrapping/insets,
  Markdown geometry and CTUI-49 complete extents. Do not emulate OpenTUI's
  nesting/root-expansion requirement for extra motion reports. One report
  reaching another eligible source resolves the complete range immediately.
- No edge autoscroll, hover, handles, toolbar, gesture arena, selectable-image
  subsystem, new terminal UI dependency, settings-file implementation or code
  execution. Only plain primary drags are selection gestures.

### Original beside current port

All links below have matching `.ansi` captures; text captures show cells,
not selection colour. [Interface's comparison and full-size proposed states](evidence/CTUI-48/drafts/interface.md)
retain the detailed evidence and 120x40/80x24 sketches.

| State | Original 120x40 / 80x24 | Current port 120x40 / 80x24 | Difference and reason |
| --- | --- | --- | --- |
| Completed Markdown | [120](evidence/CTUI-48/interface-captures/original-markdown-120x40.txt) / [80](evidence/CTUI-48/interface-captures/original-markdown-80x24.txt) | [120](evidence/CTUI-48/interface-captures/port-markdown-120x40.txt) / [80](evidence/CTUI-48/interface-captures/port-markdown-80x24.txt) | Port lacks controls; existing label/inset/wrapping differences remain. Original run control is deferred here. |
| Leader | [120](evidence/CTUI-48/interface-captures/original-leader-120x40.txt) / [80](evidence/CTUI-48/interface-captures/original-leader-80x24.txt) | [120](evidence/CTUI-48/interface-captures/port-leader-120x40.txt) / [80](evidence/CTUI-48/interface-captures/port-leader-80x24.txt) | Add b to the staged leader choices. |
| Code pick | [120](evidence/CTUI-48/interface-captures/original-pick-120x40.txt) / [80](evidence/CTUI-48/interface-captures/original-pick-80x24.txt) | [120](evidence/CTUI-48/interface-captures/port-pick-120x40.txt) / [80](evidence/CTUI-48/interface-captures/port-pick-80x24.txt) | Port has no pick mode, accent frame or key hint yet. |
| Previous code | [120](evidence/CTUI-48/interface-captures/original-pick-up-120x40.txt) / [80](evidence/CTUI-48/interface-captures/original-pick-up-80x24.txt) | [120](evidence/CTUI-48/interface-captures/port-pick-up-120x40.txt) / [80](evidence/CTUI-48/interface-captures/port-pick-up-80x24.txt) | Arrows still belong to the port's ordinary prompt/history until mode exists. |
| Help | [120](evidence/CTUI-48/interface-captures/original-help-120x40.txt) / [80](evidence/CTUI-48/interface-captures/original-help-80x24.txt) | [120](evidence/CTUI-48/interface-captures/port-help-120x40.txt) / [80](evidence/CTUI-48/interface-captures/port-help-80x24.txt) | Add only available copy/pick rows; original has later features too. Preserve natural staged panel geometry. |
| Held drag | [120](evidence/CTUI-48/interface-captures/original-drag-held-120x40.ansi) / [80](evidence/CTUI-48/interface-captures/original-drag-held-80x24.ansi) | No implementation | Slate baseline only; no release/clipboard action was performed. |

Both used the original fake's completed `markdown` reply. The port baseline
was awaited to completion. Owned tmux, fake processes, neutral capture state
and temporary raw logs were cleaned. No real model/host clipboard was used.
Dark/light/plain contrast, copy results and new implementation captures remain
ship acceptance, not results claimed by these baseline files.

## Framework call site and public contracts

Compare Flutter's [SelectionArea](https://api.flutter.dev/flutter/material/SelectionArea-class.html),
[SelectableRegion](https://api.flutter.dev/flutter/widgets/SelectableRegion-class.html)
and [SelectionRegistrar](https://api.flutter.dev/flutter/rendering/SelectionRegistrar-class.html):
a region owns gestures, a registrar collects selectable leaves, and disabled
containers exclude furniture. Adopt those roles with cell geometry. A second
public SelectableRegion, touch controls and Flutter keep-alives add no needed
choice. The implementation remains from scratch.

Proposed Dart surface, with existing presentation options retained on content
widgets. These are design signatures, not claims that the APIs already exist.

```dart
enum SelectionPhase { none, changing, finalized }

class SelectionPosition {
  const SelectionPosition(this.sourceId, this.offset);
  final Object sourceId; // Opaque fragment identity, never a row index.
  final int offset;      // Grapheme insertion boundary.
}

class SelectionValue {
  final SelectionPhase phase;
  final SelectionPosition? anchor, extent;
  final String text;
  final int generation;
  bool get hasText;
}

class SelectionController extends ChangeNotifier {
  SelectionController();
  SelectionValue get value; // UI/notification snapshot only.
  SelectionValue? snapshot(); // Synchronize before copying.
  void clear();
  List<CodeBlockGeometry> visibleCodeBlocks();
  CodeBlockGeometry? codeBlockGeometry(CodeBlockId id);
  bool revealCodeBlock(CodeBlockId id);
  void dispose();
}

SelectionArea({Key? key, required SelectionController controller,
  required Style selectionStyle,
  void Function(SelectionValue)? onSelectionChanged,
  void Function(SelectionValue)? onSelectionFinalized,
  required Widget child});
SelectionContainer.disabled({Key? key, required Widget child});
```

One area surrounds header text, transcript, draft and the overlay host.
Disable logos, gutters, border/status/help/picker furniture and request UI;
agent-authored content explicitly eligible inside a composite stays selectable.
Selection takes no focus and adds no layout dimensions. The terminal's real
prompt cursor remains CTUI-50's. One controller attaches to one live area;
validate after reconciliation as with TextAreaController. Nested areas are
separate boundaries. Disposal/detach releases registrations/capture first.
Finalized callback fires once for a matching release, even an empty click,
after releasing drag resources. Capture the immutable finalized value for that
release before notifications. If onSelectionChanged then clears selection or
starts a new drag reentrantly, still deliver exactly that old finalized value
once to the original live receiver; a generation change alone does not suppress
it. Disposal/unmount of that receiver suppresses delivery. Post-release clear
is not cancellation of the completed gesture. The port checks current selection
generation/epoch/session before accepting auto-copy from the event, so a stale
finalized event cannot copy or affect a new gesture. Cancellation before a
matching release never finalizes or auto-copies.

### Sources, lazy items and one authoritative model

```dart
abstract class SelectionSource {
  factory SelectionSource.text({required Object id,
    required Object revision, required TextSpan text,
    TextAlign align = TextAlign.left, bool softWrap = true,
    TextOverflow overflow = TextOverflow.clip, int? maxLines,
    SelectionSource? previous});
  factory SelectionSource.markdown({required Object id,
    required Object revision, required String text, bool growing = false,
    bool copyCodeBlocks = false, SelectionSource? previous});
  factory SelectionSource.code({required Object id,
    required Object revision, required String text,
    bool lineNumbers = false, bool softWrap = true,
    SelectionSource? previous});
  factory SelectionSource.diff({required Object id,
    required Object revision, required DiffView view,
    String? title, bool showTitle = true, SelectionSource? previous});
  factory SelectionSource.group({required Object id,
    required Object revision, required List<SelectionSourceChild> children,
    SelectionSource? previous});
  Object get id;
  Object get revision;
  List<SelectionSource> get children;
  SelectionSource child(Object id);
  List<MarkdownCodeBlock> get codeBlocks;
}

class SelectionSourceChild {
  const SelectionSourceChild({required this.source,
    this.insetLeft = 0, this.insetRight = 0,
    this.separatorBefore = '\n', this.selectable = true});
  final SelectionSource source;
  final int insetLeft, insetRight;
  final String separatorBefore;
  final bool selectable;
}

class SelectionChildDelegate {
  SelectionChildDelegate({required int itemCount,
    required Object Function(int) idAt,
    required int? Function(Object) indexOfId,
    required SelectionSource Function(int) sourceAt,
    String Function(int)? separatorBefore});
}
```

ListView.builder and ListViewport gain optional
`SelectionChildDelegate? selectionDelegate`. Default delegate separator is LF
between items and empty before item zero. Optional separatorBefore overrides
it explicitly, never by counting blank terminal rows. Counts, IDs, reverse
lookup and source IDs must agree; duplicate IDs and invalid lookup are errors.
Group insets are nonnegative and supply effective shaping width. The first
eligible child's copy separator is always empty. child(id) is recursive exact
ID lookup: absent or
duplicate means StateError; constructors validate uniqueness. children and
codeBlocks are immutable; Markdown supplies descriptors, groups concatenate
eligible child descriptors, other kinds return empty.

### Geometry-preserving disabled source children (S5a2)

S5a2 is a separate framework gate before the port consumes this flag.
SelectionSourceChild.selectable is immutable and defaults true. A false child
keeps its normal shared-shaper rows, wrapping, painting, insets and height in
its original vertical position, but contributes no selection fragments, text,
endpoint hits, highlight, code bounds or parent code-block descriptors. False
applies through the entire subtree; a nested true child cannot re-enable it.
This mirrors SelectionContainer.disabled without flattening text, adding false
LFs or counting rows in the port. Source order and actual layout stay intact.

Disabled children contribute no own separator. Between contributing eligible
children, use the later eligible child's configured separator once, in order;
ignore the separator of excluded children. There is no leading separator for
the first eligible child, no trailing separator for excluded final children,
and no text/separator for an all-excluded group. Explicit eligible separators
retain their existing meaning; blank terminal height never invents copy text.

children and recursive child(id) still expose decorative models for drawing;
duplicate-ID validation covers every child, including excluded subtrees.
Querying that child source standalone retains its ordinary eligibility. This
model access does not grant eligibility inside the parent: parent projection,
codeBlocks, scene/query/reveal geometry and provider registration must honor
the flag. In a provider-bound mounted subtree, the authoritative delegate must
not let an omitted bound descendant register again as an automatic standalone
leaf. The actual disabled widget boundary and offscreen projection must agree.

An eligibility change creates a new group revision; prior snapshots remain
immutable. Once observed, loss of eligibility drops the affected ranges/leases;
reenabling cannot resurrect them. Preserve unrelated surviving selected text
under the established reconciliation rules. Shared shaping remains the sole
width/height authority for mounted and never-mounted content.

Tests cover excluded first/middle/last/all children and exact separators,
nested excluded code descriptors/bounds, wrapped decorative geometry, actual
provider-bound mounted hits versus offscreen copy, attempted automatic-leaf
re-registration, eligibility toggles/released leases/no resurrection, immutable
old snapshots and revision changes. Fresh-source snapshot and matching-release
regressions at 120x40/80x24 include live-parent observer notifications that
setState: current text survives, callbacks remain outside layout and the shared
total never exceeds two passes. Reentrant key/paste/pointer input must supersede
old observer continuations without cancelling a newer gesture. No other public
API is added.

Add matching-source constructors to Text, Markdown, Code and Diff:
`Widget.fromSelectionSource(SelectionSource source, ...)`. The positional
source replaces the normal content/model argument; reject a wrong source
kind with ArgumentError. Each source snapshot freezes its effective per-kind
presentation geometry through the factory parameters above. These values are
immutable and available to the shared shaper without mounting a widget:

- Text stores align, softWrap, overflow and maxLines. Factory defaults are
  left alignment, wrapping, clip overflow and unlimited lines. Source factories
  have no BuildContext and never inherit geometry from DefaultTextStyle.
- Code stores lineNumbers and softWrap, defaulting to false and true.
- Diff stores showTitle (true) and the effective title, resolved once as
  `title ?? view.model.path`. A shown title contributes its decorative row to
  geometry but never to copied text. DiffView still determines eligible rows;
  omitted code and gap/title/number/sign furniture remain excluded.
- Markdown stores copyCodeBlocks, default false. This records whether S6 copy
  controls may change a closed ordinary code box's minimum width. It does not
  make open or quoted code buttons eligible. Existing growing metadata keeps
  its parser/highlighting meaning. Group keeps its child insets/separators;
  it needs no additional presentation fields.

A bound constructor's geometry parameters are nullable overrides: omission or
null takes the source's frozen effective value, independent of inherited
DefaultTextStyle geometry. Every nonnull override must equal that value or
throw ArgumentError before drawing or registering geometry. In particular,
`maxLines: null` cannot clear a source limit, and `title: null` cannot clear a
source title override. Make a replacement snapshot with a new revision to
remove maxLines (factory null means unlimited) or remove a title override
(factory null resolves the model path); use showTitle false to hide the title
row altogether. No sentinel or public Object parameter is introduced. Styling
still inherits normally; colour/highlighting-only options keep their existing
meaning and never replace the source's geometry.

Markdown adds `CodeBlockId? selectedCodeBlock` and
`void Function(MarkdownCodeBlock)? onCopyCodeBlock` on both constructors.
Markdown.fromSelectionSource validates that
`(onCopyCodeBlock != null) == copyCodeBlocks` before drawing; selectedCodeBlock
changes style only. The ordinary Markdown constructor derives copyCodeBlocks
from callback presence when it automatically creates a source.

Existing constructors still work and automatically register inside an area.
Ordinary Text retains its current nullable/inherited options and snapshots the
resolved effective align/wrap/overflow/maxLines at registration, including
inherited geometry. Ordinary Code and Diff keep their existing defaults.
Any geometry-affecting change creates a current source snapshot with a changed
revision, and changes itemVersion wherever extent can change. Reusing a source
revision while changing its geometry is invalid caller input. Theme-only or
picked-style changes do not manufacture a geometry revision.

Mounted rendering and never-mounted provider resolution use this same frozen
geometry and the same private pure shaper at the actual effective width. The
source is authoritative; neither path may guess defaults from a future widget,
read stale mounted geometry, or independently truncate/flatten hidden text.
TextArea registers its controller text/live layout directly; no second editable
controller or caret model is added.

A complete provider/binding pattern for a plain-text virtual log:

```dart
final sources = <SelectionSource>[
  SelectionSource.text(id: 'first', revision: 0,
    text: const TextSpan('First record')),
  SelectionSource.text(id: 'second', revision: 0,
    text: const TextSpan('Second record')),
];
final selection = SelectionController();
final scroll = ScrollController(follow: Follow.bottom);
final delegate = SelectionChildDelegate(
  itemCount: sources.length,
  idAt: (i) => sources[i].id,
  indexOfId: (id) {
    final i = sources.indexWhere((source) => source.id == id);
    return i < 0 ? null : i;
  },
  sourceAt: (i) => sources[i],
);
final log = SelectionArea(
  controller: selection,
  selectionStyle: const Style(inverse: true),
  onSelectionFinalized: (value) {
    // An app chooses copy policy here; the framework does not copy.
  },
  child: ListView.builder(
    controller: scroll,
    itemCount: sources.length,
    itemVersion: (i) => sources[i].revision,
    selectionDelegate: delegate,
    itemBuilder: (context, i) => Text.fromSelectionSource(sources[i]),
  ),
);
```

The port uses the same cached object in sourceAt and EntryView. An entry's
source is a group of its currently eligible header/text/Markdown/Code/Diff
content at the actual insets; hidden folded portions are absent. It supplies
domain data, not extracted Markdown text. A stable session/clear epoch plus
Entry.identity's opaque occurrence token prevents slot reuse; never use the
old Entry object itself as the source ID. The
[CTUI-15 entry contract](CTUI-15.md#entries) requires fresh append issuance, same-slot replacement preservation and rejection
of raw duplicate canonical IDs, with no historical Entry retention. Current
Entry object identity remains a revision signal. Plan rows use their semantic
identity.
Frame rebuilds do not manufacture new revisions. Folding/eligibility changes
are included in revision and itemVersion where they affect extent.

Caller owns exactly the current source snapshot per logical root/revision.
Reuse it unchanged for the same revision. A genuine revision passes previous:
the old snapshot; previous must have the same root ID and source kind or
throw ArgumentError. Domain replacement uses a fresh root ID; equal kinds
alone never establish identity. Old snapshots are immutable. Framework parser
bookkeeping is copied for the new snapshot, immutable blocks/boundaries shared;
no old snapshot mutates through a shared MarkdownParser. Extraction/parsing is
lazy; do not parse every source merely to construct the delegate.

Fragment IDs are opaque tokens, never parser ordinals. Reconcile recursively
inside the same surviving parent and serialization class: retain unambiguous
unchanged blocks after fingerprint lookup and equality confirmation; use only
noncrossing matches. Between the same surviving neighbors, retain a token for
exactly one old and one new block of the same kind as a same-source edit.
Crossed/reordered anchors do not authorize this fallback. All other new
fragments receive new tokens and unmatched old fragments disappear. Never
pair duplicate text by occurrence number, infer a general move, or carry IDs
from ordinary code into quote-rendered code. Full reparses, including changed
reference definitions, run the same reconciliation. Preserve unchanged parsed
prefix identity where known. Same-source ranges clamp to current grapheme
length; new/retyped/ambiguous fragments cannot inherit them. Clear the whole
selection only when none of its selected text survives.

During a held drag, source updates, geometry refresh and matching up first
reconcile those retained fragment identities. Endpoints may reflow against
fresh geometry/text only within surviving retained IDs; a new fragment cannot
inherit an endpoint or join the range merely because it now occupies the last
motion cell or lies between the old endpoints. Admit inserted fragments only
on a real pointer motion or explicit transcript scroll, including a clamped
scroll action. This is not a blanket freeze: surviving same-source text and
geometry remain current, ranges clamp/reflow within them, and removal follows
the survival rule above. Release reads current geometry and text under this
identity restriction; it never resurrects removed text or silently widens into
an inserted fragment. Main settled this source-update/frame-order rule for S3;
further held identity-versus-refresh cases use the same rule.

Virtual unmount removes geometry, not selected logical records/provider lookup.
Resolve every crossed item, including never-mounted intermediate entries,
without building widgets. Measurement-only elements publish no hit geometry.
Keep only current source snapshots/crossed range leases, not old revisions,
duplicated transcript strings, unbounded parser caches or offscreen State,
Element and render objects. Clear/removal/disposal releases leases immediately.

### Region order and exact serialization

Document order is forward logical child order, independent of paint z order.
A lazy provider occupies one slot in that order and expands to all its logical
items by index. Header, provider and draft occupy successive slots. Overlay
surfaces are separate/excluded; they never reorder the underlying document.
An automatic leaf boundary contributes LF when on a different logical row,
empty string for adjacent leaves on the same row. Explicit group/delegate
separators override that rule. IDs and order remain stable while children are
virtually absent. Reversal normalizes to current document order.

Port boundaries: header text lines join with LF; header→first transcript
content, distinct transcript entries, and transcript→draft each join with one
LF. Ordinary empty layout contributes nothing extra. Disabled logos, gutters,
status and request surfaces contribute no text/separator. Within a Markdown
reply use its explicit mappings below, not the entry boundary rule. Exact
forward/reverse tests must cover header→transcript and transcript→draft in
addition to the observed prompt-entry→reply case.

| Content | Copy text |
| --- | --- |
| Plain text, header lines, transcript prompt, draft | Displayed text before soft wrap; hard LF remains. No logo, prompt marker or placeholder. |
| Paragraph, heading, list text, quote paragraph | Inline display text, including shown address suffixes; soft wraps join with source spaces. Hard breaks remain. No list/task marker, hanging indent or outer quote bar. |
| Ordinary/list code | Original source characters/LF/tabs, without border, label, padding, number/sign/continuation gutters. Soft wraps join. |
| Table | Current rendered rows/grid, including visible truncation; never hidden cell text. |
| Quoted code/list | Current rendered code rows/borders or list rows/markers; outer quote bar excluded. Preserve this original serialization class with existing port geometry. |
| Diff | Displayed DiffView code rows in order, separated by LF; no number/sign/title/gap furniture, no omitted rows. Do not pretend separated hunks are adjacent original source. |
| Markdown gap | Explicit one-space fragment: `first\n \nsecond`. Tight list items use LF without that extra fragment. |

### Original opt-ins for current port content

Source reference: original `577b58167672e12c999aeaf4eed2a1a988513dc2`.
Paths in the table are relative to ../chord/src/ui/. theme/text.ts:80–102
sets TEXT/FILL/ROWS/CUT to selectable false; app/context.ts:44–52 supplies the
explicit useSelectable opt-in. Visible Text, agent provenance or dim/error style
alone does not confer eligibility. These are source-level findings, not new
runtime drag/copy parity evidence.

| Current content | Eligible text / excluded furniture | Original source |
| --- | --- | --- |
| Header and draft | All header text lines and editable draft opt in; logo, prompt marker/placeholder and surrounding furniture do not. This agrees with the explicit selectable-header contract. | header/Header.tsx:25–40; header/Mark.tsx:20; prompt/TextArea.tsx:97,128–132 |
| Queued prompts | Whole queue rows, message headers and more-count text are excluded, even where they display the person's words. | prompt/Prompt.tsx:568–598, especially 584 and 588 |
| User entry and assistant reply | Prompt text and Reply's explicitly selectable content are eligible; gutters/markers follow existing exclusions and Markdown serialization classes. | transcript/Transcript.tsx:120–149; transcript/Reply.tsx:198,260,278,283 |
| Thought | Thinking header is excluded; only the expanded trimmed body opts in. | transcript/Transcript.tsx:831–859, especially 842 and 848–853 |
| Tool headline and output | HeadlineText and actual summary/terminal output rows opt in. Review status, Guardian reviewing, fold counts and terminal exit/note text do not. | transcript/tools/Tool.tsx:155,216–224,263–270,452–480,646–679,787 |
| Tool diff | Separate diff summary and code rows opt in; number/sign/gap furniture does not. The separate summary is eligible Text, not the framework Diff's excluded decorative title. | transcript/tools/Tool.tsx:817–831,844–897 |
| Live or finished plan | Step descriptions opt in; marks, summary/fold counts and the Plan record title do not. | plan/Plan.tsx:37–52,73–98,115–153 |
| ReportEntry | Entire command header, labels and values are excluded; no source/separator contribution and no new parallel-row source API is required. | transcript/Transcript.tsx:598–629; all Text uses TEXT/FILL without opt-in |
| NotedEntry | Entire command header and both success/failure body are excluded; no source/separator contribution. | transcript/Transcript.tsx:636–674, especially 655,660 and 666 |
| Permission/cancelled/stopped outcome, Error/Warning entries | Outcome and Failure do not opt in; these lines are excluded even when they show an agent's reason/error. | transcript/Transcript.tsx:153–170,214–217; transcript/tools/Tool.tsx:980–1026 |
| Active permission composite | Controls, ordinary title/location/input, review/question and hints are excluded. The explicitly reused DiffRows code remains eligible inside that furniture; do not blanket-disable the authored diff. | dialogs/Permission.tsx:185–219,392–415,492–507,519–560; transcript/tools/Tool.tsx:893 |

Use an empty eligible provider root plus a disabled subtree for a wholly
excluded entry. For a partially eligible composite, preserve excluded rows
through S5a2 geometry-only children and wrap only the excluded bound widgets
in disabled boundaries. Keep eligible descendants, including permission diff
code, outside those disabled boundaries. Whole exclusion never adds a separator; selected
survivors before/after retain only their ordinary logical boundary. S5b tests
must cover direct excluded drags and crossing excluded rows, plus positive
header/draft/expanded-thought/tool/plan/permission-diff cases. This table covers
implemented types only; it does not advertise future original entry kinds.

Shared private pure shaping takes source, effective width and presentation
options and returns glyph rows plus fragment/range, hard/soft break and copy
projection metadata. Renderer and offscreen resolution use the same shaper.
Preserve current wrap algorithms. Glyph.sourceOffset from CTUI-50 is reused
but extended for code line/tab maps and Markdown's explicit soft-wrap rows.
Use existing characters segmentation/grapheme boundaries across style spans.
No screen-buffer scraping or post-copy stripping of furniture.

Only complete, exposed glyphs can start a selection, with the genuine blank-LF
source-boundary exception specified below. Clip masks, text alignment,
reverse paint order, followers and later occlusion use the same current paint
traversal as pointer hit testing. Excluded spans/ellipsis cannot expose hidden
source by taking one substring across discontinuities. Dropped wrapping spaces
have explicit soft-break metadata; padding does not. Blank source code rows
preserve LF when crossed, without inventing selectable padding. Selection style
merges before Canvas.put; whole wide glyphs are painted, syntax retained except
where the explicit selection style overrides it. Later paint naturally covers
highlight. Preserve cursor claim/overpaint semantics.

Intrinsic shaping eligibility determines copied units: truncation, ellipsis,
disabled spans and omitted rows never regain hidden source text. Temporary
viewport clipping and known overlay coverage instead mask exposed endpoint
hits, highlight and code visibleRects. They do not delete eligible interior
units from an established logical interval: crossed never-mounted/offscreen
items and known-occluded middle source text still copy in document order.
This is the design's logical-source distinction, not an original overlay
runtime-parity claim. Unknown coverage retains whole-area unresolved semantics
below; it cannot authorize a copy by treating an unknown hole as known.

### Pure self-paint coverage for S3

Expose only this bounded render-box coverage hook, so input geometry can use
actual paint coverage without painting or inspecting a screen buffer:

```dart
class PaintCoverage {
  PaintCoverage({required Type declaredFor,
    List<Rect> beforeChildren = const [],
    List<Rect> afterChildren = const []});
  const PaintCoverage.empty(Type declaredFor);
  final Type declaredFor;
  final List<Rect> beforeChildren, afterChildren;
}

// On RenderBox; the base implementation returns null.
PaintCoverage? describePaintCoverage(Rect localClip);
```

PaintCoverage is immutable; its constructor defensively freezes the rectangle
lists. Rectangles are in the box's local cell coordinates and describe only
cells actually written under localClip, in the phases before and after the
existing child paint traversal. They are not opaque bounds or a claim that a
whole box paints. Built-in primitives declare their own self-paint, including
fills/borders, glyphs and grid/count furniture in their actual phase. Glyph
coverage follows Canvas.put's clipped-wide-glyph fallback; fills use their
normal clipping. Transparent holes remain holes. This hook adds no dimensions,
new child traversal, general paint command/display-list API or terminal I/O.
It is pure over settled current geometry: never invoke paint, build/layout,
user callbacks or public synchronization recursively to obtain coverage.

Default null means unknown, not transparent. A declaration is accepted only
when `coverage.declaredFor == box.runtimeType`. Every built-in declaration
names its exact concrete type. A custom subclass must explicitly declare its
own runtime type, even when reusing an inherited layout-only paint method;
it cannot inherit permission to act transparent while overriding paint.
PaintCoverage.empty declares known no self-paint for that exact type. A custom
self-painting box that cannot express its coverage with these two phases stays
unknown. Never infer coverage from bounds, base class or pointer behavior.

If any paintable unknown subtree intersects the SelectionArea's effective
clip, the whole area's selection geometry is unresolved. Unknown outside that
clip, unmounted/measurement-only content and empty clipped surfaces do not
invalidate the area. Do not guess a hit, partial visible range or highlight
through unknown coverage. Suppress area hits/highlight and return null from
snapshot/codeBlockGeometry, an empty list from visibleCodeBlocks, and false
from revealCodeBlock. These are existing unresolved results, not deferred work
or a claim of source removal. Copy must obtain a synchronized snapshot; never
fall back to controller.value.text.

Cancel any active drag and release capture/drag resources without finalization
or automatic copy. A previously finalized logical range and its prior UI value
may remain for a later explicit retry; they do not authorize stale text or a
late finalization. Once coverage is known, reconcile sources and current
geometry normally before exposing hits/highlight or a successful synchronized
query again. Do not replay a cancelled gesture or a copy when coverage recovers.

S3 tests cover a transparent hole with content behind it, exact-type custom
subclass opt-in, unknown clipped out, unknown intersecting the area, recovery
from unknown to known, and no stale text/highlight or late finalization.

## Endpoints, capture and frame order

Original stub-only probes are retained as [endpoints](evidence/CTUI-48/interface-captures/endpoints.test.ts),
[results](evidence/CTUI-48/interface-captures/endpoints.jsonl),
[edge cases](evidence/CTUI-48/interface-captures/endpoint_edges.test.ts) and
[edge results](evidence/CTUI-48/interface-captures/endpoint_edges.jsonl).
Each probe passed at both required sizes. Auto-copy was disabled; injected copy
throws if invoked. Exact observations and commands are in the interface draft.

| Gesture | Normative result |
| --- | --- |
| Down/up same cell; same-anchor motion; moved out then back to anchor | Empty. A range requires distinct anchor/focus positions, not just a motion event. |
| Down at T of This, motion to s; reverse | `This`, both endpoint glyphs included, whole graphemes. |
| Down at T, motion to h, up at s | `Th`: release preserves last motion focus. |
| Down then up elsewhere without motion | Empty; release is not an independent move. |
| Past actual line right/left | Clamp to source line end/start, never screen padding. |
| Above/below last eligible focus source | Clamp to its start/end, preserving inclusive anchor. |
| Blank code row alone, even horizontal motion | Empty. |
| Blank row through echo done, forward/reverse | `\necho done`; a source LF remains. |
| Distinct prompt entry through reply, forward/reverse | `text\nHello, world. This reply came in chunks.` |

Internally store half-open grapheme intervals for nonempty ranges: lesser
endpoint starts its glyph, greater endpoint includes its whole glyph. Equality
is the empty special case. LF endpoints are source boundaries, not imaginary
painted spaces. A genuine blank source LF row supplies one boundary hit zone
across its effective content lane: any exposed lane x maps to the same logical
boundary. Code's lane excludes frame/padding and number/sign/continuation
gutters; TextArea's lane is its editable content width, excluding surrounding
prompt furniture and placeholder text. Horizontal motion on that one boundary
stays empty; crossing to nonempty source text retains the actual LF as in the
table. Unrelated empty layout never supplies a boundary, and coverage masks
suppress these boundary hits too. The retained original probe tests the first
content x and horizontal motion, not every x in the lane; no exhaustive original
runtime-parity claim is made for the lane clarification.

On no eligible hit, retain the last eligible focus source. A miss inside its
full current shaped geometry, including known-overlay-covered or
viewport-clipped interior rows, retains the last exact logical endpoint. Do
not project through the hidden cell or choose a nearest edge. Main explicitly
chose covered-interior retention as our own decision; no original probe exists
for that case. Actual exposed hits still update the endpoint or switch source.
True outside-line left/right and outside-source above/below positions keep the
established start/end clamps. Use full current shaped source bounds, not the
last exposed viewport row: a pointer over hidden geometric row 3 of a 100-row
source is an interior miss, whereas a pointer beyond its actual bottom clamps
to the eligible source end, including offscreen same-source text. Intrinsic
omission still excludes its units from copy. Never select a different
occluded/disabled source by geometric proximity. This closes the drafts'
ambiguous 'nearest boundary' wording. Motion into another source resolves the
full ordered interval immediately, including offscreen intermediate sources.

Extend MouseEventKind with move and synthetic cancel. Move carries the held
button, zero scrollDelta and original modifiers. Listener gains optional
captureController, onPointerMove and onPointerCancel:

```dart
class PointerCaptureController {
  PointerCaptureController();
  bool get isCaptured;
  void capture();
  void release();
  void dispose();
}
```

One controller attaches to one listener. capture() is legal only in its primary
down callback on the current route, otherwise StateError. Deepest first valid
capture wins; ancestor cannot steal it. Matching moves/up follow captured owner
and snapshotted ancestors, never a second fresh target route. Wheel uses fresh
ordinary hit routing and existing absorption. Skip a receiver disposed by an
earlier callback; new receivers wait for another event. Snapshot callbacks and
route flags once. No layout/rehit testing midway through that route.

Up ends its matching capture before callback. Capture epochs protect a new
drag created reentrantly from old-up cleanup. Explicit release cancels an
unfinished drag; detach, terminal suspension/inactivity, superseding primary
down, host disposal and crash cancel once. Clear host references first and
never invoke an already-disposed listener. A missing terminal release has no
timeout invented to recover it; next primary down cancels/restarts.

Enable button motion 1002 with current 1000/1006, never hover 1003. Parse SGR
motion bit 32 with a supported depressed button, retain modifiers, consume
unsupported reports and preserve bounded malformed/chunked-input recovery and
paste opacity. Selection accepts only unmodified primary drags; native terminal
modifier-selection remains available. Track 1002 acquisition/removal through
partial failures, suspension, resume, normal exit and supported signals; existing
port process/signal owner remains sole owner. Ownership loss cancels capture
before release; closing during suspension cannot reenable reporting.

BuildOwner/AppHost tracks an input-geometry epoch invalidated by source/tree
changes, scroll mutation, resize and controller changes even without setState.
Before creating a route, and through snapshot/query/reveal methods, a private
ensure-current path runs the existing bounded build/layout/afterLayout sequence
(maximum two passes) at current known terminal size, without paint or terminal
I/O. Reconcile sources, then project selection after settled layout, before
paint. Never add a third pass loop. Unresolved/still-dirty geometry cancels the
operation, without publishing stale text; a later explicit action can retry.
Each synchronized operation has at most two total passes, shared by its initial
ensure-current work, geometry-observer/notification effects and any
reveal-triggered scroll settlement. Reveal and observer delivery do not start
a fresh budget after a candidate layout or scroll change.

Notify geometry observers only after a stable candidate, with layout/settling
flags false. Their current-source projection and ordinary notifications may
cause a live parent to setState. If that dirties geometry, settle with only the
remaining pass budget and refresh current observers again after a stable
candidate. Do not falsely cancel after pass one while a retry remains. An
unstable candidate postpones observer projection until stability or final
exhaustion. Callbacks remain outside layout; this is not a deferred public
notification redesign.

At genuine exhaustion, notify unresolved once and return the existing failure
result, without stale text, third pass, fallback dispatch, replay or queued
retry/success/finalization. A later explicit operation can retry. Preserve input
and capture epochs across observer callbacks: reentrant real key, paste or
pointer input supersedes the outer operation, whose stale continuation must
neither dispatch its old event nor cancel a newer capture. Internal input epochs
cover those pre-route synchronization callbacks without changing normal routing
or adding public API. The generic guarantee for input during exhausted geometry
remains main's separate follow-up, not a promise of this bounded repair.
During layout/paint, public synchronization methods throw StateError rather
than recursively settle. Ordinary notification/reentrant mutation remains
outside layout using existing queued notifier discipline.

For S7 unchanged held/shown frames, reuse the current settled selection scene
and composed range only while the input-geometry epoch and root, boundary and
controller ownership still match. Source/tree changes, scroll, resize, ownership
change, clear, unresolved geometry or detach invalidate that reuse. Keep only
the current scene/range, without retaining old revisions or detached owners.
Actual pointer motion still projects the new cell. An explicit transcript
scroll, including a clamped scroll with no offset change, still admits current
inserted fragments under the held-identity rule; a matching geometry epoch must
not hide that intent. Public snapshot, matching release and reveal synchronize
and read fresh current geometry/text, never stale cached values after mutation
or unresolved settlement. Existing input/capture guards, notifications and the
same two-total-pass budget remain unchanged; no public API, retry or fallback
is added by this measured-work optimization.

Ordering is down→capture/epoch/hold. Real motion first synchronizes the prior
current geometry; only after success and a current input/capture epoch does it
store the incoming motion cell and admit/project current fragments. An older
refresh cannot overwrite that new motion. Explicit transcript scroll marks
moved, settles layout and admits current fragments, then projects last focus. A clamped explicit scroll still takes this
scroll path. Source/update-only refresh reconciles surviving retained IDs and
reflows endpoints within them, without admitting newly inserted fragments.
Up flushes pending geometry and reprojects the **last motion cell** within
those surviving identities, snapshots current text, releases capture/hold and
only then emits finalization. It never replaces focus with up coordinates or
treats release as fresh motion. A same-batch wheel/up or source-update/Ctrl+C
must read fresh text while preserving these identity/admission rules.
After finalization ranges are source-local; following new output never extends
them. Copy uses controller.snapshot() immediately, not an earlier value.text.

## Held scroll and code geometry

ScrollState gains held=false; ScrollController gains hold()/release() and pure
reduceHeld/reduceReleased. Hold snapshots offset and disables following even
when fitting. All measured/bottom/down/jump paths keep following false while
held. Release restores normal fitting normalization; otherwise the port calls
toBottom only if wasFollowing at down and no explicit transcript scroll since.
A clamped transcript scroll still sets moved. Child-consumed wheel does not
also scroll/mark the transcript. No timer, dwell, velocity or edge-scroll loop.
Shown selection retains logical sources, not a scroll hold or mounted window.

```dart
class CodeBlockId {
  // Framework-issued immutable token; no public constructor.
  Object get sourceId;
  // Value equality/hashCode include its opaque fragment token.
}
class MarkdownCodeBlock {
  final CodeBlockId id;
  final Object revision;
  final String text;
  final String? language;
  final bool complete;
}
class CodeBlockGeometry {
  final MarkdownCodeBlock block;
  final Rect bounds;
  final List<Rect> visibleRects;
}
```

The area registrar owns the private code geometry registry. Markdown supplies
current box or enclosing quote bounds; ListViewport supplies provider, effective
inset width and scroll controller. bounds is the full container rectangle in
terminal cells. Immutable, nonoverlapping visibleRects reflect actual exposed
paint cells, not a single bounding rectangle across an overlay hole. No live
geometry for measurement-only/unmounted/zero-surface blocks.

Controller visibleCodeBlocks returns current visible descriptors in paint
order; the port supplies transcript order separately. codeBlockGeometry returns
null when absent. snapshot/query/reveal all synchronize first; null/empty/false
means detached, removed, unresolved (including intersecting unknown paint
coverage) or settlement exhausted, never deferred work.
revealCodeBlock resolves provider source and shared-shaper local row without
mounting history. Whole container already within its viewport means no scroll;
otherwise align container top (quote top for quoted code, also for oversized
blocks), using itemTop plus actual insets. Settle within the same two-total-pass
operation budget, including any passes already spent before scrolling. Return
true only if that same current block is visible; normal next frame paints.
No private renderer crawl or Markdown parsing is required in the port.

Pinned markdown 7.3.1's FencedCodeBlockSyntax returns indistinguishable closed
and EOF-open code ASTs; closingFence is local/private. Existing Markdown demo
compiled AOT during this design pass, but this did not test a new adapter.
Main approved extending the existing block-syntax recording adapter through
public parser state to record consumed closing fence, including nested fences.
This adapter and truthful MarkdownCodeBlock descriptors belong to S2, so the
public SelectionSource.codeBlocks reports `complete` accurately from introduction.
S6a consumes those descriptors for framework buttons and picked styling; S6b
uses the geometry clients for port picking. Neither introduces or defers closure
truthfulness. No handwritten fence scanner/grammar.
If that approved public seam cannot supply the metadata, stop and report options. Indented code is complete; a
fenced block is eligible only after its actual closer. Test close-at-EOF,
EOF-open, appended closer, tildes/longer closers, list/quote nesting and empty
blocks. Existing characters/markdown/highlighting/dartdiff dependencies remain;
selection layout needs no package. No new dependency was installed.

## Key capture and shared matcher (S5a)

S5a is a separate framework unit before the port policy in S5b. Add optional
KeyHandler? onKeyCapture and PasteHandler? onPasteCapture to both Focus and
FocusNode, default null, using the existing bool-returning callback types.
A true result consumes input; false continues. Capture visits the active focus
path ancestor-to-focused before pending-chord handling, focused onKey/onPaste,
normal bindings or editing. Ordinary focused-to-ancestor behavior and scope
eligibility remain unchanged after capture. Paste capture sees even empty text.

Expose the existing binding matcher through this bounded surface:

```dart
enum KeyBindingMatchKind { exact, prefix, dropped, none }

class KeyBindingMatch {
  final KeyBindingMatchKind kind;
  final Binding? binding;
  final List<KeyCombo> sequence;
  bool dispatch();
}

// On FocusManager.
KeyBindingMatch matchKey(KeyEvent event,
    {bool Function(Binding)? where});
```

The manager issues results; fields and sequence are immutable. binding is
nonnull only for exact. sequence is the current pending chord plus this stroke,
or this stroke alone. exact/prefix describe enabled bindings on the full active
focus path; dropped means an existing pending chord has no continuation; none
means no pending chord and no match. A pure where predicate filters enabled
bindings before chord shadowing, so a modal binding cannot hide the explicitly
filtered selection-copy binding. The same extracted matcher serves normal
input: do not add a second recognizer, pending state, timeout or global keymap.

FocusNode.bindings snapshots each registration list defensively with
List.unmodifiable; its getter is read-only. Mutating a caller's original list
later, including mutation followed by restoration, cannot alter registrations.
Replace registrations through the existing setter/Actions path. A replacement
changes registration identity/epoch even when visible chords/descriptions are
equal but a callback differs, invalidating old capabilities. Preserve existing
catalog notification/no-op conventions where no registration replacement occurs;
no observable mutable wrapper or additional registration API is introduced.

matchKey only previews bindings; it neither invokes callbacks nor changes
pending state. It does not promise that a focused onKey handler would let an
ordinary binding run. dispatch is a one-use capability for exact/prefix only,
valid only during the same active key dispatch with unchanged focus route,
pending state, binding registration and input epoch. Stale/already-used results
return false with no effects. dropped/none dispatch also returns false without
mutation, especially for a filtered miss. Accepted dispatch uses the manager's
existing pending update or Binding.onInvoke and consumes exclusively. Normal
dispatchKey retains its existing full-path dropped-chord clear/swallow behavior.
Before accepting exact or prefix dispatch, revalidate current registration and
binding eligibility, including the original live pure where predicate. A filter
that now rejects the match makes dispatch return false without invoking an old
callback or changing pending state, even without a registration change. Prefix
must still be an eligible current prefix. Binding.enabled remains the existing
bool; its changes use registration replacement. No enabled-callback API is added.

Snapshot the capture path/callbacks for one input; skip detached/disposed
receivers. A newly focused node does not receive that old input. Reentrant input
invalidates the old continuation/result, so old processing cannot invoke a stale
binding or replay input into a replacement editor. Pending/binding/focus changes
invalidate already-issued matches; a deliberate pending cancellation can be
followed by a fresh match for the same active stroke. Existing chord expiry,
miss swallowing and ordinary action order remain the defaults.

The port's capture callback reads live policy in pure keys.dart. With shown or
copying selection, it dispatches only the filtered selection-copy exact/proper
prefix before form/modal processing; copying consumes without a duplicate copy.
A filtered dropped/none leaves unrelated pending state untouched. For other
input, full binding preview plus existing form/modal context determines whether
to clear selection/end picking before effects, then false permits ordinary
handlers. Never preserve selection merely because an outer printable binding
previews as exact when the focused form will consume the character. The ordered
route below remains authoritative. Default pending ctrl+x then raw Ctrl+C first
fails the explicit selection-copy chord check, cancels pending through the
existing manager, and proceeds through ordinary Ctrl+C/modal routing; a fresh
existing match may consume it if needed. No synthetic prefix/suffix replay.
Paste capture clears selection/picking before normal paste, including empty
paste, and returns false. All available actions stay registered through Actions
with descriptions/help. No Actions priority flag is added: a second precedence
knob would still need capture for pre-edit clears and could lag live state.

S5a tests cover ancestor/focused capture order, consume/pass-through, empty paste,
filtered exact/prefix versus unrelated pending drop, immutable result fields,
caller-list isolation/read-only getter, equal-label callback replacement and
live-filter rejection at exact/prefix dispatch, one-use/stale dispatch, callback
disposal and reentrant key/focus/binding changes,
unchanged normal handler/binding order and existing chord timeout/miss behavior.
A public focused-editor fixture demonstrates printable capture before editing;
port-specific selection/form policy is tested separately in S5b.

### Bounded prompt geometry repair in the S5a gate

Main approved making PromptInput's gutter positioned, clipped decoration rather
than a height-setting sibling. The editor alone determines prompt height; the
gutter follows that height without feeding another height change into layout.
Preserve existing visible rows/wording, keys, editable width and cursor columns.
This repair is limited to local prompt geometry convergence, alongside the
already-scoped completion convergence work. It does not add a global input
scheduler, fallback route or a guarantee that settlement exhaustion never loses
keys; that generic guarantee is main's separate follow-up.

Before the exact S5a tester gate, designer rechecks prompt 2→1 and 1→N row
transitions and same-batch clear/quit at 120x40 and 80x24, alongside the focused
capture fixture. Retain a sanitized failure-to-fix record for the /sta and
Ctrl-C repro/setup chains with source heads and repository-relative commands.
Distinguish a proven baseline failure from an uncommitted repair-chain failure;
raw diagnostic snapshots/private stack paths need not ship as evidence.

## Port behavior, keys and feedback (S5b)

S5b implements live selection/copy policy against the current permission,
form/editor, pending-chord and Ctrl+C contexts. It also supplies the shared
coordinator's code-origin API and tests for code-copy ownership/notes, without
introducing an unavailable screen action. After the separate S6a framework
button gate, S6b introduces the real code-pick reducer, actions/buttons, ctrl+x b
and their help rows, and owns simultaneous selection-plus-pick priority
acceptance. Do not register dormant/no-op pick bindings or advertise
pick/button rows in S5b. The complete coexistence route
below remains mandatory S6 acceptance, not a deferred semantic choice.

Keep plain reducers in ui/app/selection.dart and ui/transcript/code_pick.dart;
one window copy coordinator owns generations/timers. Widgets draw/dispatch.
Selection phases none/dragging/shown/copying are port policy over framework
range state. Drag remembers wasFollowing/moved. Auto-copy snapshots on release;
constructor false leaves a shown selection with `ctrl + c to copy`.

The minimal constructor/test seam is:

```dart
typedef Copy = FutureOr<CopyResult> Function(
    String text, CancellationToken cancellationToken);

TranscriptWindow({Key? key, required Launch launch,
  required StartConnection connection, Terminal? terminal, Copy? copy,
  bool copyOnSelect = true});
```

Copy and CopyResult belong to the port's selection module, not the framework.
Results distinguish sent, host-confirmed copied and failed; the coordinator
owns captured-text grapheme counts and sanitized note formatting. An injected
copy adapter wins over terminal. Otherwise use only the supplied borrowed
terminal's synchronous copyToClipboard and report sent; absent both adapter and
terminal, fail with the existing no-clipboard reason. Never create an implicit
StdioTerminal or invoke a native host clipboard. StartWindow accepts/forwards
the same borrowed terminal that bin supplies to runApp. Neither widget closes,
suspends or takes terminal ownership; existing process/signal owners remain.
Constructor spelling is copyOnSelect, default true, as already approved.

No unused Clock constructor field or new clock abstraction is introduced:
copy/note lifetimes are durations and ownership uses monotonic integer IDs,
with no necessary Clock.now read. The injected test clock is the existing
fake_async Zone, which controls Dart Timer and Future timeout scheduling;
controlled completers and the Copy adapter control async completion. Reuse
existing cancellation_token/characters and test fake_async; no new dependency.
One coordinator owns and promptly cancels pending-copy timeout and note-expiry
timers on supersession/replacement/disposal, with the generation/note-ID guards
below. A wrapper cancellation cannot undo an adapter that ignores its token;
deferred adapters check that token/ownership immediately before terminal effects.

One coordinator serves code and selection copies. Preflight UTF-8 length at
8 MiB, matching original service limit, before any write. This is port policy,
not a new Terminal limit. Production invokes synchronous copyToClipboard and
reports sent; errors become a sanitized one-line reason, oversize says
`too large to copy`. Count graphemes with characters. Inject the Copy adapter
and control the test timer Zone: original 1200 ms bound applies only to pending
adapters, not synchronous outcomes or an OSC 52 acknowledgement window. Timeout
says `the clipboard did not answer`.

Capture text, origin, copy generation, selection epoch and session identity
before invoking even a synchronous/reentrant adapter. Ignore repeated selection
copy while copying. A new accepted code/selection copy supersedes previous;
only latest live generation publishes. Selection completion also requires its
initiating epoch still copying, so clear/new-drag cannot inherit an old result.
Code completion follows its independent window note path. Cancel wrapper/timers
promptly on supersession/disposal; Future cancellation is cooperative. Never
claim a timed-out write was undone. Deferred test adapters check ownership
before terminal effects. Quit never awaits copy; no late note/write after exit.

| Outcome | Highlight and status |
| --- | --- |
| Auto-copy sent/success | Retain highlight; note expires at 3000 ms. |
| Explicit selection-copy sent/success | Clear highlight; note expires at 3000 ms. |
| Selection failure | Retain highlight and persistent `could not copy: reason · ctrl + c to try again`. |
| Code copy sent/failure | End pick; note expires at 3000 ms, failure has no selection retry clause. |
| Empty pick | `No code block to pick` for 3000 ms. |

Production note is `sent N chars to the terminal's clipboard`. A future injected
host-confirming result may format original `copied N chars to clipboard`; the
production OSC 52 adapter cannot construct that result. Note expiry checks
monotonic note ID and never owns highlight lifetime. Notes stand alone on the
status row; error tone for failure, normal notice tone for sent. Closing/armed
quit outrank pick hint; pick hint outranks ordinary notes/mode/facts.

Any ordinary key/paste clears selection before existing behavior, including
empty paste, so draft text is never replaced by a mouse selection. Resize,
verbose toggle, clear, session change, editor/terminal handoff cancel selection
and drag before their action; source removal clears when no selected text is
left. Keep prefixes and transcript scroll, with precise exceptions below.

### Ordered key routing

This is the full normative route. S5b exercises selection against existing
contexts; S6 adds its real pick branches and the coexistence matrix without
changing the ordered contract or adding placeholder actions earlier.

Extend current pure keys.dart and Actions; do not install a competing recognizer.
Every action has descriptions/help. Existing editor/modal contexts remain in
their current relative order; selection decision is read at dispatch.

1. Closing performs existing closing behavior, starting no copy/pick.
2. With shown **or copying** selection, resolve exact rebound selection:copy
   over pending chord plus stroke, then its proper prefix. Exact consumes the
   key exclusively; copying starts no duplicate. This precedes form/search
   printable suppression and modal lookup.
3. Existing binding lookup uses pending chord. A raw Ctrl+C selection override
   applies only with no pending chord. Preserve existing background/context
   priority after the explicit selection-binding rule. Then attention, own
   code-pick commands, codeBlock:pick, existing picker/request/editor actions,
   ordinary Ctrl+C/Ctrl+D and remaining existing commands/scroll/completion.
4. No command: proper prefix of live bindings means key_pending; otherwise a
   pending chord means key_dropped. Drop a miss, without replaying prefix or
   suffix as typing. Existing keyboard-layout retry remains in keys.dart.
5. Before effects, shown/copying selection clears unless command is
   copy_selection, key_pending or transcript scroll_*. Then end code pick
   unless command is a code-pick action, key_pending or transcript scroll_*.
   Resolve existing taken-back typing/prefix bookkeeping, clear pending for
   a completed command and execute its normal effect.

Consequences are normative: selection copy ends a simultaneous code pick;
code-pick arrows/c/Esc clear a simultaneous selection before acting on pick.
Prefixes/transcript scroll preserve both. Request/panel **key** scroll clears
both, matching original command classes; wheel retains existing independent
routing. ctrl+x b clears selection. Default ctrl+x then ctrl+c is ordinary
Ctrl+C fallback (draft clear/quit, or existing modal interrupt), not selection
copy; an explicitly rebound selection-copy chord ending Ctrl+C instead wins
step 2. ctrl+x z drops both prefix/suffix after clearing selection/pick.
Printable rebound selection-copy/prefix works in a form before typing suppression.

### Code buttons and mode (S6a/S6b)

S6a activates the approved framework Markdown copy callback, picked styling,
button hit/capture behavior and matching source/shaper geometry. It passes its
own API, screen, review and test gates before S6b edits consume it. S6b supplies
the port catalog, pick reducer, actions, keys/help and simultaneous selection
priority. This is staging of the existing API and behavior, with no new scope.

S6b renders the pending-chord leader from live KeyHelp state, without an
afterLayout mirror into AppState. Query and reveal the current code target
before mutating pick-state styling. This removes the additional port
notification/layout work that could consume the existing settlement budget
before same-batch ctrl+x b dispatch. Preserve all key wording, the shared
matcher, Focus notifications and the same two-total-pass budget; no third pass,
input replay or generic key-delivery fallback is introduced. CTUI-51 retains
the general exhausted-geometry key-delivery follow-up.

Keep the existing live status row inside the unconditional Transcript.footer,
after the prompt parts that depend on canSend; remove the outer duplicate.
Retain its stable keyed Padding2 and exact cells, width, order, height and cursor
placement across startup, non-send, failure, connected and closing states.
This keeps command-binding changes and live KeyHelp inside the same
layout-built subtree, without changing framework APIs, Focus notifications or
the operation budget. Recheck /sta and same-batch pick geometry at both sizes.

At120x40 and80x24, retain a same-batch ctrl+x b regression proving the live
pending presentation and current-target pick/reveal converge within that
budget. Preserve the narrow red-to-green reproduction and distinguish its
uncommitted S6b WIP provenance from a proven committed baseline.

Only closed ordinary code boxes get `[copy]`; quoted code has no button but
remains keyboard-pickable. Buttons sit at right of top border, one border dash
before/after, no blank padding. Grow a short box to minimum width if column
allows: unlabelled 10, labelled label-cell-width+13 (ts 15, console 20).
When the actual column is narrower, omit copy before existing label clipping;
keys still work. No hover. Normal button uses text colour on dim frame; picked
frame/label/button use accent, button bold. Plain uses terminal foreground and
bold. Preserve current code inset/wrapping.

Same primary down/up on same still-visible button ID/revision with no movement
is a click. Release outside, reflow moving button away, disposal, movement or
text drag ending there never clicks. A button press clears selection and
captures independently; wheel never activates. Keyboard and click call the same
copy path. Code copy uses complete source, preserving code blank lines/tabs but
omitting the parser's structural final fence newline, never rendered borders.

The port follows original ui/app/terminal.ts:692–695: copying an empty code
body returns before coordinator mutation. Do not call Copy(''), create a note,
cancel an existing copy or change its generation. Normal interaction effects
still apply: the copy key ends pick and a button press clears the range.
An empty block is distinct from an empty catalog, whose No code block to pick
notice still lasts3000ms. Generic framework empty descriptors/callbacks and
the Terminal clipboard service retain their existing behavior.

ctrl+x b picks newest partly visible eligible block; if none, newest listed
closed block. Listed assistant replies/supported messages are reachable even
unmounted. Tool/plan code is eligible only while its current geometry is visible;
no future entry types are advertised. Prove visible-only Markdown eligibility
with a generic mounted Markdown source/geometry fixture. Current plain Plan,
PlanRecord and Tool summary renderers do not produce Markdown code descriptors;
negative tests must keep them out of the catalog even when their plain text
contains fence-like content. Do not change those renderers or parse their raw
text to manufacture the formerly requested visible-plan target. This replaces
that impossible current-type acceptance case, without removing generic
visible-only Markdown eligibility. Catalog caches per current source revision;
framework descriptors/parser supply code, never a port fence scanner. Order by
entry then framework block traversal; deduplicate by CodeBlockId. On next move,
a removed pick falls back to newest eligible; no remaining target ends pick.
Copy/activation always revalidates current descriptor, never stale source.
Resize cancels selection/drag but retains a still-valid logical code pick.
Its compact hint continues to outrank ordinary notes; copying after reflow
revalidates the current descriptor. Resize is not an unrelated key action that
ends pick.

Up/down move/clamp in order and reveal whole container if possible; otherwise
top-align it. c ends pick and copies. Esc ends pick without interrupt/edit.
Unrelated keys end pick then run normal behavior; pending prefixes and transcript
scroll preserve it. In this staged slice r is ordinary input, no dormant run
binding. Use described bindings for ctrl+shift+c (Copy selection), ctrl+x b
(Pick a code block), up/down, c and Esc. Ctrl+C retains reserved contextual
behavior. Legacy Ctrl+Shift+C decoding to Ctrl+C still copies a shown selection.

Add help rows in original order with actual registered keys:

```text
ctrl + c to copy
ctrl + x b to pick a code block
c to copy the picked block
```

Leader includes `b a code block`. Pick status at 120x40 and 80x24:
`↑ ↓ another block · c copy · esc done`. At narrower/rebound widths try
`↑ ↓ block · c copy · esc done`, then complete items that fit in order, then
bare cancel key, then `picking a code block` if no usable cancel. Never cut an
item through except the final unavoidable narrow-key/words truncation. No run
clause until CTUI-25. Keep CTUI-21 binding/catalog consistency checks.

The real supported pick help rows participate in normal catalog sizing. In the
existing --help --tall-draft fixture they naturally make the 80x24 panel
overflow (12 rows, room11, two below), while 120x40 fits. Preserve normal wheel
routing, closing, draft and focus; do not trim catalog entries or manipulate
room to retain the old fit assertion. Record the actual staged geometry and
below rule at the exact S6b handoff. Earlier CTUI-47 M1 fitting evidence remains
historical and is not rewritten.

## Build units and acceptance

Each unit is a separate reviewable handoff on the named implementation head.
S1–S4, S5a, S5a2 and S6a build framework behavior and own framework tests;
S5b and S6b use it through public exports. S5a's capture/shared matcher and S5a2's
geometry-preserving eligibility each pass their own API review/test gate before
S5b consumes them. S2 includes the approved closure adapter and truthful
code-block descriptors; this piece moved from S6 because SelectionSource.codeBlocks must
report `complete` accurately when first public. S6a retains framework buttons,
picked styling/hit/capture and source/shaper geometry; it passes its own gates
before S6b port geometry clients, catalog, picking and help consume it. This
changes build order only, with the same approved parser seam, scope and
dependencies. S7 is final integration evidence,
not a substitute for tests.

| Unit | Deliverable | Tests that must fail before implementation |
| --- | --- | --- |
| S1 | Typed motion/cancel, 1002 ownership, Listener capture and dispatch epochs | Fragmented/combined SGR, modifiers/unsupported recovery/paste, capture outside/up, fresh wheel absorption, callback disposal/reentrant new down, suspend/resume/exit/partial failure cleanup. |
| S2 | Immutable source snapshots, pure range/reconciliation model, shared Text/Markdown/Code/Diff/TextArea mapping, approved closure adapter and truthful code-block descriptors | Exact serialization table at both widths; tabs/emoji/combining/wide cells/style splits; soft/hard breaks, gaps, quote/table exceptions, hidden spans; unique earlier insert/remove, same-source clamp, duplicate ambiguity, reparenting/retyped container, crossed anchors, full reference reparse and old-snapshot immutability; frozen presentation defaults, bound override mismatch/null rules, ordinary inherited Text geometry and mounted/never-mounted shaping parity; truthful complete metadata for nested/open/closed/EOF/tildes/longer closers/empty fences, appended closer and indented code. |
| S3 | SelectionArea/disabled regions, delegate, current geometry/snapshot/query/reveal, pure self-paint coverage and highlight | All endpoint probe cases, reverse mixed header/list/draft ranges with LF, never-mounted intermediate entries, clipping/occlusion/zero surface, same-batch update+copy and wheel+up, two-pass exhaustion, no callbacks during layout, disposal; transparent holes, exact-type coverage declarations, unknown clipped out/intersecting, unknown-to-known recovery and no stale text/late finalization; intrinsic omission versus known occluded copy interiors, blank-LF lane bounds, retained clipped/covered interior endpoint versus full-source outside clamp, live-receiver finalization after reentrant clear/new drag, shared two-total-pass reveal exhaustion, and held update/removal/release reconciliation with current survivor reflow but inserted-fragment admission only on real motion/explicit scroll (including clamped scroll). No offscreen widget retention. |
| S4 | Scroll held state, controller/reducer all paths and selection integration | Fit→overflow while held, fitting normalization, clamped scroll marks moved, following restoration, stationary-focus scroll projection, source-local range after release; no edge timer or periodic frame. Preserve CTUI-49 one-row extents. |
| S5a | Framework key/paste capture and shared binding preview/one-use dispatch | Capture order/consume/pass-through including empty paste; filtered exact/prefix/miss without unrelated pending mutation; immutable result and stale/used dispatch; caller-list isolation/read-only registrations, equal-label callback replacement, live-filter rejection at exact/prefix dispatch; disposal/reentrant input/focus/binding changes; ordinary route/chord timeout/miss regressions; focused-editor fixture; bounded prompt gutter convergence at 2→1/1→N, same-batch clear/quit at both required sizes, retained /sta and Ctrl-C failure/fix setup chain. |
| S5a2 | Framework geometry-preserving selectable source children and authoritative provider registration | False first/middle/last/all and exact separators; nested excluded code descriptors/geometry; wrapped decorative height; provider-bound mounted hits versus offscreen copy with no automatic re-add; eligibility toggle lease release/no resurrection; immutable old snapshots and revision changes; fresh-source snapshot/release with live-parent geometry observers at both required sizes, same total2 settlement including notifications, no false cancellation while a retry remains, reentrant input/capture supersession. |
| S5b | Port pure selection/copy policy, coordinator, theme, borrowed terminal/Copy injection, constructor seed, ordered keys/help | Auto-copy on/off; release retain vs explicit clear; persistent selection error vs timed block error; size preflight/grapheme count; sync throw/reentrant/delayed/timeout/ignored cancel; generation/epoch/session and note-ID races; pending Ctrl+C/miss/rebound form and current permission/form/selection priority; draft/empty paste; shared coordinator code-origin ownership/notes API tests without dormant pick actions/help; CTUI-15 occurrence-token append/replacement/duplicate/retention regressions; explicit current-type opt-in/exclusion table including selectable header, excluded queue and eligible active permission diff. |
| S6a | Framework Markdown buttons, picked styling, hit/capture and source/shaper geometry, consuming S2 descriptors | No open button; exact full-word click bounds; quote no button; narrow suppression/minimum width; picked styling; moved/reflowed/disposed target and release outside; no activation from drag or wheel; bound-source geometry agreement; generic visible-only Markdown source/query proof. Own API/screen/review/test gate before S6b. |
| S6b | Port geometry clients, catalog, code-pick reducer, real buttons/actions/keys/help and coexistence | No open pick; newest visible/listed, clamped arrows, offscreen quoted/nested reveal via public API, generic visible-only Markdown eligibility, negative current plain Plan/PlanRecord/Tool summary targets, removed pick; no source parsing or renderer change to invent code; real ctrl+x b/buttons/help and the full simultaneous selection+pick priority matrix, including permission/form/pending contexts; live KeyHelp pending presentation without an afterLayout AppState mirror, query/reveal before pick styling, and same-batch ctrl+x b convergence at both required sizes within the existing two-total-pass budget, with exact red/green provenance. |
| S7 | Public framework demo, port fixture/fake-window, compiled PTY and paired visual evidence | Real implemented port vs original at both required sizes, themes/states below; actual binary mouse/key path and bounded pending-copy exit with fake child/recording clipboard. Cleanup all owned resources. |

Test via package:chorded_tui/testing.dart, pure reducers and controlled test
clocks (fake_async Zone timers for copy policy), copy recorders and controlled
completers. No real clipboard/model/agent. Use scripted session updates for exact source removal/revision ordering and original
fake for existing Markdown/long/flood scenarios. No changes under ../chord.
Run relevant framework/port suites, required static checks and compile-tag
coverage against exact handed commit. Compile public demo and port with
`dart compile exe`; no runtime code loading/Flutter SDK/new package required.

At 120x40 and 80x24 check empty/header/draft; forward/reverse held drag;
auto-copy note then retained highlight; seed false copy hint; explicit success
clear; persistent failure/retry; streaming mutation and open→closed code;
permission-context precedence; overflow/scroll; quoted/table/diff selections;
button suppression in genuinely narrow columns; code-pick movement and missing
block. Dark/light/plain must prove contrast and plain no fg/bg escape. Retain
plain+ANSI failure/fix captures, source heads, exact setup and clipboard stub
results. Text captures/byte injection are not physical pointer/cursor proof.

Measure no-selection, held and shown runs at 600/10,000 entries, including
1000 updates before a frame. Report visible mounted states/builders, retained
source/range counts, parser calls, root resolutions, scene/range compositions
and frame times separately. Steady unchanged selection frames must not
parse/flatten history and must reuse the settled scene/range rather than
re-resolving history roots or recomposing an unchanged retained range; zero parsing alone is insufficient proof. Report
per-frame deltas so unchanged held/shown work cannot hide scaling with history
or selected-range count. Include invalidation/freshness regressions for source,
tree, scroll (including clamped intent), resize, ownership, clear, unresolved
geometry and detach, plus actual motion and current snapshot/release/reveal.
Run the measured600/10,000 cases under AOT with retained exact-head results; no-edge stationary pointer
causes no periodic work. Crossing can cost O(crossed source bytes), copy
O(selected bytes); visible maps O(visible cells), retained model leases only
current selected sources. Clear returns selection references to baseline.
Existing exact-height first-layout/resize cost remains CTUI-1's accepted cost,
not a new constant-time promise. If measured behavior requires changing that
contract, report the owner options rather than weakening it silently.

## Critic disposition

All findings accepted; none rejected. The final text closes each:

1. Stable identity/model lifetime: previous snapshots, opaque tokens, parent/
   serialization-compatible noncrossing reconciliation and domain replacement
   IDs; explicit duplicate/reparent/full-reparse tests.
2. Private geometry inaccessible to port: controller query/reveal methods,
   actual visibleRects, source descriptors and quote/top alignment.
3. Stale snapshots/dispatch races: synchronized public snapshot, pre-route
   bounded geometry, skip disposed receivers and capture epochs.
4. Endpoint gate: two stub-only original probes, inclusive nonempty ranges,
   equality empty, last-motion release, no-hit clamping and blank LF rules.
5. Mixed source order/separators: region slots/provider expansion, explicit
   port boundary LF versus Markdown one-space gaps, reverse exact-string tests.
6. Key precedence: one ordered route including copying/pick coexistence,
   pending Ctrl+C, misses and body-key-scroll exceptions.
7. Example mismatch: one text: spelling, full provider/binding example and
   selectable header text with disabled logos/furniture.

Critic reread the merged design and appended decisions: all seven findings
addressed, no remaining contradiction within that review scope. This is
design/source/evidence consistency approval, not implementation/runtime acceptance.
No owner question remains. Any package failure beyond the specifically approved
public adapter, unavailable fidelity or failed acceptance is a new handoff,
not permission to invent a workaround.
