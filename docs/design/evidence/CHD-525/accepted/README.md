# CHD-525: current U1 designer screen evidence

Designer inspected signed U1 `8eba99694a7d28f6f0cf351051767042f5586fd6`
on task branch `CHD-525`, after developer's explicit handoff and under the
lead's serial QA slot. Runtime remains `66290d2a`; the unit adds the honest
regression and decision record after design exception `ad1c9653`. This is
bounded screen acceptance under that exception, ready for reviewer, not a
completed review, tester pass or whole-slice release claim.

The freshly compiled host binary's SHA-256 was independently read before QA:
`85be2a93afbb1c5d587265c247d374c45c63cb6e6cbb57e9b746ba7d7dc5d433`.
Developer's fresh compile log belongs to this handoff; the equal historical
hash is not its evidence. No runtime edits occurred during capture.

## Method and fixture boundary

Each `.txt` is untouched `tmux capture-pane -p`; `.ansi` is the corresponding
`capture-pane -p -e`; `.png` renders that ANSI with existing AnsiUp and local
headless Chrome, Menlo 13px/18px, foreground `#e4e4e4`, background `#16171b`.
Each PNG contains the full terminal frame, with no cropped rows or invented
content. All published PNGs were opened for visual inspection, grouped in
full-resolution inspection sheets. The separate hardware cursor is outside
tmux cell captures. The manifest records raw capture modification times in
UTC, dimensions, border rows and file hashes; these times are filesystem
observations, not independently logged capture clocks.

Literal text uses `send-keys -l`; Enter is a separate call. Bracketed paste
uses an owned tmux buffer, not the clipboard. Bounded observed-condition
waits establish readiness; the inherited controllers retain short key and
resize settling intervals. The final zero pair additionally waits for the
actual folded agents summary, rather than merely seeing the status hint.

`devqa-*` runs `bun dev chord --fake --qa chd525-designer-devqa` at 120×40
and 80×24 in its fixed QA directory. `source-*` uses
`bun src/main.tsx fake -C <fixture-project>`; `binary-*` uses the handed
host binary with `fake -C <fixture-project>`. These latter manually prepared
fixtures have fixed scratch directories and private owned tmux sockets named
`chd525-designer-current-source` and `chd525-designer-current-binary`.
`--qa` belongs to the dev wrapper and is not passed to the binary.

Configuration, state and projects are isolated. Fixture settings map both
fake and codex runtime IDs to the fake ACP executable; the bugfix team is
copied from the repository fixture. Resource access is fixture-only through
`CHORD_RESOURCE_FIXTURE=true`. No live model/provider, installed account,
authentication or clipboard operation was used. Every completed controller
reported `owned remaining []`; owned servers, buffers and scratch fixtures
were removed. The dev wrapper's fixed QA directory was removed separately.

## Current observations

Rows below are one-based, top border then bottom border. Each ordinary pair
holds the same session, viewport, draft/cursor/display height and permanent
bottom state. Sources and binary agree:

| Pair | 120×40 open / closed | 80×24 open / closed |
| --- | --- | --- |
| Commands, `/` retained | 37/39 → 37/39 | 21/23 → 21/23 |
| Help, empty draft | 37/39 → 37/39 | 21/23 → 21/23 |
| Files, `@` retained, fixture roster | 32/34 → 32/34 | 17/19 → 17/19 |
| Agents, `@@` retained, fixture roster | 32/34 → 32/34 | 17/19 → 17/19 |
| History search, equal empty draft | 32/34 → 32/34 | 17/19 → 17/19 |

Commands, files, agents and search read above the prompt; status and agents
remain below. Color highlights, child colors, dim secondary text and the
Working accent retain their roles. Wide help fits whole. Narrow help shows
its existing overflow rule; PageDown reaches its end and PageUp returns to
the beginning, without changing prompt rows or losing the first/last keys.
The `help-page`, `help-end` and `help-up` stems record these states.

The settled zero-room source and binary triplets (`80-zero-settled`,
`80-zero-settled-tab`, `80-zero-settled-closed`) keep borders **11/20**.
All seven `draft N` lines and final `@` remain after Tab; no file is painted
or accepted. Full permanent agents rows compare equal after normalizing
elapsed seconds only: main, parser and `… +3 more`. Escape preserves those
rows too. The status hint may yield to the existing running-turn hint.
Initial early-paint frames showing main/parser/docs were omitted from this
acceptance set; hint visibility alone did not establish settled folding.

In the positive-room pressure sequence, resize 80×24 → 80×25 reveals a file;
Down five times keeps `pressure-file5.ts` visible in the single available
row. Resize back to 80×24 hides the list and blocks Tab; resize to 120×40
restores the same selection. Returning to 80×25 and Tab inserts exactly
`@pressure-file5.ts`. These are the `one-selected`, `pressure-positive` and
`one-accepted` stems. Acceptance changes the draft and closes the menu; it
is not an ordinary same-draft fixed-row comparison.

## Exact actual-owner exception

Fresh uninterrupted source and binary fixtures reproduce the exact accepted
sequence: start 80×24; submit `agentmentions`; wait nine fake process starts
and idle; submit `planshrinkgated`; queue `queued 0` through `queued 3`;
bracketed-paste `draft 0` through `draft 6`, newline, `@`; verify Tab accepts
no hidden item; resize 80×25; Down five times; capture selected file 5;
Escape; capture the unchanged draft/cursor, plan and queue.

| Current stems, both source and binary | Borders | Agents |
| --- | --- | --- |
| `80-one-settled-open` | 12/21 | main, parser, `… +3 more` (3 rows) |
| `80-one-settled-closed` | 11/20 | main, parser, docs, `… +2 more` (4 rows) |

This specific shift is accepted under the actual-owner exception. It does
not establish fixed geometry there or authorize other shifts. The unchanged
[original failed pair](../investigation/README.md) remains historical failure
evidence, with its original provenance and later decision distinguished.

## Separate history observation and controller limits

At zero room, Down on the draft's final line takes the existing ordinary
history path and sets the draft aside: borders become 17/19. Up restores all
eight draft rows at 11/20. The source `80-zero-down-set-aside` and
`80-zero-up-restored` captures show this changed-draft transition; they prove
neither fixed geometry nor hidden completion navigation. Developer confirmed
the existing U10/Q183 routing; no new key policy was introduced.

Chaining that history transition into resize 80×25 left four agents rows and
zero completion room; a controller expecting file 0 timed out and cleaned up.
That different allocation history is not the uninterrupted accepted case and
is not claimed as a successful positive-room comparison. Fresh exact-case
runs passed separately. An earlier controller also incorrectly expected
wide help to overflow; wide help fits and only narrow paging was required.
The sandbox initially prevented tmux fixture execution and nice priority;
authorized runs outside the sandbox succeeded. These controller corrections
changed no production code and justify no broader layout claim.

## Checks and remaining boundary

Finite source and binary ordinary matrices, separate exact 80×25 cases,
dev-wrapper command/help comparisons and settled zero triplets passed.
Designer did not repeat developer's regression/static/build suites, inspect
live providers, test native clipboard/physical key delivery, release targets
or installed settings. The screen reads correctly for this limited contract;
reviewer and tester remain the next gates.

Before committing the staged evidence,
`nice -n 19 bun test --isolate --timeout=60000 ./tests/privacy_test.ts`
passed: **8 tests, 0 failures, 36 expectations**, 4.30 seconds. Scoped
`bun fmt --check` on this record and the manifest, plus staged diff whitespace
checks, passed. No application or static suite was rerun for the evidence.
