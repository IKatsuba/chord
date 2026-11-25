# CTUI-36: monitors and the background view

The original's monitors (`monitor`, `stop_monitor`, `list_monitors`) and
its background summary line and view. The specification is `../chord`, to
the word: `src/session/{monitors,window_monitors,conversation}.ts`,
`src/server/tools.ts`, `src/ui/background/`, `src/ui/agents/agents.ts`
(`moveListFocus`, `summaryHint`), `src/ui/shortcuts/keys.ts`,
`src/ui/transcript/{message.ts,tools/chord.ts}`, `src/acp_agent.ts`,
`src/acp/{agent_app,host_fold}.ts`, their tests, and the original's
designs `docs/design/CHD-{243,424,430,462,473,479,481,482,487}.md`. This
document does not restate them; it settles only the Dart shape and where
it plugs into CTUI-35's seams (`docs/design/CTUI-35.md` section 9).

Departures from the original: none.

## 36a. Monitors

**`lib/session/monitors.dart`**, pure, the original's `monitors.ts` file
for file: the constants, `monitorRefusal`, `timeoutWords`, `eventLine`,
`EventLines`/`withLines`/`eventText`, `FloodWatch`, `endWord`,
`endSentence`, `leftRunningLine`, `leftStoppedNote` (unit 1, at
334e98d0), plus `monitorsPast(actions)` over the port's past actions, as
the original reads `served` monitor calls, `stop_monitor` and
`from.monitor.end`.

**`MonitorRun`**, in the same file, with no `dart:io` of its own:

```dart
typedef RunCommand =
    ShellProcess Function(String command, String cwd, void Function(String line) onLine);

final class MonitorRun {
  static Object start(MonitorInfo info, MonitorHooks hooks, String cwd,
      {RunCommand run = runMonitorCommand}); // MonitorRun or ({String error})
  RunningMonitor get running;
  void stop(StoppedBy by);          // person | agent | close
  Future<void> get ended;
}
```

Timers are `Timer` from `dart:async`, times read through `package:clock`
(`clock.now()`), as `Conversation._now` already does, so tests drive both
with `fake_async`. `runMonitorCommand` is `runShell` with two options the
original's `runShell` has and the port's `ShellOptions` comment defers
here: `onLine` (stdout split into lines, stderr dropped) and `reap`
(the process group is killed when the shell exits, and `ended` waits for
it). They go into `lib/shell.dart`'s `ShellOptions`; bash mode passes
neither and is unchanged. Process groups are `lib/platform/process.dart`'s.

**Conversation.** As the original, the runs live in `Conversation`:
`startMonitor(args, cwd, {run})`, `stopMonitor(id, {by})`, `monitors`,
`endedMonitors`, ids `m<n>` going on from `monitorsPast.last`, a
`MonitorsChanged(running, ended)` event (the original's `monitors`) on
every start, batch and end. A batch or end is a `QueuedPrompt` to the
agent from a `monitor` sender; a batch arriving while the previous one is
still queued joins it (`withLines`), as the original's `Monitoring.queued`.
Close, `/clear` and quit stop every monitor silently (`StoppedBy.close`),
and close awaits them; `/clear` resets the count and the past.

**`lib/session/window_monitors.dart`**, pure, the original's file:
`monitorsOwner`, `startMonitorIn`, `stopMonitorIn`, `monitorsIn` over
`WindowAgents`, keyed by `Caller` (`key`, `agent`, `task`); a task owns
none; the limit of 8 counts main and its long-lived children together;
a closed owner answers `This session has closed`. The fork branch of
`monitorsOwner` is CTUI-74's and is not written now.

**Server.** `WindowView` gains `monitor(caller, args)`,
`stopMonitor(caller, id)`, `monitors(caller)`, which the window
implements with `window_monitors.dart`. `toolsOf` appends `monitor`,
`stop_monitor`, `list_monitors` last, for `Role.person` and long-lived
children (not tasks); `toolNames` likewise, so `/mcp` lists main's ten
and a child's seven. Descriptions, schemas, answers (`monitorsAnswer`
with `started_at` ISO) and refusals are the original's text.

**Messages and rows.** `MessageFrom` gains `monitor: ({String id,
MonitorEnd? end})?`; `fromJson` stops returning null for it. The wrapper is
`tasks.ts`'s `wrapMessage`: `from` is `fromLine(from)` (the end word
included) and `monitor="<id>"`, as `record.dart`'s pattern already reads. Rows are the original's
`monitorMessage` (lines folded, end sentence dim after the fold) and
`monitorArrow` tones; tool rows `Monitor <description>`, `Stop monitor`,
`List monitors` as `tools/chord.ts`.

**Records and resume.** Nothing new is written beyond the `served` calls
and `prompt` lines with `from.monitor`. On resume, `monitorsPast` gives
the `leftRunningLine` note after the past (drawn as the left-open note
is) and `leftStoppedNote` goes to the agent as a turn of its own once the
session is up (`LEFT_MONITORS_TOLD = 'turn'`); `stop_monitor` on a left
id answers the original's refusal.

