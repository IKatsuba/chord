import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/release/archive.dart';
import '../../../tool/release/pack.dart';
import '../../../tool/release/preflight.dart';
import '../../../tool/release/publish.dart';
import '../../../tool/release/runner.dart';
import '../../../tool/release/state.dart';
import '../../../tool/targets.dart';
import 'fixtures/recording_runner.dart';

Matcher dies(String text) => throwsA(
  isA<ReleaseError>().having((e) => e.message, 'message', contains(text)),
);

const built = 'b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0';
const url = 'https://github.com/IKatsuba/chord/releases/tag/untagged-1';

/// npm, git and GitHub as a publish sees them: what npm has, how many views
/// a name needs before it answers, the tags made and pushed.
final class World {
  World({Set<String>? onNpm, this.late = const {}}) : onNpm = onNpm ?? {};

  final Set<String> onNpm;

  /// Names npm answers for only after this many views once published.
  final Map<String, int> late;
  final views = <String, int>{};
  final tags = <String>[];
  final pushed = <String>[];
  Ran? Function(List<String> argv)? fail;

  late final RecordingRunner runner = RecordingRunner((argv) {
    if (fail?.call(argv) case final ran?) return ran;
    switch (argv) {
      case ['npm', 'view', final spec, 'version']:
        final seen = views[spec] = (views[spec] ?? 0) + 1;
        final name = spec.substring(0, spec.lastIndexOf('@'));
        if (onNpm.contains(spec) && seen > (late[name] ?? 0)) {
          return Ran(0, stdout: '${spec.split('@').last}\n');
        }
        return const Ran(1, stderr: 'npm error code E404\n');
      case ['npm', 'publish', '--access', 'public', final file, ...]:
        final base = p.basename(file);
        final name = npmNames.firstWhere(
          (n) => base.startsWith(
            '${n.replaceFirst('@', '').replaceFirst('/', '-')}-1',
          ),
        );
        onNpm.add('$name@1.2.3');
        views.remove('$name@1.2.3');
        return const Ran(0);
      case ['git', 'rev-parse', ...]:
        return const Ran(1);
      case ['git', 'ls-remote', ...]:
        return const Ran(0);
      case ['git', 'tag', '-a', final tag, ...]:
        tags.add(tag);
        return const Ran(0);
      case ['git', 'push', 'origin', final tag]:
        pushed.add(tag);
        return const Ran(0);
      case ['gh', 'release', 'create', ...]:
        return const Ran(0, stdout: '$url\n');
    }
    return null;
  });
}

