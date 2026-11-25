# CTUI-26: sessions saved and resumed

This is the design for ship. The brief and three architect drafts remain in
[evidence/CTUI-26/drafts](evidence/CTUI-26/drafts/); this file resolves their
conflicts and takes precedence. Critic dispositions are at the end. No
production implementation or runtime parity is claimed by this design commit.

Original specification: `../chord` at
`577b58167672e12c999aeaf4eed2a1a988513dc2`, particularly
`src/session/{record,replay,sessions,session,conversation,state_dir}.ts`,
`src/ui/pickers/`, `src/ui/app/{Start.tsx,start_layout.ts,sessions.ts}`,
`src/ui/header/header.ts`, `src/cli.ts`, `src/main.tsx`, `docs/guide.md`,
CHD-445 and CHD-493. Current source supersedes historical CHD-174 window
records. Port baseline: `c32e433417abba75f0a5378edec65c3c5546af36`.
CTUI-15's session/conversation/reducer separation, CTUI-18/20's Picker/start
contracts and CTUI-21/22/23's window, settings and command contracts continue.

## Scope and ownership

Save one main session and continue it through `-c`/`--continue`,
`-r`/`--resume [id]`, `/resume` and the startup resume page. The record is
compatible with the original's version-1 JSONL where the port supports its
history. Both programs use the same XDG state store. Reopening an agent's
session is still an ACP operation: a local record never proves the agent
can resume it.

All implementation belongs under `example/chord/`. No new framework API,
file-store widget, atomic replacement service, database, lock protocol or
scheduler is needed. Existing SDK JSON/file/stream operations and maintained
UUID/XDG packages cover persistence primitives. Existing terminal widgets
cover layout. A general store in `lib/` would expose chord policy; replacing
a record would risk losing opaque history and concurrent appends.

Children, teams and monitors stay M4/M5 seams. Do not read their separate
records or revive their processes. Fork, headless mode, elicitation,
compaction, costs, rename actions, terminal resume variables and settings
files are not brought forward. Existing original lines remain intact even
when their content cannot yet be drawn. The approved visible difference is
one plain notice when history is omitted. The approved environment difference
is the HOME/XDG requirement below. An unsupported header version is refused
before starting an agent, as specified below. Existing approved CLI
help/version and other staged port differences remain.

## Buildable units

Every unit names its source/test ownership under `example/chord/`. They
can be reviewed independently; integration waits for their dependencies.

| Unit | Implementation and contract | Gate | Depends on |
| --- | --- | --- | --- |
| U1 | `session/state_dir.dart`, `sessions.dart`, record views/codecs in `record.dart`; UUID/XDG dependencies, summaries, find/list, labels and English ages | Mirrored pure tests; retained original parser/age fixtures; SDK/package AOT probes repeated against production resolution | — |
| U2 | `record.dart` Recording/FileRecording, admission snapshots, hold/queue/drain/failure lifecycle | Injected slow/failed append and reentrancy tests, byte-prefix interchange | U1 |
| U3 | ACP load/resume members/views, `inbox.dart` synchronous reply partition, `session.dart` history and submitted-content seam, `replay.dart`, enricher recall | In-memory same-read/split-read tests, original fake method/cwd/id assertions, malformed/cancel cleanup | U1 |
| U4 | `conversation.dart` recording/swap/history events; `transcript/entries.dart` private replay accumulator; `ui/app/state.dart`, `start_connection.dart`, `launch_connection.dart` one publication and ownership | Replay equivalence/identity/linear-copy tests; generation/reentrancy/close/flush checks | U2, U3 |
| U5 | Resume pure state and `ui/pickers/pickers.dart` composition; resumed compact-header facts and plain omission line | Widget checks at 120x40/80x24, narrow threshold/overflow/focus/zero-room gates | U1, U4 |
| U6 | `cli.dart` approved resume-token adapter, `bin/chord.dart` routing, shared title composition in `ui/app/start.dart` and startup resume page | Original CLI oracle; injected picker cancellation starts zero processes; any-directory start and ownership refusals | U1, U3, U5 |
| U7 | Prompt command dispatcher/catalog, resume overlay state, described Actions and shortcuts | Busy/list/error/cross-directory/queue-return/swap tests; same-batch keys and permission priority | U4, U5 |
| U8 | Owned fixtures, compiled executable and bidirectional original-fake interchange | Paired screen evidence, record bytes/method/id, scale metrics and complete process/PTY cleanup | U1–U7 |

New files have mirrored tests under `test/session/`, `test/ui/` or `test/acp/`;
existing modules gain focused cases. Ship may split a unit further without
changing its boundary. No framework source/test change is a prerequisite.

