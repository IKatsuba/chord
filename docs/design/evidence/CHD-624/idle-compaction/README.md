# "Compacted while idle" (U2, commit 91b54fd36)

`CHORD_FAKE_ADAPTER=claude bun dev chord --fake --qa <name>`, at 120x40 and
80x24; the running state held by the fake's `.fake-gate`. PNGs here, text in
`text/`. The fake's model is Fake Large, so the status line's right side
differs from the design's mock.

| Capture | Scenario and keys | Reads |
| --- | --- | --- |
| `a-running` | `idlecompact` | `✻ Compacting conversation while idle…` (accent); no spinner, no footer |
| `b-typing` | typed while it runs | the prompt takes input |
| `c-over` | released | `⎿  Conversation compacted while idle (ctrl+o for history)` (dim) |
| `d-ctrlo`, `e-back` | ctrl+o, ctrl+o | summary under `⎿  Conversation compacted while idle`; back |
| `f-midprompt` | `text` sent while it runs | spinner `Compacting conversation… (1s · esc to interrupt)`; the `✻` block hidden |
| `g-midprompt-done` | released | the line above `› text`, the turn runs on |
| `h-cancelled` | Esc in that turn | `⎿  Compaction cancelled while idle` (error) |
| `i-failed` | `idlecompactfail` | `⎿  Compaction failed while idle: Not enough messages to compact.` (error) |
| `j-says` | `idlecompactsays` | today's behaviour kept (O1 a): a Claude cycle opens and stays working |
