# CTUI-27: steering, reverse search and verbose output

The original is the specification: `../chord/docs/FEATURES.md`,
`docs/guide.md` (personal steering), `src/ui/AGENTS.md`,
`src/ui/prompt/queue.ts`, `search.ts`, `Prompt.tsx`, `src/ui/app/keys.ts`,
`state.ts`, shortcuts and `src/session/conversation.ts`.
No new framework widget API or subsystem is proposed. Reuse existing
Actions, prompt/overlay, TextLayout, transcript and session boundaries.

## Units and staged scope

1. Pure reverse-search state, editing and match-piece projection.
2. Advertised `_session/steering` transport/session operation and personal
   Conversation queue lifecycle, then supported `into` record/replay.
3. Screen/key integration for queue steering, search and verbose output,
   with existing shortcut catalog clauses restored in original order.

Keep M3+ images, retained-draft settings, children, agent message delivery,
forms and teams staged out. Do not add those systems to manufacture a case.
Existing queued `@` links and held shell context follow their exact original
row, unchanged. Preserve agent numbers as num? throughout. Any required new
subsystem goes to the lead before implementation.

## Tab steers the oldest personal row

Enter while working keeps existing queue behavior. Tab takes the oldest
eligible personal plain row, skipping messages, held/sent/taken rows, and
leaves the current draft/cursor untouched. No running turn or eligible row
means no action. Bash, permissions and open completion keep their own Tab.
Bind through Actions with a description; help says
`tab to send the oldest queued now`.

Only advertised `_session/steering` may be sent. Use the same queued row,
identity, content, links and held context, with serialized steering and
current-session ownership. Tab marks the row taken at dispatch/call entry,
before async mention resolution or waiting behind another serialized steer.
Esc leaves that row taken even before the request reaches the wire and before
its pending label appears. Only rows explicitly held for a question or open
calls are withdrawable: Esc restores those personal rows through existing
unsent draft/context restoration, and they must not be sent later.
Other-origin rows remain outside personal withdrawal. There is no general
“before wire” restoration window and no new withdrawal token.

Original `../chord/src/session/conversation.ts` marks `taken` in
`steerQueued` before calling `#steer`; `#heldSteers` separately identifies
explicit answer/call holds. `../chord/tests/session/conversation_steer_test.ts`
cases at lines 1681 and 2492 cover those holds, not every dispatch awaiting
transport. `../chord/src/session/session.ts`
resolves mentions inside `steer`, after the taken boundary.

For a personal row without a prior explicit hold, start the original 500 ms
pending-label timer when `session.steer(...)` is called, after any serialized
predecessor and explicit holds, including time spent resolving mentions in
that call. Do not move the timer to actual wire admission. If unanswered,
its queue prefix becomes `into the running turn: `. A previously displayed
explicit hold changes to that outgoing label immediately when `session.steer`
is called. Label timing never creates a draft-restoration window.
A question/call hold uses original `after your answer: ` /
`after the running calls: ` priority where the already-supported lifecycle
can reach it. Queue projection remains oldest first, first source line plus
` …` for multiline, and original hidden count.

Actual wire admission callbacks concern admission and resolved-link facts
only; they do not move the taken boundary or emit a sent-prompt echo.
Accepted injection alone removes the queue row and emits/records its personal
`›` transcript row with original `into` target. Restore refusal to its
original queue place, before later personal rows and behind earlier rows.
For three seconds show `Not taken into the running turn · it stays queued`.
Unsupported steering leaves the queue intact and shows
`This agent does not take messages into a running turn · it stays queued`
for three seconds. A late answer after turn end shows no stale note and
must deliver exactly once: into the old turn if accepted, or in queue order
as a subsequent turn. Session swap/close rejects stale outcomes.

