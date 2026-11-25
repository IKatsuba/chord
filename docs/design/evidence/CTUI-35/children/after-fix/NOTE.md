# A task in its call's place: commit a43973e0

Live, the port (`bin/chord.dart fake --agent-command <fake>`, a clean
export of the commit) and the original (`src/main.tsx fake
--agent-command <fake>`), each on a state directory of its own,
`CHORD_FAKE_CHILD_RUNTIME=fake`. `tasktwo` at 80x24, then the window at
120x40 and `taskcost`.

`tasktwo` is one `⏺ Running 2 agents… (ctrl+o to expand)` group with
`├─`/`└─` in both, and `taskcost` one `Agent(Count the cost) · fake`
block with no call row of its own; equal row for row but for the
`background` row, held back until CTUI-36.

## Main's /clear closes its children: commit f562b01f

The same runs: `agentsquiet`, `/clear`, `/cost`, at 80x24 then the window
at 120x40 (`*-main-clear-cost.*`). In both the list is gone, and the
table reads `main`, `before /clear $0.0375`, `docs … agent, closed`,
`parser $0.0125 … agent, closed`, `Total $0.0500`; equal row for row.

## The asker row on the box ctrl+x a opens: commit 524e5220

`agentsquiet`, then ctrl+x a, at 80x24 (`*-attend-asker.*`): the box
starts `docs asks`, `docs` bold in docs' colour and ` asks` plain, in
both; the rest of the screen equal row for row. One style differs, older
than this fix: the port draws the highlighted `1. Allow` bold (the
framework `Picker`'s highlight), the original only coloured.

## /resume closes the children (ffbb5b63); /clear on a picked child (524e5220, 34b39523)

`*-resume-closes-cost.txt`: a session `text`, quit; a new one,
`agentsquiet`, `/resume`, the earlier `text` session picked, `/cost`: the
list gone, `before /clear $0.0375`, `docs` and `parser` `agent, closed`,
`Total $0.0625`; equal row for row. In that run's picker the two `open
now` rows came parser, docs in the original and docs, parser in the port,
both `just now`; one run, so possibly timing.

`*-child-clear*.txt`: `agentsquiet`, parser picked, `/clear`: parser
keeps its place, colour and name with a fresh session; main shows `✓ new
reply` and, in its view, `← from chord ⎿ The person cleared parser's
context (fake · fake-small, id …). It is open with a fresh session and
knows nothing of earlier turns; your next message is its first.`; equal.
