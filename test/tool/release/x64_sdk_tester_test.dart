import 'package:test/test.dart';

import '../../../tool/release/runner.dart';
import '../../../tool/release/x64_sdk.dart';

void main() {
  group('tester: x64 SDK archive inputs', () {
    const hash =
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

    test('beta and dev URLs retain the full host version', () {
      for (final channel in ['beta', 'dev']) {
        final version = '3.14.0-123.4.$channel';
        final zip = Uri.parse(sdkZipUrl(version));
        expect(zip.scheme, 'https');
        expect(zip.host, 'storage.googleapis.com');
        expect(zip.pathSegments, [
          'dart-archive',
          'channels',
          channel,
          'release',
          version,
          'sdk',
          sdkZipName,
        ]);
        expect(sdkChecksumUrl(version), '${zip.toString()}.sha256sum');
      }
    });

    test('invalid versions cannot become archive paths', () {
      for (final version in [
        '../3.13.5',
        '3.13.5/../../other',
        '3.13.5?alt=media',
        '3.13.5+local',
        '3.14.0-123.4.beta.extra',
      ]) {
        expect(
          () => sdkZipUrl(version),
          throwsA(isA<ReleaseError>()),
          reason: version,
        );
      }
    });

    test('XDG cache paths with spaces and Unicode remain intact', () {
      const cache = '/cache/release files/工具';
      final folder = sdkFolder(
        userCache({'XDG_CACHE_HOME': cache}, '/fallback'),
        '3.14.0-123.4.beta',
      );
      expect(
        sdkDart(folder),
        '$cache/chord-release/dart-sdk/3.14.0-123.4.beta/macos-x64/bin/dart',
      );
    });

    test('unset and empty XDG cache use the supplied home', () {
      for (final env in [
        <String, String>{},
        {'XDG_CACHE_HOME': ''},
      ]) {
        expect(userCache(env, '/fixture'), '/fixture/Library/Caches');
      }
    });

    test('malformed checksum records are refused', () {
      for (final sum in [
        '${hash.substring(1)} *$sdkZipName',
        '${hash}0 *$sdkZipName',
        '${'g' * 64} *$sdkZipName',
        '$hash\t*$sdkZipName',
        '$hash *$sdkZipName\n$hash *$sdkZipName',
        '$hash *$sdkZipName trailing',
        '$hash *../$sdkZipName',
      ]) {
        expect(
          () => checksumOf(sum),
          throwsA(isA<ReleaseError>()),
          reason: sum,
        );
      }
    });

    test('a checksum with CRLF and surrounding whitespace is read', () {
      expect(checksumOf('  $hash *$sdkZipName\r\n'), hash);
    });
  });
}
