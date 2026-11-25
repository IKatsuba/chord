# CTUI-101 evidence: dimcode's one-time notice

Text captures (`*.txt`) and colour captures (`*.ansi.txt`, tmux
`capture-pane -e`) at 120x40, 80x24, 80x14 (body cut) and 80x11 (body
and hint cut), taken with the notice open at start.

- `original-*`: `../chord` run from source as `dimcode` on its fake agent
  (`tests/fixtures/fake_agent/main.ts --dimcode-permission full-access`),
  with isolated XDG state and config directories. The run directory, a
  fixed QA place, is relabelled `~/project` in the header.
- `port-*`: `dart run tool/notice.dart` from `example/chord`, the no-agent
  fixture, at commit 3de5add5. It has no header, and its transcript rows
  are filler.

The notice box matches the original row for row at every size. A known
difference that is outside this unit: the port's selected choice is bold
(the framework Picker does this for every picker), and the original's is
not.

`port-tall-draft-*` (commit 52c76184): `tool/notice.dart` with a 20-line
draft pasted into the prompt, then F2, taken at 120x40 and again after
resizing to 80x24. Above the tall prompt the body is cut after a drawn
line, and the title, the gap, the choices and the hint stay. The original
was not captured in this state: its notice holds the keys from the
moment it opens, so a draft can only be under it if the notice came due
mid-session. It passes the live room the same way (App.tsx:1889).
