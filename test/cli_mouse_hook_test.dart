import 'dart:convert';
import 'dart:io';

import 'package:chord/cli.dart';
import 'package:test/test.dart';

void main() {
  group('tester: mouse settings before startup picker', () {
    for (final user in [null, false, true]) {
      test(
        'user mouse=$user reaches hook before agent picker and ignores project',
        () async {
          final root = await Directory.systemTemp.createTemp('mouse-settings-');
          addTearDown(() => root.delete(recursive: true));
          final home = '${root.path}/home', cwd = '${root.path}/work';
          await Directory('$home/.config/chord').create(recursive: true);
          await Directory('$cwd/.chord').create(recursive: true);
          await File(
            '$home/.config/chord/settings.json',
          ).writeAsString(jsonEncode({'mouse': ?user}));
          await File(
            '$cwd/.chord/settings.json',
          ).writeAsString(jsonEncode({'mouse': user != true}));
          final order = <String>[];
          bool? seen;
          final result = await runCli(
            [],
            stdout: StringBuffer(),
            stderr: StringBuffer(),
            cwd: cwd,
            home: home,
            environment: {'HOME': home},
            stdinTTY: true,
            stdoutTTY: true,
            lookup: (_) async => null,
            onSettings: (settings) {
              order.add('settings');
              seen = settings.mouse;
            },
            pickAgent:
                ({
                  required agents,
                  required version,
                  required directory,
                  required preferred,
                  required offered,
                }) async {
                  order.add('picker');
                  expect(seen, user);
                  return null;
                },
          );
          expect(result.code, 0);
          expect(order, ['settings', 'picker']);
        },
      );
    }
  });
}
