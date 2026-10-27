# U4b2b refusal and cancellation supplement

Screen code: `0014e7de73ce958e5a67d5f177b154613525ef51`.
Captured 2026-10-27, 19:43 UTC. Earlier evidence `3d312bfa` retains
its original `e4123020`/`e23c2b7d` provenance; these are new captures.
The later supplemental evidence commit does not identify the screen code.

Visual PASS for the focused cause-text recheck requested by reviewer.
At 120x40 and 80x24, the existing refused launcher shows:
`lead: Initialization failed before the first job; the attempted agent is closing.`
The narrow report wraps that note onto two lines, preserving the lead's
refused/unknown actual configuration and the unopened reviewer.
This fixture does not establish a model-mismatch-specific cause screen.

At both sizes, the existing late launcher, `selectedlate`, followed by
Esc while its startup is gated shows:
`lead: Cancelled before its first job; the attempted agent is closing.`
The Chord-owned receipt retains the real run ID, unknown current state,
refused lead and unconfirmed reviewer. Wide output also shows the ordinary
`Interrupted by user` outcome. No gate was manually released for this case.
Before-Escape captures establish the preceding unconfirmed receipt state.

Runs used an immutable archive of exactly the screen commit, dependency
link only, no original Git directory/index/worktree. The archived tracked
command was `nice -n 19 bun tests/fixtures/selected_team_qa.ts refused`
or `late`. Each isolated fixed named QA directory used only explicit fake
commands and fixture resource sources. Text was sent with `send-keys -l`,
Enter separately; Home/PageDown inspected the full narrow report.
No helper or production changes were needed. No live provider/model,
auth-source, credential or login calls were made.

Every saved plain and ANSI capture was inspected as terminal text. Their
text matches after stripping styling; emitted style attributes were also
inspected. All own sessions were killed, tmux reported no server, and the
process query found no matching QA or fixture helpers.

This supplements the earlier visual handoff only; it does not repeat the
other five cases or establish implementation correctness, full-suite,
compiled, release-target or real-provider coverage. Reviewer owns code
blocker closure and tester owns the final reached checks.
