# CHD-319 evidence: OpenTUI 0.5.17 against 0.6.0 on screen

Captured in tmux 3.6a with `bun run chord:fake`. "before" is 6ee77f7
(OpenTUI 0.5.17) with 6faa11b's fake agent copied in; "after" is 6faa11b
(OpenTUI 0.6.0).

- `reply-*`: the `graphemes` fake reply (a decomposed é, 👩‍💻, ⚠️ and 👍🏽
  each right before bold and code), at 120x40 and 80x24.
  - `-codepoint`: OpenTUI's own pick under tmux (wcwidth). Both versions
    leave blanks after the joined and toned emoji, erase ⚠️ and wrap
    `code` early. That is CHD-324.
  - `-grapheme`: started with `OPENTUI_FORCE_UNICODE=1`, so OpenTUI measures
    by grapheme, the same way the test renderer does. Both versions draw the
    text and the bold and code runs on the right cells.
- `ctrlr-*`: ctrl+r over the prompt `say é 👩‍💻 ⚠️ auth`, under
  `OPENTUI_FORCE_UNICODE=1`. In both versions the inverse covers exactly
  `auth`. The accent written after `auth` happens in both versions.

The `.ansi` captures for before and after are byte-identical (apart from
the temporary directory) at both sizes and in both width modes. In a
terminal that can be driven from here, the late run 0.5.17 shows in
`tests/ui/tui_test.tsx` never reaches the screen, so the test is the proof
of the fix. These captures prove 0.6.0 changes nothing visible for the
worse.
