# CHD-525: pre-edit source baseline

Eight full-window source frames were captured at unchanged HEAD
`9c595170e01fa266e4becd11ab198c115969f66b` on `CHD-525`, before the developer
changed App layout. The developer explicitly held that boundary until the
raw frames were secured, then was released immediately. These are baseline
observations, not acceptance evidence for the new layout.

At each size, the owned session `chd525-designer-baseline-<size>` ran:

```text
env -u NO_COLOR CHORD_RESOURCE_FIXTURE=true bun dev chord --fake
  --qa chd525-designer-baseline-<size>
```

This used the dev wrapper's fixed isolated directory
`/tmp/chord-qa.chd525-designer-baseline-<size>` and fixture resources only.
No live provider or clipboard operation occurred. No model prompt was sent.
The sizes were set by tmux and independently read back as 120×40 and 80×24.

After readiness, literal `/` opened commands. Escape dismissed the list,
retaining the exact `/` draft and its cursor/display height. Ctrl+U cleared
the draft; that empty closed state was captured, then literal `?` opened
help without changing the empty draft. Every pair uses the same session,
viewport, one-line draft height and permanent bottom content. The command
pair is captured open then closed; the help pair closed then open. There
are no agents, queue, working line, request or background frame in this
bounded baseline. The startup header is ordinary transcript content.

## Measured prompt border rows

Rows are one-based positions in the full terminal, top border then bottom.

| Viewport | Commands closed, `/` retained | Commands open, same `/` | Help closed, empty | Help open, same empty |
| --- | --- | --- | --- | --- |
| 120×40 | 37, 39 | 28, 30 | 37, 39 | 23, 25 |
| 80×24 | 21, 23 | 16, 18 | 21, 23 | 2, 4 |

Both transient regions currently occupy space below the prompt and displace
the permanent status. The command list shows ten rows wide and six narrow.
The narrow help panel scrolls and shows the existing three-lines-below rule.
These comparisons establish the current movement with equal draft height;
they establish nothing about proposed pressure allocation, combined busy
states, agent folding, file/agent completion or search.

Each capture stem has `.txt` from `tmux capture-pane -p`, `.ansi` from
`capture-pane -p -e`, and a matching `.png` rendered with the existing
AnsiUp/Puppeteer dependencies. PNG rendering uses Menlo 13px/18px,
foreground `#e4e4e4`, background `#16171b` and captured ANSI color. Every final
PNG was opened and inspected. The separate hardware cursor is outside tmux
cell captures. The source frame text and ANSI were not edited.

The eight files per format are the two sizes crossed with `commands-open`,
`commands-closed`, `help-closed`, `help-open`. Source HEAD was checked again
after capture and remained unchanged. Both owned sessions were killed and
their fixed QA directories removed before the edit hold was released.
No application tests, static suite, compiled binary or real resource was
used for this pre-edit capture. Later implementation evidence must retain
its own commit and fixture provenance rather than relabel these frames.

Before committing, the reserved
`nice -n 19 bun test --isolate --timeout=60000 ./tests/privacy_test.ts`
passed: 8 tests, 0 failures, 36 expectations, 4.07 seconds. Changed-file
formatting and staged diff whitespace checks passed.
