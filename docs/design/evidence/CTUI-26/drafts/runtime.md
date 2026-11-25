# CTUI-26 runtime proposal

Design only. The owner has settled per-process ordering without an
interprocess lock, and append preservation with partial supported replay.
No runtime code is changed by this draft. Source observations use original
commit `577b58167672e12c999aeaf4eed2a1a988513dc2`.

## Ownership and module layout

Everything belongs in the port. No record, filesystem, process or chord
policy API is added to the framework or Terminal.

| Port source under `example/chord/` | Responsibility | Mirrored test |
| --- | --- | --- |
| `lib/session/state_dir.dart` | Approved XDG package boundary; injected environment in tests | `test/session/state_dir_test.dart` |
| `lib/session/record.dart` | Raw JSONL views, event codec, supported replay projection, FileRecording and injected append sink | `test/session/record_test.dart` |
| `lib/session/replay.dart` | ACP load replay to historical actions, shell context and image placeholders | `test/session/replay_test.dart` |
| `lib/session/sessions.dart` | Streaming summaries, list/find/continue selection, once-per-start scan | `test/session/sessions_test.dart` |
| `lib/session/inbox.dart` | Explicit opening phase, pre-answer replay drain, authoritative answer then live updates | `test/session/inbox_test.dart` |
| `lib/session/session.dart` | New/load/resume choice, record/history metadata, transmitted-prompt callback, cleanup | Existing session tests plus reopen cases |
| `lib/session/conversation.dart` | Recording ownership, replay-before-connected, generation-safe resume swap and close flush | Existing conversation tests plus resume cases |
| `lib/session/enrich.dart` | Recall already-enriched record updates into Wire without enriching again | `test/session/enrich_test.dart` |
| `lib/session/transcript/entries.dart`, `reducer.dart` | Package-internal synchronous historical fold with one frozen publication | Existing transcript tests plus replay identity/scale cases |
| `lib/session/start_connection.dart`, `launch_connection.dart` | Inject selected Resume and record factory, own closes on quit/crash/signal | Mirrored connection tests |

The current port has no Recording, no load/resume Agent members, no history
batch and no replay drain in SessionInbox. These are implementation units,
not claims about existing functionality. Existing clear already has the
replacement generation barrier and retiring-process ownership to extend.

## Record and interchange contract

Original authorities: `../chord/src/session/record.ts`, `sessions.ts`,
`state_dir.ts`, `replay.ts`, `session.ts` and `conversation.ts`.

- State is the approved XDG state location, then `chord/records`. Relative
  XDG overrides remain relative as the original accepts them. Use
  `xdg_directories` 1.1.0 and existing `path`; require nonempty HOME or
  XDG_STATE_HOME, otherwise a clear error. This approved limitation differs
  from the original account-home fallback. Framework draft owns the trial.
- New basenames are independent UUID v4 values from `uuid` 4.6.0, ending
  `.jsonl`; the basename is not the agent session id. A resumed known record
  appends to its selected existing path. Never derive a path from an ACP id.
- The first line is compact JSON with `type` first:
  `{"type":"session","version":1,"sessionId":"...","agent":"...","cwd":"...","at":0}`.
  Session identity is the agent's id. Epoch milliseconds are chord clock
  values; numeric fields received from agents retain their numeric values.
- All generated lines are compact UTF-8 JSON followed by newline. Keep
  `type` as the first property: the original summary reader uses exact
  `{"type":"prompt"` and related prefixes to avoid parsing every update.
- Record raw maps are separate from sealed TranscriptAction classes. Keep
  unknown keys and nested `_meta` in raw record/update views. A display
  projection may read only supported fields. Never deserialize and rewrite
  an existing file to append; its exact existing bytes remain the prefix.
- Valid JSON lines without a final newline are read, as in parseRecord.
  Empty lines and syntactically malformed lines are skipped independently;
  a malformed supported shape must not prevent later well-formed entries
  from replaying. Unsupported header versions are not claimed compatible.
- No tail repair: if a crash leaves an incomplete final line, the first
  append can merge with it and also become unreadable. Preserve that
  original limitation. Neither truncate nor insert a separator silently;
  crash loss is not bounded to one line. Verify exact prefix preservation
  and resumed parse behavior in this case.
- Main-session interchange means original can list and replay port-generated
  prompted v1 records and port can continue supported original main history.
  It does not mean all modern original transcript features are drawn.

### Exact supported versus opaque projection

