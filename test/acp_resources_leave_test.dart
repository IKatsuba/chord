// chord acp's way out closes the providers' limits readers as its own
// step, `resource readers`, which fails with their cleanup warnings, as
// the original's acp_agent.ts steps do.
import 'dart:async';

import 'package:chord/platform/resources.dart' show Resources;
import 'package:chord/session/resource_access.dart' show ReadLimits;
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'acp_rig.dart';

/// Readers whose close answers [warnings], counting each close.
final class _Readers implements Resources {
  _Readers(this.warnings);

  final List<String> warnings;
  var closes = 0;

  @override
  ReadLimits get read =>
      (agents, place, cancelled) =>
          Future.error(StateError('not read in these tests'));

  @override
  Future<List<String>> close() async {
    closes++;
    return warnings;
  }
}

// A held cleanup proves ACP waits for the reader step rather than its read reply.
final class _TesterHeldReaders implements Resources {
  final gate = Completer<List<String>>();
  var closes = 0;
  @override
  ReadLimits get read =>
      (_, _, _) => Future.error(StateError('not read'));
  @override
  Future<List<String>> close() {
    closes++;
    return gate.future;
  }
}

void main() {
  group('CTUI-37 tester: ACP reader leave ordering', () {
    for (final failed in [false, true]) {
      test('EOF waits for held reader cleanup, failed=$failed', () {
        fakeAsync((async) {
          final readers = _TesterHeldReaders();
          final rig = Rig(async, resources: readers);
          rig
            ..initialize()
            ..newSession();
          rig.input.close();
          rig.settle();
          expect(readers.closes, 1);
          expect(rig.exits, isEmpty);
          async.elapse(const Duration(seconds: 1));
          rig.settle();
          expect(rig.exits, isEmpty);
          if (failed) {
            readers.gate.completeError(StateError('scripted cleanup failure'));
          } else {
            readers.gate.complete(['scripted cleanup warning']);
          }
          rig.settle();
          expect(rig.exits, hasLength(1));
          expect(readers.closes, 1);
          expect(
            rig.said.where((line) => line.contains('resource readers')),
            hasLength(1),
          );
          expect(
            rig.said.join('\n'),
            contains(
              failed ? 'scripted cleanup failure' : 'scripted cleanup warning',
            ),
          );
          async.elapse(const Duration(seconds: 20));
          rig.settle();
          expect(rig.exits, hasLength(1));
          expect(readers.closes, 1);
        });
      });
    }
  });

  test('the way out closes the readers once, and names their cleanup '
      'failures on stderr', () {
    fakeAsync((async) {
      final readers = _Readers(['codex: group 41 outlived the ladder', 'x']);
      final rig = Rig(async, resources: readers);
      rig
        ..initialize()
        ..newSession();
      rig.eof();
      expect(readers.closes, 1);
      expect(
        rig.said,
        contains(
          'chord: resource readers: codex: group 41 outlived the ladder; x',
        ),
      );
      expect(rig.exits, hasLength(1));
    });
  });

  test('readers that close cleanly say nothing', () {
    fakeAsync((async) {
      final readers = _Readers(const []);
      final rig = Rig(async, resources: readers);
      rig
        ..initialize()
        ..newSession();
      rig.eof();
      expect(readers.closes, 1);
      expect(
        rig.said.where((line) => line.contains('resource readers')),
        isEmpty,
      );
    });
  });
}
