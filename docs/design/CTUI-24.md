# CTUI-24: file and agent mentions

This is the original-defined integration contract, following CTUI-51 and
CTUI-25 on the shared task branch. No implementation acceptance is claimed.

## Authority and staged boundary

Original: `577b58167672e12c999aeaf4eed2a1a988513dc2`, read-only `../chord`:
`src/ui/prompt/{mentions,state,Prompt}.ts` (Prompt is `.tsx`),
`src/ui/app/{keys,state,terminal}.ts`, `src/files.ts`, current tests and
`docs/guide.md`. CHD-519's recipient/quoting policy applies, but its old
below-prompt sketches are superseded by the current floating completion
surface above the prompt. Keep the port's settled slash-completion layer,
current room checks, prompt gutter and live status layout.

Main approved an injected immutable reachable-recipient snapshot, empty by
default, with populated fixtures/tests. M4 supplies the live roster later;
see [the decisions log](../decisions.md). Do not invent recipients from
installed agents, the catalog, visible transcript authors or saved sessions.
No runtime/team/MCP registry is implemented by this slice. Production's empty
snapshot says `No agents to mention`, not that live routing was inspected.

## Integration shape

The existing anchored overlay/list primitives are used, with separately
gated framework prerequisites below: AsyncFzf, optional follower opacity and
current-context geometry synchronization.
Optional follower opacity replaces the earlier assumption that the existing
follower could host a no-paint/no-hit pending surface without an API change. Matching/scanning,
trigger/insertion and state transitions stay plain Dart, reachable by tests.
Use maintained packages for file walking/ignore rules; if none directly fit,
stop and take options to the lead before writing a workaround. Existing
framework fuzzy matching may be reused under its approved contract.

The window accepts a caller-supplied recipient list, empty by default, frozen
at the boundary; each item carries its literal name and optional existing
agent palette colour. It represents the recipients already reachable from
this picked session. The caller replaces the snapshot on session/roster
changes; the widget never computes reachability. Replacing it invalidates
stale results and pending acceptance. Deduplicate exact equal names, retaining
the first source occurrence and stable order. Do not alphabetize agent names.
Disposed windows ignore late results. No timers or walker survives ownership.

The implementation may use the repository's existing typed recipient value
if it already expresses this data; otherwise introduce one small port value.
Constructor naming is a local developer choice; do not broaden the seam into
an asynchronous runtime provider. All list/colour inputs are immutable.

## Framework prerequisite: AsyncFzf

Lead approved a bounded extension of the existing approved Fzf scorer before
port async matching consumes it. This is its own public-API review/test gate;
no alternate matcher, isolate worker, dependency or package workaround.
The shape was settled directly with developer:

```dart
final finder = AsyncFzf<String>(
  files,
  casing: FzfCasing.caseInsensitive,
  limit: 100,
  tiebreakers: [byLengthAsc],
);
final List<FzfResult<String>>? matches = await finder.find(query);
finder.dispose();
```

Constructor takes the same items, optional selector, casing, normalize, limit
and tiebreakers as Fzf, with exactly its defaults and validation. Use the same
FzfResult and FzfTiebreaker types. AsyncFzf defensively snapshots the candidate
list/order and tiebreaker list at construction; exposed lists are read-only.
This is shallow generic ownership, not cloning arbitrary T or callbacks:
callers keep item values stable and selector/tiebreakers deterministic and pure.
Replacing candidates/options means a new finder and disposing the old one.
The synchronous Fzf public behavior is not changed by this prerequisite.

`Future<List<FzfResult<T>>?> find(String query)` returns the same complete
results as synchronous Fzf for that snapshot/options: exact original index,
item, score, start/end, positions, NFC/normalization/casing, stable score/tie
ordering and limit. Empty query retains Fzf's first-items behavior. No partial
ranked list is published. The completed result list/positions are immutable;
items retain the shallow ownership rule above.

Each find starts a new generation, even for an equal query. A superseded
pending find completes null, never an empty-results list or cancellation
exception. Idempotent `void dispose()` invalidates pending work; future finds
also return null. A completed future cannot be revoked: the port still checks
current query/candidate/session/visibility ownership before accepting it.
No stale or disposed completion can schedule a new match or update a caller.

