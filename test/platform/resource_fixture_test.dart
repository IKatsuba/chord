import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/platform/resource_fixture.dart';
import 'package:chord/session/budgets.dart';
import 'package:test/test.dart';

void main() {
  group('tester fixture boundaries', () {
    test('all named scenarios survive and near matches fall back', () {
      for (final name in ['normal', 'partial', 'timeout', 'unavailable']) {
        expect(resourceFixtureCase(name), name);
      }
      for (final value in ['TRUE', ' true', 'true ', '1', 'fixture']) {
        expect(resourceSourceMode(value), ResourceSource.official);
      }
      for (final value in ['', 'NORMAL', 'timeout ', ' partial', 'official']) {
        expect(resourceFixtureCase(value), 'normal');
      }
    });
  });

  test('fixture selection is exact and never triggered by unrelated '
      'values', () {
    expect(resourceSourceMode('true'), ResourceSource.fixture);
    expect(resourceSourceMode(null), ResourceSource.official);
    expect(resourceSourceMode('false'), ResourceSource.official);
    expect(resourceSourceMode(''), ResourceSource.official);
    expect(resourceFixtureCase('partial'), 'partial');
    expect(resourceFixtureCase('unknown'), 'normal');
    expect(resourceFixtureCase(null), 'normal');
  });

  test('a run of the tests is built without the capture flag', () {
    expect(resourceSourceMode(resourceFixtureFlag), ResourceSource.official);
  });

  test('every capture case is windows, unavailable, or a read that waits '
      'until cancelled', () async {
    for (final scenario in ['normal', 'partial']) {
      expect(
        await fixtureLimits('codex', scenario, CancellationToken()),
        isA<ProviderWindows>(),
      );
    }
    final partial =
        await fixtureLimits('codex', 'partial', CancellationToken())
            as ProviderWindows;
    expect(
      [for (final w in partial.windows) w.name],
      ['five_hour', 'seven_day'],
    );
    expect(
      await fixtureLimits('codex', 'unavailable', CancellationToken()),
      isA<ProviderUnavailable>().having(
        (p) => p.unavailable,
        'unavailable',
        'Scripted unavailable provider.',
      ),
    );
    final cancelled = CancellationToken();
    final waiting = fixtureLimits('codex', 'timeout', cancelled);
    cancelled.cancel();
    await expectLater(waiting, throwsA(isA<CancelledException>()));
  });
}
