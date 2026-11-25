---
description: Fixes a bug end to end — a failing test first, then the fix, then a review.
lead:
  agent: claude
  model: claude-opus-5-5
  mode: default
members:
  - name: tester
    role: Writes the failing test, then proves the fix
    agent: claude
    model: claude-opus-5-5
    mode: acceptEdits
    instructions: Write the smallest test that fails for the bug's own reason.
  - name: coder
    role: Writes the fix, in the files the lead names
    agent: codex
    model: gpt-6.1-sol
    mode: auto
    instructions: Make that test pass with the smallest change; never touch tests.
  - name: reviewer
    role: Reads the diff and edits nothing
    agent: claude
    model: claude-opus-5-5
    mode: plan
    instructions: Read the diff against the job and the test; change nothing.
---

One writer per file at a time. The lead writes to main when the job is done.
