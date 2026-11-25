# CTUI-42 U2 narrow fallback recheck

Handed fix: `038bc59`; exact-case fixture: signed `787349e`. Reviewer
identified a blocker after the earlier visual look: orphan relocation could
make a table cell wider than its content column at 16 columns. The earlier
120x40/80x24 pass did not establish this narrow case.

Designer ran `dart run example/markdown_wrap.dart` at 120x40 and 80x24 in
an owned tmux session. Both plain captures exactly match the earlier passed
fixture captures; ANSI captures are retained as u2-fix-markdown-*.

Designer then ran `dart run example/markdown_wrap.dart --narrow` at 16x40.
The two-row one-column table shows `alpha wit…` and `one two t…`, with a
straight right border on both rows and the header, and an aligned bottom.
No orphan phrase crosses the border. This is readable truncation at the
existing table fallback width.

The exact same source was passed to the original's exported `markdown`
function with width 16 and colors enabled, rendered directly into another
owned 16x40 tmux pane through bun -e. The source was:

```markdown
| Holds |
|---|
| alpha with abcdefgh |
| one two three four |
```

This original reference is a direct call of the original production
renderer, not its full app window or a new fake scenario. No file under the
original checkout was written. Plain narrow captures match exactly, with
side-by-side evidence in u2-fix-narrow-comparison-16x40.txt. Both ANSI
captures show the same dim-border/plain-cell presentation.

Result: visual pass for the handed fix, including the exact blocker and
retained required sizes. No code audit, automated tests, full suite or
physical-device claim is made. Port fixtures quit with Ctrl+Q, the bounded
original renderer pane was killed, and all three owned fix sessions were
checked absent or killed. Await reviewer handoff to tester.
