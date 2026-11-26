import 'package:test/test.dart';

import '../../../tool/release/runner.dart';
import '../../../tool/release/x64_sdk.dart';

Matcher dies(String text) => throwsA(
  isA<ReleaseError>().having((e) => e.message, 'message', contains(text)),
);

const hash = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  group('the channel', () {
    test('of a plain release is stable', () {
      expect(channelOf('3.13.5'), 'stable');
    });

    test('of a prerelease is the one it names', () {
      expect(channelOf('3.14.0-123.1.beta'), 'beta');
      expect(channelOf('3.14.0-200.0.dev'), 'dev');
    });

    test('of any other version is refused', () {
      for (final version in ['3.14.0-edge', '3.14.0-1.0.main', 'main', '']) {
        expect(
          () => channelOf(version),
          dies('is of no channel the Dart archive publishes'),
          reason: version,
        );
      }
    });
  });

  group('the archive', () {
    test('serves the zip by channel and version', () {
      expect(
        sdkZipUrl('3.13.5'),
        'https://storage.googleapis.com/dart-archive/channels/stable/release/'
        '3.13.5/sdk/dartsdk-macos-x64-release.zip',
      );
      expect(
        sdkZipUrl('3.14.0-200.0.dev'),
        'https://storage.googleapis.com/dart-archive/channels/dev/release/'
        '3.14.0-200.0.dev/sdk/dartsdk-macos-x64-release.zip',
      );
    });

    test('serves its checksum beside it', () {
      expect(
        sdkChecksumUrl('3.14.0-123.1.beta'),
        'https://storage.googleapis.com/dart-archive/channels/beta/release/'
        '3.14.0-123.1.beta/sdk/dartsdk-macos-x64-release.zip.sha256sum',
      );
    });
  });

  group('the cache', () {
    test(r'is $XDG_CACHE_HOME when set', () {
      expect(userCache({'XDG_CACHE_HOME': '/xdg'}, '/home/x'), '/xdg');
    });

    test('is ~/Library/Caches otherwise', () {
      expect(userCache({}, '/home/x'), '/home/x/Library/Caches');
      expect(
        userCache({'XDG_CACHE_HOME': ''}, '/home/x'),
        '/home/x/Library/Caches',
      );
    });

    test('keeps each version in its own folder', () {
      final folder = sdkFolder('/cache', '3.13.5');
      expect(folder, '/cache/chord-release/dart-sdk/3.13.5/macos-x64');
      expect(sdkDart(folder), '$folder/bin/dart');
    });
  });

  group('the checksum', () {
    test("is read from sha256sum's binary and text lines", () {
      expect(checksumOf('$hash *dartsdk-macos-x64-release.zip\n'), hash);
      expect(checksumOf('$hash  dartsdk-macos-x64-release.zip'), hash);
    });

    test('is lowercased', () {
      expect(
        checksumOf('${hash.toUpperCase()} *dartsdk-macos-x64-release.zip'),
        hash,
      );
    });

    test('of another file is refused', () {
      expect(
        () => checksumOf('$hash *dartsdk-linux-x64-release.zip'),
        dies(
          'the SDK checksum is of dartsdk-linux-x64-release.zip, not '
          'dartsdk-macos-x64-release.zip',
        ),
      );
    });

    test('without a hash is refused', () {
      for (final sum in ['', '<html>Not Found</html>', 'abc *x.zip']) {
        expect(
          () => checksumOf(sum),
          dies('the SDK checksum says no sha256'),
          reason: sum,
        );
      }
    });
  });
}
