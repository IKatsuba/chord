# CTUI-70 evidence: a form block taller than maxRows

Commit 2ef3a195, against docs/design/CTUI-70.md. Framework only: no
original to compare (the original has the defect; the design departs).
Captured in tmux at 120x40 and 80x24:

    dart run example/form.dart --narrow --long-list

- `*-1-open-h1`: ↓ five times to Region, Space: options 1–4 and
  `↓ 8 more options`, between `↑ 5 more fields` and `↓ 1 more field`.
- `*-2-h7`: ↓ six times: `↑ 4 more options`, 5–7 with the highlight on 7,
  `↓ 5 more options`.
- `*-3-h12`: the last option: `↑ 8 more options`, 9–12.
- `*-4-refused`: Accept with problems; a cut-free view, as before.
- `*-5-problem-open`: Region with its `Required` shown, list open: options
  1–3, `↓ 9 more options`, then the note in the error colour.

Every state matches the design's mocks row for row (the example indents
the form one cell). In the `.ansi` captures the option count rows are dim,
at the options' label column. Eight rows at most in every state.
