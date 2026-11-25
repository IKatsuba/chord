// The starting model, effort and mode on the original's fake agent: the
// original's tests/session/conversation_test.ts starting cases.
@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:io';

import 'package:chord/acp/connection.dart' show ChordTraffic;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/modes.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/starting.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'session_fake.dart';

bool _alive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

/// The events of a conversation on the fake started on [starting], up to
/// `connected`.
Future<List<ConversationEvent>> _startOnFake(Starting starting) async {
  final dir = Directory.systemTemp.createTempSync('chord-starting-');
  final pids = <int>[];
  final events = <ConversationEvent>[];
  final connected = Completer<void>();
  final conversation = Conversation(
    ({required onTraffic, required cancellationToken}) => openSession(
      agent: 'fake',
      command: fakeAgentCommand(),
      cwd: dir.path,
      open: fakeSessionOpener(pids.add),
      onTraffic: onTraffic,
      cancellationToken: cancellationToken,
    ),
    starting: starting,
  );
  conversation.listen((event) {
    events.add(event);
    if (event is Connected && !connected.isCompleted) connected.complete();
    if (event is ConnectFailed && !connected.isCompleted) {
      connected.completeError(event.message);
    }
  });
  addTearDown(() async {
    await conversation.close();
    expect(pids.where(_alive), isEmpty, reason: 'the agent is running');
    dir.deleteSync(recursive: true);
  });
  conversation.start();
  await connected.future.timeout(const Duration(seconds: 20));
  return events;
}

String? _mode(List<ConversationEvent> events) {
  final state = events.whereType<Connected>().single.state;
  return modesFrom(state.configOptions, state.modes)?.current;
}

