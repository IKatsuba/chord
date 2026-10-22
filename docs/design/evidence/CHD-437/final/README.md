# CHD-437: the final screens

The whole chord window on the fake agent, from the built code (chd-437 at
452e44b5), dark theme, each as a `.ansi` file with its colours (`cat` it in
a terminal, or `less -R`) and a `.txt` beside it. The fake agent's name is
`fake`; a live one says `cursor` or `grok` where these say `fake`.

| File | What it shows |
| --- | --- |
| `1-cursor-plan-120x40` | cursor's plan (`cursorplan`): `⏺ Plan(Route updates by session)`, its overview and markdown, the `Move` phase's todos, then `Todos`, with `☐ ◐ ☒`; under it the `Approve Plan` box with cursor's two choices and the Note. |
| `1-cursor-plan-80x24` | The same at 80×24: the box keeps its room, so the transcript shows the plan's tail (`Todos`). |
| `1-cursor-plan-paged-up-80x24` | At 80×24 after `pageup` (the transcript's while the box waits): the plan's steps and the `Move` phase in sight. |
| `2-grok-plan-note-120x40` | grok's plan (`grokplan`) and its box with the third choice, `No, and leave plan mode`, and a Note typed on the Note row. |
| `2-grok-plan-note-80x24` | The same at 80×24: the typed Note wraps under its own text, the hint wraps at its spaces. |
