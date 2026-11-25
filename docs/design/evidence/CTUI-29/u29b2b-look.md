# U29b2b: the agents offeredAgents offers

Handed source: `2cd717d`, with the fix `d263020`. Each was run from a clean archive of its exact commit beside the original at `577b581`, from the same working directory with isolated config and state. Window start, no agent named, Esc to leave. Settings cases in the user file:

- A: `{"offeredAgents":["codex","nope","claude","typo"]}`
- B: `{"offeredAgents":["nope"]}` (nothing known)
- C (fix check only): `["codex","nope-a-very-long-unknown-agent-name","claude","typo-another-long-name","x1","x2"]`

The look passes on `d263020`.

## Same as the original

- `fixed-start-{o,p}-{A,B,C}-{120x40,80x24,40x24}`: identical text at every size, apart from the version. A lists `1. codex · Codex` and `2. claude · Claude Agent`, with the dim `Unknown in offeredAgents: nope, typo` row under the hint after one blank row. B shows `No agents available`, the dim sentence and `Esc to cancel`. C's note at 40x24 is `Unknown in offer...ent-name, +3 more` in both.
- `start-{o,p}-A-80x16`, `-80x12` and `-80x12to24` (first pass, `2cd717d`): the note gives way to the list at 80x12 and returns at the same row when grown to 80x24, identically in both.
- `stderr-{o,p}-*`: identical lines, `chord: <user file>: "offeredAgents": no agent named <n>, left out`.
- Both note rows are dim with the default foreground, as in the original.

## Finding, fixed

On `2cd717d` at 40x24, B cut the sentence at its end (`offeredAgents in settings.json name…`). The original's CUT is OpenTUI `truncate`, `offeredAgents in...gent chord knows.`; see `pair-B-40x24-failing.txt`. Per the CTUI-16 decision, the sentence and the note now use `TextOverflow.middle` (`d263020`), and `fixed-pair-{B,C}-40x24.txt` match.

All tmux sessions were killed, and no Dart, bun or fake process was left. The scratch directory was removed.
