import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

Widget _rows(ScrollController c) => SingleChildScrollView(
  controller: c,
  child: Column(children: [for (var i = 0; i < 100; i++) Text('row $i')]),
);

void main() {
  group('CHD-638 tester: retained scroll view boundaries', () {
    testWidgets('zero and one cell layouts recover with ANSI and wide text', (
      t,
    ) async {
      final c = ScrollController();
      await t.pumpWidget(
        SingleChildScrollView(
          controller: c,
          child: Text('\x1b[31m界👩‍💻e\u0301\x1b[0m\nlast'),
        ),
        size: Size.zero,
      );
      for (final size in [
        const Size(1, 1),
        const Size(2, 2),
        const Size(3, 3),
        const Size(80, 24),
        const Size(120, 40),
      ]) {
        await t.resize(size);
        expect(
          t.screen.lines.every((line) => cellWidth(line) <= size.width),
          isTrue,
        );
        expect(t.screen.text, isNot(contains('\x1b')));
      }
      expect(t.screen, shows('界👩‍💻e\u0301'));
      expect(t.screen, shows('last'));
    });

    for (final axis in ['width', 'height']) {
      testWidgets('unbounded $axis has an explicit constraint error', (
        t,
      ) async {
        final view = SingleChildScrollView(child: Text('content'));
        await expectLater(
          t.pumpWidget(
            axis == 'width' ? Row(children: [view]) : Column(children: [view]),
          ),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('unbounded $axis'),
            ),
          ),
        );
      });
    }

    testWidgets('rowOf includes padding and aligned reveal moves the least', (
      t,
    ) async {
      final c = ScrollController();
      late BuildContext target;
      await t.pumpWidget(
        SingleChildScrollView(
          controller: c,
          padding: const EdgeInsets.only(top: 2),
          child: Column(
            children: [
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Builder(
                  builder: (context) {
                    target = context;
                    return Text('target');
                  },
                ),
              ),
              const SizedBox(height: 60),
            ],
          ),
        ),
        size: const Size(20, 10),
      );
      expect(Scrollable.rowOf(target), 9);
      Scrollable.ensureVisible(target, alignment: 0.5);
      await t.pump();
      expect(c.offset, 4);
      Scrollable.ensureVisible(target);
      await t.pump();
      expect(c.offset, 4, reason: 'already visible');
      Scrollable.ensureVisible(target, alignment: 0);
      await t.pump();
      expect(c.offset, 9);
      expect(t.screen.lines.first, 'target');
    });

    testWidgets('replacing a controller detaches without disposing either', (
      t,
    ) async {
      final first = ScrollController(), second = ScrollController();
      final current = ValueNotifier(first);
      addTearDown(current.dispose);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: current,
          builder: (_) => _rows(current.value),
        ),
      );
      first.jumpTo(50);
      await t.pump();
      expect(t.screen.lines.first, 'row 50');
      current.value = second;
      await t.pump();
      first.toBottom();
      await t.pump();
      expect(second.offset, 0);
      expect(t.screen.lines.first, 'row 0');
      second.jumpTo(20);
      await t.pump();
      expect(t.screen.lines.first, 'row 20');
      await t.pumpWidget(Text('removed'));
      expect(() => second.jumpTo(30), returnsNormally);
      expect(() => first.jumpTo(30), returnsNormally);
    });

    testWidgets(
      'offscreen state receives 1000 updates and removal cancels its stream',
      (t) async {
        final source = StreamController<int>();
        addTearDown(source.close);
        final c = ScrollController();
        final received = <int>[];
        await t.pumpWidget(
          SingleChildScrollView(
            controller: c,
            child: Column(
              children: [
                _Counter(source.stream, received.add),
                const SizedBox(height: 100),
              ],
            ),
          ),
        );
        c.toBottom();
        await t.pump();
        for (var i = 0; i < 1000; i++) {
          source.add(i);
        }
        await t.pump();
        expect(received, hasLength(1000));
        expect(t.screen, isNot(shows('value999')));
        c.toTop();
        await t.pump();
        expect(t.screen, shows('value999'));
        await t.pumpWidget(Text('removed'));
        expect(source.hasListener, isFalse);
        source.add(1000);
        await t.pump();
        expect(received, hasLength(1000));
        expect(t.screen.text, 'removed');
      },
    );
  });
}

class _Counter extends StatefulWidget {
  const _Counter(this.stream, this.received);
  final Stream<int> stream;
  final void Function(int) received;
  @override
  State<_Counter> createState() => _CounterState();
}

class _CounterState extends State<_Counter> {
  late StreamSubscription<int> _subscription;
  var value = -1;
  @override
  void initState() {
    super.initState();
    _subscription = widget.stream.listen((next) {
      widget.received(next);
      setState(() => value = next);
    });
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('value$value');
}
