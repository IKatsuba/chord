// Claude's usage read spoken from Dart, as the original's
// tests/platform/resource_worker_test.ts reads it through the SDK: the exact
// wire SDK 0.3.325 sends (argv, environment, two control requests) against
// a recording Dart fake; its failures in the original's words, and the output
// bound on every byte of stdout.
@TestOn('posix')
library;

import 'dart:convert';
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/platform/resource_process.dart';
import 'package:chord/platform/resource_worker.dart';
import 'package:chord/session/budgets.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

late Directory _dir;

/// An executable at [name] in the test's directory that runs [command].
String _wrapper(String name, List<String> command) {
  final file = File(p.join(_dir.path, name))
    ..writeAsStringSync(
      '#!/bin/sh\nexec ${command.map((word) => "'$word'").join(' ')} "\$@"\n',
    );
  Process.runSync('chmod', ['+x', file.path]);
  return file.path;
}

Map<String, Object?> _json(ProviderLimits limits) => limits.toJson();

void main() {
  group('CTUI-37 tester: reader environment ownership', () {
    test(
      'environment preparation keeps explicit session-state values and leaves input untouched',
      () {
        for (final key in [
          'CLAUDE_CODE_SDK_READS_SESSION_STATE',
          'claude_code_sdk_reads_session_state',
        ]) {
          final base = {
            'NODE_OPTIONS': '--inspect',
            'DEBUG': '1',
            key: '',
            'CLAUDE_CODE_ENTRYPOINT': 'fixture-entry',
            'UNRELATED': 'keep',
          };
          final original = Map<String, String>.of(base);
          final prepared = claudeUsageEnvironment(base);
          expect(base, original);
          expect(prepared[key], '');
          expect(
            prepared.keys.where(
              (name) =>
                  name.toUpperCase() == 'CLAUDE_CODE_SDK_READS_SESSION_STATE',
            ),
            [key],
          );
          expect(prepared['CLAUDE_CODE_ENTRYPOINT'], 'fixture-entry');
          expect(prepared['UNRELATED'], 'keep');
          expect(prepared.containsKey('NODE_OPTIONS'), isFalse);
          expect(prepared.containsKey('DEBUG'), isFalse);
        }
      },
    );
  });

  setUp(() {
    _dir = Directory.systemTemp.createTempSync('chord-claude-usage-');
    addTearDown(() => _dir.deleteSync(recursive: true));
  });

  group('the wire, against a recording fake', () {
    late String claude;
    late File record;
    setUp(() {
      claude = _wrapper('claude', [
        Platform.resolvedExecutable,
        p.join(
          Directory.current.path,
          'test',
          'fixtures',
          'claude_usage_fake.dart',
        ),
      ]);
      record = File(p.join(_dir.path, 'record.jsonl'));
    });

    Future<ProviderLimits> read(
      String mode, {
      Map<String, String> extra = const {},
    }) => collectClaudeResources(
      claude,
      cwd: _dir.path,
      cancelled: CancellationToken(),
      environment: {
        'PATH': Platform.environment['PATH'] ?? '/usr/bin:/bin',
        'HOME': _dir.path,
        'CHORD_FAKE_USAGE_RECORD': record.path,
        'CHORD_FAKE_USAGE_MODE': mode,
        'NODE_OPTIONS': '--inspect',
        'DEBUG': '1',
        ...extra,
      },
    );

    List<Map<String, Object?>> lines() => [
      for (final line in record.readAsLinesSync())
        jsonDecode(line) as Map<String, Object?>,
    ];

    test("SDK 0.3.325's argv and environment, then initialize and get_usage "
        'with skip_behaviors, and nothing else', () async {
      expect(_json(await read('normal')), {
        'agent': 'claude',
        'windows': [
          {
            'name': 'five_hour',
            'usedPercent': 1,
            'windowSeconds': 18000,
            'resetsAt': null,
            'models': null,
          },
        ],
      });
      final [head, initialize, usage] = lines();
      expect(head['argv'], [
        '--output-format',
        'stream-json',
        '--verbose',
        '--input-format',
        'stream-json',
        '--tools=',
        '--setting-sources=',
        '--strict-mcp-config',
        '--no-session-persistence',
        '--settings',
        '{"disableAllHooks":true}',
      ]);
      // NODE_OPTIONS and DEBUG removed; the entry point, the version and
      // the session-state read set, as the recording in
      // docs/design/evidence/CTUI-37/claude-usage-wire/ has them.
      expect(head['env'], {
        'CLAUDE_CODE_ENTRYPOINT': 'sdk-ts',
        'CLAUDE_AGENT_SDK_VERSION': '0.3.325',
        'CLAUDE_CODE_SDK_READS_SESSION_STATE': '1',
      });
      expect(initialize.keys, ['request_id', 'type', 'request']);
      expect(initialize['type'], 'control_request');
      expect(initialize['request'], {
        'subtype': 'initialize',
        'systemPrompt': [''],
      });
      expect(usage['request'], {
        'subtype': 'get_usage',
        'skip_behaviors': true,
      });
      expect(initialize['request_id'], matches(RegExp(r'^[0-9a-z]{13}$')));
      expect(usage['request_id'], isNot(initialize['request_id']));
    });

    test('an entry point already set is kept, an empty one is not', () async {
      await read('normal', extra: {'CLAUDE_CODE_ENTRYPOINT': 'cli'});
      expect((lines().first['env']! as Map)['CLAUDE_CODE_ENTRYPOINT'], 'cli');
      await read('normal', extra: {'CLAUDE_CODE_ENTRYPOINT': ''});
      expect(
        (lines().first['env']! as Map)['CLAUDE_CODE_ENTRYPOINT'],
        'sdk-ts',
      );
    });

    test(
      'the session-state read is left as it is when set in any case',
      () async {
        await read(
          'normal',
          extra: {'claude_code_sdk_reads_session_state': '0'},
        );
        final env = lines().first['env']! as Map;
        expect(env['claude_code_sdk_reads_session_state'], '0');
        expect(env.containsKey('CLAUDE_CODE_SDK_READS_SESSION_STATE'), isFalse);
      },
    );

    test('an error answer, a line that is not JSON, and an exit before the '
        'usage are the getter unavailable', () async {
      for (final mode in ['error', 'garbage', 'exit']) {
        expect(_json(await read(mode)), {
          'agent': 'claude',
          'unavailable':
              'The experimental usage getter is unavailable or unsupported.',
        }, reason: mode);
      }
    });

    test('past 256 KiB of stdout in all, in short lines or one long one, '
        'the read is refused', () async {
      for (final mode in ['flood', 'oversize']) {
        await expectLater(
          read(mode),
          throwsA(
            isA<ResourceReadError>()
                .having((e) => e.kind, 'kind', 'protocol')
                .having(
                  (e) => e.message,
                  'message',
                  'The isolated worker result exceeds its output bound.',
                ),
          ),
          reason: mode,
        );
      }
    });
  }, timeout: const Timeout(Duration(minutes: 1)));
}
