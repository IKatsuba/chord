# CHD-12 — Scrolling back through a long transcript

Claude Code prints into the terminal's own scrollback, so the terminal scrolls
it. chord draws on the alternate screen, which has no scrollback, so the window
has to scroll its own transcript. Today it cannot. Once a transcript is taller
than the window, its oldest lines go off the top and there is no way to get
them back. Here is chord at 80×24 after three fake-agent turns: the markdown
reply and its table are gone for good.

```
 chord                                                         fake · /tmp/demo
 › tools

 ⏺ Read(README.md)
   ⎿  # chord

 ⏺ Read it.

 › edit

 ⏺ Edit(src/greeting.ts)
   ⎿  Updated src/greeting.ts with 2 additions and 1 removal
      1 + /** Greets someone by name. */
      2   export function greet(name: string): string {
      2 -   return "hello " + name;
      3 +   return `hello, ${name}`;
      4   }

 ⏺ Edited.

╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

Only the transcript scrolls. The header, the working line, the permission
prompt, the prompt box and the status line stay where they are. Focus does not
move either: the prompt box keeps it, so you can scroll back and type at the
same time.

## Keys

| Key | Does | Why this key |
|---|---|---|
| `pgup` / `pgdn` | Scrolls one page: the transcript's visible height minus 2 rows, so the old top or bottom line stays in view. | Every pager uses them. Ink reports `pageUp` and `pageDown`, and the prompt box does nothing with them. |
| `shift + ↑` / `shift + ↓` | Scrolls one row. | Mac laptops have no PgUp key, and Terminal.app keeps fn+↑ for its own scrollback. shift+arrow reaches chord in every terminal we use. Plain ↑/↓ stays with prompt history. |
| `home` | Goes to the first line of the transcript. | |
| `end` | Goes back to the bottom and follows new output again. | The indicator names this key. |

- **shift is ignored on pgup, pgdn, home and end.** Terminal.app keeps these
  four keys for its own scrollback and passes them to the program only with
  shift held. So shift+pgup must do what pgup does.
- **You also get back to the bottom without `end`.** A `pgdn` or `shift + ↓`
  that reaches the bottom follows new output again, and so does **sending a
  prompt**. If you send a prompt, you want to see the reply. Typing in the
  prompt box does **not** move the transcript: you may be copying something
  from the old lines.
- **shift+↑/↓ must not reach any widget.** The textarea's arrow handling does
  not look at shift, so today shift+↑ walks prompt history and moves the
  cursor. ink-select-input does not look at shift either, so it would move the
  permission highlight. A shift+arrow scrolls and does nothing else. The
  window marks it as its own key, the way it already does with ctrl+o.
- **Scrolling works while a permission is asked and while `?` is open.**
  Neither of them covers the transcript.
- **When the transcript fits the window, these keys do nothing.** No indicator
  appears, and nothing moves.

### In the shortcuts panel

There are three new entries in `src/ui/keys.ts`, written the way the panel
already writes keys:

```
  pgup pgdn  to scroll
  shift + ↑ ↓  to scroll a line
  home end  for the top and the bottom
```

## Following and scrolled back

There are two states, and nothing in between:

- **Following** (the default). The bottom of the transcript is the bottom of
  the view, and new output pushes older lines up. This is how chord behaves
  today.
- **Scrolled back.** Any key that moves the view up leaves following. From
  then on, the view stays on the lines you are reading:
  - New output, the end of a turn, a permission request or an `Interrupted`
    line never moves the lines on screen. A live turn **never pulls you back
    to the bottom**.
  - ctrl+o (which expands thoughts and tool output, and folds them again) keeps
    the entry at the top of the view at the top. It does not jump.
  - A resize keeps the line at the top of the view at the top. A window that
    is following when it is resized is still following afterwards.
  - The view leaves this state only through the keys above: `end`, a
    `pgdn` / `shift + ↓` that reaches the bottom, or sending a prompt.

Why a live turn does not pull you back: the reason to scroll back during a turn
is to read something while the agent keeps working. If every new chunk pulled
you down, you could not scroll back while it streams. You do not miss anything
that needs you. The permission prompt is drawn below the transcript, so it is
on screen whatever the scroll position, and the spinner line keeps counting.

## The indicator

When you are scrolled back, the **last row of the transcript area** turns into
a dim rule that says how much is below and which key brings you back:

```
 ── ↓ 32 lines below · end to jump to the bottom ─────────────────────────────
