# Independent actual ResumePicker AOT validation

Production: `c784f3d1f4c745165b100078c4d151ee77163c51`.
Unchanged harness: `5674e39d8de00ab936ebbc6a71796493624a5c25`.
Exact archive inside the task checkout; same five nice19 configurations,
three repetitions, 50 samples at each of beginning/middle/end. Developer
and designer held numeric quiet. Commands, hashes, exits and cleanup are in
manifest.json; raw samples remain in each report. summary.json distinguishes
aggregate distributions from the worst individual navigation group p95.

Every first/cold stage shaped exactly N rows and made zero capped sizing
passes. Every stable navigation, scheduled stage input and unchanged-frame
stage made zero choice/line/shaping work. Extent counts equaled N; at most
nine baseline or seven wrapped widgets were mounted/placed. These are
current-surface and scalar-work observations, not a whole-heap census.

Times below are milliseconds. Cold ranges cover three bodies. Navigation
median ranges cover nine groups; worst p95 is the worst of those groups.

| Corpus/count | First body including construction | Resize80x24 | Return120x40 | Navigation median range | Worst group p95 |
| --- | --- | --- | --- | --- | --- |
| Baseline20 | 0.948–1.537 | 0.445–0.604 | 0.577–0.990 | 0.287–0.646 | 1.002 |
| Baseline2,000 | 6.666–8.623 | 3.649–5.623 | 3.815–4.679 | 0.242–0.653 | 1.322 |
| Baseline10,000 | 28.749–36.723 | 13.814–17.561 | 14.604–14.837 | 0.294–0.738 | 1.267 |
| Wrapped2,000 | 20.399–23.083 | 16.247–17.403 | 12.598–13.260 | 0.338–0.710 | 1.239 |
| Wrapped10,000 | 74.183–93.788 | 62.378–65.099 | 55.852–56.577 | 0.316–0.658 | 1.325 |

For the comparable 2,000-choice baseline, CTUI-26 retained navigation redraws
25.177–25.809 ms and resizes33.016–34.520 ms. New redraw group medians are
0.242–0.653 ms, worst group p95 1.322 ms; new resize bodies are3.649–5.623 ms
and3.815–4.679 ms. Titles/order/fractional last-use numbers and10-row cap
match, with Dart3.13.5/AOT. The old first64.880 ms measured drawing after
host construction; the new6.666–8.623 ms first body includes construction
(2.582–3.241 ms), separately retained in raw results. No universal speed
ratio follows from one historical run versus repeated current groups.

CTUI-26 scheduledToAcceptanceMs subtracts its requested16 ms timer.
Compare it with stage afterRequestedDelayMs here: baseline2,000 first
1.535–3.927 ms, resize3.309–3.892 ms, return3.115–3.993 ms, versus historical
74.874,43.875,42.847 ms. Stable navigation totals include16 ms and are
19.261–19.411 ms across baseline2,000 group medians; they must not be
compared directly with the old residual metric. Position setup is separate.

The wrapped corpus is an additional stress case, not the baseline oracle.
Pre-cap3N evidence at921684b remains intact; this run uses exactly N cold
shapes. Wrapped10,000 still has62.378–65.099 ms cold resize and55.852–56.577 ms
return; its first body includes construction and reaches93.788 ms. Worst
stage residual after subtracting16 ms is77.999 ms. Exact cold projection
remains O(N); navigation improvements do not remove that hitch. Aggregate
redraw p95 for this corpus is1.063 ms, while worst-group p95 is1.325 ms.
Neither number is a universal threshold or a claim about physical display.

Numeric counters add overhead. Corpus setup is excluded and reported.
RSS/peakRSS are process observations, not heap retention proof; scalar arrays
may retain high-water capacity. Existing structural tests prove bounded live
widgets and current ownership only. No scan, disk, model, agent, reopen, PTY
write or physical display latency is measured. This validates the exact
capped unit and benchmark, not later work or final whole-slice readiness.

Exact correctness gate:108 reached tests, analyze no issues, format685 files
unchanged. All five subprocesses exited0; stderr empty. All15 hosts disposed,
2,250 navigation and60stage timers awaited; no fixture root or external
process created by harness. Owned benchmark binary/processes and manual
fixture tmux were cleaned. Exact archive cleanup is recorded in manifest.
