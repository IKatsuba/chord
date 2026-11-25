# CTUI-48: architecture brief

## Problem and outcome

Mouse reporting currently prevents ordinary terminal drag selection. Port the
original window's left drag, release-copy, retained highlight and Ctrl+C
retry/cancel lifecycle. Add code-box [copy] and the ctrl+x b, arrows, c,
Esc keyboard mode. A successful OSC 52 write reports only sent to the
terminal's clipboard, never confirmed host copying.

The app author gets a reusable framework selection area/controller, semantic
source mapping and pointer capture, independent of chord and clipboard policy.
Flutter SelectionArea/SelectableRegion supply the architectural comparison,
not a dependency. Keep state/reducers directly testable.

## Authority and scope

Read AGENTS.md, README.md, docs/FEATURES.md and docs/decisions.md first.
Read CTUI-1, CTUI-2, CTUI-4/5/6, CTUI-9, CTUI-47 and CTUI-50 where relevant.
The original is read-only: ../chord/src/ui/app/selection.ts, App.tsx,
src/ui/transcript/code_pick.ts, CHD-172 and CHD-394 design notes and tests.
Inspect current code and behavior; the original is the specification.

Main settled the staged scope: selection and copy now. [run]/r and its help
clause wait for CTUI-25 bash mode. Document their future connection without
adding unavailable actions. Preserve existing approved wrapping, virtualized
transcript and scroll-geometry differences.

No implementation code, dependency changes, real model/agent or real clipboard.
Draft/evidence scripts must not modify the original. Original capture versus
current port baseline at 120x40 and 80x24 must be explicitly distinguished
from proposed screen sketches and later implementation acceptance evidence.

## Ownership and open questions

- framework writes drafts/framework.md only: public Dart call sites and exact
  parameters; region/controller/source-span lifecycle, text/code/Markdown/diff
  mapping, excluded furniture; paint/hit clipping and virtualization; mouse
  motion and capture API; ScrollController hold; code-action registry seam.
  Compare Flutter's selection architecture. Reuse existing packages; raise a
  package mismatch to lead rather than working around it.
- interface writes drafts/interface.md only: original screen/key/state contract,
  source and live capture evidence at both sizes, current port baseline beside
  it, semantic copy contents and feedback, code buttons/pick mode, help staging,
  theme and narrow geometry. Any extra evidence files remain under this task.
- runtime writes drafts/runtime.md only: ordering/reentrancy, held scroll,
  source invalidation, copy generation/timer lifecycle, terminal ownership and
  drag edge timing from the original, deterministic regression and AOT plan.
- critic edits nothing: after all drafts, find contradictions, missing contracts,
  ownership decisions and overengineering; state concrete fixes.

Each draft must define buildable units with failing-test acceptance and flag
owner questions with options/recommendation. One writer per file. The lead
merges final design and appends decisions, resolving every critic finding.

## Workspace

Use only the designated CTUI-48 worktree and CTUI-48 branch named in the
member launch prompt. Never read WIP or edit/commit in the main checkout.
Never switch branches, create another checkout or commit independently.
The lead makes the signed documentation commit after all drafts are complete.

## Owner settlements during architecture

Main approved inverse-only selection under NO_COLOR; otherwise use slate 66
on dark and 152 on light. This is an explicit appearance difference.
copyOnSelect is a default-true constructor seed now; CTUI-29 connects it to
user settings. CTUI-25 adds [run]/r and the related help clause.

Main approved resolving a nested-list range in one motion report rather
than reproducing OpenTUI's nesting-depth-dependent routing. Existing library
quirks are not reproduced; correct range/extent behavior is retained.

Pinned markdown 7.3.1 discards fence-closure status. Main approved extending
the existing block-syntax recording adapter through public parser state to
record the consumed closing fence, including nested fences. EOF-open fences
must have no buttons and be unpickable. No independent fence scanner.
