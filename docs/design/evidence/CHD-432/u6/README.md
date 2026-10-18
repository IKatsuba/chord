# CHD-432 U6 captures: unfinished calls after the refresh

Taken on main after 58444b63 with `bun dev chord --fake`, prompt `bashcut`,
which plays claude-agent-acp 0.93.0's `unfinished()` report
(`dist/tool-calls/renderer.js:472-486`).

| File | What it shows |
| --- | --- |
| `running-120x40.txt` | before Esc: `Bash(bun test)` `Running…`, `Read(package.json)` `Waiting…` |
| `cancelled-120x40.txt`, `.ansi`, `cancelled-80x24.txt` | Esc: both red `⏺`, `Error: The turn was cancelled before this tool call returned a result.` with the terminal's `(No output)`, and `Error: Claude stopped this tool call before it ran.`, then `Interrupted by user` |
| `unanswered-120x40.txt`, `unanswered-80x24.txt` | left alone: `Error: Claude ended the turn without returning a result for this tool.` |

## Against CHD-422 and CHD-417

- **"An unfinished call waits on nothing" (docs/decisions.md, CHD-254),
  which the study filed under CHD-422:** holds. After the turn no call
  says `Waiting…` or `Running…`; each ends red with the adapter's line,
  error role, whole and wrapped as CHD-422 draws a result. This reads
  better than the grey `Waiting…` it replaces: the person learns the call
  did not run. Accepted as sent.
- `(No output)` under the cancelled command is its terminal with no exit
  code and nothing written. It is true and stays.
- **CHD-417, from code, not seen on the fake:** CHD-417's cut-off sentence
  and note key on `_meta.claudeCode.nonExecutionKind: 'interrupted'`
  (`src/session/transcript/tools.ts:96-105`). 0.93.0's `unfinished()`
  report, which its own comment gives for a call "Claude switched to a
  steering message" before it ran, carries only the text "Claude stopped
  this tool call before it ran." and no `_meta`. A chord call cut off that
  way would read `Error: Claude stopped…` with no "Not delivered" sentence
  and no note to the agent. CHD-417's fake scenario plays the older shape,
  so this is unproven; raised with the lead.