CTUI-53 is the mandatory last unit of this same branch/slice after U8's
pre-fix scale evidence. Its [short design](CTUI-53.md) replaces the two
filesystem isolate jobs with a port-owned cooperative cleanup barrier;
current scan/history APIs, store/projection semantics and framework scope
remain unchanged. Final readiness requires its JIT/AOT own-handle proof and
affected scale reruns. Earlier acceptance of unresolved handles is historical
only and is superseded by this unit.

## Store and record format

Use `xdg_directories` 1.1.0 `stateHome.path`, then existing `path.join` with
`chord` and `records`. Nonempty XDG_STATE_HOME wins; otherwise HOME supplies
the package default state suffix. Relative overrides are accepted by the
actual original and candidate; do not add absolute-path validation. If both
variables are absent/empty, report a clear error naming the requirement.
The original can resolve OS account home without HOME; main explicitly
accepted this package limit. No native fallback is added. New-session save
failures use the once-only record warning and do not stop the agent; a
resume/discovery request that cannot locate its store reports that error.
Tests include explicit XDG with HOME absent. Do not access user state in tests.

Use `uuid` 4.6.0 v4 for independent `<uuid>.jsonl` basenames. ACP ids stay
literal header values, never filenames. Reopening a selected record appends
to its existing path. Legacy `windows/` files are ignored and untouched;
`w-…` is an unknown session id and goes to the agent like any other.

Generated records are compact UTF-8 JSONL with `type` first and a newline
per entry. The original summary scanner relies on exact type-first prefixes.
Separate raw JSON views from sealed transcript actions; unknown fields and
nested `_meta` remain in raw update maps. Examples of original-shaped lines:

```jsonl
{"type":"session","version":1,"sessionId":"session-id","agent":"fake","cwd":"fixture-project","at":0}
{"type":"opened","at":0}
{"type":"state","options":{}}
{"type":"prompt","turnId":"turn-1","at":1,"prompt":"hello","images":0}
{"type":"update","turnId":"turn-1","update":{"sessionUpdate":"agent_message_chunk","content":{"type":"text","text":"hello back"}}}
{"type":"result","turnId":"turn-1","result":{"status":"completed","stopReason":"end_turn"}}
{"type":"result","turnId":"turn-2","result":{"status":"failed","error":{"message":"refused","code":"-32000"}}}
```

The result codec is explicit: completed/cancelled records carry `status` and
`stopReason`; failed records contain nested `error.message` and optional
string `error.code`. Do not serialize Dart's flattened TurnFailed fields.
Live numeric RPC codes encode as strings. Reading retains original raw codes;
a representable integer string can map to the current numeric display field.
Other strings retain the message and flag omitted detail. Historical
completed/cancelled status must survive independently of stopReason: a
recorded completed/cancelled mismatch follows the original status for its
ending row. Extend the port result representation at that seam; live result
behavior is unchanged. Sign-in/account data is never promoted to live state.

Read UTF-8 with replacement behavior matching Node, then line splitting and
SDK jsonDecode. Parse valid JSON even without a final newline. Skip blank,
syntactically invalid or individually malformed supported entries without
losing subsequent entries. Only version 1 is the interchange target. Refuse
an unsupported header version before starting any agent process, name the
version in the error and leave the file untouched. This owner-approved guard
is a deliberate difference from the original; do not guess, migrate or repair
the format. Missing and malformed-only records retain their separate reopen
behavior. For supported records, preserve every existing byte as an append
prefix. Never compact, migrate, repair, truncate or rewrite old lines. A torn final line may absorb the first appended line: this is the
original limit, and crash loss is not promised to be one line. Retain a test
for this exact behavior rather than inserting a hidden separator.

### Supported projection and omitted history

| Input | Projection |
| --- | --- |
| `session` | Identity/summary metadata; no row |
| `opened` | End unfinished historical turn and disconnected boundary |
| `state` | Metadata only; never issue historical setters |
| Ordinary `prompt` | Split existing shell context; restore image placeholders and literal mentions; no file reread |
| Main `update` | Supported list below, through current reducers |
| `cancel`, `disconnected`, `result` | Historical actions with original times/result semantics; omit disconnected line on write if its time is absent |
| `renamed`, main `session_info_update` | Discovery/opened-header title metadata; null clears, blank ignored, subagent titles ignored; no rename setter/history UI |
| `usage` cost lines; `served`, `ran`, `closed`, `asked`, `answered`, `plan_asked`, `plan_answered`, `stopping`, `self_started`, `forked` | Preserve opaque bytes; omit unsupported history and set notice flag |
| Unknown meaningful kind or malformed nonempty history | Skip safely; set the same notice flag |

