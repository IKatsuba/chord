// A turn's figures on the original's fake agent: its own cost, and chord's
// estimate where it reports tokens only.
@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:io';

import 'package:chord/session/conversation.dart';
import 'package:chord/session/prices.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/session/turn_costs.dart';
import 'package:test/test.dart';

import 'session_fake.dart';

bool _alive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

/// The figures of one turn on the fake started with [flags].
Future<TurnFigures> _turn(List<String> flags) async {
  final dir = Directory.systemTemp.createTempSync('chord-spend-');
  final pids = <int>[];
  final done = Completer<TurnFigures>();
  final conversation = Conversation(
    ({required onTraffic, required cancellationToken}) => openSession(
      agent: 'fake',
      command: fakeAgentCommand(null, flags),
      cwd: dir.path,
      open: fakeSessionOpener(pids.add),
      onTraffic: onTraffic,
      cancellationToken: cancellationToken,
    ),
  );
  conversation.listen((event) {
    if (event is Connected) conversation.send('hello');
    if (event case Transcribed(action: UsageAction(:final figures))) {
      if (!done.isCompleted) done.complete(figures);
    }
  });
  addTearDown(() async {
    await conversation.close();
    expect(pids.where(_alive), isEmpty, reason: 'the agent is running');
    dir.deleteSync(recursive: true);
  });
  conversation.start();
  return done.future.timeout(const Duration(seconds: 20));
}

void main() {
  final skip = fakeAgentSkip;

  test("an agent's own cost is the turn's, with its tokens", () async {
    final figures = await _turn(const []);
    expect(figures.usage['totalTokens'], greaterThan(0));
    expect(figures.cost.cost?.currency, 'USD');
    expect(figures.cost.cost!.amount, greaterThan(0));
    expect(figures.cost.estimated, isFalse);
  }, skip: skip);

  test("tokens only: chord's estimate from the price data, marked", () async {
    final figures = await _turn(const ['--tokens-only']);
    expect(figures.model, 'gpt-5.3-codex');
    expect(figures.cost.estimated, isTrue);
    expect(
      figures.cost.cost!.amount,
      closeTo(turnCost('gpt-5.3-codex', figures.usage)!, 1e-12),
    );
  }, skip: skip);
}
