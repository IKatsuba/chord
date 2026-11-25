# CTUI-2: positioned children and anchored layers

Framework design for ship 9. Sources: `../chord/src/ui/AGENTS.md`,
`../chord/src/ui/prompt/Overlay.tsx` and `overlay.ts`. CTUI-1's list and
build-during-layout mechanism remain the foundation. CTUI-39 supplies
LayoutBuilder. This slice implements framework primitives, not chord's
prompt, completion reducers or picker composition.

## Positioned

```dart
Stack(children: [
  transcript,
  Positioned(left: 0, right: 0, bottom: 0, child: belowRule),
]);

const Positioned({Key? key, int? left, int? top, int? right, int? bottom,
  int? width, int? height, required Widget child});
```

Coordinates and dimensions are integer cells. Like Flutter, at most two
of left/right/width and at most two of top/bottom/height may be supplied;
width and height must be nonnegative. Negative edge offsets are allowed.
Positioned must reach Stack without another render object between them.
Use a RenderPositioned proxy as the stack's direct render child, matching
Flexible's existing wrapper approach; no general parent-data mechanism.

Stack keeps its existing top-left alignment and loose nonpositioned-child
constraints. Only nonpositioned children determine its natural size,
constrained by its parent. With only positioned children, fill bounded
axes and use the minimum on unbounded axes. A pair of opposing edges gives
the child a tight size of max(0, stack dimension minus both offsets).
An explicit dimension gives a tight size. Otherwise that axis is loose
up to the stack dimension. Left/top wins placement when supplied;
otherwise right/bottom places the child's far edge; neither means zero.
Children paint in declaration order. Clip all stack children to its bounds,
including negative placements, without splitting wide graphemes. A tight
Stack stays that size when any positioned child's size changes.

## Overlay API

```dart
final link = LayerLink();
final page = OverlayEntry(builder: (context) => const Window());
Overlay(initialEntries: [page]);

// In Window, above the prompt, always mounted even with no entry:
CompositedTransformTarget(
  link: link,
  child: const SizedBox(height: 0),
);

// A descendant opens a command picker:
final entry = OverlayEntry(
  builder: (context) => CompositedTransformFollower(
    link: link,
    targetAnchor: Alignment.topLeft,
    followerAnchor: Alignment.bottomLeft,
    child: LayoutBuilder(builder: (context, room) =>
      CommandPicker(room: room.maxHeight, columns: room.maxWidth)),
  ),
);
Overlay.of(context).insert(entry);
// Accept or cancel, through described Actions bindings:
entry.remove();
entry.dispose();
```

Public shape:

```dart
Overlay({Key? key, List<OverlayEntry> initialEntries = const []});
OverlayState Overlay.of(BuildContext context);
OverlayState? Overlay.maybeOf(BuildContext context);
OverlayEntry({required Widget Function(BuildContext) builder,
  bool requestFocus = true});
// OverlayEntry: mounted, markNeedsBuild(), remove(), dispose().
// OverlayState: insert(entry, {OverlayEntry? below, OverlayEntry? above}).
LayerLink();
CompositedTransformTarget({Key? key, required LayerLink link,
  required Widget child});
CompositedTransformFollower({Key? key, required LayerLink link,
  Alignment targetAnchor = Alignment.topLeft,
  Alignment followerAnchor = Alignment.topLeft,
  Offset offset = Offset.zero, bool showWhenUnlinked = false,
  required Widget child});
FocusScope({Key? key, FocusScopeNode? node, bool autofocus = false,
  required Widget child});
FocusScopeNode({String? debugLabel});
```

Entries paint bottom to top in insertion order. above/below are mutually
exclusive and must belong to this overlay. An entry belongs to one overlay;
remove detaches it, dispose releases an already removed entry. Removing an
entry twice is harmless; insertion after disposal is an error. Removing
Overlay unmounts its entries and releases its scopes. initialEntries are
initial, as Flutter's; updating the list does not replace active entries.
Entry builders inherit at Overlay's location, not the caller's location.
Put Theme and app-wide Actions above Overlay, or explicitly pass local data.
The bottom entry is the ordinary base and is laid out at the overlay's
constraints; it remains mounted when floating entries change. Overlay needs
bounded width and height. Ordinary entries receive the overlay's bounds;
a follower narrows these as specified below. No automatic centering, frame,
dismissal key or background belongs to Overlay itself.

