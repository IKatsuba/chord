/// A hand-run benchmark of ListView: 10 000 markdown-like entries, a resize,
/// and streaming at 16 appends per frame (about 1 000 a second at 60 fps),
/// printing frame times.
///
///     dart run benchmark/list_view.dart
///     dart compile exe benchmark/list_view.dart -o build/list_view_bench
///
/// It drives an [AppHost] without a terminal, so it times build, layout and
/// paint; writing to a terminal is not in it. Streaming is simulated frame
/// by frame, back to back, not paced by the clock: 312 frames of 16 appends,
/// the frames five seconds at 60 fps would have.
///
/// The switch run models chord's window showing another session: two
/// sessions of 10 000 entries, each with its own retained
/// [ScrollController], one following and one scrolled back to its middle.
/// The list is keyed by the shown session, as the window keys its
/// transcript, so every switch unmounts one viewport and builds another.
/// Item heights live on the controller, so the new viewport reuses those
/// measured under unchanged versions: only the first attach of a session
/// and an attach at a new width measure every entry. It times the switch
/// frames, and the round trip back to the scrolled-back session, which
/// must land on the entry it left, a resize while away included.
library;

import 'package:chord_tui/chord_tui.dart';

const entries = 10000;
const frameMs = 16;
const appendsPerSecond = 1000;
const streamSeconds = 5;

/// An entry shaped like a chat reply in markdown: a heading, a paragraph
/// that wraps, a list, and sometimes a code block.
List<String> entry(int i) => [
  '## Entry $i',
  'This is paragraph $i of the transcript, long enough to wrap at eighty '
      'columns and again at forty, with ${'some more words ' * (i % 5)}in it.',
  for (var b = 0; b < i % 4; b++) '- point $b of entry $i',
  if (i % 3 == 0) ...['```dart', 'final x$i = compute($i);', '```'],
];

class EntryView extends StatelessWidget {
  const EntryView(this.lines, {super.key});

  final List<String> lines;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 1),
    child: Column(
      children: [
        for (final l in lines)
          Text(
            l,
            style: l.startsWith('#')
                ? Style.bold
                : l.startsWith('```') || l.startsWith('final')
                ? Style.dim
                : null,
          ),
      ],
    ),
  );
}

/// Times [frames] and prints min, median, p95 and max in milliseconds.
void report(String name, List<Duration> frames) {
  final ms = [for (final f in frames) f.inMicroseconds / 1000]..sort();
  String at(double q) =>
      ms[((ms.length - 1) * q).round()].toStringAsFixed(2).padLeft(8);
  print(
    '${name.padRight(44)} frames ${'${ms.length}'.padLeft(4)}  '
    'min ${at(0)}  median ${at(0.5)}  p95 ${at(0.95)}  max ${at(1)} ms',
  );
}

Duration time(void Function() fn) {
  final sw = Stopwatch()..start();
  fn();
  return sw.elapsed;
}

void main() {
  final data = ValueNotifier([for (var i = 0; i < entries; i++) entry(i)]);
  final scroll = ScrollController(follow: Follow.bottom);
  final host = AppHost(
    ListenableBuilder(
      listenable: data,
      builder: (context) => ListView.builder(
        controller: scroll,
        itemCount: data.value.length,
        itemVersion: (i) => data.value[i],
        itemBuilder: (context, i) => EntryView(data.value[i]),
      ),
    ),
  );

  var size = const Size(120, 40);
  report('first frame, 10 000 entries', [time(() => host.drawFrame(size))]);
  print('  content rows: ${scroll.contentRows}');
  report('steady frames', [
    for (var i = 0; i < 100; i++) time(() => host.drawFrame(size)),
  ]);

  size = const Size(80, 24);
  report('resize to 80x24', [time(() => host.drawFrame(size))]);
  size = const Size(120, 40);
  report('resize back to 120x40', [time(() => host.drawFrame(size))]);

  void stream(String name) {
    final perFrame = appendsPerSecond * frameMs ~/ 1000;
    final frames = <Duration>[];
    for (var f = 0; f < streamSeconds * 1000 ~/ frameMs; f++) {
      frames.add(
        time(() {
          final next = List.of(data.value);
          for (var a = 0; a < perFrame; a++) {
            next.add(entry(next.length));
          }
          data.value = next;
          host.drawFrame(size);
        }),
      );
    }
    report(name, frames);
  }

  stream('16 appends/frame (~1 000/s), following');
  print('  entries: ${data.value.length}, following: ${scroll.isFollowing}');
  scroll.pageUp();
  host.drawFrame(size);
  stream('16 appends/frame (~1 000/s), scrolled back');
  print('  rows below: ${scroll.rowsBelow}');

  host.dispose();

  switchFrames();
}

/// Switching between two sessions' retained controllers; after each one's
/// first attach, a switch at the same width reuses its heights.
void switchFrames() {
  const switches = 40;
  final sessions = [
    for (var s = 0; s < 2; s++)
      [for (var i = 0; i < entries; i++) entry(i + s * entries)],
  ];
  final scrolls = [
    for (var s = 0; s < 2; s++) ScrollController(follow: Follow.bottom),
  ];
  final shown = ValueNotifier(0);
  final host = AppHost(
    ListenableBuilder(
      listenable: shown,
      builder: (context) {
        final items = sessions[shown.value];
        return ListView.builder(
          // A new viewport per session, as the window's keyed transcript.
          key: ValueKey(('transcript', shown.value)),
          controller: scrolls[shown.value],
          itemCount: items.length,
          itemVersion: (i) => items[i],
          itemBuilder: (context, i) => EntryView(items[i]),
        );
      },
    ),
  );

  var size = const Size(120, 40);
  host.drawFrame(size);
  shown.value = 1;
  host.drawFrame(size);
  final back = scrolls[1]..jumpTo(scrolls[1].contentRows ~/ 2);
  host.drawFrame(size);
  final entryLeft = back.firstVisible;
  final offsetLeft = back.offset;
  print(
    'switch: 2 sessions of ${sessions[0].length} entries, '
    '${back.contentRows} rows each at 120x40; session 1 left at entry '
    '$entryLeft, row $offsetLeft',
  );

  final toFollowing = <Duration>[];
  final toScrolledBack = <Duration>[];
  final roundTrips = <Duration>[];
  var landed = 0;
  for (var n = 0; n < switches; n++) {
    final away = time(() {
      shown.value = 0;
      host.drawFrame(size);
    });
    final home = time(() {
      shown.value = 1;
      host.drawFrame(size);
    });
    toFollowing.add(away);
    toScrolledBack.add(home);
    roundTrips.add(away + home);
    if (back.firstVisible == entryLeft && back.offset == offsetLeft) landed++;
  }
  report('switch to the following session', toFollowing);
  report('switch to the scrolled-back session', toScrolledBack);
  report('round trip, two switch frames', roundTrips);
  print(
    '  landed on entry $entryLeft at row $offsetLeft: $landed of '
    '$switches; following: ${scrolls[0].isFollowing}',
  );

  // Away at another width, back at it: the anchor, not the row, decides.
  shown.value = 0;
  host.drawFrame(size);
  size = const Size(80, 24);
  host.drawFrame(size);
  shown.value = 1;
  report('switch back after a resize to 80x24', [
    time(() => host.drawFrame(size)),
  ]);
  print(
    '  entry ${back.firstVisible} (left at $entryLeft), '
    'row ${back.offset} of ${back.contentRows}',
  );

  host.dispose();
  for (final s in scrolls) {
    s.dispose();
  }
}
