// dimcode's one-time notice in the window: its box above the prompt in the
// pickers' frame, 1 dismissing it for good, 2 and Esc showing it again next
// time, a permission hiding it until answered (the original's
// ui/pickers/Pickers.tsx NoticeBox, ui/app/state.ts and keys.ts).
import 'dart:convert';
import 'dart:io';

import 'package:chord/cli.dart';
import 'package:chord/notices.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

const _launch = Launch(
  name: 'dimcode',
  agent: null,
  agentCommand: 'unused',
  version: '0.0.1',
  directory: '.',
);

Future<StartConnection> _window(
  WidgetTester t,
  Size size, {
  String? configHome,
}) async {
  final c = StartConnection(command: 'unused', cwd: '.', configHome: configHome)
    ..app.value = const AppState(
      start: StartState(phase: StartPhase.connected),
      transcript: model.Transcript(
        entries: [model.UserEntry('u', 'request text')],
      ),
    );
  addTearDown(c.close);
  await t.pumpWidget(
    TranscriptWindow(launch: _launch, connection: c),
    size: size,
  );
  return c;
}

Future<void> _open(WidgetTester t, StartConnection c) async {
  c.fold.dispatch(const FrontActed(NoticeOpenedAction(dimcodeNotice)));
  // The overlay is placed after layout; its focus, and the highlight,
  // the frame after.
  await t.pump();
  await t.pump();
}

const _hint =
    'Enter to pick · 1–2 · ↑↓ to move · Esc to show it again next time';

