# CTUI-49: corrected transcript geometry

Handed unit: signed `55ef56407f3bc1717730dc9c35d5d23fd9da35ec`.
Lead/main ruling: `2adf163`. No production change; regression verifies
stable full extents. Original head: `577b58167672e12c999aeaf4eed2a1a988513dc2`.

## Reproduction

Original command: `bun dev chord --fake --qa designer-ctui49`.
Port command: `dart run example/chord/tool/dev.dart chord --fake`.
Owned tmux sessions, 120x40: send `long` literally, Enter separately, wait
until Line 200 and no working line; send `permission`, Enter separately,
wait for prompt then Esc; send `bigask`, Enter separately, then Down to
choice 2. Capture bottom, inject one SGR up report `ESC[<64;10;7M` over
proposal title. Save both plain and ANSI captures.

At 120x40 the original title-wheel result begins `4. Line 4 of 200` with
`↓ 1 line below`; the port retains the wrapped MCP headline with `↓ 2 lines
below`. This reproduces retained CTUI-47 evidence exactly. The port behavior
is deliberately kept, following the main ruling: original layout collapses
its measured tool content when Below leaves one viewport row. The proposal
body, current choice and status geometry match. Timer values differ because
captures were taken at different elapsed times.

| State | Original | Port |
| --- | --- | --- |
| Bottom 120x40 | original-bottom-120x40.txt | port-bottom-120x40.txt |
| Title wheel up 120x40 | original-title-up-120x40.txt | port-title-up-120x40.txt |
| Resize to 80x24 | original-resized-80x24.txt | port-resized-80x24.txt |
| Bottom 80x24 | original-bottom-80x24.txt | port-bottom-80x24.txt |
| Title wheel up 80x24 | original-title-up-80x24.txt | port-title-up-80x24.txt |

Each has an `.ansi` companion for the same state. At 80x24 no transcript
row remains above the working line: title wheel does not expose transcript
content and the visible proposal matches. This is a viewport boundary, not
evidence that the original one-row collapse occurs at 80x24.

## Independent original probe

`original-clip-probe.js` is the exact read-only developer-supplied probe,
independently run against original source. Run from the original checkout
with `bun --eval` and the file contents as its argument. It dynamically
imports React, tests/ui/harness.tsx, Clip.tsx and Tool.tsx through process.cwd;
no original files are written. Full stdout is original-clip-probe.jsonl;
stderr is original-clip-probe.stderr.txt (empty), exit 0.

The child layout heights for parent Clip heights 2, 1 and 3 are respectively
9, 1 and 9. At 1 the frame is empty. Source references and the linked upstream
opentui#1739 diagnosis are in the lead's CTUI-49 decisions entry. This is a
specific reproduction of the original library defect, not an inferred cause
from a screen difference.

## Result and cleanup

Visual pass on the handed unit, with intentional corrected geometry named
above; hand onward to reviewer with 55ef564 and 2adf163. No implementation
review was performed. No themes changed by this regression-only unit; ANSI
captures confirm the existing default theme state. Both owned tmux sessions
were killed after captures; the surviving owned port process was then sent TERM
after its worktree cwd and launch time were verified. It remained after TERM,
so that verified owned process was killed explicitly and checked again. No physical mouse/trackpad claim: wheel evidence
uses byte injection.
