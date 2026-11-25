# CTUI-26 framework draft

## Recommendation and ownership

No framework prerequisite. Keep saved-session files, discovery, JSON Lines,
record replay, XDG location, ACP reopening and failure policy entirely in
`example/chord/`. Add no public class, export, service, render object, parent
data or scheduler hook in `lib/`. A file-backed store is not terminal machinery,
and the brief needs only chord's particular append-only conversation record.
A generic atomic-replacement service would be the wrong abstraction: replacing
the file could discard another process's appends and opaque original history.

Flutter also leaves application persistence to application services/packages.
Its StatefulWidget/State and ListenableBuilder-shaped observation are enough
here; async I/O must not occur in build, layout or paint. Flutter's lazy lists
use viewports and slivers; this framework already has ListView.builder and
RenderListViewport. This feature needs those existing cell constraints,
clipping and row extents, not a new sliver protocol, restoration bucket,
keep-alive layer, raster layer or scheduler.

## Evidence inspected

Required repository documents: AGENTS.md, README.md, docs/FEATURES.md,
docs/decisions.md and the brief. Relevant designs: CTUI-15's session/reducer
and deferred resume seam; CTUI-18's Picker activation; CTUI-22's picker
observation. Inspected existing Picker, PickerRow, PickerState, ListView,
RenderListViewport, TextInput, TextLayout, diffBuffers, start page/startLayout,
settings picker, prompt-overlay budget functions, session/conversation and
transcript entry writers.

Original source: `../chord/src/session/record.ts`, `replay.ts`, `sessions.ts`,
`state_dir.ts`, `../chord/src/ui/pickers/picker.ts`, `Pickers.tsx`, the installed
xdg-basedir 5.1.0 implementation, guide resume sections and
`../chord/docs/design/CHD-445.md`. This is source evidence and small compiled
primitive trials; it is not live original/port screen comparison evidence.

## Existing classes and public APIs consumed

- Picker<T>: items, initialValue, itemBuilder, maxVisibleRows, enabled,
  focusNode, unhandledKeys, onSelected and onCanceled. Keep searchable false:
  the original resume picker has a directory-scope toggle, not a text filter.
  Its default clamped navigation and tall-row line stepping already fit.
- PickerItem<T> carries stable unique values; choose the session id after
  discovery deduplicates by session id. Never persist a Picker index.
- LayoutBuilder, Row, Column, SizedBox, Expanded, Padding, Box and Text compose
  the frame and hanging labels. Theme/port palette supply styles.
- Focus/FocusNode, Actions/Binding and KeyHelp supply existing routing and
  descriptions. Port shortcut catalog adds only the original resume actions.
- Overlay, OverlayEntry and the existing prompt placement host the inline
  picker; the existing startLayout(framed: true) budget serves the startup page.
- ListenableBuilder publishes loaded port state; runApp.beforeExit awaits
  port-owned final cleanup after terminal restoration. The existing process
  signal owner remains responsible for ordering session shutdown and flush.

Proposed port-only seams, to be reconciled with runtime's draft: plain
Resume/SessionRecord values in session/sessions.dart; FileRecording implementing
an injected Recording boundary in session/record.dart; record-to-action and
agent-replay-to-action functions in record.dart/replay.dart. Reads and writes
accept an injected directory and ordinary async functions for tests. There is
no generic Store<T>, widget-owned file handle or dependency on BuildContext.
Runtime owns exact Recording signatures and lifecycle ordering.

## Layout and paint algorithm

The page or overlay receives finite cell width and height. Subtract existing
border, padding, title, description, gap and wrapped hint rows before assigning
Picker its row budget. In zero choice room, omit or disable the choice list
and its acceptance/navigation bindings; retain the original remaining chrome
and scope/cancel actions. Do not accept a cached selection merely because it
was visible before a resize. Keep the current two-pass settlement limit.

Build metadata columns once from the immutable offered-session snapshot:
relative time, optional directory and any supported label prefix. Compute
column widths with cellWidth, not String.length. Directory display uses the
original maximum of 30 cells and existing cutPath; raw cwd remains unchanged.
Freeze the relative-time reference for one picker opening, as the original
freezes it, so time does not cause rows to move under the highlight.

For a hanging row, Picker draws its existing highlight/number/edge gutters.
Its itemBuilder returns a LayoutBuilder receiving the actual remaining content
width. Pass the enclosing frame's inner width into that closure as well.
Let L be the widest metadata prefix including its two-space separator; W the
actual content width; I the enclosing frame inner width. If W - L >= I / 2,
return a Row with a fixed L-cell prefix and Expanded(Text(title)); otherwise
return a Column containing the metadata line and Text(title) beneath it.
Use crossAxisAlignment.start and mainAxisSize.min. Metadata-only lines omit
trailing alignment blanks in the stacked form. The existing Text layout owns
word wrapping, hard breaking of an overlong word, graphemes and CJK widths.
Do not prewrap title strings, make a second port text shaper, or measure one
string layout and paint a separately reconstructed line array.

