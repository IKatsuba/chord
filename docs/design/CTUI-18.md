# CTUI-18: Picker activation and focus (B0)

This design adds only the framework API needed by the permission prompt.
The port's screens, wording and keys follow the original. The rest of
Picker follows CTUI-8.

## Call site

```dart
// The window's State owns and disposes this node.
final permissionFocus = FocusNode(debugLabel: 'permission');

Picker<String>(
  items: choices,
  enabled: !held,
  focusNode: permissionFocus,
  onSelected: choose,
  onCanceled: reject,
);

// After enabling the picker, the window's ctrl+x a action requests focus.
permissionFocus.requestFocus();
```

Add these named parameters to the existing constructor:

```dart
bool enabled = true,
FocusNode? focusNode,
```

`enabled` controls input and highlight. `focusNode` follows TextArea:
Picker creates and disposes its fallback node; the caller owns a supplied
node, which serves one mounted picker at a time. On replacement, detach
the old node and listeners and attach the new node through the existing
Focus lifecycle. Never dispose a caller's node.

## States

Enabled behavior and defaults remain unchanged: `autofocus` is true;
the focused picker or its filter editor draws the highlight; available
actions are listed by KeyHelp. An enabled but unfocused picker continues
to draw no highlight.

With `enabled: false`:

- Bind no picker actions: navigation, numbers, acceptance, cancellation,
  scrolling or filter editing. KeyHelp lists no enabled picker action.
  Enclosing window actions remain available.
- Neither picker nor filter editor can take or retain focus through
  autofocus, traversal or an explicit request. Disabling releases focus
  through the normal focus system; Picker does not choose a sibling.
- Draw no `❯` or selected-row styling. Keep the blank gutter, numbers,
  labels and current viewport, so text does not move. A searchable
  picker's query stays visible without an editable cursor.
- Keep selected value and query. Toggling does not choose, cancel, clear
  or submit, and no key is queued for reactivation.

Enabling an already mounted picker permits focus without stealing it.
The window enables the permission box before explicitly requesting its
node. `autofocus` retains its first-mount meaning and has no effect while
disabled.

## Appearance

These API mocks show the choice area at 120x40 and 80x24; omitted cells
are blank. They are not captures or runtime verification.

```text
120x40, enabled and focused       80x24, enabled and focused
❯ 1. Allow once                   ❯ 1. Allow once
  2. Always allow                   2. Always allow
  3. Deny                           3. Deny

120x40, disabled                  80x24, disabled
  1. Allow once                     1. Allow once
  2. Always allow                   2. Always allow
  3. Deny                           3. Deny
```

Empty items still show `No choices.`; an empty filtered result still shows
`No matches.`. Neither acquires a fabricated selection. Overflowing and
narrow content keeps CTUI-8's wrapping, row budget, edge markers and hidden
choice count. Disabling adds no frame, status text, colour or truncation
policy.

## Keys and verification

No new framework keys. Enabled navigation, numbers, Enter, Esc,
page/home/end scrolling and optional filter keys retain CTUI-8's Actions
descriptions and KeyHelp listing. The window owns `ctrl+x a` and its
description, not Picker.

B0 checks should cover unchanged defaults, disabled keys and KeyHelp,
disabled initial autofocus and explicit requests, disabling while focused
or editing a filter, caller-driven reactivation, preservation of query and
selection, and supplied/fallback node replacement and disposal. Visual
handover checks both sizes, including empty, overflowing and narrow states.

## Why one flag

The original's `src/ui/pickers/Pickers.tsx` ChoiceList separates `active`
(input) and `marked` (highlight). In `src/ui/dialogs/Permission.tsx`, a held
request turns both off. The agents-list `away` case is outside this slice.
One conventional `enabled` flag expresses the required state; no separate
highlight override is introduced. A supplied node lets the window return
focus without teaching a general widget about permissions or chord's keys.
No package is needed for this terminal widget API.

## B0a: keys left to the enclosing Actions

Add one named parameter, matching TextArea's public name and key syntax:

```dart
Set<String> unhandledKeys = const {},
```

```dart
Picker<String>(
  items: choices,
  enabled: !held,
  focusNode: permissionFocus,
  unhandledKeys: const {
    'pageup', 'pagedown', 'shift+pageup', 'shift+pagedown',
  },
  onSelected: choose,
  onCanceled: reject,
);
```

