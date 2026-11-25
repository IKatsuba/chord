import 'dart:convert';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/files.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

Future<Directory> tree() async {
  final dir = await Directory.systemTemp.createTemp('chord-files-');
  addTearDown(() => dir.delete(recursive: true));
  return dir;
}

Future<void> put(Directory dir, String name, [String content = '']) async {
  final file = File(p.join(dir.path, name));
  await file.parent.create(recursive: true);
  await file.writeAsString(content);
}

void main() {
  test(
    'nonrepository walk uses nested rules, dotfiles and settled depth/name ordering',
    () async {
      final dir = await tree();
      for (final path in [
        '.git/HEAD',
        'dist/out.js',
        'src/ui/App.tsx',
        'src/ui/gen.ts',
        'src/main.ts',
        'debug.log',
        'README.md',
        '.hidden',
        'A',
        'aa',
        'Z',
        'za',
        'src/keep.log',
        'src/drop.log',
        'src/deeper/keep.log',
      ]) {
        await put(dir, path);
      }
      await put(dir, '.gitignore', 'dist/\n*.log\n');
      await put(dir, 'src/.gitignore', '!keep.log\n');
      await put(dir, 'src/ui/.gitignore', 'gen.ts\n');
      expect(await listFiles(dir.path), [
        '.gitignore',
        '.hidden',
        'A',
        'aa',
        'README.md',
        'Z',
        'za',
        'src/.gitignore',
        'src/keep.log',
        'src/main.ts',
        'src/deeper/keep.log',
        'src/ui/.gitignore',
        'src/ui/App.tsx',
      ]);
      await put(dir, 'new.txt');
      expect(await listFiles(dir.path), contains('new.txt'));
    },
  );
  test(
    'discovery follows existing file/directory links and excludes broken links and directories',
    () async {
      final dir = await tree(), outside = await tree();
      await put(dir, 'top.txt');
      await put(dir, 'sub/child.txt');
      await put(outside, 'external.txt');
      await Link(p.join(dir.path, 'alias-file')).create('top.txt');
      await Link(p.join(dir.path, 'alias-dir')).create('sub');
      await Link(p.join(dir.path, 'broken')).create('missing');
      await Link(
        p.join(dir.path, 'external-file'),
      ).create(p.join(outside.path, 'external.txt'));
      await Link(p.join(dir.path, 'external-dir')).create(outside.path);
      expect(await listFiles(dir.path), [
        'alias-file',
        'external-file',
        'top.txt',
        'alias-dir/child.txt',
        'external-dir/external.txt',
        'sub/child.txt',
      ]);
    },
  );
  test(
    'links rewalk current offered files, deduplicate typed order and encode literal names',
    () async {
      final dir = await tree();
      for (final path in [
        'a.ts',
        'space name.md',
        'dir/b#.txt',
        'gone',
        '.git/config',
        'out.log',
      ]) {
        await put(dir, path);
      }
      await put(dir, '.gitignore', '*.log\n');
      await File(p.join(dir.path, 'gone')).delete();
      final links = await mentionLinks([
        'dir/b#.txt',
        'a.ts',
        'space name.md',
        'a.ts',
        'dir',
        'gone',
        'out.log',
        '.git/config',
        '../outside',
        './a.ts',
      ], dir.path);
      expect(links.map((x) => x.toJson()['name']), [
        'dir/b#.txt',
        'a.ts',
        'space name.md',
      ]);
      expect(links.map((x) => x.type).toSet(), {'resource_link'});
      for (final link in links) {
        final data = link.toJson();
        expect(
          Uri.parse(data['uri'] as String).toFilePath(),
          p.join(dir.path, data['name'] as String),
        );
      }
      expect(links.first.toJson()['uri'], endsWith('dir/b%23.txt'));
      expect(links.last.toJson()['uri'], endsWith('space%20name.md'));
      expect(await mentionLinks([], p.join(dir.path, 'missing')), isEmpty);
      expect(
        await mentionLinks(['a.ts'], p.join(dir.path, 'missing')),
        isEmpty,
      );
    },
  );
  test(
    'pre-cancelled discovery does no work and cancelled attachments fail closed',
    () async {
      final dir = await tree();
      final token = CancellationToken()..cancel();
      await expectLater(
        listFiles(dir.path, cancellationToken: token),
        throwsA(isA<CancelledException>()),
      );
      expect(
        await mentionLinks(['a.ts'], dir.path, cancellationToken: token),
        isEmpty,
      );
    },
  );
  test('ported rule outcomes match git check-ignore when available', () async {
    ProcessResult version;
    try {
      version = await Process.run('git', ['--version']);
    } on ProcessException {
      markTestSkipped('git is unavailable');
      return;
    }
    if (version.exitCode != 0) {
      markTestSkipped('git is unavailable');
      return;
    }
    final dir = await tree();
    final names = [
      'normal.txt',
      'root-only',
      'deep/root-only',
      'debug.log',
      'sub/drop.log',
      'sub/keep.log',
      'sub/deeper/keep.log',
      'closed/keep.txt',
      'space name',
      '!literal',
      '#literal',
      'tmp/a',
      'sub/local.txt',
      'sub/deep/local.txt',
    ];
    for (final name in names) {
      await put(dir, name);
    }
    await put(
      dir,
      '.gitignore',
      '*.log\n/root-only\nclosed/\n!closed/keep.txt\nspace\\ name\n\\!literal\n\\#literal\ntmp/**\n',
    );
    await put(dir, 'sub/.gitignore', '!keep.log\n/local.txt\n');
    expect((await Process.run('git', ['init', '-q', dir.path])).exitCode, 0);
    final process = await Process.start('git', [
      '-C',
      dir.path,
      '-c',
      'core.excludesFile=/dev/null',
      'check-ignore',
      '--no-index',
      '-z',
      '--stdin',
    ]);
    final stdout = process.stdout.transform(utf8.decoder).join();
    final stderr = process.stderr.transform(utf8.decoder).join();
    process.stdin.write('${names.join('\x00')}\x00');
    await process.stdin.close();
    final code = await process.exitCode;
    expect(code, anyOf(0, 1), reason: await stderr);
    final ignored = (await stdout)
        .split('\x00')
        .where((x) => x.isNotEmpty)
        .toSet();
    final listed = (await listFiles(dir.path)).toSet();
    for (final name in names) {
      expect(listed.contains(name), !ignored.contains(name), reason: name);
    }
  });
}
