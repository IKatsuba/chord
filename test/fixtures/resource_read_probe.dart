// Reads Claude's limits with the `claude` at its first argument, its wire
// recorded to the file at its second, and prints the answer as JSON.
// Compiled, it is its own group launcher, as chord's binary is, so the
// reader runs as it does from a built chord.
import 'dart:convert';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/platform/group_exec.dart';
import 'package:chord/platform/resource_worker.dart';

Future<void> main(List<String> args) async {
  if (args.isNotEmpty && args.first == groupExecFlag) groupExec(args);
  final [claude, record] = args;
  final limits = await collectClaudeResources(
    claude,
    cwd: Directory.systemTemp.path,
    cancelled: CancellationToken(),
    environment: {
      'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
      'HOME': Platform.environment['HOME'] ?? '/',
      'CHORD_FAKE_USAGE_RECORD': record,
      'CHORD_FAKE_USAGE_MODE': 'normal',
    },
  );
  stdout.write(jsonEncode(limits.toJson()));
  await stdout.flush();
  exit(0);
}
