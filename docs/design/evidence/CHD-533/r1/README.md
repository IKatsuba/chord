# R1 owner correction: remove explicit choose

Screen code: `e9fd843648c654fcb30a9c5cfb2b136e489a6c73`.
Design correction: `f75967c0`. Captured 2026-10-27, 21:13 UTC.
The later evidence-only commit is separate from the screen revision.

Visual PASS at 120x40 and 80x24 for the removal surfaces and preserved
critical path. Earlier U5 evidence is historical and superseded for the
removed command; its files and original SHA provenance remain unchanged.

The exact handed commit ran from an immutable archive, with dependencies
linked only and held unchanged, no original Git directory/index/worktree.
The archived tracked launcher was
`nice -n 19 bun tests/fixtures/selected_team_qa.ts normal`.
Its fixed named QA directory isolates config/state and supplies explicit
fake commands for all runtimes and fixture-only resource sources. No live
provider/model, auth-source, credential or login calls were made.

At each size, `/team ch` has no choose completion; Tab leaves the draft
unchanged. `?` and `/help` contain no choose shortcut or model-turn entry.
The narrow shortcuts panel was also scrolled to its final rows.
Submitting `/team choose fixture job` gives the local response
`/team has no choose; it takes list, new, show, run or stop`.
The resulting screen contains no Team call, Resources call or selection
reply before the person deliberately starts another action.

The saved picker still prepares `/team run fixture`; adding `selectedidle`
launches its saved fake-large configuration. A separately typed direct run
uses the same saved configuration. Neither shows a selection report.
An ordinary `selectedteam` fake-agent prompt then calls the existing MCP
facts/selection flow: Resources, reason, warnings, planned choices, actual
lead and unconfirmed reviewer remain readable. The selected fake-small
configuration is distinct from the two earlier saved runs. ctrl+o and
Home/PageDown expose saved choices and changes without a new opt-in.

Every saved plain and ANSI capture was inspected as terminal text. Text
matches after stripping styling; emitted style attributes were inspected.
No images were made. All own sessions were killed; final tmux query found
no server and process query found no matching QA or fixture helper processes.

Scope is visible removal and the preserved direct/MCP screen flow. It does
not prove absence of hidden protocol calls, exact turn counts or lifecycle
behavior beyond these observations; code review and reached tests provide
that evidence separately. No full historical seven-case matrix, Resume
recheck, full suite, compiled or real-provider check was run by designer.
The separately pending tester-owned shortcut-count migration is excluded
from this app snapshot and is not validated by this QA.