void main() {
  final skip = fakeAgentSkip;

  group('tester: CTUI-75 U2 held-back warning ownership', () {
    Future<
      ({
        Conversation conversation,
        List<ConversationEvent> events,
        TrafficRecorder traffic,
        Future<void> ready,
      })
    >
    begin(Starting starting, List<String> flags, String server) async {
      final root = Directory.systemTemp.createTempSync('held-back-tester-');
      final pids = <int>[];
      final events = <ConversationEvent>[];
      final traffic = TrafficRecorder();
      final ready = Completer<void>();
      final conversation =
          Conversation(
            ({required onTraffic, required cancellationToken}) => openSession(
              agent: 'fake',
              command: fakeAgentCommand(null, ['--no-http', ...flags]),
              cwd: root.path,
              mcpServers: [
                {
                  'type': 'http',
                  'name': server,
                  'url': 'https://example.com',
                  'headers': <Object>[],
                },
              ],
              open: fakeSessionOpener(pids.add),
              onTraffic: (event) {
                traffic.add(event);
                onTraffic(event);
              },
              cancellationToken: cancellationToken,
            ),
            starting: starting,
          )..listen((event) {
            events.add(event);
            if (event is Connected && !ready.isCompleted) ready.complete();
          });
      addTearDown(() async {
        await conversation.close().timeout(const Duration(seconds: 10));
        expect(
          pids.where(_alive),
          isEmpty,
          reason: 'owned fake remained alive',
        );
        root.deleteSync(recursive: true);
      });
      conversation.start();
      return (
        conversation: conversation,
        events: events,
        traffic: traffic,
        ready: ready.future,
      );
    }

    List<String> warnings(List<ConversationEvent> events) => [
      for (final event in events)
        if (event case Transcribed(action: WarnedAction(:final message)))
          message,
    ];

    test(
      'closing a hung startup never publishes its held-back warning',
      () async {
        final run = await begin(
          const Starting(model: StartingValue('fake-small')),
          ['--hang', 'config'],
          'hung-docs',
        );
        await run.traffic
            .next(
              (event) =>
                  event is ChordTraffic &&
                  [
                    'session/set_model',
                    'session/set_config_option',
                  ].contains(event.message['method']),
            )
            .timeout(const Duration(seconds: 10));
        expect(warnings(run.events), isEmpty);
        await run.conversation.close().timeout(const Duration(seconds: 10));
        expect(warnings(run.events), isEmpty);
        expect(run.events.whereType<Connected>(), isEmpty);
        expect(run.events.whereType<HistoryReplayed>(), isEmpty);
      },
      skip: skip,
    );

    test(
      'concurrent sessions keep refusals and held-back names separate',
      () async {
        final first = await begin(
          const Starting(effort: StartingValue('high')),
          ['--refuse-config'],
          'refused-docs',
        );
        final second = await begin(const Starting(), [], 'other-docs');
        await Future.wait([
          first.ready,
          second.ready,
        ]).timeout(const Duration(seconds: 20));
        for (final (run, own, other) in [
          (first, 'refused-docs', 'other-docs'),
          (second, 'other-docs', 'refused-docs'),
        ]) {
          expect(warnings(run.events), hasLength(1));
          expect(warnings(run.events).single, contains(own));
          expect(warnings(run.events).single, isNot(contains(other)));
          final warned = run.events.indexWhere(
            (event) => event is Transcribed && event.action is WarnedAction,
          );
          final connected = run.events.indexWhere(
            (event) => event is Connected,
          );
          expect(warned, lessThan(connected));
        }
        final refused = first.events.indexWhere(
          (event) => event is Transcribed && event.action is FailedAction,
        );
        final warned = first.events.indexWhere(
          (event) => event is Transcribed && event.action is WarnedAction,
        );
        expect(refused, greaterThanOrEqualTo(0));
        expect(refused, lessThan(warned));
        expect(
          second.events.whereType<Transcribed>().any(
            (event) => event.action is FailedAction,
          ),
          isFalse,
        );
      },
      skip: skip,
    );
  });

  group('tester: CTUI-29 original fake startup boundaries', () {
    Future<
      ({
        Conversation conversation,
        List<ConversationEvent> events,
        TrafficRecorder traffic,
      })
    >
    begin(Starting starting, List<String> flags) async {
      final root = Directory.systemTemp.createTempSync('starting-tester-');
      final pids = <int>[];
      final traffic = TrafficRecorder();
      final events = <ConversationEvent>[];
      final conversation = Conversation(
        ({required onTraffic, required cancellationToken}) => openSession(
          agent: 'fake',
          command: fakeAgentCommand(null, flags),
          cwd: root.path,
          open: fakeSessionOpener(pids.add),
          onTraffic: (event) {
            traffic.add(event);
            onTraffic(event);
          },
          cancellationToken: cancellationToken,
        ),
        starting: starting,
      )..listen(events.add);
      addTearDown(() async {
        await conversation.close().timeout(const Duration(seconds: 10));
        expect(
          pids.where(_alive),
          isEmpty,
          reason: 'owned fake agent remained alive',
        );
        root.deleteSync(recursive: true);
      });
      conversation.start();
      return (conversation: conversation, events: events, traffic: traffic);
    }

    for (final kind in ['model', 'mode', 'clear']) {
      test('close stops a fake hanging on startup $kind', () async {
        final run = await begin(
          kind == 'mode'
              ? const Starting(mode: StartingValue('plan'))
              : const Starting(model: StartingValue('fake-small')),
          ['--hang', 'config'],
        );
        await run.traffic
            .next(
              (event) =>
                  event is ChordTraffic &&
                  [
                    'session/set_model',
                    'session/set_mode',
                    'session/set_config_option',
                  ].contains(event.message['method']),
            )
            .timeout(const Duration(seconds: 10));
        if (kind == 'clear') {
          await run.conversation.clear().timeout(const Duration(seconds: 10));
        }
        await run.conversation.close().timeout(const Duration(seconds: 10));
        expect(run.events.whereType<Connected>(), isEmpty);
        expect(run.events.last, isA<Closing>());
      }, skip: skip);
    }

    for (final (flags, effort, reason) in [
      (<String>['--refuse-config'], 'high', 'The fake agent holds its effort.'),
      (<String>[], 'max', 'the agent offers low, medium, high'),
      (<String>['--no-config'], 'high', 'the agent offers no efforts'),
    ]) {
      test('a required effort refusal remains optional with $reason', () async {
        final run = await begin(
          Starting(
            effort: StartingValue(
              effort,
              from: 'set by --effort',
              required: true,
            ),
          ),
          flags,
        );
        final connected = Completer<void>();
        final unsubscribe = run.conversation.listen((event) {
          if (event is Connected && !connected.isCompleted) {
            connected.complete();
          }
          if (event is ConnectFailed && !connected.isCompleted) {
            connected.completeError(event.message);
          }
        });
        addTearDown(unsubscribe);
        await connected.future.timeout(const Duration(seconds: 10));
        expect(
          [
            for (final event in run.events)
              if (event case Transcribed(action: FailedAction(:final message)))
                message,
          ],
          ['Could not start on $effort effort, set by --effort: $reason'],
        );
        expect(run.events.whereType<Connected>(), hasLength(1));
      }, skip: skip);
    }
  });

  test(
    'a starting mode the agent offers is the one the session opens in',
    () async {
      final events = await _startOnFake(
        const Starting(
          mode: StartingValue('plan', from: 'set by --permission-mode'),
        ),
      );
      expect(_mode(events), 'plan');
      expect(
        events.any((e) => e is Transcribed && e.action is FailedAction),
        isFalse,
      );
    },
    skip: skip,
  );

  test('a starting mode the agent does not offer is said with where it was '
      'set and what it offers', () async {
    final events = await _startOnFake(
      const Starting(
        mode: StartingValue('yolo', from: 'set in .chord/settings.json'),
      ),
    );
    final failed = events.indexWhere(
      (e) => e is Transcribed && e.action is FailedAction,
    );
    final action = (events[failed] as Transcribed).action as FailedAction;
    expect(action.turnId, 'starting-1');
    expect(
      action.message,
      'Could not start in yolo mode, set in .chord/settings.json: the agent '
      'offers default, acceptEdits, plan',
    );
    expect(failed, lessThan(events.indexWhere((e) => e is Connected)));
    expect(_mode(events), 'default');
  }, skip: skip);
}
