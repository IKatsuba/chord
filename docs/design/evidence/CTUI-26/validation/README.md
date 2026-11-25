# CTUI-26 and CTUI-53 validation record

This summarizes handed, reviewed implementation/runtime/scale units. It is
not a final exact-head validation or universal performance-pass claim.
Designer read the retained reports and verified the six full-run hashes;
no runtime was rerun for this summary. Final writer changes and the team's
final exact-commit gate remain separate.

## Provenance and retained evidence

| Evidence | Exact source/artifact boundary |
| --- | --- |
| Pre-fix twelve-result scale baseline | Artifact 8f5725fd4fbd10eb0cd5547fb3d96fe26cda67e2; source/workload boundary in its [manifest](../../../../../example/chord/test/fixtures/records/scale/manifest.json) and [summary](../scale-baseline/README.md) |
| Package capability gap | Artifact 32aad5979acdbee191730b00bf4cf0d799437944; [manifest, source/lock and JIT/AOT results](../../../../../example/chord/test/fixtures/records/ctui53_packages/manifest.json) |
| Real public-operation own-FD proof | Artifact/tool/test 9a36a02253f511898c4fbc20c737feddd7ad8048; exact base archive 82388d693e3e6f42772ac07132e4cb71088fbcd8 plus guarded tool/test hashes in [manifest](../../../../../example/chord/test/fixtures/records/ctui53_handles/manifest.json) |
| Canonical benchmark-root correction | Source a7a8205b9429dfd059ded49d2cb05e78d644a2c4; [small smoke manifest](../../../../../example/chord/test/fixtures/records/ctui53_scale_smoke/manifest.json), diagnostic scope only |
| Full affected six-run rerun | Source a7a8205b9429dfd059ded49d2cb05e78d644a2c4; tester-run artifact b6099d06455119b2273c65e80e847214a1c80538; [tester manifest and per-report SHA256](../../../../../example/chord/test/fixtures/records/ctui53_scale/tester-manifest.json) |
| Native resume/interchange unit | Source 51b49ab1991d8b3fb6540d3ce27d382a7b190615; developer/reviewer/tester handoff reports 13 compiled tests and one interchange check; [native smoke](../../../../../example/chord/test/fixtures/native_resume_smoke.dart), [compile tests](../../../../../example/chord/test/cli_start_compile_test.dart), [interchange test](../../../../../example/chord/test/session/record_interchange_test.dart) |

The full six reports were copied byte-exact by developer, reviewed and
independently byte-verified by tester. Raw artifacts remain developer-owned;
this summary links them without duplication or modification. All source
commits and instrumentation distinctions in their manifests remain material.

## CTUI-53 cleanup result

The [JIT](../../../../../example/chord/test/fixtures/records/ctui53_handles/jit.json)
and [AOT](../../../../../example/chord/test/fixtures/records/ctui53_handles/aot.json)
public-operation proof each positively observed one DIR during enumeration,
eight REG files during scan and one REG during selected-history reading.
One immediate own-process lsof snapshot after each public Future settled was
empty, as was the post-root-deletion snapshot. Across eight operations per
mode (directory/eight-file/selected/projection cancellation, scan/selected
success, filesystem/version error), Closed streams/tasks and pending Futures
were zero, SDK exit was joined and roots were removed. Projection cancellation
was gated after its IO had already closed. No sleep, retry or polling made
an empty snapshot pass. Reviewer and independent tester accepted these gates.

The initial [invalid-path control log](../../../../../example/chord/test/fixtures/records/ctui53_handles/invalid-path-control.log)
reported no DIR because literal noncanonical roots did not match canonical
lsof paths; a setup copy mistake repeated the stale invalid control once.
Those attempts ran no AOT and prove neither absence of a DIR nor production
cleanup failure. The corrected proof canonicalizes the actual allocated root
before seeding/gating/snapshots and observes the positive controls above.
The later benchmark smoke also rejected one wrong source comparison path
before runtime; its manifest retains that setup guard and corrected invocation.

## Full affected workload, attributed to tester

Tester ran three sequential JIT repetitions, one AOT build and three sequential
native repetitions at exact a7a8205, with source SHA256
ce5c7cbfd69056dd078c8c2b770d137396e619f4a43aae231fd64beea3094048.
All exited zero with empty stderr. Each used 2000 freshly created records,
an additional 8 MiB irrelevant line, 4000 history turns and 10000 stalled
updates. Files were warm after creation. Cached locks, controlled TMPDIR/XDG
and read-only original source were isolated; actual roots, binary and owned
processes were cleaned. Headless synthetic Actions are not PTY/display timing.