Supported main updates are `agent_message_chunk`, `agent_thought_chunk`,
`tool_call`, `tool_call_update`, base `plan`, `usage_update` context and
`current_mode_update`. `config_option_update` and `available_commands_update`
are recognized state/command metadata; their lack of a row is intentional.
`session_info_update` title is recognized metadata. Recorded
`user_message_chunk` does not duplicate the authoritative prompt line; in
agent-load replay its contiguous chunks form prompts. Other update kinds,
subagent-targeted updates and prompts with unsupported `from`/`into` semantics
are omitted and flagged. Do not reinterpret a sender's prompt as the person's.
Header child/task/team provenance also signals deferred history. Main tool
calls can draw their ordinary supported fields; do not invent served/team
semantics. Extra unknown keys alone, and intentionally nondrawing metadata,
do not trigger a notice.

When any meaningful part is omitted, add exactly one window-only line after
supported replay, before live output:

```text
Some saved history is not shown in this version.
```

Use ordinary transcript text, normal wrapping/inset, no severity glyph or
agent label. It is presentation, bypasses Recording, and is never sent to the
agent or saved as history. Deduplicate per successful opening, including
resize/rebuild. No notice for a wholly supported record. The original child
and monitor notices name particular runtimes and do not fit arbitrary omitted
history; main approved this plain fallback.

`history-` prefixes separate historical turn ids from new ids. At next prompt,
opened boundary or EOF, synthesize the original completed/end_turn result for
an unfinished historical turn. This settles drawing and asserts no actual
agent completion. Preserve withImages' existing-placeholder count; converted
agent history writes `images:0` when placeholders are already in text. Never
restore pending RPC permissions, timers or input from a record.

## Recording while the agent streams

A port Recording interface owns `opened`, `sent`, `heard` and `flushed`.
FileRecording accepts injectable directory, clock, UUID source, append
operation and failure callback. Its calls synchronously snapshot/encode and
enqueue; the UI/agent does not await disk writes. No file IO occurs in build,
layout or paint.

A new open holds header, converted agent history when needed, opened time and
current state. A known-record open holds only opened/state. Hold subsequent
updates until an actual submitted prompt releases those lines before its
prompt line. Merely opening or looking at a resumed session changes no bytes
or last-use time. Clearing/replacing an unprompted open discards its hold.
Later-feature rename/receipt exceptions are outside this runtime.

Add a per-call submitted-content seam to Session.prompt, registered before
asking ACP and carrying Conversation's turn id. Observe its matching admitted
`ChordTraffic` `session/prompt` for the expected session in the existing
transport tap: Writer.enqueue takes the queue position before tapping it.
Snapshot the finalized content after shell-context assembly and asynchronous
mention resolution, including links and image count, before external listeners
or inbound agent updates. Invoke once only for that call's actual outbound
admission, never on the prompt response or UI PromptAction. Cancellation or
reentrant close before admission records neither unsent prompt nor its failure
result. A closed call cannot claim a replacement's later admission. Preserve
embedded-resource metadata only; do not persist image/audio payloads. Record
callback failure must not break the ACP pipe.

Hear enriched semantic events before window listeners. Record updates whole
and record model/mode/options only when changed. Do not rerun enrichers during
recording. Permission RPCs and local reports/drafts/queue are not persisted.
Unsubmitted shell runs remain unsaved; only submitted shell context is kept.

One process-owned drain carries `(path, encodedLine)` entries, snapshots a
batch, groups by path preserving per-path order, awaits appends and repeats.
Enqueues during a write join its next batch. A queued path never follows the
new current session after a swap. The single-main owner does not create a
second live Conversation for its current session id. No generic lock table,
lockfile, PID lease or stale-lock recovery is introduced.

Main chose the original concurrency contract: serialize appends per process;
other original/port processes may open the same session and interleave turns.
Document the same advice to close it in the other pane before resuming here.
A Dart-only advisory lock would not exclude the original. Append completion
is not an interprocess transaction or power-loss durability guarantee.

`flushed()` joins the active drain, including enqueues during it; it does not
persist unprompted holds. A mkdir/append failure drops the uncertain taken
batch and pending queue, reports `Could not keep this session's record:
<message>` once, and lets the session run. Later events retry fresh writes,
as in the original. Do not retry uncertain partially written bytes or
permanently disable recording. A throwing warning callback cannot wedge the
drain. Snapshot mutable wire maps before queuing.

Close establishes its barrier before listeners/cancellation, ends admission,
stops settle/open/replay work and all current/retiring agents through existing
process-group ownership, then joins admitted writes. Late results/settings/
updates cannot cross the barrier. Final flush precedes completed close.
Filesystem operations have no original timeout; neither all shutdown IO nor
queue memory is bounded. Do not add dropping, ACP backpressure or a forced
flush deadline without a new owner decision. A thousand updates between
frames remain a thousand ordered lines; only painting is coalesced.