Picker already derives measured item heights from its ScrollController and
uses the existing pickerRoom/pickerMove/pickerLines functions for reveal,
edge arrows and hidden-item footer. Its edge gutter can reduce actual content
width by two cells when overflow begins. The row LayoutBuilder sees that
change and chooses the correct hanging/stacked form. Boundary fixtures must
cover an overflow-induced switch and convergence within the existing host
budget; source inspection alone does not establish that every transition
settles. If that gate fails, return the specific failing case to the owner;
do not introduce another pass or duplicate wrapping in the port.

Text and Box paint ordinary glyphs/background/border into the existing clipped
cell canvas. RenderListViewport offsets visible children by measured scroll
position and clips them to its rectangle. diffBuffers compares the final
buffer against the prior frame, writes changed cells/styles and preserves the
existing wide-character tail treatment. Persistence never paints, changes
terminal ownership or writes escape sequences itself.

Keys still travel through the existing focused tree and Actions matcher.
The parent owns Ctrl+A's scope action and original close/quit actions; Picker
owns arrows/j/k, digits and Enter while visible and active. The scope switch
must publish a fresh coherent choices snapshot and apply the original reset
semantics. A selection callback validates the current snapshot and startup/
window generation before starting a resume. No awaiting operation retains a
render object, focus node or widget as the authority for which session to use.

## Replay, identity and invalidation

The on-disk record is input to plain port reducers, not serialized widgets or
render objects. Replay supported actions in record order before publishing the
new session transcript. Existing reducers and occurrence-identity writers own
entry identity; never serialize EntryIdentity, TextRun caches, scroll offsets,
selection fragments or terminal cells. Reopening is a new in-memory document,
so old selection/code-pick ownership cannot migrate to equal turn IDs in it.

CTUI-15 mentions inBatch as a future seam, but current entries.dart contains
only appended/lastReplaced/replacedAt. Do not claim bulk replay is already
implemented or linear. If measured replay repeatedly copies a growing list,
runtime must specify a port-owned batch writer that preserves every existing
entry/identity invariant and passes the CTUI-15 performance gate. This is not
a reason to add a framework collection API or change live update behavior.

The owner settled opaque preservation: append without altering any existing
bytes or original lines. Replay only supported history, revive no children,
teams or monitors, and show exactly one window notice after replay when
history parts were omitted: `Some saved history is not shown in this version.`
The notice is presentation, not a fabricated historical event to append back
to the record. Runtime must define omitted versus intentionally nondrawing
metadata; an opened/state/header line alone does not establish missing history.

## Persistence primitives and package gates

Retained sources, lock, sanitized outputs and reproduction instructions:
[framework primitive evidence](../framework/README.md).

Use SDK dart:convert jsonEncode/jsonDecode, utf8.decoder and LineSplitter;
SDK dart:io File.openRead, Directory and async append operations; existing
path 1.9.1 for joins. JSONL is one SDK JSON value per line, not a new parser.
Reading a malformed line and projecting the original known record kinds are
port compatibility policy. No new database, atomic-write, lock, JSON parser,
filesystem abstraction or queue package is proposed. The runtime writer's
serial future chain is ordering of chord events, not a replacement scheduler.
SDK file APIs are native APIs under dart compile exe; they need no wrapper
package merely to expose append or streaming reads.

A compiled SDK probe wrote a session header and a prompt containing Unicode
using awaited File.writeAsString(..., mode: FileMode.append, flush: false),
read them through openRead -> utf8.decoder -> LineSplitter, checked the second
value after jsonDecode, then opened an append handle, flushed and closed it.
Output: `PASS SDK JSONL append/UTF-8 stream/flush/close`. This establishes API
availability and round-trip behavior, not cross-process atomicity, power-loss
durability or production writer lifecycle correctness.