| Runtime | Retained full reports | Named descriptor snapshots |
| --- | --- | --- |
| JIT | [1](../../../../../example/chord/test/fixtures/records/ctui53_scale/jit-1.json), [2](../../../../../example/chord/test/fixtures/records/ctui53_scale/jit-2.json), [3](../../../../../example/chord/test/fixtures/records/ctui53_scale/jit-3.json) | All ten stages zero in each run |
| AOT | [1](../../../../../example/chord/test/fixtures/records/ctui53_scale/aot-1.json), [2](../../../../../example/chord/test/fixtures/records/ctui53_scale/aot-2.json), [3](../../../../../example/chord/test/fixtures/records/ctui53_scale/aot-3.json) | All ten stages zero in each run |

The ten stages include before/after scan, after cancelled scan, after the
instrumented scanner, after preparation, after cancelled preparation, after
layout/drain and before/after root deletion. Roots were canonicalized before
IO. Scan/preparation cancellation actually occurred in all six runs. Peak
instrumented scan streams were eight, retained streams/pending Futures zero;
queued/held bytes after drain were zero. Correctness/copy/root guards passed.
These results close the affected scale cleanup gate; they do not retroactively
certify older zeros or imply that arbitrary future workloads cannot fail.

Stage wall times and the range of per-run maximum delivered-input samples,
in milliseconds, remain distinct:

| Stage | JIT wall | JIT max input | AOT wall | AOT max input |
| --- | --- | --- | --- | --- |
| Scan | 764.234–794.068 | 3.149–4.236 | 601.616–630.801 | 2.475–3.060 |
| Preparation | 75.823–79.001 | 0.262–2.059 | 40.501–41.848 | 0.606–0.956 |
| First layout 120x40 | 355.814–380.505 | 339.999–364.691 | 133.549–135.142 | 117.572–119.166 |
| Resize 80x24 | 184.046–187.282 | 168.130–171.355 | 125.316–130.856 | 109.329–114.866 |
| Resize back 120x40 | 147.545–150.681 | 131.613–134.753 | 125.741–129.926 | 109.760–113.944 |

Request-to-public-Future cancellation timing was JIT scan 1.625–1.810 ms,
preparation 0.397–0.631 ms; AOT scan 0.086–0.092 ms, preparation 0.206–0.241 ms.
These are not physical exit latencies. Fifty unpaced steady frames totalled
12.837–13.353 ms in JIT and 4.626–4.815 ms in AOT with zero dispatched-input
samples: latency is null, not measured zero. Cumulative process peak RSS was
about 643.53–647.42 MiB JIT and 138.56–139.41 MiB AOT; it is not per-stage
allocation. Original Bun references remain separately labelled, with different
features/input instrumentation and no cross-runtime speed ratio.

## Historical failures and measurement confidence

Pre-fix JIT end observations 0/1/7 and AOT 8/0/0 remain unchanged. Named
positive REG/DIR observations are real failure evidence. The one bounded
transient-DIR diagnostic did not identify the initial unnamed JIT end handle.
Later REG recurrences persisted through root removal. All twelve baseline
JSONs are retained, with their differing counts-only/named instrumentation.
Their literal-root matching lacks verified canonical identity for every run,
so historical zero snapshots cannot independently exclude alias/parent-path
mismatch. New canonical proof does not turn those old zeros into certified
absence. The baseline summary's confidence addendum records this distinction.

Physical isolate count and physical exit latency remain unmeasured numerical
metrics. Explicit IO cleanup ACK plus same-port SDK exit is the operational
barrier, not a physical timing measurement. A watchdog bounds hung failures;
elapsed waiting is not cleanup proof. The stalled append remains an injected
gate, not filesystem flush/durability measurement. No queue cap or timeout was
added. Root/process cleanup and zero pre-exit descriptors are distinct claims.

## Screen/native scope and approved limits

Source/fixture visual looks at 120x40 and 80x24 are retained separately in
[U4b](../u4b/README.md), [U5](../u5/README.md), [U6](../u6/README.md) and
[U7](../u7/README.md), with their exact hashes, failure/fix captures and limits.
The compiled PTY smoke is scoped to 80x24. Lead chose no extra
compiled 120x40 run; source 120x40 captures are not native 120x40 proof.
Native/interchange results are attributed to the developer/tester handoffs,
not a new designer runtime. The original fake has canned HISTORY; it does not
prove an agent's real persistent history. Existing source/transcript/byte-prefix
interchange limits and deferred runtime families remain in the binding design.

Main retains the existing failed-start/protocol-error screen without prompt or
resume anchor; /resume after failed startup is a separate task. The separate
2000-choice picker run still reports 64.880 ms first layout, 34.520/33.016 ms
resizes and 25.177–25.809 ms navigation redraws. No extra picker rerun was
performed. Main deferred that framework redraw concern; transcript hitches
above remain explicit too. No framework cache change, O(visible rows) claim
or universal performance pass is made. Cleanup correction does not erase
first-layout, resize or navigation costs.

All implementation/runtime/scale units have handed review/test passes within
these scopes. Final documentation and exact-head suite/static validation are
still a separate gate; this summary does not declare the branch ready.