If the adapter returns startedNewTurn, cancel its self-started turn, draw
`Interrupted · the agent started this on its own; your message goes as the next turn`,
wait for quiet, and requeue/advance once. Preserve any already-visible work.
Do not replace this with an extra user turn or silently drop the prompt.
Supported personal `into` replay must retain original grouping/wording;
it must not trigger the saved-history omission notice solely for steering.

## Ctrl+R reverse history search

Search is plain case-sensitive substring, newest first. An empty query
matches nothing and shows the saved draft. Repeated identical prompts appear
only at their last occurrence. Query changes restart from newest; Ctrl+R
finds the next older distinct prompt. Exhaustion retains the last match and
uses `no matching prompt:`; normal label is `search prompts:`.

Search owns typing/paste; paste searches its first line, removing control
characters. Main explicitly retains that paste behavior as a correction of
the original UI wiring, which ignores bracketed search paste despite the
pure editedQuery helper defining first-line/control filtering (decision
`4b027fd`). Do not change generic editor paste behavior.
Backspace/Delete remove one Unicode code point. Modified
non-edit keys preserve the query. Match highlighting is literal substring,
all nonoverlapping occurrences, inverse style; do not add fuzzy matching,
regex semantics, normalization or a new text-editing subsystem.

Draw the one-row search overlay above the prompt with its dim top rule and
two-cell horizontal inset. Show query and inverse blank cursor cell. Long
query rows use existing rich middle CUT: ASCII `...`, preserving the styled
label/prefix and query suffix including its inverse final blank, as the
original CUT inventory in CTUI-16 specifies. Do not substitute end ellipsis.
The prompt shows the matched full text with inverse hits and cursor at end;
it is not editable while search owns input. The underlying draft and cursor
survive. Enter or Tab takes the match into the draft without sending;
Esc or Ctrl+C cancels and restores the old draft/cursor. With no match,
acceptance returns to the original draft. At any positive terminal size,
query-owned Enter/Tab still recalls and closes search even if both query
text and the readonly matched editor are clipped. This is search acceptance,
not a hidden editor edit or send. A 0×0 terminal is inert; no input is deferred
for replay when room returns. Recalled slash text must not
accidentally accept completion on the same key. Preserve existing bash recall
and history boundaries. Search may open during a turn; modal key ownership
still wins. On transcript folding, an active asksPerson request closes
search when it is not held back, restoring the saved draft/cursor. Actually
attending a held request also closes search; answering does not reopen it.
Preserve the original asksPerson/heldBack distinction rather than adding a
blanket overlay visibility or geometry policy (original state.ts 1105–1116
and 620–628, plus retained overlapask reference).
Scroll and Ctrl+O keep original priority.

## Ctrl+O verbose output

Toggle existing expanded transcript rendering: full thought and tool output
for supported entries, with original collapsed summaries/hints otherwise.
Keep the same transcript, focus, draft, selection rules and scroll policy;
this is not a new screen or a protocol setting. Reflow invalidates geometry
through existing item/source revisions and clears selection as the original
does. No M3 content is invented. Help says `ctrl + o for verbose output`;
search help restores `ctrl + r to search prompts`, `tab enter to take a match`
and `esc to cancel a search`, using the staged catalog's actual geometry.

## Original beside the planned port

Original head `577b58167672e12c999aeaf4eed2a1a988513dc2`, fake QA only.
Each linked text capture has matching `.ansi`. Planned cells reproduce
these observations; no implementation comparison or pass is claimed yet.

| State | Original | Planned port |
| --- | --- | --- |
| Search newest, 120x40 | [capture](evidence/CTUI-27/original-search-newest-120x40.txt) | Same overlay/query and newest draft match |
| Search newest, 80x24 | [capture](evidence/CTUI-27/original-search-newest-80x24.txt) | Same one-row overlay, inverse match and fixed prompt |
| Older/exhausted, 80x24 | [older](evidence/CTUI-27/original-search-older-80x24.txt), [exhausted](evidence/CTUI-27/original-search-exhausted-80x24.txt) | Keep match; only failed label changes at exhaustion |
| Thought, 120x40 | [collapsed](evidence/CTUI-27/original-thought-collapsed-120x40.txt), [expanded](evidence/CTUI-27/original-thought-expanded-120x40.txt) | Same collapsed/expanded thought and answer |
| Thought, 80x24 | [collapsed](evidence/CTUI-27/original-thought-collapsed-80x24.txt), [expanded](evidence/CTUI-27/original-thought-expanded-80x24.txt) | Same content with original scroll/reflow |