New port dependency recommendation: [uuid 4.6.0](https://pub.dev/packages/uuid),
using const Uuid().v4() for an independent record basename, matching the
original randomUUID filename policy. ACP session ids remain literal header
values and never become filenames. AOT probe generated 10,000 IDs, checked
unique count 10,000 and every value against the v4/variant canonical lowercase
pattern. Each tested environment printed `PASS uuid: 10000 distinct v4 values`.
No UUID implementation is written here.

State-location candidate: Flutter-maintained
[xdg_directories 1.1.0](https://pub.dev/packages/xdg_directories), specifically
stateHome.path, then existing path.join(base, 'chord', 'records'). Its package
metadata advertises Linux, but the tested stateHome implementation is pure
Dart environment/path handling, with no platform gate or subprocess. It
compiled and ran on the current macOS arm64 host. This does not certify every
API of the package on macOS; this slice uses only stateHome.

AOT trial dependencies resolved from the local pub cache:

| Package | Version |
| --- | --- |
| uuid | 4.6.0 |
| xdg_directories | 1.1.0 |
| path | 1.9.1 |
| crypto | 3.0.8 |
| fixnum | 1.1.1 |
| meta | 1.19.0 |

Dart SDK: 3.13.5 stable, macos_arm64. The probe compiled with
`dart --suppress-analytics compile exe probe.dart -o probe`. Offline pub get
produced the lock/config and resolved the six packages, then exited 66 because
its cache active-roots bookkeeping was sandbox-denied; compilation using the
produced configuration exited 0. Initial SDK compilation without analytics
suppression produced a binary but exited 1 on telemetry bookkeeping; the
suppressed rerun exited 0. Neither bookkeeping failure is a package/AOT
failure. No production dependency file was changed.

Compared the compiled candidate against Bun importing the original installed
xdg-basedir 5.1.0. Printed only boolean outcomes, no real directory values:

| Environment | xdg_directories result | Original result |
| --- | --- | --- |
| Explicit absolute XDG_STATE_HOME | override used | override used |
| Relative XDG_STATE_HOME | relative value used | relative value used |
| Empty XDG_STATE_HOME, HOME present | default state suffix | default state suffix |
| Missing XDG_STATE_HOME, HOME present | default state suffix | default state suffix |
| Missing XDG_STATE_HOME and HOME | StateError | OS account home fallback |

Contrary to an initial concern, the actual original does not reject relative
XDG_STATE_HOME. Preserve that behavior; no absolute-path validation is added.
Missing HOME is a real package misfit: Dart's candidate requires HOME for its
fallback, while Node/Bun os.homedir resolves the account home on this host.
Options sent to main: accept the explicit environment requirement; trial an
additional maintained OS-home provider; defer the shared default location.
Main approved the first: require nonempty HOME or XDG_STATE_HOME and give a
clear error otherwise. This bounded compatibility difference belongs in the
final design/decisions. No package workaround or native home lookup is added.

## Concurrency and compatibility decisions

Owner settled: no cross-process lock. Serialize appends within a process and
retain the original documented possibility of turns interleaving across
processes. The original guide explicitly allows parallel reopen and warns
about this. A Dart-only advisory lock could not exclude original writers;
changing that policy would require a coordinated protocol outside this task.
Do not describe append, one process's flush, or a complete newline as an
interprocess transaction or a guarantee against partial writes/crashes.

Version 1 is a compatibility target, not proof that every original event is
supported by the port. Preserve unknown original content by never rewriting
old bytes, distinguish drawing omissions from ACP load failures, and let the
original agent/session behavior govern unknown ids. Sharing the directory
must never mean automatic schema migration or deletion of legacy windows.
The settled HOME requirement is the explicit environment limitation above.
No owner question remains open in this draft.

## Cost and required acceptance

Let N be offered sessions, B scanned record bytes, M replayed events, V visible
rows, T laid-out row text, C terminal cells and Q queued write bytes.

- Discovery reads O(B) bytes, with bounded concurrent file streams and retained
  summaries O(N), plus current line buffers. It is not a header-only scan:
  prompts and titles can occur throughout a record. An individual enormous
  line still costs its full size. Sorting summaries costs O(N log N).
- Each appended event encodes O(event bytes); queued bytes occupy O(Q). Writes
  append pending bytes, without O(total history) rewrites. The original has
  no hard queue bound; runtime must report that limit honestly.
- Initial list sizing and width invalidation can measure every item: O(T)
  shaping plus O(N) extent bookkeeping, with only visible widgets retained.
  Picker scans its result heights; do not claim O(V) total layout work.
  Current Picker builds ListView without itemVersion, so rebuilds may discard
  every cached height. Long-list measurements must include this current cost.
- Steady cell diff costs O(C); terminal output scales with changed cells.
  Layout/paint uses existing frame batching; disk completion must not force a
  frame per line. No record scan occurs during layout or every frame.
- Record parsing is O(record bytes); action folding is not proven O(M) with
  today's copied lists. Measure large compiled replay separately from frame
  time and from discovery. Do not turn an intended batch optimization into
  a claimed current property.

Implementation stays under example/chord: new record/replay/sessions/state-dir
modules, session/conversation ingress, startup/CLI resume routing, picker and
resume page composition, transcript/window state, shortcuts and owned tests.
Port pubspec/lock gain only approved packages. Existing framework files listed
above are read dependencies and require no modification.

The ship gate needs pure record/discovery/replay tests plus real original/port
fixtures at 120x40 and 80x24, relevant dark/light/plain themes and narrow edges.
Include long Unicode titles, wide directory names, the half-width hanging
threshold on both sides, overflow changing the edge gutter, a row taller than
the viewport, empty/zero-room states, scope reset, same-batch keys, resize then
Enter, loading/cancel/stale completion, omission notice exactly once, and fresh
selection ownership after swap. A compiled smoke uses isolated state and the
original fake, never a real model; prove bidirectional main-session record
interchange and untouched original byte prefixes. Runtime owns slow/failing
write, drain, shutdown, crash-tail and concurrent append cases. Live screen
parity, high-volume performance and crash durability are not established by
this design-only primitive trial.
