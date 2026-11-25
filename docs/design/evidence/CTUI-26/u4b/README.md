# U4b: replay publication and record warning

Visual acceptance of handed implementation `9dfdd2c5b92076f3ef433de6fa960a46f7767e74`.
Original: `577b58167672e12c999aeaf4eed2a1a988513dc2`.
No blocking screen finding. This is a screen look, not a code review or a
persistence, replay-fence, process-lifecycle or full-interchange test pass.

## Reproduction and observations

Run the handed `dart run example/chord/tool/record_history.dart --warning`
with a fresh isolated XDG_STATE_HOME in an owned designer tmux session.
The fixture owns its temporary cwd, seed record and original fake process.
It opens a supported prompt/reply: `Inspect the saved notes` and
`The saved notes are ready.` Capture at 120x40, resize to 80x24 and capture.
Type `text` with literal send-keys, then Enter in its own call; wait for the
fake reply before capture. Resize back to 120x40, capture, submit `text`
again and capture `port-second-120x40`: one warning remains after two turns.
Quit using Ctrl+Q. No real agent or owner state was used.

Plain initial/history/warning frames came from the handed HEAD before
concurrent implementation edits. The environment inherited NO_COLOR=1.
Consequently, these are explicitly plain observations, including the
original captures; they are not color proof. Dark/light warning frames came
from a git archive of the exact handed commit under ignored build/, with
root and port package configurations resolving their local packages inside
that archive. Run with NO_COLOR unset, COLORTERM=truecolor and FORCE_COLOR=3;
use --light for light. The 80x24 captures followed settled resize. The warning
uses existing amber #ffc107 in dark and #8a5a00 in light, ordinary body text
in plain, and the existing transcript bullet/inset. Prompt/status remain
readable and live output follows saved history. No duplicate past appears.

For the original, seed the same four compact version-1 lines from the handed
fixture (session, prompt, update, completed result) in an isolated state's
chord/records/saved.jsonl with synthetic cwd. Launch the read-only original
source entry using Bun production define, fake named agent, explicit original
fake command with --scenario text, synthetic -C and --resume with the seed id.
After initial captures, move the owned seed file aside and replace its path
with a directory to force append failure on submitted `text`. The original
warning wraps at 80x24 and live output follows. This is an owned EISDIR
failure, while the port injects `Bad state: fixture record write failed`;
the error suffixes and their line counts intentionally differ.

## Evidence and boundaries

Each txt pane capture has matching ansi output. comparison-* puts original
and port frames beside each other at each size. original/port-initial show
the same supported historical prompt/reply. original/port-warning show the
existing record-warning transcript shape and continued live output.
port-dark-warning, port-light-warning and port-plain-warning cover both sizes.

Original adds its version, actual synthetic cwd, /help and resumed metadata.
The port fixture supplies version 0.0.1 and directory label project. Dedicated
resumed header, omission notice and picker are U5; integrated real CLI,
combined states and interchange remain U8. These differences are not a U4b
parity claim. The warning is an existing warning row, not the U5 omission line.

Sanitization replaces the synthetic absolute temporary root with an ASCII
fixture-root label padded with underscores to the same cell length. This
preserves captured wrapping and positions. No home path is retained.
Color gradients use half-block glyphs; plain uses the existing solid mark.

All fixture sessions exited cooperatively (port Ctrl+Q, original Ctrl+D).
Owned pane process checks showed dead panes and no remaining fixture/fake
processes before killing the owned tmux server. The isolated capture state
and exact-commit archive were removed after copying evidence. No test suite,
compile or implementation edit was performed for this visual gate.

Cleanup limit added after the U5 tester finding: this run verified fixture/
fake process exit and removed its outer capture resources, but did not verify
deletion of record_history's separately created temporary record directory.
The fixture's deletion after process-exiting runApp is bypassed in the handed
lifecycle. Do not read this visual gate as a fixture-directory cleanup pass;
a signed fixture fix and controlled-TMPDIR verification remain required.

Cleanup resolution (tester-verified, not a new designer run): signed fix
b8183e6ed9b0b54fb2c75f3cc3144f4cf9e2223d moves fixture-root deletion into
awaited shutdown. Tester observed the exact seeded root and saved.jsonl under
controlled TMPDIR before running; header/omission/live text stayed unchanged
through 120x40 to 80x24, Ctrl+Q exited 0, the exact root was absent and no
fixture directories remained. Owned tmux/fake/process/outer state were removed.
Tester closed the cleanup blocker at this fix. Their ignored observation logs
are under build/tester-u5-b8183e6/build/tester-live-observations/
(seeded-root, initial-120, initial-80, live-80 and exit-status txt files).
The historical visual-run verification limits above remain; this addendum
records the later exact-fix cleanup result supplied by tester.
