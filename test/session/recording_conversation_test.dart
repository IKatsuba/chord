import 'dart:async';
import 'dart:io';

import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/servers.dart';
import 'package:chord/session/auth_status.dart';
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/start_state.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'conversation_fake.dart';
import 'reopen_session_test.dart' as memory;

Future<void> settled() => Future<void>.delayed(Duration.zero);

final class Controlled implements Session {
  Controlled(
    this.id, {
    this.resumed,
    this.record,
    List<TranscriptAction> actions = const [],
    bool omitted = false,
    this.closeGate,
  }) {
    prepared = PreparedHistory(
      rawHasPast: record != null,
      omitted: omitted,
      actions: actions,
    );
  }
  final inner = ScriptedSession();
  @override
  final String id;
  @override
  String get agent => 'controlled';
  @override
  String get cwd => 'fixture-project';
  @override
  final Resume? resumed;
  @override
  final String? record;
  late PreparedHistory prepared;
  final List<acp.SessionUpdate> retained = [];
  final Completer<void>? closeGate;
  var closed = false, subscriptions = 0, reads = 0, closes = 0;
  Future<void>? closing;
  @override
  AgentState get state => inner.state;
  @override
  get permissions => inner.permissions;
  @override
  get plans => inner.plans;
  @override
  get elicitations => inner.elicitations;
  @override
  Future<void> get exited => inner.exited;
  @override
  String? gone() => inner.gone();
  @override
  PreparedHistory takeHistory() {
    reads++;
    final result = prepared;
    prepared = PreparedHistory.empty;
    return result;
  }

  @override
  void Function() subscribeAll(
    void Function(acp.SessionUpdate update, String? subagentId) listener,
  ) => subscribe((update) => listener(update, null));

  @override
  void Function() subscribe(void Function(acp.SessionUpdate) listener) {
    subscriptions++;
    final stop = inner.subscribe(listener);
    for (final update in retained.toList()) {
      if (closed) break;
      inner.state = foldUpdate(inner.state, update);
      listener(update);
    }
    retained.clear();
    return stop;
  }

  void emit(Map<String, Object?> json) {
    inner.state = foldUpdate(inner.state, acp.SessionUpdate.fromJson(json));
    inner.say(json);
  }

  @override
  Turn prompt(
    String text, {
    List<String> mentions = const [],
    PromptParts parts = PromptParts.none,
    String? turnId,
    void Function(SubmittedContent)? onSubmitted,
  }) => inner.prompt(
    text,
    mentions: mentions,
    parts: parts,
    turnId: turnId,
    onSubmitted: onSubmitted,
  );
  @override
  List<HeldBack> get heldBack => inner.heldBack;

  @override
  String? get chordServer => inner.chordServer;

  @override
  Map<String, Object?>? get chordServerPassed => inner.chordServerPassed;
  @override
  Future<void> setConfigEntry(Map<String, Object?> entry) =>
      inner.setConfigEntry(entry);
  @override
  AccountState get account => inner.account;
  @override
  void Function() subscribeAccount(void Function(AccountState) listener) =>
      inner.subscribeAccount(listener);
  @override
  bool takesTitles() => inner.takesTitles();
  @override
  bool forks() => inner.forks();
  @override
  Future<String> setTitle(String title) => inner.setTitle(title);
  @override
  bool takesImages() => inner.takesImages();
  @override
  bool takesEmbeddedContext() => inner.takesEmbeddedContext();
  @override
  bool steers() => inner.steers();
  @override
  bool cutsCallsOnSteer() => inner.cutsCallsOnSteer();
  @override
  bool startsOwnCycles() => inner.startsOwnCycles();
  @override
  Future<SteerOutcome> steer(
    String text, {
    List<String> mentions = const [],
    PromptParts parts = PromptParts.none,
    String? turnId,
    void Function(SubmittedContent content)? onSubmitted,
  }) => inner.steer(
    text,
    mentions: mentions,
    parts: parts,
    turnId: turnId,
    onSubmitted: onSubmitted,
  );
  @override
  Future<void> cancel() => inner.cancel();
  @override
  Future<void> stopSubagent(String id) => inner.stopSubagent(id);
  @override
  Future<void> setMode(String id) => inner.setMode(id);
  @override
  Future<void> setModel(String id) => inner.setModel(id);
  @override
  Future<void> setOption(String id, String value) => inner.setOption(id, value);
  @override
  Future<void> close() {
    if (closing case final future?) return future;
    final done = Completer<void>();
    closing = done.future;
    closed = true;
    closes++;
    () async {
      await inner.close();
      await closeGate?.future;
    }().then(done.complete, onError: done.completeError);
    return done.future;
  }
}