```

When anything arrives after you scrolled back, the rule says so. `↓ new
output` is drawn bold in the accent colour, and the rest stays dim:

```
 ── ↓ new output · 72 lines below · end to jump to the bottom ────────────────
```

- **It takes the place of a transcript row and is not added below one.** The
  prompt box, the working line and the transcript above it keep their places
  when the indicator appears and when it goes. Nothing on screen shifts.
- **The count is in screen rows**, the same rows that pgdn moves through, and
  it counts the row the rule covers. It goes up as output streams in. One row
  reads `1 line below`.
- **`new output` is in words as well as colour,** so it reads the same in a
  light terminal, a dark one, and a capture without colour. It stays until you
  are back at the bottom, including after the turn ends.
- **The rule does not end with `…`.** It runs out to the transcript's right
  padding, at column `columns − 1`, like a fold mark. At 80 columns the longest
  text is about 63 cells, so the rule never has to cut its words. If a window is too
  narrow for the whole text, drop `· end to jump to the bottom` first and keep
  `↓ N lines below`.
- When you are following, there is no rule and no top marker. The status line
  stays `? for shortcuts`, and the `?` panel is where you find these keys, as
  with every other key.

## What the engineer needs for the check

The acceptance check needs a fake-agent scenario that overflows both sizes and
is still streaming while someone in tmux scrolls back. Add **`long`** to
`tests/fixtures/fake_agent.ts`: one reply that is an ordered list of 200 items,
`N. Line N of 200, streamed one at a time.`, one item per chunk, about 100 ms
apart. That makes about 20 s of streaming. The numbers let a capture show
exactly which lines are on screen. The mocks below use this scenario.

## Mocks

The header's path is shortened in the mocks. The working line is drawn the way
it is today.

### 120×40 — 1. Following while `long` streams (item 90 of 200 so far)

```
 chord                                                                                          fake · ~/projects/chord
   58. Line 58 of 200, streamed one at a time.
   59. Line 59 of 200, streamed one at a time.
   60. Line 60 of 200, streamed one at a time.
   61. Line 61 of 200, streamed one at a time.
   62. Line 62 of 200, streamed one at a time.
   63. Line 63 of 200, streamed one at a time.
   64. Line 64 of 200, streamed one at a time.
   65. Line 65 of 200, streamed one at a time.
   66. Line 66 of 200, streamed one at a time.
   67. Line 67 of 200, streamed one at a time.
   68. Line 68 of 200, streamed one at a time.
   69. Line 69 of 200, streamed one at a time.
   70. Line 70 of 200, streamed one at a time.
   71. Line 71 of 200, streamed one at a time.
   72. Line 72 of 200, streamed one at a time.
   73. Line 73 of 200, streamed one at a time.
   74. Line 74 of 200, streamed one at a time.
   75. Line 75 of 200, streamed one at a time.
   76. Line 76 of 200, streamed one at a time.
   77. Line 77 of 200, streamed one at a time.
   78. Line 78 of 200, streamed one at a time.
   79. Line 79 of 200, streamed one at a time.
   80. Line 80 of 200, streamed one at a time.
   81. Line 81 of 200, streamed one at a time.
   82. Line 82 of 200, streamed one at a time.
   83. Line 83 of 200, streamed one at a time.
   84. Line 84 of 200, streamed one at a time.
   85. Line 85 of 200, streamed one at a time.
   86. Line 86 of 200, streamed one at a time.
   87. Line 87 of 200, streamed one at a time.
   88. Line 88 of 200, streamed one at a time.
   89. Line 89 of 200, streamed one at a time.
   90. Line 90 of 200, streamed one at a time.

 ✶ Working… (9s · esc to interrupt)
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