## 36b. The background

**Pure, `lib/ui/background/`:**

- `background.dart`: `background.ts` for kinds `monitor` and `task`
  only: `BackgroundItem`, `ItemStatus`, `backgroundItems`, `leavesList`,
  `summaryGroups`, `summaryLines`, `callPlace`. The `agent` kind and its
  fields (`stoppable`, `parent`, `parentAt`, `stopping`, `stoppingIn`,
  `itemSubagent`'s agent branch) are CTUI-83's: the seam is
  `BackgroundKind` and the `backgroundItems` switch, which CTUI-83
  extends; nothing unreachable ships.
- `state.dart`: `BackgroundState` and `reduceBackground`, every action of
  `state.ts`, in the window's state beside `agentsFocus`, plus
  `summaryFocus`; `backgroundShown`, `agentsHaveKeys`.
- `view.dart`: `view.ts`: `focusedItem`, `focusAfter`, `stepDetail`,
  `stateText`, `hintLines`, `viewRows`, `viewWindow`, `moveView`,
  `laidAt`, `edgeMarked`, `detailLines`, `workHead`, `pinnedName`,
  `stopRefused`, and **`logStep`/`FOLLOWING`** (CTUI-33's leftover).
  `FOLLOWING` is `double.infinity` as `num`, or, if developer prefers an
  `int` top, a `const following = -1` sentinel; either way it lives here,
  on the port's `requestStep`/`requestView`/`hiddenRows`
  (`lib/ui/dialogs/permission.dart`), as the original's does.
- The frame's arithmetic, `backgroundRowLimit(windowRows, hintHeight)`
  and `hintMode`, is pure and beside them, not in the widget.

**Widgets, `lib/ui/background/`:** `summary_line.dart` (`SummaryLine`)
and `background_view.dart` (`BackgroundView`, its monitor detail and the
task detail's `WorkDetail`). **No new `lib/` widget.** The view is rows
of wrapped multi-column text against a line budget with tall rows walked
a line at a time, the same shape CTUI-35 found `ListView` and `Picker` do
not fit (decisions, "the agents list is the port's own"); it is drawn
with `Box` (border in the permission colour, `paddingX: 1`), a
`Column` of `Text.rich` lines, `cellWidth` and `TextLayout.wrapAnsi`.
The title is a `Text.rich` row inside the box, as the original's (bold
`Background`, dim `· N in this session` / `· m1, 2 of 3 · ended`), not
`Box.title`. Scroll rules are the port's `requestRule`. The task
detail's work reuses the transcript's subagent work rendering
(`ui/transcript/agents/`), followed with `logStep`.

**Where it sits.** The view is drawn where the original draws it, in the
request area above the prompt, after the plan box, at most half the
window (`backgroundRowLimit`); it is hidden, not closed, while an ask that
came after it is open (`backgroundShown`). In `agentsRoom` both the
summary line (its `summaryLines` count) and the open frame are in
`fixed`: neither shrinks, as the original's `flexShrink={0}`.

**Keys.** `moveListFocus(rows, by, {summary, onSummary})` returns a
`ListTarget` (`ListAgent(key)` | `ListSummary()`), the summary line the
list's last stop and its only one with no child; `↓` from an empty draft
enters the list when either is drawn. On the summary line the status hint
is `summaryHint`; Enter opens the view. In the view: ↑ ↓ j k move (or
step the detail), Enter opens a monitor's detail or goes to a task's
call, Esc/← back, `x` stops (`agents:close`, one action for both), pgup
pgdn and home end as the original. All through `Actions` with
descriptions. The panel (`lib/ui/shortcuts/keys.dart`) gets the
original's lines: `↑ ↓` `for prompts, agents, background`, `x` `to close
an agent, stop background`, and the `enter` line `for background,
details, a call`; the shortcuts panel test checks them at 80x24.

**Stop.** `x` on a monitor is `stopMonitor(id, by: person)` in the
owner's conversation; on a task, the task's close. Refusals go to the
hint through `background_stop_asked`/`background_hinted` tokens.

## 36c. `chord acp`

`monitors: 1` in `initialize`'s `_meta` capabilities, in the original's
place; `_chord/monitors/changed {sessionId, running, ended}` sent from
each `MonitorsChanged` (held until a child's route is up, as other child
events); `_chord/monitors/stop {sessionId, id}` handled as
`agent_app.ts` with its errors. `host_fold.dart` lists `MonitorsChanged`
among `hostNotActions`, so its coverage test passes.

## Checks

Screens at 120x40 and 80x24 beside the original's
`bun dev chord --fake --qa <scenario>` for `monitor`, `monitors`,
`monitorexit`, `monitortimeout`, `monitorflood`, `monitorchild`,
`childmonitor` and `agenttask`; captures under
`docs/design/evidence/CTUI-36/`.
