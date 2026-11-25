import 'dart:io';

import 'package:chord_tui/chord_tui.dart';

Future<void> main(List<String> args) => runApp(
  TextAreaSpansExample(
    light: args.contains('--light'),
    zero: args.contains('--zero'),
  ),
  environment: {
    ...Platform.environment,
    if (args.contains('--plain')) 'NO_COLOR': '1',
  },
);

/// Editable text with whole-text decoration and its actual reported viewport.
class TextAreaSpansExample extends StatefulWidget {
  const TextAreaSpansExample({
    super.key,
    this.light = false,
    this.zero = false,
  });
  final bool light, zero;
  @override
  State<TextAreaSpansExample> createState() => _TextAreaSpansExampleState();
}

class _TextAreaSpansExampleState extends State<TextAreaSpansExample> {
  final _text = TextAreaController(
    text: 'Context ${'x' * 60}needle crosses\n終わり 😀 é',
  );
  TextAreaLayout? _layout;
  bool _decorated = true;
  late bool _light = widget.light;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _layoutChanged(TextAreaLayout layout) =>
      setState(() => _layout = layout);

  TextSpan _spans(BuildContext context, String text) {
    const query = 'needle crosses';
    final parts = <TextSpan>[];
    var at = 0;
    while (true) {
      final hit = text.indexOf(query, at);
      if (hit < 0) break;
      parts.add(TextSpan(text.substring(at, hit)));
      parts.add(const TextSpan(query, style: Style.inverse));
      at = hit + query.length;
    }
    parts.add(TextSpan(text.substring(at)));
    return TextSpan('', children: parts);
  }

  @override
  Widget build(BuildContext context) => Theme(
    data: _light ? ThemeData.light() : ThemeData.dark(),
    child: Builder(
      builder: (context) => Actions(
        bindings: [
          Binding(
            'ctrl+g',
            'Toggle decoration',
            () => setState(() => _decorated = !_decorated),
          ),
          Binding(
            'ctrl+t',
            'Toggle theme',
            () => setState(() => _light = !_light),
          ),
          Binding('ctrl+q', 'Quit', () => exitApp(context)),
        ],
        child: Column(
          children: [
            Expanded(
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  height: widget.zero ? 0 : null,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 2,
                        child: Column(
                          children: [
                            for (final row
                                in _layout?.shownRows ?? <TextAreaRow>[])
                              Text(
                                row.line == 0 && row.piece == 0 ? '› ' : '  ',
                                style: Theme.of(context).dim,
                              ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: TextArea(
                          controller: _text,
                          autofocus: true,
                          maxHeight: 6,
                          textSpanBuilder: _decorated ? _spans : null,
                          onLayoutChanged: _layoutChanged,
                          unhandledKeys: const {
                            'home',
                            'end',
                            'ctrl+g',
                            'ctrl+t',
                            'ctrl+q',
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Text(
              _layout == null
                  ? ''
                  : _layout!.height == 0
                  ? 'rows 0 of ${_layout!.rows.length}'
                  : 'rows ${_layout!.rowOffset + 1}–${_layout!.rowOffset + _layout!.height} of ${_layout!.rows.length}',
              style: Theme.of(context).dim,
              softWrap: false,
            ),
            KeyHelp.builder(
              builder: (_, bindings, pending) => Text(
                bindings
                    .where(
                      (b) => const {
                        'Toggle decoration',
                        'Toggle theme',
                        'Quit',
                      }.contains(b.description),
                    )
                    .map((b) => '${b.chord} ${b.description}')
                    .join(' · '),
                softWrap: false,
                overflow: TextOverflow.middle,
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
