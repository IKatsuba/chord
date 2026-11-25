import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/release/archive.dart';
import '../../../tool/release/build.dart';
import '../../../tool/release/runner.dart';
import '../../../tool/targets.dart';

void main() {
  group('tester CTUI-151: verified staged extended attributes', () {
    test(
      'known attributes on every staged member stay out of all archives',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'archive-xattrs-tester-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        for (final target in targets) {
          File(p.join(root.path, binaryOf(target)))
            ..createSync(recursive: true)
            ..writeAsStringSync('fixture binary ${target.name}\n');
        }
        File(
          p.join(root.path, 'LICENSE'),
        ).writeAsStringSync('fixture licence\n');
        final runner = _AttributedRunner(root.path);
        await archive(
          runner,
          root.path,
          notices: 'fixture notices\n',
          notarised: {'darwin-arm64', 'darwin-x64'},
        );
        expect(runner.attributed, targets.length * members.length);
        for (final target in targets) {
          final path = p.join(root.path, archivesFolder, target.archive);
          final raw = String.fromCharCodes(
            gzip.decode(File(path).readAsBytesSync()),
          );
          expect(raw, isNot(contains('com.example.ctui151')));
          expect(raw, isNot(contains('attribute-sentinel')));
          expect(raw, isNot(contains('SCHILY.xattr')));
          final listing = await Process.run('/usr/bin/tar', ['-tzf', path]);
          expect(listing.exitCode, 0, reason: '${listing.stderr}');
          expect((listing.stdout as String).trim().split('\n'), members);
          checkSum(path);
        }
      },
      skip: Platform.isMacOS && File('/usr/bin/xattr').existsSync()
          ? false
          : 'Verified extended-attribute proof requires macOS xattr.',
    );
  });
}

final class _AttributedRunner implements ReleaseRunner {
  _AttributedRunner(this.root);
  final String root;
  var attributed = 0;

  @override
  Future<Ran> run(
    String command,
    List<String> args, {
    bool loud = false,
    String? cwd,
    Map<String, String> env = const {},
  }) async {
    if (command == 'file') {
      final target = targets.singleWhere((t) => binaryOf(t) == args.single);
      return Ran(0, stdout: '${args.single}: ${kinds[target.name]}\n');
    }
    if (command == 'codesign') return const Ran(0);
    // The flavour question writes nothing, so it carries no stage to mark.
    if (command == 'tar' && args.contains('--version')) {
      // Falls through to the real tar below.
    } else if (command == 'tar') {
      final stage = p.join(root, args[args.indexOf('-C') + 1]);
      for (final member in members) {
        final path = p.join(stage, member);
        final set = await Process.run('/usr/bin/xattr', [
          '-w',
          'com.example.ctui151',
          'attribute-sentinel',
          path,
        ]);
        expect(set.exitCode, 0, reason: '${set.stderr}');
        final read = await Process.run('/usr/bin/xattr', [
          '-p',
          'com.example.ctui151',
          path,
        ]);
        expect(read.exitCode, 0, reason: '${read.stderr}');
        expect((read.stdout as String).trim(), 'attribute-sentinel');
        attributed++;
      }
    } else if (command != 'chmod') {
      throw StateError('unexpected archive command $command');
    }
    return ProcessReleaseRunner(
      root: root,
      env: Platform.environment,
    ).run(command, args, loud: loud, cwd: cwd, env: env);
  }

  @override
  Future<Started> start(
    String command,
    List<String> args, {
    String? cwd,
    Map<String, String> env = const {},
  }) => throw StateError('archive fixture must not start processes');
}