Source-derived steering states still need paired captures after developer's
handoff, including pending/refusal/unsupported and draft preservation. One
exploratory texttillsteered sequence completed before its Tab; it is not
steering evidence. No in-flight, delayed-label or exactly-once runtime proof
is inferred from the retained thought captures containing that earlier text.

Reference sequence: `bun dev chord --fake --qa designer-ctui27`, with fake
steering set to claude; send `alpha first request`, `alpha second request`,
then draft `draft stays here`. Ctrl+R, literal `alpha`, Ctrl+R twice and Esc.
Esc restored the draft live. Clear draft, send `tools`, later `thought`, and
capture Ctrl+O both ways at both sizes. Literal text and Enter use separate
send-keys calls. Only displayed synthetic QA cwd becomes `fixture-project`;
this shortening is not an exact width oracle. Original source was not edited.

## Handoff checks

Pure tests cover empty/duplicate/multiline/Unicode/literal search and failed
match retention. Session tests separately cover explicit question/call-held Esc
withdrawal/restoration without later send, and dispatch-taken Esc preserving
rows while mention resolution is pending, while serialization waits, and
before/after the pending label. Pin the original timer phase at the
`session.steer` call rather than actual wire admission, including immediate
label transition from a displayed hold. UI queue tests pin the same taken
boundary; accepted transcript/record tests must not admit an early echo.
Cover ordering on refusal,
unsupported, 500 ms/3 s timers, end-before-answer, accepted/refused late
outcomes, startedNewTurn, serialized multiple steers, close/swap and original
links/held context. Record/replay tests cover personal into grouping.

Screen checks at 120x40/80x24 compare original in the same state. Include
long/narrow query and match, zero overlay room, matching multiline text,
search during work, positive-size clipped-query/editor acceptance without
sending, inert 0×0 input, modal/selection/chord priorities, full tool output,
light/plain inverse contrast and real staged shortcuts overflow. Existing
wheel-taking boxes retain their original ownership. Keep failure/fix
captures and clean all owned tmux/fake processes and synthetic state.


## Framework prerequisite: styles for TextArea's full text

Main approved this narrow prerequisite before the port consumes it (decision
122dc85). It adds decoration, not another editor, read-only mode, row model,
controller API, selection source or scheduler. CTUI-7/17/48 geometry and input
contracts remain. Framework implementation comes first, with its own
API/fixture/review/test gate. After that implementation and the lead's
CTUI-52 release, independent pure search/protocol units may pipeline review.
U27c and other port consumers use the hook only after its framework gate
passes. This design addendum itself does not release implementation.

Add one nullable named TextArea parameter, default null:

```dart
final TextSpan Function(BuildContext context, String text)? textSpanBuilder;

TextArea(
  controller: shownPrompt,
  maxHeight: promptRows,
  onLayoutChanged: rememberActualViewport,
  textSpanBuilder: (context, text) => TextSpan(
    '',
    children: [
      for (final piece in foundPieces(text, query))
        TextSpan(piece.text, style: piece.found ? Style.inverse : null),
    ],
  ),
);
```

foundPieces is the app's plain literal-match projection, not framework search.
The callback receives the entire exact controller.text for that build, already
normalized by TextAreaController. It returns that same text with styles.
TextSpan.toPlainText() MUST equal the supplied String exactly: no addition,
omission, reordering, Unicode normalization, replacement characters, injected
cursor cells or ANSI/control cleaning. Validate at runtime, including AOT,
with ArgumentError through ordinary build-error handling; never a debug-only
assert or silent acceptance of changed text.

