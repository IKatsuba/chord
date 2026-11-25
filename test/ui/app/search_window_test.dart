import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import 'steering_window_test.dart' show connected, send;
import 'window_fake_test.dart' show until;

TextAreaController editor(WidgetTester t) {
  TextAreaController? found;
  void visit(Element e) {
    if (e.widget case TextArea(:final controller)) found = controller;
    e.visitChildren(visit);
  }

  visit(t.host.rootElement);
  return found!;
}

void main() {
  _testerSearchOwnershipBoundaries();
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'search preserves draft/cursor/undo and accepts without sending $size',
      (t) async {
        final f = await connected(t, size);
        await send(t, 'alpha first');
        await send(t, 'alpha second');
        await send(t, 'alpha first');
        await t.type('draft 界😀');
        await t.press('left');
        final saved = editor(t), cursor = editor(t).cursor;
        final text = saved.text;
        final savedLayout = saved.lastLayout;
        await t.press('ctrl+r');
        expect(f.connection.app.value.search, isNotNull);
        await t.type('alpha');
        expect(f.connection.app.value.search?.match, 2);
        expect(editor(t).text, 'alpha first');
        expect(editor(t), isNot(same(saved)));
        expect(t.screen, shows('search prompts: alpha'));
        expect(t.screen.buffer.cursor, isNull);
        await t.press('ctrl+r');
        expect(editor(t).text, 'alpha second');
        await t.press('ctrl+r');
        expect(f.connection.app.value.search?.failed, isTrue);
        expect(t.screen, shows('no matching prompt: alpha'));
        expect(saved.text, text);
        expect(saved.cursor, cursor);
        expect(saved.lastLayout, same(savedLayout));
        await t.press('esc');
        expect(editor(t), same(saved));
        expect(saved.text, text);
        expect(saved.cursor, cursor);
        await t.press('ctrl+z');
        expect(saved.text, 'draft 界');
        await t.press('ctrl+y');
        expect(saved.text, text);
        await t.press('ctrl+r');
        await t.paste('second\nnot query');
        expect(f.connection.app.value.search?.query, 'second');
        await t.press('tab');
        expect(f.connection.app.value.search, isNull);
        expect(saved.text, 'alpha second');
        expect(
          f.agent.requests.where((r) => r['method'] == 'session/prompt'),
          hasLength(1),
        );
        expect(
          f.agent.requests.where((r) => r['method'] == '_session/steering'),
          isEmpty,
        );
        expect(
          t.focusManager.primaryFocus?.debugLabel,
          'prompt',
          reason: t.focusManager.activeBindings
              .map((b) => b.description)
              .join(', '),
        );
      },
    );
    testWidgets(
      'bracketed paste edits only first query line without sending $size',
      (t) async {
        final f = await connected(t, size);
        await send(t, 'alpha reference');
        await t.type('saved 界😀');
        await t.press('left');
        final saved = editor(t),
            text = editor(t).text,
            cursor = editor(t).cursor;
        final savedLayout = saved.lastLayout;
        await t.press('ctrl+r');
        final events = InputParser().feed('\x1b[200~alpha\nignored\x1b[201~');
        expect(events, hasLength(1));
        final pasted = events.single as PasteEvent;
        expect(pasted.text, 'alpha\nignored');
        t.host.handlePaste(pasted.text);
        await t.pump();
        expect(f.connection.app.value.search?.query, 'alpha');
        expect(editor(t).text, 'alpha reference');
        expect(saved.text, text);
        expect(saved.cursor, cursor);
        expect(saved.lastLayout, same(savedLayout));
        expect(
          f.agent.requests.where((r) => r['method'] == 'session/prompt'),
          hasLength(1),
        );
        expect(
          f.agent.requests.where((r) => r['method'] == '_session/steering'),
          isEmpty,
        );
        await t.press('esc');
        expect(editor(t), same(saved));
        expect(saved.text, text);
        expect(saved.cursor, cursor);
      },
    );
    testWidgets('empty/missing search cancellation and modified edits $size', (
      t,
    ) async {
      final f = await connected(t, size);
      await t.type('original');
      final saved = editor(t);
      await t.press('ctrl+r');
      await t.press('enter');
      expect(saved.text, 'original');
      expect(f.agent.hasPrompt, isFalse);
      await t.press('ctrl+r');
      await t.type('界😀');
      await t.press('backspace');
      expect(f.connection.app.value.search?.query, '界');
      await t.press('delete');
      expect(f.connection.app.value.search?.query, '');
      await t.type('?none');
      expect(f.connection.app.value.shortcuts.help, isFalse);
      expect(f.connection.app.value.search?.failed, isTrue);
      await t.press('ctrl+c');
      expect(saved.text, 'original');
      expect(f.connection.app.value.search, isNull);
    });
    for (final accept in ['enter', 'tab']) {
      testWidgets(
        'query $accept recalls once at clipped8x3 without sending $size',
        (t) async {
          final f = await connected(t, size);
          await send(t, 'alpha long 界😀 ${'word ' * 80}');
          await t.type('saved');
          final saved = editor(t);
          await t.press('ctrl+r');
          await t.type('alpha');
          final shown = editor(t).text;
          await t.resize(const Size(32, 10));
          expect(saved.text, 'saved');
          await t.resize(const Size(8, 3));
          await t.press(accept);
          expect(f.connection.app.value.search, isNull);
          expect(saved.text, shown);
          await t.resize(size);
          expect(saved.text, shown);
          expect(
            f.agent.requests.where((r) => r['method'] == 'session/prompt'),
            hasLength(1),
          );
          expect(
            f.agent.requests.where((r) => r['method'] == '_session/steering'),
            isEmpty,
          );
        },
      );
    }
    testWidgets('zero surface keeps query and saved editor inert $size', (
      t,
    ) async {
      final f = await connected(t, size);
      await send(t, 'alpha');
      await t.type('saved');
      final saved = editor(t);
      await t.press('ctrl+r');
      await t.type('alpha');
      await t.resize(Size.zero);
      await t.press('enter tab');
      await t.type('hidden');
      expect(f.connection.app.value.search?.query, 'alpha');
      expect(saved.text, 'saved');
      await t.resize(size);
      expect(f.connection.app.value.search, isNotNull);
      await t.press('esc');
      expect(saved.text, 'saved');
    });
    testWidgets(
      'verbose reuses full thought/tool renderer and preserves search $size',
      (t) async {
        final f = await connected(t, size);
        await send(t, 'alpha');
        f.agent.update({
          'sessionUpdate': 'agent_thought_chunk',
          'content': {'type': 'text', 'text': 'Reasoning detail 界😀'},
        });
        f.agent.update({
          'sessionUpdate': 'tool_call',
          'toolCallId': 'fixture-details',
          'title': 'Inspect facts',
          'kind': 'other',
          'status': 'completed',
          'content': [
            {
              'type': 'content',
              'content': {'type': 'text', 'text': 'Full tool detail'},
            },
          ],
        });
        await t.pump();
        await t.type('saved');
        final saved = editor(t), savedLayout = editor(t).lastLayout;
        await t.press('ctrl+r');
        await t.type('alpha');
        final entries = f.connection.app.value.transcript.entries;
        expect(t.screen, isNot(shows('Reasoning detail')));
        await t.press('ctrl+o');
        expect(t.screen, shows('Reasoning detail 界😀'));
        expect(t.screen, shows('Full tool detail'));
        expect(f.connection.app.value.transcript.entries, same(entries));
        expect(f.connection.app.value.search?.query, 'alpha');
        expect(saved.text, 'saved');
        expect(saved.lastLayout, same(savedLayout));
        expect(t.screen.buffer.cursor, isNull);
        await t.press('ctrl+o');
        expect(t.screen, isNot(shows('Reasoning detail')));
        expect(f.connection.app.value.search?.query, 'alpha');
      },
    );

    testWidgets(
      'search match/modal reflow settles within normal two-pass operations $size',
      (t) async {
        final f = await connected(t, size);
        await send(t, 'alpha ${'word ' * 60}');
        await t.type('saved');
        final saved = editor(t), savedLayout = editor(t).lastLayout;
        for (final key in ['ctrl+r', 'a', 'l', 'p', 'h', 'a']) {
          final before = t.inputLayoutPasses;
          t.host.handleKey(KeyCombo.parse(key).toEvent());
          expect(t.inputLayoutPasses - before, lessThanOrEqualTo(2));
          final paintBefore = t.inputLayoutPasses;
          await t.pump();
          expect(t.inputLayoutPasses - paintBefore, lessThanOrEqualTo(2));
        }
        expect(saved.lastLayout, same(savedLayout));
        f.agent.askPermission();
        await until(() => f.agent.hasPermission);
        var before = t.inputLayoutPasses;
        await t.pump();
        expect(t.inputLayoutPasses - before, lessThanOrEqualTo(2));
        expect(f.connection.app.value.search, isNull);
        expect(editor(t), same(saved));
        for (final next in [const Size(32, 10), Size.zero, size]) {
          before = t.inputLayoutPasses;
          await t.resize(next);
          expect(t.inputLayoutPasses - before, lessThanOrEqualTo(2));
          expect(saved.text, 'saved');
        }
        final shown = editor(t).lastLayout;
        for (var i = 0; i < 3; i++) {
          before = t.inputLayoutPasses;
          await t.pump();
          expect(t.inputLayoutPasses - before, lessThanOrEqualTo(2));
          expect(editor(t).lastLayout, same(shown));
        }
      },
    );

    testWidgets('search shown and query exclude semantic selection $size', (
      t,
    ) async {
      final f = await connected(t, size);
      await send(t, 'alpha saved');
      await t.type('hidden draft');
      final saved = editor(t);
      await t.press('ctrl+r');
      await t.type('alpha');
      SelectionController? selection;
      void visit(Element e) {
        if (e.widget case SelectionArea(:final controller)) {
          selection = controller;
        }
        e.visitChildren(visit);
      }

      visit(t.host.rootElement);
      final row = t.screen.lines.indexWhere(
        (line) => line.contains('│ › alpha saved'),
      );
      expect(row, greaterThanOrEqualTo(0));
      for (final y in [row, row - 3]) {
        for (final (kind, x) in [
          (MouseEventKind.press, 4),
          (MouseEventKind.move, 12),
          (MouseEventKind.release, 12),
        ]) {
          await t.mouse(
            MouseEvent(
              kind,
              position: Offset(x, y),
              button: MouseButton.primary,
            ),
          );
        }
        expect(selection!.snapshot()?.hasText ?? false, isFalse);
      }
      expect(saved.text, 'hidden draft');
      expect(f.connection.app.value.draft, 'hidden draft');
    });
    testWidgets(
      'bash and slash matches recall without same-key completion/send $size',
      (t) async {
        final f = await connected(t, size);
        await send(t, '!echo alpha');
        await until(() => f.connection.app.value.held.isNotEmpty);
        await t.type('/review');
        await t.press('enter');
        await t.press('ctrl+r');
        await t.type('echo');
        expect(editor(t).text, 'echo alpha');
        await t.press('tab');
        expect(f.connection.app.value.bash, isTrue);
        expect(editor(t).text, 'echo alpha');
        await t.press('ctrl+c');
        await t.press('backspace');
        await t.press('ctrl+r');
        await t.type('/review');
        await t.press('tab');
        expect(f.connection.app.value.bash, isFalse);
        expect(editor(t).text, '/review');
        expect(
          f.agent.requests.where((r) => r['method'] == '_session/steering'),
          isEmpty,
        );
      },
    );

    testWidgets(
      'permission cancels query while verbose preserves it before arrival $size',
      (t) async {
        final f = await connected(t, size);
        await send(t, 'alpha');
        await t.type('saved');
        final saved = editor(t), savedLayout = editor(t).lastLayout;
        await t.press('ctrl+r');
        await t.type('alpha');
        await t.press('ctrl+o');
        expect(f.connection.app.value.expanded, isTrue);
        expect(f.connection.app.value.search?.query, 'alpha');
        expect(saved.text, 'saved');
        expect(saved.lastLayout, same(savedLayout));
        f.agent.askPermission();
        await until(() => f.agent.hasPermission);
        await t.pump();
        expect(f.connection.app.value.search, isNull);
        expect(editor(t), same(saved));
        expect(t.screen, shows('Esc to reject'));
        await t.resize(const Size(32, 10));
        expect(saved.text, 'saved');
        await t.resize(size);
        final restoredLayout = saved.lastLayout;
        await t.pump();
        await t.pump();
        expect(saved.lastLayout, same(restoredLayout));
        await t.press('esc');
        await until(() => !f.agent.hasPermission);
        await t.pump();
        expect(f.connection.app.value.search, isNull);
        expect(saved.text, 'saved');
        expect(
          f.connection.app.value.transcript.entries
              .whereType<model.UserEntry>(),
          hasLength(1),
        );
      },
    );
  }
}

