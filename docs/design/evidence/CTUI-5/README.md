# CTUI-5 Code visual check

Unit 2, implementation commit 4b446d4. Ran `dart run example/code.dart`
in designer-owned tmux session `designer-code`, first at 120x40 then at
80x24. No code diff was used for the visual decision.

Result: visual pass. The numbered Dart sample matches CTUI-5's two sketches;
the narrow continuation is dim, aligned in the mark column, and retains
the string's token colour. TypeScript's multiline comment remains coloured
on both lines. Empty and unlabelled samples retain blank rows and indent.
The tab expands to two cells. Numbers-off and wrap-off states read as
specified. Paging reveals the lower samples; theme toggling leaves layout
unchanged. KeyHelp lists the fixture's actions and truncates at the edge,
as the existing widget does.

Files named code-dark, code-light and code-plain record both viewport
sizes, as plain text and capture-pane -e output (.ansi). Additional narrow
captures show clipped, unnumbered and scrolled-lower states. These are
whole-pane text captures, not screenshots; ANSI files preserve exact styles.
The light captures select ThemeData.light; they do not claim an actual
light-background terminal measurement. Plain mode has no colour escapes.

Reference comparison: CTUI-3's existing chord-derived palettes and the
code/highlight contracts in CTUI-5.md; `../chord/docs/images/edit.png`
provides the token-colour reference. This is a standalone framework widget,
not a port reply screen: no original transcript was run or compared for
pixel equality. The approved wrap marker/optional line numbers and absence
of code-box furniture are intentional. The port's later Markdown screen
check will compare the original reply beside its fixture.

No findings. This pass does not measure performance, cache correctness,
NO_COLOR startup handling, or widths below the two required viewport sizes.
Those remain reviewer/tester scope. Killed the owned tmux session and
confirmed it no longer exists. No other session was touched.

## Whitespace fix recheck

Implementation 0e9c17c supersedes 4b446d4 for the unit's wrap behaviour.
Reviewer found that the original implementation dropped source spaces at
wrap boundaries; the initial fixture look did not exercise that case and
its visual pass did not clear this correctness finding.

Re-ran the handed-over fixture in owned session designer-code-fix at
120x40 and 80x24. The code-fix-* captures supersede the original dark
captures. The standard Dart source retains the same 80-column break.
The seven-cell sample with numbers disabled shows `  a` on its first
row and `↪ b` on the continuation. With numbers enabled, source spaces
lead the continuation after its blank number gutter and marker. The
12-cell sample retains indented continuations; whitespace-only rows at
these deliberately tiny widths are expected when preserving source.
Trailing spaces are invisible in normal capture-pane text, so these
captures establish placement/readability, not a lossless source proof.
Reviewer separately reported 46 reached tests passing and cleared the
space-preservation blocker on 0e9c17c.

Visual recheck passes with no further findings. No colour roles changed;
the initial light/plain captures remain the theme reference. Killed the
owned fix session and confirmed it absent before handover.
