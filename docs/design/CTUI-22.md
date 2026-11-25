# CTUI-22: modes and session setting pickers

The original is the screen specification: `../chord/src/ui/pickers/Pickers.tsx`,
`picker.ts`, `state.ts`, `src/session/parameters.ts` and `docs/guide.md`.
This design covers the framework prerequisite first; original screen captures
and the port comparison follow in the screen handoff.

## U2b: observe the highlighted value

The model settings preview names the highlighted model before it is accepted.
Existing Picker owns that highlight but reports acceptance only. The lead
approved one optional framework callback, following Flutter's onChanged naming.

```dart
Picker<String>(
  items: modelItems,
  initialValue: currentModel,
  onChanged: (model) => setState(() => highlightedModel = model),
  onSelected: switchModel,
  onCanceled: close,
);
```

Add `void Function(T value)? onChanged` with default null. It observes a
non-null highlighted value changing; it does not accept the item. No callback
on initial mount, Enter on an unchanged highlight, numeric acceptance that does
not move the highlight, viewport-only scrolling, resize, remeasurement,
disable/enable, or equal-valued item replacement/reordering. Values keep the
existing unique, stable equality contract. `initialValue` remains an initial
seed, not a controlled selection or a request to reset an existing Picker.
There is no new controller, setter, or highlight decoration policy.

Arrow/j/k movement calls it once when the resulting highlighted value differs
by equality from the previous value. Filter changes and replacement/removal of
items may also change the semantic highlighted value: report the final
non-null value once after reconciliation. An empty result emits nothing; when
a later result acquires a highlight, report that value. Do not invent a value
for no result. A filter change retaining the same value emits nothing.

Never invoke a caller callback during build, layout, or paint. Input-driven
changes may notify synchronously after Picker's state is updated. Changes
arising while reconciling widget items must notify through the existing
BuildOwner.afterLayout hook, outside build/layout/paint, coalesced to the
latest still-current highlighted value. Waiting until after paint is not
required; no new frame hook is introduced. If A changes to B and back to A
before deferred delivery, emit nothing. Empty results clear the semantic
notification baseline, so a later non-null highlight can emit that value. A queued notification must check
that the State remains mounted and the value is still highlighted; disposal or
superseding reconciliation cancels stale delivery. Use the current callback,
not a stale closure. A callback may remove the Picker, update its items, change
focus or rebuild the parent; do not continue with stale item indexes after it.
Reentrant changes must not recursively deliver the same value. A callback
throw follows the framework's normal event/error path.

This callback changes no cells, keys, bounds or default behavior. Existing
Picker captures remain its visual specification at 120x40 and 80x24: empty,
focused, tall/overflowing and narrow states are unchanged. Tests must reach
navigation, no-op movement at an end, acceptance, filtered retention/change,
item reconciliation, equal-valued reorder, empty-to-nonempty, reentrancy and
queued disposal, without mirroring implementation internals.

## Placement and composition

Use the existing Overlay with a zero-height CompositedTransformTarget above
the prompt, and a follower with targetAnchor topLeft/followerAnchor bottomLeft.
The floating layer paints an opaque background across its width. It consumes
no transcript height, leaves the prompt and status rows fixed, and clips at
the rows above the anchor. A framed picker has priority over a simultaneous
completion list. Existing frame widgets and Picker supply choices; the port
owns original titles, explanatory text, settings line and hints. No new
framework overlay API is needed.

Model, effort and config pickers retain original numbered choices and clamped
navigation. Config values are a separately keyed Picker; Esc returns to the
settings list with its previous setting highlighted, then Esc closes. Model
left/right adjusts pending effort, clamped, without sending until acceptance;
Esc discards it. Every action uses described Actions bindings and appears in
the staged shortcuts catalog in the original wording.

## Original screen baseline for U3

Original head `577b58167672e12c999aeaf4eed2a1a988513dc2`, run through
`bun dev chord --fake --qa designer-ctui49`. Captures in
`docs/design/evidence/CTUI-22/` show model default at 80x24, pending effort
at both sizes, another highlighted model at 120x40, and both settings levels
at both sizes. These are original runtime captures, not a port claim.

At either width, the port will reproduce these same bottom-anchored rows:

```text
│ Select model
│ Switch fake's model for this session.
│
│ ❯ 1. Fake Large with a 1M context window ✔
│   2. Fake Small
│
│ Medium effort  ←/→ to adjust
│
│ Enter to switch · ←/→ for effort · Esc to close
```

