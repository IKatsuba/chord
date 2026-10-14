# CHD-172 independent QA

Checked source at `1f909e7` on main. Appearance was already approved;
these captures prove behavior using the owner's repeated-option grammar.
Only fake agents ran. No live agent or model was used.

## What ran

- `deno task check` in the foreground with process access: 1221 tests,
  20 steps, zero failures (6m19s).
- `deno task compile`, then the resulting macOS arm64 binary in tmux.
- Fresh HOME, XDG config/state/cache and two project directories under
  `/tmp/chd172-final.XDzrEf`; source and fake fixtures copied there.
- Three sessions recorded through the TUI: `text` on fake in proj,
  `tools` on fake in other, `permission` on fake2 in other (Enter allowed it).
- From a third directory:
  `chord -C /tmp/chd172-final.XDzrEf/launch -r 488905ef-f770-49ef-a6f9-1324e3d06fbb --resume 517c521b-a1cd-496d-aa97-741c5b4c0c70 --resume=4278154d-7142-4629-8861-37699e2a1fcb`.
- ctrl+x 1/2/3, resize 120x40 to 80x24 and back, `/mcp`,
  `error`, `slow`, Esc, `mode`, `!pwd`, ctrl+d.
- Compiled three-tab restore at both sizes; compiled single-id resume with
  the positional agent after the id, then `mode`; source `fake --continue`
  in other at 80x24.
- Ten repeated ids, unknown id among recorded ids, repeated id, each at
  120x40 and 80x24; eight piped ten-id runs (two fresh HOME/cache source,
  four warm source, two compiled).

## What was seen

- Three tabs in order, tab 1 in front. Each replays its own past.
  Header and strip follow proj/other and fake/fake2.
- Project settings follow the tab: Fake Large/default in proj;
  Fake Small/plan for fake and Fake Small/acceptEdits for fake2 in other.
  `/mcp` follows proj-server/other-server. Bash pwd names other.
- The deliberate agent error is shown. Esc interrupts slow; the next prompt
  succeeds as `Mode: plan`. Resize preserves the restored transcripts.
- Compiled single-id resume replays text and answers `Mode: default`;
  `--continue` opens just the latest fake session in other.
- All refusals exit 2 with the expected message. No half-opened window.
  No react-reconciler stack in these runs; CHD-232 remains the separately
  filed intermittent report, updated with this negative reproduction.
- Quit exits 0, prints the existing command per resumable tab, and returns
  to a usable shell. Every terminal comparison matches before/after `stty -g`;
  tmux reports `alternate=0 cursor=1`. Owned tmux sessions are removed.
  The cancelled earlier CHD-172 QA server and its three fake agents were
  also quit and removed. The pre-existing unrelated orphan was left alone.

Library first: production argv tests and compiled startup exercise Cliffy's
native collected single-value option. The documented variadic trial did not
fit; the owner's repeated-option choice is used without a workaround.
No production code or dependency was added during QA.
