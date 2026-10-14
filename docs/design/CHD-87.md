# CHD-87 — Themes, light and dark

chord picks its colours from one theme. A person chooses it with `/theme`, and
the choice is saved in `~/.config/chord/settings.json`. The default, `auto`,
asks the terminal what its background is. This sheet covers the themes, the
colours in each one, how `auto` decides, the picker and its keys. CHD-70 is
part of it: on a white terminal, the diff's changed rows become pale tints.

The pictures are under `evidence/CHD-87/sheets/`. Each one shows a screen four
ways: the dark theme and the light theme, each on a dark and on a light
terminal. The screens are chord's real screens, captured from the fake agent
and recoloured into the proposed palettes. The `.ansi` file behind each
picture is in `evidence/CHD-87/mock/`, and the screens as they are today are
in `evidence/CHD-87/today/`.

## What a theme owns, and what it leaves alone

**chord never paints plain text.** Replies, prompts, table cells and the
prompt box's text use the terminal's own foreground colour. Dim text, the
prompt box's border, `⎿`, hints and the status line's model use SGR 2 (dim) of
that same colour. This is already true today, and it stays true. Claude Code
does it differently: its themes paint text white (231) or near-black (236).
That is why Claude Code's dark theme on a white terminal is white text on
white. Under chord, the wrong theme can only make the accents fade (see the
lower half of each sheet). The text stays readable.

A theme owns only these colours:

| Role         | Where it shows                                                        |
| ------------ | --------------------------------------------------------------------- |
| `accent`     | the working line's spinner and words, the highlighted slash command   |
| `permission` | permission prompt and pickers: title, border, `❯` and the highlighted row |
| `inlineCode` | `` `code` `` in a reply (markdown.ts, today the hard-coded `#5769f7`) |
| `link`       | a reply's links (today ANSI `blue`, which is 2:1 on black in many palettes) |
| `bash`       | the `!` gutter and bash mode on the status line                       |
| `plan` `edits` `auto` | the mode on the status line (CHD-43's colours)               |
| `error`      | the red `⏺` line, `Interrupted by user`, a failed tool's `⎿`, `bypass` |
| `warning`    | the yellow settings-problem line, `low` context on the status line    |
| `success`    | a finished tool call's `⏺`                                            |
| code tokens  | `keyword string number comment title type name meta`, two sets: on the terminal, and on a diff tint |
| diff         | `tintAdded tintRemoved signAdded signRemoved tintText`                |

## The themes

The ids are Claude Code's own (`theme` in its config), so they need no
translating for someone coming from Claude Code:

| id                 | Picker label                        |
| ------------------ | ----------------------------------- |
| `auto` (default)   | Auto (dark, from the terminal)      |
| `dark`             | Dark                                |
| `light`            | Light                               |
| `dark-daltonized`  | Dark, colour-blind friendly         |
| `light-daltonized` | Light, colour-blind friendly        |
| `dark-ansi`        | Dark, the terminal's 16 colours     |
| `light-ansi`       | Light, the terminal's 16 colours    |

Claude Code's labels say "colorblind-friendly" and "ANSI colors only". chord's
labels use the repository's spelling, and they say what "ANSI" means to
someone who does not know the word.

### Dark and light

Each colour's contrast ratio is shown against the background it was made for.
In brackets is the ratio when the theme is used on the wrong background.

| Role        | dark      | on #000 | light     | on #fff |
| ----------- | --------- | ------- | --------- | ------- |
| accent      | `#d77757` | 6.7     | `#b9532f` | 4.8     |
| permission  | `#b1b9f9` | 11.2    | `#4a5ae0` | 5.5     |
| inlineCode  | `#b1b9f9` | 11.2    | `#4a5ae0` | 5.5     |
| link        | `#8cc8ff` | 11.8    | `#0b5cad` | 6.7     |
| bash        | `#fd5db1` | 7.4     | `#d1006f` | 5.3     |
| plan        | `#48968c` | 6.0     | `#006b66` | 6.4     |
| edits       | `#af87ff` | 7.7     | `#7a3fd6` | 6.0     |
| auto        | `#ffd700` | 15.0    | `#8a6100` | 5.5     |
| error       | `#ff6b80` | 7.7     | `#c4162a` | 6.0     |
| warning     | `#ffc107` | 12.9    | `#8a5a00` | 5.9     |
| success     | `#4eba65` | 8.5     | `#2c7a39` | 5.3     |

The dark column keeps Claude Code's dark colours wherever chord already used
them (accent, plan, edits, auto, and permission and bash in Claude Code's own
dark values). The light column keeps their hues and darkens each one to 4.5:1
or more on white. Today `PERMISSION` and `BASH` are mid tones chosen to read on
both backgrounds. Once there is a theme, each gets the right tone for its
background, as the comments in `App.tsx` already expect.

**Code on the terminal's background** (reply code boxes, a diff's unchanged
rows):

