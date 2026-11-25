// The window's watch over dimcode's notice (the original's
// ui/app/sessions.ts:275-322): each session apart, by its id, through the
// record's gate; a session cleared or closed comes due anew.
import 'dart:io';

import 'package:chord/notices.dart';
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/ui/app/sessions.dart';
import 'package:test/test.dart';

AgentState _at(String current) => AgentState(
  configOptions: [
    {
      'id': 'permission',
      'name': 'Permission',
      'type': 'select',
      'currentValue': current,
      'options': [
        for (final v in ['read-only', 'workspace-write', 'full-access'])
          {'value': v, 'name': v},
      ],
    },
  ],
);

void main() {
  late Directory dir;
  late List<String> opened;
  late WindowNotices notices;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('chord-window-notices-');
    opened = [];
    notices = WindowNotices(configHome: dir.path, opened: opened.add);
  });
  tearDown(() => dir.deleteSync(recursive: true));

  // The record is read from disk: a few real turns of the loop.
  Future<void> settle() async {
    for (var i = 0; i < 10; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test(
    'a session up at risk opens it; read-only, or another agent, not',
    () async {
      notices.watched('main:1', 'dimcode', Connected('s', _at('read-only')));
      notices.watched('child:2', 'codex', Connected('s', _at('full-access')));
      await settle();
      expect(opened, isEmpty);

      notices.watched(
        'main:1',
        'dimcode',
        AgentStateChanged(_at('full-access')),
      );
      await settle();
      expect(opened, [dimcodeNotice]);

      // Still at risk, from one value to another: not again.
      notices.watched(
        'main:1',
        'dimcode',
        AgentStateChanged(_at('workspace-write')),
      );
      await settle();
      expect(opened, [dimcodeNotice]);
    },
  );

  test('another session comes due of its own; a cleared one anew', () async {
    notices.watched('main:1', 'dimcode', Connected('s', _at('full-access')));
    notices.watched('task-a', 'dimcode', Connected('t', _at('full-access')));
    await settle();
    expect(opened, hasLength(2));

    notices.watched('main:1', 'dimcode', const Cleared());
    notices.watched('main:1', 'dimcode', Connected('s2', _at('full-access')));
    await settle();
    expect(opened, hasLength(3));
  });

  test('a session closed while the record is read shows none', () async {
    notices.watched('child:2', 'dimcode', Connected('s', _at('full-access')));
    notices.watched('child:2', 'dimcode', const Closing());
    await settle();
    expect(opened, isEmpty);
  });

  test('dismissed: recorded beside the settings, and shown no more', () async {
    notices.dismiss(dimcodeNotice);
    notices.watched('main:1', 'dimcode', Connected('s', _at('full-access')));
    await settle();
    expect(opened, isEmpty);
    expect(await dismissedNotices(noticesFile(dir.path)), {dimcodeNotice});

    // Another window on this machine reads the record.
    final next = <String>[];
    WindowNotices(
      configHome: dir.path,
      opened: next.add,
    ).watched('main:1', 'dimcode', Connected('s', _at('full-access')));
    await settle();
    await settle();
    expect(next, isEmpty);
  });

  test('without a config home it shows, and records nothing', () async {
    final shown = <String>[];
    final none = WindowNotices(opened: shown.add)..dismiss(dimcodeNotice);
    none.watched('main:1', 'dimcode', Connected('s', _at('full-access')));
    await settle();
    expect(shown, isEmpty);

    WindowNotices(
      opened: shown.add,
    ).watched('main:1', 'dimcode', Connected('s', _at('full-access')));
    await settle();
    expect(shown, [dimcodeNotice]);
  });
}
