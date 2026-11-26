import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

class _Terminal extends Terminal {
  final input$ = StreamController<String>();

  @override
  Size get size => const Size(80, 24);

  @override
  Stream<String> get input => input$.stream;

  @override
  Stream<Size> get resizes => const Stream.empty();

  @override
  void write(String data) {}

  @override
  void enter() {}

  @override
  Future<void> leave() async {}
}

void main() {
  test('TerminalScope.of gives the terminal runApp was given', () async {
    final term = _Terminal();
    Terminal? seen;
    final running = runApp(
      Builder(
        builder: (context) {
          seen = TerminalScope.of(context);
          return Text('app');
        },
      ),
      terminal: term,
      exitProcess: false,
      handleSignals: false,
      environment: const {},
    );
    await Future<void>.delayed(const Duration(milliseconds: 200));
    await term.input$.close();
    await running;
    expect(seen, same(term));
  });

  testWidgets('the tester gives its recording terminal', (t) async {
    Terminal? seen;
    await t.pumpWidget(
      Builder(
        builder: (context) {
          seen = TerminalScope.maybeOf(context);
          TerminalScope.of(context).openUrl('https://example.com');
          return Text('app');
        },
      ),
      size: const Size(120, 40),
    );
    expect(seen, same(t.terminal));
    expect(t.terminal.openedUrls, ['https://example.com']);
    expect(t.terminal.size, const Size(120, 40));
    await t.resize(const Size(80, 24));
    expect(t.terminal.size, const Size(80, 24));
  });

  testWidgets('a TerminalScope gives its subtree another terminal', (t) async {
    final other = _Terminal();
    Terminal? inside, outside;
    await t.pumpWidget(
      Column(
        children: [
          Builder(
            builder: (context) {
              outside = TerminalScope.of(context);
              return Text('out');
            },
          ),
          TerminalScope(
            terminal: other,
            child: Builder(
              builder: (context) {
                inside = TerminalScope.of(context);
                return Text('in');
              },
            ),
          ),
        ],
      ),
    );
    expect(outside, same(t.terminal));
    expect(inside, same(other));
  });

  test('TerminalScope.of says what is missing without a scope', () {
    final host = AppHost(
      Builder(
        builder: (context) {
          TerminalScope.of(context);
          return Text('');
        },
      ),
      onExit: () {},
    );
    addTearDown(host.dispose);
    final frame = host.drawFrame(const Size(80, 24));
    expect(Screen(frame).text, contains('No TerminalScope'));
  });
}