void main() {
  late Directory root;
  late List<String> said;
  late List<String> errs;
  setUp(() {
    root = Directory.systemTemp.createTempSync('publish_test');
    final tgz = Directory(p.join(root.path, tgzFolder))
      ..createSync(recursive: true);
    for (final name in npmNames) {
      File(
        p.join(tgz.path, tarballName(name, '1.2.3')),
      ).writeAsStringSync(name);
    }
    recordSums(tgz.path, [for (final n in npmNames) tarballName(n, '1.2.3')]);
    final archives = Directory(p.join(root.path, archivesFolder))
      ..createSync(recursive: true);
    for (final target in targets) {
      File(p.join(archives.path, target.archive)).writeAsStringSync('$target');
    }
    recordSums(archives.path, [for (final t in targets) t.archive]);
    said = [];
    errs = [];
  });
  tearDown(() => root.deleteSync(recursive: true));

  Recorder recorder([Map<String, Object?> more = const {}]) =>
      Recorder(root.path, {
        'format': 1,
        'package': 'chord',
        'version': '1.2.3',
        'channel': null,
        'branch': 'main',
        'base': built,
        'built': built,
        'stages': <String, Object?>{},
        'npm': <String, Object?>{},
        ...more,
      });

  Future<void> run(World world, Recorder recorded, {bool tty = true}) =>
      publish(
        world.runner,
        root.path,
        version: '1.2.3',
        recorded: recorded,
        npmNames: npmNames,
        tty: tty,
        sleep: (_) async {},
        out: said.add,
        err: errs.add,
      );

  List<String> published(World world) => [
    for (final call in world.runner.calls)
      if (call.argv.take(2).join(' ') == 'npm publish')
        p.basename(call.argv[4]),
  ];

  test('publishes every platform package, then the main one last, and tags '
      'the built commit', () async {
    final world = World();
    await run(world, recorder());
    expect(published(world), [
      for (final name in npmNames) tarballName(name, '1.2.3'),
    ]);
    expect(
      world.runner.calls
          .where((c) => c.argv.take(2).join(' ') == 'npm publish')
          .every((c) => c.loud),
      isTrue,
    );
    expect(world.tags, ['v1.2.3']);
    expect(world.pushed, ['v1.2.3']);
    expect(
      world.runner.argvs
          .where((argv) => argv.first == 'git' && argv[1] == 'tag')
          .single,
      ['git', 'tag', '-a', 'v1.2.3', '-m', 'chord v1.2.3', built],
    );
  });

  test('records each npm name answered, the tag pushed and the draft made '
      'with its URL', () async {
    final recorded = recorder();
    await run(World(), recorded);
    expect(recorded.state['npm'], {
      for (final name in npmNames) name: 'answered',
    });
    expect(recorded.state['tag'], {'state': 'pushed'});
    expect(recorded.state['draft'], {'state': 'made', 'url': url});
    expect(readState(root.path, 'chord'), recorded.state);
  });

  test('drafts the tag with the archives and SHA256SUMS, never publishing '
      'it; a channel draft is a pre-release', () async {
    final world = World();
    await run(world, recorder());
    expect(world.runner.argvs.last, [
      'gh',
      'release',
      'create',
      'v1.2.3',
      '--draft',
      '--verify-tag',
      '--title',
      'chord v1.2.3',
      '--notes',
      '',
      for (final target in targets) 'build/release/archives/${target.archive}',
      'build/release/archives/SHA256SUMS',
    ]);
    expect(said.last, 'drafted v1.2.3, with its archives: $url');
    final channel = RecordingRunner((_) => const Ran(0, stdout: '$url\n'));
    await draftRelease(
      channel,
      '1.3.0-next.0',
      'v1.3.0-next.0',
      't',
      const [],
      out: said.add,
    );
    expect(channel.argvs.single, contains('--prerelease'));
  });

  test('npm publish arguments: no tag for a stable version, the channel\'s '
      'for a pre-release', () {
    expect(publishArguments('1.2.3', 'f.tgz'), [
      'publish',
      '--access',
      'public',
      'f.tgz',
    ]);
    expect(publishArguments('1.3.0-next.2', 'f.tgz'), [
      'publish',
      '--access',
      'public',
      'f.tgz',
      '--tag',
      'next',
    ]);
  });

  test('an npm name the state never started that npm has is refused, not '
      'skipped', () async {
    await expectLater(
      run(World(onNpm: {'${npmNames.first}@1.2.3'}), recorder()),
      dies(
        'npm has ${npmNames.first}@1.2.3, which this release did not '
        'publish; rm -r .release/chord abandons it',
      ),
    );
  });

  test('one a killed run left pending that npm has is answered, not '
      'published again', () async {
    final world = World(onNpm: {'${npmNames.first}@1.2.3'});
    await run(
      world,
      recorder({
        'npm': {npmNames.first: 'pending'},
      }),
    );
    expect(
      published(world),
      isNot(contains(tarballName(npmNames.first, '1.2.3'))),
    );
  });

  test(
    'the main package waits for a platform package npm answers for late',
    () async {
      final world = World(late: {npmNames.first: 3});
      await run(world, recorder());
      expect(errs, [
        for (var i = 1; i <= 3; i++)
          'release: waiting for ${npmNames.first}@1.2.3 to answer npm view '
              '($i/60)',
      ]);
      expect(published(world).last, tarballName(npmNames.last, '1.2.3'));
    },
  );

  test('a platform package npm never answers for stops the release before '
      'the main one', () async {
    final world = World(late: {npmNames.first: 1000});
    await expectLater(
      run(world, recorder()),
      dies(
        '${npmNames.first}@1.2.3 did not answer npm view in 15 minutes; '
        '@chorded/chord was not published. Rerun `dart run '
        'tool/release.dart chord` once',
      ),
    );
    expect(published(world), hasLength(4));
  });

  test('the main package npm never answers for is not tagged, and says how '
      'to tag it', () async {
    final world = World(late: {npmNames.last: 1000});
    await expectLater(
      run(world, recorder()),
      dies(
        'tag it with: git tag -a v1.2.3 -m "chord v1.2.3" $built && git push '
        'origin v1.2.3',
      ),
    );
    expect(world.tags, isEmpty);
  });

  test('says npm will ask, once', () async {
    await run(World(), recorder());
    expect(said.where((line) => line.startsWith('npm will ask')), hasLength(1));
  });

  test('stops without a terminal, and publishes nothing', () async {
    final world = World();
    await expectLater(
      run(world, recorder(), tty: false),
      dies('npm publish asks in the terminal to authorise each publish'),
    );
    expect(published(world), isEmpty);
  });

  test(
    'a tarball changed since it was packed is refused, with both sums',
    () async {
      File(
        p.join(root.path, tgzFolder, tarballName(npmNames.first, '1.2.3')),
      ).writeAsStringSync('changed');
      await expectLater(run(World(), recorder()), dies('has sha256'));
    },
  );

  test('a tarball that is not there is refused', () async {
    File(
      p.join(root.path, tgzFolder, tarballName(npmNames.first, '1.2.3')),
    ).deleteSync();
    await expectLater(
      run(World(), recorder()),
      dies('nothing of this run is left to resume from'),
    );
  });

  test('a changed archive stops before npm takes anything', () async {
    File(
      p.join(root.path, archivesFolder, targets.last.archive),
    ).writeAsStringSync('changed');
    final world = World();
    await expectLater(run(world, recorder()), dies('has sha256'));
    expect(published(world), isEmpty);
  });

  test('a missing archive stops before npm takes anything', () async {
    File(p.join(root.path, archivesFolder, targets.first.archive)).deleteSync();
    final world = World();
    await expectLater(run(world, recorder()), dies('for the draft'));
    expect(published(world), isEmpty);
  });

  test(
    'a draft that fails says the version is out, and how to finish',
    () async {
      final world = World()
        ..fail = (argv) =>
            argv.first == 'gh' ? const Ran(1, stderr: 'HTTP 422\n') : null;
      await expectLater(
        run(world, recorder()),
        dies(
          'v1.2.3 is on npm and tagged, but its draft release failed: HTTP '
          "422\nFinish it with: gh release create v1.2.3 --draft --verify-tag "
          "--title 'chord v1.2.3' --notes ''",
        ),
      );
    },
  );

  test('a tag push that fails keeps its diagnostic', () async {
    final world = World()
      ..fail = (argv) => argv.take(2).join(' ') == 'git push'
          ? const Ran(1, stderr: 'rejected\n')
          : null;
    await expectLater(
      run(world, recorder()),
      dies('git push origin v1.2.3 failed: rejected'),
    );
  });

  test('a resumed publish asks nothing of what is done', () async {
    final world = World(onNpm: {for (final n in npmNames) '$n@1.2.3'});
    await run(
      world,
      recorder({
        'npm': {for (final n in npmNames) n: 'answered'},
        'tag': {'state': 'pushed'},
        'draft': {'state': 'made', 'url': url},
      }),
    );
    expect(world.runner.calls, isEmpty);
  });

  group('tester: interrupted publish recovery', () {
    test(
      'an accepted publish interrupted before its return is not sent twice',
      () async {
        final world = World();
        final recorded = recorder();
        var interrupted = false;
        world.fail = (argv) {
          if (!interrupted && argv.take(2).join(' ') == 'npm publish') {
            interrupted = true;
            world.onNpm.add('${npmNames.first}@1.2.3');
            throw StateError('lost answer');
          }
          return null;
        };
        await expectLater(run(world, recorded), throwsStateError);
        expect((recorded.state['npm'] as Map)[npmNames.first], 'pending');
        world.fail = null;
        await run(world, recorded);
        expect(
          published(
            world,
          ).where((file) => file == tarballName(npmNames.first, '1.2.3')),
          hasLength(1),
        );
        expect(
          (recorded.state['npm'] as Map).values.every(
            (status) => status == 'answered',
          ),
          isTrue,
        );
      },
    );

    test(
      'a pending draft found already made is recorded without recreation',
      () async {
        final world = World();
        world.fail = (argv) => argv.take(3).join(' ') == 'gh release view'
            ? const Ran(0, stdout: '$url\n')
            : null;
        final recorded = recorder({
          'npm': {for (final name in npmNames) name: 'answered'},
          'tag': {'state': 'pushed'},
          'draft': {'state': 'pending'},
        });
        await run(world, recorded);
        expect(world.runner.argvs, [
          ['gh', 'release', 'view', 'v1.2.3', '--json', 'url', '--jq', '.url'],
        ]);
        expect(recorded.state['draft'], {'state': 'made', 'url': url});
      },
    );
  });
}