Invoke and validate in TextArea's own outer content build BEFORE returning
its Focus/Actions subtree. An invalid callback/result must not leave the old
editor's key/paste/action handlers active under an inner error widget.
Discard old decoration; ordinary error presentation replaces that subtree.
A later valid rebuild recovers through the normal framework boundary without
replaying input or modifying text/undo/cursor to repair the error. Callback
exceptions use the same normal boundary. The callback is pure: no edits,
focus changes, controller.layout calls, IO or notifications.

Null keeps the existing path. A visible placeholder keeps its existing
placeholder/placeholderStyle path and does not invoke/decorate the callback.
Empty text without a placeholder may return an empty TextSpan; preserve the
existing empty cursor row. Non-placeholder builds validate even with zero
visible width/height, but paint no fabricated row or action surface.

### Styling and raw row mapping

Use current widget.style/theme and ordinary inherited TextSpan child styles,
with existing flatten/merge precedence. Full span runs use UTF16 offsets;
TextAreaLayout row.start/end are RAW controller grapheme offsets. Reuse the
existing controller/characters segmentation and grapheme-start style rule:
a grapheme takes the style at its first UTF16 unit. A span boundary inside
a combining/ZWJ/emoji cluster does not split or remeasure that cluster;
a later run starts affecting the next grapheme. Do not invent segmentation.

Project styles onto existing actual-layout rows; preserve each row.text
EXACTLY. Hard LF occupies its full-text offset but contributes no row glyph.
Tabs remain raw tabs and use the existing row paint expansion/style behavior.
Empty end/cursor rows remain present. A match crossing a soft wrap is found
once in the whole text and styled on both rows; do not search each row anew.

Do not strip ANSI or C0 controls, expand tabs or shape the whole decorated
text before the controller wraps it. Existing per-row Text paint continues
its current ANSI/control sanitation, including escapes crossing style runs
and sequences split by an existing wrap. Decoration cannot add ANSI execution
or change the historical row-level sanitation. Reuse existing rich text
style/grapheme helpers as appropriate; no parallel text shaper/parser.

### Invocation, invalidation and freshness

A normal TextArea content build uses the current callback/captures/inherited
styles; it may run during more than one normal framework build phase.
Do not cache solely by callback identity or unchanged controller text:
query/theme/captured style can change on a parent/inherited rebuild.
External changes still need normal invalidation; no new version/listener API.
Freeze only the current resolved decoration snapshot, not a history of texts,
queries or caller-owned mutable span trees. No onChanged/onLayoutChanged,
selection/undo change or extra layout notification follows from styles alone.

The outer build and inner LayoutBuilder can see different live state. Tag
decoration with its controller identity, exact text, widget/builder generation
and effective widget.style/theme/inherited base style. Inside the existing
constrained content layout, always lay out the current controller as before. If identity/text/
configuration/base style is no longer current, discard stale decoration and
draw CURRENT raw rows through the ordinary plain path/current base style.
Never slice old spans against new rows or reuse an old resolved base style.

Existing controller/widget/inherited invalidation supplies the normal next
build: it may use a remaining standard pass, or the next frame when the
existing budget is exhausted. There is no third pass, retry loop, user
hook call from the inner layout callback, forced synchronous convergence
or controller mutation. Its outer invocation uses normal widget-build
semantics, not a new global scheduler/phase guarantee.
Adversarial sibling/afterLayout text, controller and theme replacement tests
must separate current plain text/geometry from next-frame fresh decoration.
The null/default path and its notification timing remain unchanged.

### Geometry, selection and later port ownership

