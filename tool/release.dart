/// chord's release, on the owner's arm64 Mac (docs/design/CTUI-102.md, U7):
/// the original's `bun dev release chord`, its RELEASE text, options and
/// stages in order. Teams never run it: every stage is checked through a
/// recording runner, and the original's own dry run is the owner's.
///
///     dart run tool/release.dart chord [options]
library;

import 'dart:io';

import 'package:path/path.dart' as p;

import '../test/fixtures/fake.dart';
import 'release/build.dart';
import 'release/cli.dart';
import 'release/run.dart';
import 'release/runner.dart';
import 'release/select.dart';
import 'release/stages.dart';

Future<void> main(List<String> args) async {
  final ReleaseCall call;
  try {
    call = parseRelease(args);
  } on UsageError catch (error) {
    stdout.writeln(releaseHelp());
    stderr.write('\n  error: ${error.message}\n\n');
    exitCode = 2;
    return;
  }
  switch (call) {
    case ReleaseHelp():
      stdout.writeln(releaseHelp());
    case ReleaseUnclear(:final line):
      stderr.writeln(line);
      exitCode = 1;
    case ReleaseRun(:final stages, :final options, :final bump):
      final root = p.normalize(
        p.join(p.dirname(Platform.script.toFilePath()), '..'),
      );
      final env = Platform.environment;
      final release = Release(
        root: root,
        runner: ProcessReleaseRunner(root: root, env: env),
        out: stdout.writeln,
        err: stderr.writeln,
        sleep: (duration) => Future<void>.delayed(duration),
        tty: stdin.hasTerminal && stdout.hasTerminal,
        home: env['HOME'] ?? '',
        sdks: Sdks.of(env),
        sdkDir: p.dirname(p.dirname(Platform.resolvedExecutable)),
        fake: () {
          if (fakeAgent.reason case final reason?) die(reason);
          return fakeAgentCommand().map((word) => "'$word'").join(' ');
        },
        platform: hostPlatform(),
        env: env,
      );
      try {
        await runRelease(release, stages, options, wanted: bump);
      } on ReleaseError catch (error) {
        stderr.writeln('release: ${error.message}');
        exitCode = 1;
      }
  }
}
