# CTUI-16 original references

Original commit: `577b58167672e12c999aeaf4eed2a1a988513dc2`.
The original tree was clean before and after capture. No original files
were edited. These are original runtime references, not a port acceptance
result.

Ran `bun dev chord --fake --qa <name>` from the original checkout, in
fresh designer-owned tmux sessions at 120x40 and 80x24. Each prompt was
sent with send-keys -l, then Enter in a separate call. Plain captures use
capture-pane -p; `.ansi.txt` adds -e to retain attributes and colors.
The root captures unset NO_COLOR and set TERM=xterm-256color and
COLORTERM=truecolor. `plain/` retains the initial NO_COLOR=1 references.
Both sets use the fake's default five-millisecond step interval.

Prompts: text, markdown, long, thought, tools, calls, edit, rewrite, bash,
shell, todos, error, turnfailed, and slow followed by Esc. `plan` is added
because current `todos` only reports `todo tools: 1`; `plan` produces the
completed checklist. No permission scenario was run.

The unqualified scenario captures show the completed turn, except slow,
whose files explicitly name working/cancelled. `expanded` follows ctrl+o.
`home` follows Home; rewrite-home follows expansion and Home. For long,
`streaming` follows the bottom before completion, `paused-streaming`
follows Shift+Up while the reply continues, the unqualified capture follows
End after completion, and `home` then shows the beginning and below-rule.
Markdown also has a streaming capture while its fence is still growing.
Timing-dependent elapsed values and partial text are observations of that
frame, not deterministic goldens.

Visual reference points:

- User `›`, reply `⏺`, collapsed `∴ Thinking…`, italic expanded thought,
  and a blank row between blocks.
- `calls` shows a three-line Read preview with `… +4 lines (ctrl+o to
  expand)`, a wrapped Bash headline and a failed Read result.
- Edit headline includes full additions/removals. Changed rows have
  colored signs and full-width tints; long source wraps under the code
  column. `rewrite` displays all diff hunks both before and after ctrl+o.
  Current tools/tools.ts passes true to diffView for ordinary diff content;
  the ten-row helper's existence does not make those tools fold.
- Completed shell output keeps its last three lines, with the hidden-line
  hint and Exit code 1 below; expanded output shows the whole terminal.
- Errors use red marker and text in the color captures. Esc on slow keeps
  the partial reply and appends `⎿ Interrupted by user`.
- A paused stream says `new output`, reports lines below and offers End;
  an idle scrolled transcript retains the count without `new output`.

The logo and footer belong to the original window; CTUI-16's interim input
and deferred start/status work must be assessed against their authorized
scope. These captures do not decide exceptions for other screen content.
Each owned tmux session was killed after capture; cleanup was checked.
