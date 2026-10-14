---
description: Fixes a bug end to end — a failing test first, then the fix, then a review of the diff.
lead:
  agent: claude
  model: opus
  mode: default
  instructions: |
    Read the job and the code it points at until you can name the cause and
    the files involved. Then open tester first, and coder only once tester's
    test fails for the bug's own reason. Open reviewer last, on the diff.
    Close each member when its part is done. You edit nothing yourself.
members:
  - name: tester
    role: Writes the failing test, then proves the fix
    agent: claude
    model: sonnet
    mode: acceptEdits
    instructions: |
      Write the smallest test that fails because of the bug, not for any
      other reason, and run it to show that. Afterwards run the suite the
      lead names and report what fails, word for word.
  - name: coder
    role: Writes the fix, in the files the lead names
    agent: codex
    model: gpt-5.3-codex
    mode: auto
    instructions: |
      Make the failing test pass with the smallest change that fixes the
      cause. Do not touch tests. Report the files you changed and why.
  - name: reviewer
    role: Reads the diff and edits nothing
    agent: claude
    model: opus
    mode: plan
    instructions: |
      Read `git diff` and the test. Say what is wrong, or that nothing is.
      Never edit a file.
---

# How bugfix works

1. The lead reads the job, finds the files involved, and names who may edit
   which before anyone starts.
2. tester writes a test that fails for the bug's own reason. It edits
   `tests/` only, and reports the failure.
3. coder fixes the code so that test passes. It edits only the files the
   lead named for it, and never `tests/`.
4. reviewer reads the diff and edits nothing. If it finds a problem, the
   lead hands it back to coder.
5. tester runs the whole suite once more, and the lead reports to main.

## Who edits what

- One writer per file at a time. Before a member starts, the lead tells it
  which files are its own, and no other member edits them until it reports
  that it is done.
- A member that needs a file it does not own asks its owner directly, and
  tells the lead what the two of them agreed. It never edits the file "just
  quickly".
- Only one member at a time runs anything that writes outside its files, such
  as formatters, `--fix` and code generators.
- Another run of a team may be working in this directory. Before anyone
  starts, the lead asks the other runs' leads which files they hold, and
  keeps out of them.
- Nobody commits. The person commits.

## Reporting

The lead writes to main when it needs a decision only the person can make,
when the job is done, and when the job cannot be done. Nothing else: main
does not need every step.
