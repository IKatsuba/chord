# CTUI-36 captures

Text captures from tmux (`capture-pane -p`), the port beside the original,
each running on the original's fake agent with the named scenario typed as
the prompt. The startup header's working directory is relabelled
`~/project` in every capture; nothing else is edited.

- `unit3-*`: scenario `monitors`, the `Monitor(...)` tool rows. The
  `← from … · monitor` row and the `background` line under the status line
  belong to later units.
- `unit4-<scenario>-*`: scenarios `monitors`, `monitorexit`,
  `monitortimeout` and `monitorflood`, the `← from … · monitor` rows and
  their end lines; `.ansi` files keep the colours (`capture-pane -p -e`).
  The port's `monitorexit` at both sizes and `monitortimeout` at 120x40
  were taken at bae9caca, which holds unit 4 (2a2432d6) unchanged under
  these rows; the rest at 2a2432d6.
- `unit5-*`: scenario `monitors`, its event heard, then `/clear`,
  `/resume` and Enter on the newest session, at bae9caca: the resumed
  past closing with the monitors-left note and chord's turn to the agent.
  The pickers' older rows are each store's earlier runs, not a difference.
- `unit9-*`: the background summary line at 7796dd15. `monitors`, then
  `focused` after ↓ from the empty draft; `child` with scenario
  `monitorchild` (`CHORD_FAKE_CHILD_RUNTIME=fake`), then `childfocus`
  after ↓ ↓ ↓ through main and parser onto the line. The port's
  `childfocus`/`child` at 80x24 ran from a clean export of 7796dd15, as the
  shared tree held later work that did not build yet.
- `unit10-*`: the background view; the port's captures from a clean
  export of 43fc9e68, nothing else in its tree. Scenario `monitors`, then ↓ Enter (`view`), ↓ (`view2`),
  ↑ Enter (`detail1`), pgdn (`detail1pg`), ↓ (`detail2`), ← (`back`),
  x on CI run 4812 (`stopped`), Esc (`closed`), Esc Esc ? (`panel`).
  Times differ by the second the two were started apart. The panel's
  other differences (`/vim`, forms, `esc ←`) predate this task.
- `unit10b-*`: a task's detail and going to a call, the port from a clean
  export of b46059d6. Scenario `tasklong` (`CHORD_FAKE_CHILD_RUNTIME=fake`):
  ↓ Enter (`taskview`), 3 s idle (`taskview-idle`), Enter (`taskdetail`),
  3 s idle (`taskdetail-idle`), Enter (`taskcall`). Scenario `monitors`:
  home, ↓ Enter Enter (`mondetail`), Enter (`moncall`, held on the call
  with the `↓ 1 line below` rule at 80x24). The prompt border's 244 against
  dim is CTUI-31's recorded slip; the command line's wrap is CTUI-84.
- `unit15-*` and `unit16-*` (CTUI-74, /fork): both run as `chord fake
  --agent-command "bun …/fake_agent/main.ts --fork"` with an isolated
  `XDG_STATE_HOME`; the port from clean exports (unit 15's flow at
  e68f8c2c, `unit15-refused-*` with `CHORD_FAKE_REFUSE_FORK=1` at
  67f7f8fa, unit 16 at 39f19366 for 120x40 and 67f7f8fa for 80x24 and
  `resumed`). Unit 15: `text`, `/f` (`slash`), `/fork` (`forked`), `/fork`
  on the fork (`fork2`), ↓ ↑ ↑ (`main`). Unit 16: `text` in the fork
  (`forktext`), `/clear` on it (`forkclear`), main's `/clear`
  (`mainclear`), ↓ ↓ (`listfork`), x (`closed`), `/resume`
  (`resumepick`), Enter on the fork's record (`resumed`).
- `unit19-*` (CTUI-79, the settings tool): both run as `chord fake
  --agent-command "bun …/fake_agent/main.ts"` in a scratch project with
  their own `XDG_CONFIG_HOME` and `XDG_STATE_HOME`; the port from a clean
  export of 37e3573d. `unit19-<scenario>-<step>`: `a` after the scenario's
  prompt, `b` after its key (C-o for `read`, 1 for `theme` and `vim`, Esc
  for `esc`, PageUp for `long`). The scratch paths are relabelled
  `~/.config` and `~/project`, which shifts a box's right edge where a
  path stands in it. The refusal rows' wrap after `.` is CTUI-84.
- `unit19-narrow-*`: `settingslong` at 40x24 and 80x24 after 849945b2
  (box sized to its wrapped choice and hint), the port from a clean export.
  Where the scratch path wraps inside the box it is relabelled
  `~/scratch/run-` / `x/config/…`, keeping its width.
