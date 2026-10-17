# CHD-364 (reply age): which clock each state in the agents list counts

This file records the decision for CHD-364 as the board numbers it today:
the agents list's reply age. `CHD-364.md` beside it is an older design from
before the board's renumbering (steering) and is unrelated.

## What reads wrong

When a message reaches a child that is not in front, its row first reads
`← message from @main`, with no time. When the child replies, the row turns
to `✓ replied …`. The age then counts from when the message arrived, not
from the reply. On the fake agent, parser's row reads `✓ replied 23s ago` in
the first half-second it says `replied`
(`evidence/CHD-364-reply-age/replied-120x40.txt`, taken with
`CHORD_FAKE_STEERING=codex CHORD_FAKE_STEER_LATE=1 CHORD_FAKE_STEP_MS=60`,
scenario `agents`, main in front).

The cause is in `src/session/tabs.ts`: the `message` to `replied` change keeps
`before.unseen.since`.

## The rule

A time on a row counts from the event its words name:

| State | Words | Counts from |
| --- | --- | --- |
| asking | `● permission 13s`, `● input 13s` | the request |
| exited, failed to start | `✗ exited`, `✗ failed to start` | no time shown |
| turn failed | `✗ turn failed 12s ago` | the failure (`failedAt`, CHD-264, 03578e30) |
| message | `← message from @main` | no time shown |
| replied | `✓ replied 4s ago` | the reply: the turn's end |
| working | `✻ working 41s` | the turn's start |

`unseen.since` keeps its own job: **when the unseen news began**. It is what
orders the news for `ctrl+x a` and the status line's oldest-first naming.
The age drawn on the row is a separate time, kept beside it, as
`failedAt` already is for a failed turn: a `repliedAt` (or a field of any
name) set when the state becomes `replied` and set again at each later reply
before the person looks. The row names the newest reply, since that is
what a reply means to the person. A failed turn keeps its first failure,
because the first failure is the one to look into; a reply has no such
first.

**Why:** the words say `replied 23s ago`, so the person reads the time as
when the reply came. The order of the news is another question. A message
that arrived first is still the oldest news when its reply comes, so
`ctrl+x a` keeps going to it first. CHD-264 already split the two clocks
this way for a failed turn, and this makes `replied` the same.

The same rule applies wherever these words appear with a time: a folded
team lead (`✓ coder: replied 4s ago`) and the sessions picker. No words,
colours or keys change.

## Check

With the repro above, parser's first `replied` row reads `replied 0s ago` or
`1s ago`, and counts up from there. `ctrl+x a` and the status line still name
the agent whose news is oldest.
