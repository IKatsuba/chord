// The benchmark's own failure path: a folded flood that cannot finish ends
// within its bound and leaves no heartbeat behind, so a failed run exits.
@Tags(['fake_agent'])
library;

import 'dart:async';

import 'package:chord/ui/app/state.dart';
import 'package:test/test.dart';

import '../../benchmark/acp_updates.dart';
import '../fixtures/fake_harness.dart';

void main() {
  test('a folded flood that never reaches its Esc fails within its bound, '
      'and its heartbeat is stopped', () async {
    final folding = Folding(AppState.starting);
    final watch = Stopwatch()..start();

    // `text` answers at once and never floods, so the cancel never comes.
    await expectLater(
      floodFolded(
        folding: folding,
        scenario: 'text',
        within: const Duration(seconds: 2),
      ),
      throwsA(isA<TimeoutException>()),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
    expect(folding.beating, isFalse);
    expect(folding.lateness, isNotEmpty);
  }, skip: fakeAgentSkip);
}
