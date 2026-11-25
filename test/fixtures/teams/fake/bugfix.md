---
description: Fixes a bug end to end — a failing test first, then the fix.
lead:
  agent: fake
  model: fake-large
  mode: default
  instructions: |
    Read the job and the code it points at until you can name the cause and
    the files involved. Then open tester first, and coder only once tester's
    test fails for the bug's own reason. You edit nothing yourself.
members:
  - name: tester
    role: Writes the failing test, then proves the fix
    agent: fake
    model: fake-small
    mode: acceptEdits
    instructions: |
      Write the smallest test that fails because of the bug, not for any
      other reason, and run it to show that.
  - name: coder
    role: Writes the fix, in the files the lead names
    agent: fake
    model: fake-large
    mode: plan
    instructions: |
      Make the failing test pass with the smallest change that fixes the
      cause. Do not touch tests.
---

# How bugfix works

1. The lead reads the job and names who may edit which files.
2. tester writes a test that fails for the bug's own reason, in `tests/`.
3. coder fixes the code so that test passes, and never edits `tests/`.

## Who edits what

- One writer per file at a time; a member asks a file's owner directly.
- Another run of a team may be working here: the leads agree on files.

## Reporting

The lead writes to main when the job is done or cannot be done.
