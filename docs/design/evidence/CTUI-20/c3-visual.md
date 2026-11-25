# C3 start page: visual acceptance

Screen handover: `60195b7`. Centering fix rechecked: `0f412b9`.

## Method and scope

Ran `dart run example/chord/tool/start.dart --long`, then `--many --long`
and `--empty --long` in owned tmux sessions. Ran the original with
`bun dev chord --qa` and an isolated capture name, with no agent argument.
Canceled through Esc throughout; no model or agent was launched.

Compared 120x40 and 80x24, then 39x14 and 30x8. The port fixture has
neutral frozen directories and synthetic agents; the original lists its
installed inventory. Side-by-side captures explicitly retain those data
and version differences. Original empty inventory was not reproduced;
its nonempty reference captures are named accordingly.

The final centering check explicitly used NO_COLOR=1. A separate colored
check removed NO_COLOR and set FORCE_COLOR=3, COLORTERM=truecolor and
TERM=xterm-256color for those fixture processes only. Text and ANSI
captures cover full and compact art. This verifies the settled theme-art
scope, not terminal color-depth negotiation or quantization.

## Observed

Full artwork, tagline, version/directory and picker read clearly at
120x40. At 80x24 the compact mark/wordmark leaves room for the picker.
At 39x14 the art gives way to a single chord/version/directory line;
the long synthetic directory is `…/example/project`, retaining a slash
boundary and the final components. At 30x8 only the picker/title and
wrapped key hint remain. No clipped art remains above it.

With many agents the visible-row budget and hidden-item count agree
with the original's composition: fourteen choice rows at 120x40 and
twelve at 80x24, with an edge marker and more count. Synthetic count is
28 and original inventory is 29, so counts and labels differ as expected.
The three-agent fixture shows the missing-command note. Moving from
claude to codex in the small window and widening preserves codex as the
selection. The empty fixture shows No agents available and Esc to cancel
without fabricated choices at both standard sizes.

## Finding and fix

The initial art group was one cell left of the original; plain chord sat
one row too high beside both even-height marks. Reported to developer.
Fix `0f412b9` rounds spare art-group cells and wordmark rows locally.
Fresh NO_COLOR captures now match: full mark begins at column 52, compact
at 35, with chord on the original's lower middle row. The full and compact
colored wordmarks also match the original's text geometry. Sampled ANSI
art roles/gradient values match in the forced truecolor fixture. Initial
captures remain as finding evidence; fixed-plain and color captures are
the acceptance states.

## Result and limits

Pass for C3 after `0f412b9`; no remaining visual finding. Preview data
comparison does not claim actual CLI agent discovery, config inventory,
startup selection, or launch-path wiring. Those are C4, which was not
handed over and was not inspected. Original empty-state runtime parity
and automatic color-depth behavior remain unmeasured here. No suite was
run by designer.

All owned sessions and original/preview processes exited after Esc.
No fake or real agent was started or left running.
