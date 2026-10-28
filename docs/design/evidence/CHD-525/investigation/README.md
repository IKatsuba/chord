# CHD-525: unresolved layout investigation

This record supersedes completion implications in earlier investigation
material. It preserves a measured failure and a later source-only finding;
neither is an accepted fix. Historical authority and alternatives remain in
[the design](../../../CHD-525.md).

## Original real-terminal failure

Source: `66290d2aa07108fd4d9c3c972d148568b1309c35`, not the later
design-only commit containing this record. These are unchanged copies of
the original `source-80-one-settled-open.txt` and
`source-80-one-settled-closed.txt` captures. Both files have filesystem
modification time 2026-10-28 11:14:27 +01:00; no independently logged
capture clock is available. Their original directory was provisionally
named `final`; that name does not mean acceptance.

The original follow-up controller used a private tmux socket, a fixed QA
directory, isolated configuration/state, fixture-only resource access and
the repository's fake ACP agent. It launched source through
`bun src/main.tsx fake -C <fixture-project>`. This was a manually prepared
QA fixture, not a fresh `bun dev chord --qa` run for this documentation
update. Literal text and Enter were sent separately; captures used
`tmux capture-pane -p`.

Sequence: start at 80×24; submit `agentmentions` and wait for nine fake
process starts and the idle frame; submit `planshrinkgated`; queue
`queued 0` through `queued 3`; bracketed-paste seven lines `draft 0`
through `draft 6`, followed by a newline and `@`. Observe zero-room
completion and Tab leaving the draft unaccepted. Resize to 80×25; move
Down five times to `pressure-file5.ts`; capture open; send Escape and
capture closed with the same eight-line draft and cursor after `@`. No
resize, draft/cursor edit, plan/queue or roster mutation occurred between
the pair. The controller waited for the visible selection and its
disappearance, with short settling delays.
Developer confirms its final cleanup removed the owned tmux server, fake
processes, paste buffer and scratch directory after the comparison failed.
This record does not rerun or strengthen that original method.

| Capture                         | Prompt top / bottom, one-based | Permanent agents rows               |
| ------------------------------- | ------------------------------ | ----------------------------------- |
| [Open](source-80x25-open.txt)     | 12 / 21                        | 23–25: main, parser, `… +3 more`      |
| [Closed](source-80x25-closed.txt) | 11 / 20                        | 22–25: main, parser, docs, `… +2 more` |

Both frames are 80 columns by 25 rows. Working, the three plan rows, four
queued prompts and the displayed draft remain. The status row also moves
from 22 to 21. Elapsed timestamps advance between captures; this is not a
byte-identical permanent-content comparison. The observed agents growth
and border movement violate the same-draft geometry requirement. At this
source, `App.tsx` pins the transient agents height from `agentsRoom`
(lines 800–802, 1988–2008); closing restores native sizing. This explains
the observed transition by source inspection, not by a new runtime probe.

SHA-256 of the unchanged text captures:

```text
fbbc81aeef7451fadc0adcaffafd83ed67f0180658b9280ed5f9483474c478b0  source-80x25-open.txt
a507f1a3d465af37344fc5c3ba4da5269820bcafba15a3d28b98f728781b2b17  source-80x25-closed.txt
```

## Stopped baseline-pass trial

The later uncommitted trial attempted to measure native closed agents room
by temporarily hiding the transient. It retained mounted help with public
`visible` and used `onSizeChange`, `flushSync` and `renderAfter`. Its failed
changes were preserved separately, not accepted or integrated by this note.

The retained targeted-run log reports **6 pass, 3 fail**, 36 filtered tests,
198 expectations, nine tests across two files in 14.33 seconds, under Bun
1.4.4. The pressure one-row and zero-submit cases passed. The zero-resize
case failed permanent-content equality (`… +2 more` versus `… +3 more`).
Existing CHD-528 help checks passed without agents at 80×20, 80×24 and
100×30, and with agents at 80×24. With agents, 80×20 had a corrupted first
help row; 100×30 had no visible first help row. Both failed the existing
first-row assertion. Passing subsets do not establish combined layout fit.

The exact command was:

```sh
nice -n 19 bun test --isolate --timeout=60000 ./tests/ui/app/AppLayout_test.tsx ./tests/ui/shortcuts/Shortcuts_test.tsx -t 'pressure|CHD-528 tester: page boundaries' > /tmp/chd-525-baseline-beforepaint-trial.log 2>&1
```

It exited 1. The log's filesystem modification time is 2026-10-28
11:33:48 +01:00. The case breakdown above follows the retained log rather
than a broader claim that all pressure cases passed.

The original log is retained privately as
`chd-525-baseline-beforepaint-trial.log`; it includes machine paths and is
not published here. SHA-256:
`6664df9673efaf0e6c62923f0fa064e915989c42d9be4eecc6e03d2b45c2dcf5`.
These results belong to the stopped trial, not immutable `66290d2a` or the
untried candidate below. No static, rebuild or integration success is
claimed for it.

## Fresh public composition assessment: untried

Designer proposed one native root column: an above region with
`flexGrow=1`, `flexShrink=1`, `flexBasis=0`, `minHeight=0` and hidden
overflow, holding transcript, Working, plan, queue, requests/pickers and
transient in their existing order; a permanent prompt/status/agents/summary
group with `flexShrink=0`. Keys, precedence, help paging and colors would
remain unchanged. No new action was proposed.

Designer and reviewer independently rejected its source fit. The zero-basis
above region removes pinned above-chrome demand from root negotiation;
the nonshrinking bottom group gives agents no externally reduced height
to reproduce the existing closed partial/floor fold. It can instead clip
required above chrome. An auto basis reintroduces transient demand and
menu-induced folding. See immutable `App.tsx` lines 661–677, 1463–1487,
1642–1877 and 1988–2008, and [CHD-464](../../../CHD-464.md)'s pressure and
hysteresis rules.

Installed OpenTUI 0.6.6 `Renderable.d.ts` lines 30–57 and
`renderables/ScrollBox.d.ts` lines 16–30 expose native sizing, clipping and
viewport composition. The [public layout documentation](https://opentui.com/docs/core-concepts/layout/)
describes ordinary flex sizing and absolute flow. This assessment found no
closed-only demand/priority allocation that resolves the conflict. A custom
measurement provider supplying that allocation would cross the forbidden
layout-engine boundary. This is a bounded source assessment, not API
exhaustiveness proof or a measured candidate failure. No candidate trial
was run.

The smallest alternatives are to defer pending a fitting public capability,
or explicitly change the fixed-geometry pressure requirement and retain
native folding (historical design option B). Neither alternative is selected
by this record. A changed ordering or overlay is also a design change,
not an equivalent implementation of the current contract.