## ACP reopen and the synchronous replay boundary

Add Agent.loadSession/resumeSession through existing request/cancellation
machinery and shared answer views. Load/resume answers have model/mode/options
but no new sessionId: retain the requested id, and do not access
NewSessionResponse.sessionId. Requests carry that id, selected cwd and the
same current MCP policy as new sessions. No new client capability is declared.

Maintain separate `rawHasPast` and supported/omitted projections. `rawHasPast`
is original parsed-record presence (`recorded.length > 0`), not supported
historical action count. Header-only and opaque-only parsed history count;
a missing or wholly unparseable record does not. The selected original record
path remains the append destination even if reading it finds no past, matching
the original. No automatic header repair is implied for a disappeared file.

| rawHasPast | Offers resume | Offers load | Selected operation and history |
| --- | --- | --- | --- |
| true | yes | either | resume; local supported projection |
| true | no | either | load; local projection, discard agent replay |
| false | yes | yes | load; agent replay |
| false | yes | no | resume; no fabricated past |
| false | no | either | load; agent replay if successful |

Session selects and invokes load even when neither operation is advertised.
Preserve the original connection-level offered guard: when load is not
advertised, the connection refuses locally with
`The agent does not offer session/load.` and sends no RPC. The table
describes operation selection; only an offered method reaches the wire. Never fallback to new, retry another
method automatically or treat a local record as successful ACP resume.
Failure closes the attempted process and reports `it cannot resume session <id>: <agent error>`. A failed ACP open
publishes no prepared partial history and never restores the retired runtime.

The fence is synchronous, not an await continuation. One byte read can contain
HISTORY, reply and LIVE; the decoder processes all three before the reply's
Future continuation runs. Extend the existing SessionInbox traffic ingress:

1. `beginReopen(method, requestedSessionId)` arms before Agent's request.
   `hear(ChordTraffic)` captures the matching load/resume method **and**
   params.sessionId's JSON-RPC id. Initialize/setter traffic cannot claim it.
2. `hear(AgentTraffic)` observes the response with that id and changes the
   pre/post-reply partition immediately, in the existing tap before routing
   the reply and before the decoder reads the next frame. Keep post-reply
   notifications buffered; do not fold them into state yet.
3. After the await validates the shared answer, `completeReopen(answer,
   rawHasPast)` seeds authoritative AgentState, extracts the history partition
   and orders retained live updates. Load's pre-reply notifications are agent
   history only when rawHasPast is false; otherwise discard them. Resume's
   pre-reply notifications are LIVE because resume replays nothing: retain
   them before post-reply notifications, and apply both after answer seeding.
   Thus early resume state may override the answer, then later live state
   overrides it. Filter notifications by the requested session id.
4. Session exposes prepared historical actions and resumed/omission facts.
   Conversation emits one HistoryReplayed-style batch event; it holds no
   Transcript. StartConnection/reduceApp owns detached folding and one app
   publication before live subscription drain and Connected. Replay and its
   notice bypass Recording. Call Recording.opened before admitting retained
   live events, then drain them in order. Recheck ownership after every
   callback; an observer may close or swap the session synchronously.
5. RPC error, malformed answer, cancellation or replacement discards both
   partitions/prepared history and stops the attempted process. A stale batch
   or callback cannot publish, record or start a replacement session.

Before reopening, recall recorded supported main updates into the enricher
Wire as already heard state, without running the enricher chain again.
RawOutputContent must not inject content twice. Original guardianReview replay
interpretation uses the existing approved metadata logic. Current live answer
and updates override historical settings; history never sends setters.

Current entries.dart has no implemented inBatch despite CTUI-15's planned
seam. Add a package-internal synchronous replay accumulator at the three entry
writers/reducer boundary. Only its detached historical fold may mutate its
private list; no intermediate mutable list or state escapes. Preserve fresh
EntryIdentity per append occurrence, old identity on replacement and unchanged
live copy-on-write behavior. Freeze one final list. Merely publishing once
after repeated whole-list copies is still quadratic and fails the linear
accumulated-copy gate. No persistent collection or framework transaction API
is introduced; CTUI-15's retained collection trials remain applicable.

## Discovery and visible flows

Stream summaries with at most eight files open, extracting first header,
first/last prompt, chronological title/rename metadata and relevant opening
metadata without retaining updates. Missing directory means empty; unreadable
or disappeared individual files are skipped; other directory errors propagate.
Use a once-per-start Future so one launch does not rescan for agent, picker
and selection. Reopening `/resume` scans afresh. No watcher/permanent index.
Last use is last recorded prompt time for prompted sessions, not file mtime
or an unprompted opening. Preserve original stable ties; add no new tie sort.

