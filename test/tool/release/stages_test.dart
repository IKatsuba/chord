import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/release/build.dart';
import '../../../tool/release/cli.dart';
import '../../../tool/release/pack.dart';
import '../../../tool/release/runner.dart';
import '../../../tool/release/stages.dart';
import '../../../tool/targets.dart';
import 'fixtures/recording_runner.dart';

Matcher dies(String text) => throwsA(
  isA<ReleaseError>().having((e) => e.message, 'message', contains(text)),
);

Stage stage(String name) => chordStages.firstWhere((s) => s.name == name);

const hash = '0123456789ABCDEF0123456789ABCDEF01234567';

void main() {
  late Directory root;
  late List<String> said;
  setUp(() {
    root = Directory.systemTemp.createTempSync('stages_test');
    said = [];
  });
  tearDown(() => root.deleteSync(recursive: true));

  Release releaseWith(
    RecordingRunner runner, {
    String platform = 'darwin-arm64',
  }) => Release(
    root: root.path,
    runner: runner,
    out: said.add,
    err: said.add,
    sleep: (_) async {},
    tty: false,
    home: '/home/x',
    sdks: const Sdks(dart: 'dart', version: '3.13.5', cache: '/cache'),
    sdkDir: '/sdk',
    fake: () => "bun '/chord/fake.ts'",
    platform: platform,
  );

  test("chord's stages are the help's, publish run by the release itself", () {
    expect([
      for (final s in chordStages) s.name,
      publishStage,
    ], releaseStageNames);
    expect(
      [
        for (final s in chordStages)
          if (s.armMac) s.name,
      ],
      ['sign', 'notarise'],
    );
    expect(
      [
        for (final s in chordStages)
          if (s.versioned) s.name,
      ],
      ['compile'],
    );
  });

  test('what each stage leaves', () {
    expect(stage('compile').outputs!('1.2.3'), [
      for (final target in targets) binaryOf(target),
    ]);
    expect(stage('sign').outputs!('1.2.3'), darwinBinaries);
    expect(stage('notarise').outputs!('1.2.3'), darwinBinaries);
    expect(
      stage('pack').outputs!('1.2.3'),
      contains('build/release/tgz/SHA256SUMS'),
    );
    expect(stage('install').outputs, isNull);
  });

  group('the machine', () {
    test(
      'signing anywhere but an arm64 Mac is refused before anything else',
      () {
        expect(
          () => onMachine(['compile', 'sign'], 'linux-x64'),
          dies('sign and notarise run only on an arm64 Mac; this is linux-x64'),
        );
        expect(
          () => onMachine(['notarise'], 'darwin-x64'),
          dies('this is darwin-x64'),
        );
      },
    );

    test('a run without signing or notarisation runs anywhere', () {
      onMachine([
        'install',
        'quality',
        'compile',
        'selftest',
        'pack',
      ], 'linux-x64');
      onMachine(['sign', 'notarise'], 'darwin-arm64');
    });
  });

  test('install gets both lockfiles\' packages, loud', () async {
    final runner = RecordingRunner();
    await stage('install').run(releaseWith(runner), '1.2.3', (_) => {});
    expect(
      [
        for (final call in runner.calls)
          (call.argv.join(' '), call.cwd, call.loud),
      ],
      [
        ('dart pub get --enforce-lockfile', 'packages/chord_tui', true),
        ('dart pub get --enforce-lockfile', null, true),
      ],
    );
  });

  test('quality runs the static checks and both suites, and stops at the '
      'first that fails', () async {
    final runner = RecordingRunner();
    await stage('quality').run(releaseWith(runner), '1.2.3', (_) => {});
    expect(
      [for (final call in runner.calls) (call.argv.join(' '), call.cwd)],
      [
        ('dart analyze', null),
        ('dart format --output=none --set-exit-if-changed .', null),
        ('dart test', 'packages/chord_tui'),
        ('dart test', null),
      ],
    );
    final failing = RecordingRunner(
      (argv) => argv.contains('format') ? const Ran(1) : null,
    );
    await expectLater(
      stage('quality').run(releaseWith(failing), '1.2.3', (_) => {}),
      dies('dart format --output=none --set-exit-if-changed . failed'),
    );
    expect(failing.calls, hasLength(2));
  });

  test('the identity is found once, before the build, and signs', () async {
    final runner = RecordingRunner(
      (argv) => switch (argv) {
        ['security', ...] => const Ran(
          0,
          stdout: '  1) $hash "Developer ID Application: X (YQ8ZD2KZ3T)"\n',
        ),
        _ => null,
      },
    );
    final release = releaseWith(runner);
    await stage('sign').ready!(release);
    await stage('sign').ready!(release);
    expect(
      runner.argvs.where((argv) => argv.first == 'security'),
      hasLength(1),
    );
    expect(release.identity, hash);
  });

  test("Apple's credentials are checked before anything builds", () async {
    final runner = RecordingRunner();
    await stage('notarise').ready!(releaseWith(runner));
    expect(runner.argvs.single, [
      'xcrun',
      'notarytool',
      'history',
      '--keychain-profile',
      'roost-notary',
    ]);
    await expectLater(
      stage('notarise').ready!(
        releaseWith(
          RecordingRunner(
            (_) => const Ran(69, stderr: 'No Keychain password item found'),
          ),
        ),
      ),
      dies(
        'xcrun notarytool history --keychain-profile roost-notary failed: '
        'No Keychain password item found',
      ),
    );
  });

  test('a stage that did not leave its output stops the release', () {
    expect(
      () => outputSums(root.path, stage('notarise'), '1.2.3'),
      dies('notarise did not leave ${darwinBinaries.first}'),
    );
    for (final binary in darwinBinaries) {
      (File(
        p.join(root.path, binary),
      )..createSync(recursive: true)).writeAsStringSync(binary);
    }
    expect(
      outputSums(root.path, stage('notarise'), '1.2.3').keys,
      darwinBinaries,
    );
  });

  test('pack refuses what notarise did not record', () async {
    for (final target in targets) {
      (File(
        p.join(root.path, binaryOf(target)),
      )..createSync(recursive: true)).writeAsStringSync('$target');
    }
    final runner = RecordingRunner();
    await expectLater(
      stage('pack').run(releaseWith(runner), '1.2.3', (_) => {}),
      dies('has no notarisation recorded'),
    );
    expect(runner.calls, isEmpty);
  });

  test('the host is named as the release names machines', () {
    expect(hostPlatform(), matches(RegExp(r'^(darwin|linux)-(arm64|x64)$')));
  });

  test("the help's examples, the dry run without Apple skipping pack too", () {
    expect(
      releaseHelp(),
      contains('--bump patch --dry-run --skip notarise,pack'),
    );
    expect(releaseExamples, hasLength(7));
  });
}
