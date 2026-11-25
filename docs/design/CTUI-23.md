# CTUI-23: floating slash completion

Sources: `../chord/src/ui/prompt/commands.ts`, `Prompt.tsx`, `Overlay.tsx`,
`overlay.ts`, `src/ui/app/keys.ts` and `state.ts`. Original baseline head:
`577b58167672e12c999aeaf4eed2a1a988513dc2`. Original live captures are under
`docs/design/evidence/CTUI-23/`, at 120x40 and 80x24. They include future
commands; the supported subset below is the lead/main-approved staged scope.

## Composition and appearance

Use existing exported PickerState for matching/highlight movement, with
`moved(step, wrap: true)`, and ListView/ScrollController for the viewport.
The port supplies command data, dispatch, row content and described Actions;
no public completion widget is needed. The U5a visibility getter below
closes the zero-room boundary found during integration. Do not use a
focus-taking Picker whose numeric and j/k acceptance conflicts with typing.

A zero-height anchor stays mounted above the prompt. The existing Overlay
follower bottom-left attaches to its top-left. The floating layer fills its
background and spans the window width, without consuming transcript rows or
changing transcript offset. Its bottom remains above the prompt's gap; it
never paints on the prompt/status. A framed picker takes its natural bounded
height first, and completion uses only the room left beneath it. Without a
frame, one dim rule precedes completion, inset one cell each side. With a
frame, omit this extra rule. All paint clips at the top of the window.

At 120x40 completion permits ten item rows; at 80x24 it permits six. In
general the limit is max(3, floor(windowRows / 4)), further bounded by room
after frame/rule. No hidden-count footer, numbers or selection glyph is
added. Name and description are one cut row each. One shared name column is
min(widest displayed command label + 2, floor((width - 4) / 3)); measure
all matching items so the column stays still while scrolling. The list is
inset two cells. Selected row text uses the permission/mode colour; other
rows are dim, following the original. No fill highlight is introduced.

Original examples (remaining window rows unchanged):

```text
 ──────────────────────────────────────────────────────────────────────────────
  /model  Switch the agent's model

╭──────────────────────────────────────────────────────────────────────────────╮
│ › /model                                                                     │
╰──────────────────────────────────────────────────────────────────────────────╯
```

The same filtered item uses one row at either required size. The unfiltered
original captures show ten/six rows respectively. Staged port captures will
have fewer commands, deliberately, in the original alphabetical order.

## Input and lifecycle

Offer the list only for a draft matching slash plus a non-whitespace name
with nothing before it: `/` offers all, `/mod` matches fuzzily, a space or
second line closes it. Agent descriptions use their first trimmed line.
Local command names win duplicates. Supported local commands are clear,
config, effort, exit, fast, help, model and status. Other original-owned
names stay reserved locally, absent from completion and never sent to the
agent. The lead's decisions entry records this staging.

Up/down wraps the highlighted match and moves the least necessary window
to keep it visible. Digits, j/k and other text edit the prompt normally.
Tab inserts the highlighted command's full name and trailing space; Enter
runs that highlighted item (a local command dispatches locally; an agent
command sends its slash/name). Once arguments are typed Enter uses the typed
command and arguments. Esc dismisses completion and retains draft/cursor;
subsequent Esc follows normal interruption behavior. A changed draft resets
menu dismissal/highlight/window as the original reducer does. Do not steal
history arrows when completion is dismissed or no matches are available.

No matches draws no list or fabricated first choice. No visible item room
means no highlighted acceptance, completion or navigation action; ordinary
prompt submission remains the typed submission. Room returning cannot fire
a deferred acceptance. Resizing preserves semantic highlight where valid,
clamps the viewport and does not change draft/cursor. Item updates re-match
before acceptance so no old index selects a new item. Keep prompt identity
and focus through open/close, resize and model/config overlays; completion
is a non-focus-taking overlay. Closing a focus-taking picker restores the
prompt's prior focus.

An original completion scrollbox consumes one row per wheel report only
when its own content overflows its allocated visible body; fitting bodies
bubble to the transcript. Rule, frame and prompt do not take list-body
wheel steps. Retain the original windowed items rather than inventing an
all-items wheel navigator. Key navigation reveals the highlight again after
body scrolling. Pure matching/window state and widget tests should cover
zero-room, resize, dismissal, updates and focus/draft invariants.

All active actions are Actions bindings with descriptions. Restore original
shortcut clauses for completion and picker arrows only when these actions
are implemented; do not list future commands or unsupported actions.


## U5a: latest laid-out overlay visibility

A follower with no room skips laying out its child. A completion list's
last positive row report can therefore survive a resize to zero room.
The lead approved the smallest reusable framework surface: a getter on
OverlayEntry, using the render result the overlay already computes.
There is no new geometry formula, notification API or overlay redesign.