void _testerSearchOwnershipBoundaries() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    for (final accept in ['enter', 'tab']) {
      testWidgets(
        'tester: query $accept accepts at1x1 after zero-axis paste stays inert $size',
        (t) async {
          final f = await connected(t, size);
          await send(t, 'literal 界😀 é reference');
          await t.type('saved draft');
          await t.press('left');
          final saved = editor(t),
              savedText = editor(t).text,
              cursor = editor(t).cursor;
          await t.press('ctrl+r');
          await t.type('reference');
          for (final zero in const [Size(0, 24), Size(80, 0), Size.zero]) {
            await t.resize(zero);
            await t.paste('hidden\nignored');
            await t.press('enter tab backspace');
            expect(f.connection.app.value.search?.query, 'reference');
            expect((saved.text, saved.cursor), (savedText, cursor));
          }
          await t.resize(const Size(1, 1));
          await t.press(accept);
          expect(f.connection.app.value.search, isNull);
          expect(saved.text, 'literal 界😀 é reference');
          await t.resize(size);
          expect(editor(t), same(saved));
          expect(saved.text, 'literal 界😀 é reference');
          expect(
            f.agent.requests.where((r) => r['method'] == 'session/prompt'),
            hasLength(1),
          );
          expect(
            f.agent.requests.where((r) => r['method'] == '_session/steering'),
            isEmpty,
          );
        },
      );
    }

    testWidgets(
      'tester: permission arrival blocks query paste and accept before repaint $size',
      (t) async {
        final f = await connected(t, size);
        await send(t, 'alpha reference');
        await t.type('saved é😀');
        final saved = editor(t),
            text = editor(t).text,
            cursor = editor(t).cursor;
        await t.press('ctrl+r');
        await t.type('alpha');
        f.agent.askPermission();
        await until(() => f.agent.hasPermission);
        expect(f.connection.app.value.search, isNull);
        t.host.handlePaste('must not edit draft');
        t.host.handleKey(KeyCombo.parse('tab').toEvent());
        await t.pump();
        expect(editor(t), same(saved));
        expect((saved.text, saved.cursor), (text, cursor));
        expect(f.connection.app.value.search, isNull);
        expect(
          f.agent.requests.where((r) => r['method'] == 'session/prompt'),
          hasLength(1),
        );
        expect(
          f.agent.requests.where((r) => r['method'] == '_session/steering'),
          isEmpty,
        );
        await t.press('esc');
        await until(() => !f.agent.hasPermission);
        await t.pump();
        expect(f.connection.app.value.search, isNull);
        expect((saved.text, saved.cursor), (text, cursor));
      },
    );

    testWidgets(
      'tester: a thousand query updates preserve hidden controller and layout $size',
      (t) async {
        final f = await connected(t, size);
        await send(t, 'alpha 界😀 é reference');
        await t.type('saved draft');
        final saved = editor(t),
            text = editor(t).text,
            cursor = editor(t).cursor,
            layout = editor(t).lastLayout;
        await t.press('ctrl+r');
        await t.type('alpha');
        for (var i = 0; i < 1000; i++) {
          t.host.handleKey(KeyCombo.parse('x').toEvent());
        }
        await t.pump();
        expect(f.connection.app.value.search?.query, 'alpha${'x' * 1000}');
        expect(f.connection.app.value.search?.failed, isTrue);
        expect((saved.text, saved.cursor), (text, cursor));
        expect(saved.lastLayout, same(layout));
        expect(t.screen.buffer.cursor, isNull);
        await t.press('esc');
        expect(editor(t), same(saved));
        expect((saved.text, saved.cursor), (text, cursor));
        await t.press('ctrl+z');
        expect(saved.text, 'saved draf');
      },
    );
  }
}
