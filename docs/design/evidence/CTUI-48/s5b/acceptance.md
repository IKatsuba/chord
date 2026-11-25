# S5b designer acceptance

Held implementation: `97a041f45e51b484badff762d29b82d597f10a53`.
Occurrence identity parent: `eba3259675d619ee5aedd354f952627836d88a16`.
Original: `577b58167672e12c999aeaf4eed2a1a988513dc2`.
Developer held the clean shared tree throughout. No screen/API finding;
hand this unit directly to reviewer. S6 pick/buttons are intentionally absent.

The public constructor shape follows the approved contract: borrowed optional
Terminal, optional Copy override, copyOnSelect default true. Copy reports
sent/copied/failed separately; the coordinator owns character counts and
cancellation. EntryIdentity remains a typed opaque occurrence identity while
existing const Entry construction remains available. This is an API look;
writer/reducer, stale ownership and key precedence claims remain the handed
automated evidence, not inferred from screenshots.

## Runtime setup and paired states

Run the two retained Python drivers from the repository root. Each starts
owned tmux panes at120x40 and80x24 and saves capture-pane -p and -p -e. Final
runs explicitly unset NO_COLOR and set TERM=xterm-256color,
COLORTERM=truecolor; --plain deliberately reintroduces NO_COLOR. Text is sent
with send-keys -l; Enter is a separate send-keys call. The selection injects
SGR primary down, motion and release over the first four cells of
`Next eligible request`. This proves protocol routing, not physical pointer
or native terminal selection delivery.

Port: `dart run example/chord/tool/selection.dart`, with --manual, --failure,
--timeout, --light or --plain as named by captures. This is the real
TranscriptWindow with seeded model occurrences and a recording-only Copy
adapter, without an agent. The fixture has one fixed ignored journal, so all
port cases run serially; each journal is saved before the next fixture starts.

Original: original-recording.ts imports the read-only original main.tsx and
replaces its exported startServices.copier factory before cli.parse. The host
clipboard and terminal clipboard adapter are never constructed. The fake
agent command comes from original tests/fixtures/fake.ts and shell-quote;
production React and resource-fixture behavior follow the original dev runner.
The launch uses isolated config/state/project directories and
--no-mcp-servers. `long`, then `Next eligible request`, each followed by a
separate Enter, puts the private directory header outside the captured view.
CHORD_FAKE_STEP_MS=1 bounds setup time. This is original production UI with a
stubbed factory, not an unmodified bun-dev clipboard run.

Both stubs record attempts and simulated writes only. A write event means the
recording adapter accepted text; it proves no OS write or OSC delivery.
The sent stub returns the original terminal-attempted outcome; failure returns
recording clipboard refused; timeout never resolves. Retained JSONL journals
contain exactly `Next` for every attempted/write payload. Original journals
cover both sizes in order; port journals are per size and case.

All pairs are `paired-<mode>-<theme>-<size>-<state>.txt`, original left and port
right; matching individual .ansi files retain color and highlight evidence.

| Cases at both sizes | Observed result |
| --- | --- |
| auto dark/light/plain released | sent 4 chars to the terminal's clipboard; range retained |
| auto expired | note gone after3000ms; range still selected |
| auto typed-clear, port | ordinary x clears range and enters the focused draft |
| manual released | ctrl + c to copy; no port adapter call until explicit key |
| manual explicit | same sent note; selected cells cleared |
| failure released/persistent/retry | error retains highlight beyond3000ms; Ctrl+C makes a second attempt |
| timeout released/bounded/retry | pending does not pretend success;1200ms bound reports clipboard did not answer; Ctrl+C retries |
| pending retry then Ctrl+D | fixture exits0 without awaiting the pending adapter |

Inspect the selected `Next` cells in final ANSI: dark is palette66 and light
palette152 in both products. Port plain uses inverse with no foreground or
background SGR anywhere in its selected screen. Original plain retains slate66;
that difference is explicitly approved in CTUI-48. Error/status wording and
prompt geometry agree, including the full retry clause at80 columns.

## Differences and evidence limits

The port fixture has a seeded Markdown reply and its header remains visible;
the original has a200-line fake history, a later Hello reply, real fake model
facts and a different version/launch label. Those are setup differences, not
matched transcript evidence. Original manual/pending status may retain fake
facts alongside its hint, while this port fixture has no such model facts.
Full matched fake-session/window parity, AOT/PTY, performance, code buttons,
pick coexistence and the remaining design-state matrix belong to S6/S7.
There was no real model, clipboard, physical pointer or terminal contrast test.

Initial runs inherited NO_COLOR=1 from the tool shell. Representative plain+
ANSI captures and result records remain in setup-inherited-no-color. Their
dark/light labels describe requested flags, not actual theme proof. The final
root-level captures rerun those cases with the explicit environment above.
This was a capture setup failure, not a product color defect.

sanitized-picker-failure-fix.txt retains developer-handed four permission
Picker failures: FocusNode replacement and missing second choice at both sizes.
Developer reports the stable wrapper key repair; the same-byte final reached
aggregate is1306 passes, with unchanged wheel panel/fake files separately22
passes. Designer did not reconstruct the pre-fix runtime or claim a live
permission before/after capture. The handed ignored reached-command manifest
names142 explicit session/UI files; no full suite or compile was run here.

All12 final port panes and6 final original panes exited0. The owned tmux
server and runtime processes are gone; isolated original config, state and
fake records were removed after saving journals. cleanup.json records the
privacy and process checks. No original file was edited. The S6a/S6b unit-list
staging amendment remains queued until the S5b tester gate releases the tree.
