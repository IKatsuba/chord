# CTUI-96 evidence: a lone combining mark after redraw

Commit ac47694a (Buffer.set takes a width-0 grapheme as a styled space).

No example draws a lone mark, so these captures come from a throwaway probe
app, kept outside the repository in a scratch package that depends on this
checkout by path (its directory is not named here). Its source:

```dart
import 'package:chorded_tui/chorded_tui.dart';
void main() => runApp(const P());
class P extends StatefulWidget { const P(); @override State<P> createState() => _S(); }
class _S extends State<P> {
  var styled = false;
  @override
  Widget build(BuildContext context) => Actions(
    bindings: [
      Binding('ctrl+q', 'Quit', () => exitApp(context)),
      Binding('t', 'Toggle', () => setState(() => styled = !styled)),
    ],
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('joined: café résumé'),
      Row(children: [Text('L'), styled ? Text(' ', style: Theme.of(context).focus) : Text('́'), Text('R after lone mark')]),
      styled ? Text(' line starting with a styled space', style: Theme.of(context).dim) : Text('́line starting with a lone mark'),
      Text(styled ? 'state: styled space (t toggles)' : 'state: lone mark (t toggles)'),
    ]),
  );
}
```

Run with `dart run bin/probe.dart` in tmux at 120x40 and 80x24, captured
with `capture-pane -p` (and `-e` for the styled state):

1. `*-1-lone.txt`: a lone U+0301 between L and R, and one starting a line.
2. `*-2-styled.txt` / `.ansi`: t redraws those cells as styled spaces.
3. `*-3-back.txt`, `*-4-styled-again.txt`: toggled back and forth.

At every step no mark is left on a neighbouring glyph (the CTUI-37 slip),
and the joined `café résumé` (e + U+0301 as one grapheme) draws unchanged.
