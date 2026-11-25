# CTUI-53: cancellation joins record IO cleanup

Contract for the last unit of the CTUI-26 branch/slice, designed and approved
before implementation. The handed validation record is below. There is no
screen change.

## Cause, scope and unchanged behavior

The signed [package manifest](../../example/chord/test/fixtures/records/ctui53_packages/manifest.json)
at 32aad5979acdbee191730b00bf4cf0d799437944 retains source, lock and JIT/AOT
results. cancellation_token 2.0.1 settles its public cancellation Future
before body cleanup; the probe retains a REG file even after observed worker
exit notification. worker_manager 7.2.9 gentle cancellation also settles
before cleanup ACK. Its descriptor closes only after the processing gate
releases and explicit cleanup runs. Neither public API supplies this barrier.
Other candidates were source-inspected only, as the manifest states. Main's
conditional approval of a port-only cooperative SDK worker is now effective.

Replace only the scan/selected-history CancellableIsolate.run jobs with an
owned SDK-isolate operation in example/chord/lib/session/. Keep the existing
CancellationToken input and these signatures:

```dart
Future<List<SessionRecord>> readRecords(
  String stateDir, {CancellationToken? cancellationToken});
Future<PreparedHistory> readRecordedHistory(
  String? path, {CancellationToken? cancellationToken});
```

Keep scanRecords' injected line-stream seam, recordsOnce failure identity,
JSON-shaped native projections/error envelopes (no extra JSON-string round
trip), all numeric num values, eight simultaneous file streams per scan,
enumeration-order summaries and all CTUI-26 store/projection behavior.
Missing records directory returns []; individual unreadable/disappeared scan
files are skipped; other directory errors propagate. Selected missing file
returns PreparedHistory.empty; null path retains its immediate empty/no-worker
behavior. Unsupported versions still fail before any agent starts. Selected
UTF-8 replacement, final-line parsing, rawHasPast, omission and action/recall
semantics stay unchanged. CPU parse/projection remains off the UI isolate.
No agent, recording, prompt/admission, framework, widget, dependency, public
scheduler, deadline or queue-cap change belongs here.

## Private operation protocol

One operation owns one worker, identity, worker control port, parent event
port and completion. Concurrent operations share none of that state. Give
the same dedicated parent event port to the worker and Isolate.spawn's
onError/onExit parameters, with errorsAreFatal true; register them and
main-side token observation before worker execution.
An already-cancelled nonempty IO request spawns nothing and throws the
original main-side token.exception object. Do not wrap the returned Future
in a package cancellable wrapper that settles before this protocol finishes.

| Message/state | Contract |
| --- | --- |
| Ready(id, control port) | Worker installs control input before any IO, then waits. Only control ports cross outside JSON-shaped data. |
| Run(id, kind, path) | Parent admits scan or selected preparation only if not cancelled. A cancellation latched before Ready/Run sends Cancel instead and opens no IO. |
| Cancel(id) | Idempotent stop request. Latch it, stop discovery/new file admission, discard partial output and enter owned cleanup. |
| Closed(id, outcome) | Tagged terminal JSON map, transferred only by final Isolate.exit(eventPort, envelope) after every owned close/cancel and IO task joins successfully. It is the cleanup ACK, for success, caught job error or cancellation. Never use ordinary send for Closed. |
| CleanupFailed(id, cause) | Tagged terminal JSON map transferred by final Isolate.exit after attempting every owned close/join. It records failure, not a Closed ACK. |
| SDK error list | The same port receives the SDK's two-element error/stack list, distinct from tagged protocol maps. Retain its details until exit; it is never a cleanup ACK. |
| null | Reserved for the same-port SDK exit notification. With prior Closed, join exit and consider publication. With prior CleanupFailed, reject that cleanup failure. Without a prior valid terminal map, reject the fixed missing-ACK failure immediately. Exit alone is not IO cleanup proof. |

Await all owned IO and control cleanup before the sole final Isolate.exit
call; exit itself does not execute pending finally blocks. Ready/Closed/
CleanupFailed maps carry the operation id. SDK error lists and null cannot be
mistaken for those maps. Keep the parent event port open after a terminal map,
latch its outcome and wait for null on that same port. Never infer a missing
ACK from an exit event on a separate port. No timeout, polling, grace period
or later callback is needed to distinguish absence: on this one-port transport,
null without a prior valid terminal map means termination without that map.

