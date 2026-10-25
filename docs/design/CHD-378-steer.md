# CHD-378: Tab steers the person's message into the running turn

The owner decided the behaviour (task body, 2026-10-14): Enter during a
turn queues, as today; Tab, the rebindable `chat:steer`, sends the prompt
box's text into the running turn on an agent that takes
`_session/steering`; on one that does not, nothing is sent and the status
line says so; a refused or late steer goes into the queue as an ordinary
prompt. One press, one message: prompts queued earlier with Enter stay
queued. This file is what that looks like.

(`CHD-378.md` beside it is an older, unrelated design under the same key.)

The captures are in `evidence/CHD-378/steer/`: `today-*` is chord 0.59.0 on
the fake agent (`CHORD_FAKE_STEERING=claude bun dev chord --fake --qa
des378`, scenarios `texttillsteered`, `bashcut`, `permissionsteer`), and
`mock-*` is each of those captures with only what this design changes
edited in. Every picture is a whole-window colour PNG at 120×40 and 80×24,
with its text beside it.

## The rule in one line

**A steered prompt is drawn as the person's own `›` row, where chord handed
it to the agent, and nothing marks it as steered.** It is CHD-364's rule for
another agent's steered `←` row, in the person's shape. The queue holds only
what really waits.

## 1. The shortcuts panel

One line, right after `enter to send`, so the two ways of sending read as a
pair (`mock-shortcuts-*`):

```
  enter to send
  tab to send into the running turn
  shift or \ + enter for a newline
```

- **The words.** The owner's own: the text goes *into the running turn*.
  "steer" is the protocol's word and the action's id, not the person's.
- **Rebound,** the line shows the bound key, as every rebindable entry does
  (`super + enter to send into the running turn`); the action is `chat:steer`
  in `bindings.ts`, the entry in `keys.ts` names it.
- **No clash with the lists' Tab.** `tab to complete a command` and `tab
  enter to add a file` act only while the `/` or `@` list is open; then Tab
  stays theirs and never steers.
- **Fit.** The panel had exactly 40 lines; this is the 41st. At 120×40 the
  three columns still take 14 rows. At 80×24 the two columns take 21 rows,
  one more than the window has room for beside the box and the blank row
  above it: the last line, `tab enter to add a file`, is cut. The mock
  (`mock-shortcuts-80x24`) left that blank row out and so was one row off.
  Open with the owner (Q217); this section follows the answer.

## 2. Tab on an agent without steering

Nothing is sent and **the draft stays in the box**, so Enter can still queue
it. The status line's left side says, in the warning tone of a notice that
says something asked for did not happen (`failed`, as a failed copy's)
(`mock-nosteering-*`):

```
╭──────────────────────────────────────────────────────────────────────────────╮
│ › Use the second parser instead                                              │
╰──────────────────────────────────────────────────────────────────────────────╯
  This agent does not take messages into a running turn · enter queues it
```

- **The words.** What the task says, then the way out. `this agent`, not its
  name: the header already names it, and a name would push the line past 80
  columns. 72 cells, it fits 80×24 whole; the model on the right gives way,
  as it does for any notice that needs the room. At 120 both fit.
- **How long.** 3 s, the same as a copy's note (`COPIED_NOTE_MS`), counted
  from the last Tab: a second press restarts it. Typing, Enter or Esc does
  not clear it early; it is short enough not to matter, and a note that
  vanishes on the next key is missed by a person who types on.
- **The same note** when the agent's steering is unknown because it has not
  said (no `_meta.steering.supported`): chord does not guess.

## 3. A steered prompt in the transcript

Tab clears the box at once, as Enter does, and the text goes into prompt
history like any sent prompt (↑ recalls it). The row appears in the
transcript in the frame the steering request is answered `injected`, after
whatever the transcript holds then, with the working line still going below
it (`mock-steered-*`):

```
 › texttillsteered

 ⏺ Hello, world. This reply came in chunks.

 › Use the second parser instead

 ››› Working… (4s · esc to interrupt)
```

and the agent's next step comes under it (`mock-steered-next-*`):

```
 › Use the second parser instead

 ⏺ Switching to the second parser.
