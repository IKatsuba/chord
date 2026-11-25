/// One shard of a package's tests, for CI to split a suite over runners:
///
///     dart run tool/shards.dart --package=<dir> --shard=<k>/<n>
///
/// prints the package's test files of shard k of n, one a line, relative to
/// the package, for `dart test` to take. The files are every `*_test.dart`
/// under the package's `test/`, sorted; shard k takes every n-th from the
/// k-th, so each file is in exactly one shard, whatever n.
library;

import 'dart:io';

import 'package:path/path.dart' as p;

/// Every `*_test.dart` under [packageDir]'s `test/`, relative to
/// [packageDir], in posix form, sorted.
List<String> testFiles(String packageDir) {
  final root = Directory(p.join(packageDir, 'test'));
  if (!root.existsSync()) return [];
  return [
    for (final entry in root.listSync(recursive: true, followLinks: false))
      if (entry is File && entry.path.endsWith('_test.dart'))
        p.posix.joinAll(p.split(p.relative(entry.path, from: packageDir))),
  ]..sort();
}

/// Shard [k] of [n] of [files]: every n-th file from the k-th, k counted
/// from 1.
List<String> shardOf(List<String> files, int k, int n) {
  if (n < 1 || k < 1 || k > n) {
    throw ArgumentError('a shard is k/n with 1 <= k <= n, not $k/$n');
  }
  return [
    for (final (index, file) in files.indexed)
      if (index % n == k - 1) file,
  ];
}

/// The `k/n` of `--shard=k/n`.
(int, int) parseShard(String text) {
  final match = RegExp(r'^(\d+)/(\d+)$').firstMatch(text);
  final k = match == null ? null : int.parse(match.group(1)!);
  final n = match == null ? null : int.parse(match.group(2)!);
  if (k == null || n == null || n < 1 || k < 1 || k > n) {
    throw FormatException('--shard takes k/n with 1 <= k <= n, not "$text"');
  }
  return (k, n);
}

const _usage =
    'Usage: dart run tool/shards.dart --package=<dir> --shard=<k>/<n>';

void main(List<String> args) {
  String? package;
  String? shard;
  for (final arg in args) {
    if (arg.startsWith('--package=')) {
      package = arg.substring('--package='.length);
    } else if (arg.startsWith('--shard=')) {
      shard = arg.substring('--shard='.length);
    } else {
      stderr.writeln('$_usage\n\nerror: unknown argument "$arg"');
      exit(2);
    }
  }
  if (package == null || shard == null) {
    stderr.writeln(_usage);
    exit(2);
  }
  final (int, int) wanted;
  try {
    wanted = parseShard(shard);
  } on FormatException catch (error) {
    stderr.writeln('$_usage\n\nerror: ${error.message}');
    exit(2);
  }
  if (!Directory(p.join(package, 'test')).existsSync()) {
    stderr.writeln('error: $package has no test directory');
    exit(2);
  }
  shardOf(testFiles(package), wanted.$1, wanted.$2).forEach(stdout.writeln);
}