## One tree, local layout walk

RenderOverlay lays out the base first, then walks that completed subtree,
summing each child's offset, to collect target rectangles keyed by link.
It stops at nested overlays, which own their own links. Targets referenced
by this overlay must be in its base; targets in floating entries are out.
Two mounted targets with the same link are an error. Entries use the
existing BuildOwner.buildDuringLayout to mount their children; the render
object then lays them out and paints them after the base. RenderBox stamps each layout with the current layout-pass counter, and
AppHost starts that counter before each root layout. The target walk skips
boxes without the current stamp, including children a parent kept mounted
but did not lay out. The lead approved this small RenderBox/AppHost addition
to make the unlaid-out guarantee explicit. No render-parent API, global-offset
pass, host paint hook, reparenting or second tree is needed. The lead approved this local walk as part of the new render object.

Only targets actually reached in the completed base tree are linked. A
missing, unmounted, unlaid-out or virtualised-away ListView target is
unlinked, including items built only temporarily for measurement. No
previous-frame rectangle is reused. With showWhenUnlinked false, the entry
has no paint and cannot take focus or expose Actions. Its state may stay
mounted, but its keys are inactive. With true, lay it out at the overlay's
origin, with ordinary overlay constraints and offset, and clip to the
window. This option is not used by chord. Moving a target, scrolling or
resizing triggers a fresh local walk every frame even when the entry's
widget has not changed. Relayout the follower with the new rectangle and
room; rebuild its LayoutBuilder only if its constraints changed. Never
rebuild the base merely because an entry opened, closed or moved.

The existing host lays out the whole tree each frame. Thus "without
relaying out what is under it" means that layers do not alter the base's
constraints, allocated rows, scroll geometry or follow state; it does not
promise skipping the base's ordinary layout call. Opening an entry does
not invalidate the transcript's item heights or reconstruct its elements.

## Anchoring, room and opaque paint

A follower must be its entry's root render object or sit beneath only
single-child render wrappers that add zero offset. A multi-child render
ancestor inside the entry (including Stack or Flex), or a nonzero-offset
ancestor between the entry and follower, is an error, asserted by the
implementation. Place Padding, Stack, Flex or other positional decoration
inside the follower instead. This is the
lead-approved small-slice restriction, unlike Flutter's general follower.

The follower's anchor point equals the target anchor point plus offset.
For a bottom follower anchor, available height is the rows above that
point; for a top anchor, it is the rows below it. A centered anchor gets
twice the smaller distance to the two bounds. Apply the same rule across
columns, intersecting with the overlay bounds. All arithmetic uses integer
cell Alignment placement. Child constraints are loose from zero up to that
room, so a short picker hugs its bottom anchor and a tall one can reach
row zero. A zero-height target is valid and supplies its width from its
parent; chord's anchor takes full window width. The follower clips both
paint and descendant overflow to that room and the overlay rectangle.
No cell at or below the bottom anchor can be painted by an upward follower.

A floating surface must overwrite every cell in its own laid-out rectangle,
including blanks, with terminal-default background before painting its
child. This is the follower's default paint behaviour, using the renderer's
default background rather than a theme-specific RGB. That clears transcript
characters as well as colours and works in NO_COLOR. It fills only the
child's actual rectangle, not the entire available room. Frameless chord
completions supply their own dim top rule; framed pickers supply their own
frame. CTUI-2 adds neither. A chord picker and completion list share one
entry: the picker gets room first, the list gets what remains; the original's
room reducer, rule and body-cutting policy belong to the later port slice.

## Focus and keys

