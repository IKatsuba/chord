# /cost over the whole window: unit 17, commit 3d7a8cc7

- `orig-120x40-live.txt`: `../chord`, `bun dev chord --fake --qa <name>`
  with `CHORD_FAKE_CHILD_RUNTIME=fake`, `agentsquiet`, then `/cost`.
- `orig-80x24-closed.*`: the same window at 80x24, `docs` closed from the
  list (↓ to it, `x`, `x`), then `/cost`: `agent, closed`.
- `port-*-closed-test.txt`: the port's screens from
  `test/ui/app/cost_agents_window_test.dart` at the commit (a hidden child
  `parser`, a closed `docs`), printed. By hand the port cannot open the
  fake's children at this commit (`No agent named fake`), so no live run.

The table matches: the empty row after the session's rows, the heading,
the cost and token columns right-aligned, `agent` and `agent, closed`, the
Total row, the note naming main by its agent (`fake not reported`, as
`sum` in `src/ui/transcript/spend.ts`) and wrapping between its parts at
80 columns (`noteLines` in `src/ui/transcript/spend_table.ts`). The
figures differ only because the test's state reports no cost.

## Live through the port's runner: unit 34

Since commit 7dc1d9b2 the port opens the fake's children on `fake`, so
the set above is now also taken live, from both programs, at 120x40 and
80x24. The original: `CHORD_FAKE_CHILD_RUNTIME=fake bun dev chord --fake
--qa <name>` in `../chord`; the port: the same variable, `dart run
example/chord/tool/dev.dart chord --fake` from the repository's root. The
QA directory and the repository's path are relabelled `<project>`. In
each, prompt `agentsquiet`, then:

- `*-<size>-run-live.*`: `/cost` with parser and docs open: `agent` on
  each. Match at both sizes.
- `*-<size>-run-closed.*`: ↓ ↓ ↓ to docs, `x`, `x` (docs waits on its
  permission, so the second press stops and closes it), Esc, `/cost`:
  `agent, closed`. The table matches at both sizes. chord's message to
  main differs: the original's `The person closed docs (fake, id …)`, the
  port's `(fake · fake-large, id …)`, which also wraps one word sooner at
  80 columns. Kept on purpose: the port names the child's current
  model, where the original looks it up after the child is dropped (see
  `docs/decisions.md`, "the person's close note names the child's current
  model").
- `*-<size>-run-retired.*`: then `/clear`, `/cost`: main's spend before
  the clear as `before /clear`, main `not reported`. Differs: the original
  closes parser on `/clear`, so its list is gone and parser's row reads
  `agent, closed` after docs'; the port keeps parser open through
  `/clear`, its row `agent` above docs', and draws the list (main and
  parser) under the status line.

The earlier sentence that the port cannot open the fake's children no
longer holds; the `port-*-closed-test.txt` screens stay as they were taken.
