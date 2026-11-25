@Tags(['fake_agent'])
library;

import 'dart:async';

import 'package:chord/acp/connection.dart' show windowCapabilities;
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'session_fake.dart';
import 'transcript/fold.dart';

List<Terminal> _terminals(List<acp.SessionUpdate> updates) => [
  for (final entry in fold([
    const PromptAction('turn', 'bash', 0),
    for (final update in updates) UpdateAction('turn', update),
  ]).entries)
    if (entry is ToolEntry) ...?entry.call.terminals,
];

void main() {
  group('tester terminal capability isolation', skip: fakeAgentSkip, () {
    test(
      'simultaneous clients keep terminal and fallback output separate',
      () async {
        final outputs = await Future.wait([
          for (final declared in [true, false])
            (() async {
              late List<acp.SessionUpdate> updates;
              await withSession(
                capabilities: declared ? windowCapabilities() : null,
                flags: const ['--step-ms', '1'],
                (session, _) async => updates = await collect(session, 'bash'),
              );
              return updates;
            })(),
        ]);
        final terminal = _terminals(outputs[0]).single;
        expect(terminal.output, ' M src/main.tsx\n?? notes.md\n');
        expect((terminal.exited, terminal.exitCode), (true, 0));
        expect(_terminals(outputs[1]), isEmpty);
        expect(calls(outputs[1]).last['content'], [
          {
            'type': 'content',
            'content': {
              'type': 'text',
              'text': '```console\n M src/main.tsx\n?? notes.md\n```',
            },
          },
        ]);
        expect(said(outputs[0]), ['Two files changed.']);
        expect(said(outputs[1]), ['Two files changed.']);
      },
    );

    test(
      'cancelling a command leaves no output in the following turn',
      () async {
        await withSession(capabilities: windowCapabilities(), (
          session,
          _,
        ) async {
          final requested = Completer<void>();
          final first = await run(
            session,
            'bashcut',
            onUpdate: (updates, turn) {
              if (!requested.isCompleted && calls(updates).length >= 3) {
                requested.complete();
                turn.cancel().ignore();
              }
            },
          );
          expect(requested.isCompleted, isTrue);
          expect(
            first.result,
            isA<TurnAnswered>().having((r) => r.cancelled, 'cancelled', true),
          );
          final terminal = _terminals(first.updates).single;
          expect(terminal.exited, isTrue);
          expect(terminal.exitCode, isNull);
          final next = await collect(session, 'text');
          expect(_terminals(next), isEmpty);
          expect(said(next).join(), 'Hello, world. This reply came in chunks.');
        });
      },
    );
  });
}
