// The CI workflow (CTUI-146, CTUI-190): its jobs, their needs and runners, the
// aggregate check's conditions, what each runs, and that every test file of
// both packages is in exactly one of its shards.
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:process_run/which.dart';
import 'package:test/test.dart';
import 'package:yaml/yaml.dart';

import '../../tool/shards.dart';
import '../fixtures/fake.dart' show portPackageDir;

/// The port's workflow, from the repository's root.
final workflowPath = p.normalize(p.absolute('.github', 'workflows', 'ci.yml'));

final actionlint = whichSync('actionlint');

void main() {
  final text = File(workflowPath).readAsStringSync();
  final workflow = loadYaml(text) as YamlMap;
  final jobs = workflow['jobs'] as YamlMap;
  List<YamlMap> steps(String job) =>
      ((jobs[job] as YamlMap)['steps'] as YamlList).cast<YamlMap>();
  List<String> runs(String job) => [
    for (final step in steps(job))
      if (step['run'] case final String run)
        [
          run.trim(),
          if (step['working-directory'] case final String dir) '@ $dir',
        ].join(' '),
  ];

  test('is the only workflow; chord.yml is gone', () {
    expect(
      Directory(
        p.dirname(workflowPath),
      ).listSync().map((e) => p.basename(e.path)),
      ['ci.yml'],
    );
  });

  test('reads the repository and nothing else', () {
    expect(workflow['permissions'], {'contents': 'read'});
    expect(text, isNot(contains('secrets.')));
    expect(text, isNot(contains('id-token')));
    expect(text, isNot(contains('github.event')));
  });

  test('runs on pushes to main and on pull requests only', () {
    expect(workflow['on'], {
      'push': {
        'branches': ['main'],
      },
      'pull_request': null,
    });
  });

  test('has its seven jobs, every one on ubuntu-latest', () {
    expect(jobs.keys, [
      'static',
      'tests',
      'compile',
      'node',
      'release',
      'cursor-cloud-acp',
      'check',
    ]);
    for (final job in jobs.keys) {
      expect((jobs[job] as YamlMap)['runs-on'], 'ubuntu-latest', reason: job);
    }
  });

  test('checks out without credentials and sets up the pinned SDK in every '
      'job that builds', () {
    for (final job in ['static', 'tests', 'compile', 'node', 'release']) {
      final checkout = steps(job).first;
      expect(checkout['uses'], 'actions/checkout@v5', reason: job);
      expect((checkout['with'] as YamlMap)['persist-credentials'], isFalse);
      final setup = steps(job)[1];
      expect(setup['uses'], 'dart-lang/setup-dart@v1', reason: job);
      expect((setup['with'] as YamlMap)['sdk'].toString(), '3.13.5');
    }
  });

  test('static analyzes both packages, checks the format and lints the '
      'workflow', () {
    expect(runs('static'), [
      'dart pub get @ packages/chord_tui',
      'dart pub get',
      'dart analyze',
      'dart analyze @ packages/chord_tui',
      'dart format --output=none --set-exit-if-changed .',
    ]);
    expect(steps('static').last['uses'], 'docker://rhysd/actionlint:1.7.7');
  });

  test("tests runs each package's shard of three through tool/shards.dart, "
      'under pipefail', () {
    final tests = jobs['tests'] as YamlMap;
    final strategy = tests['strategy'] as YamlMap;
    expect(strategy['fail-fast'], isFalse);
    expect((strategy['matrix'] as YamlMap)['shard'], [1, 2, 3]);
    expect(runs('tests'), [
      'dart pub get @ packages/chord_tui',
      'dart pub get',
      r'dart run tool/shards.dart --package=. --shard=${{ matrix.shard }}/3 '
          '| xargs dart test',
      'dart run tool/shards.dart --package=packages/chord_tui '
          r'--shard=${{ matrix.shard }}/3 | (cd packages/chord_tui && xargs '
          'dart test)',
    ]);
    for (final step in steps('tests').where((s) => s['run'] != null).skip(2)) {
      expect(step['shell'], 'bash', reason: 'bash runs it with pipefail');
    }
  });

  for (final (name, package) in [
    ('the app', '.'),
    ('the framework', 'packages/chord_tui'),
  ]) {
    test('$name: every test file is in exactly one of the three shards', () {
      final files = testFiles(p.join(portPackageDir(), package));
      expect(files, isNotEmpty);
      final sharded = [for (var k = 1; k <= 3; k++) ...shardOf(files, k, 3)];
      expect(sharded..sort(), files);
      for (var k = 1; k <= 3; k++) {
        expect(shardOf(files, k, 3), isNotEmpty, reason: 'shard $k');
      }
    });
  }

  test("compile installs expect and runs both packages' compile tags", () {
    expect(runs('compile'), [
      'sudo apt-get update && sudo apt-get install -y expect',
      'dart pub get @ packages/chord_tui',
      'dart pub get',
      'dart test -t compile --run-skipped',
      'dart test -t compile --run-skipped @ packages/chord_tui',
    ]);
  });

  test('node runs the npm shim test on Node 22.13', () {
    final node = steps(
      'node',
    ).firstWhere((step) => step['uses'] == 'actions/setup-node@v4');
    expect((node['with'] as YamlMap)['node-version'], '22.13');
    expect(runs('node'), [
      'dart pub get @ packages/chord_tui',
      'dart pub get',
      'dart test test/tool/npm_test.dart',
    ]);
  });

  test(
    "release checks the release's two Linux targets through tool/ci.dart",
    () {
      expect(runs('release'), [
        'dart pub get @ packages/chord_tui',
        'dart pub get',
        'dart run tool/ci.dart linux-x64',
        'dart run tool/ci.dart linux-arm64',
      ]);
    },
  );

  test('cursor-cloud-acp checks out without credentials, sets up Bun 1.4.4 '
      'and Node 22.13, and runs its quality and the tooling tests', () {
    final checkout = steps('cursor-cloud-acp').first;
    expect(checkout['uses'], 'actions/checkout@v5');
    expect((checkout['with'] as YamlMap)['persist-credentials'], isFalse);
    final bun = steps('cursor-cloud-acp')[1];
    expect(bun['uses'], 'oven-sh/setup-bun@v2');
    expect((bun['with'] as YamlMap)['bun-version'].toString(), '1.4.4');
    final node = steps('cursor-cloud-acp')[2];
    expect(node['uses'], 'actions/setup-node@v4');
    expect((node['with'] as YamlMap)['node-version'], '22.13');
    expect(runs('cursor-cloud-acp'), [
      'bun install --frozen-lockfile',
      'bun dev quality cursor-cloud-acp',
      'bun test ./tests/scripts ./lint',
    ]);
  });

  test('check needs every job, runs always, and passes only when each '
      'succeeded', () {
    const needed = [
      'static',
      'tests',
      'compile',
      'node',
      'release',
      'cursor-cloud-acp',
    ];
    final check = jobs['check'] as YamlMap;
    expect(check['needs'], needed);
    expect(check['if'], 'always()');
    expect(runs('check').single.split('\n'), [
      for (final job in needed) "test '\${{ needs.$job.result }}' = success",
    ]);
  });

  test('uses only checkout, setup-dart, setup-node, setup-bun and '
      'actionlint', () {
    expect(
      {
        for (final job in jobs.keys)
          for (final step in steps(job as String))
            if (step['uses'] case final String action) action,
      },
      {
        'actions/checkout@v5',
        'dart-lang/setup-dart@v1',
        'actions/setup-node@v4',
        'oven-sh/setup-bun@v2',
        'docker://rhysd/actionlint:1.7.7',
      },
    );
  });

  test('is clean under actionlint', () async {
    final ran = await Process.run(actionlint!, [workflowPath]);
    expect(ran.exitCode, 0, reason: '${ran.stdout}${ran.stderr}');
  }, skip: actionlint == null ? 'actionlint is not on PATH' : false);
}