The writer generates `session`, `opened`, `state`, `prompt`, `update`,
`cancel`, `disconnected` and `result` for the implemented main-session
runtime. It preserves enriched ACP update maps whole, including unknown
updates; it does not serialize render objects, occurrence identities,
selection, draft, queued-unsent prompts, frame counters or permission RPCs.

| Record kind | Replay treatment |
| --- | --- |
| `session` | Identity and summary metadata; no transcript row |
| `opened` | End previous unfinished historical turn, then disconnected boundary; no waiting runtime survives |
| `state` | Metadata only; never send historical settings to the agent; current opening answer is authoritative |
| `prompt` | Supported when no sender/steering semantics (`from`/`into`); split existing shell context, restore image placeholders and literal mentions; links/resources are metadata, never reread files |
| `update` | Main-session allowlist below; retain raw fields, pass through existing reducer; never replay subagent-targeted updates as main |
| `cancel` | CancelAction with historical time; later explicit result wins normally |
| `disconnected` | DisconnectedAction with recorded time |
| `result` | Completed/cancelled status and exact stopReason; failed message and optional code; preserve opaque extras on disk |
| `renamed` | Read title for discovery/header only; no title setter or pending rename dispatch in this slice |
| `usage` | Opaque turn-cost history; no cost accounting added |
| `served`, `ran`, `closed`, `asked`, `answered`, `plan_asked`, `plan_answered`, `stopping`, `self_started`, `forked` | Opaque later-feature history; skip and flag omitted history |
| Unknown kind | Opaque; skip and flag omitted history |

Supported main update kinds: `agent_message_chunk`, `agent_thought_chunk`,
`tool_call`, `tool_call_update`, `plan`, `usage_update`,
`current_mode_update`. Feed `config_option_update` and
`available_commands_update` through the appropriate historical state/metadata
projection without claiming a transcript row. Read `session_info_update`
title/null semantics for discovery, without adding account/status features.
`user_message_chunk` is ignored in recorded history because the prompt line
is authoritative; in ACP load replay its contiguous main-session chunks
form the prompt instead. Every other update kind is opaque and flags the
notice. Existing reducer handling of unknown kinds remains unchanged.

Any `subagentId`, `subagent_update`, later-feature prompt with `from` or
`into`, and a header with parent/task/team ownership flag the omitted-history
notice. A prompt needing unsupported sender/steering semantics is skipped
as a unit; do not mislabel it as the person's prompt. Do not follow child
record references, start child runtimes, reconstruct teams or restart
monitors. A main tool call still draws its supported ordinary tool fields;
chord-specific served/team semantics are opaque. Extra unknown map keys
alone do not cause a warning. Omitted cost/token/sign-in detail on a result
also sets the notice; historical sign-in/account data is never promoted to
live account state. For failed codes, preserve original string on disk and
adapt only a valid numeric code to current TurnFailed's integer field;
message remains visible for nonnumeric codes.

If any meaningful part was omitted, append exactly one window-only plain
note after history: `Some saved history is not shown in this version.`
Do not write that note back to the record or send it as a prompt. The
original's `leftOpenLine` (`ui/agents/agents.ts`) describes named children
not reopened, and `leftRunningLine` (`session/monitors.ts`) names monitors
not restarted. Neither correctly describes arbitrary omitted history;
using either would require later-feature reconstruction. The owner's
approved plain-line fallback therefore fits. Metadata-only lines and
empty files do not cause it. A skipped malformed nonempty line also sets
this single note; do not add one warning per bad line.

Replay ids are prefixed `history-` as the original, separate from new turn
ids. At a subsequent prompt, opened boundary or EOF, an unfinished prior
prompt receives the original synthetic completed/end_turn result. This
settles the display; it is not a claim the agent completed the work. Never
recreate a pending permission dialog, timer or request from history.

## Ordered writes and failure lifecycle

Introduce a small port Recording interface matching original ownership:
`opened(session)`, `sent(actualPrompt)`, `heard(event)` and `flushed()`.
The production FileRecording takes an injected clock, UUID factory,
state directory, async append operation and once-only warning callback.
No widget is needed for testing. Record calls are synchronous enqueue
operations; UI and prompt progression never await filesystem latency.

