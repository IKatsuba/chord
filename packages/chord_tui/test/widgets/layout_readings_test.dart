// A press that does nothing as typed is read again on the US layout: the
// terminal's base key, then the app's table; editing widgets never hear a
// reading, as docs/design/CTUI-67.md has it.
import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

List<String> _russian(String typed) => switch (typed) {
  'ф' => ['a'],
  'Ф' => ['A'],
  'ч' => ['x'],
  'о' => ['j'],
  _ => const [],
};

class _ReadingStream extends StatefulWidget {
  const _ReadingStream(this.stream);
  final Stream<int> stream;
  @override
  State<_ReadingStream> createState() => _ReadingStreamState();
}

class _ReadingStreamState extends State<_ReadingStream> {
  late final StreamSubscription<int> subscription;
  int count = 0;
  @override
  void initState() {
    super.initState();
    subscription = widget.stream.listen(
      (value) => setState(() => count = value),
    );
  }

  @override
  void dispose() {
    subscription.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('count $count');
}

class _ReadingUnbounded extends SingleChildRenderObjectWidget {
  const _ReadingUnbounded({required super.child});
  @override
  RenderBox createRenderObject(BuildContext context) => _ReadingUnboundedBox();
}

class _ReadingUnboundedBox extends RenderProxyBox {
  @override
  void performLayout() {
    child?.layout(const BoxConstraints());
    size = constraints.constrain(child?.size ?? Size.zero);
  }
}

void main() {
  group('tester: CTUI-67 editor and lifetime boundaries', () {
    for (final size in const [
      Size.zero,
      Size(1, 1),
      Size(80, 24),
      Size(120, 40),
    ]) {
      testWidgets(
        'a reading never edits Unicode or escape-bearing text across resize $size',
        (t) async {
          final text = TextAreaController(text: '界🙂e\u0301\x1b[31m');
          addTearDown(text.dispose);
          var calls = 0;
          final binding = Binding('ctrl+j', 'App action', () => calls++);
          await t.pumpWidget(
            Actions(
              bindings: [binding],
              child: TextArea(controller: text, autofocus: true),
            ),
            size: size,
            layoutFallback: _russian,
          );
          const typed = KeyEvent('о', ctrl: true, baseKey: 'j');
          final reading = t.focusManager.readingsOf(typed).single;
          expect(
            identical(t.focusManager.matchKey(reading).binding, binding),
            isTrue,
          );
          await t.sendKey(typed);
          await t.resize(const Size(80, 24));
          await t.sendKey(typed);
          expect(calls, 2);
          expect(text.text, '界🙂e\u0301\x1b[31m');
        },
      );
    }

    for (final size in const [Size(80, 24), Size(120, 40)]) {
      testWidgets(
        'Form edits typed text and routes readings differently in its list $size',
        (t) async {
          final form = FormController(
            fields: const [
              TextFormItem(name: 'text', label: 'Text', initialValue: 'abc'),
              ChoiceFormItem<String>(
                name: 'choice',
                label: 'Choice',
                options: [
                  PickerItem(value: 'first', label: 'First'),
                  PickerItem(value: 'second', label: 'Second'),
                ],
              ),
            ],
          );
          addTearDown(form.dispose);
          final calls = <String>[];
          final binding = Binding(
            'ctrl+a',
            'App action',
            () => calls.add('app'),
          );
          await t.pumpWidget(
            Actions(
              bindings: [
                binding,
                Binding('j', 'Ancestor j', () => calls.add('ancestor')),
              ],
              child: Form(
                controller: form,
                onSubmitted: (_) {},
                onCanceled: () {},
              ),
            ),
            size: size,
            layoutFallback: _russian,
          );
          await t.sendKey(const KeyEvent('ф', baseKey: 'a'));
          expect(form.value.values['text'], 'abcф');
          final cursor = form.value.cursor;
          final reading = t.focusManager
              .readingsOf(const KeyEvent('ф', ctrl: true, baseKey: 'a'))
              .single;
          expect(
            identical(t.focusManager.matchKey(reading).binding, binding),
            isTrue,
          );
          await t.sendKey(const KeyEvent('ф', ctrl: true, baseKey: 'a'));
          expect(form.value.cursor, cursor);
          expect(calls, ['app']);
          await t.press('down');
          await t.press('right');
          expect(form.value.listOpen, isTrue);
          await t.sendKey(const KeyEvent('о', baseKey: 'j'));
          expect(form.value.highlighted, 1);
          await t.press('enter');
          expect(form.value.values['choice'], 'second');
          expect(calls, ['app']);
        },
      );
    }

    testWidgets('unbounded child layout does not change reading dispatch', (
      t,
    ) async {
      var calls = 0;
      await t.pumpWidget(
        _ReadingUnbounded(
          child: Actions(
            bindings: [Binding('ctrl+x', 'App action', () => calls++)],
            child: Focus(autofocus: true, child: Text('界🙂e\u0301')),
          ),
        ),
        layoutFallback: _russian,
      );
      await t.press('ctrl+ч');
      expect(calls, 1);
    });

    testWidgets('preview follows focus away from an editor and back', (
      t,
    ) async {
      final editor = FocusNode();
      final other = FocusNode();
      final text = TextEditingController(text: '界🙂e\u0301');
      addTearDown(editor.dispose);
      addTearDown(other.dispose);
      addTearDown(text.dispose);
      final calls = <String>[];
      final app = Binding('ctrl+a', 'App action', () => calls.add('app'));
      final local = Binding('ctrl+a', 'Local action', () => calls.add('local'));
      await t.pumpWidget(
        Actions(
          bindings: [app],
          child: Column(
            children: [
              TextInput(controller: text, focusNode: editor, autofocus: true),
              Actions(
                bindings: [local],
                child: Focus(focusNode: other, child: Text('other')),
              ),
            ],
          ),
        ),
        layoutFallback: _russian,
      );
      final reading = t.focusManager
          .readingsOf(const KeyEvent('ф', ctrl: true))
          .single;
      expect(identical(t.focusManager.matchKey(reading).binding, app), isTrue);
      other.requestFocus();
      await t.pump();
      expect(
        identical(t.focusManager.matchKey(reading).binding, local),
        isTrue,
      );
      await t.press('ctrl+ф');
      editor.requestFocus();
      await t.pump();
      expect(identical(t.focusManager.matchKey(reading).binding, app), isTrue);
      await t.press('ctrl+ф');
      expect(calls, ['local', 'app']);
      expect(text.text, '界🙂e\u0301');
    });

    testWidgets(
      'a thousand updates coalesce and removal cancels the live stream and chord',
      (t) async {
        final stream = StreamController<int>.broadcast(sync: true);
        addTearDown(stream.close);
        var oldCalls = 0;
        await t.pumpWidget(
          Actions(
            bindings: [Binding('ctrl+x a', 'Old action', () => oldCalls++)],
            child: Focus(autofocus: true, child: _ReadingStream(stream.stream)),
          ),
          layoutFallback: _russian,
        );
        for (var i = 1; i <= 1000; i++) {
          stream.add(i);
        }
        await t.pump();
        expect(t.screen, shows('count 1000'));
        await t.press('ctrl+x');
        final old = t.focusManager;
        expect(old.pendingChord, isNotEmpty);
        await t.pumpWidget(
          Focus(autofocus: true, child: Text('new')),
          layoutFallback: _russian,
        );
        expect(stream.hasListener, isFalse);
        stream.add(1001);
        await t.press('ф');
        expect(old.isDisposed, isTrue);
        expect(old.dispatchKey(const KeyEvent('ф')), isFalse);
        expect(t.focusManager.pendingChord, isEmpty);
        expect(oldCalls, 0);
        expect(t.screen, shows('new'));
      },
    );
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('an exact binding as typed beats its reading, and the base '
        'key comes before the table, at $size', (t) async {
      final heard = <String>[];
      await t.pumpWidget(
        Actions(
          bindings: [
            Binding('ctrl+ч', 'typed', () => heard.add('typed')),
            Binding('ctrl+x', 'base', () => heard.add('base')),
            Binding('ctrl+y', 'table', () => heard.add('table')),
          ],
          child: Focus(autofocus: true, child: Text('here')),
        ),
        size: size,
        layoutFallback: (typed) => typed == 'ч' ? ['y'] : const [],
      );
      await t.sendKey(const KeyEvent('ч', ctrl: true, baseKey: 'x'));
      expect(heard, ['typed']);
      expect(
        t.focusManager
            .readingsOf(const KeyEvent('ч', ctrl: true, baseKey: 'x'))
            .map((r) => '${r.combo}'),
        ['ctrl+x', 'ctrl+y'],
      );
    });
  }

  testWidgets('without a typed binding the base key is read, then the '
      'table; nothing at all leaves the press unhandled', (t) async {
    final heard = <String>[];
    await t.pumpWidget(
      Actions(
        bindings: [
          Binding('ctrl+x', 'base', () => heard.add('base')),
          Binding('ctrl+y', 'table', () => heard.add('table')),
        ],
        child: Focus(autofocus: true, child: Text('here')),
      ),
      layoutFallback: (typed) => switch (typed) {
        'ч' => ['x', 'y'],
        'ш' => ['y'],
        _ => const [],
      },
    );
    await t.sendKey(const KeyEvent('ч', ctrl: true, baseKey: 'x'));
    expect(heard, ['base']);
    await t.press('ctrl+ч');
    expect(heard, ['base', 'base']);
    await t.press('ctrl+ш');
    expect(heard, ['base', 'base', 'table']);
    expect(
      t.focusManager.dispatchKey(const KeyEvent('q', ctrl: true)),
      isFalse,
    );
  });

  testWidgets('a reading goes past a focused TextArea to the app, and never '
      'its own keys', (t) async {
    final text = TextAreaController();
    final heard = <String>[];
    await t.pumpWidget(
      Actions(
        bindings: [Binding('ctrl+a', 'app', () => heard.add('app'))],
        child: TextArea(controller: text, autofocus: true),
      ),
      layoutFallback: _russian,
    );
    await t.type('abc');
    // ctrl+ф read as ctrl+a is the app's, not the text area's line start.
    await t.sendKey(const KeyEvent('ф', ctrl: true, baseKey: 'a'));
    expect(heard, ['app']);
    expect(text.cursor, 3);
    // ctrl+о read as ctrl+j is no newline in the text area.
    await t.sendKey(const KeyEvent('о', ctrl: true, baseKey: 'j'));
    expect(text.text, 'abc');
    // As typed, ctrl+a is still the text area's own.
    await t.press('ctrl+a');
    expect(heard, ['app']);
    expect(text.cursor, 0);
  });

  testWidgets('a typed character lands in a TextArea even with a binding '
      'on its reading above it', (t) async {
    final text = TextAreaController();
    final heard = <String>[];
    await t.pumpWidget(
      Actions(
        bindings: [Binding('a', 'app', () => heard.add('app'))],
        child: TextArea(controller: text, autofocus: true),
      ),
      layoutFallback: _russian,
    );
    await t.type('ф');
    await t.sendKey(const KeyEvent('ф', baseKey: 'a'));
    expect(text.text, 'фф');
    expect(heard, isEmpty);
  });

  testWidgets('a waiting chord finishes on a reading before it drops', (
    t,
  ) async {
    final heard = <String>[];
    await t.pumpWidget(
      Actions(
        bindings: [Binding('ctrl+x a', 'answer', () => heard.add('answer'))],
        child: Focus(autofocus: true, child: Text('here')),
      ),
      layoutFallback: _russian,
    );
    await t.press('ctrl+x');
    expect(t.focusManager.pendingChord, isNotEmpty);
    await t.press('ф');
    expect(heard, ['answer']);
    expect(t.focusManager.pendingChord, isEmpty);
    await t.press('ctrl+x');
    await t.press('й');
    expect(heard, ['answer']);
    expect(t.focusManager.pendingChord, isEmpty);
  });

  testWidgets('a picker, which sets nothing, moves on a reading of j', (
    t,
  ) async {
    String? picked;
    await t.pumpWidget(
      Picker<String>(
        items: const [
          PickerItem(value: 'one', label: 'One'),
          PickerItem(value: 'two', label: 'Two'),
        ],
        autofocus: true,
        onSelected: (value) => picked = value,
        onCanceled: () {},
      ),
    );
    await t.sendKey(const KeyEvent('о', baseKey: 'j'));
    await t.press('enter');
    expect(picked, 'two');
  });

  testWidgets('a TextInput is passed by too: its ctrl+a stays its own as '
      'typed, and a reading of it is the app\'s', (t) async {
    final text = TextEditingController();
    final heard = <String>[];
    await t.pumpWidget(
      Actions(
        bindings: [Binding('ctrl+a', 'app', () => heard.add('app'))],
        child: TextInput(controller: text, autofocus: true),
      ),
      layoutFallback: _russian,
    );
    await t.type('ab');
    await t.sendKey(const KeyEvent('ф', ctrl: true, baseKey: 'a'));
    expect(heard, ['app']);
    expect(text.cursor, 2);
    await t.press('ctrl+a');
    expect(heard, ['app']);
    expect(text.cursor, 0);
  });

  testWidgets('a reading previews as it dispatches: past the TextArea\'s '
      'own keys, even from a capture of the typed press', (t) async {
    final text = TextAreaController();
    final heard = <String>[];
    final app = Binding('ctrl+a', 'app', () => heard.add('app'));
    KeyBindingMatch? previewed;
    await t.pumpWidget(
      Actions(
        bindings: [app],
        child: Focus(
          canRequestFocus: false,
          onKeyCapture: (event) {
            final reading = t.focusManager.readingsOf(event).firstOrNull;
            if (reading != null) previewed = t.focusManager.matchKey(reading);
            return false;
          },
          child: TextArea(controller: text, autofocus: true),
        ),
      ),
      layoutFallback: _russian,
    );
    await t.sendKey(const KeyEvent('ф', ctrl: true, baseKey: 'a'));
    expect(identical(previewed?.binding, app), isTrue);
    expect(heard, ['app']);
  });
}
