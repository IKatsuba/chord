# U52e: cancel focus after disappearing choices

Exact handed fix: signed `0f823adbc576a4696e128afefef0e188b22d31b3`.
Designer live fix handback PASS to reviewer for this finding. No code audit,
headless execution or broad framework/parser claim is made. Original failure
and baseline findings remain intact in eae4bd2 and tester `01bf5ad`.

Ran exact source archived inside build with self-package roots redirected,
external resolved packages reused, no pub get and no concurrent source.
Original source head remains `577b581`. Used the unchanged UUID/timestamp/
record/launch corpus in u52c-repro-corpus.json, isolated state/config, original
fake load refusal and same task cwd. The only production variable is the
handed focus fix; synthetic age can advance with wall time in both windows.

Both overlays are confirmed visible at 80x24. The same sequential operations
send Escape to original, Escape to port, resize original to 32x10 and resize
port to 32x10. Immediate captures show unsettled rendering and are retained
without using them as a result. After explicit 1-second sleep and subsequent
normal parser/frame settlement, BOTH overlays are closed and both failed
prompts are visible. Exact command and capture timings remain in
u52e-escape-resize-recheck.json. No extra Escape was needed after overlap.

Closed both processes, relaunched fresh at 32x10 with the same corpus, opened
both pickers and sent Escape separately without resize. BOTH close in this
fresh control as before. Text/ANSI before/immediate/settled/control pairs
and side-by-side settled comparisons are retained. Existing plain-Text
wrapping differences and the accepted original hint-over-border slip remain;
this fix changes cancel ownership, not those render policies.

Developer-handed build/ctui52-escape/before.log and after.log are retained
byte-for-byte as u52e-developer-before.log/after.log, with SHA256 provenance.
They show the original three-case headless red/green output; they are not
presented as designer-run tests or as the full 127-test command result.
Developer separately reports 127 reached tests plus both statics clean.
Reviewer/tester still own exact source correctness and cache/source guards.

All original/port/control processes exited cooperatively; owned tmux servers
ended, no relevant Dart/Bun/fake process remained. Isolated state/config and
exact archive were removed. No real agent/model/physical terminal or AOT
measurement was used. This closes the designer's U52c round 1 overlap finding;
U52c wording evidence remains separately scoped, and full CTUI-52 readiness still
requires the remaining U52d header follow-up and reviewer/tester gates.

Copied developer logs preserve their original whitespace byte-for-byte; the
scoped whitespace check excludes only that raw before.log and terminal blank
rows at EOF. Their hashes remain verified against the handed originals.
