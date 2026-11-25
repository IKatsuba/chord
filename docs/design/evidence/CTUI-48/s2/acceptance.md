# S2 designer acceptance

Implementation: `bbdab4aff35e75fa97278ec9d710ba341363e595` on CTUI-48.
Developer held the clean assigned worktree throughout this API/demo look.

The public SelectionSource factories match the approved immutable geometry
contract: Text align/wrap/overflow/maxLines, Code numbering/wrap, Markdown
copyCodeBlocks=false and Diff frozen effective title/showTitle. The bound
Text/Code/Markdown/Diff constructors follow the approved nullable override
shape and validate conflicts. Code identity has no public constructor;
Markdown descriptors expose complete from introduction. Public factory and
binding examples read naturally at their call sites. No API finding.
This is a designer API look, not code review or independent test verification.

## Runtime evidence

Commands, each run from the assigned task worktree in owned tmux sessions:

```sh
dart run example/markdown.dart
dart run example/code.dart
dart run example/markdown_wrap.dart
dart run example/diff_view.dart
```

Socket label: ctui48-designer. Sessions designer-s2-120 (120x40) and
designer-s2-80 (80x24), with at most two demos running together.
Capture-pane -p and -p -e retained every state as .txt and .ansi:

- markdown-dark/light/plain: initial completed content; C-t twice selects
  light then plain. Plain-bottom follows End, showing code boxes, table and
  definition text. Paragraphs, list markers/indentation, quote bars, code
  borders and table cells remain readable at both widths.
- code-initial: numbered and wrapped dark code, including Japanese text.
  code-no-numbers-no-wrap follows C-n and C-w, showing ordinary clipping at
  the narrow width and the preserved source blank lines/tab example.
- markdown-wrap: completed link/table fixture at each size, including
  wrapped table cell phrases and long link display text.
- diff-capped/full: C-o toggles the row cap. Counts stay 2 additions and
  2 removals; the cap's hidden-row note disappears for the full view; long
  changed lines wrap at 80 columns with their gutter preserved.

No visual finding. This framework-only unit changes source/shaping internals;
no port screen or original comparison is claimed here. Demos use existing
ordinary constructors; they do not prove interactive selection or exercise
all provider-bound runtime paths. Those paths remain covered by the handed
S2 tests and subsequent S3/S7 acceptance. No clipboard, fake agent, compile,
soak, full suite or physical pointer/cursor check was performed by designer.

ANSI captures retain palette evidence; all plain Markdown captures were
checked for foreground/background SGR codes and had none. Captures contain
no private filesystem path. Each pair exited normally with C-q before the
next started. Final list-sessions reported no owned server; process inspection
showed no surviving owned demo or tmux process. No failure/fix captures were
needed because this designer look found no failure.