Continue filters exact cwd, agent and no parent; it picks latest. Earlier
lists filter the selected agent, exclude current id, deduplicate by session id
using latest record and default to local cwd. Titles use last main
session_info_update/rename, null clearing and blank-ignore; task provenance
retains original task-label policy. A child record may be selected as one's
new main, with deferred history notice; none of its former runtimes revive.

| Entry/condition | Visible behavior |
| --- | --- |
| `--continue` | Skip agent picker; latest selected/default agent here; missing: `No earlier <agent> session in <cwd> to continue.` |
| `--resume <id>` | Known record supplies cwd and, with no named agent/override, its agent; unknown id uses selected/default agent and invocation cwd |
| Explicit agent conflicts with recorded id | `Session <id> belongs to another agent (<agent>).` before starting |
| Agent-command override without a named agent | Belongs to default agent alone; preserve record-agent mismatch refusal |
| Bare `--resume` | Title-page picker before any process starts; local scope initially, any-directory selection permitted; Esc quits without resume message |
| Bare resume without terminal | `--resume needs an id when not in a terminal` |
| No startup sessions anywhere | `No earlier <agent> session to resume.`; no global-empty picker |
| `/resume` | Fresh list for main's agent excluding current; local scope initially, even when only remote records exist |
| Failed startup/protocol error | Preserve existing port error screen without prompt or resume overlay anchor; post-failed-start `/resume` is a separate follow-up |
| None anywhere in-window | `No earlier <agent> session to resume, here or in any other directory.` |
| Listing fails | `Could not read the earlier sessions: <error>` through command-report policy |
| Running turn | `A turn is running. Wait for it to end, or press Esc to interrupt it, then /resume.`; use current bound cancel key; recheck after scan and acceptance |
| In-window other cwd | Close picker, retain current session; `That session is in <shown cwd>. Quit and open it there with:` then reopen command on its own line |
| In-window same cwd | Close picker, withdraw queue through current draft-return policy, retire old main and open selected session |

Main approved this failed-start limit for CTUI-26: the original permits
resume commands after failed startup, while the port retains its existing
startup/protocol-error screen without command input or an overlay anchor.
Post-failed-start `/resume` is deferred separately; U7 does not expand that
screen or imply an in-window retry route.

Commands quote agent/id/explicit command safely as original resumeCommand,
including dash-leading id `--resume=` form. Repeat an explicitly typed command
override only for its agent; do not store it or invent unrelated flags. Print
`Resume this session with:` after terminal restoration for a prompted or
successfully resumed main as original resumableSession/resumeMessage decide;
looking-only new sessions and cancelled startup produce nothing. Failed record
writing does not prove the agent cannot resume its id. Current terminal
variables/notifications remain a later seam.

A valid replacement uses the existing clear-style barrier before any await:
increment generation, detach old references, abort old settings/mentions/read/
replay work, withdraw queued input, retire old path/process, emit Cleared and
start the replacement. Late old events write neither replacement file nor UI.
Close joins all retirements even if replacement fails. Clear/resize cannot
restart a scan/replay. Clear selection/code-pick/source ownership on swap;
persisted ids are not occurrence identity.

### CLI package adaptation and relative ages

The approved adapter handles `-r`/`--resume` only, then existing args handles
the remaining CLI. Express absent, pick, continue and id intents explicitly;
never use an empty string sentinel that can collide with an id. Respect
other options' values and `--`. Preserve repeated-option refusal, `-c`
conflict and original flag-name ambiguity, not a conventional reinterpretation.
[cli-trial/oracle.json](evidence/CTUI-26/cli-trial/oracle.json) retains actual
original outcomes, including `--resume=c`/`--resume=-r` as picker,
`--resume=` as absent, `-raaa` unsupported and `--agent-command --resume`
as a command value. Copy original error wording within existing approved
help/stdout, error/stderr and exit-2 layout. Future unsupported options stay
unsupported; this adapter does not implement their behavior.

Original lastUsed uses flooring and six fixed units: 365-day year, 30-day
month, week, day, hour, minute. Under a minute/future is `just now`; one day,
week, month, year use `yesterday`, `last week`, `last month`, `last year`;
otherwise English singular/plural count plus `ago`. Invalid timestamps display
raw. Freeze age reference per scope opening. The approved narrow port uses
[time-trial/oracle.json](evidence/CTUI-26/time-trial/oracle.json), actual Bun
boundary fixtures, rather than timeago rounding or words.

## Resume widgets, states and keys

Proposed port-only composition, no new framework constructor:

```dart
ResumePicker(
  key: ValueKey('resume/$opening/${picker.everywhere}'),
  picker: picker,
  agent: launch.name,
  home: home,
  rows: listRows,
  room: room,
  starting: starting,
  onToggleScope: toggleResumeScope,
  onSelected: pickSession,
  onCanceled: starting ? cancelStartup : closeResumePicker,
);
```

