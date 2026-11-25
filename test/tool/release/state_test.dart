import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/release/runner.dart';
import '../../../tool/release/state.dart';

const stages = ['install', 'quality', 'build', 'pack', 'publish'];
const abandonOne = 'rm -r .release/one abandons it';
const command = 'dart run tool/release.dart one';

/// A state of `one` 1.2.0 with [done] stages and its npm names as given.
ReleaseState state([
  List<String> done = const [],
  Map<String, String> npm = const {},
  Map<String, Object?> more = const {},
]) => {
  'format': 1,
  'package': 'one',
  'version': '1.2.0',
  'channel': null,
  'branch': 'main',
  'base': 'a' * 40,
  'built': 'b' * 40,
  'stages': {
    for (final stage in done)
      stage: {'at': '2026-11-12T00:00:00.000Z', 'outputs': <String, String>{}},
  },
  'npm': npm,
  ...more,
};

/// A selection of [selected], nothing else given.
Selection selection([
  List<String> selected = stages,
  ({
    bool? named,
    bool? dryRun,
    String? bump,
    String? channel,
    List<String>? npm,
    bool? githubRelease,
  })
  more = const (
    named: null,
    dryRun: null,
    bump: null,
    channel: null,
    npm: null,
    githubRelease: null,
  ),
]) => (
  stages: stages,
  selected: selected,
  named: more.named ?? false,
  dryRun: more.dryRun ?? false,
  bump: more.bump,
  channel: more.channel,
  npm: more.npm ?? ['@chorded/one'],
  githubRelease: more.githubRelease ?? false,
);

({
  bool? named,
  bool? dryRun,
  String? bump,
  String? channel,
  List<String>? npm,
  bool? githubRelease,
})
given({
  bool? named,
  bool? dryRun,
  String? bump,
  String? channel,
  List<String>? npm,
  bool? githubRelease,
}) => (
  named: named,
  dryRun: dryRun,
  bump: bump,
  channel: channel,
  npm: npm,
  githubRelease: githubRelease,
);

Left leftOf(ReleaseState at, Selection selection) =>
    left(at, selection, command: command);

String refused(void Function() run) {
  try {
    run();
  } on ReleaseError catch (error) {
    return error.message;
  }
  fail('not refused');
}

