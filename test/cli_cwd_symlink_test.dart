// CTUI-91: a directory given with -C through a symlink, as /tmp is on
// macOS, is the directory the window shows, as the original's Cliffy
// default and -C keep it; never the path the link resolves to.
import 'dart:io';

import 'package:chord/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test('-C through a symlink keeps the path as given', () async {
    final root = Directory.systemTemp
        .createTempSync('chord-cwd-link-')
        .resolveSymbolicLinksSync();
    addTearDown(() => Directory(root).deleteSync(recursive: true));
    final real = Directory(p.join(root, 'real'))..createSync();
    final link = p.join(root, 'link');
    Link(link).createSync(real.path);

    final outcome = await runCli(
      ['-C', link, 'codex'],
      stdout: StringBuffer(),
      stderr: StringBuffer(),
      cwd: root,
      home: p.join(root, 'home'),
      environment: {'XDG_CONFIG_HOME': p.join(root, 'config')},
      lookup: (command) async => '/bin/$command',
      readSessionRecords: () async => const [],
    );
    expect(outcome.code, 0);
    expect(outcome.launch!.cwd, link);
    expect(outcome.launch!.directory, link);
  });
}