final class Spy implements Recording {
  Spy(this.order);
  final List<String> order;
  final openedSessions = <RecordingSession>[];
  final events = <ConversationEvent>[];
  final prompts = <Map<String, Object?>>[];
  void Function()? onOpen, onSent;
  void Function(ConversationEvent)? onHeard;
  Completer<void>? flushGate;
  int flushes = 0;
  @override
  void opened(RecordingSession session) {
    order.add('record open');
    openedSessions.add(session);
    onOpen?.call();
  }

  @override
  void sent(
    String turnId,
    String prompt,
    num images,
    List<Map<String, Object?>> links,
    num at, {
    List<Map<String, Object?>> resources = const [],
    String? into,
    MessageFrom? from,
  }) {
    order.add('record sent');
    prompts.add({
      'turnId': turnId,
      'prompt': prompt,
      'images': images,
      'links': links,
      'at': at,
      'resources': resources,
      'into': ?into,
    });
    onSent?.call();
  }

  @override
  void heard(ConversationEvent event) {
    order.add('record ${event.runtimeType}');
    events.add(event);
    onHeard?.call(event);
  }

  @override
  Future<void> flushed() async {
    flushes++;
    await flushGate?.future;
  }
}

Map<String, Object?> say(String text) => {
  'sessionUpdate': 'agent_message_chunk',
  'content': {'type': 'text', 'text': text},
};
List<TranscriptAction> past([String text = 'PAST']) => [
  const PromptAction('history-id', 'saved prompt', 1.25),
  UpdateAction('history-id', acp.SessionUpdate.fromJson(say(text))),
  const ResultAction('history-id', TurnAnswered('end_turn')),
];

