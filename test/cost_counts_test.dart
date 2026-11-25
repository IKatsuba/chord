import 'package:chord/agents.dart';
import 'package:chord/cost_counts.dart';
import 'package:test/test.dart';

void main() {
  group('tester: CTUI-29 original counting tables', () {
    test('every counted agent is catalogued under that exact name', () {
      for (final name in {...costCounts.keys, ...usageCounts.keys}) {
        expect(findAgent(name), isNotNull, reason: name);
      }
    });

    test('opening and session costs follow the original agent table', () {
      expect(costCountOf('claude'), CostCount.opening);
      for (final name in [
        'cursor-cloud',
        'dimcode',
        'dirac',
        'kilo',
        'opencode',
      ]) {
        expect(costCountOf(name), CostCount.session, reason: name);
      }
      for (final name in ['codex', 'toString', '', 'Claude']) {
        expect(costCountOf(name), isNull, reason: name);
      }
    });

    test('only dirac reports answer usage as a running session total', () {
      expect(usageCountOf('dirac'), UsageCount.session);
      for (final name in ['claude', 'dimcode', 'toString', '', 'Dirac']) {
        expect(usageCountOf(name), isNull, reason: name);
      }
    });
  });
}
