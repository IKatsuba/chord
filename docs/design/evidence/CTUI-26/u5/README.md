# U5: resume picker, resumed header and omission line

Screen look accepted after fix f6f6685d0c7e5efaec305cb39f96687959e2b7b5,
on handed U5 4f72b939acf808871236cda20ee4a53c14e256b8. Original source:
577b58167672e12c999aeaf4eed2a1a988513dc2. No blocking screen finding remains.

## Runs

Port runs used exact git archives under ignored build/; copied root/port
package configurations resolved local packages inside each archive.
port-fix-* is the fix commit; other port captures are the handed parent.
The fix changes only the description overflow, so parent observations remain
useful but are not relabeled as fix-commit reruns. All runs used owned tmux
and isolated state. NO_COLOR was unset, COLORTERM=truecolor, FORCE_COLOR=3;
--plain deliberately set NO_COLOR. Text used literal send-keys, Enter in its
own call; captures waited for settled frames.

Run dart run example/chord/tool/resume.dart (agent-free). Ctrl+A toggles
local/all and opens at the top. --empty has only remote records; Ctrl+A
reveals them. --tall --many has a 40-line title/30 records: Down at 120x40
advances from lines 1–7 to 2–8 in the same selected item. Resize to 80x24
retains the selected session and reveals its start; Up clamps there.
--zero shows no choices or Enter hint; Enter and digit 1 produce no Selected
report, while Ctrl+A changes scope. --light/--plain are captured at both
standard sizes. The fixture intentionally caps its list at six rows.
Ctrl+Q exits. Threshold captures are 35/36/37x24 and 32x10.

Run dart run example/chord/tool/record_history.dart --omitted --title with
fresh XDG_STATE_HOME and the resolved original fake checkout. The fixture
owns its cwd/seed/fake. Wrapped agent title, supported saved prompt/reply,
then one plain omission line appear. Submit text: live output follows with
one omission after resize. Light repeats titled history; plain without
--title shows fallback first-prompt header. Ctrl+Q closes/reaps the fake.
Fixture-directory deletion was not verified by this visual run; see the
cleanup correction below. Remove the outer state separately.

Original uses its read-only source launcher with Bun production define,
fake named agent, explicit original fake command (--scenario text), isolated
XDG config/cache/state and synthetic -C. Seed four compact v1 records using
resume.dart labels: local 0/2, remote 1/3, long title and Unicode paths/titles;
prompt time current for 0 and yesterday for others. Open /resume, Ctrl+A,
resize and capture. For header pairs use fake-supported id
11111111-1111-4111-8111-111111111111, a renamed record with eight repeats of
Saved agent title 界😀 and yesterday's prompt, then reopen that id. A first
arbitrary-id refusal was excluded; no refusal frame is retained.

## Finding, fix and evidence

Before fix, the description hard-clipped scope at 35/36/37 columns. Original
CUT retains its tail: fake's earlier...his directory. at 35. Developer
accepted the finding; f6f6685 uses existing TextOverflow.middle. Fix captures
retain scope at all three widths. Metadata remains clipped as designed.
Three-way comparison-description files retain original, failure and fix.

Local/all/empty, numbered Unicode rows, hanging/stacked titles, selected
wrapped styles, overflow edges/count, tall-row reading, zero-row input,
dark/light/plain, narrow chrome, resumed title/fallback and omission were
observed. At 80x24 all-directory titles stack; at 120x40 they hang beside
metadata. ANSI confirms permission color on frame/title/highlight and wrapped
selected lines, dim descriptions/hints. Header title wrapping matches the
original at both standard sizes. Omission has normal inset and no role glyph,
between saved history and live output. No duplicate past/omission appeared.

Every txt has matching ansi. Original local has a 120x40 pair; all-directory
and title have both-size pairs. Port local is retained at both sizes.
The agent-free picker sits at the bottom of a blank window; original sits
above real prompt/status. Absolute positions/body budgets therefore differ;
these frames do not prove integrated overlay geometry. Original absolute
synthetic paths differ from port home-relative labels; all-directory wrapping
is not an identical-input width oracle. Original ages advanced to 1 minute
ago; port ages freeze at just now/yesterday. Threshold original frames verify
the description rule, not identical metadata math. 32x10 is a port safe-clipping
observation, not a new original clipping parity pass.

Original version/directory/staged /help differ. Original title pairs have no
omission: it is an approved port-only line. Live title mutation/frozen header
was not induced. Screen captures do not establish omission bypassing file/ACP,
all key ownership, async lifecycle or two-pass convergence; review/tests own
those checks. Full startup, live overlay, permission suspension, pending/error/
reopen transitions and integrated CLI/interchange remain U6/U7/U8 gates.

## Sanitization and cleanup

Synthetic temporary roots became same-cell-length ASCII fixture-root labels
padded with underscores, preserving wrapping/positions. No home path remains.
Port sessions exited with Ctrl+Q, original picker with Esc then app Ctrl+D.
Owned process checks showed dead panes and no retained fixture/fake process
before killing the owned tmux server. Owned state/archive/temp captures were
removed after saving evidence. Those are the capture runner resources, not
proof that record_history removed its separately created fixture directory.
No suite, compile or implementation edit was performed by designer.

Cleanup correction after tester inspection of exact f6f6685: the app/fake exit,
but a controlled TMPDIR retains chord-record-history-* and saved.jsonl. The
fixture deletes that root in finally after a process-exiting runApp; that
deletion is bypassed. The earlier directory-cleanup claim was incorrect.
Process exit and screen acceptance stand; fixture-directory cleanup remains
blocked until a signed fix and controlled-TMPDIR verification. No cleanup
fix or retest is claimed by this correction.

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