Pure ResumePickerState contains the immutable snapshot, cwd/scope and opening
identity. Caller owns IO/generation; the widget owns focus and Picker's
highlight/viewport only. Scope changes remount a separately keyed list from
the top; resize retains snapshot/highlight and remeasures. Async results and
acceptance validate current generation/session/scope/visibility again.

Use existing Picker with searchable:false, **showNumbers:true**, clamped
navigation, showInitialSelectionAtTop:false, countHiddenItemsAbove:true.
The custom itemBuilder contains metadata/title only. Keep the number in
Picker's separate fixed column so continuation lines retain its inset; the
interface draft's caller-numbered variant is rejected. Default label cutting
is unsuitable: use wrapping Text for titles.

Age, optional future open-now column (empty seam here), optional directory
and title have original two-space separators and list-wide aligned widths.
Directory display uses existing homePath/cutPath, capped at 30 cells. Retain
the original prefix/title split: hang is a UTF-16 string slice offset; measure
the sliced prefix in cells. It is not itself a cell indentation value.
Let I = frame columns minus 4 (border/padding), W = actual content width after
marker, optional two-cell overflow gutter and number column, and L = maximum
prefix cell width including the final two-space separator. Every row uses
hanging Row(prefix, Expanded(title)) when W-L >= I/2; otherwise every row uses
Column(prefix.trimEnd(), title). Metadata Text is exactly one nonwrapping
clipped line in both branches; titles wrap/hard-break via existing Text.
Never wrap a long metadata prefix into extra rows or prewrap title strings.
Carry parent I into the item builder; its LayoutBuilder supplies actual W.
Overflow can alter W, so gate convergence within the existing two-pass budget.

Rounded frame/padding/title/body/gap/hint follow SettingsPicker. Permission/
focus roles color border, bold title and highlighted row; descriptions/hints
are dim; plain theme uses existing role fallback. Selected style spans wrapped
lines. The list body budget follows original framedRows/cutRows and startup
layout, with title/hint priority. Zero visible rows means no list acceptance/
navigation/digit bindings. Scope/cancel remain. No fabricated spinner, query
field, empty-choice wording or hidden-body sentence is added.

At 120x40 startup uses the full mark/tagline, centered version/agent/directory
and 84-cell frame; 80x24 uses the compact art and 78-cell frame. Local labels
hang; wider all-directory metadata can move titles to their own lines. Live
resume is a full-width opaque anchored frame above unchanged prompt/status,
without consuming transcript height. Source-based transitions and observed
capture limits are listed in the interface evidence README/draft.

| State | Required behavior at both sizes |
| --- | --- |
| Local empty, remote exists | `No earlier sessions in this directory.`; scope/cancel hint, no selection |
| Focused local/all | Numbered age/title rows; all adds directory; original edge arrows/hidden count |
| Tall/overflow | Arrows read a clipped selected row one line per press before changing choice; reveal/clamp normally |
| Read pending | Keep current live screen/draft; no invented pending picker; stale completion invalidated |
| Permission/form appears | Retain picker snapshot but suspend its focus/actions while asksPerson UI has priority; reappear afterward |
| Reopen pending | Freeze acceptance immediately; no duplicate process; replace with startup state |
| Reopen fails | Existing startup/protocol error without prompt/resume anchor, no prepared partial history, no successful-resume header; post-failed-start commands remain separately deferred |
| Resumed | Compact header, supported past, optional single plain omission line, then current live output/prompt |
| Narrow/zero-room | Original chrome/clipping priorities; no stale acceptance; inspect 32x10 and threshold neighbors |

Compact header gains original `resumed · <age> · <title>` after help. Omit
absent facts; actual agent title wraps, fallback first prompt uses existing
cut-row policy. Freeze opened facts rather than rewriting the header on later
title updates. Do not insert the large startup splash into live history.

| Key | Active action |
| --- | --- |
| `/resume` + Enter | Local command/completion `Resume an earlier session` |
| Up/k, Down/j | Picker previous/next, clamped; tall-row reading |
| Enter, 1–9 | Accept highlighted/result-position item only with current visible row/input ownership |
| Ctrl+A | Outer resume Actions toggles directory scope, including empty/zero rows |
| Esc | Outer Actions closes live picker or cancels startup; omit Picker-owned Esc |
| Ctrl+C | Existing startup cancel or live clear/cancel/arm/quit priority |
| Ctrl+D | Existing quit path; no fabricated resumable session on cancelled startup |

