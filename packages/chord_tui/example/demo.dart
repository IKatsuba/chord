import 'package:chord_tui/chord_tui.dart';

void main() => runApp(const Demo());

/// What ctrl+t picks: the terminal's own theme, or one forced over it.
enum _ThemeChoice { auto, dark, light, plain }

class Demo extends StatefulWidget {
  const Demo({super.key});

  @override
  State<Demo> createState() => _DemoState();
}

class _DemoState extends State<Demo> {
  final _draft = TextEditingController();
  final _log = <String>[];
  final _scroll = ScrollController(follow: Follow.bottom);
  var _busy = false;
  var _details = false;
  var _choice = _ThemeChoice.auto;

  void _submit(String text) {
    if (text.trim().isEmpty) return;
    setState(() {
      _log.add(text);
      _draft.clear();
      // Sending goes back to the end, as chord does.
      _scroll.toBottom();
    });
  }

  void _fill() => setState(() {
    final from = _log.length;
    for (var i = 0; i < 200; i++) {
      _log.add('line ${from + i + 1}${', and more' * (i % 12)}');
    }
  });

  void _nextTheme() => setState(
    () => _choice =
        _ThemeChoice.values[(_choice.index + 1) % _ThemeChoice.values.length],
  );

  /// What the header says about the theme, in chord's `/theme` wording.
  String _themeLabel(BuildContext context) {
    final bg = Theme.backgroundOf(context);
    final label = switch (_choice) {
      _ThemeChoice.auto => switch (bg.source) {
        BrightnessSource.terminal => '${bg.brightness.name}, from the terminal',
        BrightnessSource.colorFgBg => '${bg.brightness.name}, from COLORFGBG',
        BrightnessSource.fallback =>
          '${bg.brightness.name}: the terminal did not say',
      },
      _ => '${_choice.name} (ctrl+t)',
    };
    return Theme.noColorOf(context) ? '$label, no colour' : label;
  }

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.backgroundOf(context).brightness;
    // NO_COLOR wins over a theme an app picks, as over runApp's.
    final noColor = Theme.noColorOf(context);
    final forced = switch (_choice) {
      _ThemeChoice.auto => null,
      _ when noColor => ThemeData.plain(brightness: brightness),
      _ThemeChoice.dark => ThemeData.dark(),
      _ThemeChoice.light => ThemeData.light(),
      _ThemeChoice.plain => ThemeData.plain(brightness: brightness),
    };
    final content = Builder(builder: _content);
    return Actions(
      bindings: [
        Binding(
          'ctrl+o',
          'Toggle details',
          () => setState(() => _details = !_details),
        ),
        Binding('ctrl+t', 'Theme', _nextTheme),
        Binding(
          'ctrl+x b',
          'Toggle busy',
          () => setState(() => _busy = !_busy),
        ),
        Binding('ctrl+x c', 'Clear', () => setState(_log.clear)),
        Binding('ctrl+x f', 'Fill the log', _fill),
        Binding('ctrl+q', 'Quit', () => exitApp(context)),
        // The text input takes home and end itself, so they do not reach these.
        ...scrollBindings(
          _scroll,
          keys: const ScrollKeys(
            lineUp: ['shift+up'],
            lineDown: ['shift+down'],
          ),
        ),
      ],
      child: forced == null ? content : Theme(data: forced, child: content),
    );
  }

  Widget _content(BuildContext context) {
    final theme = Theme.of(context);
    final tint = theme.diff.tint;
    return Column(
      children: [
        Row(
          children: [
            Text(' chorded-tui demo ', style: theme.accent.merge(Style.bold)),
            // The label is dropped whole rather than cut when there is no room.
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final label = _themeLabel(context);
                  if (cellWidth(label) > constraints.maxWidth) {
                    return const SizedBox();
                  }
                  return Text(label, align: TextAlign.right, softWrap: false);
                },
              ),
            ),
          ],
        ),
        Expanded(
          child: Box(
            border: Border.rounded,
            title: 'log',
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Column(
              children: [
                if (_details)
                  Text.rich(
                    TextSpan(
                      '',
                      children: [
                        TextSpan('accent', style: theme.accent),
                        TextSpan(' '),
                        TextSpan('link', style: theme.link),
                        TextSpan(' '),
                        TextSpan('code', style: theme.inlineCode),
                        TextSpan(' '),
                        TextSpan('success', style: theme.success),
                        TextSpan(' '),
                        TextSpan('warning', style: theme.warning),
                        TextSpan(' '),
                        TextSpan('error', style: theme.error),
                        TextSpan('  '),
                        TextSpan(
                          '+',
                          style: (tint?.added ?? Style.plain).merge(
                            theme.diff.added,
                          ),
                        ),
                        TextSpan(
                          ' added',
                          style: tint == null
                              ? theme.diff.added
                              : tint.added.merge(tint.text),
                        ),
                        TextSpan('  '),
                        TextSpan(
                          '-',
                          style: (tint?.removed ?? Style.plain).merge(
                            theme.diff.removed,
                          ),
                        ),
                        TextSpan(
                          ' removed',
                          style: tint == null
                              ? theme.diff.removed
                              : tint.removed.merge(tint.text),
                        ),
                      ],
                    ),
                    softWrap: false,
                  ),
                if (_log.isEmpty)
                  Text(
                    'Type something and press enter. 日本語 and 🙂 are measured in cells.',
                    style: theme.dim,
                  )
                else
                  // Keyed: the details row above comes and goes, and the
                  // list must keep its element, and with it its anchor.
                  Expanded(
                    key: const ValueKey('log'),
                    child: ListView.builder(
                      controller: _scroll,
                      itemCount: _log.length,
                      itemVersion: (i) => (_log[i], _details),
                      itemBuilder: (context, i) => Row(
                        children: [
                          Text('${i + 1} ', style: theme.dim),
                          Expanded(child: Text(_log[i])),
                          if (_details)
                            Text(
                              ' ${cellWidth(_log[i])} cells',
                              style: theme.warning,
                            ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        Box(
          border: Border.rounded.withStyle(theme.focus),
          child: TextInput(
            controller: _draft,
            autofocus: true,
            prefix: '> ',
            placeholder: 'Say something',
            onSubmit: _submit,
          ),
        ),
        Row(
          spacing: 1,
          children: [
            Spinner(visible: _busy, style: theme.accent),
            const Expanded(child: KeyHelp()),
          ],
        ),
      ],
    );
  }
}
