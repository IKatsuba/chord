// The original's tests/notices_test.ts (CHD-434), ported.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord/notices.dart';
import 'package:chord/session/config.dart' show AgentOption;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

AgentOption permission(String current, {String id = 'permission'}) => (
  id: id,
  name: 'Permission',
  current: current,
  values: [
    for (final value in ['read-only', 'workspace-write', 'full-access'])
      (value: value, name: value),
  ],
);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('chord-notices-'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('the words and choices are the original\'s', () {
    expect(dimcodeNotice, 'dimcode-agents');
    expect(dimcodeWords.title, 'dimcode can start other agents');
    expect(dimcodeWords.paragraphs, [
      'With its permission option at full-access, dimcode may start other '
          'agent CLIs it finds on your PATH, such as claude, codex and cursor, '
          'as subagents of its own, with their approvals bypassed and on your '
          'own accounts. At workspace-write it asks you first, and once you '
          "allow it, the same holds. Nothing those agents do reaches chord's "
          'permission box.',
      'To turn a CLI off, set externalAgents.<type>.enabled to false in '
          '~/.dimcode/v2/config.json (claude-code, codex, cursor, …), or use '
          "/external-agents in dimcode's own TUI. Or keep the permission "
          'option at read-only in /config, where dimcode refuses its agent '
          'tool.',
    ]);
    expect(noticeChoices, [
      (
        key: 'dismiss',
        label: "Got it, don't show this again",
        value: 'dismiss',
      ),
      (key: 'later', label: 'Show it again next time', value: 'later'),
    ]);
  });

  test("dimcode's notice is due once its permission is at anything but "
      'read-only, from dimcode alone', () {
    expect(dimcodeAtRisk('dimcode', [permission('full-access')]), isTrue);
    expect(dimcodeAtRisk('dimcode', [permission('workspace-write')]), isTrue);
    expect(dimcodeAtRisk('dimcode', [permission('read-only')]), isFalse);
    expect(dimcodeAtRisk('dimcode', []), isFalse);
    expect(dimcodeAtRisk('codex', [permission('full-access')]), isFalse);
  });

  test('each session comes due on its own way out of read-only, whatever '
      'another is at, and anew after going back', () {
    final watch = NoticeWatch();
    int? at(String id, String value, [String agent = 'dimcode']) =>
        watch.heard(id, agent, [permission(value)]);

    expect(at('a', 'read-only'), isNull);
    final first = at('a', 'full-access');
    expect(first, isA<int>());
    // Still there, and from one value at risk to another: not again.
    expect(at('a', 'full-access'), isNull);
    expect(at('a', 'workspace-write'), isNull);
    expect(watch.holds('a', first!), isTrue);

    // Another session, while the first is at risk, is due of its own.
    final other = at('b', 'full-access');
    expect(other, isA<int>());
    expect(other, isNot(first));
    expect(at('a', 'read-only'), isNull);
    expect(watch.holds('a', first), isFalse);
    expect(watch.holds('b', other!), isTrue);
    expect(at('a', 'full-access'), isA<int>());
    expect(at('c', 'full-access', 'codex'), isNull);
  });

  test(
    'a read that finishes after its session closed, was cleared, or came due '
    'again holds for none but the latest',
    () {
      final watch = NoticeWatch();
      final full = [permission('full-access')];
      final held = watch.heard('main:1', 'dimcode', full)!;

      // Cleared: the session after it, under the same id, at full-access too.
      watch.gone('main:1');
      expect(watch.holds('main:1', held), isFalse);
      final next = watch.heard('main:1', 'dimcode', full)!;
      expect(next, isNot(held));
      // The read begun before the clear still finds nothing to show for.
      expect(watch.holds('main:1', held), isFalse);
      expect(watch.holds('main:1', next), isTrue);
      watch.gone('main:1');
      expect(watch.holds('main:1', next), isFalse);
    },
  );

  test('its dismissal is recorded beside the user settings file, others kept, '
      'and read back', () async {
    final file = noticesFile(dir.path)!;

    expect(file, p.join(dir.path, 'chord', 'notices.json'));
    expect(noticesFile(null), isNull);
    expect(await dismissedNotices(file), isEmpty);

    await dismissNotice(file, 'another');
    await dismissNotice(file, dimcodeNotice);
    await dismissNotice(file, dimcodeNotice);

    expect([...await dismissedNotices(file)], ['another', dimcodeNotice]);
    expect(jsonDecode(File(file).readAsStringSync()), {
      'dismissed': ['another', dimcodeNotice],
    });
    expect(
      File(file).readAsStringSync(),
      '{\n  "dismissed": [\n    "another",\n    "$dimcodeNotice"\n  ]\n}\n',
    );

    // A record that does not read shows the notice again, never throws.
    File(file).writeAsStringSync('{ not json');
    expect(await dismissedNotices(file), isEmpty);
    File(file).writeAsStringSync(jsonEncode({'dismissed': 'all'}));
    expect(await dismissedNotices(file), isEmpty);
    expect(await dismissedNotices(null), isEmpty);
  });

  group('machine records and independent eligibility', () {
    test('a late ticket cannot cross session ids or survive lost eligibility, '
        'even after repeated id reuse', () {
      final watch = NoticeWatch();
      final tickets = <int>[];
      final other = watch.heard('other', 'dimcode', [
        permission('workspace-write'),
      ])!;

      for (var cycle = 0; cycle < 30; cycle++) {
        final ticket = watch.heard('reused', 'dimcode', [
          permission('full-access'),
        ])!;
        expect(tickets, isNot(contains(ticket)));
        expect(watch.holds('other', ticket), isFalse);
        tickets.add(ticket);
        expect(
          watch.heard('reused', 'dimcode', [permission('workspace-write')]),
          isNull,
        );
        expect(watch.holds('reused', ticket), isTrue);

        switch (cycle % 3) {
          case 0:
            watch.gone('reused');
          case 1:
            watch.heard('reused', 'dimcode', []);
          default:
            watch.heard('reused', 'fake', [permission('full-access')]);
        }
        for (final stale in tickets) {
          expect(watch.holds('reused', stale), isFalse);
        }
        expect(watch.holds('other', other), isTrue);
      }
    });

    test('future permission values remain eligible, while a similarly named '
        'option or runtime does not', () {
      expect(dimcodeAtRisk('dimcode', [permission('future-access')]), isTrue);
      expect(
        dimcodeAtRisk('dimcode', [
          permission('full-access', id: 'permissionMode'),
        ]),
        isFalse,
      );
      expect(dimcodeAtRisk('Dimcode', [permission('full-access')]), isFalse);

      final watch = NoticeWatch();
      final ticket = watch.heard('a', 'dimcode', [
        permission('future-access'),
      ])!;
      watch.heard('a', 'dimcode', [permission('read-only')]);
      expect(watch.holds('a', ticket), isFalse);
    });

    test('empty and structurally corrupt records fail open; a failed write '
        'leaves no temporary record', () async {
      final file = p.join(dir.path, 'notices.json');

      for (final text in [
        '',
        'null',
        '[]',
        '{"dismissed":[1]}',
        '{"dismissed":null}',
      ]) {
        File(file).writeAsStringSync(text);
        expect(await dismissedNotices(file), isEmpty, reason: text);
      }

      File(file).deleteSync();
      Directory(file).createSync();
      await expectLater(dismissedNotices(file), throwsA(anything));
      await expectLater(dismissNotice(file, dimcodeNotice), throwsA(anything));
      expect(
        [for (final entry in dir.listSync()) p.basename(entry.path)],
        ['notices.json'],
      );
    });

    test('dismissal is shared within one user directory, not another machine '
        'directory or the project', () async {
      final first = noticesFile(p.join(dir.path, 'one'))!;
      final second = noticesFile(p.join(dir.path, 'two'))!;

      await dismissNotice(first, 'unrelated');
      await dismissNotice(first, dimcodeNotice);
      expect((await dismissedNotices(first)).contains(dimcodeNotice), isTrue);
      expect((await dismissedNotices(second)).contains(dimcodeNotice), isFalse);
      expect([...await dismissedNotices(first)], ['unrelated', dimcodeNotice]);
      expect(
        [for (final entry in dir.listSync()) p.basename(entry.path)],
        ['one'],
      );
    });
  });

  group("the window's gate between the record's reads and its write", () {
    bool always() => true;

    test(
      'a read begun before 1 that finds the record empty shows nothing',
      () async {
        final read = Completer<Set<String>>();
        final gate = NoticeGate(() => read.future, (_) async {});
        final due = gate.due(dimcodeNotice, always);

        await gate.dismiss(dimcodeNotice);
        read.complete({});
        expect(await due, isFalse);
      },
    );

    test('while 1 is still being written, another session coming due shows '
        'nothing', () async {
      final write = Completer<void>();
      final gate = NoticeGate(() async => {}, (_) => write.future);
      final dismissed = gate.dismiss(dimcodeNotice);

      // The rename has not landed: the record still reads empty.
      expect(await gate.due(dimcodeNotice, always), isFalse);
      write.complete();
      await dismissed;
      expect(await gate.due(dimcodeNotice, always), isFalse);
    });

    test(
      'a write that fails gives it back, to show the next time it comes due, '
      'and no read begun before shows it',
      () async {
        final write = Completer<void>();
        final read = Completer<Set<String>>();
        var reads = 0;
        final gate = NoticeGate(
          () => reads++ == 0 ? read.future : Future.value(<String>{}),
          (_) => write.future,
        );
        final before = gate.due(dimcodeNotice, always);
        final dismissed = gate.dismiss(dimcodeNotice);

        write.completeError(const FileSystemException('read-only'));
        await dismissed;
        read.complete({});
        expect(await before, isFalse);
        expect(await gate.due(dimcodeNotice, always), isTrue);
      },
    );

    test('a session come due while the write is pending is spent, though the '
        'write then fails; the next one shows it', () async {
      final write = Completer<void>();
      final read = Completer<Set<String>>();
      var reads = 0;
      final gate = NoticeGate(
        () => reads++ == 0 ? read.future : Future.value(<String>{}),
        (_) => write.future,
      );
      final dismissed = gate.dismiss(dimcodeNotice);
      final during = gate.due(dimcodeNotice, always);

      write.completeError(const FileSystemException('read-only'));
      await dismissed;
      read.complete({});
      expect(await during, isFalse);
      expect(await gate.due(dimcodeNotice, always), isTrue);
    });

    test(
      'a record that does not read shows it; one that names it, or a session '
      'no longer at risk, does not',
      () async {
        final failing = NoticeGate(
          () => Future.error(const FileSystemException('EISDIR')),
          (_) async {},
        );
        expect(await failing.due(dimcodeNotice, always), isTrue);
        expect(await failing.due(dimcodeNotice, () => false), isFalse);

        final recorded = NoticeGate(() async => {dimcodeNotice}, (_) async {});
        expect(await recorded.due(dimcodeNotice, always), isFalse);
      },
    );
  });

  group('eligibility at the end of a record read', () {
    test('a held read for a cleared session cannot open for its replacement or '
        'another live session', () async {
      final watch = NoticeWatch();
      final reads = <Completer<Set<String>>>[];
      final gate = NoticeGate(() {
        final read = Completer<Set<String>>();
        reads.add(read);
        return read.future;
      }, (_) async {});
      final first = watch.heard('reused', 'dimcode', [
        permission('full-access'),
      ])!;
      final old = gate.due(dimcodeNotice, () => watch.holds('reused', first));

      watch.gone('reused');
      final next = watch.heard('reused', 'dimcode', [
        permission('workspace-write'),
      ])!;
      final other = watch.heard('other', 'dimcode', [
        permission('full-access'),
      ])!;
      final fresh = gate.due(dimcodeNotice, () => watch.holds('reused', next));
      final parallel = gate.due(
        dimcodeNotice,
        () => watch.holds('other', other),
      );

      reads[2].complete({});
      reads[0].complete({});
      reads[1].complete({});
      expect(await old, isFalse);
      expect(await fresh, isTrue);
      expect(await parallel, isTrue);
    });

    test('an unreadable record still cannot resurrect a closed or read-only '
        'session', () async {
      for (final ends in ['closed', 'read-only']) {
        final watch = NoticeWatch();
        final read = Completer<Set<String>>();
        final gate = NoticeGate(() => read.future, (_) async {});
        final ticket = watch.heard('one', 'dimcode', [
          permission('full-access'),
        ])!;
        final due = gate.due(dimcodeNotice, () => watch.holds('one', ticket));

        if (ends == 'closed') {
          watch.gone('one');
        } else {
          watch.heard('one', 'dimcode', [permission('read-only')]);
        }
        read.completeError(StateError('record unreadable'));
        expect(await due, isFalse);
      }
    });
  });
}
