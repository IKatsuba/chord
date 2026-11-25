# CTUI-26 pre-fix scale evidence

Baseline evidence commit: `8f5725fd4fbd10eb0cd5547fb3d96fe26cda67e2`.
The developer-owned [manifest](../../../../../example/chord/test/fixtures/records/scale/manifest.json)
records base source `2b550b7fd9299b30c9f843967aaf4d82972db441`, workload,
commands, instrumentation variants and cleanup scope. These links point to
preserved raw fixtures; this summary does not duplicate or modify them.
Designer inspected the signed manifest and all twelve result JSONs without
running a benchmark or inspecting unhanded implementation.

This is pre-fix evidence, not an all-gates-pass or performance-pass report.
CTUI-53 cancellation cleanup is mandatory before final readiness. Earlier
acceptance of unresolved handles is superseded; the diagnostic observations
remain historical evidence. CTUI-53's package approach is not settled by this
summary, and no framework change is introduced here.

## Retained cleanup failures and diagnostic

| Full repetition | JIT end descriptors | AOT end descriptors |
| --- | ---: | ---: |
| 1 | [0](../../../../../example/chord/test/fixtures/records/scale/jit-1.json) | [8](../../../../../example/chord/test/fixtures/records/scale/aot-1.json) |
| 2 | [1](../../../../../example/chord/test/fixtures/records/scale/jit-2.json) | [0](../../../../../example/chord/test/fixtures/records/scale/aot-2.json) |
| 3 | [7](../../../../../example/chord/test/fixtures/records/scale/jit-3.json) | [0](../../../../../example/chord/test/fixtures/records/scale/aot-3.json) |

The initial JIT repetition 2 recorded one retained end descriptor without its
name. The bounded [JIT diagnostic](../../../../../example/chord/test/fixtures/records/scale/jit-diagnostic.json)
then saw a DIR descriptor for the owned records directory immediately after
scan cancellation, followed by zero at later snapshots. It did not identify
or reproduce the earlier unnamed end observation. It is not proof of a fix.

Later JIT repetition 3 and AOT repetition 1 retained named REG record-file
descriptors from afterCancelScan through deletion of the owned root. Their
raw snapshots preserve names and descriptor numbers. Thus AOT recurrence was
observed and retained, not merely a possible future concern. A removed root,
zero pending operation Futures and zero retained instrumented scanner streams
do not establish zero OS descriptors or worker exit. CTUI-53 must release
files and end the worker before the cancelled operation Future completes,
with JIT/AOT verification and affected scale reruns. No CTUI-53 pass is claimed.

Counts-only results and runs with external named lsof snapshots are labelled
separately in the manifest. Adding those snapshots changes instrumentation;
do not combine them into an unqualified performance comparison.

## Runtime, workload and measurement limits

Default runs freshly created 2000 records, totalling 139890199 scanned bytes,
with 64 KiB irrelevant content per record and an additional 8 MiB line. The
selected history has 4000 turns, 12000 actions and 8000 entries. Fifty steady
frames are unpaced back-to-back draws/cell diffs. Filesystem caches were warm
after fixture creation. Small controls remain separate:
[JIT](../../../../../example/chord/test/fixtures/records/scale/jit-small.json),
[AOT](../../../../../example/chord/test/fixtures/records/scale/aot-small.json)
and [named AOT diagnostic](../../../../../example/chord/test/fixtures/records/scale/aot-small-diagnostic.json).

Physical isolate count and physical exit latency are explicitly unmeasured.
Cancellation timing is request to operation-Future settlement only. Direct
OS-descriptor observations, pending-Future counters and instrumented scanner
stream counters are distinct measurements. Future settlement does not prove
physical exit; zero samples means null, not measured zero latency. Peak RSS
is cumulative within each process. The separately labelled original Bun
reference measures different runtime/features and has no synthetic Actions
input; no cross-runtime speed ratio is claimed.

The stalled append is an injected IO gate, not a filesystem flush/durability
measurement. Queued-byte high-water excludes active append and held opening.
The raw reports retain wall time, RSS, heartbeat/input samples, replay copying,
queue/drain figures and cleanup snapshots. No new cap, deadline, durability
guarantee or O(visible rows) total-layout claim follows from these results.

## Picker and transcript hitches remain separate

The [2000-choice actual picker run](../../../../../example/chord/test/fixtures/records/scale/aot-picker-2000.json)
measured first layout at 64.880 ms, resize to 80x24 at 34.520 ms, resize back
to 120x40 at 33.016 ms, and navigation redraws at 25.177–25.809 ms. The raw
scheduled-to-acceptance and dispatch components remain intact. The
[20-choice control](../../../../../example/chord/test/fixtures/records/scale/aot-picker-small.json)
is retained separately. These picker-host runs use in-memory summaries;
they do not measure scan, disk, agent, reopen or PTY/display latency.

The full AOT transcript runs separately measured first layout at
136.196–142.905 ms and resizes at 126.631–130.018 ms. Full JIT transcript
first layout was 386.498–394.813 ms and resizes 146.918–184.165 ms. These are
stage wall times, not substitutes for the separately retained heartbeat/input
samples or the picker navigation measurement. No fast unchanged steady frame
cancels out a first-layout, resize or navigation hitch.

Main chose performance A: defer the measured 2000-choice redraw/navigation
hitch to a separate framework task, retain all picker/transcript figures,
and make no performance-pass claim or framework/cache change here. This
performance disposition does not waive mandatory CTUI-53 cleanup or other
validation gates.

## Cleanup scope and evidence ownership

The developer reports every actual fixture root deleted, each benchmark
process exited, scratch binaries and outer TMPDIR/XDG removed, and no owned
process remaining. That is end-of-run process/root cleanup, not zero retained
descriptors before exit. The raw failures above are preserved even though
process termination eventually releases OS resources.

All paths in descriptor snapshots are relative to the owned fixture root;
leading slashes do not identify system files. The manifest sanitizes commands
and owned environment labels. No owner state or original source was changed.
The twelve raw result JSONs and manifest remain developer-owned under
example/chord/test/fixtures/records/scale/; designer owns only this summary.

## Later confidence and cleanup addendum

The status and unsettled-approach wording above describes this pre-fix
baseline when retained at 8f5725fd. CTUI-53 subsequently supplied reviewed,
tester-accepted canonical own-handle proof and the full affected six-run
cleanup rerun; see the [validation record](../validation/README.md).
Historical baseline JSONs and positive named REG/DIR failures remain untouched.

The later audit found that old benchmark root matching used a literal prefix,
without retained canonical-root identity for every invocation. Therefore the
zero entries above are recorded observations, not independently certified
absence of owned descriptors. Alias/parent-component mismatches cannot be
excluded for every old zero. Positive named failures remain real; corrected
canonical post-fix zeros do not retroactively certify the old snapshots.
Invalid-path positive-control and setup failures are retained separately,
with their limitations, in the linked CTUI-53 manifests/log. The six new full
results pass their scoped cleanup/correctness gate, while all prior hitch
figures and the explicit no-performance-pass disposition remain.