Preprocessing/scanning and score/tie ordering yield cooperatively in bounded
chunks to the event queue, not only microtasks. Reuse the existing scorer and
result semantics; bounded stable merge work must not end the scan with one
large blocking tie-group/native sort. Check generation/disposal after every
yield and before publication, including during final merge. No public batch,
scheduler or clock knob is added. Constructor snapshot copying is linear;
individual candidate/comparer cost is not a hard wallclock latency guarantee.
There is no background worker, polling timer or ownership of a widget.

Tests compare sync/async every result field across current oracle cases,
Unicode/case/normalization, ties, empty and limited queries, duplicate items
and custom selectors/tiebreakers. A large scan and large equal-score group must
let an event-queue timer/key run before completion. Cover supersession during
scan and final ordering, repeated equal queries, dispose midwork/idempotence/
postdispose, caller list mutation and replacement ownership. A cancelled null
must not be mistaken for no matches by the port. Existing Fzf regressions and
static checks remain clean; reviewer/tester gate this before port consumption.

## Framework prerequisite: optional follower opacity

Implementation discovery showed that the existing follower always fills its
child rectangle, declares that rectangle covered and self-hits it. A transparent
SizedBox child alone cannot satisfy the pending surface contract. Main approved
this bounded prerequisite before port consumption, replacing the prior no-API
assumption. No larger room-query or visibility API is added.

```dart
CompositedTransformFollower(
  link: promptEdge,
  targetAnchor: Alignment.topLeft,
  followerAnchor: Alignment.bottomLeft,
  opaque: false,
  child: LayoutBuilder(
    builder: (context, constraints) => SizedBox(
      width: constraints.maxWidth,
      height: 1,
    ),
  ),
)
```

Add `bool opaque = true` to CompositedTransformFollower and RenderFollower,
forwarded on creation/update and exposed with public documentation. True keeps
all current behavior: follower fill, self coverage and self-hit. False skips
only the follower's rectangle fill, own beforeChildren paint coverage and
hitTestSelf. Its own coverage is known-empty, not unknown/null. Children retain
normal painting, coverage and hit traversal under the existing room clip.
False does not make an interactive/painted child transparent or ignore input.
Unknown child coverage remains unresolved under CTUI-48's existing rules;
exact-runtime coverage declarations and stale-query guards are not weakened.

Opacity does not affect link/anchor/offset calculations, constraints, child
size/layout, showing, showWhenUnlinked, or OverlayEntry.visible. A linked,
positive-sized empty child can therefore report raw visibility while painting
and self-hitting nothing. Zero room/zero width/unlinked visibility remains as
before, including the existing showWhenUnlinked exception. Focus policy is
independent: the pending entry must explicitly use requestFocus:false.

The pending caller uses false only for the empty geometry-only surface;
normal completion/searching/agent-empty drawing restores existing opaque
behavior. It still checks potential normal row room and current ownership.
This property supplies no fake rows, room prediction, extra layout passes,
input replay, paint probes or new capture/focus policy.

Own framework designer/reviewer/tester gate precedes U24b2 port use. Tests
prove unchanged default output/coverage/hits; false plus an empty positive
child preserves underlying cells, pointer/wheel routing, selection and code
query exposure; painted/interactive children retain their actual cells and
hits. Toggle opacity at unchanged geometry and synchronize current queries,
including an occluded underlying code button's stale-click prevention.
Cover linked/unlinked/zero-room/resize and unknown-child behavior. Existing
overlay, input and selection regressions remain required.

Extend the existing overlay_visibility example with --passive, retaining its
current keys and descriptions. A positive-width height-one empty follower over
numbered transcript rows must visibly preserve them, keep prompt focus, report
raw geometry eligibility for Tab and stop eligibility on zero-room/unlink.
Compare default and passive live at120x40/80x24 plus the zero-room edge; inspect
underlying pointer/wheel/selection behavior and clean owned sessions. This is
a generic fixture, not a new port action or implementation acceptance.

## Framework prerequisite: current context geometry

Review reproduced an async pending result publishing after resize/dirty layout
but before the next frame, when cached visibility/room still looked positive.
The committed API has no geometry-only public sync: entry.visible, LayerLink
and findRenderObject are cached; owner synchronization is internal; drawFrame
paints and belongs to the host. SelectionController.snapshot is not a substitute:
selection exposure, ranges and unknown paint coverage are different semantics.
Main approved this bounded public seam, before the port repair consumes it.

