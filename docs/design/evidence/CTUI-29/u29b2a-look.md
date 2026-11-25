# U29b2a: start chord from its settings files

Handed source: `f2cc240`. It was run from a clean archive of that commit beside the original at `577b581` (v0.71.0), using the same isolated `XDG_CONFIG_HOME` and `XDG_STATE_HOME` and the same working directory. The user file holds `{"colour":1,"copyOnSelect":false,"agents":{"fake":{"command":["bun","../chord/tests/fixtures/fake_agent/main.ts"]}}}`. The project `.chord/settings.json` holds `{"theme":"dark","agent":"fake","agents":{"fake":{"permissionMode":"yolo"}}}`. The original was run with `bun --define 'process.env.NODE_ENV:"production"' ../chord/src/main.tsx`. Captures replace the local checkout path with `../chord`.

The look passes. The one difference found was taken to main, which made it a known difference (CTUI-57).

## Same as the original

- `picker-{o,p}-*`: with no agent named, both open the agent picker with `fake` (settings.agent) highlighted. The text is identical at 120x40 and 80x24, apart from the version.
- `window-{o,p}-*` and `pair-window-*`: after Enter, the transcript starts with the two settings warnings (amber `⏺`, user file `unknown key "colour"`, project file `"theme" is read only from …`) and then the red refusal `Could not start in yolo mode, set in .chord/settings.json: the agent offers default, acceptEdits, plan`. Text, order and foreground colours are identical at 120x40. The original also paints the space after the gutter white, which draws nothing.
- `agents-{o,p}.txt`: byte-identical, including `fake  from settings  settings  bun ../chord/…` and exit 0.
- `refusal-{o,p}.{out,err}`, with `"command": 1` in the project file and `chord fake`: identical stderr lines (the three problems, then `chord: fake not started: agents.fake.command in .chord/settings.json: expected a string, got a number`) and exit 1.
- `help-{o,p}.txt`: `-m/--model`, `--effort` and `--permission-mode` carry the original's wording. The help's layout differs from cliffy's, as it did before this unit.

## Known difference, CTUI-57

At 80x24 the original wraps the theme warning after a `/` inside the path (`…read only from /tmp/…/cfg/chord/` + `settings.json, ignored`). The port's Text breaks only at spaces and moves the whole path down a line. The original draws the row as a plain OpenTUI `<text>` (`Failure`, `src/ui/transcript/tools/Tool.tsx:1005`). This is the framework's generic wrap, not settings code, and nothing in docs/decisions.md settles it. Main chose to keep it as a known difference and filed the framework task CTUI-57; the lead logs it in docs/decisions.md. It is not a finding for this unit.

## Not covered here

- The old differences, not from this unit: the header lacks `· /help`, and `--help` places `-r, --resume [id]`'s description 5 columns right.
- `copyOnSelect: false` needs a mouse drag and is left to the tests.
- The status-line problem count, `/new`, `agents --json` and `-C` are outside the unit.

All tmux sessions were killed, no Dart, bun or fake process was left, and the scratch directory was removed.