On opening, hold header (new record only), converted ACP history if no
record existed, opened time and current state. Known record opens hold
only opened/state. Keep subsequent updates held until a prompt is actually
submitted. First submission releases held lines before its prompt line;
looking at a session and leaving writes no bytes and does not change its
last-use time. On clear/resume before prompting, discard that opening's
held lines. Do not bring newer original rename/receipt exceptions forward.

Capture the transmitted prompt, not Conversation's UI PromptAction:
`next.text` is the drawn text, whereas `next.prompt` includes shell context
and Session resolves mention links asynchronously. Add a per-call
onSubmitted callback carrying finalized content, links, images count,
conversation turnId and timestamp at ACP outbound admission, before an
agent update can arrive. Pass the conversation turnId explicitly; Session's
internal Turn id is different. Cancellation during mention resolution or a
reentrant close before admission writes no prompt/result. Existing generic
outbound traffic admission may support this hook, but a response awaited
until the turn ends is too late. Persist embedded resource metadata only,
never image/audio payloads or reread file contents. Snapshot encoded lines
at admission so later mutable ACP maps cannot change queued history.

Hear enriched semantic updates before window listeners. Record state
changes only when model/mode/options differ. No duplicate state lines for
no-op reports. Permission requests/answers remain transport interactions;
ordinary tool update history may draw their historical outcomes, but no
permission RPC or live wait is reconstructed. Shell output is retained
only in the prompt context actually submitted; unsubmitted shell work is
not retroactively added to the record.

A single drain owns an ordered queue of `(path, encodedLine)`. It takes a
batch, groups by path preserving each path's order, appends, and loops until
empty. Enqueues during a write join the next batch. Carry the path in every
queued item so a swap cannot redirect old data. Serialize all writers in
this process that share a path; do not create a second live Conversation
for the current same agent/session id. No lock file, PID lease, timeout
steal or interprocess claim. Two original/port processes writing one record
have the same possible interleaving and inconsistent view as the original.

`flushed()` joins writes already enqueued, including arrivals during the
active drain. It does not persist unprompted held lines and is not fsync or
power-loss durability. File append completion is the promised boundary.
A write/mkdir failure discards the failed taken batch and pending queue,
reports `Could not keep this session's record: <message>` once, and lets the
agent continue. A later event tries writing again as the original does;
do not permanently disable the writer or resend uncertain failed batches.
Partial append then error may have written a prefix: no automatic retry or
transactional guarantee is claimed. Ensure a throwing warning listener
cannot leave the drain flag stuck.

Close sets its barrier before listeners/cancellation, stops admission,
aborts settle waits and opening/replay work, closes all current/retiring
agent processes through the existing bounded process-group ladder, then
joins previously admitted record writes. A result or usage arriving after
the close barrier never enters the record after that final flush. There
is no disk I/O timeout in original FileRecording; the process-stop bound
must not be described as a bound on all shutdown I/O. Filesystem operations
can hang. Adding a flush deadline would change the original and remains
an owner question, not an invented timer in this design.

## ACP opening, replay fence and session replacement

Add Agent.loadSession and Agent.resumeSession using existing ask/cancellation
machinery and typed map views. These answers do not contain a new sessionId;
seed state from their model/mode/options, retain the requested id. Do not
route them through NewSessionResponse.sessionId. Request uses selected cwd,
requested sessionId and the same current MCP-server policy as new sessions.
No new capability is declared merely because loading is implemented.

| Local usable record past | Advertises resume | Advertises load | Request/history |
| --- | --- | --- | --- |
| yes | yes | either | resume; local past |
| yes | no | either | load; local past, discard load replay |
| no | yes | yes | load; agent replay |
| no | yes | no | resume; no invented history |
| no | no | either | load; agent replay if it succeeds |

The last case preserves original behavior even if load was not advertised:
ask load and surface its error. No fallback to session/new, no automatic
second request after refusal, and no assumption a matching local record
means the agent still possesses the session. Failure closes the new process
and reports `it cannot resume session <id>: <agent error>`.

Explicitly separate pre-answer notification history from subsequent live
notifications. Current SessionInbox.open cannot be used unchanged:

1. Read selected local record and compute supported past in cancellable work.
   Recall its supported main updates into the enricher Wire before reopen.
   Recall folds already-enriched updates as heardFromAgent does; do not run
   the enricher chain, especially rawOutputContent, again. Original's
   guardianReview transformation belongs to replay projection only; reuse
   existing approved metadata interpretation rather than inventing a new one.
