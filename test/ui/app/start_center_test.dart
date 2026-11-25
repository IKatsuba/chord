import 'dart:async';

import 'package:chord/agents.dart';
import 'package:chord/ui/app/start.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final (size, markWidth, gap, artRows) in [
    (const Size(120, 40), 9, 3, 8),
    (const Size(80, 24), 4, 2, 4),
  ]) {
    test('plain art rounds odd centering down and right at $size', () async {
      final terminal = _Terminal(size);
      Screen? screen;
      await runApp(
        Builder(
          builder: (context) {
            context.owner.afterLayout(() {
              final buffer = Buffer(size.width, size.height);
              context.findRenderObject()!.paint(Canvas(buffer), Offset.zero);
              screen = Screen(buffer);
              exitApp(context);
            });
            return StartPage(
              version: '0.0.1',
              directory: '/workspace/demo',
              agents: [
                for (final name in ['claude', 'codex', 'pi'])
                  ListedAgent(
                    name: name,
                    title: name,
                    start: 'unused',
                    from: AgentRunner.cli,
                  ),
              ],
              onPicked: (_) {},
            );
          },
        ),
        terminal: terminal,
        exitProcess: false,
        environment: const {'NO_COLOR': '1'},
      ).timeout(const Duration(seconds: 3));
      final rows = screen!.lines;
      final first = rows.indexWhere((row) => row.contains('█'));
      final left = (size.width - (markWidth + gap + 5) + 1) ~/ 2;
      expect(rows[first].indexOf('█'), left);
      expect(
        rows[first + (artRows - 1 + 1) ~/ 2].indexOf('chord'),
        left + markWidth + gap,
      );
      await terminal.events.close();
    });
  }
}

class _Terminal extends Terminal {
  _Terminal(this.size);
  @override
  final Size size;
  final events = StreamController<String>();
  @override
  Stream<String> get input => events.stream;
  @override
  Stream<Size> get resizes => const Stream.empty();
  @override
  void enter() {}
  @override
  Future<void> leave() async {}
  @override
  void write(String data) {
    if (data == '\x1b]11;?\x07') events.add('\x1b]11;rgb:0000/0000/0000\x07');
  }
}
