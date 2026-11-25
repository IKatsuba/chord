import 'package:test/test.dart';

import '../../../tool/release/cli.dart';
import '../../../tool/release/select.dart';

const chordStages = [
  'install',
  'quality',
  'compile',
  'sign',
  'selftest',
  'notarise',
  'pack',
  'publish',
];

ReleaseRun released(List<String> argv) =>
    parseRelease(['chord', ...argv]) as ReleaseRun;

Matcher refuses([String? text]) => throwsA(
  text == null
      ? isA<UsageError>()
      : isA<UsageError>().having((e) => e.message, 'message', contains(text)),
);

void main() {
  test("chord's stages, as the original's but natives", () {
    expect(releaseStageNames, chordStages);
  });

  group('release', () {
    test('with no options runs every stage of the package', () {
      final run = released([]);
      expect(run.package, 'chord');
      expect(run.stages, chordStages);
      expect(run.options.dryRun, isFalse);
      expect(run.bump, isNull);
    });

    test('--dry-run runs every stage but publish', () {
      final run = released(['--dry-run']);
      expect(run.stages, chordStages.sublist(0, chordStages.length - 1));
      expect(run.options.dryRun, isTrue);
    });

    test('--skip takes a comma-separated list', () {
      final run = released(['--skip', 'install,quality']);
      expect(run.stages, chordStages.sublist(2));
      expect(run.options.skip, ['install', 'quality']);
    });

    test("--only, --from and --to over the package's own stages", () {
      expect(released(['--only', 'pack,sign']).stages, ['sign', 'pack']);
      expect(released(['--from', 'compile', '--to', 'sign']).stages, [
        'compile',
        'sign',
      ]);
    });

    test('--bump and --channel are passed on', () {
      final run = released(['--bump', 'major', '--channel', 'next']);
      expect(run.bump, 'major');
      expect(run.options.channel, 'next');
      expect(released(['--bump', '1.2.3']).bump, '1.2.3');
    });

    test("a stage the package does not have is refused, naming the stages", () {
      expect(
        () => released(['--only', 'natives']),
        refuses(
          'Option "--only" must be of type "stage", but got "natives". '
          'Expected values: "install", "quality", "compile", "sign", '
          '"selftest", "notarise", "pack", "publish"',
        ),
      );
    });

    for (final (name, argv) in [
      ('an unknown stage', ['--skip', 'tests']),
      ('an unknown stage in a list', ['--only', 'pack,tests']),
      ('the natives stage, which the port has not', ['--from', 'natives']),
      ('--package, which is gone', ['--package', 'chord']),
      ('--npm, which never was', ['--npm', '@chorded/chord']),
      ('--only with --skip', ['--only', 'publish', '--skip', 'quality']),
      ('--only with --from', ['--only', 'publish', '--from', 'pack']),
      ('--only with --to', ['--only', 'pack', '--to', 'pack']),
      ('--dry-run with --only publish', ['--dry-run', '--only', 'publish']),
      ('options that leave no stage', ['--from', 'pack', '--to', 'quality']),
      ('a second argument', ['now']),
      ('a version as an argument', ['1.0.0']),
      ('a bump written with a v', ['--bump', 'v1.0.0']),
      ('a bump that is no version', ['--bump', 'next']),
    ]) {
      test('refuses $name', () {
        expect(() => released(argv), refuses());
      });
    }

    test('an unknown package is refused, listing the packages', () {
      expect(() => parseRelease(['x']), refuses('Expected values: "chord"'));
    });

    test('a bump that is neither says what a bump is', () {
      expect(
        () => released(['--bump', 'v1']),
        refuses(
          '"v1" is neither an exact version (1.2.3) nor one of major, minor, '
          'patch, fix.',
        ),
      );
    });
  });

  group('a bare release', () {
    const line =
        'release: not clear which package to release: dart run '
        'tool/release.dart <package> (chord)';

    test('releases nothing and says so, whatever options it is given', () {
      for (final argv in [
        <String>[],
        ['--dry-run'],
        ['--bump', 'minor', '--channel', 'next'],
        ['--only', 'publish'],
        ['--skip', 'compile'],
      ]) {
        expect(
          (parseRelease(argv) as ReleaseUnclear).line,
          line,
          reason: '$argv',
        );
      }
    });

    test("checks that need the package's stages do not run without one", () {
      expect(
        parseRelease(['--dry-run', '--only', 'publish']),
        isA<ReleaseUnclear>(),
      );
    });

    test('refusals of the options still come first: conflicts, values, '
        'unknown flags', () {
      for (final argv in [
        ['--only', 'publish', '--skip', 'quality'],
        ['--skip', 'tests'],
        ['--bump', 'v1'],
        ['--nope'],
      ]) {
        expect(() => parseRelease(argv), refuses(), reason: '$argv');
      }
    });
  });

  group('the help', () {
    test('is asked for with -h or --help', () {
      expect(parseRelease(['-h']), isA<ReleaseHelp>());
      expect(parseRelease(['chord', '--help']), isA<ReleaseHelp>());
    });

    test("says the release's words, its stages and its options", () {
      final help = releaseHelp();
      expect(help, startsWith('Usage: $releaseCommand [package] [options]\n'));
      expect(help, contains("The release of chord; it runs on the owner's"));
      expect(help, contains('.release/chord/state.json'));
      expect(help, isNot(contains('package.json')));
      expect(
        help,
        contains(
          'Stages:\n'
          '  install   dart pub get --enforce-lockfile, root and port\n'
          '  quality   dart analyze, the format check and both suites\n',
        ),
      );
      for (final option in [
        '--bump',
        '--channel',
        '--dry-run',
        '--skip',
        '--only',
        '--from',
        '--to',
      ]) {
        expect(help, contains(option));
      }
    });
  });

  group('tester: release option boundaries', () {
    test('repeated multi-options keep one stage in release order', () {
      expect(released(['--only=pack,sign', '--only=pack']).stages, [
        'sign',
        'pack',
      ]);
      expect(
        released(['--skip=install', '--skip=quality,install']).stages,
        chordStages.sublist(2),
      );
    });

    test('the option terminator cannot turn extra words into a release', () {
      expect(
        () => parseRelease(['chord', '--', '--dry-run']),
        refuses('Too many arguments'),
      );
      expect(
        () => parseRelease(['--', '--dry-run']),
        refuses('Expected values: "chord"'),
      );
      expect(parseRelease(['--', 'chord']), isA<ReleaseRun>());
    });
  });
}