### 120×40 — 2. One `pgup`: older lines, and the rule

You see this state only for a moment. While a turn is streaming, the next
chunk turns it into state 3. Scrolling back after the turn has ended stays in
this state.

```
 chord                                                                                          fake · ~/projects/chord
   27. Line 27 of 200, streamed one at a time.
   28. Line 28 of 200, streamed one at a time.
   29. Line 29 of 200, streamed one at a time.
   30. Line 30 of 200, streamed one at a time.
   31. Line 31 of 200, streamed one at a time.
   32. Line 32 of 200, streamed one at a time.
   33. Line 33 of 200, streamed one at a time.
   34. Line 34 of 200, streamed one at a time.
   35. Line 35 of 200, streamed one at a time.
   36. Line 36 of 200, streamed one at a time.
   37. Line 37 of 200, streamed one at a time.
   38. Line 38 of 200, streamed one at a time.
   39. Line 39 of 200, streamed one at a time.
   40. Line 40 of 200, streamed one at a time.
   41. Line 41 of 200, streamed one at a time.
   42. Line 42 of 200, streamed one at a time.
   43. Line 43 of 200, streamed one at a time.
   44. Line 44 of 200, streamed one at a time.
   45. Line 45 of 200, streamed one at a time.
   46. Line 46 of 200, streamed one at a time.
   47. Line 47 of 200, streamed one at a time.
   48. Line 48 of 200, streamed one at a time.
   49. Line 49 of 200, streamed one at a time.
   50. Line 50 of 200, streamed one at a time.
   51. Line 51 of 200, streamed one at a time.
   52. Line 52 of 200, streamed one at a time.
   53. Line 53 of 200, streamed one at a time.
   54. Line 54 of 200, streamed one at a time.
   55. Line 55 of 200, streamed one at a time.
   56. Line 56 of 200, streamed one at a time.
   57. Line 57 of 200, streamed one at a time.
   58. Line 58 of 200, streamed one at a time.
 ── ↓ 32 lines below · end to jump to the bottom ──────────────────────────────────────────────────────────────────────

 ✶ Working… (9s · esc to interrupt)
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

### 120×40 — 3. The stream goes on while you are scrolled back

The lines on screen stay where they were. Only the rule changes: it now says
`new output`, and the count has gone up.

```
 chord                                                                                          fake · ~/projects/chord
   27. Line 27 of 200, streamed one at a time.
   28. Line 28 of 200, streamed one at a time.
   29. Line 29 of 200, streamed one at a time.
   30. Line 30 of 200, streamed one at a time.
   31. Line 31 of 200, streamed one at a time.
   32. Line 32 of 200, streamed one at a time.
   33. Line 33 of 200, streamed one at a time.
   34. Line 34 of 200, streamed one at a time.
   35. Line 35 of 200, streamed one at a time.
   36. Line 36 of 200, streamed one at a time.
   37. Line 37 of 200, streamed one at a time.
   38. Line 38 of 200, streamed one at a time.
   39. Line 39 of 200, streamed one at a time.
   40. Line 40 of 200, streamed one at a time.
   41. Line 41 of 200, streamed one at a time.
   42. Line 42 of 200, streamed one at a time.
   43. Line 43 of 200, streamed one at a time.
   44. Line 44 of 200, streamed one at a time.
   45. Line 45 of 200, streamed one at a time.
   46. Line 46 of 200, streamed one at a time.
   47. Line 47 of 200, streamed one at a time.
   48. Line 48 of 200, streamed one at a time.
   49. Line 49 of 200, streamed one at a time.
   50. Line 50 of 200, streamed one at a time.
   51. Line 51 of 200, streamed one at a time.
   52. Line 52 of 200, streamed one at a time.
   53. Line 53 of 200, streamed one at a time.
   54. Line 54 of 200, streamed one at a time.
   55. Line 55 of 200, streamed one at a time.
   56. Line 56 of 200, streamed one at a time.
   57. Line 57 of 200, streamed one at a time.
   58. Line 58 of 200, streamed one at a time.
 ── ↓ new output · 72 lines below · end to jump to the bottom ─────────────────────────────────────────────────────────

 ✶ Working… (9s · esc to interrupt)
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

