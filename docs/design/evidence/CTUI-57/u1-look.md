# U1: word-wrap breaks, looked at

Handed source: `4664e86`. Run beside the original (`../chord`, v0.71.0) with the CTUI-29 settings setup ([u29b2a-look.md](../CTUI-29/u29b2a-look.md)), isolated `XDG_CONFIG_HOME` and `XDG_STATE_HOME`, working directory `/tmp/ctui29-look`, then Enter on the picker.

The look passes.

- `u1-window-{o,p}-80x24`: the theme warning now breaks after the `/` as the original does: `…read only from /tmp/ctui29-look/cfg/chord/` + `settings.json, ignored`. This was the CTUI-29 known difference; it is gone.
- `u1-window-{o,p}-120x40`: rows fit; identical text.
- Colours of the warning rows are the same; the original still paints the space after the gutter white, which draws nothing (as in CTUI-29).
- The only other differences are old and not this unit's: version, and the header's `· /help`.
- `u1-markdown-wrap-{120x40,80x24}`: `dart run example/markdown_wrap.dart` reads as before; paragraphs break after `/` and in a URL, tables do not break at punctuation.
