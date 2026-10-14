# CHD-205 independent QA

Checked current main after the second reviewer approval, preserving the
designer's appearance decision. All agents below were the repository's fake ACP
fixture. No live model or agent was used. User settings were isolated through
temporary XDG config and state directories; the TUI worked in a neutral scratch
directory.

## What ran

- `deno task check` on the current tree, including the committed
  ink-testing-library clipboard-stub tests, mouse framing tests and fake-agent
  session tests.
- `deno task compile`, then the native macOS binary in tmux.
- Keyboard-only tmux at 120x40 and 80x24 with Vim enabled: image clipboard set
  with osascript from the fixture PNG, and text-only clipboard set with pbcopy.
  Empty markers were sent with `tmux send-keys -l`, both whole and as
  `ESC[20`, `0~ESC[20`, `1~` with 200 ms gaps.
- Insert and normal-mode image/text checks; ctrl+v with/without an image;
  submission; non-empty text and image-path pastes; search, model picker,
  permission and form input; fake-agent error; resize during a turn; Esc
  interruption; source and compiled quit.
- Compiled checks against a fake agent advertising no image capability, with
  image and text-only clipboards. A no-input wait was compared with its initial
  frame to cover terminals that send no paste bytes.
- Terminal mode and exact owned-process inspection with tmux and ps; public-path
  scan of these captures.

## What was observed

- Full check passed: 1,140 tests, 20 steps, zero failures in 5m49s.
  Native compilation succeeded. The staged-evidence privacy check passed all
  seven tests; its first standalone invocation lacked Deno write/env grants,
  corrected to the repository test task's permissions for the successful run.
- Empty image pastes put `[Image #N]` at the cursor at both sizes. Normal mode
  produced `kee [Image #N] p`, matching ctrl+v's insertion position. Delayed
  marker fragments inserted once. No marker bytes appeared in the draft.
- Text-only empty pastes left screen captures identical, with no new failure
  line, in both modes and at both sizes. The source 120 normal-text capture
  retains the earlier ctrl+v no-image line intentionally: the empty paste did
  not change it. The compiled 120 normal-text capture checks a clean status
  line and is also identical to its before frame.
- ctrl+v still inserted the next numbered image, and still displayed
  `No image in the clipboard` when appropriate.
- The source and compiled fake-agent replies acknowledged the submitted images
  as `image/png`. The clipboard library returned 73-byte PNGs; the file path
  supplied the fixture's original 70-byte PNG.
- A non-empty bracketed paste stayed `hello text`. A pasted absolute image path
  became a marker and submitted an image.
- Search and model-picker frames were unchanged after an empty paste. The next
  picker key changed the model. A form accepted `Ada` after an empty paste;
  the permission's next `1` allowed it. No clipboard image appeared there.
- An agent error displayed `The fake agent failed on purpose.` Resize from
  80x24 to 120x40 during `slow`, followed by Esc interruption, displayed
  `Interrupted by user` and left the prompt usable.
- The compiled no-images agent quietly ignored a text-only empty paste and
  displayed `fake does not take images` for an actual clipboard image. Sending
  no bytes left its draft unchanged.
- Source and compiled exits were independently observed with
  `alternate_on=0`, `cursor_flag=1`, and their exact app/agent PIDs absent from
  ps. Terminal canonical/echo flags and control characters were restored;
  the stty snapshots differed only in the pending-input bit. The owned tmux
  session was removed, and no owned fixture agent remained.

## Library and terminal scope

The implementation reuses Ink 8's tested `usePaste` and existing input emitter;
no new parser, renderer, component or dependency was written in QA.

Source research, not native terminal measurements:

- [kitty](https://github.com/kovidgoyal/kitty/blob/master/kitty/window.py):
  `paste_with_actions` returns on empty text, sending nothing.
- [WezTerm macOS clipboard reader](https://github.com/wezterm/wezterm/blob/main/window/src/os/macos/clipboard.rs)
  errors without text or filenames. Its
  [GUI paste path](https://github.com/wezterm/wezterm/blob/main/wezterm-gui/src/termwindow/clipboard.rs)
  sends a paste only after a successful read, so this image-only path sends
  nothing.
- [iTerm2 session](https://github.com/gnachman/iTerm2/blob/master/sources/PTYSession/PTYSession.m)
  routes no-text paste through its
  [non-text helper](https://github.com/gnachman/iTerm2/blob/master/sources/Pasting/iTermNonTextPasteHelper.swift):
  image choices include a temporary file path, base64, upload or cancel rather
  than automatic empty markers.
- [Terminal.app](https://support.apple.com/en-ca/guide/terminal/trml1019/mac):
  Apple's documentation describes text paste; image-only bytes remain unknown.

Ghostty's empty markers are the owner's native observation. Other terminals
were not launched here. Appearance was not rejudged. No separate minor findings
were identified.
