# Unit 4 visual check

Implementation: `370a97d2d2520e024dac98a95e1d91acb3ab6e45`.

Passed the handed-over header change at 120x40 and 80x24 in owned tmux
sessions, running from the task worktree. Commands:

```sh
dart run example/chord/bin/chord.dart fake --agent-command true
dart run example/chord/bin/chord.dart claude --agent-command true
dart run example/chord/bin/chord.dart
```

Text and ANSI captures are `unit4-fake-*`, `unit4-claude-*`, and
`unit4-no-option-*` in this directory. Directory text is redacted as
`<directory>`; `<directory…>` preserves that the original line was clipped.
All other text, styles and blank rows are the captured screen. Captures
retain all 40 or 24 rows, but do not preserve the redacted path's cell width.

The unknown catalog name shows `fake`, exactly as the CTUI-13 design.
The catalog name remains `Claude Agent`; no-option and catalog-override
screens match. `chord` is bold, the rest dim. At 80 columns the catalog
header clips with an ellipsis, leaving the quit hint intact on row 2.
There is no agent connection or status row in unit 4. Unit 5 adds those.

Compared with `original-connected-120` and `original-connected-80` in this
directory: the original names this agent `fake`, and styles the chord
wordmark bold with dim metadata. The interim's compact single header,
no mark/model/prompt, and one-press quit hint are the already-approved
CTUI-11/CTUI-13 staged differences. No new visual difference was found.

Ctrl+c closed the 120x40 fake-name run and ctrl+d closed the 80x24 run.
Both subsequent comparison runs closed with ctrl+d. All designer unit 4
tmux sessions were absent afterwards; no matching launched command or fake
agent remained. This is a visual pass, not a code review or test-suite pass.