These keys are parsed by KeyCombo, as TextArea's are. Picker omits its own
bindings for matching keys in navigation and filter modes: they go to the
widgets above unchanged, without invoking a picker action. They are not
picker shortcuts in KeyHelp; the enclosing Actions supplies their action
and description. A key for which Picker already has no binding remains
unhandled. The empty default preserves existing key behavior. Changes to
the supplied set take effect when the widget updates.

The permission window uses this to scroll the request above the choices
with pageup/pagedown and their shift variants, instead of scrolling the
choice list. This does not introduce a port-specific key rule into Picker,
change focus or selection, or add a new visual state. Disabled behavior
still takes precedence: no picker bindings exist while disabled.

B0a checks should demonstrate a parent action receiving an omitted picker
key exactly once, no movement or selection by Picker for that key, the
unchanged default behavior, KeyCombo-equivalent spellings, updates to the
set, and accurate KeyHelp descriptions. Verify the same pass-through for
picker-owned bindings while the optional filter editor is active. The
screen checks remain those of B0; B0a adds no appearance or framework key.

B0a boundary clarified with developer: only Picker-owned Actions bindings
are omitted. The embedded TextInput retains its own editing and submission
keys, including printable input and Enter. This parameter does not add a
TextInput pass-through API; the permission window's page keys do not need
one.

## B0b: circular choices and caller-supplied numbering

The original has two navigation policies. ChoiceList uses `choiceKey` in
`src/ui/pickers/picker.ts`: up on the first choice selects the last, and
down on the last selects the first. AgentPicker uses PickerList and
`pickerKey`, whose documented policy clamps at the ends. Thus the start
page keeps the framework default; permission choices opt into wrapping.

Add these named parameters to Picker:

```dart
bool wrapNavigation = false,
bool showNumbers = true,
```

```dart
Picker<String>(
  items: [
    for (final choice in choices)
      PickerItem(value: choice.value, label: choice.label),
  ], // Original choicesFor already supplies '1. name', '2. name', ... .
  wrapNavigation: true,
  showNumbers: false,
  enabled: !held,
  focusNode: permissionFocus,
  unhandledKeys: const {
    'pageup', 'pagedown', 'shift+pageup', 'shift+pagedown',
  },
  itemBuilder: (_, item, _) => Text(item.label),
  onSelected: choose,
  onCanceled: reject,
);
```

`wrapNavigation` changes only up/down and k/j at the ends. True moves from
the first choice to the last and from the last to the first, revealing the
new choice. Existing movement through a choice taller than its viewport
still reads its lines before leaving that choice; wrapping occurs at the
outer boundary. Empty lists remain inert and a single choice remains
selected. False preserves clamping. It adds no key or KeyHelp description;
disabled and unhandled-key policies still apply first.

`showNumbers: false` removes only Picker's number column and its separator.
The selection marker keeps its two cells. The label or itemBuilder result
uses the newly available width; no extra number gutter is reserved on
continuation lines. Existing overflow edge columns, when needed, remain.
The caller supplies any visible numbering as part of its label/content.
Picker does not insert, rewrite, pad or strip a number in that content.
The existing itemBuilder signature and inherited selected-row style remain
unchanged. The default label remains one line with its existing overflow
policy; wrapping is requested by a Text builder, as above.

Numeric shortcuts still select result positions 1 through 9 independently
of visible numbering. Callers who put numbers in their labels keep them
consistent with result order. Permission choices are not searchable.
`showNumbers: true` preserves the existing padded number column and all
existing custom-builder behavior. This avoids a second prefix composition
API solely to put numbers into a caller's wrapped or rich text.

### Captures to expect

At both 120x40 and 80x24 a short choice looks unchanged:

```text
❯ 1. Allow once
  2. Deny
```

A label longer than the available width wraps with its continuation under
its number, rather than under the text after its number. This 24-cell
content example illustrates that same rule at either window size:

```text
❯ 1. Allow this action
  for this folder
  2. Deny
```

Every wrapped line inherits selected-row styling. Held/disabled choices
keep the same geometry without the marker or selected style. Empty,
filtered-empty, overflow and narrow states retain the B0/CTUI-8 policy;
these flags add no frame or hint. The port separately uses middle overflow
for CUT rows; no new framework truncation API is needed here.

Verify default clamping and numbering, wrap in both directions with arrows
and j/k, zero/one/multiple choices, scrolling to a wrapped selection,
multiline choice boundaries, and interactions with enabled/unhandledKeys.
Verify caller-numbered wrapping/height and numeric selection, custom
content, no phantom number gutter, and unchanged default builders. The
permission visual recheck must include a long option at 120x40 and 80x24.