```dart
bool canPublishCurrentMatch() {
  if (!context.ensureCurrentInputGeometry()) return false;
  // Synchronization can run ordinary callbacks: read live state afterward.
  return queryStillCurrent && completionEntry.visible && availableRows > 0;
}
```

Add `bool ensureCurrentInputGeometry()` to BuildContext, implemented by Element.
No arguments, callback, pass knob, public epoch or new owner hook. Delegate once
to the existing internal owner synchronizer with its default budget. The wrapper
must not start/reset an independent operation or add a layout pass, paint,
terminal effect, queued retry or input replay. Nested queries share the existing
operation's remaining two-pass budget; ordinary settlement callbacks/observers
and error recovery remain unchanged. Do not promote the internal owner method
or suppress internal-member diagnostics in the port.

An unmounted/detached captured context returns false before accessing its owner.
Capture the owner before delegation; after callbacks return true only when the
underlying geometry settled, the context is still mounted and its owner is
identical. An absent synchronization hook, unknown host size or disposed host
returns false through the existing hook. A known zero-axis size can settle
and return true while an entry stays invisible; action eligibility still needs
positive room and entry.visible. No positive-size host policy is added.
Existing layout/paint/active-settlement StateError guards and ordinary
exception/recovery behavior remain; do not catch misuse and label it success.
Reentrant input/disposal/replacement must retain existing supersession guards
and cannot cancel a newer operation or make a detached receiver current.

True means only that this attached host's build/layout geometry is current at
return. It does not mean a particular overlay has room, a selection is exposed,
a match is current, or an action remains eligible after later mutations/awaits.
It does not query/resolve a selection snapshot or range. Unknown selection paint
coverage is not a direct failure criterion; normal observer dirtiness still
shares the same budget. False drops that acceptance; the caller must not loop,
retry automatically or use stale cached visibility as fallback.

The port injects a window geometry validator into the plain match controller,
invoked BEFORE publishing the new match. After synchronization, recheck live
context/entry attachment, controller ownership, query/candidates/generation and
normal positive row room. Publishing an empty result legitimately removes its
own list: preserve pending Enter-to-no-match submission using that validated
prepublication eligibility, with data ownership rechecks around callbacks.
Do not validate only after removing the surface and accidentally lose that Enter.
No selection dummy/probe, internal call or extra layout budget is permitted.

Own nonvisual framework API reviewer/tester gate precedes port repair use;
lead explicitly requires no new demo or capture matrix. Tests cover stable and
dirty geometry, recorded resize before frame, first usable size, unmounted/
disposed/detached or owner-changed context, zero room, exhaustion, nested shared
budget and reentrant supersession, guarded layout/paint calls and no paint.
Include stable layout with unresolved selection coverage to prove separation.
Then port regressions cover pending valid/no-match Enter, resize/unlink before
result publication, exhaustion, callback reentrancy and no later replay.
The signed port repair returns through designer for its affected screen path.

## Trigger and insertion

Recognize single `@` only at line start or after whitespace and immediately
before a non-whitespace query ending at the cursor; midword/email text does
not open completion. `@@` has priority and completes agents. An opening
quote after `@@` permits spaces until the closing quote; an `@` inside that
quoted name cannot reopen the file finder. A completed quoted token does not
reopen until a later separating whitespace/new mention. Cursor positions and
suffix replacement follow the original, including mention edits midline.

Up/Down move and clamp the current highlight; Tab or Enter inserts the chosen
literal name/path with its trigger and one separating space, keeping other
text and the cursor just after that space. Names/paths with whitespace are
quoted, e.g. `@"space name.txt" ` or `@@"bugfix 2" `. Preserve an existing
separating space and suffix. Agent insertion consumes its quoted suffix through
the closer when appropriate; no escaping/renaming/chip policy is invented.
Esc dismisses the current finder without editing the draft or interrupting.
Moving/editing to another trigger permits that new completion normally.
Completion is suppressed in bash mode, search, closing and modal states that
own input, following current original precedence. Preserve selection capture,
shared matcher priority and pending-chord handling.

## File discovery, matching and pending acceptance

