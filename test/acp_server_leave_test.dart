// chord acp's way out closes chord's MCP server as its own step, `chord's
// server`, beside the sessions' and before the readers', as the original's
// acp_agent.ts steps do.
import 'dart:async';

import 'package:chord/server/server.dart' show Admitted, ChordServer;
import 'package:chord/server/tools.dart' show Caller;
import 'package:fake_async/fake_async.dart';
import 'package:chord/platform/resources.dart' show Resources;
import 'package:chord/session/resource_access.dart' show ReadLimits;
import 'package:chord/session/leaving.dart';
import 'package:test/test.dart';

import 'acp_rig.dart';

/// A server whose close waits on [gate], counting each close.
final class _Server implements ChordServer {
  final gate = Completer<void>();
  var closes = 0;

  @override
  String get url => 'http://127.0.0.1:9/mcp';

  @override
  Admitted admit(Caller caller) => (
    token: 'token',
    server: {
      'type': 'http',
      'name': 'chord',
      'url': url,
      'headers': <Object?>[],
    },
  );

  @override
  void revoke(String token) {}

  @override
  Future<void> close() {
    closes++;
    return gate.future;
  }
}

// Holds the adjacent cleanup independently of the server's close.
final class _TesterReaders implements Resources {
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
  group('tester: CTUI-98 server leave boundaries', () {
    test('server and readers close concurrently and repeated leave joins', () {
      fakeAsync((async) {
        final server = _Server();
        final readers = _TesterReaders();
        final rig = Rig(async, server: server, resources: readers);
        rig
          ..initialize()
          ..newSession()
          ..newSession();
        rig.host.leave(const LeaveEof());
        rig.settle();
        rig.host.leave(const LeaveCrash());
        rig.settle();
        expect(server.closes, 1);
        expect(readers.closes, 1);
        expect(rig.exits, isEmpty);
        readers.gate.complete([]);
        rig.settle();
        expect(rig.exits, isEmpty);
        server.gate.complete();
        rig.settle();
        async.elapse(const Duration(seconds: 1));
        rig.settle();
        expect(rig.exits, hasLength(1));
        expect(rig.agents.every((agent) => agent.exited), isTrue);
        expect(server.closes, 1);
        expect(readers.closes, 1);
      });
    });

    test(
      'deadline names a hung server and late completion cannot exit twice',
      () {
        fakeAsync((async) {
          final server = _Server();
          final rig = Rig(async, server: server);
          rig.initialize();
          rig.input.close();
          rig.settle();
          expect(server.closes, 1);
          async.elapse(const Duration(seconds: 16));
          rig.settle();
          expect(rig.exits, hasLength(1));
          expect(
            rig.said,
            contains("chord: not settled at the deadline: chord's server"),
          );
          server.gate.complete();
          rig.settle();
          async.elapse(const Duration(seconds: 20));
          expect(rig.exits, hasLength(1));
          expect(server.closes, 1);
        });
      },
    );

    test('server failure does not finish while readers are still closing', () {
      fakeAsync((async) {
        final server = _Server();
        final readers = _TesterReaders();
        final rig = Rig(async, server: server, resources: readers);
        rig.initialize();
        rig.input.close();
        rig.settle();
        server.gate.completeError(StateError('tester server failure'));
        rig.settle();
        expect(
          rig.said,
          contains("chord: chord's server: tester server failure"),
        );
        expect(rig.exits, isEmpty);
        readers.gate.complete([]);
        rig.settle();
        expect(rig.exits, hasLength(1));
      });
    });
  });

  test("the way out closes chord's server once and waits for it", () {
    fakeAsync((async) {
      final server = _Server();
      final rig = Rig(async, server: server);
      rig
        ..initialize()
        ..newSession();
      rig.input.close();
      rig.settle();
      expect(server.closes, 1);
      // The sessions' own steps are done by then; the server's holds the exit.
      async.elapse(const Duration(seconds: 1));
      rig.settle();
      expect(rig.exits, isEmpty);
      server.gate.complete();
      rig.settle();
      expect(rig.exits, hasLength(1));
      expect(server.closes, 1);
      expect(
        rig.said.where((line) => line.contains("chord's server")),
        isEmpty,
      );
    });
  });

  test('a server that fails to close is named on stderr', () {
    fakeAsync((async) {
      final server = _Server();
      final rig = Rig(async, server: server);
      rig
        ..initialize()
        ..newSession();
      rig.input.close();
      rig.settle();
      async.elapse(const Duration(seconds: 1));
      rig.settle();
      server.gate.completeError(StateError('scripted close failure'));
      rig.settle();
      expect(rig.exits, hasLength(1));
      expect(
        rig.said,
        contains("chord: chord's server: scripted close failure"),
      );
    });
  });
}
