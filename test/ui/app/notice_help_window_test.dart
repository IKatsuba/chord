// CTUI-105: the shortcuts help and dimcode's notice drawn together, as the
// original's Overlay lays them (App.tsx 1807, 1886; state.ts noticeShown):
// the help right above the prompt, the notice's frame on the help's top
// edge, no gap and no rule between them; the notice keeps its rows and its
// keys, the help takes what is left; '?' still toggles the help.
import 'package:chord/notices.dart';
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'steering_window_test.dart' show connected;
import 'window_fake_test.dart' show until;

Future<void> _arrive(WidgetTester t, StartConnection c) async {
  c.notices.watched(
    'notice-session',
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
  await until(() => c.app.value.notice != null);
  for (var i = 0; i < 4; i++) {
    await t.pump();
  }
}

const _choice = "1. Got it, don't show this again";

/// The row the prompt's top border is on.
int _prompt(WidgetTester t) {
  final lines = t.screen.lines;
  for (var y = lines.length - 1; y >= 0; y--) {
    if (lines[y].startsWith('╭') &&
        y + 1 < lines.length &&
        lines[y + 1].startsWith('│ ›')) {
      return y;
    }
  }
  throw StateError('no prompt:\n${t.screen.text}');
}

/// The row the notice's bottom border is on.
int _noticeBottom(WidgetTester t) {
  final lines = t.screen.lines;
  final title = lines.indexWhere((l) => l.contains(dimcodeWords.title));
  expect(title, greaterThan(0), reason: t.screen.text);
  return lines.indexWhere((l) => l.startsWith('╰'), title);
}

bool _helpShown(WidgetTester t) => t.screen.text.contains('enter to send');

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('help open, the notice arrives on top of it and keeps its '
        'rows; Enter answers it and help stays, at $size', (t) async {
      final f = await connected(t, size);
      await t.press('?');
      await t.pump();
      await _arrive(t, f.connection);
      final text = t.screen.text;
      expect(text, contains(dimcodeWords.title));
      expect(text, contains(_choice));
      expect(text, contains('2. Show it again next time'));
      final bottom = _noticeBottom(t);
      if (size.height == 40) {
        // The help right under the frame, no gap and no rule, and its last
        // row right above the prompt.
        expect(t.screen.lines[bottom + 1], contains('enter to send'));
        expect(t.screen.lines[bottom + 1], isNot(contains('──')));
        expect(t.screen.lines[_prompt(t) - 2].trim(), isNotEmpty);
      } else {
        // No room left for the help: the notice takes it all.
        expect(bottom + 2, _prompt(t));
        expect(_helpShown(t), isFalse);
      }
      await t.press('enter');
      await t.pump();
      await t.pump();
      expect(f.connection.app.value.notice, isNull);
      expect(f.connection.app.value.shortcuts.help, isTrue);
      expect(_helpShown(t), isTrue);
      expect(t.screen.text, contains('─────'));
    });

    testWidgets("'?' while the notice shows opens help under it, and "
        'closes it again, the notice back on the prompt, at $size', (t) async {
      final f = await connected(t, size);
      await _arrive(t, f.connection);
      final alone = _noticeBottom(t);
      expect(alone + 2, _prompt(t));
      await t.press('?');
      await t.pump();
      await t.pump();
      expect(f.connection.app.value.shortcuts.help, isTrue);
      expect(t.screen.text, contains(_choice));
      expect(_helpShown(t), size.height == 40);
      await t.press('?');
      await t.pump();
      await t.pump();
      expect(f.connection.app.value.shortcuts.help, isFalse);
      expect(_noticeBottom(t) + 2, _prompt(t));
      expect(f.connection.app.value.notice, isNotNull);
    });
  }

  testWidgets('stacked help still scrolls with its keys, the notice keeps '
      'its own, at 120x30, where the help left under it overflows', (t) async {
    final f = await connected(t, const Size(120, 30));
    await t.press('?');
    await t.pump();
    await _arrive(t, f.connection);
    expect(t.screen.text, contains('lines below'));
    await t.press('pagedown');
    await t.pump();
    expect(t.screen.text, contains('lines above'));
    await t.press('down');
    await t.press('enter');
    await t.pump();
    // ↓ moved the notice's choice: 2, shown again next time.
    expect(f.connection.app.value.notice, isNull);
    expect(f.connection.app.value.shortcuts.help, isTrue);
  });

  testWidgets('Esc closes the notice and leaves help in full, its rule back, '
      'at 80x24', (t) async {
    final f = await connected(t, const Size(80, 24));
    await _arrive(t, f.connection);
    await t.press('?');
    await t.pump();
    await t.press('esc');
    await t.pump();
    await t.pump();
    expect(f.connection.app.value.notice, isNull);
    expect(f.connection.app.value.shortcuts.help, isTrue);
    expect(_helpShown(t), isTrue);
    expect(t.screen.text, contains('lines below'));
  });
}
