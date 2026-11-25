# U55a and U55b: a paragraph line's leading whitespace

Handed source: 55a `3a52328` (framework Markdown) and 55b `90372ef` (the port's steering replay fixture and test). Both pass the designer look at 120x40 and 80x24. Each was run from a clean archive of its exact commit, never from the shared tree.

## 55a: framework Markdown

`example/markdown.dart` has no paragraph that starts with whitespace, so a probe copy of it was run with the sample replaced by `u55a-probe-sample.dart.txt`. That sample covers a first chunk ` Late work 1.`, a hard break followed by three spaces, a soft line indented by three, ` **b** x`, a loose list item's second paragraph, a quote continuation, indented code and fenced code. The probe was run on `bdda73f` (before) and `3a52328` (after).

- Before (`u55a-probe-before-*`): every case keeps its whitespace, ` Late work 1.`, `   b, after three spaces`, ` b x`, and `   x` under `- i`.
- After (`u55a-probe-after-*`): every paragraph line starts at the block's left edge. The loose item's paragraph hangs under its item text (`  x`), not one cell further. The quote is unchanged. Both code blocks keep their indentation exactly.
- Streaming (`u55a-probe-after-stream-early-80x24`): the first frame after Ctrl+S is `Late work 1. A first ch` at 5%, with no leading cell, so the trim holds while growing.
- The unchanged demo's captures (`u55a-demo-before-*`, `u55a-demo-after-*`) are byte-identical text and ANSI at both sizes, so nothing else moved.

## 55b: steering replay fixture

`dart run example/chord/tool/steering_replay.dart`, Ctrl+T (lone self-started closure), Ctrl+N (late work 1), Ctrl+N (late work 2). The input is the raw ` Late work N.` again.

- `u55b-port-alone-late-*` shows `⏺ Late work 1.` with one space, as the original's `u27b2-original-alone-late-*` from CTUI-27 does (same record). Side by side: `u55b-pair-alone-late-*` (original | port). The CTUI-27 residual `⏺  Late work 1.` is gone.
- `u55b-port-alone-late2-*`: the second chunk's space joins mid-paragraph, `⏺ Late work 1. Late work 2.`, as CTUI-27's work→late case already agreed.
- The remaining differences in the pair are the ones CTUI-27 already recorded. The standalone fixture has no header or prompt chrome and uses the full width, so its notice is cut two cells later (`goes as the …` against `goes as th…`). The original also paints its spaces white, which draws nothing.

## Citation

The upstream draft (`upstream-issue.md`) cites CommonMark 0.30 examples 222, 223 (paragraphs) and 636 (hard break). Example 642, which 55a's decision entry and test comment cite, is a raw HTML case in 0.30 and 0.31.2, so that citation was sent back to developer. The AST probe also showed that `HtmlRenderer` hides the gap with a per-line `trimLeft()`. The draft says so, because `markdownToHtml` alone looks correct.

## Cleanup

All tmux sessions of designer were killed, and no fixture or Dart process was left. The scratch archives sat outside the repository and were removed. No clipboard, terminal cursor or AOT claim is made.
