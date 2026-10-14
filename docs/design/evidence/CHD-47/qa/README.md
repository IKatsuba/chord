# CHD-47 independent QA

Checked the combined model-picker change at `b027f09`, after design and review.
The approved appearance was not reconsidered. No live agent was started.

## Commands run

- `deno task check`: 290 tests and 20 steps passed. The sandbox attempt could
  not spawn `ps` for existing cleanup helpers; the unchanged command passed
  with process access.
- `deno task compile`: macOS arm64 binary produced and started in tmux.
- Ran that binary with `fake`, the repository fake-agent command, a neutral
  temporary `-C` directory and an isolated `XDG_STATE_HOME`.
- Used `tmux send-keys` only, separate literal input and Enter calls, captures
  after settling, and `tmux resize-window` between 120x40 and 80x24.
- Read session tests in the passing check: advertised models/order/current,
  `setModel` and readback after a turn, and refusal of an unadvertised model.
- Checked terminal flags with `tmux list-panes`, before/after `stty -g`, raw
  terminal output, and owned process exit with `ps`; killed the QA tmux session.
- `git diff --check` and a private-path search over these captures.

## Observed behavior

The repository fake offers two models. At 120x40, `/model`, Down, Enter closes
it and the status changes to Fake Small. Reopening marks and highlights model
2. Resizing that open picker to 80x24 preserves it; digit `1` switches back to
Fake Large. The four acceptance captures include plain text and ANSI versions.

Enter on the current model closes the picker. Esc closes it and typing reaches
the prompt again. `error` shows the fake agent's intentional failure. During
`slow`, opening `/model` and pressing Esc closes only the picker: the working
turn continues. A second Esc interrupts the turn, with `Interrupted by user`.

Additional checks used temporary copies of the same SDK fake, without changing
repository fixtures. Relative fixture imports were resolved to the originals;
all variants ran under Deno with the project configuration:

- Long list: replace `AVAILABLE_MODELS` with twelve `qa-1` through `qa-12`
  choices named QA Model 1 through QA Model 12, and the initial current-model
  fallback with `qa-11`. At 80x24 it opens with model 11 in sight and six hidden.
  Individually spaced Up/Down or j/k keys stop at both ends. The captured top
  has rows 1-6 and a down marker; the captured bottom has rows 7-12 and an up
  marker. Resizing to 120x40 shows ten rows and two hidden. From a scrolled
  window, digit `2` switches to QA Model 2, rather than the second visible row.
- Request recording: append the value on entry to the fake's existing
  `session/set_config_option` handler. The digit switch recorded exactly
  `qa-2`; reopening and Enter on the current model added no request.
- Refusal: throw an SDK `RequestError(-32603, 'Model refused by QA fake.')`
  in that handler. Picking the advertised second model draws the error in the
  transcript and leaves Fake Large in the status line.
- Permission precedence: delay the existing `permission` scenario by two
  seconds, open the picker during that delay, then let permission arrive.
  Permission replaces the picker. Digit `1` answers Allow, records no model
  request, and the picker returns. Esc closes it afterwards.
- No models: remove the model config option from `configOptions`. `/model`
  says the agent offers no models, and Esc closes it.

Ctrl+D and two separate Ctrl+C presses both returned to a responsive shell,
with `cursor_flag=1` and `alternate_on=0`. The original fake run's `stty -g`
was identical before and after. A subsequent shell launch began with macOS's
transient PENDIN bit set; that bit was cleared afterwards, with all other
terminal settings identical. Raw output contains alternate-screen exit and
cursor-show sequences. `ps` found no remaining QA binary or fake-agent process.

No implementation changes or new findings. Existing follow-ups CHD-58
(model-switch transcript record), CHD-59 (hidden-count direction wording) and
CHD-52 (unrelated CHD-32 evidence privacy) remain separate. The pre-existing
untracked CHD-32 directory was not modified or staged.