### 120×40 — 4. `end`: back at the bottom, following again

```
 chord                                                                                          fake · ~/projects/chord
   118. Line 118 of 200, streamed one at a time.
   119. Line 119 of 200, streamed one at a time.
   120. Line 120 of 200, streamed one at a time.
   121. Line 121 of 200, streamed one at a time.
   122. Line 122 of 200, streamed one at a time.
   123. Line 123 of 200, streamed one at a time.
   124. Line 124 of 200, streamed one at a time.
   125. Line 125 of 200, streamed one at a time.
   126. Line 126 of 200, streamed one at a time.
   127. Line 127 of 200, streamed one at a time.
   128. Line 128 of 200, streamed one at a time.
   129. Line 129 of 200, streamed one at a time.
   130. Line 130 of 200, streamed one at a time.
   131. Line 131 of 200, streamed one at a time.
   132. Line 132 of 200, streamed one at a time.
   133. Line 133 of 200, streamed one at a time.
   134. Line 134 of 200, streamed one at a time.
   135. Line 135 of 200, streamed one at a time.
   136. Line 136 of 200, streamed one at a time.
   137. Line 137 of 200, streamed one at a time.
   138. Line 138 of 200, streamed one at a time.
   139. Line 139 of 200, streamed one at a time.
   140. Line 140 of 200, streamed one at a time.
   141. Line 141 of 200, streamed one at a time.
   142. Line 142 of 200, streamed one at a time.
   143. Line 143 of 200, streamed one at a time.
   144. Line 144 of 200, streamed one at a time.
   145. Line 145 of 200, streamed one at a time.
   146. Line 146 of 200, streamed one at a time.
   147. Line 147 of 200, streamed one at a time.
   148. Line 148 of 200, streamed one at a time.
   149. Line 149 of 200, streamed one at a time.
   150. Line 150 of 200, streamed one at a time.

 ✶ Working… (9s · esc to interrupt)
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

### 80×24 — 1. Following

```
 chord                                                  fake · ~/projects/chord
   74. Line 74 of 200, streamed one at a time.
   75. Line 75 of 200, streamed one at a time.
   76. Line 76 of 200, streamed one at a time.
   77. Line 77 of 200, streamed one at a time.
   78. Line 78 of 200, streamed one at a time.
   79. Line 79 of 200, streamed one at a time.
   80. Line 80 of 200, streamed one at a time.
   81. Line 81 of 200, streamed one at a time.
   82. Line 82 of 200, streamed one at a time.
   83. Line 83 of 200, streamed one at a time.
   84. Line 84 of 200, streamed one at a time.
   85. Line 85 of 200, streamed one at a time.
   86. Line 86 of 200, streamed one at a time.
   87. Line 87 of 200, streamed one at a time.
   88. Line 88 of 200, streamed one at a time.
   89. Line 89 of 200, streamed one at a time.
   90. Line 90 of 200, streamed one at a time.

 ✶ Working… (9s · esc to interrupt)
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

### 80×24 — 2. Scrolled back

