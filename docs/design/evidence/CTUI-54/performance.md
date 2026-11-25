# CTUI-54: validated actual resume performance

Stable navigation no longer projects every resume choice. Exact cold-width
projection remains O(N), with visible widget work bounded. This records the
reviewer-cleared/tester-validated unit; it is not final whole-slice readiness
or a general latency/memory pass.

Production `c784f3d1f4c745165b100078c4d151ee77163c51`, unchanged harness
`5674e39d8de00ab936ebbc6a71796493624a5c25`. Developer post-cap evidence
`8d3cc83`; independent tester evidence `b0654a8`. Reviewer cleared source and
both evidence sets. Designer read the tester README/manifest/summary and
all five raw reports' scoped work/surface/cleanup counters, without rerunning
benchmarks. The [independent validation](../../../../benchmark/results/ctui54/tester/actual_resume_post_cap/README.md)
links exact commands, binary/harness hashes, raw samples and measurement limits.

Five AOT configurations cover baseline 20/2,000/10,000 and wrapped 2,000/10,000,
three repetitions and beginning/middle/end navigation groups. All first/cold
stages shape exactly N rows, with zero capped no-edge/edge sizing passes.
Stable navigation, stage-scheduled input and unchanged frames record zero
choice/line/shaping work. Extents count N; mounted/placed widgets are at most
nine baseline and seven wrapped. These are current-surface observations,
not a whole-heap retention census or a bound on scalar-array capacity.

## Comparable 2,000-choice result

The baseline matches CTUI-26 titles/order, fractional last-use numbers,
10-row cap and Dart 3.13.5/AOT. The historical run recorded navigation
redraw 25.177–25.809 ms and cold/return resize 33.016–34.520 ms. Independent
post-cap navigation group medians are 0.242–0.653 ms, worst-group p95 is
1.322 ms; resize bodies are 3.649–5.623 ms to 80x24 and 3.815–4.679 ms back
to 120x40. One old run versus repeated new groups gives no universal ratio.

The new first body 6.666–8.623 ms includes construction, separately measured
at 2.582–3.241 ms. Historical first 64.880 ms timed drawing after construction.
Keep those conventions visible rather than treating the figures as identical
stages. Historical scheduledToAcceptanceMs subtracts its requested 16 ms timer;
compare new stage afterRequestedDelayMs, not stable total delays that include
16 ms. New baseline2,000 stage residuals are 1.535–3.927 ms on first body,
3.309–3.892 ms on resize and 3.115–3.993 ms on return. Full distributions
and setup costs remain in the linked tester evidence.

## Residual cold-width hitch

Wrapped 10,000 is additional stress, not the historical baseline. Its first
body including construction is 74.183–93.788 ms; cold resize 62.378–65.099 ms
and return 55.852–56.577 ms remain blocking work. Worst scheduled-stage
residual after subtracting 16 ms is 77.999 ms. Navigation aggregate p95 is
1.063 ms, while the worst individual group p95 is1.325 ms; neither erases
those cold hitches or defines a universal threshold.

Pre-cap3N evidence at `921684b` remains intact. The exact cap proof removes
two unnecessary sizing passes; it does not estimate geometry or eliminate
the remaining N shaping calls. Developer post-cap reports remain separately
owned under [post_cap](../../../../example/chord/test/fixtures/picker_scale/ctui54/post_cap/manifest.json).
The approved cold-width allowance must accompany any responsiveness claim.

Numeric counters add AOT-active overhead. Corpus setup is excluded/reported.
RSS/peakRSS are process observations, not retained-heap proof. No scan, disk,
agent, model, reopen, PTY write or physical display latency is measured.
All five independent processes exited0 with empty stderr; 15 hosts disposed,
2,250 navigation and 60 stage timers awaited. Tester verified binary/archive/
process/tmux cleanup. No fixture root/external process was created by the
harness. The exact reached correctness gate passed 108 tests and both statics.
Screen evidence is independently retained in u54c2-look.md and
u54c2-cap-look.md, including the accepted narrow original layout slip.
