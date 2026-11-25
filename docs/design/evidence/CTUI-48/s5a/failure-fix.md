# Convergence failure-to-fix record

Evidence inputs were explicitly handed by developer; designer did not recreate
old checkouts, substitute production files or rerun a failing baseline.
Sanitized excerpts retain original log labels and line numbers in
sanitized-failure-fix-excerpts.txt. developer-reached-commands.txt preserves the
handed commands/results; these are developer results, not designer test runs.
Raw probe snapshots and private stack paths are not shipped.

| Stage | Source and result | Evidence |
| --- | --- | --- |
| Proven production /sta failure | Baseline `74cdd9fac42ade6e1e7e6280c7e85f70fca70826`; developer's authorized exact substitution of focus.dart/focus_manager.dart removed the then-current production deltas. Expected /sta, actual /t at both sizes. | baseline-test.log excerpts |
| First convergence repair attempt | Uncommitted repair chain on that baseline, not an independently addressable commit. Developer reported partial /ta behavior; the retained diagnostic independently records handling false on character s. | initial-command-diagnostic.log excerpts |
| Second repair plus S5a chain | Uncommitted work based on the same baseline. Command completion improved, but sibling binding and prompt Ctrl-C convergence still failed. This is not a baseline-proven Ctrl-C defect. | sibling-red.log, quit-chain.log, quit-chain-deltas.log and quit-diagnostic.log excerpts |
| Accepted bounded repairs | Signed `f7727620475a9e0f3ece5e765c5a99093632769e`; combined clean S5a acceptance head `101826632dc3a6573405fd362ec73be66703ecd5`. Scoped subtree draining, nonredundant overlay sync and positioned/clipped gutter; editor alone sets prompt height. | Handed focused repair results and final root823/port394 passes; fixed-head runtime captures |

The baseline reproduction command, from example/chord:

```sh
dart test test/ui/app/commands_geometry_test.dart -n 'mode keeps original precedence' --reporter failures-only
```

The original-history Ctrl-C chain is labelled by
`test/ui/app/prompt_window_test.dart` in the handed diagnostics. The final
reached run includes that test plus commands_geometry_test.dart,
commands_convergence_test.dart and prompt_convergence_test.dart. Developer's
focused comparison reported sibling/input geometry11, command geometry/
convergence8, and prompt convergence/input/original history29 passed. Final
reached aggregates reported root823 and port394, analyze clean, format520 with
zero changes and diff-check clean. See the handed command record for exact
aggregate file lists and flags; no whole-suite or compile result is inferred.

The fixed-head runtime checks in acceptance.md demonstrate intact /sta, normal
Tab acceptance, denied Tab at height5 followed by restored acceptance, prompt
2→1/1→3 geometry, matched original prompt cells/caret columns and status0 exits
for same-batch clear/quit and multiline-paste/quit at both sizes. They do not
prove the internal two-pass count; exact reached tests cover that bound.

The generic guarantee that input can never be lost when geometry settlement
is exhausted remains main's separate follow-up. These local repairs add no
third pass, replay, fallback route or global input scheduler, and this record
makes no claim that the generic issue is fixed.
