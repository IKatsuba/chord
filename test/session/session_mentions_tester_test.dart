@Tags(['fake_agent'])
library;

import 'dart:async';

import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/transcript/types.dart' show TurnAnswered;
import 'package:test/test.dart';

import '../fixtures/fake_harness.dart';
import 'session_mentions_test.dart' show withLinks, sent, link;

void main() {
  group('tester: resolved links retain turn and session ownership', () {
    test(
      'cancelling one resolver leaves another and later active turn untouched',
      () async {
        final first = Completer<List<acp.ContentBlock>>();
        final second = Completer<List<acp.ContentBlock>>();
        await withLinks(
          (session, traffic, _) async {
            final cancelled = session.prompt('first', mentions: ['a']);
            final surviving = session.prompt('second', mentions: ['b']);
            await cancelled.cancel();
            expect((await cancelled.result as TurnAnswered).cancelled, isTrue);
            second.complete([link('b')]);
            expect(await surviving.result, isA<TurnAnswered>());
            expect(sent(traffic, 'session/prompt'), hasLength(1));
            first.completeError(StateError('late retired resolver'));
            final chunk = Completer<void>();
            final forget = session.subscribe((update) {
              if (update.toJson()['sessionUpdate'] == 'agent_message_chunk' &&
                  !chunk.isCompleted) {
                chunk.complete();
              }
            });
            final active = session.prompt('slow');
            await chunk.future.timeout(const Duration(seconds: 5));
            await cancelled.cancel();
            await surviving.cancel();
            expect(sent(traffic, 'session/cancel'), isEmpty);
            await active.cancel();
            expect((await active.result as TurnAnswered).cancelled, isTrue);
            expect(sent(traffic, 'session/cancel'), hasLength(1));
            forget();
          },
          resolver: (paths, cwd, {cancellationToken}) =>
              paths.single == 'a' ? first.future : second.future,
        );
      },
    );

    test(
      'closing one session cannot cancel another resolver or redirect late links',
      () async {
        final first = Completer<List<acp.ContentBlock>>();
        final second = Completer<List<acp.ContentBlock>>();
        String? firstCwd;
        await withLinks(
          (a, aTraffic, _) async {
            final old = a.prompt('old', mentions: ['a']);
            await withLinks(
              (b, bTraffic, _) async {
                final current = b.prompt('current', mentions: ['b']);
                await a.close();
                expect((await old.result as TurnAnswered).cancelled, isTrue);
                first.complete([link('a')]);
                second.complete([link('b')]);
                expect(await current.result, isA<TurnAnswered>());
                expect(sent(aTraffic, 'session/prompt'), isEmpty);
                final blocks =
                    (sent(bTraffic, 'session/prompt').single['params']
                            as Map)['prompt']
                        as List;
                expect((blocks.first as Map)['text'], 'current');
                expect((blocks.last as Map)['name'], 'b');
              },
              resolver: (paths, cwd, {cancellationToken}) {
                expect(cwd, isNot(firstCwd));
                return second.future;
              },
            );
          },
          resolver: (paths, cwd, {cancellationToken}) {
            firstCwd = cwd;
            return first.future;
          },
        );
      },
    );

    test(
      'synchronous resolver failure still sends exactly one text block',
      () async {
        await withLinks(
          (session, traffic, _) async {
            expect(
              await session.prompt('literal @a', mentions: ['a']).result,
              isA<TurnAnswered>(),
            );
            expect(
              (sent(traffic, 'session/prompt').single['params']
                  as Map)['prompt'],
              [
                {'type': 'text', 'text': 'literal @a'},
              ],
            );
          },
          resolver: (_, _, {cancellationToken}) =>
              throw StateError('synchronous discovery failure'),
        );
      },
    );
  }, skip: fakeAgentSkip);
}