```

- **Today's user row,** unchanged: dim `›`, the text in the terminal's own
  colour, folded and wrapped as a prompt row is. No `· steered` tag: the
  position already says it went in mid-turn (CHD-364 part 2, and Claude Code
  draws its own mid-turn messages as plain prompt rows).
- **Where chord handed it over, not where the agent read it.** A call
  running at that moment finishes above the row; the agent's next step comes
  below. Same as CHD-364.
- **No queue row for a quick round trip.** A row that blinks for a few
  milliseconds reads as a glitch (CHD-364 part 1), and the box already
  empty is the feedback the press needs. But a steer can go unanswered for
  seconds (one that meets the turn's end, or Codex's late answer), and then
  the text would be on screen nowhere. So **after 500 ms without an
  answer**, the queue shows it, dim like every queue row:

  ```
   ››› Working… (3s · esc to interrupt)
   › into the running turn: Use the second parser instead
  ```

  Answered `injected`, the row leaves the queue in the same frame the
  prompt's row is drawn in the transcript. Refused or late, it loses its
  reason and becomes the plain queue row of §5. A fast answer never shows
  it.
- **Esc does not take it back.** The steer is already out with the agent,
  so an interrupt leaves an `into the running turn` row where it is (it goes
  as the next turn if refused), while the person's other queued rows come
  back into the box as today.
- **Replay.** A resumed session draws the row in the same place, as the
  record keeps it.
- **The same on Claude and Codex.** Only the holds below differ.

## 4. A steer that waits

A steered prompt can be held, as another agent's steered message is
(CHD-364 part 4, CHD-423). It then sits in the queue under the working line
from the press until it goes in, its reason ahead of the text, dim from end
to end like every queue row.

**Behind Claude's open tool calls** (a steer would cut them, CHD-417/423)
(`mock-held-calls-*`):

```
 ⏺ Bash(bun test)
   ⎿  Running…

 ⏺ Read(package.json)
   ⎿  Waiting…

 ››› Working… (2s · esc to interrupt)
 › after the running calls: Skip the slow tests
```

When the calls end, the row leaves the queue in the same frame it is drawn
in the transcript, after the calls (`mock-held-calls-went-*`):

```
 ⏺ Read(package.json)
   ⎿  Read 40 lines

 › Skip the slow tests

 ››› Working… (2s · esc to interrupt)
```

**Behind the person's answer** to a permission, form or link, when one opens
while the steer waits (the box takes the keys, so this is a steer pressed
before it opened) (`mock-held-answer-*`):

```
 ››› Waiting for permission… (3s)
 › after your answer: Also write the docs for it
```

- **The words** are the agent rows' (`· after the running calls`, `· after
  your answer`), without the `·` because the person's row has no header
  before them. `after your answer: ` is already what a person's prompt held
  behind a request between turns says (CHD-158); it is right here too, as
  the prompt goes right after the answer either way.
- **Told apart from an Enter-queued row** by the reason: a plain `› text`
  waits for the turn's end; a row with a reason goes into this turn when
  the reason clears. A queue mixing both reads in press order:

  ```
   ››› Working… (6s · esc to interrupt)
   › Then update the changelog
   › after the running calls: Skip the slow tests
  ```

- **One reason at a time,** as CHD-423: an open question first, else running
  calls. Answered, a row still behind calls changes its reason, never shows
  both.
- **80×24:** `› after the running calls: ` is 28 cells, leaving the text
  about 48; the queue cuts the text in its middle as it cuts any row.
- **Esc interrupting the turn** takes a held steer back into the draft with
  the other queued prompts, as Esc does with all of the person's queued
  prompts (`restoredDraft`): it is the person's, not an agent's.

## 5. Refused or late

The steer is refused (`promptRequired`, an error) or meets the turn's end:
the text goes into the queue as an ordinary prompt, and the queue row is
today's plain row (`today-queued-*`, which is exactly this picture):

```
 ››› Working… (9s · esc to interrupt)
 › Use the second parser instead
```

It goes when the turn ends, behind the prompts queued before it. A held row
whose steer is refused, or an `into the running turn` row (§3) whose steer
comes back refused or late, drops its reason and becomes this row. No status
note and no error: nothing was lost, it went the old way (CHD-364 part 5),
and the row moving to the queue instead of the transcript is the visible
difference. If the turn had already ended, the row goes as the next turn at
once and the queue shows it only for that moment.

**Codex's `startedNewTurn`** (the steer found no turn, the agent started one
of its own) is CHD-365's case with the person as sender: chord cancels that
turn, the outcome line reads `Interrupted · the agent started this on its
own; your message goes as the next turn`, and the prompt goes as chord's
next turn.

## 6. Tab that does nothing new

- **Empty box,** turn running or not: nothing, no note.
- **No turn running,** text in the box: nothing, no note. Enter sends it.
- **`/` or `@` list open:** the list's Tab, as today.
- **A permission, form or question has the keys:** its own Tab, as today.
- **Bash mode (`!`):** nothing; a shell command is not a message.

## 7. Open with the owner

- **A draft with a pasted image (Q215).** Steering carries text only. Open:
  what Tab does with it is not designed here.
- **A draft with `@path` mentions (Q216).** A new turn attaches each as a
  resource link; steering carries text only. Open: not designed here.

## Colour roles

- Steered row: the user row's (`›` dim, text default).
- Held, in-flight and refused rows: the queue's dim, whole row.
- The no-steering note: `warning` (the status line's `failed` tone).
- Nothing new in `theme.ts`.

## Keys

`chat:steer`, default `tab`, rebindable, listed in the shortcuts panel as
`tab to send into the running turn`. Nothing else new.

## Why

The owner chose steering over interrupting, so the screen must not look
like an interrupt: no red, no stopped turn, the working line goes on and
the person's row simply appears among the turn's steps. Drawing it as the
person's own row, where it went in, keeps the transcript a true record of
what the agent was told and when, the way another agent's steered message
already reads. Everything that does not go in at once says why in the
queue, in words the screen already uses.
