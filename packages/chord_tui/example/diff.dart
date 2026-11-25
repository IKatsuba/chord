import 'package:chord_tui/chord_tui.dart';

void main() => runApp(const DiffExample());

/// Diffs of several shapes, with keys to change the theme and scroll: the
/// framework's `Diff` widget on its own.
class DiffExample extends StatefulWidget {
  const DiffExample({super.key});

  @override
  State<DiffExample> createState() => _DiffExampleState();
}

const _old = '''export function greet(name: string): string {
  return "hello " + name;
}
''';

const _new = '''/** Greets someone by name. */
export function greet(name: string): string {
  return `hello, \${name}`;
}
''';

final _longOld = [
  for (var i = 1; i <= 11; i++) 'step$i();',
  "  return 'A message about terminal cells, 日本語, and preserving every "
      "grapheme while the source line wraps';",
  ...[for (var i = 13; i <= 46; i++) 'more$i();'],
  'save();',
  '\tindented();',
].join('\n');

final _longNew = _longOld
    .replaceFirst(
      RegExp(r"  return 'A message[^\n]*"),
      "  return 'A shorter message';",
    )
    .replaceFirst('\tindented();', '\tindented(again);\n');

const _patch = '''diff --git a/lib/app.dart b/lib/app.dart
--- a/lib/app.dart
+++ b/lib/app.dart
@@ -3,4 +3,4 @@ class App {
   /* A comment the hunk opens
      and closes. */
-  final int count = 1;
+  final int count = 2;
   final String name;
@@ -20,2 +20,3 @@
   void run() {}
+  void stop() {}
 }
''';

/// Each sample: a label, and its diff.
final samples = <(String, Widget)>[
  ('edit', const Diff(_old, _new, title: 'src/greeting.ts')),
  (
    'long line, two hunks, a tab',
    Diff(_longOld, _longNew, title: 'src/long.ts'),
  ),
  ('unified patch', Diff.fromUnified(_patch)),
  ('new file', const Diff('', 'line one\n\nline three\n', title: 'notes.md')),
  (
    'unknown language',
    const Diff('a\nb\n', 'a\nc\n', title: 'data.nolanguage'),
  ),
  ('equal texts', const Diff('same\n', 'same', title: 'same.txt')),
];

enum _Tone { dark, light, untinted, plain }

class _DiffExampleState extends State<DiffExample> {
  final _scroll = ScrollController();
  var _tone = _Tone.dark;

  @override
  Widget build(BuildContext context) {
    final dark = ThemeData.dark();
    final theme = switch (_tone) {
      _Tone.dark => dark,
      _Tone.light => ThemeData.light(),
      _Tone.untinted => dark.copyWith(
        diff: DiffTheme(added: dark.diff.added, removed: dark.diff.removed),
      ),
      _Tone.plain => ThemeData.plain(),
    };
    return Actions(
      bindings: [
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
    return Column(
      children: [
        Text(' Diff  ${_tone.name}', style: theme.accent),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            itemCount: samples.length,
            itemVersion: (i) => _tone,
            itemBuilder: (context, i) => Column(
              children: [
                Text(''),
                Text(' ${samples[i].$1}', style: theme.accent),
                samples[i].$2,
              ],
            ),
          ),
        ),
        const KeyHelp(),
      ],
    );
  }
}
