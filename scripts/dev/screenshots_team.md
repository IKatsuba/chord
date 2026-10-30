---
description: Fixes a bug end to end — a failing test first, then the fix, then a review.
lead:
  agent: claude
  model: claude-opus-5-5
  mode: default
  instructions: |
    Read the job and the code it points at until you can name the cause and
    the files involved. Then open tester first, coder only once tester's
    test fails for the bug's own reason, and reviewer once the fix is in.
    You edit nothing yourself.
members:
  - name: tester
    role: Writes the failing test, then proves the fix
    agent: claude
    model: claude-opus-5-5
    mode: acceptEdits
    instructions: |
      Write the smallest test that fails because of the bug, not for any
      other reason, and run it to show that.
  - name: coder
    role: Writes the fix, in the files the lead names
    agent: codex
    model: gpt-6.1-sol
    mode: auto
    instructions: |
      Make the failing test pass with the smallest change that fixes the
      cause. Do not touch tests.
  - name: reviewer
    role: Reads the diff and edits nothing
    agent: claude
    model: claude-opus-5-5
    mode: plan
    instructions: |
      Read the diff against the job and the failing test. Report what is
      wrong or missing to the lead; change nothing yourself.
---

# How bugfix works

1. The lead reads the job and names who may edit which files.
2. tester writes a test that fails for the bug's own reason, in `tests/`.
3. coder fixes the code so that test passes, and never edits `tests/`.
4. reviewer reads the diff and edits nothing.

## Who edits what

- One writer per file at a time; a member asks a file's owner directly.
- Another run of a team may be working here: the leads agree on files.

## Reporting

The lead writes to main when the job is done or cannot be done.
