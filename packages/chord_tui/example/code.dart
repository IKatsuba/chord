import 'package:chord_tui/chord_tui.dart';

void main() => runApp(const CodeExample());

/// Code blocks in several languages, with keys to number, wrap and
/// recolour them: the framework's `Code` widget on its own.
class CodeExample extends StatefulWidget {
  const CodeExample({super.key});

  @override
  State<CodeExample> createState() => _CodeExampleState();
}

/// Each sample: a label, the language it is coloured as, its source and,
/// for some, the cells it is given.
const samples = <(String, String?, String, int?)>[
  (
    'dart',
    'dart',
    "void main() {\n"
        "  print('A long message about terminal cells, 日本語, and keeping "
        "every grapheme together on screen.');\n"
        "}",
    null,
  ),
  (
    'ts',
    'ts',
    "/** A comment\n * over three lines. */\n"
        "export class Cache<T> extends Map<string, T> {\n"
        "  private hits = 0; // counted\n"
        "  get(key: string): T | undefined {\n"
        "    return super.get(key) ?? undefined;\n  }\n}",
    null,
  ),
  (
    'python',
    'python',
    '@cached\ndef area(r: float = 1.0) -> str:\n'
        '    """Doc."""\n    return f"{3.14159 * r * r:.2f}"  # rounded\n',
    null,
  ),
  (
    'sh, with a tab',
    'sh',
    'for f in *.txt; do\n\techo "\$f" | grep -v x > /dev/null\ndone',
    null,
  ),
  (
    'no language',
    null,
    'plain text, as it is\n\n  indented after a blank line',
    null,
  ),
  ('empty', 'dart', '', null),
  ('spaces kept, 7 cells wide', null, 'a    b', 7),
  ('spaces kept, 12 cells wide', null, 'x      y\n          indented ten', 12),
];

enum _Tone { dark, light, plain }

class _CodeExampleState extends State<CodeExample> {
  final _scroll = ScrollController();
  var _numbers = true;
  var _wrap = true;
  var _tone = _Tone.dark;

  @override
  Widget build(BuildContext context) {
    final theme = switch (_tone) {
      _Tone.dark => ThemeData.dark(),
      _Tone.light => ThemeData.light(),
      _Tone.plain => ThemeData.plain(),
    };
    return Actions(
      bindings: [
        Binding(
          'ctrl+n',
          'Line numbers',
          () => setState(() => _numbers = !_numbers),
        ),
        Binding('ctrl+w', 'Wrap', () => setState(() => _wrap = !_wrap)),
        Binding(
          'ctrl+t',
          'Theme',
          () => setState(
            () => _tone = _Tone.values[(_tone.index + 1) % _Tone.values.length],
          ),
        ),
        Binding('ctrl+q', 'Quit', () => exitApp(context)),
        ...scrollBindings(
          _scroll,
          keys: const ScrollKeys(
            lineUp: ['up', 'shift+up'],
            lineDown: ['down', 'shift+down'],
          ),
        ),
      ],
      child: Theme(
        data: theme,
        child: Builder(builder: _content),
      ),
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final state =
        '${_tone.name}, numbers ${_numbers ? 'on' : 'off'}, '
        'wrap ${_wrap ? 'on' : 'off'}';
    return Column(
      children: [
        Text(' Code  $state', style: theme.accent),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            itemCount: samples.length,
            itemVersion: (i) => (_numbers, _wrap, _tone),
            itemBuilder: (context, i) {
              final (label, language, source, width) = samples[i];
              final code = Code(
                source,
                language: language,
                lineNumbers: _numbers,
                softWrap: _wrap,
              );
              return Column(
                children: [
                  Text(''),
                  Text(' $label', style: theme.dim),
                  if (width == null)
                    code
                  else
                    Row(
                      children: [SizedBox(width: width, child: code)],
                    ),
                ],
              );
            },
          ),
        ),
        const KeyHelp(),
      ],
    );
  }
}