| Token   | dark      | on #000 | light     | on #fff |
| ------- | --------- | ------- | --------- | ------- |
| keyword | `#d7a6ff` | 10.8    | `#8250df` | 5.0     |
| string  | `#f2d38a` | 14.5    | `#7d5200` | 6.8     |
| number  | `#ffb07a` | 11.7    | `#a94800` | 5.8     |
| comment | `#8f96a0` | 7.0     | `#6e7781` | 4.5     |
| title   | `#8cc8ff` | 11.8    | `#0b5cad` | 6.7     |
| type    | `#7fe0e8` | 13.7    | `#00727a` | 5.7     |
| name    | `#f5a3c7` | 10.9    | `#b0306f` | 6.0     |
| meta    | `#b4bcff` | 11.6    | `#4a50c4` | 6.5     |

Both themes use the same hue families as today's sheets (lavender keywords,
amber strings, orange numbers, grey comments, blue names, cyan types, pink
variables). None of them is green or red, so a token never looks like an
addition or a removal (decisions.md, "emphasize highlights code"). The dark set
is today's `ON_TINT`, which is light enough for black. Today's `ON_TERMINAL`
mid tones go away.

**The diff (CHD-70):**

| Role        | dark      | light     | Light reads as                                   |
| ----------- | --------- | --------- | ------------------------------------------------ |
| tintAdded   | `#1f3b24` | `#dcf5e0` | pale green, 1.2:1 against white: a wash, not a block |
| tintRemoved | `#4a1f27` | `#fde2e2` | pale red                                         |
| signAdded   | `#86e08a` | `#17702f` | 5.4 on its tint                                  |
| signRemoved | `#ff8e8e` | `#c4162a` | 4.9 on its tint                                  |
| tintText    | `#e4e4e4` | `#1f2328` | 13.7 / 12.9 on the tints                         |

On a tint, tokens use a set darkened a step further than the terminal set, so
each is 4.4:1 or more on both pale tints: `keyword #7a45d0, string #6e4900,
number #9a4200, comment #626b75, title #0a55a0, type #00666d, name #a32a66,
meta #4248b5`. The dark theme's on-tint set is today's `ON_TINT`, unchanged.

`tintText` is always set explicitly, never left to the terminal. If someone
uses the light theme on a black terminal, the pale rows still carry dark text
(lower right of `sheets/120x40-edit.png`).

### Colour-blind friendly

Only the diff changes. For red–green colour blindness (the usual one), an
addition is blue and a removal is orange, the pair that stays apart:

| Role        | dark-daltonized | light-daltonized |
| ----------- | --------------- | ---------------- |
| tintAdded   | `#16304f`       | `#dbeeff`        |
| tintRemoved | `#4a2a12`       | `#fde8d4`        |
| signAdded   | `#6cb6ff`       | `#0a5bc4`        |
| signRemoved | `#ffb15c`       | `#a34a00`        |

Every other colour is the dark or light theme's. Each token on these tints is
4.3:1 or more. Claude Code's colour-blind theme keeps the red removal and only
makes the addition blue. chord moves both, so the two never depend on telling
red from green. The `+` and `-` stay as well, so no change is shown by colour
alone. See `sheets/120x40-edit-variants.png`, top row.

### The terminal's 16 colours

These themes are for terminals without 24-bit or 256-colour support, and for
people whose own palette is tuned for their eyes. They use only SGR 30–37 and
90–97, so the terminal's palette decides the actual colour. `dark-ansi` takes
the bright half and `light-ansi` the normal half:

| Role                       | dark-ansi       | light-ansi     |
| -------------------------- | --------------- | -------------- |
| accent, auto, warning      | yellowBright 93 | yellow 33      |
| permission, inlineCode, link, title, meta | blueBright 94 | blue 34 |
| bash, edits, keyword       | magentaBright 95 | magenta 35    |
| plan, type                 | cyanBright 96   | cyan 36        |
| string, number             | yellowBright 93 | yellow 33      |
| comment                    | gray 90         | gray 90        |
| name                       | default         | default        |
| error, signRemoved         | redBright 91    | red 31         |
| success, signAdded         | greenBright 92  | green 32       |

