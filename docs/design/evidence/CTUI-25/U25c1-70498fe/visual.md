# U25c1 earlier screen reference, not standalone acceptance

Handed screen: `70498fec4b5c1271ef55bdb76b6da47476176619`.
Original: `577b58167672e12c999aeaf4eed2a1a988513dc2`, read-only ../chord.
This commit alone is NOT accepted as reached-green: developer found that
mounted source shellStopKey=esc differed from the lazy code catalog options,
breaking existing copy-button source revision agreement. Required repair is
included in final combined U25c2 head29e178a; see sibling U25c-29e178a report.

This earlier live look covered empty ! entry, empty Backspace leave, bracketed
paste of a multiline script into an empty normal prompt, local Enter submit,
full12 stdout lines then stderr/exit3, ordinary prompt restoration, Up recall,
Ctrl+C clear retaining bash mode, running and Esc stop, empty result and
injected spawn failure. Both120x40/80x24 and port dark/light/plain are retained.
Original used the same bounded multiline printf script, !true for empty, and
printf ready; sleep45 for running, explicitly stopped by Esc. Port hold/empty/
failed are deterministic injected scenarios; failure wording is source-defined,
not a claim that the original real shell was forced not to start.

Running, stopped and draft presentation match current original wording/layout.
The port's fixture header lacks the original agent/model facts; approved shared
text wrapping differs from original mid-token wraps. These are recorded,
not new parity claims. No real port shell/agent/clipboard action occurred.
Queued context serialization, connection ownership and cancellation are reached
logic tests, not proven by these screens or by this recording connection.

Exact70498fe source ran in an immutable ignored-build snapshot with offline
pinned dependencies. Launches: dart run example/chord/tool/bash.dart, --light,
--plain, with inherited NO_COLOR removed for coloured themes. Original launch:
bun dev chord --fake --qa ctui-designer-u25c1, NO_COLOR removed. Text was sent
literally, multiline content through bracketed paste, Enter in separate calls.
No compile or heavy tests ran. Owned sessions/processes/QA state and snapshot
were cleaned. Full raw trailing blank capture rows are intentional.
