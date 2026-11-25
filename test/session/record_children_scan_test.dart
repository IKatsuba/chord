// A resumed session's children found by their records' first lines in an
// isolated state directory, and the parent's record prepared with its tasks'
// work spliced in. From the original's tests/session/record_test.ts, its
// CHD-557 cases.
import 'dart:convert';
import 'dart:io';

import 'package:chord/session/record.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/transcript/entries.dart' show replayTranscript;
import 'package:chord/session/transcript/subagents.dart' show subagentsIn;
import 'package:chord/session/transcript/types.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'record_children_test.dart' show header, parent, prompt, task;

String lines(List<Object?> entries) =>
    entries.map((entry) => '${jsonEncode(entry)}\n').join();

/// A records directory in a state directory of its own, as
/// `XDG_STATE_HOME` gives chord's, deleted after the test.
Future<String> records() async {
  final home = await Directory.systemTemp.createTemp('chord-children-');
  addTearDown(() => home.delete(recursive: true));
  final dir = recordsDir(p.join(home.path, 'state', 'chord'));
  await Directory(dir).create(recursive: true);
  return dir;
}

void main() {
  _testerChildRecordScans();
  group('childPasts', () {
    test("gives the records whose header's parent is the session, and no "
        "other session's", () async {
      final dir = await records();
      await File(p.join(dir, 'task.jsonl')).writeAsString(lines(task()));
      final child = [
        header('c-s', {'parent': 'main-1', 'name': 'parser', 'id': 'c1'}),
        prompt('t', 'Read.'),
      ];
      await File(p.join(dir, 'child.jsonl')).writeAsString(lines(child));
      await File(p.join(dir, 'other.jsonl')).writeAsString(
        lines([
          header('o-s', {'parent': 'main-2', 'task': 'task-2'}),
        ]),
      );
      await File(p.join(dir, 'parent.jsonl')).writeAsString(lines(parent()));
      await File(p.join(dir, 'notes.txt')).writeAsString(lines(task()));
      final found = await childPasts(dir, 'main-1');
      expect(found, hasLength(2));
      expect(found, containsAll([task(), child]));
      expect(taskPasts(found).keys, ['task-1']);
    });

    test('a child is read whole, a line cut short passed over; a header '
        'alone with no newline is a child', () async {
      final dir = await records();
      await File(
        p.join(dir, 'task.jsonl'),
      ).writeAsString('${lines(task())}{"type":"update","turnId":"t","upd');
      final only = header('o-s', {'parent': 'main-1', 'task': 'task-2'});
      await File(p.join(dir, 'only.jsonl')).writeAsString(jsonEncode(only));
      final found = await childPasts(dir, 'main-1');
      expect(
        found,
        containsAll([
          task(),
          [only],
        ]),
      );
      expect(found, hasLength(2));
    });

    test('a first line that is no header, is cut short or is blank names no '
        'child', () async {
      final dir = await records();
      final named = header('t-s', {'parent': 'main-1', 'task': 'task-1'});
      await File(
        p.join(dir, 'prompt.jsonl'),
      ).writeAsString(lines([prompt('t', 'x'), named]));
      final cut = jsonEncode(named);
      await File(
        p.join(dir, 'cut.jsonl'),
      ).writeAsString('${cut.substring(0, cut.length - 2)}\n${lines(task())}');
      await File(
        p.join(dir, 'blank.jsonl'),
      ).writeAsString('\n${lines([named])}');
      await File(p.join(dir, 'empty.jsonl')).writeAsString('');
      await Directory(p.join(dir, 'directory.jsonl')).create();
      expect(await childPasts(dir, 'main-1'), isEmpty);
    });

    test("a header longer than a read's chunk is read to its end", () async {
      final dir = await records();
      final long = [
        header('t-s', {
          'parent': 'main-1',
          'task': 'task-1',
          'name': '🙂é' * 20000,
        }),
        prompt('t', 'x'),
      ];
      await File(p.join(dir, 'long.jsonl')).writeAsString(lines(long));
      expect(taskPasts(await childPasts(dir, 'main-1')), {'task-1': long});
    });

    test('a records directory that is not there has no children', () async {
      final dir = await records();
      expect(await childPasts(p.join(dir, 'gone'), 'main-1'), isEmpty);
    });
  });

  group('readRecordedHistory', () {
    test("draws a parent's task block with the task's work from its own "
        'record beside it', () async {
      final dir = await records();
      final path = p.join(dir, 'parent.jsonl');
      await File(path).writeAsString(lines(parent()));
      await File(p.join(dir, 'task.jsonl')).writeAsString(lines(task()));
      final history = await readRecordedHistory(path);
      expect(history.omitted, isFalse);
      expect(
        [
          for (final action in history.actions.whereType<UpdateAction>())
            if (action.subagentId == 'task-1') action.turnId,
        ],
        ['history-t1'],
      );
      expect(
        history.actions.whereType<ServedAction>().single.subagentId,
        'task-1',
      );
      final block = subagentsIn(
        replayTranscript(history.actions).entries,
      ).singleWhere((each) => each.id == 'task-1');
      expect(block.task?.workLost, isFalse);
      expect(
        block.entries.whereType<AssistantEntry>().single.text.text,
        'Found it.',
      );
      // Nothing of the task's counts as the session's own.
      expect(
        history.recalled.where((update) => update.kind == 'subagent_update'),
        hasLength(2),
      );
      expect(
        history.recalled.where(
          (update) => update.kind == 'agent_message_chunk',
        ),
        hasLength(1),
      );
    });

    test("a task whose record is gone keeps the bare block, its work said "
        'lost', () async {
      final dir = await records();
      final path = p.join(dir, 'parent.jsonl');
      await File(path).writeAsString(lines(parent()));
      final history = await readRecordedHistory(path);
      final block = subagentsIn(
        replayTranscript(history.actions).entries,
      ).single;
      expect(block.task?.workLost, isTrue);
      expect(block.entries, isEmpty);
    });

    test("another parent's task of the same id is not spliced", () async {
      final dir = await records();
      final path = p.join(dir, 'parent.jsonl');
      await File(path).writeAsString(lines(parent()));
      final other = [...task()]
        ..[0] = header('task-s', {
          'parent': 'main-2',
          'name': 'reader',
          'task': 'task-1',
        });
      await File(p.join(dir, 'other.jsonl')).writeAsString(lines(other));
      final history = await readRecordedHistory(path);
      expect(
        history.actions.whereType<UpdateAction>().where(
          (action) => action.subagentId != null,
        ),
        isEmpty,
      );
    });
  });
}

