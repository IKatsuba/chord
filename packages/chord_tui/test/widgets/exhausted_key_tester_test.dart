import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

class _ChangingFocus extends StatefulWidget {
  const _ChangingFocus({required this.built, required this.received});

  final List<int> built;
  final List<String> received;

  @override
  State<_ChangingFocus> createState() => _ChangingFocusState();
}

class _ChangingFocusState extends State<_ChangingFocus> {
  int generation = 0;

  @override
  Widget build(BuildContext context) {
    final current = generation;
    widget.built.add(current);
    context.owner.afterLayout(() {
      if (mounted) setState(() => generation++);
    });
    return Actions(
      key: ValueKey(current),
      bindings: [
        Binding('ctrl+k', 'Record current tree', () {
          widget.received.add('$current:action');
        }),
      ],
      child: Focus(
        autofocus: true,
        onKey: (event) {
          if (event.ctrl) return false;
          widget.received.add('$current:${event.key}');
          return true;
        },
        child: Text('界👩‍💻é\x1b[31m edge'),
      ),
    );
  }
}

class _StreamChurn extends StatefulWidget {
  const _StreamChurn({required this.updates, required this.received});

  final Stream<int> updates;
  final List<String> received;

  @override
  State<_StreamChurn> createState() => _StreamChurnState();
}

class _StreamChurnState extends State<_StreamChurn> {
  late final StreamSubscription<int> subscription;
  int value = 0;

  @override
  void initState() {
    super.initState();
    subscription = widget.updates.listen((next) {
      setState(() => value = next);
    });
  }

  @override
  Widget build(BuildContext context) {
    context.owner.afterLayout(() {
      if (mounted) setState(() {});
    });
    return Focus(
      autofocus: true,
      onKey: (event) {
        widget.received.add('$value:${event.key}');
        return true;
      },
      child: Text('$value'),
    );
  }

  @override
  void dispose() {
    subscription.cancel();
    super.dispose();
  }
}

void main() {
  group('tester: exhausted keys use the completed mounted tree', () {
    for (final size in [
      const Size(0, 0),
      const Size(1, 1),
      const Size(80, 24),
      const Size(120, 40),
    ]) {
      testWidgets('replacement focus and bindings stay current $size', (
        t,
      ) async {
        final built = <int>[];
        final received = <String>[];
        await t.pumpWidget(
          _ChangingFocus(built: built, received: received),
          size: size,
        );
        for (final event in [
          const KeyEvent('界'),
          const KeyEvent('👩‍💻'),
          const KeyEvent('é'),
          const KeyEvent('escape'),
          const KeyEvent('k', ctrl: true),
        ]) {
          final before = t.inputLayoutPasses;
          expect(t.host.handleKey(event), isTrue);
          expect(t.inputLayoutPasses - before, 2);
          expect(
            received.last,
            '${built.last}:${event.ctrl ? 'action' : event.key}',
          );
        }
        expect(received, hasLength(5));
        await t.resize(const Size(80, 24));
        final before = t.inputLayoutPasses;
        expect(t.host.handleKey(const KeyEvent('r')), isTrue);
        expect(t.inputLayoutPasses - before, 2);
        expect(received.last, '${built.last}:r');
        await t.pump();
        expect(received, hasLength(6));
      });
    }

    testWidgets('a thousand updates coalesce before keys and detach safely', (
      t,
    ) async {
      final updates = StreamController<int>(sync: true);
      addTearDown(updates.close);
      final received = <String>[];
      await t.pumpWidget(
        _StreamChurn(updates: updates.stream, received: received),
      );
      for (var i = 0; i < 1000; i++) {
        updates.add(i);
      }
      for (final key in ['a', 'b', 'c']) {
        final before = t.inputLayoutPasses;
        expect(t.host.handleKey(KeyEvent(key)), isTrue);
        expect(t.inputLayoutPasses - before, 2);
      }
      expect(received, ['999:a', '999:b', '999:c']);
      await t.pumpWidget(Text('removed'));
      expect(updates.hasListener, isFalse);
      updates.add(1000);
      await t.pump();
      expect(received, ['999:a', '999:b', '999:c']);
      expect(t.screen, shows('removed'));
    });
  });
}
