import 'dart:async';

import 'package:chord_tui/chord_tui.dart';

import '../grid.dart' show GridStep;
import '../page.dart';
import '../palette.dart';

/// One way in: its name, the command, and what it suits.
typedef InstallWay = ({String name, String command, String note});

/// The three ways in, as the install page offers them.
const installWays = <InstallWay>[
  (
    name: 'Homebrew',
    command: 'brew install ikatsuba/tap/chord',
    note: 'macOS and Linux. brew upgrade keeps it current.',
  ),
  (
    name: 'npm',
    command: 'npm i -g @chorded/chord',
    note: 'Any machine with Node; the right binary is picked for you.',
  ),
  (
    name: 'From source',
    command: 'dart compile exe bin/chord.dart',
    note: 'Dart 3.12 or later, from a checkout of the repository.',
  ),
];

/// What the Then block opens a session with.
const thenCommand = 'chord claude -C ~/projects/app';

/// How to install chord: a header, the three ways as cards, then the
/// command that opens a session. The arrows select a card or the Then
/// block, and `c` copies the selected command.
class InstallPage extends StatefulWidget {
  /// The install page.
  const InstallPage({super.key});

  @override
  State<InstallPage> createState() => _InstallPageState();
}

class _InstallPageState extends State<InstallPage> {
  // 0–2 the cards, 3 the Then block.
  var _selected = 0;
  var _lastCard = 0;

  // ←→ move along the cards, ↓ from a card reaches Then, ↑ comes back.
  void _move(GridStep step) => setState(() {
    final last = installWays.length - 1;
    switch (step) {
      case GridStep.left when _selected < 3:
        _selected = (_selected - 1).clamp(0, last);
      case GridStep.right when _selected < 3:
        _selected = (_selected + 1).clamp(0, last);
      case GridStep.down when _selected < 3:
        _lastCard = _selected;
        _selected = 3;
      case GridStep.up when _selected == 3:
        _selected = _lastCard;
      default:
    }
    _copied = false;
  });

  // A copy says so for two seconds, so the key never looks dead.
  var _copied = false;
  Timer? _copiedTimer;

  void _copy(BuildContext context) {
    TerminalScope.maybeOf(context)?.copyToClipboard(_command);
    _copiedTimer?.cancel();
    _copiedTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
    setState(() => _copied = true);
  }

  @override
  void dispose() {
    _copiedTimer?.cancel();
    super.dispose();
  }

  String get _command =>
      _selected == 3 ? thenCommand : installWays[_selected].command;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      // As many cards to a row as leave each command whole: a card's inner
      // width is its own less the frame and the padding.
      final content = pageContentWidth(constraints.maxWidth);
      final widest = installWays.fold(
        0,
        (w, way) => cellWidth('\$ ${way.command}') > w
            ? cellWidth('\$ ${way.command}')
            : w,
      );
      final columns = [
        3,
        2,
        1,
      ].firstWhere((n) => n == 1 || (content - 2 * (n - 1)) ~/ n - 6 >= widest);
      final theme = Theme.of(context);
      final palette = theme.extension<SitePalette>() ?? const SitePalette();
      final copy = _copied
          ? Text('copied', style: theme.accent, softWrap: false)
          : Text.rich(
              TextSpan(
                '',
                children: [
                  TextSpan('copy ', style: theme.dim),
                  TextSpan('c', style: theme.text.merge(Style.bold)),
                ],
              ),
              softWrap: false,
            );
      final rows = [
        for (var r = 0; r * columns < installWays.length; r++)
          [
            for (
              var i = r * columns;
              i < (r + 1) * columns && i < installWays.length;
              i++
            )
              i,
          ],
      ];
      return SitePage(
        bindings: [
          for (final (key, step) in const [
            ('left', GridStep.left),
            ('right', GridStep.right),
            ('up', GridStep.up),
            ('down', GridStep.down),
          ])
            Binding(key, 'move', () => _move(step), id: 'install:move'),
          Binding('c', 'copy', () => _copy(context)),
        ],
        sections: [
          Text.rich(
            TextSpan(
              '',
              children: [
                TextSpan('Home', style: theme.dim),
                TextSpan(' › ', style: theme.dim),
                TextSpan('Install', style: theme.text),
              ],
            ),
            softWrap: false,
          ),
          Text(''),
          Text('INSTALL', style: theme.accent.merge(Style.bold)),
          Text('Three ways in.', style: theme.text.merge(Style.bold)),
          Text(''),
          Text(
            'chord is one native binary for macOS and Linux, arm64 and x64. '
            'Pick a way; c copies its command.',
            style: theme.dim,
          ),
          Text(''),
          for (final row in rows) ...[
            LayoutBuilder(
              builder: (context, c) {
                final room = c.maxWidth - 2 * (columns - 1);
                return Row(
                  spacing: 2,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final (j, i) in row.indexed)
                      _card(
                        theme,
                        installWays[i],
                        i == _selected,
                        room ~/ columns + (j < room % columns ? 1 : 0),
                        copy,
                      ),
                  ],
                );
              },
            ),
            Text(''),
          ],
          Text('THEN', style: theme.accent.merge(Style.bold)),
          Box(
            background: palette.raised,
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('shell', style: theme.dim),
                    const Spacer(),
                    if (_selected == 3) copy,
                  ],
                ),
                Text(''),
                Text(
                  '// open a session in your project',
                  style: theme.dim.merge(Style.italic),
                ),
                Text.rich(
                  TextSpan(
                    'chord claude',
                    children: [
                      TextSpan(' -C', style: theme.accent),
                      TextSpan(' ~/projects/app'),
                    ],
                  ),
                  softWrap: false,
                ),
              ],
            ),
          ),
        ],
      );
    },
  );

  Widget _card(
    ThemeData theme,
    InstallWay way,
    bool selected,
    int width,
    Widget copy,
  ) => Box(
    border: Border.rounded.withStyle(selected ? theme.accent : theme.border),
    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
    width: width,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              way.name,
              style: (selected ? theme.accent : theme.text).merge(Style.bold),
              softWrap: false,
            ),
            const Spacer(),
            if (selected) copy,
          ],
        ),
        Text(''),
        Text.rich(
          TextSpan(
            '',
            children: [
              TextSpan(r'$ ', style: theme.dim),
              TextSpan(way.command, style: theme.accent),
            ],
          ),
          softWrap: false,
        ),
        Text(''),
        Text(way.note, style: theme.dim),
      ],
    ),
  );
}