void main() {
  test(
    'recording callback replacement ends old event delivery before actual admission',
    () async {
      final first = Controlled('first'), second = Controlled('second');
      final spy = Spy([]);
      final c = Conversation(
        ({required onTraffic, required cancellationToken}) async => first,
        recording: spy,
        reopen: (_, {required onTraffic, required cancellationToken}) async =>
            second,
      );
      final events = <ConversationEvent>[];
      c.listen(events.add);
      c.start();
      await settled();
      spy.onHeard = (event) {
        if (event case Transcribed(action: PromptAction())) {
          spy.onHeard = null;
          c
              .resume(const Resume(sessionId: 'second', cwd: 'fixture-project'))
              .ignore();
        }
      };
      c.send('must not admit');
      await settled();
      expect(first.inner.turns, isEmpty);
      expect(spy.prompts, isEmpty);
      expect(
        events.whereType<Transcribed>().where((e) => e.action is PromptAction),
        isEmpty,
      );
      // Closed after its quiet, as the original closes a session let go.
      await Future<void>.delayed(const Duration(milliseconds: quietMs + 100));
      expect(first.closed, isTrue);
      expect(c.send('new'), isTrue);
      second.inner.turns.single.answer(const TurnAnswered('end_turn'));
      await settled();
      await c.close();
    },
  );

  test(
    'throwing sent recorder warns once without disabling work or resumability',
    () async {
      final session = Controlled('id'), spy = Spy([]);
      final c = Conversation(
        ({required onTraffic, required cancellationToken}) async => session,
        recording: spy,
      );
      final events = <ConversationEvent>[];
      c.listen(events.add);
      spy.onSent = () => throw StateError('record observer');
      c.start();
      await settled();
      for (final text in ['first', 'second']) {
        expect(c.send(text), isTrue);
        session.inner.turns.last.answer(const TurnAnswered('end_turn'));
        await settled();
      }
      expect(
        events.whereType<Transcribed>().where((e) => e.action is WarnedAction),
        hasLength(1),
      );
      expect(
        spy.events.whereType<Transcribed>().where(
          (e) => e.action is WarnedAction,
        ),
        isEmpty,
      );
      expect(spy.prompts, hasLength(2));
      expect(c.resumable, (agent: 'controlled', sessionId: 'id'));
      await c.close();
    },
  );

  test(
    'mixed-path admitted writes keep their captured record across replacement and close',
    () async {
      final dir = await memory.directory();
      final firstFile = File(p.join(dir.path, 'first.jsonl')),
          secondFile = File(p.join(dir.path, 'second.jsonl'));
      await firstFile.writeAsString('');
      await secondFile.writeAsString('');
      final first = Controlled('first', record: firstFile.path),
          second = Controlled('second', record: secondFile.path);
      final entered = Completer<void>(), release = Completer<void>();
      final recorder = FileRecording(
        dir.path,
        failed: fail,
        append: (path, text) async {
          if (!entered.isCompleted) {
            entered.complete();
            await release.future;
          }
          await File(path).writeAsString(text, mode: FileMode.append);
        },
      );
      final c = Conversation(
        ({required onTraffic, required cancellationToken}) async => first,
        recording: recorder,
        reopen: (_, {required onTraffic, required cancellationToken}) async =>
            second,
      );
      c.start();
      await settled();
      c.send('FIRST');
      await entered.future;
      await c.resume(
        Resume(
          sessionId: 'second',
          cwd: 'fixture-project',
          record: secondFile.path,
        ),
      );
      await settled();
      c.send('SECOND');
      second.inner.turns.single.answer(const TurnAnswered('end_turn'));
      await settled();
      first.inner.turns.single.answer(const TurnAnswered('end_turn'));
      final close = c.close();
      release.complete();
      await close;
      final old = await firstFile.readAsString(),
          current = await secondFile.readAsString();
      expect(old, contains('FIRST'));
      expect(old, isNot(contains('SECOND')));
      expect(current, contains('SECOND'));
      expect(current, isNot(contains('FIRST')));
    },
  );

  test(
    'history publishes once before recording open/live drain and never reaches Recording',
    () async {
      final order = <String>[], spy = Spy(order);
      const resumed = Resume(sessionId: 'id', cwd: 'fixture-project');
      final session = Controlled(
        'id',
        resumed: resumed,
        actions: past(),
        omitted: true,
      )..retained.add(acp.SessionUpdate.fromJson(say('LIVE')));
      final c = Conversation(
        ({required onTraffic, required cancellationToken}) async => session,
        recording: spy,
      );
      var app = AppState.starting;
      final snapshots = <AppState>[];
      c.listen((event) {
        app = reduceApp(app, event);
        snapshots.add(app);
        order.add('window ${event.runtimeType}');
        if (event is HistoryReplayed) expect(c.send('too early'), isFalse);
      });
      c.start();
      await settled();
      expect(
        order.indexOf('window HistoryReplayed'),
        lessThan(order.indexOf('record open')),
      );
      expect(
        order.indexOf('record open'),
        lessThan(order.indexOf('record Transcribed')),
      );
      expect(
        order.indexOf('record Transcribed'),
        lessThan(order.indexOf('window Transcribed')),
      );
      expect(
        order.indexOf('window Transcribed'),
        lessThan(order.indexOf('window Connected')),
      );
      expect(spy.events.whereType<HistoryReplayed>(), isEmpty);
      expect(
        spy.events.whereType<Transcribed>().where(
          (e) => e.action.turnId.startsWith('history-'),
        ),
        isEmpty,
      );
      expect(
        spy.openedSessions.single.history
            .where((e) => e['type'] == 'prompt')
            .single['images'],
        0,
      );
      expect(
        snapshots.first.transcript.entries
            .whereType<AssistantEntry>()
            .single
            .text
            .text,
        'PAST',
      );
      expect(
        app.transcript.entries.whereType<AssistantEntry>().map(
          (e) => e.text.text,
        ),
        ['PAST', 'LIVE'],
      );
      expect(app.omittedHistory, isTrue);
      expect(c.resumable, (agent: 'controlled', sessionId: 'id'));
      expect(session.reads, 1);
      await c.close();
    },
  );

  test(
    'close during history publication prevents recording open, live subscription and Connected',
    () async {
      final spy = Spy([]);
      final session = Controlled(
        'id',
        resumed: const Resume(sessionId: 'id', cwd: 'fixture-project'),
        actions: past(),
      )..retained.add(acp.SessionUpdate.fromJson(say('late')));
      final c = Conversation(
        ({required onTraffic, required cancellationToken}) async => session,
        recording: spy,
      );
      Future<void>? closing;
      final later = <ConversationEvent>[];
      c.listen((event) {
        if (event is HistoryReplayed) closing = c.close();
      });
      c.listen(later.add);
      c.start();
      await settled();
      await closing;
      expect(later.whereType<HistoryReplayed>(), isEmpty);
      expect(later.whereType<Closing>(), hasLength(1));
      expect(later.whereType<Connected>(), isEmpty);
      expect(session.subscriptions, 0);
      expect(spy.openedSessions, isEmpty);
      expect(session.closes, 1);
    },
  );

  test(
    'history listener replacement cannot publish stale remainder with equal persisted ids',
    () async {
      final first = Controlled(
        'same',
        resumed: const Resume(sessionId: 'same', cwd: 'fixture-project'),
        actions: past('OLD'),
      );
      final second = Controlled(
        'same',
        resumed: const Resume(sessionId: 'same', cwd: 'fixture-project'),
        actions: past('NEW'),
      );
      final spy = Spy([]);
      final c = Conversation(
        ({required onTraffic, required cancellationToken}) async => first,
        recording: spy,
        reopen: (_, {required onTraffic, required cancellationToken}) async =>
            second,
      );
      var replaced = false;
      var app = AppState.starting;
      c.listen((event) {
        app = reduceApp(app, event);
        if (event is HistoryReplayed && !replaced) {
          replaced = true;
          c
              .resume(const Resume(sessionId: 'same', cwd: 'fixture-project'))
              .ignore();
        }
      });
      final later = <ConversationEvent>[];
      c.listen(later.add);
      c.start();
      await settled();
      expect(later.whereType<HistoryReplayed>(), hasLength(1));
      expect(
        app.transcript.entries.whereType<AssistantEntry>().single.text.text,
        'NEW',
      );
      expect(first.subscriptions, 0);
      expect(first.closes, 1);
      expect(spy.openedSessions, hasLength(1));
      await c.close();
      expect(second.closes, 1);
    },
  );

  test(
    'recording hears admitted payload before user observers and failures stay local',
    () async {
      final order = <String>[], spy = Spy(order);
      final session = Controlled('id');
      final c = Conversation(
        ({required onTraffic, required cancellationToken}) async => session,
        recording: spy,
      );
      final events = <ConversationEvent>[];
      c.listen((event) {
        events.add(event);
        order.add('window ${event.runtimeType}');
      });
      c.start();
      await settled();
      expect(c.resumable, isNull);
      c.send('typed @fixture', 'final shell context @fixture');
      expect(spy.prompts.single['prompt'], 'final shell context @fixture');
      expect(spy.prompts.single['turnId'], 'turn-1');
      session.emit(say('reply'));
      expect(
        order.lastIndexOf('record Transcribed'),
        lessThan(order.lastIndexOf('window Transcribed')),
      );
      session.inner.turns.single.answer(const TurnAnswered('end_turn'));
      await settled();
      expect(c.resumable, (agent: 'controlled', sessionId: 'id'));
      c.recordingFailed('record unavailable');
      c.recordingFailed('again');
      expect(
        events.whereType<Transcribed>().where((e) => e.action is WarnedAction),
        hasLength(1),
      );
      expect(
        spy.events.whereType<Transcribed>().where(
          (e) => e.action is WarnedAction,
        ),
        isEmpty,
      );
      await c.close();
    },
  );

  for (final interrupt in [false, true]) {
    test(
      '${interrupt ? 'cancel' : 'close'} from prompt observer records no unsubmitted prompt/result',
      () async {
        final dir = await memory.directory();
        final file = File(p.join(dir.path, 'records', 'fixture.jsonl'));
        final recorder = FileRecording(
          dir.path,
          failed: fail,
          uuid: () => 'fixture',
        );
        final session = Controlled('id');
        final c = Conversation(
          ({required onTraffic, required cancellationToken}) async => session,
          recording: recorder,
        );
        Future<void>? closing;
        c.listen((event) {
          if (event case Transcribed(action: PromptAction())) {
            if (interrupt) {
              c.interrupt();
            } else {
              closing = c.close();
            }
          }
        });
        c.start();
        await settled();
        c.send('not submitted');
        await settled();
        await closing;
        await c.close();
        expect(session.inner.turns, isEmpty);
        expect(await file.exists(), isFalse);
        expect(c.resumable, isNull);
      },
    );
  }

  test(
    'reentrant send during admission queues and replacement cannot overwrite its new turn',
    () async {
      final first = Controlled('first'), second = Controlled('second');
      final spy = Spy([]);
      final c = Conversation(
        ({required onTraffic, required cancellationToken}) async => first,
        recording: spy,
        reopen: (_, {required onTraffic, required cancellationToken}) async =>
            second,
      );
      c.start();
      await settled();
      spy.onSent = () {
        spy.onSent = null;
        expect(c.send('queued'), isTrue);
        c
            .resume(const Resume(sessionId: 'second', cwd: 'fixture-project'))
            .ignore();
      };
      c.send('old');
      await settled();
      // The session let go closes once its turn has ended and gone quiet.
      expect(first.closed, isFalse);
      first.inner.turns.single.answer(const TurnAnswered('end_turn'));
      await settled();
      await Future<void>.delayed(const Duration(milliseconds: quietMs + 100));
      expect(first.closed, isTrue);
      expect(second.closed, isFalse);
      expect(c.send('new'), isTrue);
      second.inner.turns.single.answer(const TurnAnswered('end_turn'));
      await settled();
      expect(spy.prompts.map((p) => p['prompt']), ['old', 'new']);
      expect(
        spy.events.whereType<QueueWithdrawn>().single.prompts.single.text,
        'queued',
      );
      expect(
        spy.events
            .whereType<Transcribed>()
            .where((e) => e.action is ResultAction)
            .map((e) => e.action.turnId),
        ['turn-3'],
      );
      await c.close();
    },
  );

  test(
    'swap during retained live callback closes old drain and suppresses following state',
    () async {
      final first = Controlled('first')
        ..retained.addAll([
          acp.SessionUpdate.fromJson({
            'sessionUpdate': 'current_mode_update',
            'currentModeId': 'OLD',
          }),
          acp.SessionUpdate.fromJson(say('must not drain')),
        ]);
      final second = Controlled('second')
        ..inner.state = const AgentState(modes: {'currentModeId': 'NEW'});
      final spy = Spy([]);
      final c = Conversation(
        ({required onTraffic, required cancellationToken}) async => first,
        recording: spy,
        reopen: (_, {required onTraffic, required cancellationToken}) async =>
            second,
      );
      var app = AppState.starting, swapped = false;
      final events = <ConversationEvent>[];
      c.listen((event) {
        app = reduceApp(app, event);
        events.add(event);
        if (event is Transcribed && !swapped) {
          swapped = true;
          c
              .resume(const Resume(sessionId: 'second', cwd: 'fixture-project'))
              .ignore();
        }
      });
      c.start();
      await settled();
      await Future<void>.delayed(const Duration(milliseconds: quietMs + 100));
      expect(first.closed, isTrue);
      expect(app.agent.modes!['currentModeId'], 'NEW');
      expect(events.whereType<AgentStateChanged>(), isEmpty);
      expect(spy.events.whereType<Transcribed>(), hasLength(1));
      await c.close();
    },
  );

  test(
    'close joins retired sessions even when replacement open fails',
    () async {
      final gate = Completer<void>();
      final first = Controlled('first', closeGate: gate);
      final spy = Spy([]);
      final c = Conversation(
        ({required onTraffic, required cancellationToken}) async => first,
        recording: spy,
        reopen: (_, {required onTraffic, required cancellationToken}) async =>
            throw StateError('replacement failed'),
      );
      final events = <ConversationEvent>[];
      c.listen(events.add);
      c.start();
      await settled();
      c.resume(const Resume(sessionId: 'bad', cwd: 'fixture-project')).ignore();
      await settled();
      var closed = false;
      final close = c.close().then((_) => closed = true);
      await settled();
      expect(closed, isFalse);
      gate.complete();
      await close;
      expect(events.whereType<ConnectFailed>(), hasLength(1));
      expect(first.closes, 1);
    },
  );

  test(
    'completed close joins slow admitted bytes and nothing recreates a removed directory',
    () async {
      final dir = await memory.directory();
      final entered = Completer<void>(), release = Completer<void>();
      var writes = 0;
      final recorder = FileRecording(
        dir.path,
        failed: fail,
        uuid: () => 'fixture',
        append: (path, text) async {
          writes++;
          entered.complete();
          await release.future;
          await Directory(p.dirname(path)).create(recursive: true);
          await File(path).writeAsString(text, mode: FileMode.append);
        },
      );
      final session = Controlled('id');
      final c = Conversation(
        ({required onTraffic, required cancellationToken}) async => session,
        recording: recorder,
      );
      c.start();
      await settled();
      c.send('admitted');
      await entered.future;
      var closed = false;
      final close = c.close().then((_) => closed = true);
      await settled();
      expect(closed, isFalse);
      session.emit(say('late'));
      release.complete();
      await close;
      await dir.delete(recursive: true);
      session.inner.turns.single.answer(const TurnAnswered('end_turn'));
      session.emit(say('later'));
      await settled();
      expect(await dir.exists(), isFalse);
      expect(writes, 1);
    },
  );

  test(
    'StartConnection publishes historical rows once before live rows and allows close in that gap',
    () async {
      for (final closeAtHistory in [false, true]) {
        final dir = await memory.directory();
        final file = File(p.join(dir.path, 'record.jsonl'));
        await file.writeAsString(
          encodeRecord({
            'type': 'prompt',
            'turnId': 'saved',
            'prompt': 'PAST',
            'images': 0,
            'at': 1,
          }),
        );
        final transport = memory.Memory()..post = [memory.say('LIVE')];
        final spy = Spy([]);
        final connection = StartConnection(
          command: 'memory',
          cwd: dir.path,
          agent: 'memory',
          open: transport.open,
          resume: Resume(
            sessionId: 'literal/id',
            cwd: dir.path,
            record: file.path,
          ),
          recording: spy,
        );
        final historyEvents = <HistoryReplayed>[];
        Future<void>? closing;
        connection.listen((event) {
          if (event is HistoryReplayed) historyEvents.add(event);
        });
        connection.app.addListener(() {
          final app = connection.app.value;
          if (closeAtHistory &&
              app.transcript.entries.whereType<UserEntry>().isNotEmpty &&
              !app.closing) {
            closing = connection.close();
          }
        });
        connection.start();
        while (!transport.process.exited &&
            connection.app.value.start.phase != StartPhase.connected) {
          await settled();
        }
        if (closeAtHistory) {
          await closing;
          expect(historyEvents, isEmpty);
          expect(spy.openedSessions, isEmpty);
          expect(
            connection.app.value.transcript.entries.whereType<AssistantEntry>(),
            isEmpty,
          );
        } else {
          expect(historyEvents, hasLength(1));
          expect(
            connection.app.value.transcript.entries
                .whereType<UserEntry>()
                .single
                .text,
            'PAST',
          );
          expect(
            connection.app.value.transcript.entries
                .whereType<AssistantEntry>()
                .single
                .text
                .text,
            'LIVE',
          );
          expect(spy.events.whereType<HistoryReplayed>(), isEmpty);
          await connection.close();
        }
        expect(transport.process.exited, isTrue);
      }
    },
  );
}
