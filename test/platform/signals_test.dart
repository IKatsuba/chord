import 'dart:async';
import 'dart:io';

import 'package:chord/platform/signals.dart';
import 'package:test/test.dart';

void main() {
  group('dieBySignal', () {
    late Map<ProcessSignal, StreamController<ProcessSignal>> sent;
    late List<String> said;

    setUp(() {
      said = [];
      sent = {
        for (final signal in leaveSignals)
          signal: StreamController<ProcessSignal>.broadcast(
            onCancel: () => said.add('off $signal'),
          ),
      };
    });

    test('watches SIGTERM, SIGINT and SIGHUP', () {
      expect(leaveSignals, [
        ProcessSignal.sigterm,
        ProcessSignal.sigint,
        ProcessSignal.sighup,
      ]);
    });

    test('leaves, takes the handlers off, then raises the signal', () async {
      final leaving = Completer<void>();
      dieBySignal(
        () {
          said.add('leave');
          return leaving.future;
        },
        watch: (signal) => sent[signal]!.stream,
        raise: (signal) => said.add('raise $signal'),
      );
      sent[ProcessSignal.sighup]!.add(ProcessSignal.sighup);
      await Future<void>.delayed(Duration.zero);
      expect(said, ['leave']);
      // A second signal while leaving is held, not let through.
      sent[ProcessSignal.sigterm]!.add(ProcessSignal.sigterm);
      await Future<void>.delayed(Duration.zero);
      expect(said, ['leave']);
      leaving.complete();
      await Future<void>.delayed(Duration.zero);
      expect(said, [
        'leave',
        'off SIGTERM',
        'off SIGINT',
        'off SIGHUP',
        'raise SIGHUP',
      ]);
    });

    test('a leave that fails still raises the signal', () async {
      dieBySignal(
        () async {
          said.add('leave');
          throw StateError('the terminal is gone');
        },
        watch: (signal) => sent[signal]!.stream,
        raise: (signal) => said.add('raise $signal'),
      );
      sent[ProcessSignal.sighup]!.add(ProcessSignal.sighup);
      await Future<void>.delayed(Duration.zero);
      expect(said, [
        'leave',
        'off SIGTERM',
        'off SIGINT',
        'off SIGHUP',
        'raise SIGHUP',
      ]);
    });

    test('the function it returns takes the handlers off', () async {
      final off = dieBySignal(
        () async => said.add('leave'),
        watch: (signal) => sent[signal]!.stream,
        raise: (signal) => said.add('raise'),
      );
      off();
      sent[ProcessSignal.sigterm]!.add(ProcessSignal.sigterm);
      await Future<void>.delayed(Duration.zero);
      expect(said, ['off SIGTERM', 'off SIGINT', 'off SIGHUP']);
    });
  });
}
