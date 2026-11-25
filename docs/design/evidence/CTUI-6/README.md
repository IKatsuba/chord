# CTUI-6 Diff visual check

Unit 6, implementation f23e6bc. Ran `dart run example/diff.dart` in owned
session designer-diff at 120x40 and 80x24. Ran the original fake agent's
edit scenario in owned session designer-diff-original at both sizes;
scenario text was sent literally and Enter in its own call. No code diff
was used for the visual decision.

Result: visual pass, no findings. The greeting edit reproduces the
original's row text, signs and shared numbering. The live original files
retain its tool framing; the framework supplies only title and rows, as
designed. The original capture's runtime-directory row is explicitly
omitted; no other row was changed. Also compared the existing reference
`../chord/docs/images/edit.png`.

The long removed line fits at 120 and wraps at 80. Its continuation starts
at column 6 (five blank gutter cells), with no repeated sign, number or ↪.
This follows the design's written code-column rule; CTUI-6.md's sketch was
corrected to remove its two excess spaces. Source indentation belongs to
the first row only. Gap dots sit in the sign column between hunks.

Dark/light captures show syntax tones over row tints. Files captured with
capture-pane -e -N preserve trailing blank cells: the background extends
through the complete row, including gutter, trailing cells, the wrapped
continuation and an empty added line. Light selects ThemeData.light;
no actual light-terminal background measurement is claimed. Untinted
captures show whole changed code in added/removed colour while context
keeps syntax tones. Plain captures have no colour and retain signs and
dim numbering. Lower samples show unified hunks and multiline comments,
a new file with a blank addition, unknown-language rows without syntax
colours, and equal files with only their title. KeyHelp lists the fixture's
actions and truncates according to its existing behaviour.

The complete-state check covers both required viewport sizes and every
fixture theme. It is not a parser validation, performance, cache or
NO_COLOR startup test, nor a claim to cover syntax state absent from a
unified input. Those limits remain in CTUI-6.md and technical checks.
Both owned sessions exited; tmux reported both absent and their terminal
devices were gone. No other session was touched.