void main() {
  group('what is left', () {
    test('with no options: the stages not done, then what is left of '
        'publish', () {
      final it = leftOf(state(['install', 'quality']), selection());
      expect(it.cleared, isEmpty);
      expect(it.stages, ['build', 'pack']);
      expect(it.publish!.npm, ['@chorded/one']);
      expect((it.publish!.tag, it.publish!.draft), (true, false));
    });

    test('publish: the npm names not answered, the tag not pushed, the '
        'draft not made', () {
      final at = state(
        ['install', 'quality', 'build', 'pack'],
        {
          '@chorded/a': 'answered',
          '@chorded/b': 'sent',
          '@chorded/one': 'pending',
        },
        {
          'tag': {'state': 'made'},
          'draft': {'state': 'pending'},
        },
      );
      final all = given(
        githubRelease: true,
        npm: ['@chorded/a', '@chorded/b', '@chorded/c', '@chorded/one'],
      );
      final it = leftOf(at, selection(stages, all));
      expect(it.stages, isEmpty);
      expect(it.publish!.npm, ['@chorded/b', '@chorded/c', '@chorded/one']);
      expect((it.publish!.tag, it.publish!.draft), (true, true));
      final done = leftOf({
        ...at,
        'tag': {'state': 'pushed'},
        'draft': {'state': 'made'},
      }, selection(stages, all));
      expect((done.publish!.tag, done.publish!.draft), (false, false));
    });

    test('--skip: those stages are not run and stay not done', () {
      final it = leftOf(
        state(['install']),
        selection(['install', 'build', 'pack']),
      );
      expect(it.stages, ['build', 'pack']);
      expect(it.publish, isNull);
    });

    test('--to: stops after it, nothing of publish', () {
      final it = leftOf(state(['install']), selection(['install', 'quality']));
      expect(it.stages, ['quality']);
      expect(it.publish, isNull);
    });

    test('--only or --from: a done stage runs again, cleared with every done '
        'one after it', () {
      final at = state(['install', 'quality', 'build', 'pack']);
      final only = leftOf(at, selection(['quality'], given(named: true)));
      expect(only.cleared, ['quality', 'build', 'pack']);
      expect(only.stages, ['quality']);
      final from = leftOf(
        at,
        selection(['build', 'pack', 'publish'], given(named: true)),
      );
      expect(from.cleared, ['build', 'pack']);
      expect(from.stages, ['build', 'pack']);
      expect(from.publish, isNotNull);
    });

    test('an exact --bump equal to the state version is the same as none', () {
      final bumped = leftOf(
        state(['install']),
        selection(stages, given(bump: '1.2.0')),
      );
      final plain = leftOf(state(['install']), selection());
      expect(bumped.stages, plain.stages);
      expect(bumped.publish!.npm, plain.publish!.npm);
      expect(bumped.publish!.tag, plain.publish!.tag);
    });

    test("the state's own channel is allowed", () {
      final at = state([], {}, {'channel': 'next', 'version': '1.2.0-next.0'});
      expect(leftOf(at, selection(stages, given(channel: 'next'))).stages, [
        'install',
        'quality',
        'build',
        'pack',
      ]);
    });
  });

  group('refused, naming the way out', () {
    test('--dry-run', () {
      expect(
        refused(
          () => leftOf(
            state(['install']),
            selection(stages, given(dryRun: true)),
          ),
        ),
        '--dry-run is refused while one 1.2.0 is in progress (done: install; '
        'npm 0 of 1): `$command` continues it; $abandonOne',
      );
    });

    test('--bump another version or a bump word', () {
      for (final bump in ['1.3.0', 'patch']) {
        expect(
          refused(
            () => leftOf(
              state(['install']),
              selection(stages, given(bump: bump)),
            ),
          ),
          '--bump $bump is refused while one 1.2.0 is in progress (done: '
          'install; npm 0 of 1): `$command` continues it; $abandonOne',
        );
      }
    });

    test('another channel', () {
      expect(
        refused(
          () => leftOf(state(), selection(stages, given(channel: 'next'))),
        ),
        '--channel next is not one 1.2.0 is in progress (done: nothing; npm '
        "0 of 1)'s channel, none; $abandonOne",
      );
    });

    test('a stage before publish run again once npm has any of it', () {
      for (final sent in ['sent', 'answered']) {
        expect(
          refused(
            () => leftOf(
              state(
                ['install', 'quality', 'build', 'pack'],
                {'@chorded/a': sent, '@chorded/one': 'pending'},
              ),
              selection([
                'pack',
                'publish',
              ], given(named: true, npm: ['@chorded/a', '@chorded/one'])),
            ),
          ),
          startsWith("pack cannot run again: npm has one 1.2.0's bytes"),
        );
      }
    });

    test('publish without pack done', () {
      expect(
        refused(
          () => leftOf(
            state(['install', 'quality', 'build']),
            selection(['publish'], given(named: true)),
          ),
        ),
        "publish needs pack's output; pack is not done in one 1.2.0; "
        '$abandonOne',
      );
    });
  });

  test('a state is finished once npm answered for all, the tag is pushed '
      'and, with a GitHub release, the draft made', () {
    final at = state(
      [],
      {'@chorded/one': 'answered'},
      {
        'tag': {'state': 'pushed'},
      },
    );
    const npm = ['@chorded/one'];
    expect(finished(at, npm, false), isTrue);
    expect(finished(at, npm, true), isFalse);
    expect(
      finished(
        {
          ...at,
          'draft': {'state': 'made'},
        },
        npm,
        true,
      ),
      isTrue,
    );
    expect(
      finished(
        {
          ...at,
          'tag': {'state': 'made'},
        },
        npm,
        false,
      ),
      isFalse,
    );
    expect(
      finished(
        {
          ...at,
          'npm': {'@chorded/one': 'sent'},
        },
        npm,
        false,
      ),
      isFalse,
    );
    // A name the state never started is not done.
    expect(finished(at, ['@chorded/a', ...npm], false), isFalse);
  });

  test('cleared leaves the other done stages', () {
    expect(
      (cleared(state(['install', 'quality', 'build']), [
                'quality',
                'build',
              ])['stages']!
              as Map)
          .keys,
      ['install'],
    );
  });

  group('on disk', () {
    late Directory root;
    String file() => p.join(root.path, '.release', 'one', 'state.json');
    setUp(() => root = Directory.systemTemp.createTempSync('state_test'));
    tearDown(() => root.deleteSync(recursive: true));

    test('none until written; written, read back whole; cleared, none '
        'again', () {
      expect(readState(root.path, 'one'), isNull);
      final at = state(
        ['install'],
        {},
        {
          'versionCommit': {'state': 'made', 'sha': 'c' * 40},
        },
      );
      writeState(root.path, at);
      expect(readState(root.path, 'one'), at);
      clearState(root.path, 'one');
      expect(
        Directory(p.join(root.path, '.release', 'one')).existsSync(),
        isFalse,
      );
      expect(readState(root.path, 'one'), isNull);
    });

    test('a write stopped before the rename leaves the old state', () {
      writeState(root.path, state(['install']));
      expect(
        () => writeState(
          root.path,
          state(['install', 'quality']),
          rename: (_, _) => throw StateError('killed before the rename'),
        ),
        throwsA(isA<StateError>()),
      );
      expect((readState(root.path, 'one')!['stages']! as Map).keys, [
        'install',
      ]);
    });

    test('a leftover .tmp is never read, and the next write replaces it', () {
      writeState(root.path, state(['install']));
      File('${file()}.tmp').writeAsStringSync('{"half":');
      expect((readState(root.path, 'one')!['stages']! as Map).keys, [
        'install',
      ]);
      writeState(root.path, state(['install', 'quality']));
      expect(File('${file()}.tmp').existsSync(), isFalse);
      expect((readState(root.path, 'one')!['stages']! as Map).keys, [
        'install',
        'quality',
      ]);
    });

    test('a state that breaks the schema is never written', () {
      expect(
        () => writeState(root.path, {
          ...state(),
          'npm': {'@chorded/one': 'x'},
        }),
        throwsArgumentError,
      );
      expect(File(file()).existsSync(), isFalse);
    });

    for (final (what, text, why) in [
      (
        'another format, untouched',
        '{"format":2}',
        'has format 2; this release reads format 1',
      ),
      ('not JSON', '{', 'is not JSON: '),
      (
        'a missing field',
        jsonEncode({...state()}..remove('built')),
        "is not a release's state: built: ",
      ),
      (
        'a field of the wrong kind',
        jsonEncode({
          ...state(),
          'npm': {'@chorded/one': 'gone'},
        }),
        "is not a release's state: npm.@chorded",
      ),
      (
        "another package's",
        jsonEncode({...state(), 'package': 'chord'}),
        "is chord's state, not one's",
      ),
    ]) {
      test('a state that is $what is refused, naming the file', () {
        Directory(
          p.join(root.path, '.release', 'one'),
        ).createSync(recursive: true);
        File(file()).writeAsStringSync(text);
        final message = refused(() => readState(root.path, 'one'));
        expect(message, startsWith('${file()} $why'));
        expect(message, endsWith('; $abandonOne'));
        expect(File(file()).readAsStringSync(), text);
      });
    }
  });

  group('tester: persisted state boundaries', () {
    late Directory root;
    setUp(
      () => root = Directory.systemTemp.createTempSync('state_boundary_test'),
    );
    tearDown(() => root.deleteSync(recursive: true));

    test('an invalid replacement preserves the previous state bytes', () {
      writeState(root.path, state(['install']));
      final file = File(p.join(root.path, stateDir('one'), 'state.json'));
      final before = file.readAsBytesSync();
      expect(
        () => writeState(root.path, {...state(), 'built': null}),
        throwsArgumentError,
      );
      expect(file.readAsBytesSync(), before);
      expect(File('${file.path}.tmp').existsSync(), isFalse);
    });

    test('scalar and incomplete state files are refused without rewriting', () {
      final file = File(p.join(root.path, stateDir('one'), 'state.json'))
        ..createSync(recursive: true);
      for (final text in ['null', '[]', '"state"', '{"format":1}']) {
        file.writeAsStringSync(text);
        expect(
          refused(() => readState(root.path, 'one')),
          endsWith(abandonOne),
        );
        expect(file.readAsStringSync(), text);
      }
    });

    test('clearing one release leaves another release intact', () {
      writeState(root.path, state(['install']));
      final other = {
        ...state(['quality']),
        'package': 'two',
      };
      writeState(root.path, other);
      clearState(root.path, 'one');
      clearState(root.path, 'one');
      expect(readState(root.path, 'one'), isNull);
      expect(readState(root.path, 'two'), other);
    });
  });
}