Omit generic Picker home/end/page/shift-page bindings as existing port pickers
do; do not invent resume navigation. Every active action has a description and
staged shortcut clause. Restore scope/navigation/close clauses when enabled;
startup keeps its compact hint and no new shortcuts panel. Exact hints:
`Enter to resume · Ctrl+a for all directories · Esc to close` in-window,
`Esc to quit` at startup; all scope says `for this directory`. Omit Enter
when no row fits. Resume actions cannot consume a permission answer or prompt
select-all while hidden. Current matcher/geometry freshness and selection
contracts remain in force.

## Original beside the current port

The retained frames are sanitized observations with substitutions documented
in [interface/README.md](evidence/CTUI-26/interface/README.md). Directory labels
were shortened after capture without reflow; use source widths for exact
thresholds. These are before-feature port captures, not target mocks or a
parity pass. Each artifact has corresponding ANSI output.

| Size/state | Original capture | Current port capture | Difference/reason |
| --- | --- | --- | --- |
| 120x40 live resume | [original-120-slash](evidence/CTUI-26/interface/original-120-slash.txt) | [port-120-slash](evidence/CTUI-26/interface/port-120-slash.txt) | Original framed picker; port typed `/resume` has no offered feature yet; not a dispatch-refusal observation |
| 80x24 live resume | [original-80-slash](evidence/CTUI-26/interface/original-80-slash.txt) | [port-80-slash](evidence/CTUI-26/interface/port-80-slash.txt) | Same missing implementation; prompt/status remain visible |
| 120x40 startup | [original-120-start](evidence/CTUI-26/interface/original-120-start.txt) | [port-120-idle](evidence/CTUI-26/interface/port-120-idle.txt) | Current port has ordinary live window, no resume title page |
| 80x24 startup | [original-80-here](evidence/CTUI-26/interface/original-80-here.txt) | [port-80-resume-flag](evidence/CTUI-26/interface/port-80-resume-flag.txt) | Port rejects unknown --resume with help/exit 2; original picks before process start |

Original evidence also covers both-size all-directory, empty-local,
light/plain and permission base screens; 80x24 cross-directory refusal and
32x10 clipping. Combined streaming+picker, permission suspension/reappearance,
failed reopen, resumed header and zero-room transitions remain ship gates.
The narrow original clips its bottom border/hint; do not credit a proposed
repair as parity. See the interface draft's state matrix for exact reached
coverage. The implementation must add paired original/port captures at both
sizes and narrow threshold neighbors, with dark/light/plain and Unicode
labels, retaining any approved differences explicitly.

## Validation, performance and limits

Pure/injected tests cover compact prefixes, unsupported header versions
(refusal naming the version, zero processes and unchanged file bytes), every
supported projection, unknown fields/kinds, malformed/torn/unterminated lines, original nested
results including mismatched status/reason and string codes, shell context,
image placeholders, chronology of titles, duplicate ids and cwd/agent rules.
Use the same fixtures through original parseRecord/recordActions and port
projection; unchanged original bytes remain the prefix after a port append.
Looking-only sessions write nothing. Verify once-only omission presentation
and that notice/local command events never reach the file.

Force slow append with completers: prompt/update/result order, enqueue during
write, mixed-path swaps, partial failure, once-warning/later-event retry,
throwing observers, close before admission and late mention/settings/update.
Remove the fixture directory immediately after completed close and prove
nothing recreates it. No post-barrier events or forgotten retiring processes.
Do not convert telemetry/cache sandbox errors into product failures.

For the replay fence, HISTORY/reply/LIVE in one byte read must equal split
reads. Include unrelated response ids; header-only/opaque-only/malformed-only
local files; local-record load suppressing replay; no-record load grouping
user chunks; resume early live updates. Specifically early resume mode A,
answer B, post mode C ends at C; without post it ends at A. Close/swap during
synchronous drain and between history publication and live subscribe must
stop remaining work without touching newer ownership. Final opening facts
beat historical settings; current live reports beat opening facts.

Replay fold must equal ordinary fold, publish once, freeze lists and preserve
occurrence identities. Measure accumulated entry copying so large replay is
linear at its writer boundary. Keep Conversation free of transcript state.
No selection/code-pick cache migrates to a new document with equal ids.

Use original fake through existing finder/harness, never a real model:
default load HISTORY, `--resume-only` with local record, resume-only without
local record, and neither operation advertised. In the latter case assert
the local offered-guard error and no load/resume RPC; an advertised load
refusal uses `CHORD_FAKE_REFUSE_LOAD`. Also cover `opened` and
text/thought/tools/shell/late/flood/slow/ignorescancel/crash. The fake has fixed
HISTORY rather than a real persistent agent history; distinguish that from verification of
local saved turns. Use port-owned scripted children/in-memory ACP for exact
reply partitions and hung requests, with no original changes.