On opening single-@, walk the current session directory again; retain the
previous list while walking. Include dotfiles, respect nested gitignore rules,
exclude .git, directories and ignored output, and work outside a repository.
Return relative files ordered by depth, then lowercase codepoint order,
then original codepoint order. Main extended CTUI-23's existing tested
locale-comparison fallback to files and every original localeCompare use;
no new package trial is required. See the existing trial/choice and global
extension in [the decisions log](../decisions.md). This is an explicit
ordering difference from the original, not locale parity.
An unsuccessful walk adds no error UI or attachment. Never write the original.

An empty query immediately offers the first 100 paths in discovery order.
Nonempty query uses original case-insensitive fzf scoring, shorter-path tie
break and stable source order otherwise, capped at 100. Matching is asynchronous
and yields so typing continues. A newer query/candidate/session generation
invalidates old results. Keep the previous list/highlight while pending; after
150 ms show dim `searching…` in its final available row, preserving the
highlight above it rather than adding another row. When only one body row
fits and a retained choice exists, preserve that highlighted choice and omit
the searching marker; this is the original FileList's clipped tiny-room
behavior. With no retained choice, one row may show the marker alone. With
at least two rows, retain the highlighted choice and use the last row for the
marker; with zero row room draw neither and invalidate pending acceptance.
Test zero/one/two rows with and without retained matches. Agent snapshots use
the same scoring, without file-loading UI or a searching marker.

Enter/Tab on a pending current match waits for its first result unless the
person moved the retained highlight, in which case accept that row immediately.
Waiting does not block further typing. Drop the wait when its mention, query,
position, kind, session, candidates or visibility is no longer current, or
Esc dismisses. A returned row is accepted only from the current snapshot.
If no result, waiting Enter submits the then-current draft as typed; Tab does
nothing. No matching files closes the file list. Agents retain a dim
nonselectable `No agents to mention` or `No matching agents` row as applicable;
Enter submits normally and Tab does nothing in either empty state.

No matching rows is distinct from no available row room. Original
`src/ui/app/keys.ts` explicitly waits for a current pending match even after
an empty prior result when fileFinder draws no list. A matching empty-pending
state must therefore permit Enter/Tab to await the first current result when
normal list-row room exists. This does not invent an invisible highlighted
choice: navigation and immediate row acceptance still require real current
rows; an explicit pending wait uses the current first-result/ownership rules.

Use the existing passive linked completion entry, requestFocus:false. Only
while a current pendingMention exists but there are no retained visible rows,
its LayoutBuilder may return a transparent one-cell-high SizedBox with positive
available width (explicit width if the surrounding constraints do not supply
it). It draws no rule, background, placeholder or choice. This geometry-only
surface requires the separately gated opaque:false follower above and remains
consistent with CTUI-23's entry.visible definition; visibility itself is unchanged. It must not add focus, pointer handlers, wheel
absorption, paint/selection occlusion or a change to transcript/prompt geometry.
Normal list/searching/agent-empty drawing replaces it when that is appropriate.
Do not use it before a current pendingMention exists or for an empty-agent
snapshot that has no pending match under the original rules.

Report potential list-row room from the same follower LayoutBuilder constraints
and normal furniture allocation, including the rule a result list would need;
a one-row surface alone is not proof that an actual result row can fit. No
independent page-height calculation or cached shim height. At dispatch and
pending-result resolution, combine entry.visible with current positive row
room and live query/candidate/session/attachment ownership. An explicit wait
may resolve to its current first result without fabricating an interim row.
Use existing geometry freshness/budget rules; add no pass, replay or retry.

Zero available row room, zero-width/unlinked surface, dismissal or stale
ownership disables navigation/acceptance and drops an awaited pick. Enter
then follows normal draft submission, Tab does nothing. The entry's false raw
visibility invalidates stale positive child reports when child layout is
skipped. Returning room never replays the dropped acceptance. Test the empty
pending wait/result path, the150ms searching transition, room loss/return,
unlink/disposal and unchanged underlying pointer/wheel/selection behavior.
Every async path checks current ownership.

## Drawing at both sizes

The list floats over the transcript above the prompt, with a dim top rule,
the existing panel padding and no title/frame/extra footer/selection glyph.
It keeps the transcript's height/scroll, prompt gap, status and cursor rows.
Its requested row limit is max(3, floor(window rows / 4)): ten at 120x40,
six at 80x24, clipped further to actual available room. Follow the highlight
inside that viewport; long paths/names cut to row width but insert in full.
No new scrollbar is introduced. An overflowing finder owns wheel, with its
underlying transcript unchanged; use the original-sized fitting/overflowing
cases rather than forcing extra rows.