```dart
final completionEntry = OverlayEntry(
  requestFocus: false,
  builder: (context) => CompositedTransformFollower(
    link: promptEdge,
    targetAnchor: Alignment.topLeft,
    followerAnchor: Alignment.bottomLeft,
    child: commandList,
  ),
);

bool canUseCompletion() => completionEntry.visible && visibleItemCount > 0;

// Described app Actions consult this when the key arrives.
// Tab: complete only if canUseCompletion().
// Enter: use the highlighted match only if canUseCompletion(); otherwise
// submit the typed draft through the ordinary submission path.
// Up/down: navigate completion only if canUseCompletion(); otherwise retain
// ordinary prompt/history behavior.
```

Add `bool get visible`. It reports whether the entry had a paintable
nonzero surface in the latest overlay layout. Default before any layout is
false. It is distinct from mounted, focus eligibility and requesting focus.
It does not measure visibility through overlapping layers or return a
visible fraction. A surface covered by another entry can still be visible
under this geometric definition.

For a follower use the existing raw RenderOverlay/onShown result: linked,
positive available width/height and a child taking positive width/height.
With showWhenUnlinked:false an unlinked follower is false; preserve the
existing showWhenUnlinked:true exception, which can paint an unlinked child
with nonzero geometry and therefore reports true. Ordinary entries use the
existing raw laid-out surface result. Do not use the focus normalization
that forces the base entry active: even that entry has false visible when
its actual raw surface is zero.

### Timing and lifecycle

The getter is read-only and has no callbacks, listener, rebuild promise or
side effects. Update its backing value from the existing raw layout result
before deferred focus effects and before any early return that skips focus
work because visibility did not change. The result must be current even
when the child did not receive layout. Never invoke app code while setting
this value. Existing focus and painting behavior stays unchanged.

False before insertion/first layout; false immediately on remove, dispose
or unmount of the entry/owning overlay. Removal cannot wait for the next
frame. A removed entry reinserted later starts false until its new layout;
never restore its old positive result from an earlier attachment. Disposal
retains the existing no-reinsert contract. Queued work from a former
attachment cannot make a removed/disposed entry visible again. A getter
read after disposal safely returns false. No callbacks means no new caller
reentrancy contract; existing focus restoration rules still apply.

This is latest-layout truth, not a prediction of an unlaid-out resize.
Do not read internal RenderFollower state or independently calculate the
port's page height. Existing layout scheduling determines when new geometry
becomes available. Do not add post-paint hooks or change resize dispatch in
this unit without a separately demonstrated need.

### Completion integration

At dispatch, conjunct entry.visible with the current laid-out command row
count. The entry false result invalidates a stale positive count on empty
follower room. A visible frame alone does not imply a visible completion
row; the count remains necessary when pickers consume the room. No invisible
highlight is completed, accepted or navigated. Do not queue acceptance for
when room returns. Returning room restores eligibility only after positive
layout; draft/cursor/selection are otherwise retained by the original rules.

Specific regression: at80x24 type /sta, verify one status match; resize to
80x5 so follower room is empty; Tab leaves /sta unchanged. Enter follows the
typed command path rather than accepting status by an unseen highlight.
Up/down do not move invisible completion. Resize back without a key and
verify no completion runs by itself. Test unlinked and zero-width cases too.

### Public fixture and acceptance

Add a standalone framework fixture, for example
`example/overlay_visibility.dart`, importing only the exported library.
Use an always-mounted zero-height target above a five-row editor/footer,
and a passive one-row completion layer. At120x40 and80x24 the layer is
shown; at80x5 it has no room. A described Tab action checks entry.visible
at dispatch, editing the seed draft only when true. A described reset key
restores the seed; quit is described, and KeyHelp lists the active actions.
The footer can show the last action result (completed/ignored); it must not
pretend the getter sends rebuild notifications. Input keeps focus and
ordinary typing at every size. No agent/domain data belongs in this fixture.

Expected fragments, mocks only:

```text
120x40 / 80x24, layer above footer:
  status  Complete the word
[editor holding sta]
Last Tab: completed       # after Tab, editor holds status

80x5, footer only:
[editor holding sta]
Last Tab: ignored         # after Tab, editor still holds sta
```

Tests must prove initial false, ordinary/base raw zero geometry, linked
positive/zero room, child zero size, unlink/relink including the explicit
showWhenUnlinked exception, immediate remove/dispose/unmount false,
reinsertion, focus preservation and public dispatch integration. Retain
failure/fix screen evidence at required sizes plus80x5. Unit handoff goes
through designer's public API/fixture gate, reviewer, then tester before
the port relies on the prerequisite's final pass. No new package is needed
for a terminal layout visibility property.


### U5 hidden-completion status hint

The original shows `not enough space` as a low-priority status hint while
a current completion has matches but no visible room. This is a hint, not
a real notice: reported mode and real notices retain their original higher
priority and width/drop order. Returning room removes it without accepting
anything or changing draft/cursor.

Use the existing always-laid-out base-page LayoutBuilder to schedule a
coalesced owner.afterLayout reconciliation outside the follower. At callback
time read the current entry.visible and current rows/query/matches; update
hidden status only if the semantic flag changes, with mounted/current-entry
guards. The follower may skip child layout at zero room; its raw visibility
still updates. Do not duplicate page-height arithmetic, poll with a timer,
read private render state or expand the getter's no-notification contract.
