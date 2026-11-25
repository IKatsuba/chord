import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:test/test.dart';

import 'recording_conversation_test.dart'
    show Controlled, Spy, past, say, settled;

void main() {
  group('CTUI-26 U4b tester: recording-open replacement boundary', () {
    for (final warning in [false, true]) {
      test(
        '${warning ? 'warning observer' : 'recorder open'} replacement suppresses old live subscription and facts',
        () async {
          const oldFacts = Resume(
            sessionId: 'same',
            cwd: 'fixture-project',
            title: 'OLD title',
          );
          const newFacts = Resume(
            sessionId: 'same',
            cwd: 'fixture-project',
            title: 'NEW title',
          );
          final first = Controlled(
            'same',
            resumed: oldFacts,
            actions: past('OLD'),
          )..retained.add(acp.SessionUpdate.fromJson(say('old retained')));
          final second = Controlled(
            'same',
            resumed: newFacts,
            actions: past('NEW'),
          )..retained.add(acp.SessionUpdate.fromJson(say('new live')));
          final spy = Spy([]);
          final conversation = Conversation(
            ({required onTraffic, required cancellationToken}) async => first,
            recording: spy,
            reopen:
                (_, {required onTraffic, required cancellationToken}) async =>
                    second,
          );
          final events = <ConversationEvent>[];
          var app = AppState.starting;
          void replace() => conversation.resume(newFacts).ignore();
          spy.onOpen = () {
            spy.onOpen = null;
            if (warning) throw StateError('fixture open observer');
            replace();
          };
          conversation.listen((event) {
            app = reduceApp(app, event);
            events.add(event);
            if (warning &&
                event is Transcribed &&
                event.action is WarnedAction) {
              replace();
            }
          });
          try {
            conversation.start();
            await settled();
            expect(first.closed, isTrue);
            expect(first.subscriptions, 0);
            expect(second.subscriptions, 1);
            expect(spy.openedSessions, hasLength(2));
            expect(events.whereType<Connected>(), hasLength(1));
            expect(app.resumed, same(newFacts));
            expect(
              app.transcript.entries.whereType<AssistantEntry>().map(
                (e) => e.text.text,
              ),
              ['NEW', 'new live'],
            );
            first.emit(say('old late'));
            await settled();
            expect(
              app.transcript.entries.whereType<AssistantEntry>().map(
                (e) => e.text.text,
              ),
              ['NEW', 'new live'],
            );
            expect(
              events.whereType<Transcribed>().where(
                (e) => e.action is WarnedAction,
              ),
              hasLength(warning ? 1 : 0),
            );
            expect(
              spy.events.whereType<Transcribed>().where(
                (e) => e.action is WarnedAction,
              ),
              isEmpty,
            );
          } finally {
            await conversation.close();
          }
          expect(first.closes, 1);
          expect(second.closes, 1);
        },
      );
    }
  });
}