There is **no tint**. A background colour taken from 16 is a loud block in
most palettes. Instead, a changed row is the terminal's green or red from its
sign to the end, with no syntax colours, the way `git diff` draws it. This is
chord's no-highlight path today (`App.tsx`'s non-`HIGHLIGHT` branch), so the
16-colour themes reuse it. See `sheets/120x40-edit-variants.png`, bottom row.

## `auto`: asking the terminal

At start, **before Ink takes stdin**, `main.tsx` asks for the background with
OSC 11 (`ESC ] 11 ; ? ESC \`). The answer comes back as
`ESC ] 11 ; rgb:RRRR/GGGG/BBBB` followed by ST or BEL. Its relative luminance
picks the theme: light above 0.5, dark otherwise.

- **Only on a terminal:** both stdin and stdout must be TTYs. Never under
  `-p`, which draws no window.
- **Wait at most 100 ms.** A terminal that does not answer must not hold up
  the start. A late answer must not land in the prompt, so OSC replies are
  taken out of what Ink reads. Measured here: tmux 3.6 answers at once with the pane's
  `window-style` background (`rgb:ffff/ffff/ffff` for
  `bg=#ffffff`, `rgb:1e1e/1e1e/1e1e` for `#1e1e1e`). A detached pane with no
  style gives no answer, so it falls back. I did not measure a pane with a
  client attached, where tmux should pass on its terminal's background; QA
  should.
- **If there is no answer:** use `COLORFGBG` (set by rxvt and Konsole) when
  present. Its last field, `7` or `15`, means light; anything else means dark.
  If that is missing too, use dark, which is what chord looks like today.
- **Asked once per start.** Choosing Auto in `/theme` uses the background
  found at start. It does not ask again, because Ink owns stdin by then. The
  label shows what was found: `Auto (light, from the terminal)`, or
  `Auto (dark: the terminal did not say)` when nothing answered.
- `auto` resolves only to `dark` or `light`. Someone who wants the colour-blind
  or 16-colour version picks it by name. Claude Code works the same way, and
  there is an open request to change that. That is for later.

## `/theme`

`/theme` opens a picker in the box `/model` and `/config` use. It has the same
border, title colour, `❯`, numbered rows and `✔` on the one in use. Under the
choices is a three-row diff sample, drawn by the same `Diff` component the
transcript uses, in the highlighted theme. 120×40, dark terminal, Dark
highlighted:

```
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Theme                                                                                                                │
│ Choose the colours that read best on this terminal.                                                                  │
│                                                                                                                      │
│   1. Auto (dark, from the terminal) ✔                                                                                │
│ ❯ 2. Dark                                                                                                            │
│   3. Light                                                                                                           │
│   4. Dark, colour-blind friendly                                                                                     │
│   5. Light, colour-blind friendly                                                                                    │
│   6. Dark, the terminal's 16 colours                                                                                 │
│   7. Light, the terminal's 16 colours                                                                                │
│                                                                                                                      │
│  1   function greet(name) {                                                                                          │
│  2 -   return "hello " + name;                                                                                       │
│  2 +   return `hello, ${name}`;                                                                                      │
│                                                                                                                      │
│ ↑↓ to preview · Enter to keep · Esc to go back to Auto                                                               │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                                                                    │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts
```

At 80×24 the box is 18 rows. Add the header, the blank row above the prompt,
the prompt box and the status line, and it is exactly 24, with no transcript
row showing (`sheets/80x24-theme-picker.png`). Claude Code's own sample is six rows
with dashed rules. chord's three rows are what fits at 24 rows. A shorter
window drops the sample before it drops a choice. The window itself is the
larger preview anyway.

**Behaviour:**

- **Highlight previews:** moving to a row switches the whole window to that
  theme straight away, transcript included. The person sees their own last
  diff in it, not just the sample. Nothing is saved yet.