2. Buffer pre-answer notifications in wire order. For load, drain this
   phase on answer and turn it into replay only if no usable local record;
   otherwise discard it. For resume, those early updates are live and must
   remain queued, since resume replays nothing. Filter by requested id.
3. Fence at answer handling before the next notification can be routed.
   Seed authoritative opening state, retaining live post-answer updates
   separately. Do not refold discarded load replay over current state.
4. Fold historical actions to one detached transcript, prepend resumed
   header metadata, and publish that batch once. Replay bypasses Recording.
   Then call Recording.opened, attach live subscriptions (which drain held
   live updates in order), and emit Connected only if generation is current.
   A historical plan remains historical until the live state/updates replace
   it; historical settings never issue setters.
5. A close or swap at any boundary cancels the attempt; discard its prepared
   transcript and stop its process. No partial replay reaches the new window.

There is no `inBatch` in current entries.dart. Add only a package-internal
synchronous replay fold, not a framework export or general transaction
system. Its private mutable accumulator is owned solely during historical
folding; append/replace preserve fresh occurrence identity on append and
existing identity on replacement. Freeze a fresh unmodifiable list and
publish after the fold. Intermediate mutable lists cannot escape to UI,
selection sources or normal live reducers. Implementation must include a
linear-time accumulated-entry gate; merely calling existing copy-on-write
reduceTranscript for every entry then publishing once is still quadratic.
Keep source occurrence identities independent of persisted turn/tool ids.

Resume selection first validates agent/directory scope. Same current id is
not reopened. An elsewhere choice produces the original command refusal
without starting anything. A valid replacement uses existing clear-style
barrier before any await: increment generation, detach current references,
abort outstanding settings/mentions/list/replay work, withdraw queued input
through existing behavior, retire old process and record path, emit cleared,
then start replacement. Old close runs beside opening; a late result,
settings answer, permission or update cannot touch replacement state or file.
Reopen failure does not silently restore the old runtime or start a fresh
session. Current-port late callbacks are discarded, with no later-feature
retired-cost plumbing introduced. Close joins every retired process and
admitted write even when the replacement failed.

## Discovery, scale and scheduling

Use async SDK byte streams, UTF-8 decoding and line splitting. Summary scans
keep at most eight files open as the original; extract header, first/last
prompt, latest title and last opening without retaining update bodies.
Skip unreadable/disappearing individual files; missing records directory
means empty list. Directory-level errors other than missing propagate.
A once-per-start future prevents duplicate scans during startup. A reopened
picker gets a fresh scan; a stale result must not replace a newer generation
or revive a closed picker. No watcher, permanent index or retry loop.

Last-used ordering is last prompt time for prompted sessions, not mtime or
last opened time. Continue filters agent, exact cwd and no parent. Listing
and id lookup use original latest-record/deduplication rules; unknown ids
are handed to the selected agent without an invented local record. Header
parent/task/team metadata is preserved even when later features are opaque.
Follow interface draft for catalog and directory refusal wording.

Async disk I/O alone does not protect frames from a huge JSON line or a
large replay fold. Do summary parsing and history projection in one owned
cancellable isolate using the already accepted cancellation_token adapter;
transfer serializable record projections, never widget objects. Keep the
number of active workers bounded (one active history preparation; eight
file reads inside a scan); a replacement cancels rather than accumulating
workers. Final transcript install is atomic and generation checked. If the
final main-isolate fold still exceeds the accepted first-resume/resize
budget, retain measurements and hand that specific gate to the owner;
do not introduce a general persistent-store subsystem.

A thousand updates between two frames remain a thousand ordered record
entries; frame coalescing only affects painting. Normal writing adds memory
proportional to queued/held encoded events, not an extra retained lifetime
transcript. Original queues and preprompt holds are unbounded when disk
stalls or an agent floods. Report queue bytes/high-water and input latency
in evidence; no silent dropping, disk backpressure imposed on ACP, or new
queue cap is authorized. Resume must avoid whole-file string plus duplicated
raw/actions/transcript copies, release parsed past after setup, and never
scan entire child histories. Resize schedules layout only; it neither
rescans records nor replays history. No terminal protocol is needed.

## Tests and acceptance gates

Pure and injected-I/O tests never need a model, real agent or terminal.
Every new source above has a mirrored test. All production claims below
are future ship gates, not tests run during this design.

