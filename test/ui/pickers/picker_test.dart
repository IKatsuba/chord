import 'package:chord/agents.dart';
import 'package:chord/ui/pickers/picker.dart';
import 'package:chord/ui/pickers/mcp.dart';
import 'package:test/test.dart';

void main() {
  test('agent labels preserve catalog order, default and dim notes', () {
    ListedAgent agent(String name, String title, [bool? found]) => ListedAgent(
      name: name,
      title: title,
      start: 'unused',
      from: AgentRunner.cli,
      found: found,
    );
    final choices = agentChoices([
      agent('codex', 'Codex'),
      agent('claude', 'claude'),
      agent('missing', 'Missing', false),
    ], 'claude');
    expect(choices.map((c) => c.value), ['codex', 'claude', 'missing']);
    expect(choices.map((c) => c.current), [false, true, false]);
    expect(choices.map((c) => c.label), [
      'codex\x1b[2m · Codex\x1b[22m',
      'claude',
      'missing\x1b[2m · Missing · not on PATH\x1b[22m',
    ]);
  });
  test(
    'cutPath leaves fitting paths and drops only partial leading component',
    () {
      expect(cutPath('~/src/app', 20), '~/src/app');
      expect(
        cutPath('~/work/acme/services/billing/acme-api', 28),
        '…/services/billing/acme-api',
      );
      expect(cutPath('abcdefgh', 4), '…fgh');
      expect(cutPath('abcdefgh', 0), '…');
      expect(cutPath('~/界/项目', 7), '…/项目');
    },
  );
}
