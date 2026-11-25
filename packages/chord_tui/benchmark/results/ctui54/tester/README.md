# Independent CTUI-54 framework AOT evidence

Harness: `a49170c44dc59b0074008f10bc2b5cb75209a850`.
Production: `ffa1efd2f86b9d92013aa0b9ebe7b7d4af73938a`.
The exact committed archive ran inside the task checkout. The manifest names
commands, hashes, binary digest, exits and cleanup. All five runs used nice19
sequentially during a developer/designer numeric quiet boundary. Each has
three repetitions at beginning/middle/end and 50 inputs per host. Corpus
and row budget are in each report. This is framework measurement only;
it does not pass actual resume or the pending failed-projection repair.

Times are milliseconds. Navigation ranges are the nine host medians;
cold ranges are minimum to maximum across the nine hosts.

| Kind/count | First layout | Resize 80x24 | Return 120x40 | Navigation redraw median range | Worst redraw p95 |
| --- | --- | --- | --- | --- | --- |
| Default 2,000 | 0.294–0.985 | 0.111–0.922 | 0.116–0.342 | 0.186–0.371 | 0.689 |
| Default 10,000 | 0.500–2.239 | 0.292–1.814 | 0.299–1.119 | 0.184–0.381 | 0.742 |
| Exact custom 2,000 | 8.949–23.367 | 9.951–15.659 | 7.492–10.784 | 0.098–0.442 | 0.953 |
| Exact custom 10,000 | 45.906–58.988 | 44.162–46.120 | 33.372–35.936 | 0.103–0.434 | 0.960 |
| Measured fallback 20 | 1.400–3.919 | 1.104–3.279 | 0.995–2.438 | 0.724–1.336 | 2.473 |

Stable exact/default navigation made zero scalar projection/filter calls.
Per 50 inputs, item reads were at most 600 and exact custom builds/layouts
at most 400. Exact cold widths made exactly N scalar projections. Fallback20
made 1,000 custom builds/layouts per 50 inputs; it is a separate conservative
control. Default custom build/layout counters are unavailable, so their zeros
do not count built-in rows. Scheduled-to-acceptance median ranges were
18.153–18.566 ms for exact/default and 18.813–19.479 ms for fallback, including
the intentional 16 ms timer. Cold exact geometry retains an O(N) hitch.
There is no universal timing threshold.

First layout excludes AppHost/corpus creation. RSS is process observation,
not retained-heap proof. Source ownership and deterministic current-generation,
projection/read/build/layout evidence support only bounded navigation work
and cache ownership. ItemExtents can retain one high-water scalar capacity
after count shrink; allocated capacity need not shrink to current N. No
old-generation heap census or physical display latency was measured. This
generic corpus is not CTUI-26's actual ResumePicker corpus; its comparison
remains a separate gate.

Exact-snapshot analysis passed; format checked 680 files with zero changes.
All 45 hosts disposed, all 2,250 timers awaited, all subprocesses exited,
stderr empty, no owned benchmark process remained. Scratch binary/archive
were removed. No tmux, state root, model or agent was created for these runs.
The initial missing output-directory compile failure is retained in
compile-setup.txt as a setup observation, not a product failure.