```
 chord                                                  fake · ~/projects/chord
   59. Line 59 of 200, streamed one at a time.
   60. Line 60 of 200, streamed one at a time.
   61. Line 61 of 200, streamed one at a time.
   62. Line 62 of 200, streamed one at a time.
   63. Line 63 of 200, streamed one at a time.
   64. Line 64 of 200, streamed one at a time.
   65. Line 65 of 200, streamed one at a time.
   66. Line 66 of 200, streamed one at a time.
   67. Line 67 of 200, streamed one at a time.
   68. Line 68 of 200, streamed one at a time.
   69. Line 69 of 200, streamed one at a time.
   70. Line 70 of 200, streamed one at a time.
   71. Line 71 of 200, streamed one at a time.
   72. Line 72 of 200, streamed one at a time.
   73. Line 73 of 200, streamed one at a time.
   74. Line 74 of 200, streamed one at a time.
 ── ↓ 16 lines below · end to jump to the bottom ──────────────────────────────

 ✶ Working… (9s · esc to interrupt)
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

### 80×24 — 3. New output below

```
 chord                                                  fake · ~/projects/chord
   59. Line 59 of 200, streamed one at a time.
   60. Line 60 of 200, streamed one at a time.
   61. Line 61 of 200, streamed one at a time.
   62. Line 62 of 200, streamed one at a time.
   63. Line 63 of 200, streamed one at a time.
   64. Line 64 of 200, streamed one at a time.
   65. Line 65 of 200, streamed one at a time.
   66. Line 66 of 200, streamed one at a time.
   67. Line 67 of 200, streamed one at a time.
   68. Line 68 of 200, streamed one at a time.
   69. Line 69 of 200, streamed one at a time.
   70. Line 70 of 200, streamed one at a time.
   71. Line 71 of 200, streamed one at a time.
   72. Line 72 of 200, streamed one at a time.
   73. Line 73 of 200, streamed one at a time.
   74. Line 74 of 200, streamed one at a time.
 ── ↓ new output · 56 lines below · end to jump to the bottom ─────────────────

 ✶ Working… (9s · esc to interrupt)
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

### 80×24 — 4. `end`

```
 chord                                                  fake · ~/projects/chord
   134. Line 134 of 200, streamed one at a time.
   135. Line 135 of 200, streamed one at a time.
   136. Line 136 of 200, streamed one at a time.
   137. Line 137 of 200, streamed one at a time.
   138. Line 138 of 200, streamed one at a time.
   139. Line 139 of 200, streamed one at a time.
   140. Line 140 of 200, streamed one at a time.
   141. Line 141 of 200, streamed one at a time.
   142. Line 142 of 200, streamed one at a time.
   143. Line 143 of 200, streamed one at a time.
   144. Line 144 of 200, streamed one at a time.
   145. Line 145 of 200, streamed one at a time.
   146. Line 146 of 200, streamed one at a time.
   147. Line 147 of 200, streamed one at a time.
   148. Line 148 of 200, streamed one at a time.
   149. Line 149 of 200, streamed one at a time.
   150. Line 150 of 200, streamed one at a time.

 ✶ Working… (9s · esc to interrupt)
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

### 80×24 — The turn has ended and you are scrolled back, with nothing new

```
 chord                                                  fake · ~/projects/chord
   119. Line 119 of 200, streamed one at a time.
   120. Line 120 of 200, streamed one at a time.
   121. Line 121 of 200, streamed one at a time.
   122. Line 122 of 200, streamed one at a time.
   123. Line 123 of 200, streamed one at a time.
   124. Line 124 of 200, streamed one at a time.
   125. Line 125 of 200, streamed one at a time.
   126. Line 126 of 200, streamed one at a time.
   127. Line 127 of 200, streamed one at a time.
   128. Line 128 of 200, streamed one at a time.
   129. Line 129 of 200, streamed one at a time.
   130. Line 130 of 200, streamed one at a time.
   131. Line 131 of 200, streamed one at a time.
   132. Line 132 of 200, streamed one at a time.
   133. Line 133 of 200, streamed one at a time.
   134. Line 134 of 200, streamed one at a time.
   135. Line 135 of 200, streamed one at a time.
   136. Line 136 of 200, streamed one at a time.
 ── ↓ 64 lines below · end to jump to the bottom ──────────────────────────────
╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

## Left out of this slice

- **The mouse wheel.** chord does not capture the mouse, and it should not:
  capturing it would break selecting text to copy it. But iTerm2 and
  Terminal.app turn the wheel into ↑/↓ on the alternate screen, and in chord
  ↑/↓ walks prompt history. That is filed as its own task, CHD-31.
- **Search in the transcript, and jumping from entry to entry.** These come
  later, if at all.
