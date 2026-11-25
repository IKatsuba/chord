# Bounded U52b Escape/resize baseline observation

Exact production: `61d012cf319bd3fee9d533fc9c04a818546ea6d5`.
The approved fixture-only `bb3a6d2` overlay was present but the CLI route
was used. No U52c code was inspected or executed. The lead authorized one
overlapping Escape/resize attempt and one fresh32 separated control only.
No diagnostic loop, additional Escape or product repair was performed.

Both cases used the designer's identical UUID2 compact version1 record,
record timestamp1794963008680 and prompt, task cwd, isolated XDG state/config,
original fake through Bun, CHORD_FAKE_REFUSE_LOAD=1 and NO_COLOR removed.
The CLI loaded the saved UUID, failed, then received literal /resume and
Enter in separate invocations. Captures prove the picker was visible before
each Escape. Config hashes, reconstructable argv and corpus are in manifest.
The readiness assertion initially expected literal load; baseline wording
was cannot resume/Resource not found. That setup assertion was corrected
before any /resume or Escape/resize input and was not an overlap retry.

| Case | Input | Immediate | Settled |
| --- | --- | --- | --- |
| Overlap | Escape at80x24; resize32x10 | Picker visible12.737ms after resize | Still visible1034.575ms after resize |
| Fresh32 control | Start32x10; Escape; no resize | Picker visible11.439ms after Escape | Closed1040.918ms after Escape |

Overlap Escape completed at5.012ms; resize began20.052ms and ended27.471ms.
A requested10ms gap approximated the intervening original-resize command
in the designer's paired sequence; the actual gap was15.040ms. Timings are
retained rather than asserted identical to the designer's four-command run.
Immediate visibility is not treated as a settled failure. Fresh control
starts a separate CLI process/state at32x10; it does not reuse overlap state.

This establishes the same behavior on the already reviewed baseline under
this bounded timing. It does not assign a cause, blame U52c, or establish a
framework, parser or CTUI-51 defect. The designer's original577b581/current4a
paired observation remains separately scoped in evidence commit eae4bd2;
its approximately39.3second settlement was not repeated here. The lead's
approved follow-up repair requires its own normal handoff and tests.

Sanitized text captures have matching ANSI. Only displayed task/archive/
state/config root paths are replaced; replacement labels are not width
oracles. Ctrl+D closed both cases. No exact-archive CLI process or owned
tmux server remained; both isolated state/config roots and archive were
removed. No separate physical-isolate or whole-system census is claimed.
