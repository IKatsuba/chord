---
description: riff as lead and member, on its fake provider, for checks by hand.
lead:
  agent: riff
  model: fake
  mode: ask
  instructions: |
    Read the job, then open helper and send it the one step it does. You
    edit nothing yourself.
members:
  - name: helper
    role: Does the one step the lead sends it
    agent: riff
    model: fake
    mode: ask
    instructions: |
      Do the step the lead sends you and say when it is done.
---

# How riff works as a team

1. The lead reads the job and sends helper one step.
2. helper does it and tells the lead.

Run it with `bun dev chord --fake --qa <name> riff`: riff's fake provider
answers every turn, and its tool-call prompts reach chord's own tools
under the `chord__` prefix, each asking first. This text names no such
prompt itself: the fake would run one it finds in a team's prompt.
