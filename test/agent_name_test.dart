// The original's tests/agent_name_test.ts.
import 'package:chord/agent_name.dart';
import 'package:test/test.dart';

void main() {
  test('agent names reject the delimiter and C0/DEL, keeping other '
      'characters', () {
    for (final name in ['parser', 'bugfix 2', r'a\b', "a'b"]) {
      expect(agentNameProblem(name), isNull);
    }
    expect(agentNameProblem('a"b'), 'must not contain the character "');
  });

  test('each C0 and DEL control is named in the refusal', () {
    for (final code in [for (var at = 0; at < 32; at++) at, 127]) {
      final hex = code.toRadixString(16).toUpperCase().padLeft(4, '0');
      expect(
        agentNameProblem('a${String.fromCharCode(code)}b'),
        'must not contain the control character U+$hex',
      );
    }
    expect(agentNameProblem('a\u0085b'), isNull);
  });
}
