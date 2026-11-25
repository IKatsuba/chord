/// A hand-run benchmark of Markdown under a streamed reply: a reply grows
/// chunk by chunk to about 50 KB in a list that follows the bottom, one
/// frame per chunk, printing frame times as it grows; then the same for a
/// reply that is one long code block, which the parse cannot freeze, whose
/// frames at 50 KB are held to [budgetMs]; the exit code is 1 when over.
/// Each stream ends with one frame of the finished reply, which colours an
/// open code block whole.
///
///     dart run benchmark/markdown_stream.dart
///     dart compile exe benchmark/markdown_stream.dart -o build/markdown_stream
///
/// It drives an [AppHost] without a terminal, so it times parsing, build,
/// layout and paint; writing to a terminal is not in it. Frames run back
/// to back, not paced by the clock.
library;

import 'dart:io';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/text/markdown.dart';

const chunk = 40;

/// A frame at 60 Hz: the most the frame at 50 KB of one open code block
/// may take under `dart compile exe`.
const budgetMs = 16;
const target = 50 * 1024;

/// A reply shaped like an agent's: headings, paragraphs that wrap, lists,
/// code and a table, repeated.
String reply() {
  const part = '''## Step

A paragraph with **bold**, `code`, a [link](https://example.com) and 日本語,
long enough to wrap at eighty columns and again at forty, with more words.

- a point with *emphasis*
- another point
  - nested

```dart
void main() {
  print('hello');
}
```

| name | status |
|------|--------|
| one  | ready  |

''';
  final out = StringBuffer();
  while (out.length < target) {
    out.write(part);
  }
  return out.toString();
}

/// One long open code block: every chunk lands in the last block.
String codeReply() {
  final out = StringBuffer('```dart\n');
  var i = 0;
  while (out.length < target) {
    out.writeln('final value$i = compute($i); // line $i');
    i++;
  }
  return out.toString();
}

void report(String name, List<Duration> frames) {
  final ms = [for (final f in frames) f.inMicroseconds / 1000]..sort();
  String at(double q) =>
      ms[((ms.length - 1) * q).round()].toStringAsFixed(2).padLeft(8);
  print(
    '${name.padRight(40)} frames ${'${ms.length}'.padLeft(5)}  '
    'median ${at(0.5)}  p95 ${at(0.95)}  max ${at(1)} ms',
  );
}

Duration time(void Function() fn) {
  final sw = Stopwatch()..start();
  fn();
  return sw.elapsed;
}

(List<Duration>, Duration) stream(String name, String full, Size size) {
  // The text, and whether the reply is still streaming.
  final text = ValueNotifier(('', true));
  final host = AppHost(
    ListenableBuilder(
      listenable: text,
      builder: (context) => ListView.builder(
        controller: ScrollController(follow: Follow.bottom),
        itemCount: 1,
        itemVersion: (i) => text.value,
        itemBuilder: (context, i) =>
            Markdown(text.value.$1, growing: text.value.$2),
      ),
    ),
  );
  final frames = <Duration>[];
  var next = 10 * 1024;
  for (var end = chunk; end <= full.length; end += chunk) {
    frames.add(
      time(() {
        text.value = (full.substring(0, end), true);
        host.drawFrame(size);
      }),
    );
    if (end >= next) {
      report('$name to ${end ~/ 1024} KB', frames.sublist(frames.length - 50));
      next += 10 * 1024;
    }
  }
  report('$name, every frame', frames);
  // The reply ends: what grew is drawn once more, finished, which colours
  // an open code block whole.
  final close = time(() {
    text.value = (full, false);
    host.drawFrame(size);
  });
  report('$name, the frame at its end', [close]);
  host.dispose();
  return (frames, close);
}

/// The parse alone, appended to chunk by chunk, against a whole parse of
/// each chunk: what freezing the leading blocks saves.
void parse(String name, String full) {
  final parser = MarkdownParser();
  final appended = <Duration>[];
  final whole = <Duration>[];
  for (var end = chunk; end <= full.length; end += chunk) {
    final text = full.substring(0, end);
    appended.add(time(() => parser.update(text)));
    if (end % (chunk * 25) == 0) {
      whole.add(time(() => MarkdownParser().update(text)));
    }
  }
  report('$name: parse, appended', appended);
  report('$name: parse, whole (every 25th chunk)', whole);
}

void main() {
  final text = reply();
  final code = codeReply();
  parse('reply', text);
  parse('one code block', code);
  stream('reply at 120x40', text, const Size(120, 40));
  stream('reply at 80x24', text, const Size(80, 24));
  final (frames, close) = stream(
    'one code block at 120x40',
    code,
    const Size(120, 40),
  );
  // The budget is a frame at 60 Hz, for the frames at the end of the open
  // block, where each chunk lands in 50 KB of code; it holds compiled.
  final end = [
    for (final f in frames.sublist(frames.length - 50)) f.inMicroseconds,
  ]..sort();
  final median = end[end.length ~/ 2] / 1000;
  final within = median <= budgetMs;
  print(
    'one code block at 50 KB: median ${median.toStringAsFixed(2)} ms, '
    'budget $budgetMs ms: ${within ? 'within' : 'OVER'}',
  );
  print(
    'one code block at 50 KB, finished: '
    '${(close.inMicroseconds / 1000).toStringAsFixed(2)} ms, once',
  );
  if (!within) exitCode = 1;
}