Every floating entry owns a FocusScope. requestFocus defaults true: after
the entry is linked and laid out with positive room, save the previous
primary node and move focus to its autofocus descendant, or its scope if
none. Tab and Shift+Tab stay in the top focused entry's eligible descendants;
the scope itself holds focus if none exist. Implement these traversal
actions through described Actions bindings so KeyHelp includes them.
Closing restores the saved node only if still attached, not disposed and
eligible. Otherwise use the most recent eligible node in the enclosing
scope, then that scope's first eligible descendant, then its scope node.
At the outermost level use the base scope's first eligible node, or clear
primary focus if none. Never request focus on a detached/disposed node.

Nested entries restore in stack order. Removing a covered entry must not
steal focus from the top one; restoration skips removed scopes. Losing a
link or all available rows suspends the entry's focus and bindings with the
same fallback; when room returns a requesting entry can take focus again,
unless a newer focused entry is above it. Reset pending key chords at scope
changes. Scope traversal and saved-node tracking belong in FocusManager;
FocusScope follows Flutter's public naming and is usable outside Overlay.

Passive completions use requestFocus:false: the prompt keeps focus, paste,
normal draft submission and its own completion Actions. The entry does
not intercept traversal or steal focus on mount, resize or relink. At zero
visible rows the port disables completion acceptance/navigation, including
pending picks, as the original requires. Overlay itself binds no Esc;
Picker/Dialog binds Esc with its own description. Base-only Actions are
siblings of focused entries and cannot receive their keys. App-wide Actions
above Overlay remain reachable, including quit and the shortcuts panel.

## Text mocks and states

These are design mocks, not runtime captures; unshown rows stay unchanged.
Both widths use a full-width anchor immediately above the protected prompt
gap. At 120x40, anchor y=36; at 80x24, anchor y=20. A four-row framed picker
occupies rows 32–35 or 16–19 respectively; a 40-row picker is constrained
to 36 or 20 rows. The transcript retains its 36 or 20 allocated rows.

```text
120x40                           80x24
row 31 transcript still here      row 15 transcript still here
row 32 ┌──────────────────…┐      row 16 ┌──────────────────…┐
row 33 │ Models            │      row 17 │ Models            │
row 34 │ Esc to close      │      row 18 │ Esc to close      │
row 35 └──────────────────…┘      row 19 └──────────────────…┘
row 36 [prompt gap]               row 20 [prompt gap]
row 37 > /model                   row 21 > /model
row 38 [permanent status]         row 22 [permanent status]
row 39 [permanent hints]          row 23 [permanent hints]
```

Empty overlay: base alone, unchanged focus and no additional rows. Focused
entry: frame uses theme.focus when supplied by its content; passive entry
has no automatic focus decoration. Overflow: cut within available rows,
never across the prompt. Narrow: clip to supplied width; no minimum width
may escape the window. Zero room/unlinked: no paint or entry keys. Filled
blank areas must hide a patterned transcript in dark, light and plain.
These framework mocks intentionally contain no chord wording commitment;
the port must compare its completed screen with original captures later.

## Units in build order and acceptance

1. RenderPositioned and RenderStack positioning, plus Positioned. Test each
   axis combination, rejection of triples, natural size, all-positioned and
   unbounded cases, negative offsets, clipping and paint order.
2. LayerLink, target/follower render objects, RenderOverlay and Overlay's
   element child manager on buildDuringLayout. Test same-frame anchors,
   zero-row targets, movement with unchanged entry, missing/virtualised
   targets, room constraints, opaque blanks and nested overlay isolation.
3. FocusScopeNode/FocusScope and manager traversal/restoration; overlay
   entry lifecycle and active scope. Test nested/out-of-order removal,
   disposal of the saved node, no eligible fallback, pending chord reset,
   passive entries, unlink/relink and zero room.
4. Runnable framework fixture: a streaming transcript with scroll-back,
   zero-row anchor, framed and frameless layers and a focused picker.
   Demonstrate stable base build counts, height, offset and following across
   open/close, movement and resize; record screenshots at 120x40 and 80x24
   in dark/light/plain, plus missing anchor and no room. Designer looks
   before reviewer. No port implementation or maintained package is needed
   for these terminal layout and focus primitives.
