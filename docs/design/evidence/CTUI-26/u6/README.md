# U6: startup resume and source CLI routes

Visually accepted at 074f70fdeeff80edf035db3d11e878dc7c56d025 after two
narrow fixes. Handed unit b85f72898ca7be36a7fd93b47c30a5cd82c6f75f;
first fix cf222931dd61338e8befe7075b8cde7977e68f38. Original source:
577b58167672e12c999aeaf4eed2a1a988513dc2. No blocking screen finding remains.

## Reproduction

Each port source run used an exact git archive under ignored build/, with
root/port package configurations resolving local packages into that archive.
port-* captures are b85f728; port-fix-* are cf222931; port-fix2-* are 074f70f.
Older observations are retained with their actual provenance, not relabeled.
Owned designer tmux used 120x40, 80x24, 32x10 and 32x9/11 neighbors.
NO_COLOR unset, COLORTERM=truecolor, FORCE_COLOR=3; --plain explicitly disables
colors. TMPDIR and XDG_STATE_HOME were owned/isolated. No real agent ran.

Run dart run example/chord/tool/start.dart --resume. Capture local, Ctrl+A
all; resize and repeat at both standard sizes. --empty --light starts with
only remote records; local empty omits Enter, Ctrl+A lists them. --tall --many
--plain exercises startup overflow. Down reads the tall selected row before
changing choice. Escape closes fixtures. Final-fix startup at 32x11 accepted
Enter and exited 0; the fixture starts no process. Normal Escape cancellation
also exits 0. Ctrl+C/Ctrl+D and every digit were not individually driven by
this screen look; injected/unit tests own those checks.

Original paired startup runs use read-only source via Bun production define,
fake named agent, explicit original fake command (--scenario text), isolated
state/config/cache and synthetic -C, with bare --resume. Seed four compact
v1 header/prompt records matching the fixture's title texts: local 0/2 and
remote 1/3; current prompt time for 0 and yesterday for others. Capture local,
Ctrl+A all, resize and capture. Escape exits before an agent starts. No
original file was edited. Original narrow neighbors reused these records.

## Findings and exact fix rechecks

At b85f728, 32x10 reserved the full wrapped hint/border and dropped all choices
and Enter, while original showed one selected metadata row and clipped its
hint/bottom border. cf222931 restores original startup unbounded room priority
but still showed two body lines where original allows one. Lead confirmed
this was port composition drift: an added footer row exceeded listed budget,
not an OpenTUI quirk. 074f70f removes that extra allowance without a framework
change. Final 32x10 metadata marker/down-edge, gap, hint start and bottom
clipping now match original. 32x9 and 32x11 preserve the same priorities; at
11 rows the border fits. Four-way failure/fix comparison is retained.

The shared resume composition fix also supersedes U5's earlier tall-six
observations that displayed seven lines. Final-fix tool/resume.dart --tall
--many --plain shows exactly six body lines at both standard sizes; Down
changes lines 1–6 to 2–7 in the same selected item. Ordinary --many --light
keeps its hidden-count footer inside six total rows, at both sizes. These
port-fix2-tall6/footer6 frames specifically verify the corrected budget.
Standard startup local full/compact layouts remain readable after fixes.

## Actual source CLI route observations

Use absolute archive example/chord/bin/chord.dart from an owned project cwd,
fake named agent and explicit original fake command (--scenario text), with
fresh owned TMPDIR/XDG_STATE_HOME. Submit literal text then Enter in its own
call; wait for Hello, world. This reply came in chunks. Ctrl+D exits 0 and
prints Resume this session with: plus the command after restoration (retained
plain scrollback). Store the printed UUID only within the owned fixture.

Bare --resume opens before any fake process was present at observation;
Escape in a fresh pane exits 0 with no resume message. --continue opens live
history directly without a picker. --resume with the stored UUID does the
same. From another owned directory, bare --resume starts local-empty;
Ctrl+A all then Enter opens the stored project cwd and its saved text/reply.
The explicit-id, continue and cross-directory resumed windows were closed
with Ctrl+D before opening another live runtime for that id. All reached
source CLI processes exited 0. These are source route observations, not a
compiled launcher, RPC-method/id assertion or interchange pass.

## Captures, differences and limits

Every pane txt has matching ansi; the restoration scrollback is intentionally
plain only. comparison-local/all pairs original/port at both standard sizes.
The 120x40 full art/tagline and 84-cell frame match; 80x24 compact art and
78-cell frame match. Version and directory labels differ. The port fixture
uses project/home-relative synthetic paths, original uses absolute synthetic
paths. Tied yesterday records follow distinct supplied input order; this is
not a stable-order mismatch claim. Original current ages advance while the
port fixture ages freeze. These different inputs are disclosed; all-directory
column widths/order are not an identical-fixture proof.

Dark startup, light empty/all and plain tall states were observed. Original
paired frames use its default palette; existing original theme evidence is
retained in the design baseline. No new original light/plain palette parity
claim is made here. The fake-only CLI checks used dark. Tall capture budgets
vary with startup versus the six-row agent-free fixture; compare within that
context. The second fix was checked from its exact archive for one/six-row,
footer and standard-size states; earlier actual CLI routes were not rerun
because neither visual fix changes their routing.

Original narrow clipping is preserved, not credited as a repaired screen.
No startup unbound acceptance, async no-start race, CLI-oracle correctness,
unsupported-header guard, exact RPC admission or process-group correctness
is proved by static captures. Those belong to reviewer/tester. U7 slash
command/overlay ownership and U8 compiled/bidirectional/combined-state proof
remain open.

Synthetic absolute temporary roots became same-cell-length ASCII fixture-root
labels padded with underscores. Truncated synthetic path segments became
same-length fixture-label strings. Restoration command paragraphs containing
absolute fake/source paths were redacted row by row without reflow. No home
path is retained. Dead-pane footers are tmux output, not product wording.

## Cleanup

All owned panes were confirmed dead with status 0. No owned app/fake process
remained; controlled TMPDIR was empty. Then the owned tmux server, archive,
outer XDG/synthetic records/projects/temp capture root were removed. Record
state was intentionally kept for the source resume observations until cleanup;
one owned record remained before removal. No test suite, compile, implementation
edit or owner-state access was performed by designer.