Frame and inner padding follow the original captures across the window;
content has a one-cell inset inside the frame. The palette permission role
supplies border, title and highlighted choice, independent of session mode.
Use framework theme.focus for this existing permission role. A missing
permission colour (plain/NO_COLOR) uses the original dim frame fallback;
there is no default-mode dim picker border.
The list has a blank row before it, before settings line, and before hint.
The active value carries `✔`; a changed effort carries `•`. A different
highlighted model changes the preview wording but does not switch the
session. It retains a pending moved effort, requesting it after the model
switch only if the new model offers the same id. The original parameters
module owns full/short/drop order as width narrows; do not hardcode the fake.

Settings level one is `Settings`, `Change fake's settings for this session.`,
then `1. Effort  Medium`, with `Enter to choose · Esc to close`. Level two
is `Set Effort`, its original description, ordered values with `✔` on the
current one and `Enter to set · Esc to go back`. Preserve display labels,
ids and order exactly as offered by the agent; grouped option presentation
comes from original pure selectors. Effort-only picker uses `Effort` title
and original model-aware description and hint. Empty models/efforts/options
use the original explanatory sentence, omit list acceptance, and retain Esc.
Legacy models have no settings line; absent efforts have no left/right
bindings. A busy setter disables list input/highlight as existing Picker's
enabled contract requires, while the pending transcript record shows work.

Long lists use original row budget and hidden count through existing Picker;
resize preserves semantic choice and re-reveals it. Where room is too short,
cut body first, retaining title/hint and clipped frame; zero visible choices
have no acceptance bindings. Use original framedRows/cutRows geometry,
without generic Dialog's extra wording or automatic hidden-body sentence.

Shift+Tab cycles modes in agent order, wrapping, through the serialized
setter. Offered labels are not inferred from ids. Unknown current mode and
empty/singleton choices follow the original selector; no fabricated mode.
Status mode colour updates from reported state, and errors/pending rows
use original wording. The main prompt border remains dim across modes;
original Prompt.tsx changes it only for bash or a selected child agent,
features outside this unit. Do not apply plan/edits/auto roles to the prompt
or picker. Palette explicitly describes those three as status-line roles. New actions and restored picker/value-arrow
shortcut clauses must be active bindings.

No unresolved original design choice was found. The intentional staged
command catalog is recorded by the lead. Side-by-side port captures and
reached theme comparisons are added only after developer's committed U3
handoff; the original captures here are the target.


### U3 palette clarification

The earlier phrase "mode colour" was inaccurate and is corrected above.
Original `src/ui/pickers/Pickers.tsx` calls borderOf(useColours().permission)
and paints picker title/highlight with that same palette role. A missing
role alone takes DIM_BORDER. `src/ui/app/App.tsx` constructs paletteOf from
theme and colour capability, without a mode override. `src/ui/prompt/Prompt.tsx`
uses bash colour, then selected child-agent colour, then DIM_BORDER for the
main prompt. `src/ui/theme/theme.ts` labels plan/edits/auto as status-line
roles. Default dark picker colour is permission #b1b9f9, light #4a5ae0;
reuse theme roles, never literal colours in the picker. Retained original
ANSI captures show the default palette. This corrects the design against
the original; it is not a deliberate port difference.


### U3 wheel ownership clarification

Numbered model/effort/config PickerList bodies do not consume wheel reports,
even when their manually windowed choices overflow. Original PickerList and
Body are plain boxes, not scrollboxes, with no wheel handler. Let reports
bubble to the transcript; do not add a generic Picker Listener for this port
slice. The standing rule concerns original boxes that actually consume wheel,
such as permission proposal and shortcuts scrollboxes. Completion is another
separate scrollbox and remains specified in CTUI-23.

Live original evidence `original-picker-wheel-*` under CTUI-22 confirms:
120x40 model fitting body wheel up scrolls transcript while choices stay put;
80x24 effort body behaves likewise. At 80x14 the effort body genuinely
shows only Medium with an upper marker and `… +2 more`; down wheel directly
over its choice leaves the complete screen byte-identical. The small size
is an additional overflow probe, not a substitute for required sizes.


### U3 initialized-session lifecycle mapping

Original app connection remains ready after session.exited: conversation
emits only transcript disconnected, and app reducer keeps connection state.
Accordingly, the port's Gone phase after an initialized session maps to the
original ready state for existing picker/command availability. Preserve
post-exit pickers and dispatch through the established dead-agent refusal
path; hide before initialization, startup failure and closing only. The
lead settled this as original fidelity, retracting the earlier ready-only
predicate interpretation that treated port Gone as unavailable. It is not
an intentional original behavior correction. Long title/hint TEXT wraps as
the original; reserve their actual wrapped height before cutting body rows.
CUT descriptions and whole numbered labels still truncate in the middle.
