@Tags(['fake_agent'])
library;

import 'dart:async';
import 'package:chord/acp/connection.dart';
import 'package:chord/session/context.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';
import 'session_fake.dart';

void main() {
  test(
    'fake receives held local output while transcript retains only typed text',
    () async {
      await withSession((session, traffic) async {
        final conversation = Conversation(
          ({required onTraffic, required cancellationToken}) async => session,
        );
        final connected = Completer<void>(), ended = Completer<void>();
        final actions = <TranscriptAction>[];
        conversation.listen((event) {
          if (event is Connected) connected.complete();
          if (event is Transcribed) {
            actions.add(event.action);
            if (event.action is ResultAction) ended.complete();
          }
        });
        conversation.start();
        await connected.future.timeout(const Duration(seconds: 5));
        final payload = withContext(
          shellContext([
            const ShellRun(
              command: 'printf ready',
              stdout: '\u009b31mready\u009b0m\n',
              running: false,
              code: 0,
            ),
          ]),
          'text',
        );
        expect(conversation.send('text', payload), isTrue);
        try {
          await ended.future.timeout(const Duration(seconds: 10));
          expect(actions.whereType<PromptAction>().single.text, 'text');
          final prompts = traffic.heard
              .whereType<ChordTraffic>()
              .map((t) => t.message)
              .where((m) => m['method'] == 'session/prompt');
          expect(
            prompts.single['params'],
            containsPair('prompt', [
              {'type': 'text', 'text': payload},
            ]),
          );
          expect(payload, contains('<bash-stdout>ready</bash-stdout>'));
        } finally {
          await conversation.close();
        }
      });
    },
    skip: fakeAgentSkip,
  );
}
