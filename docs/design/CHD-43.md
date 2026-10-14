# CHD-43 — Where the permission mode sits on the status line

The mode decides what the agent may do without asking, so it is the state on the
status line that matters most when it is not the default. Claude Code puts it at
the left edge of the line, under the prompt box. It takes the place of the
shortcut hint, in the mode's own colour, and a dim `(shift+tab to cycle)` follows
it. Claude Code 2.x at 120 columns, after each shift+tab:

```
  ⏵⏵ auto mode on (shift+tab to cycle)          yellow  (38;5;220)
  ⏸ manual mode on                              dim, no hint
  ⏵⏵ accept edits on (shift+tab to cycle)       lavender (38;5;147)
  ⏸ plan mode on (shift+tab to cycle)           teal    (38;5;73)
```

The first build of CHD-43 (a5cfa15) put the mode at the far right instead, after
the model name and joined to it with ` · `. That reads as a fact about the model,
and the eye looks there last. It is also the end of the line that runs out of
room first. A long model name with `⏵⏵ bypass permissions on` pushes the mode to
the edge at 80 columns. Nothing on screen says that shift+tab changes it.

## The shape

The mode goes on the left. When the agent is in a mode other than its default,
the mode takes the place of `? for shortcuts`. The model stays on the right.

120×40, accept edits:

```
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ⏵⏵ accept edits on (shift+tab to cycle)                                          Fake Large with a 1M context window
```

80×24, plan (`⏸ plan mode on` is teal, and the hint and the model are dim):

```
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ⏸ plan mode on (shift+tab to cycle)       Fake Large with a 1M context window
```

## States

- **Default mode, or an agent with no modes:** `? for shortcuts` on the left,
  the model on the right, the same as before CHD-43.
- **Non-default mode, empty draft:** the mode, then the hint, on the left.
- **Non-default mode, typing:** the mode stays, because a draft hides only the
  shortcut hint, not the state.
- **Narrow:** the dim `(shift+tab to cycle)` goes first, then the model name is
  cut with `…`. The mode itself is never cut.
- **Agent changes the mode itself** (leaving plan): the line goes back to
  `? for shortcuts`, as it does now.
- **A refused set_mode:** an error line in the transcript, and the status line
  stays where it was, as it does now.

## Naming a mode chord has no words for

Claude's ids keep Claude Code's words: `accept edits on`, `plan mode on`,
`bypass permissions on`, `auto mode on`. Any other mode reads as the agent's
own name for it, lowercased, then `mode on`. Codex's `Read Only` becomes
`read only mode on`. The agent's name is the one its user knows, and the id is
not meant to be read by people. These modes use the `⏵⏵` glyph and the dim
colour. chord does not guess whether a mode is safe.

## Keys

`shift + tab to cycle modes` is in the shortcuts panel (it is there now, at 80
and at 120).