Compiled PTY smoke uses isolated state and the native launcher: prompt/quit,
continue/id/picker routes, `/resume` replacement, no-start cancellation,
refusal, prompt after resume using the same ACP id, and cleanup of every owned
process group/PTY. Prove original writes -> port reads/appends -> original
reads, and port writes -> original resumes, comparing method, id, cwd,
transcript projection and exact bytes. Run normal root/port static and
appropriate test gates after implementation; compile tags explicitly.

Summary scans retain O(number of summaries + current line buffers), with
eight file streams, and read O(total scanned bytes); an enormous line still
costs its size. Keep existing cancellation_token inputs for scan/selected-
history preparation; CTUI-53's port-owned cooperative SDK worker explicitly
closes/joins owned IO before its cleanup ACK and joins worker exit before the
public operation Future settles. Normal cancellation must not kill the worker
before cleanup. Exit notification alone does not prove file closure. Keep
work bounded to current operations. Transfer JSON projections, never widgets;
release raw/action
copies after setup. Sorting is O(N log N). Picker can measure all items and
currently invalidates height caches on rebuild; do not claim O(visible rows)
total layout. Final transcript fold, first layout and steady drawing are
separate costs. Steady cell diff is O(terminal cells); IO causes no frame per
record line. Resize does not replay or rescan.

Retain AOT scale reports for thousands of records, large irrelevant update
lines, long history and stalled-disk flood: wall time, peak memory, heartbeat/
input delay, queued-byte high-water and measurable stream, pending-Future,
OS-handle, temporary-root and process cleanup counters. Measure cancellation
latency from request to operation-Future settlement. Main approved these
observable metrics without a new production or VM-service diagnostic seam;
physical isolate count and physical exit latency are explicitly unmeasured.
Future settlement does not prove physical isolate exit. All other scale and
responsiveness gates remain unchanged. Compare like runtimes. CTUI-1's accepted first-resume/resize
hitch is context, not a manufactured new pass threshold. A missed responsiveness
gate goes to the owner with measured options. Unbounded held/queued bytes and
filesystem flush latency remain documented original limits, with no invented
queue cap, deadline or durability guarantee.

## Packages tried and critic resolution

[framework evidence](evidence/CTUI-26/framework/README.md) retains sources,
locks and sanitized output: SDK append/UTF-8 stream/flush/close passed; uuid
4.6.0 generated 10,000 distinct canonical v4 values per environment; pure
stateHome from xdg_directories 1.1.0 built on macOS and matched original
xdg-basedir 5.1.0 except the approved no-HOME fallback. Only that surface is
claimed; package platform metadata is not whole-package macOS certification.

[CLI evidence](evidence/CTUI-26/cli-trial/README.md): args 2.7.0 AOT rejects
bare resume and accepts repeats last-wins. Main approved its bounded adapter.
[Time evidence](evidence/CTUI-26/time-trial/README.md): timeago 3.7.1 AOT
builds but differs in wording, unit thresholds/rounding and weeks; intl
0.20.3 has no relative-time formatter; intl4x 1.0.1's prior CTUI-23 native
build-hook failure under dart compile exe is reused, not claimed rerun.
Main approved the bounded English lastUsed port and checked-in Bun fixtures.
No package workaround or production dependency change was made in design.

All five critic findings were accepted:

1. **Reply fence could run too late:** synchronous method/session/id matching
   at Traffic ingress, pre/post partitions and explicit resume-early-live branch.
2. **Usable history was ambiguous:** rawHasPast is separate from supported
   projection; record presence drives method choice.
3. **Result representation differed:** explicit original JSON codec and
   independent historical status; raw string codes retained.
4. **Number/metadata wrapping differed:** framework number column retained;
   metadata stays one clipped line, measured after source-equivalent slicing.
5. **Replay ownership/failure was vague:** Session actions, Conversation batch
   event, StartConnection/AppState detached fold/publication; no partial history
   on failed ACP open; reentrant ownership checks through live drain.

The critic confirmed these resolutions close the blockers. No critic finding
was rejected. Draft caller-numbered rows and await-only fence interpretations
are superseded by this file. No owner question remains open; implementation
and combined-state/parity/performance proof remain ship's gates.

## Handed validation record

The [CTUI-26/53 validation summary](evidence/CTUI-26/validation/README.md)
links reviewed source/fixture screen looks, scoped compiled 80x24/interchange
results and CTUI-53's canonical own-handle proof plus full three-JIT/three-AOT
cleanup reruns. It retains pre-fix positive descriptor failures and explicitly
uncertified historical zero-prefix observations. Physical numerical metrics,
canned fake history, failed-start command deferral and measured picker/
transcript hitches remain scoped limits, with no universal performance pass.
This is evidence for the handed units, not final exact-head branch readiness;
writer changes and the final suite/static gate remain separate.
