import 'dart:async';

import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/session.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'reopen_session_test.dart' show Memory, directory;

void main() {
  group('CTUI-26 U3c tester: per-call outbound admission', () {
    test(
      'a nested prompt observer retains each call and writer order exactly once',
      () async {
        final dir = await directory();
        final memory = Memory();
        final session = await openSession(
          agent: 'memory',
          command: 'memory',
          cwd: dir.path,
          open: memory.open,
        );
        final snapshots = <SubmittedContent>[];
        Turn? inner;
        try {
          final outer = session.prompt(
            'outer 界👩‍💻é',
            turnId: 'outer',
            onSubmitted: (content) {
              snapshots.add(content);
              inner = session.prompt(
                'inner',
                turnId: 'inner',
                onSubmitted: (content) {
                  snapshots.add(content);
                  throw StateError('fixture nested observer');
                },
              );
            },
          );
          expect(await outer.result, isA<TurnAnswered>());
          expect(await inner!.result, isA<TurnAnswered>());
          expect(snapshots.map((s) => s.turnId), ['outer', 'inner']);
          expect(snapshots.map((s) => s.prompt), ['outer 界👩‍💻é', 'inner']);
          final requests = memory.requests.where(
            (m) => m['method'] == 'session/prompt',
          );
          expect(
            requests.map(
              (m) =>
                  (((m['params'] as Map)['prompt'] as List).first
                      as Map)['text'],
            ),
            ['outer 界👩‍💻é', 'inner'],
          );
          expect(requests.map((m) => m['id']).toSet(), hasLength(2));
        } finally {
          await memory.close(session);
        }
      },
    );

    test(
      'simultaneous equal-id sessions keep reversed mention completions separate',
      () async {
        final dir = await directory();
        final firstMemory = Memory(), secondMemory = Memory();
        final firstLinks = Completer<List<acp.ContentBlock>>();
        final secondLinks = Completer<List<acp.ContentBlock>>();
        final first = await openSession(
          agent: 'memory',
          command: 'memory',
          cwd: dir.path,
          open: firstMemory.open,
          resolveMentions: (_, _, {cancellationToken}) => firstLinks.future,
        );
        final second = await openSession(
          agent: 'memory',
          command: 'memory',
          cwd: dir.path,
          open: secondMemory.open,
          resolveMentions: (_, _, {cancellationToken}) => secondLinks.future,
        );
        final snapshots = <SubmittedContent>[];
        acp.ContentBlock link(String name) => acp.ContentBlock.fromJson({
          'type': 'resource_link',
          'uri': 'file:$name',
          'name': name,
        });
        try {
          expect(first.id, second.id);
          final a = first.prompt(
            'first @a',
            mentions: ['a'],
            turnId: 'first',
            onSubmitted: snapshots.add,
          );
          final b = second.prompt(
            'second @b',
            mentions: ['b'],
            turnId: 'second',
            onSubmitted: snapshots.add,
          );
          expect(snapshots, isEmpty);
          secondLinks.complete([link('b')]);
          expect(await b.result, isA<TurnAnswered>());
          await secondMemory.close(second);
          firstLinks.complete([link('a')]);
          expect(await a.result, isA<TurnAnswered>());
          expect(snapshots.map((s) => s.turnId), ['second', 'first']);
          expect(snapshots.map((s) => s.links.single['name']), ['b', 'a']);
          expect(snapshots.map((s) => s.prompt), ['second @b', 'first @a']);
          for (final memory in [firstMemory, secondMemory]) {
            expect(
              memory.requests.where((m) => m['method'] == 'session/prompt'),
              hasLength(1),
            );
          }
        } finally {
          await firstMemory.close(first);
          await secondMemory.close(second);
        }
      },
    );
  });
}
