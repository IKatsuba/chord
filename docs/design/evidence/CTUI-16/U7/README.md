# U7: live fake window visual pass

Developer handover `86bc0ef`. Original references use `577b581` under
../original/. Checked at 120x40 and 80x24 in designer-owned tmux sessions,
with NO_COLOR unset, TERM=xterm-256color and COLORTERM=truecolor.
Plain captures use capture-pane -p; `.ansi.txt` adds -e. Saved captures
are unaltered and contain only a neutral QA directory in the header.

First ran the requested root command:
`dart run example/chord/tool/dev.dart chord --fake`. Its child cwd is
explicitly forced to the repository root, even if the runner starts
elsewhere. For unaltered neutral-directory captures, the lead accepted
running the equivalent child argv from an owned QA directory: Dart runs
the port bin/chord.dart with `fake --agent-command` naming bun and the
original fake. XDG_STATE_HOME is owned QA state. This uses the same fake
and live connection/window; no implementation file was changed for QA.

Each scenario starts a fresh live window. Prompts were sent literally
with send-keys -l and Enter in a separate call: text, markdown, long,
thought, tools, calls, edit, rewrite, bash, shell, plan, todos, error,
turnfailed, and slow followed by Esc. No active permission scenario ran.
Expanded captures follow ctrl+o; Home exposes the beginning. Long is
captured while following, after PageUp while output continues, after
completion and End, then Home. Slow records partial output, cancellation
and a new successful text turn after cancellation. Timing-dependent text,
counts and viewport positions are observations, not deterministic goldens.

Visual result: pass for U7's authorized scope. Empty connected state has
no connected receipt. Input submits a prompt, clears, and remains usable.
Thought collapse/expansion, reply/list spacing, tool status/headlines,
Read previews and hidden counts, terminal tails/exit notes, full diffs,
finished plans, red failures and attached cancellation match original
presentation at both sizes. The long stream follows; PageUp holds with
new-output/count and End resumes. A second send after Esc succeeds.
`compare-*` puts original and live port captures side by side at equal
sizes; differences in fixed window furniture change available transcript
height and therefore which source rows fit.

Authorized differences and limits:

- The owner chose an interim one-line input for CTUI-16. The port retains
  an interim header/quit footer; original start/header, multiline prompt,
  status/spinner and full shortcuts surfaces belong to their later tasks.
- CTUI-4 already approved six-cell code-box furniture, wrapped code and
  omitted copy/run buttons. Those existing framework differences remain.
- The same-width Markdown table wraps some cell words differently from
  the original (for example `closing a` / `session` versus `closing` /
  `a session`). Side-by-side captures preserve it. The lead explicitly
  assigned this existing CTUI-4 difference to a separate framework
  follow-up and said it does not block U7. At 80 columns the original
  also breaks the displayed ACP URL after `https://`, while the framework
  keeps that URL together on the next row. The lead explicitly confirmed
  both table and URL wrapping as one CTUI-4 follow-up outside this slice.
- Live permissions, history/queue UI, idle agent exit and compiled launch
  were not exercised visually here. No claim of those states is made.

All scenario sessions quit with ctrl+d; the initial root-command session
quit with ctrl+c. Owned sessions, fake processes and QA state were checked
and cleaned up. No original source was edited. This is a visual pass, not
an automated suite run, performance measurement or full-slice acceptance.
