import 'package:test/test.dart';

import '../../../tool/release/select.dart';

const stages = [
  'install',
  'quality',
  'compile',
  'sign',
  'selftest',
  'notarise',
  'pack',
  'publish',
];

/// chord's stages the options leave.
List<String> select(ReleaseOptions options) =>
    selectStages((name: 'chord', stages: stages), options);

Matcher refuses([String? text]) => throwsA(
  text == null
      ? isA<UsageError>()
      : isA<UsageError>().having((e) => e.message, 'message', text),
);

void main() {
  group('the stages a run leaves', () {
    test('every stage, in order, with no options', () {
      expect(select(const ReleaseOptions()), stages);
    });

    test('a dry run leaves out publish alone', () {
      expect(
        select(const ReleaseOptions(dryRun: true)),
        stages.where((stage) => stage != 'publish'),
      );
    });

    test('--skip leaves out the stages named', () {
      expect(select(const ReleaseOptions(skip: ['quality', 'notarise'])), [
        'install',
        'compile',
        'sign',
        'selftest',
        'pack',
        'publish',
      ]);
    });

    test('--only keeps the release order, whatever order it is given in', () {
      expect(select(const ReleaseOptions(only: ['publish', 'pack'])), [
        'pack',
        'publish',
      ]);
    });

    test('--from and --to bound the run, both ends included', () {
      expect(select(const ReleaseOptions(from: 'sign')), [
        'sign',
        'selftest',
        'notarise',
        'pack',
        'publish',
      ]);
      expect(select(const ReleaseOptions(to: 'compile')), [
        'install',
        'quality',
        'compile',
      ]);
      expect(select(const ReleaseOptions(from: 'selftest', to: 'pack')), [
        'selftest',
        'notarise',
        'pack',
      ]);
    });

    test('--from and --to with --skip', () {
      expect(
        select(
          const ReleaseOptions(from: 'compile', to: 'pack', skip: ['notarise']),
        ),
        ['compile', 'sign', 'selftest', 'pack'],
      );
    });

    test('--dry-run with --skip, as the run without Apple', () {
      expect(select(const ReleaseOptions(dryRun: true, skip: ['notarise'])), [
        'install',
        'quality',
        'compile',
        'sign',
        'selftest',
        'pack',
      ]);
    });
  });

  group('refused', () {
    test("a stage the package does not have, naming the package's stages", () {
      const one = (name: 'one', stages: ['build', 'pack', 'publish']);
      for (final options in const [
        ReleaseOptions(skip: ['compile']),
        ReleaseOptions(only: ['pack', 'compile']),
        ReleaseOptions(from: 'compile'),
        ReleaseOptions(to: 'compile'),
      ]) {
        expect(
          () => selectStages(one, options),
          refuses(
            'one has no stage "compile"; its stages are build, pack, publish',
          ),
        );
      }
    });

    test("another package's stages, in its own order", () {
      const one = (name: 'one', stages: ['build', 'pack', 'publish']);
      expect(selectStages(one, const ReleaseOptions()), [
        'build',
        'pack',
        'publish',
      ]);
      expect(
        selectStages(one, const ReleaseOptions(dryRun: true, from: 'pack')),
        ['pack'],
      );
    });

    test('--dry-run with --only publish', () {
      expect(
        () => select(const ReleaseOptions(dryRun: true, only: ['publish'])),
        refuses(
          '--dry-run stops before publish, so --only publish has nothing to '
          'run.',
        ),
      );
    });

    test('options that leave no stage', () {
      expect(
        () => select(const ReleaseOptions(from: 'pack', to: 'install')),
        refuses('The options leave no stage to run.'),
      );
      expect(
        () =>
            select(const ReleaseOptions(only: ['quality'], skip: ['quality'])),
        refuses(),
      );
    });
  });

  test('--dry-run refuses publish anywhere in --only', () {
    expect(
      () =>
          select(const ReleaseOptions(dryRun: true, only: ['pack', 'publish'])),
      refuses(),
    );
  });

  group('tester: stage interval boundaries', () {
    test(
      'every inclusive interval is kept and every reversed interval refused',
      () {
        for (var first = 0; first < stages.length; first++) {
          for (var last = 0; last < stages.length; last++) {
            final options = ReleaseOptions(
              from: stages[first],
              to: stages[last],
            );
            if (first <= last) {
              expect(select(options), stages.sublist(first, last + 1));
            } else {
              expect(() => select(options), refuses());
            }
          }
        }
      },
    );

    test('duplicate choices never repeat a stage', () {
      expect(select(const ReleaseOptions(only: ['pack', 'sign', 'pack'])), [
        'sign',
        'pack',
      ]);
      expect(
        select(const ReleaseOptions(skip: ['publish', 'publish'])),
        stages.sublist(0, stages.length - 1),
      );
    });
  });
}
