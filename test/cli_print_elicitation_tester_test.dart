@Tags(['fake_agent'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:chord/cli.dart';
import 'package:test/test.dart';

import '../tool/dev.dart' show shellWord;
import 'fixtures/fake_harness.dart';

void main() {
  group('tester print elicitation output isolation', skip: fakeAgentSkip, () {
    test('concurrent JSON form and link runs keep warnings off stdout', () async {
      final results = await Future.wait([
        for (final prompt in ['form', 'link'])
          (() async {
            final dir = Directory.systemTemp.createTempSync(
              'print-form-tester-',
            );
            final out = StringBuffer(), err = StringBuffer();
            try {
              final result = await runCli(
                [
                  'fake',
                  '--agent-command',
                  fakeAgentCommand(null, [
                    '--step-ms',
                    '0',
                  ]).map(shellWord).join(' '),
                  '-p',
                  prompt,
                  '--output-format',
                  'json',
                ],
                stdout: out,
                stderr: err,
                cwd: dir.path,
                home: '${dir.path}/home',
                environment: {'HOME': '${dir.path}/home'},
                stdinTTY: true,
                lookup: (command) async => '/bin/$command',
              );
              expect(result.code, 0);
              expect(out.toString().trimRight().split('\n'), hasLength(1));
              final json = jsonDecode(out.toString()) as Map<String, Object?>;
              expect(json['type'], 'result');
              expect(json['is_error'], false);
              expect(
                json['result'],
                'Elicitation answer: ${prompt == 'form' ? 'decline' : 'cancel'}',
              );
              expect(json['stop_reason'], 'end_turn');
              return err.toString();
            } finally {
              dir.deleteSync(recursive: true);
            }
          })(),
      ]);
      expect(results, [
        'chord: fake asked: Set up the deploy target — skipped (no one to answer under -p)\n',
        '',
      ]);
    });
  });
}
