import 'dart:async';

import 'package:chord_tui/chord_tui.dart';

void main() => runApp(const MarkdownExample());

/// A reply with every block Markdown draws, and keys to stream it in again
/// chunk by chunk, change the theme and scroll: the framework's `Markdown`
/// widget on its own.
class MarkdownExample extends StatefulWidget {
  const MarkdownExample({super.key});

  @override
  State<MarkdownExample> createState() => _MarkdownExampleState();
}

/// The reply shown.
const sample = '''# Terminal cells

A paragraph with *emphasis*, **strong**, ~~struck~~, `inline code`, a
[link](https://example.com), <https://auto.example> and 日本語 that wraps in
the width it receives, then continues at the same left edge.
After a hard break.

## Lists

- A first item
- A second item that is long enough to wrap, so its text hangs under its own first word and not under the marker
  - A nested item
- [x] A done task
- [ ] An open task

3. three
4. four

- loose one

- loose two

> A quoted paragraph that is long enough to wrap, keeping its bar on every row it takes.
>
> > A nested quote.

```dart example
void main() {
  print('A long message about terminal cells, 日本語, and keeping every grapheme together on screen.');
}
```

```
unlabelled
```

```nolanguage
unknown label, plain
```

| Name | Status | Count |
|:-----|:------:|------:|
| renderer | ready | 2 |
| a cell long enough to wrap inside its column | waiting | 10 |

---

![an image draws nothing](image.png)

[ref]: https://ref.example "A definition, shown as written"
''';

enum _Tone { dark, light, plain }

class _MarkdownExampleState extends State<MarkdownExample> {
  final _scroll = ScrollController();
  var _tone = _Tone.dark;
  var _shown = sample.length;
  Timer? _timer;

  /// Streams the reply in again, 24 characters every 30 ms.
  void _stream() {
    _timer?.cancel();
    setState(() => _shown = 0);
    _timer = Timer.periodic(const Duration(milliseconds: 30), (timer) {
      setState(() {
        _shown = (_shown + 24).clamp(0, sample.length);
        if (_shown == sample.length) timer.cancel();
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = switch (_tone) {
      _Tone.dark => ThemeData.dark(),
      _Tone.light => ThemeData.light(),
      _Tone.plain => ThemeData.plain(),
    };
    return Actions(
      bindings: [
        Binding('ctrl+s', 'Stream again', _stream),
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
    final text = sample.substring(0, _shown);
    final growing = _shown < sample.length;
    return Column(
      children: [
        Text(
          ' Markdown  ${_tone.name}, ${_shown * 100 ~/ sample.length}%',
          style: theme.accent,
        ),
        Expanded(
          child: ListView.builder(
            controller: _scroll,
            itemCount: 1,
            itemVersion: (i) => (text, _tone, growing),
            itemBuilder: (context, i) => Markdown(text, growing: growing),
          ),
        ),
        const KeyHelp(),
      ],
    );
  }
}