void main() {
  _rowsAsTheOriginal();

  test('one notice at a time, closed by its own action', () {
    const open = AppState(notice: 'a');
    expect(reduceWindow(open, const NoticeOpenedAction('b')).notice, 'a');
    expect(
      reduceWindow(const AppState(), const NoticeOpenedAction('b')).notice,
      'b',
    );
    expect(reduceWindow(open, const NoticeClosedAction()).notice, isNull);
  });

  test('it waits behind a picker, the background view, an ask, or closing', () {
    expect(const AppState(notice: 'a').noticeShown, isTrue);
    expect(const AppState(notice: 'a', closing: true).noticeShown, isFalse);
    expect(
      const AppState(notice: 'a', themePreview: 'auto').noticeShown,
      isFalse,
    );
    expect(const AppState(notice: 'a', mcpPanel: true).noticeShown, isFalse);
    expect(
      const AppState(
        notice: 'a',
        transcript: model.Transcript(
          turn: model.AwaitingPermission('t', 0, [model.PermissionWait('p')]),
        ),
      ).noticeShown,
      isFalse,
    );
    expect(
      const AppState(
        notice: 'a',
        transcript: model.Transcript(asking: [model.FormWait('f', 'Input')]),
      ).noticeShown,
      isFalse,
    );
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('the box shows title, paragraphs, choices and hint $size', (
      t,
    ) async {
      final c = await _window(t, size);
      await _open(t, c);

      final text = t.screen.text;
      expect(text, contains('dimcode can start other agents'));
      expect(text, contains('With its permission option at full-access,'));
      expect(text, contains('To turn a CLI off, set'));
      expect(text, contains("1. Got it, don't show this again"));
      expect(text, contains('2. Show it again next time'));
      expect(text, contains(_hint));
      // Wrapped at spaces: the config path stays whole on its line.
      expect(text, contains('~/.dimcode/v2/config.json'));
      // The box takes the window's width, in the pickers' rounded frame.
      final rows = text.split('\n');
      final top = rows.indexWhere((row) => row.startsWith('╭'));
      expect(rows[top], '╭${'─' * (size.width.toInt() - 2)}╮');
      expect(rows[top + 1], contains('dimcode can start other agents'));
    });

    testWidgets('2 closes it, to show again; Esc does the same $size', (
      t,
    ) async {
      final dir = Directory.systemTemp.createTempSync('chord-notice-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final c = await _window(t, size, configHome: dir.path);
      for (final key in ['2', 'esc']) {
        await _open(t, c);
        expect(t.screen.text, contains('dimcode can start other agents'));
        await t.press(key);
        await t.pump();
        expect(c.app.value.notice, isNull, reason: key);
        expect(
          t.screen.text,
          isNot(contains('dimcode can start other agents')),
        );
      }
      expect(File(noticesFile(dir.path)!).existsSync(), isFalse);
    });

    testWidgets('1 dismisses it for good on this machine $size', (t) async {
      final dir = Directory.systemTemp.createTempSync('chord-notice-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final c = await _window(t, size, configHome: dir.path);
      await _open(t, c);
      await t.press('1');
      await t.pump();
      for (
        var i = 0;
        i < 20 && !File(noticesFile(dir.path)!).existsSync();
        i++
      ) {
        await t.pump(const Duration(milliseconds: 10));
      }

      expect(c.app.value.notice, isNull);
      expect(jsonDecode(File(noticesFile(dir.path)!).readAsStringSync()), {
        'dismissed': [dimcodeNotice],
      });
    });

    testWidgets(
      'a permission asked hides it and takes Esc; it comes back $size',
      (t) async {
        final c = await _window(t, size);
        await _open(t, c);
        final app = c.app.value;
        c.app.value = AppState(
          start: app.start,
          notice: app.notice,
          transcript: const model.Transcript(
            turn: model.AwaitingPermission('t', 0, [model.PermissionWait('p')]),
          ),
        );
        await t.pump();
        expect(
          t.screen.text,
          isNot(contains('dimcode can start other agents')),
        );
        expect(c.app.value.notice, dimcodeNotice);

        c.app.value = AppState(start: app.start, notice: c.app.value.notice);
        await t.pump();
        expect(t.screen.text, contains('dimcode can start other agents'));
      },
    );
  }

  testWidgets('short of room the body goes first, then the hint', (t) async {
    final c = await _window(t, const Size(80, 14));
    await _open(t, c);
    final text = t.screen.text;
    expect(text, contains('dimcode can start other agents'));
    expect(text, contains("1. Got it, don't show this again"));
    expect(text, contains('2. Show it again next time'));
    expect(text, isNot(contains('To turn a CLI off')));
  });

  testWidgets('its Esc is listed as leaving a picker', (t) async {
    final c = await _window(t, const Size(120, 40));
    await _open(t, c);
    expect(
      t.focusManager.activeBindings.where(
        (b) =>
            b.description ==
                "Close dimcode's notice, to show it again next time" &&
            b.id == 'select:cancel',
      ),
      hasLength(1),
    );
  });
}

/// The notice's box rows, as the original draws them at 80 columns.
List<String> _box(List<String> inner) => [
  '╭${'─' * 78}╮',
  for (final row in inner) '│ ${row.padRight(76)} │',
  '╰${'─' * 78}╯',
];

/// The rows of the first box on [screen], its frame included.
List<String> _drawn(String screen) {
  final rows = screen.split('\n');
  final top = rows.indexWhere((row) => row.startsWith('╭'));
  final bottom = rows.indexWhere((row) => row.startsWith('╰'), top);
  return rows.sublist(top, bottom + 1);
}

void _rowsAsTheOriginal() {
  const title = 'dimcode can start other agents';
  const choices = [
    "❯ 1. Got it, don't show this again",
    '  2. Show it again next time',
  ];
  const hint =
      'Enter to pick · 1–2 · ↑↓ to move · Esc to show it again next time';
  for (final (rows, inner) in [
    (
      24,
      [
        title,
        '',
        'With its permission option at full-access, dimcode may start other agent',
        'CLIs it finds on your PATH, such as claude, codex and cursor, as subagents',
        'of its own, with their approvals bypassed and on your own accounts. At',
        'workspace-write it asks you first, and once you allow it, the same holds.',
        "Nothing those agents do reaches chord's permission box.",
        '',
        'To turn a CLI off, set externalAgents.<type>.enabled to false in',
        '~/.dimcode/v2/config.json (claude-code, codex, cursor, …), or use',
        "/external-agents in dimcode's own TUI. Or keep the permission option at",
        'read-only in /config, where dimcode refuses its agent tool.',
        '',
        ...choices,
        '',
        hint,
      ],
    ),
    (14, [title, '', ...choices, '', hint]),
    (11, [title, '', ...choices]),
  ]) {
    testWidgets('its rows are the original\'s at 80x$rows', (t) async {
      final c = await _window(t, Size(80, rows));
      await _open(t, c);
      expect(_drawn(t.screen.text), _box(inner));
    });
  }
}
