import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../../../tool/release/runner.dart';
import '../../../tool/release/x64_sdk.dart';

void main() {
  group('tester: production SDK fetcher on loopback', () {
    late ServerSocket server;
    late StreamSubscription<Socket> connections;
    late List<Socket> sockets;
    late List<int> response;
    late List<String> requests;

    setUp(() async {
      response = [];
      requests = [];
      sockets = [];
      server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
      connections = server.listen((socket) {
        sockets.add(socket);
        var answered = false;
        socket.listen((bytes) async {
          if (answered) return;
          answered = true;
          requests.add(utf8.decode(bytes));
          socket.add(response);
          await socket.flush();
          await socket.close();
        });
      });
    });
    tearDown(() async {
      for (final socket in sockets) {
        socket.destroy();
      }
      await connections.cancel();
      await server.close();
    });

    Uri url() => Uri.http('127.0.0.1:${server.port}', '/sdk.zip');
    void reply(int status, List<int> body, {int? length}) {
      response = [
        ...ascii.encode(
          'HTTP/1.1 $status Recorded\r\n'
          'Content-Length: ${length ?? body.length}\r\n'
          'Connection: close\r\n\r\n',
        ),
        ...body,
      ];
    }

    test('a successful response returns exact bytes for writing', () async {
      final body = [0, 255, 128, 13, 10, ...utf8.encode('SDK 工具')];
      reply(200, body);
      final temp = Directory.systemTemp.createTempSync('sdk_fetch_tester');
      addTearDown(() => temp.deleteSync(recursive: true));
      final file = File('${temp.path}/sdk.zip');
      file.writeAsBytesSync(
        await httpFetch(url()).timeout(const Duration(seconds: 5)),
      );
      expect(file.readAsBytesSync(), body);
      expect(requests.single, startsWith('GET /sdk.zip HTTP/1.1\r\n'));
    });

    test('a non-200 response is refused with its status and URL', () async {
      reply(503, utf8.encode('unavailable'));
      final endpoint = url();
      await expectLater(
        httpFetch(endpoint).timeout(const Duration(seconds: 5)),
        throwsA(
          isA<ReleaseError>().having(
            (e) => e.message,
            'message',
            '$endpoint answered 503',
          ),
        ),
      );
      expect(requests, hasLength(1));
    });

    test(
      'a truncated response fails instead of returning partial bytes',
      () async {
        reply(200, [1, 2, 3], length: 100);
        await expectLater(
          httpFetch(url()).timeout(const Duration(seconds: 5)),
          throwsA(
            isA<Exception>().having(
              (e) => e.toString(),
              'message',
              contains('Connection closed'),
            ),
          ),
        );
        expect(requests, hasLength(1));
      },
    );
  });
}
