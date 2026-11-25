import 'dart:convert';
import 'dart:io';

import 'package:chord/session/conversation.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:fake_async/fake_async.dart';

import '../../session/conversation_fake.dart';

/// Agent-free closure-observer probe; run against the selected source snapshot.
void main(List<String> args) {
  final result = <String, Object?>{
    'probe': 'self-start recovery closure-observer send',
    'sourceRevision': args.single,
    'runtime': Platform.version,
  };
  fakeAsync((async) {
    final fixture = Scripted();
    fixture.session.steering = true;
    fixture.conversation.start();
    async.flushMicrotasks();
    fixture.conversation.send('running');
    fixture.conversation.send('first');
    result['dispatched'] = fixture.conversation.steerQueued();
    async.flushMicrotasks();
    fixture.session.turns.first.answer();
    async.flushMicrotasks();
    String? own;
    fixture.conversation.listen((event) {
      if (event case Transcribed(action: SelfStartedAction(:final turnId))) {
        own = turnId;
        result['observerSent'] = fixture.conversation.send('observer');
      }
    });
    fixture.session.steered.single.answer(SteerOutcome.startedNewTurn);
    async.flushMicrotasks();
    final beforeQuiet = fixture.session.turns.map((turn) => turn.text).toList();
    fixture.session.chunk('self-started late work');
    final late = fixture.events
        .whereType<Transcribed>()
        .map((event) => event.action)
        .whereType<UpdateAction>()
        .last;
    result.addAll({
      'expectedBeforeQuiet': ['running'],
      'actualBeforeQuiet': beforeQuiet,
      'ownTurn': own,
      'lateWorkTurn': late.turnId,
      'orderPass': beforeQuiet.length == 1 && beforeQuiet.single == 'running',
      'workOwnerPass': late.turnId == own,
    });
    fixture.conversation.close();
    async.flushMicrotasks();
    result['pendingTimersAfterClose'] = async.nonPeriodicTimerCount;
    result['closes'] = fixture.session.closes;
  });
  stdout.writeln(const JsonEncoder.withIndent('  ').convert(result));
}
