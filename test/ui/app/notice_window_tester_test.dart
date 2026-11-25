import 'package:chord/notices.dart';
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/ui/pickers/pickers.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/children.dart';
import 'search_window_test.dart' show editor;
import 'steering_window_test.dart' show connected, send;
import 'window_fake_test.dart' show until;

void _eligible(StartConnection c, [String id = 'notice-session']) =>
    c.notices.watched(
      id,
      'dimcode',
      AgentStateChanged(
        AgentState(
          configOptions: [
            {
              'id': 'permission',
              'name': 'Permission',
              'type': 'select',
              'currentValue': 'full-access',
              'options': [
                {'value': 'full-access', 'name': 'Full access'},
              ],
            },
          ],
        ),
      ),
    );

Future<void> _arrive(WidgetTester t, StartConnection c) async {
  _eligible(c);
  await until(() => c.app.value.notice != null);
  await t.pump();
  await t.pump();
}

void main() {
  group('tester CTUI-105: stacked notice request ownership', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'permission interruption restores stacked notice keys at $size',
        (t) async {
          final f = await connected(t, size);
          await send(t, 'running');
          await t.press('?');
          await _arrive(t, f.connection);
          expect(f.connection.app.value.shortcuts.help, isTrue);
          expect(t.screen.text, contains(dimcodeWords.title));
          f.agent.askPermission();
          await until(() => f.agent.hasPermission);
          await t.pump();
          expect(t.screen.text, isNot(contains(dimcodeWords.title)));
          await t.press('esc');
          expect(f.connection.app.value.shortcuts.help, isFalse);
          expect(f.agent.hasPermission, isTrue);
          await t.press('esc');
          await until(() => !f.agent.hasPermission);
          await t.pump();
          await t.pump();
          expect(t.screen.text, contains(dimcodeWords.title));
          expect(f.connection.app.value.shortcuts.help, isFalse);
          await t.press('?');
          await t.pump();
          await t.pump();
          expect(f.connection.app.value.shortcuts.help, isTrue);
          await t.press('2');
          await t.pump();
          await t.pump();
          expect(f.connection.app.value.notice, isNull);
          expect(f.connection.app.value.shortcuts.help, isTrue);
          expect(t.screen.text, contains('enter to send'));
        },
      );
    }
  });

  group('tester CTUI-101: notice arrival and window ownership', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      for (final searching in [false, true]) {
        testWidgets(
          'async arrival keeps editing state with search=$searching $size',
          (t) async {
            final f = await connected(t, size);
            await send(t, 'alpha reference');
            await t.type('saved 界😀é');
            await t.press('left');
            final saved = editor(t), text = saved.text, cursor = saved.cursor;
            if (searching) {
              await t.press('ctrl+r');
              await t.type('alpha');
            }
            final query = f.connection.app.value.search;
            await _arrive(t, f.connection);
            expect(t.screen.text, contains(dimcodeWords.title));
            await t.type('x');
            await t.press('down');
            await t.press('enter');
            expect(f.connection.app.value.notice, isNull);
            expect(f.connection.app.value.search, same(query));
            expect((saved.text, saved.cursor), (text, cursor));
            if (searching) await t.press('esc');
            expect(editor(t), same(saved));
            await t.type('z');
            expect(saved.text, contains('z'));
            expect(
              f.agent.requests.where((r) => r['method'] == 'session/prompt'),
              hasLength(1),
            );
          },
        );
      }

      testWidgets(
        'tall draft and agent list retain both choices across resize $size',
        (t) async {
          final f = childrenFixture(['--tall', '--tasks']);
          addTearDown(f.close);
          await t.pumpWidget(childrenPreview(f), size: size);
          await t.paste(List.generate(20, (i) => 'draft $i 界😀é').join('\n'));
          final draft = f.connection.app.value.draft;
          await _arrive(t, f.connection);
          expect(t.screen.text, contains("1. Got it, don't show this again"));
          expect(t.screen.text, contains('2. Show it again next time'));
          await t.resize(
            size.width == 80 ? const Size(120, 40) : const Size(80, 24),
          );
          await t.pump();
          expect(t.screen.text, contains("1. Got it, don't show this again"));
          expect(t.screen.text, contains('2. Show it again next time'));
          await t.press('j');
          await t.press('enter');
          expect(f.connection.app.value.notice, isNull);
          expect(f.connection.app.value.draft, draft);
        },
      );

      testWidgets(
        'permission hides notice and restores its keys after rejection $size',
        (t) async {
          final f = await connected(t, size);
          await send(t, 'running');
          await _arrive(t, f.connection);
          f.agent.askPermission();
          await until(() => f.agent.hasPermission);
          await t.pump();
          expect(t.screen.text, isNot(contains(dimcodeWords.title)));
          expect(f.connection.app.value.notice, dimcodeNotice);
          await t.press('esc');
          await until(() => !f.agent.hasPermission);
          await t.pump();
          await t.pump();
          expect(t.screen.text, contains(dimcodeWords.title));
          await t.press('2');
          expect(f.connection.app.value.notice, isNull);
        },
      );
    }

    testWidgets(
      'notice stacks over help and closing it restores help and draft',
      (t) async {
        final f = await connected(t, const Size(80, 24));
        await t.press('?');
        expect(f.connection.app.value.shortcuts.help, isTrue);
        await _arrive(t, f.connection);
        expect(t.screen.text, contains(dimcodeWords.title));
        expect(f.connection.app.value.shortcuts.help, isTrue);
        await t.resize(const Size(120, 40));
        await t.pump();
        expect(t.screen.text, contains('enter to send'));
        expect(t.screen.text, contains(dimcodeWords.title));
        await t.press('esc');
        await t.pump();
        await t.pump();
        expect(f.connection.app.value.notice, isNull);
        expect(f.connection.app.value.shortcuts.help, isTrue);
        expect(t.screen.text, contains('enter to send'));
        expect(f.connection.app.value.draft, '');
      },
    );

    testWidgets('all notice navigation aliases choose the highlighted answer', (
      t,
    ) async {
      for (final (keys, expected) in [
        ('down up enter', true),
        ('j k enter', true),
        ('down enter', false),
        ('1', true),
        ('2', false),
      ]) {
        bool? answer;
        await t.pumpWidget(
          NoticeBox(
            room: 19,
            onAnswer: (value) => answer = value,
            onClose: () {},
          ),
        );
        await t.pump();
        await t.press(keys);
        expect(answer, expected, reason: keys);
      }
    });

    testWidgets('late arrival after unmount does not retain an overlay', (
      t,
    ) async {
      final f = await connected(t, const Size(80, 24));
      _eligible(f.connection);
      await t.pumpWidget(Text('replacement'));
      await until(() => f.connection.app.value.notice != null);
      await t.pump();
      expect(t.screen.text, 'replacement');
      expect(
        t.focusManager.activeBindings.where(
          (b) => b.description.contains('dimcode'),
        ),
        isEmpty,
      );
    });

    testWidgets('zero and one cell constraints do not prevent teardown', (
      t,
    ) async {
      for (final size in [Size.zero, const Size(1, 1), const Size(80, 1)]) {
        await t.pumpWidget(
          NoticeBox(room: 0, onAnswer: (_) {}, onClose: () {}),
          size: size,
        );
        await t.pump();
      }
      await t.pumpWidget(Text('done'));
      expect(t.screen.text, 'done');
    });
  });
}