One path/name per row. Selected row uses permission colour; other file rows
are dim. Unselected agent names use supplied existing agent colours; `main`
uses dim text. No new palette role or bold. Plain preserves existing port
NO_COLOR policy. An empty recipient row has no highlight or spinner.

At 120x40 and 80x24 the proposed populated agent list has the same contents
and ordering, within the floating room (excerpts, not new glyphs):

```text
──────────────────────────────────────────────────────────
  parser
  docs
  bugfix
  bugfix 2

╭────────────────────────────────────────────────────────╮
│ › @@                                                   │
╰────────────────────────────────────────────────────────╯
```

With no recipient, replace those four rows by `No agents to mention`; with an
unmatched query and a nonempty snapshot, `No matching agents`. Focus remains
in the prompt; the overlay owns only its described completion keys. There is
no separate filter editor.

## Sent mentions

Single-@ mentions remain literal prompt text. Attach one ACP `resource_link`
per valid offered file, in first typed order, using the original literal name
and file URI. Re-walk/validate current files when resolving attachment links;
directories, ignored/missing/outside-tree paths stay text only. A failed walk
costs no prompt text. Repeated paths attach once. Consume agent tokens first,
including quoted names with embedded @, so `@@` attaches no file and routes
nothing. Queue/send paths preserve current original ordering, ownership and
cancellation; no late attachment can target a switched/disposed session.

## Keys and shortcuts

All introduced completion actions use existing Actions descriptions/catalog
conventions: Up/Down highlight, Tab/Enter complete, Esc dismiss. Preserve
normal Enter submission and Tab no-op/other existing behavior when no choice
is eligible, rather than swallowing input globally. Add no unsupported
steering/runtime/team action to help. Keep the existing key-help snapshot
and natural panel sizing; an overflowing help/finder box owns wheel.

## Original evidence beside proposed port

Captured using `bun dev chord --fake --qa ctui-designer-120` at120x40 and80x24,
with neutral files notes.md, source.dart and space name.txt in its QA directory.
Matching `.ansi` files retain highlight/colour evidence. No recipient runtimes
were created for the empty-state captures.

| State | Original 120x40 / 80x24 | Proposed port |
| --- | --- | --- |
| @ file list | [120](evidence/CTUI-24/original-files-120x40.txt) / [80](evidence/CTUI-24/original-files-80x24.txt) | Same floating placement, rule, literal rows and highlight; keep approved port transcript geometry/header. |
| @@ empty | [120](evidence/CTUI-24/original-agents-empty-120x40.txt) / [80](evidence/CTUI-24/original-agents-empty-80x24.txt) | Same dim empty row; production candidates are staged empty, not live routing. |

Complete captures are the full-window reference/mock for the same proposed
states, retaining already-approved port wrapping/header/staged-feature
differences. Populated runtime reachability is original-defined, but its live
provider is explicitly deferred. Populated injected fixtures must prove the
same rows, ordering, colours, quoting and empty-query transitions. Add actual
matched port captures at the implementation handover before claiming parity.
No OpenTUI clipping/selection quirks are a target; record deliberate differences.

## Acceptance and handover

Pure tests cover trigger boundaries, Unicode cursor/suffix handling, quotes,
agent-token attachment exclusion, dedup/order and exact insertion. File package
trials demonstrate nested ignore/dotfiles/nonrepository operation under AOT;
no custom ignore workaround without an owner decision. Use temporary trees.
Async tests retain late result/walk/session/disposal cancellation, slow marker,
waiting and moved-highlight picks, no-match Enter/Tab and typing during wait.

Screen fixtures cover populated/empty/no-match @/@@, long paths/names, six/ten
rows, scrolling, zero room and room return, light/dark/plain, both required
sizes and resize while pending. Assert prompt focus/cursor, draft, status rows
and transcript offset remain intact; exercise real production completion
plumbing with injected snapshots. Fake ACP proves valid links once in order
and no @@ link/routing. No real model or live registry is needed.

Designer acts only on developer's named completed unit/commit/launch command,
captures the live original beside port, records findings in one pass, cleans
owned resources and hands to reviewer. Existing staged recipient boundary is
not a reason to claim live roster acceptance. Tester owns final heavy runs.
