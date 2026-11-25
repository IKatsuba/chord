import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

/// [child] in a box [width] cells wide, at the top left.
Widget narrow(int width, Widget child) => Align(
  alignment: Alignment.topLeft,
  child: SizedBox(width: width, child: child),
);

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('without defaults text wraps and clips, at $size', (t) async {
      await t.pumpWidget(narrow(8, Text('one two three')), size: size);
      expect(t.screen.lines.take(3), ['one two', 'three', '']);
    });
  }

  testWidgets('text takes the wrapping, overflow and limit around it', (
    t,
  ) async {
    await t.pumpWidget(
      narrow(
        8,
        DefaultTextStyle(
          style: Style.plain,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          child: Text('one two three'),
        ),
      ),
    );
    expect(t.screen.lines.take(2), ['one two…', '']);
  });

  testWidgets('a limit alone cuts the lines it wraps into', (t) async {
    await t.pumpWidget(
      narrow(
        8,
        DefaultTextStyle(
          style: Style.plain,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          child: Text('one two three'),
        ),
      ),
    );
    expect(t.screen.lines.take(2), ['one two…', '']);
  });

  testWidgets('text that says its own policy overrides the default', (t) async {
    await t.pumpWidget(
      narrow(
        8,
        DefaultTextStyle(
          style: Style.plain,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
          child: Text(
            'one two three',
            softWrap: true,
            overflow: TextOverflow.clip,
            maxLines: 2,
          ),
        ),
      ),
    );
    expect(t.screen.lines.take(3), ['one two', 'three', '']);
  });

  testWidgets('a box with a style keeps the policy around it', (t) async {
    await t.pumpWidget(
      narrow(
        8,
        DefaultTextStyle(
          style: Style.plain,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          child: Box(style: Style.bold, child: Text('one two three')),
        ),
      ),
    );
    expect(t.screen.lines.first, 'one two…');
    expect(t.screen.styleAt(0, 0), Style.bold);
  });

  testWidgets('a changed default reaches the text', (t) async {
    final cut = ValueNotifier(false);
    await t.pumpWidget(
      ListenableBuilder(
        listenable: cut,
        builder: (_) => narrow(
          8,
          DefaultTextStyle(
            style: Style.plain,
            softWrap: cut.value ? false : null,
            overflow: cut.value ? TextOverflow.ellipsis : null,
            child: const _Constant(),
          ),
        ),
      ),
    );
    expect(t.screen.lines.take(2), ['one two', 'three']);
    cut.value = true;
    await t.pump();
    expect(t.screen.lines.take(2), ['one two…', '']);
  });
  group('tester: inherited Text policy boundaries', () {
    testWidgets('rich and ANSI text obey inherited one-line clipping', (
      t,
    ) async {
      await t.pumpWidget(
        narrow(
          8,
          DefaultTextStyle(
            style: Style.bold,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            child: Column(
              children: [
                const Text.rich(TextSpan('界🙂e\u0301 tail')),
                Text.ansi('\x1b[31m界🙂e\u0301 tail\x1b[0m'),
              ],
            ),
          ),
        ),
      );
      expect(t.screen.lines.take(2), ['界🙂e\u0301 t…', '界🙂e\u0301 t…']);
      expect(t.screen.charAt(7, 0), '…');
      await t.resize(Size.zero);
      await t.resize(const Size(1, 1));
      await t.resize(const Size(80, 24));
      expect(t.screen.lines.take(2), ['界🙂e\u0301 t…', '界🙂e\u0301 t…']);
    });
    testWidgets('explicit policy remains after inherited policy changes', (
      t,
    ) async {
      final change = ValueNotifier(false);
      addTearDown(change.dispose);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: change,
          builder: (_) => narrow(
            8,
            DefaultTextStyle(
              style: Style.plain,
              softWrap: change.value,
              overflow: change.value
                  ? TextOverflow.clip
                  : TextOverflow.ellipsis,
              maxLines: change.value ? 5 : 1,
              child: Text(
                'one two three',
                softWrap: true,
                overflow: TextOverflow.clip,
                maxLines: 2,
              ),
            ),
          ),
        ),
      );
      expect(t.screen.lines.take(2), ['one two', 'three']);
      change.value = true;
      await t.pump();
      expect(t.screen.lines.take(2), ['one two', 'three']);
    });
  });
}

/// Text built once, so only the default can change it.
class _Constant extends StatelessWidget {
  const _Constant();

  @override
  Widget build(BuildContext context) => Text('one two three');
}
