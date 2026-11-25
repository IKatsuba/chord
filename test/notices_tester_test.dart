import 'dart:async';
import 'dart:io';

import 'package:chord/notices.dart';
import 'package:chord/session/config.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

AgentOption _permission(String value) => (
  id: 'permission',
  name: 'Permission',
  current: value,
  values: [(value: value, name: value)],
);

void main() {
  group('tester CTUI-101: notice record and late eligibility', () {
    late Directory root;
    setUp(
      () => root = Directory.systemTemp.createTempSync('chord-notice-tester-'),
    );
    tearDown(() => root.deleteSync(recursive: true));

    test('a fresh gate observes dismissal from a prior gate', () async {
      final file = noticesFile(root.path)!;
      NoticeGate gate() => NoticeGate(
        () => dismissedNotices(file),
        (id) => dismissNotice(file, id),
      );
      final first = gate();
      expect(await first.due(dimcodeNotice, () => true), isTrue);
      expect(File(file).existsSync(), isFalse);
      await first.dismiss(dimcodeNotice);
      expect(await gate().due(dimcodeNotice, () => true), isFalse);
      expect(await gate().due('unrelated', () => true), isTrue);
    });

    test(
      'a malformed byte in a JSON string uses replacement decoding',
      () async {
        final file = File(p.join(root.path, 'notices.json'));
        file.writeAsBytesSync([
          ...'{"dismissed":["'.codeUnits,
          0xff,
          ...'"]}'.codeUnits,
        ]);
        expect(await dismissedNotices(file.path), {'�'});
        await dismissNotice(file.path, dimcodeNotice);
        expect(await dismissedNotices(file.path), {'�', dimcodeNotice});
        expect(root.listSync(), hasLength(1));
      },
    );

    test(
      'a thousand option updates do not duplicate or revive a stale ticket',
      () async {
        final watch = NoticeWatch();
        final read = Completer<Set<String>>();
        final gate = NoticeGate(() => read.future, (_) async {});
        final ticket = watch.heard('session', 'dimcode', [
          _permission('full-access'),
        ])!;
        final due = gate.due(
          dimcodeNotice,
          () => watch.holds('session', ticket),
        );
        for (var i = 0; i < 1000; i++) {
          expect(
            watch.heard('session', 'dimcode', [
              _permission(i.isEven ? 'workspace-write' : 'full-access'),
            ]),
            isNull,
          );
        }
        watch.heard('session', 'dimcode', [_permission('read-only')]);
        read.complete({});
        expect(await due, isFalse);
        expect(
          watch.heard('session', 'dimcode', [_permission('workspace-write')]),
          isNot(ticket),
        );
      },
    );

    test(
      'synchronous record failures fail open and dismissal can retry',
      () async {
        var writes = 0;
        final gate = NoticeGate(
          () => throw const FileSystemException('unreadable fixture'),
          (_) {
            writes++;
            if (writes == 1) {
              throw const FileSystemException('unwritable fixture');
            }
            return Future.value();
          },
        );
        expect(await gate.due(dimcodeNotice, () => true), isTrue);
        await gate.dismiss(dimcodeNotice);
        expect(await gate.due(dimcodeNotice, () => true), isTrue);
        await gate.dismiss(dimcodeNotice);
        expect(await gate.due(dimcodeNotice, () => true), isFalse);
        expect(writes, 2);
      },
    );
  });
}
