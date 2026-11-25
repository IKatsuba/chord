import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:path/path.dart' as p;

import 'acp/schema.dart' as acp;
import 'ignore.dart';

/// A fresh ignore-aware walk; cancellation also stops its filesystem worker.
Future<List<String>> listFiles(
  String cwd, {
  CancellationToken? cancellationToken,
}) => CancellableIsolate.run(() => _listFiles(cwd), cancellationToken);

List<String> _listFiles(String cwd) {
  final root = p.absolute(cwd);
  String resolve(String relative) => p.join(root, relative);
  final (files, _) = Ignore.listFiles(
    listDir: (dir) => [
      for (final entity in Directory(resolve(dir)).listSync(followLinks: false))
        if (p.basename(entity.path) != '.git' &&
            switch (FileSystemEntity.typeSync(entity.path, followLinks: true)) {
              FileSystemEntityType.file ||
              FileSystemEntityType.directory => true,
              _ => false,
            })
          p.posix.joinAll(p.split(p.relative(entity.path, from: root))),
    ],
    ignoreForDir: (dir) {
      final file = File(p.join(resolve(dir), '.gitignore'));
      return file.existsSync() ? Ignore(file.readAsLinesSync()) : null;
    },
    isDir: (dir) => Directory(resolve(dir)).existsSync(),
  );
  return files.toList()..sort((a, b) {
    final depth = p.posix.split(a).length.compareTo(p.posix.split(b).length);
    if (depth != 0) return depth;
    final lower = a.toLowerCase().compareTo(b.toLowerCase());
    return lower == 0 ? a.compareTo(b) : lower;
  });
}

/// Valid offered files, once each in typed order; failed discovery adds no links.
Future<List<acp.ContentBlock>> mentionLinks(
  List<String> paths,
  String cwd, {
  CancellationToken? cancellationToken,
}) async {
  if (paths.isEmpty) return const [];
  final Set<String> files;
  try {
    files = (await listFiles(
      cwd,
      cancellationToken: cancellationToken,
    )).toSet();
  } catch (_) {
    return const [];
  }
  if (cancellationToken?.isCancelled ?? false) return const [];
  return List.unmodifiable([
    for (final name in paths.toSet())
      if (files.contains(name))
        acp.ContentBlock.fromJson({
          'type': 'resource_link',
          'name': name,
          'uri': Uri.file(p.join(p.absolute(cwd), name)).toString(),
        }),
  ]);
}