- Codec/oracle: same compact fixture through original parseRecord,
  recordActions and port projection. Cover main text/thought/tool/plan,
  shell context, image placeholders, titles, missing result, multiple
  opened boundaries, cancelled/failed codes, unknown keys/kinds and
  malformed/truncated lines. Opaque bytes remain exact after append; zero
  or many omissions produce respectively zero or one window-only note.
- Writer barriers: injected append completers force prompt/update/result,
  enqueue-during-write, mixed-path clear/resume, reentrant close, delayed
  mention resolution and concurrent per-path writers. Assert exact bytes
  and order; looking only creates nothing. Verify warning once, later-event
  retry, mkdir failure, partial append failure and tail-merge behavior.
- Replay fence over in-memory ACP: one read containing history, answer,
  live update equals split reads. Record wins without duplicate live rows;
  no-record load creates history-1/history-2 turns. Resume-only early
  commands/live chunks survive. Another session's updates are dropped.
  Authoritative answer plus post-answer settings beats historical settings.
- Generation/cancellation: list, selected-file read, history preparation,
  initialize, load and resume each cancelled by swap or close. Old prompt
  resolve/settings/permission/update cannot appear or write in replacement.
  Final flush precedes completion and admits no post-close result/usage.
  Remove fixture directory immediately after close; no late mkdir/write
  should recreate it. Retirement errors do not poison a new session.
- Batching identity: equal visible output to ordinary fold; unique occurrence
  identity even with reused tool ids, stable identity on replacement,
  frozen result, no intermediate publication, long replay linear accumulated
  entry copying, and fresh session selection/source ownership after swap.
- Original fake via existing fake_harness, tagged fake_agent: ordinary load
  HISTORY (two prompts/tool), --resume-only with local record chooses
  resume, --resume-only --no-load without local record resumes with no
  fabricated past, default load-only with local record suppresses HISTORY,
  CHORD_FAKE_REFUSE_LOAD closes/refuses without new fallback. Use `opened`
  scenario/traffic to assert method/id/cwd. `text`, `thought`, `tools`,
  `shell`, `late`, `flood`, `slow`, `ignorescancel` and `crash` exercise
  recorded turns and shutdown. The fake does not persist actual history:
  distinguish local record verification from agent HISTORY replay.
- No original edits. Existing fake lacks precise hung-load and controlled
  reply-boundary scenarios; use port-owned scripted children/in-memory ACP
  for these. Add a port-owned fake scenario only if the existing harness
  cannot express the case; never call a real agent.
- testWidgets window at 120x40 and 80x24: resumed header precedes history,
  idle prompt after replay, one omission note, plain/light themes, picker
  cancellation, active-session exclusion, failed reopen and cross-directory
  refusal. Resize during list/load/replay does not restart work. Interface
  draft owns original-vs-port captures and narrow-edge cases.
- Compiled executable with isolated state env: send first prompt, quit,
  re-launch --continue and --resume, /resume swap, no-id picker cancel
  starts no process, fake refuses, then verify exact record bytes and
  all owned process groups gone. Compile-tag PTY harness only, no real
  terminal. User data is never discovered or written by tests.
- Performance evidence: thousands of synthetic record summaries with large
  irrelevant update lines, selected long history, flood against stalled
  append. Report wall time, maximum input/heartbeat delay, queue high-water,
  peak memory, cancellation latency and retained workers/handles. Compare
  JIT with JIT and AOT with AOT. No invented numerical pass or unlimited
  shutdown guarantee.

## Package and experiment status

No new JSONL, mutex or database package: JSON conversion and asynchronous
file/stream operations are SDK facilities, and path is already pinned.
Framework's retained draft records uuid 4.6.0 and xdg_directories 1.1.0 AOT
trials and the approved XDG boundary. This draft does not propose a custom
UUID generator or home lookup workaround.

An isolated SDK-only native probe executed 1,000 serial UTF-8 JSONL appends,
streamed decoding and verified an opaque prefix byte-for-byte: PASS. This
shows SDK AOT support only, not production writer/replay correctness. The
compiler produced the binary but its CLI returned failure while updating
sandbox-restricted telemetry metadata; the generated executable ran and
passed. No package mismatch is inferred from that environment error.

## Remaining owner questions

No unresolved schema/lock/opaque-history choice blocks this proposal; those
are settled above. One explicit runtime limit remains: original record
flush has no filesystem deadline and its queued/held data is unbounded.
Matching it is the current contract. A bounded disk-failure/forced-exit
policy or queue budget would require a separate owner decision with its
visible loss/backpressure behavior before implementation changes it.
