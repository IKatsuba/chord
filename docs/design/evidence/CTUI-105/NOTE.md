# CTUI-105 evidence: shortcuts help and dimcode's notice together

`original-*`: `../chord` run from source as `dimcode` on its fake agent,
in tmux at 120x40 and 80x24, with isolated empty XDG_STATE_HOME and an
XDG_CONFIG_HOME whose `chord/settings.json` defines the agent:

    { "agents": { "dimcode": { "command":
      "bun ../chord/tests/fixtures/fake_agent/main.ts --dimcode-permission full-access" } } }

    (cd ../chord && bun dev chord dimcode -C <project>)

(the settings file held the checkout's absolute path; written relative here).

1. `*-1-notice.txt`: the notice open at start.
2. `*-2-question.*`: `?` typed with the notice open. At 120x40 the help
   panel opens under the notice, its bottom row right above the prompt,
   the notice's frame directly on top of it (no gap row, no dim rule); the
   notice keeps its rows. At 80x24 the notice takes all the room: help is
   open but drawn with 0 rows, nothing else changes.
3. `*-3-after-enter.txt`: Enter answers the notice; help stays open and,
   with the room free, draws in full under its own dim rule (at 80x24 with
   `── ↓ 5 lines below · pagedown to scroll ──`).

The run directory in the header is relabelled `<project>`.

`port-*` (commit 6b790f3f): the port run the same way, as `dimcode` on
the original's fake agent through the same settings file and isolated
XDG directories, `CHORD_FAKE_CHILD_RUNTIME=fake` set:

    dart run example/chord/bin/chord.dart dimcode -C <project>

Steps as above (notice, `?`, Enter) at 120x40 and 80x24. Every text
capture matches the original's row for row (header version and run
directory aside), and the 120x40 colour capture gives the notice title,
choices and help rows the same styles.
