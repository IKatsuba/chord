import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import '../../tool/build.dart';
import '../../tool/serving.dart';

Pinned _pin(String url, List<int> bytes) => Pinned(
  name: 'asset.tgz',
  url: url,
  algorithm: 'sha512',
  digest: base64.encode(sha512.convert(bytes).bytes),
);

Directory _cache() {
  final dir = Directory.systemTemp.createTempSync('site-asset-tester-');
  addTearDown(() => dir.deleteSync(recursive: true));
  return dir;
}

Future<String> _origin(void Function(HttpRequest request) answer) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  addTearDown(() => server.close(force: true));
  server.listen(answer);
  return 'http://127.0.0.1:${server.port}/asset';
}

void main() {
  group('tester: pinned asset cache ownership', () {
    test('a verified cached asset needs no network', () async {
      final bytes = utf8.encode('verified asset');
      final cache = _cache();
      File('${cache.path}/asset.tgz').writeAsBytesSync(bytes);
      expect(
        await fetchPinned(_pin('https://example.invalid/asset', bytes), cache),
        bytes,
      );
      expect(cache.listSync().map((f) => f.uri.pathSegments.last), [
        'asset.tgz',
      ]);
    });

    test(
      'a corrupt cache is replaced only by verified bytes and reused',
      () async {
        final bytes = utf8.encode('verified replacement');
        final cache = _cache();
        final file = File('${cache.path}/asset.tgz')
          ..writeAsStringSync('corrupt');
        var requests = 0;
        final url = await _origin((request) {
          requests++;
          request.response.add(bytes);
          request.response.close();
        });
        final pin = _pin(url, bytes);
        expect(await fetchPinned(pin, cache), bytes);
        expect(file.readAsBytesSync(), bytes);
        expect(File('${file.path}.partial').existsSync(), isFalse);
        expect(await fetchPinned(pin, cache), bytes);
        expect(requests, 1);
      },
    );

    test(
      'a digest failure leaves no cached payload and a later retry succeeds',
      () async {
        final bytes = utf8.encode('verified retry');
        final cache = _cache();
        var requests = 0;
        final url = await _origin((request) {
          request.response.add(
            ++requests == 1 ? utf8.encode('wrong bytes') : bytes,
          );
          request.response.close();
        });
        final pin = _pin(url, bytes);
        await expectLater(fetchPinned(pin, cache), throwsStateError);
        expect(cache.listSync(), isEmpty);
        expect(await fetchPinned(pin, cache), bytes);
        expect(requests, 2);
      },
    );

    test(
      'an HTTP failure leaves neither a cached asset nor a partial file',
      () async {
        final cache = _cache();
        final url = await _origin((request) {
          request.response.statusCode = HttpStatus.serviceUnavailable;
          request.response.write('unavailable');
          request.response.close();
        });
        await expectLater(
          fetchPinned(_pin(url, utf8.encode('expected')), cache),
          throwsA(
            isA<StateError>().having(
              (e) => e.message,
              'message',
              contains('503'),
            ),
          ),
        );
        expect(cache.listSync(), isEmpty);
      },
    );
  });

  group('tester: base and encoded asset routes', () {
    test(
      'nested bases keep files, encoded unknown paths and traversal distinct',
      () {
        const files = {'index.html', 'main.wasm'};
        for (final base in ['/', '/chord/', '/docs/chord/']) {
          expect(
            serve('${base}main%2Ewasm', base, files),
            const ServedFile('main.wasm'),
          );
          expect(
            serve('${base}missing%25', base, files),
            const ServedFile('index.html'),
          );
          expect(
            serve('${base}missing%2Ewasm', base, files),
            const NotServed(),
          );
          expect(
            serve('$base%2e%2e%2fmain.wasm', base, files),
            const NotServed(),
          );
        }
        expect(
          serve('/chorded/main.wasm', '/chord/', files),
          const NotServed(),
        );
      },
    );

    test(
      'the base is escaped as an HTML attribute and a missing placeholder fails',
      () {
        expect(
          pageFor('<base href="/">', '/a&"b/'),
          '<base href="/a&amp;&quot;b/">',
        );
        expect(() => pageFor('<html></html>', '/chord/'), throwsStateError);
      },
    );
  });
}