void _testerChildRecordScans() {
  group('CTUI-35 tester: child record discovery boundaries', () {
    test('multibyte header spanning chunks at EOF stays whole', () async {
      final dir = await records();
      final entry = header('child', {
        'parent': 'root',
        'task': 'task-eof',
        'name': '界🙂e\u0301' * 20000,
      });
      await File(p.join(dir, 'child.jsonl')).writeAsString(jsonEncode(entry));
      expect(await childPasts(dir, 'root'), [
        [entry],
      ]);
    });

    test(
      'parallel scans keep seventy interleaved parents apart with cut tails',
      () async {
        final dir = await records();
        await Future.wait([
          for (var i = 0; i < 70; i++)
            File(p.join(dir, '$i.jsonl')).writeAsString(
              '${jsonEncode(header('session-$i', {'parent': i.isEven ? 'a' : 'b', 'task': 'task-$i'}))}\n{"type":',
            ),
        ]);
        final found = await Future.wait([
          childPasts(dir, 'a'),
          childPasts(dir, 'b'),
        ]);
        for (var side = 0; side < 2; side++) {
          expect(taskPasts(found[side]).keys.toSet(), {
            for (var i = side; i < 70; i += 2) 'task-$i',
          });
          expect(found[side].every((record) => record.length == 1), isTrue);
        }
      },
    );
  });
}
