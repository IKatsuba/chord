# CHD-532: startup agent picker screen acceptance

Designer accepts screen unit `c16dff73` on `CHD-532`: the actual unnamed
startup picker and transition to the fake conversation read clearly at
120×40 and 80×24. No blocking screen finding remains. This is a screen
look, not code review or the tester's acceptance.

## Exact provenance and safe fixture

Source ran the absolute Bun executable with `src/main.tsx -C <project>`;
compiled ran `dist/bun-darwin-arm64/chord -C <project>`. Neither invocation
supplied a named agent, `--fake`, `--qa` or `--agent-command`: those would
bypass this startup choice. The compiled SHA-256 was independently checked:
`40fadb70ca116f51bec0b5296b703fed90b29380b54cf1de6ce6d66ea0de99ae`.
Developer built it from the handed source with no later source changes.

Each actual CLI run used its own fixed
`/tmp/chord-qa.chd532-designer-<capture-prefix>` directory, with isolated
`project`, `config` and `state`. The project settings were:

```json
{
  "agent": "fixture",
  "mouse": false,
  "agents": {
    "fixture": {
      "command": ["<absolute Bun executable>", "<checkout>/tests/fixtures/startup_agent.ts"],
      "model": "fake-small"
    }
  }
}
```

Environment: `NO_COLOR` removed, `XDG_CONFIG_HOME=<scratch>/config`,
`XDG_STATE_HOME=<scratch>/state`, `CHORD_RESOURCE_FIXTURE=true`, and
`CHORD_START_LOG=<scratch>/starts`. The fake wrapper records one PID before
importing the existing fake agent. The project-scoped `mouse` entry in the
handed fixture is ignored by existing settings policy; the selected screens
truthfully show that warning. No mouse or clipboard operation was performed.

Each owned tmux session used its capture prefix after `chd532-designer-`.
Startup waited for `Select agent`. Text used `send-keys -l`; Enter was a
separate command. No real catalog entry was started: the selected `fixture`
and `claude` entries both invoked the explicit fake command. Registry order
and PATH availability labels are the unchanged actual catalog, not a synthetic
installed-only list. No fetch, installation, authentication or provider call
was used.

## Bounded checks

| Capture prefix | Actual run and result |
| --- | --- |
| `source-120x40` | Configured last candidate `fixture` visible and highlighted. Twelve Up presses cross the visible window boundary; twelve Down presses return to `fixture`. Enter starts one fake PID, then `text`, Enter produces `Hello, world.` with `Fake Small`. |
| `binary-80x24` | Same configured last candidate visible in the six-row window. Enter starts one fake PID; `text`, Enter gives the normal fake reply and selected-agent header. |
| `binary-120x40-cancel` | Unknown unselected default falls back to first-candidate highlight. Escape exits with status 0 and no fake PID log. Nothing is selected or started. |
| `source-80x24-missing` | Preferred `fx` with PATH set to an empty scratch directory shows `not found`. Enter produces existing missing-command refusal and status 1; no fake PID log. |
| `source-80x24-default` | No `agent` setting; `claude` is safely overridden with the fake command/model. Built-in default highlights the fifth catalog entry. After two Up presses move highlight to entry 3, literal `5` selects absolute entry 5 and starts exactly one fake process. |

Before selection or cancellation, the start log was absent. Successful runs
quit using Ctrl+C twice after the reply. Project settings bytes were compared
before/after each run and stayed identical. These observations prove fake
process counts, not independent instrumentation of every startup factory;
the developer's actual-handler factory tests are separate evidence.

Before choice, the header says only `chord` and the directory; no agent,
model, status or prompt implies a running session. The title, highlighted
row, overflow indicators and key hint remain visible at both sizes. After
choice, the ordinary selected-agent header, prompt and status replace the
picker cleanly. Short/empty candidate lists remain developer component-test
proofs; no alternate production catalog or new component fixture was made
for this look. Other preserved CLI routes and shortcut coverage belong to
the developer/tester checks; no broad CLI matrix was repeated here.

## Evidence, colors and cleanup

Every file in [screen/](screen/) is a full-window live tmux frame: `.txt`
from `capture-pane -p`, `.ansi` from `capture-pane -p -e`, and `.png` rendered
from matching ANSI with existing AnsiUp/Puppeteer dependencies. Ten final
PNGs were individually opened and inspected. Rendering uses Menlo 13px/18px,
foreground `#e4e4e4`, background `#16171b`, preserving captured ANSI colors.
The highlight uses dark `permission` RGB `177;185;249`; secondary text is
dim. No new border or agent identity color appears before choice. Native
terminal cursor pixels are outside these cell captures. The refused frame
includes tmux's dead-pane status after the application exits.

All owned sessions were killed, owned fake processes exited, fixed scratch
directories and temporary helpers were removed. No live provider, native
clipboard operation, physical-key gesture, light theme or cross-target
binary was checked. No application tests or static suite were repeated by
designer. The original short scrolling sample moved only the highlight;
it was replaced by the final twelve-step sample that crosses the window.

Before committing, the reserved
`nice -n 19 bun test --isolate --timeout=60000 ./tests/privacy_test.ts`
passed: 8 tests, 0 failures, 36 expectations, 4.38 seconds. Changed-file
formatting and staged diff whitespace checks passed.
