# CHD-432 U2 captures

Taken on af6ab4d5 with `bun dev chord --fake`, prompt `claudebackground`,
Esc about half a second in.

| File | What it shows |
| --- | --- |
| `after-esc-120x40.txt`, `.ansi`, `after-esc-80x24.txt` | right after Esc: the group still `Running 2 agents…`, the tester (announced `cancel`) at `Bash(bun test)`, the explorer `Cancelled` from the adapter's own `idle`, `Interrupted by user`, and `1 agent still running` on the status line |
| `ended-120x40.txt` | about 5 s later: `2 agents ended · 1 cancelled`, the tester `Done` |