- **Enter keeps:** the highlighted theme stays, a dim note `⎿ Theme set to
  Light` goes into the transcript (like `/config`'s notes), and the choice is
  written to the user's settings file.
- **Esc goes back:** the theme in use before `/theme` opened comes back, and
  nothing is written. The hint names that theme so this is not a surprise.
- **Choosing again what is already in use:** the picker closes, with no note
  and no write.
- **Under NO_COLOR:** the picker still opens and still saves, because the
  setting is the person's own. Under the title it says `NO_COLOR is set, so
  chord draws no colour`, and the sample shows `+` and `-` only. Nothing is
  coloured at any point.
- **The file cannot be written** (read-only, or the existing file is not a
  JSON object): the theme still changes for this session. A red `⏺` line says
  so: `Could not save the theme to ~/.config/chord/settings.json: <why>; it
  lasts until chord quits`. A file that is not valid JSON is never
  overwritten.
- **A narrow window:** labels are cut with `…` like `/model`'s. The `✔` comes
  after the label, so it is cut first. The `❯` and the number never are.

**Keys:** `/theme` (Enter or Tab in the slash list), `↑`/`↓` to move and
preview, the digits as on the other pickers, Enter to keep, Esc to go back.
These are the pickers' keys that the shortcuts panel already lists. Esc needs
its `close_theme_picker` beside `close_model_picker` in `keys.ts`. `/theme` goes into
`commands.ts` and into `/help` with the line `Choose chord's colours for a dark
or light terminal`.

## The setting

```json
{ "theme": "light" }
```

- **Only in the user's file**, `~/.config/chord/settings.json`. The theme
  depends on someone's terminal and eyes, not on a project. A `theme` in
  `.chord/settings.json` is reported the way other settings problems are
  (stderr, plus a yellow line in the window): `theme is read only from
  ~/.config/chord/settings.json`. It costs only that key.
- **No flag.** Nothing asked for one, and the setting plus `/theme` cover it.
- **Writing it** (the first thing chord ever writes to a settings file): read
  the file, set `theme`, and write the object back with two-space indents,
  keeping the other keys in their order. Create the file and its directory if
  they are missing. Write a temporary file and rename it over the old one, so
  a crash cannot leave half a file.
- An unknown value, such as `"theme": "solarized"`, is a settings problem like
  any other. It lists the seven ids, and chord starts on `auto`.

## NO_COLOR

NO_COLOR outranks every theme, as it outranks highlighting today: no
foreground, no background, no tint. The 16-colour themes do not count as "a
little colour" either. CHD-69's leak (inline code in 24-bit blue under
NO_COLOR) goes away by itself once `inlineCode` comes from the theme. Taking
the colour from the theme only for a terminal that takes colour (`highlighting()`)
fixes it, and CHD-69 can close with this change and its test. Bold, italic,
underline and dim stay: they are not colour, and NO_COLOR asks only that
colour be left out.

## Libraries

Tried during this design:

- **Background detection:** I found no maintained package on npm or JSR that
  sends OSC 11 and reads the answer. I searched the npm registry
  for "terminal background color detect", "osc 11 terminal background",
  "terminal dark light mode detect" and "term background", and checked
  sixteen likely names (`terminal-background`, `termbg`,
  `detect-terminal-background`, `is-dark-terminal`, `xterm-query`, …), none
  of which exist. JSR has nothing. `@neotales/ansi` (JSR) detects colour level,
  not the background, and is a 0.0.0 alpha. `supports-color` (already under
  Ink, through chalk) detects the colour level only. `ansi-escapes` (already
  under Ink) has no OSC 11 query. So the query and the parsing of `rgb:` are
  chord's own, about 30 lines, and that finding belongs in `decisions.md`.
  The engineer should search once more before writing it, and look at
  whatever Ink 6's own `useStdin` offers for writing a query before the first
  render.
- **Colour handling:** chalk (already used by `highlight.ts`) draws hex at
  whatever level the terminal supports, and named colours for the 16-colour
  themes. Ink's `<Text color>` takes both, so no new package is needed. The
  contrast ratios above come from the WCAG formula in a throwaway script and
  are not needed at run time.
- **A colour library for luminance** (`culori`, `color`): neither parses
  X11's `rgb:RRRR/GGGG/BBBB`. The luminance of one colour is three lines.
  Pick it up if the engineer finds a parser that does read `rgb:`.

## How the change should look when I look at it

I will check at 120×40 and 80×24, with
`tmux set -g window-style 'bg=#ffffff,fg=#000000'` for light and the default
for dark:

1. `auto` on each background picks the matching theme, and the `/theme`
   label says what was found.
2. The fake agent's `markdown` and `edit` replies, and the status line in
   accept-edits and in plan, in `dark` and `light` on both backgrounds, match
   `sheets/` (the colours in `capture-pane -e`, the layout in the text).
3. CHD-70: `edit` on the white background shows pale tints with dark text
   (`#dcf5e0` / `#fde2e2`, `#1f2328`).
4. `/theme`: the preview follows the highlight across the whole window, Esc
   restores, Enter writes `theme` to the user's file and adds the note, and a
   second chord start opens in it.
5. Under `NO_COLOR=1`, no `38;`/`48;` escapes at all in `capture-pane -e`,
   inline code included.