Keep the actual TextArea LayoutBuilder/controller.layout as the only viewport
authority. Same width/height constraints, rows, raw offsets, rowOffset, cursor
row/column, exact-width empty cursor rows and maxHeight apply. Keep the same
SelectionEditor/controller semantic identity, eligible text, selection ranges,
hit/clip geometry, editing bindings, paste, undo/redo and terminal cursor.
A no-op decorator must be indistinguishable from null apart from callback
execution; no hidden duplicate editor or guessed gutter layout.

Later search uses a separate shown-presentation controller and its real
TextArea layout. A match uses the whole matched text/cursor at its end;
without a match use the saved draft text/cursor snapshot, as original App.tsx.
Follow the original search presentation identity (`search:<match index>`),
including its fresh viewport when that identity changes; a query-only style
change retaining that identity does not reset the controller/viewport.
Preserve the saved draft/controller/cursor/undo without laying it out
or mutating it during search. Existing focus exclusion/ineligible match focus
and a query-owning focus/capture keep typing/paste/search keys away from that
shown editor; no new readOnly flag is justified for this scope. The matched
editor has no hardware cursor; the search line paints its inverse blank query
cursor. The original matched overlay uses TEXT/selectable:false without
useSelectable; Prompt.tsx and theme/text.ts are source proof, not a runtime
selection claim.
Lead settled the visible matched projection AND query line as nonselectable
furniture. Use existing SelectionContainer.disabled/excluded-source geometry;
the hidden saved draft exposes no hit, copy or source while search is shown.
Do not reproduce incidental opacity-zero editor hit behavior. This is port
eligibility only: the framework hook leaves normal SelectionEditor semantics
unchanged and adds no selection API or readOnly mode.

The gutter reads only the shown area's actual onLayoutChanged snapshot, with
the existing clipped decoration/two-pass contract. No controller.layout guess
from the port or afterLayout geometry loop. Accept writes recall into the saved
draft once; cancel restores the saved controller/focus. At positive terminal
size, query-owned Enter/Tab recalls/closes even with both search surfaces
clipped; there is no editor/query visibility guard on that action. The hidden
readonly editor never owns editing, paste, send or hardware cursor. At 0×0
the terminal is inert, and no clipped input is deferred. Existing global copy/chord,
modal, completion and scroll precedence remains the port's responsibility.

### Public fixture and acceptance

Provide a framework-owned public fixture using the new API, independent of
chord search/session code. Reuse existing viewport/gutter reporting. Actions
and KeyHelp advertise Ctrl+G toggle decoration, Ctrl+T theme, Ctrl+Q quit;
the area leaves those keys to outer Actions. Editable behavior stays normal.
Use fixed text with Unicode, hard LF and a literal hit crossing a soft wrap.
At 120x40 and 80x24 compare decorated/plain geometry and cursor with retained
captures, plus narrow/zero-room and light/plain contrast. These are planned
mocks, not runtime evidence (brackets mean inverse, not literal cells):

```text
120x40, 2-cell gutter and wide content
› Context <60 x characters>[needle crosses]
  終わり 😀 é

80x24, same text with a 78-cell editor
› Context <60 x characters>[needle cro]
  [sses]
  終わり 😀 é
```

No new port key or screen state comes from the hook. Framework tests must
cover null/no-op equivalence, inherited/root/child styles, UTF16 boundaries
inside combining/ZWJ/CJK clusters, hard LF/tabs/control/ANSI across runs and
wraps, global repeated/cross-wrap matches, exact-width cursor rows, zero and
constrained room, callback replacement/removal, placeholder transitions and
style-only notification silence. Compare cursor/SelectionEditor/undo and
source geometry before/after decoration, including normal eligible content
versus existing disabled wrappers; styling cannot re-enable excluded text.
Invalid text and callback errors need initial and valid-to-invalid-to-valid input-ownership regressions plus
AOT-active rejection. Freshness tests need adversarial sibling/afterLayout
text/controller/theme replacement with current plain fallback and only
normal next-frame convergence. Reserve heavy/AOT slots through the lead.
