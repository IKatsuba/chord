import 'package:chord/acp/connection.dart';
import 'package:chord/session/starting.dart';
import 'package:test/test.dart';

/// A mode ask against an agent that lists [ids] and answers with [answer].
({StartingAsk ask, int Function() asked}) _mode(
  List<String>? ids, {
  Future<void> Function()? answer,
  bool listedOnly = true,
  StartingValue value = const StartingValue(
    'plan',
    from: 'set by --permission-mode',
  ),
  String? Function()? current,
}) {
  var asked = 0;
  return (
    ask: StartingAsk(
      value: value,
      what: 'in plan mode',
      kind: 'modes',
      listedOnly: listedOnly,
      offered: () async => ids,
      current: current,
      ask: () {
        asked++;
        return answer?.call() ?? Future.value();
      },
    ),
    asked: () => asked,
  );
}

Future<void> _refuse() =>
    Future.error(RpcException(-32602, 'Invalid params: not now'));

void main() {
  test("a refusal's details, where an agent puts its reason, come before "
      'its message', () {
    expect(
      agentMessageOf(
        RpcException(
          -32603,
          'Internal error',
          data: {'details': ' Not in plan. '},
        ),
      ),
      'Not in plan.',
    );
    expect(agentMessageOf(RpcException(-32603, 'Busy')), 'Busy');
  });

  test('a starting value the agent lists and takes says nothing', () async {
    final mode = _mode(['default', 'plan']);
    expect(await askStarting(mode.ask), isNull);
    expect(mode.asked(), 1);
  });

  test('a starting value the agent does not list is not asked for', () async {
    final mode = _mode(['default', 'acceptEdits']);
    expect(
      await askStarting(mode.ask),
      'start in plan mode, set by --permission-mode: the agent offers '
      'default, acceptEdits',
    );
    expect(mode.asked(), 0);
  });

  test(
    "a listed value the agent refuses is said in the agent's words",
    () async {
      expect(
        await askStarting(_mode(['plan'], answer: _refuse).ask),
        'start in plan mode, set by --permission-mode: Invalid params: not now',
      );
    },
  );

  test('a mode from an agent that lists none is not asked for, and says it '
      'lists none', () async {
    for (final ids in [null, <String>[]]) {
      final mode = _mode(ids);
      expect(
        await askStarting(mode.ask),
        'start in plan mode, set by --permission-mode: the agent offers no '
        'modes',
      );
      expect(mode.asked(), 0);
    }
  });

  test('a model from an agent that lists none is asked all the same, its '
      "refusal in the agent's words", () async {
    for (final ids in [null, <String>[]]) {
      final model = _mode(ids, listedOnly: false);
      expect(await askStarting(model.ask), isNull);
      expect(model.asked(), 1);
      expect(
        await askStarting(_mode(ids, listedOnly: false, answer: _refuse).ask),
        'start in plan mode, set by --permission-mode: Invalid params: not now',
      );
    }
  });

  test('a value set nowhere in particular says no where', () async {
    expect(
      await askStarting(
        _mode(['default'], value: const StartingValue('plan')).ask,
      ),
      'start in plan mode: the agent offers default',
    );
  });

  test('a value the session is on already is not asked for; a required one '
      'the agent leaves is refused', () async {
    final on = _mode(['plan'], current: () => 'plan');
    expect(await askStarting(on.ask), isNull);
    expect(on.asked(), 0);
    final left = _mode(
      ['default', 'plan'],
      value: const StartingValue('plan', required: true),
      current: () => 'default',
    );
    expect(
      await askStarting(left.ask),
      'start in plan mode: the agent is in default',
    );
    expect(left.asked(), 1);
    final optional = _mode(['default', 'plan'], current: () => 'default');
    expect(await askStarting(optional.ask), isNull);
  });
}
