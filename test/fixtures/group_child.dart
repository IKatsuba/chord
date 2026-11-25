import 'dart:convert';
import 'dart:io';

import 'package:chord/platform/group_exec.dart';
import 'package:chord/platform/process.dart';

/// Starts a program through the launcher from whatever directory it runs
/// in, prints what it wrote, and exits with its exit code: `sh` printing
/// its pid and its group's id when given no arguments. Compiled, it is its
/// own launcher, as chord's binary is.
Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first == groupExecFlag) groupExec(args);
  final [program, ...rest] = args.isEmpty
      ? ['sh', '-c', r'echo "$$ $(ps -o pgid= -p $$)"']
      : args;
  final GroupProcess group;
  try {
    group = await spawnGroup(program, rest, cwd: Directory.systemTemp.path);
    await group.started;
  } on CannotStart catch (error) {
    stderr.writeln(error);
    await stderr.flush();
    exit(2);
  }
  stdout.write(await group.stdout.transform(utf8.decoder).join());
  final status = await group.exit;
  await stdout.flush();
  exit(status.code);
}