This is the installed Dart 3.13.5 SDK lib/isolate/isolate.dart pattern:
Isolate.run at lines 253–315 gives one RawReceivePort to final results,
onError and onExit, treating null as termination without a result;
_RemoteRunner at lines 1242/1244 returns through Isolate.exit. The official
[Isolate.run implementation](https://api.dart.dev/dart-isolate/Isolate/run.html),
[final exit message contract](https://api.dart.dev/dart-isolate/Isolate/exit.html)
and [exit-listener contract](https://api.dart.dev/dart-isolate/Isolate/addOnExitListener.html)
support this source-backed final-envelope-before-null ordering. It does not
assert ordering between arbitrary ports or measure physical exit latency.

Parent validates identity and settles once only after the terminal/exit rule
above. Close ports, detach token observation and release worker references
once. Ignore duplicate terminal/late messages, including artificial messages
after null/settlement; never redirect them into a newer operation. A spawn
failure that creates no worker closes local ports and preserves that failure,
unless cancellation already won publication.

## IO ownership, CPU work and publication races

The worker owns the Directory.list iterator/subscription and every file
stream, including selected-history reading. Replace its unowned readAsString
Future with an explicitly owned cancellable read while preserving decoding
and projection. Up to eight scan file streams are admitted at once. EOF,
individual-file skip, domain error and cancellation all go through the same
scope. Await cancellation/closure of every active directory/file subscription
and completion of every IO task; do not abandon tasks or wait on an onDone
callback that cancellation suppresses. A close failure cannot prevent the
remaining close attempts. No normal cancellation uses Isolate.kill, exits
before finally or has a forced timeout. An outstanding OS operation may delay
cancellation; do not promise a hard latency bound.

Check cancellation before admission, after awaited IO, before/after parsing
and before sending a result. Yield to the worker event queue between bounded
batches of lines/projection work so control messages are serviced. An individual
synchronous decode cannot be preempted; check again afterward and publish no
partial data. This adds no public scheduling knob or responsiveness threshold.

Parent publication is synchronous and once-only. Cancellation observed before
that point wins over an unpublished success or caught job error, even if the
worker already sent Closed; cleanup/exit must still be joined. Preserve the
exact original main-side token.exception object/custom reason, not a serialized
copy or default CancelledException. Cancellation after public completion leaves
that result completed. Cancelling while startup is pending must join the
handshake/worker cleanup; cancellation after Run may stop already-admitted IO
but must not admit another file. Selected-history cancellation never starts
an agent or publishes a partially prepared transcript.

Caught domain errors use JSON envelopes: reconstruct FileSystemException with
its category, message, path and OSError fields; reconstruct
UnsupportedRecordVersion with its exact JSON version value and current
wording. No numeric coercion. Other caught job errors become
StateError('Record worker failed: <error>') with remote stack information.
Cleanup/protocol failure outranks cancellation, which outranks an unpublished
caught job error/success. Explicit cleanup failure becomes
StateError('Record worker IO cleanup failed: <cause>'). An unexpected worker
exit without Closed becomes
StateError('Record worker exited without acknowledging IO cleanup.'). Join
exit, preserve available error/stack details, and never label either abnormal
path ordinary cancellation or cleanup success. No fabricated ACK, retry or
kill fallback is allowed. IO cleanup is not certified on these abnormal paths;
retain/report that failure rather than inferring it from exit.

Existing session/Conversation preparation and close/swap barriers await the
public operation Future. Cancellation now makes that await sufficient for
normal owned-IO cleanup plus joined exit. Widget/session generation guards
still reject stale outcomes; they do not replace worker cleanup. Do not
change prompt admission, file append ordering, successful replay publication
or the lifetime of unrelated operations.

## Required proof and handoff

Use deterministic test-owned gates/markers around directory enumeration,
eight active files, selected read and projection; no sleep or polling until
zero. Keep instrumentation private/test-owned, not a production/VM-service
API. Verify no IO/spawn for pre-cancel, cancel-before-ready/run, in-flight IO,
large irrelevant lines, CPU projection, result/cancel ordering, late/duplicate
ACK/error/exit, concurrent independence, normal success and caught errors.
A missing ACK or failed close must produce the explicit cleanup failure above,
not a cancelled/successful result. Deterministically test same-port terminal
then null, null without terminal, SDK error list then null, CleanupFailed then
null and duplicate/late messages. Do not model arbitrary cross-port delivery
as the normal transport or add a timer to decide absence. No test may credit
exit alone as file closure.

Run public-operation own-process descriptor proof in JIT and compiled AOT:
observe owned directory/file IO active before cancellation; immediately after
the Future settles assert zero owned REG/DIR descriptors, zero pending tasks/
streams, Closed observed and SDK exit joined. Check success, cancellation and
caught-error paths. Delete the owned root immediately and prove no recreation;
remove outer state/binaries and verify no owned process remains. A watchdog
only bounds a hung test; elapsed waiting cannot establish cleanup. Retain
failure/fix logs, exact commit, sources/locks, named descriptor observations
and the affected full JIT/AOT scale reruns, including immediate after-cancel
and end snapshots. Normal empty/small controls do not replace the failed
2000-record workload.

Preserve the [pre-fix scale summary](evidence/CTUI-26/scale-baseline/README.md)
and raw failures (JIT end 0/1/7; AOT 8/0/0). Final readiness requires CTUI-53
review/test acceptance and affected scale proof; historical unresolved-handle
acceptance is superseded. Physical isolate count/physical exit latency remain
unmeasured numerical metrics: observing this operation's SDK exit notification
is a join condition, not a physical timing measurement. Report request to
public-Future settlement honestly. Keep picker/transcript hitch figures and
main's separate framework follow-up; no performance-pass claim follows from
this cleanup fix. No screen/public-framework API gate is added.

## Handed validation record

The [validation summary](evidence/CTUI-26/validation/README.md) links the real
public-operation JIT/AOT own-descriptor proof retained at 9a36a022 and the
full affected three-JIT/three-AOT results at b6099d0 from source a7a8205.
Reviewer and independent tester accepted those scoped cleanup/correctness
gates. Positive DIR/eight-file/selected controls precede immediate zero-FD
snapshots after public settlement; the six full runs have ten named zero
snapshots each with canonical roots. Invalid path controls, setup guards,
pre-fix named failures and uncertain historical zeros remain visible.
This satisfies the handed CTUI-53 cleanup/affected-scale evidence gate,
not a universal performance or final exact-head readiness claim. Physical
numerical metrics and measured/deferred picker/transcript hitches stay as
specified above; no screen/public-framework API change was added.
