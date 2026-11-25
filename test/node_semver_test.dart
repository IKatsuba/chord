import 'dart:convert';

import 'package:chord/node_semver.dart';
import 'package:test/test.dart';

void main() {
  group('the twelve ways pub_semver differs from semver', () {
    test('1: a leading zero in a numeric identifier is no version', () {
      expect(valid('1.0.0-next.01'), isNull);
      expect(valid('1.0.0-next.00'), isNull);
      expect(valid('1.0.0-next.0'), '1.0.0-next.0');
    });

    test('2: a leading zero in a component is no version', () {
      expect(valid('01.0.0'), isNull);
      expect(valid('1.00.0'), isNull);
      expect(valid('1.0.00'), isNull);
      expect(valid('0.0.0'), '0.0.0');
    });

    test('3: a component above 2^53 - 1 is no version', () {
      expect(valid('9007199254740991.0.0'), '9007199254740991.0.0');
      expect(valid('9007199254740992.0.0'), isNull);
      expect(valid('0.0.99999999999999999999'), isNull);
    });

    test('4: a numeric identifier from 2^53 - 1 up is a string', () {
      expect(prerelease('1.0.0-next.9007199254740990'), [
        'next',
        9007199254740990,
      ]);
      expect(prerelease('1.0.0-next.9007199254740991'), [
        'next',
        '9007199254740991',
      ]);
      expect(prerelease('1.0.0-next.9007199254740992'), [
        'next',
        '9007199254740992',
      ]);
    });

    test('5: a leading v or whitespace around a pre-release is normalised', () {
      expect(valid('v1.0.0-next.0'), '1.0.0-next.0');
      expect(valid(' 1.0.0-next.0'), '1.0.0-next.0');
      expect(valid('1.0.0-next.0\t'), '1.0.0-next.0');
      expect(prerelease('v1.0.0-next.0'), ['next', 0]);
    });

    test('6: a leading v or whitespace around a stable version is valid', () {
      expect(valid('v1.0.0'), '1.0.0');
      expect(valid(' 1.0.0'), '1.0.0');
      expect(valid('1.0.0\n'), '1.0.0');
      expect(valid('﻿1.0.0'), '1.0.0');
      expect(valid('vv1.0.0'), isNull);
      expect(valid('=1.0.0'), isNull);
      // JavaScript's trim keeps U+0085, which Dart's would drop.
      expect(valid('\u00851.0.0'), isNull);
    });

    test('7: build metadata is dropped from the normalised version', () {
      expect(valid('1.0.0-next.0+build'), '1.0.0-next.0');
      expect(valid('1.0.0+build'), '1.0.0');
      expect(prerelease('1.0.0+build'), isNull);
      expect(valid('1.0.0-next.0+'), isNull);
    });

    test('8: a version over 256 characters is no version', () {
      final atLimit = '1.0.0-${'a' * 250}';
      expect(atLimit, hasLength(256));
      expect(valid(atLimit), atLimit);
      expect(valid('1.0.0-${'a' * 251}'), isNull);
      // The limit counts the untrimmed text.
      expect(valid(' $atLimit'), isNull);
    });

    test('9: build metadata does not order', () {
      expect(compare('1.0.0', '1.0.0+build'), 0);
      expect(compare('1.0.0+a', '1.0.0+b'), 0);
      expect(compare('1.0.0+2', '1.0.0+10'), 0);
      expect(gt('1.2.3+build', '1.2.3'), isFalse);
    });

    test('10: npm takes vN and x for a range, and nothing else', () {
      for (final name in ['x', 'vx', 'vvx', '0', 'v0', 'v1', 'vvvv12']) {
        expect(isRangeName(name), isTrue, reason: name);
      }
      for (final name in [
        'v',
        'v01',
        'v1-beta',
        'x-1',
        'any',
        'next',
        'latest',
        'main',
        'rc2',
      ]) {
        expect(isRangeName(name), isFalse, reason: name);
      }
      expect(isRangeName('v9007199254740990'), isTrue);
      expect(isRangeName('v9007199254740991'), isFalse);
      expect(isRangeName('v99999999999999999'), isFalse);
    });

    test('11: a channel release counts up its number', () {
      expect(incChannel('1.0.0-next.3', 'next'), '1.0.0-next.4');
      expect(incChannel('2.3.4-rc2.0', 'rc2'), '2.3.4-rc2.1');
      expect(() => incChannel('1.0.0-next.3', 'beta'), throwsArgumentError);
      expect(() => incChannel('1.0.0', 'next'), throwsArgumentError);
      expect(() => incChannel('1.0.0-next.one', 'next'), throwsArgumentError);
    });

    test('12: a stable bump raises one part and zeroes the rest', () {
      expect(incStable('1.2.3', Part.major), '2.0.0');
      expect(incStable('1.2.3', Part.minor), '1.3.0');
      expect(incStable('1.2.3', Part.patch), '1.2.4');
      expect(incStable('v1.2.3+build', Part.patch), '1.2.4');
      expect(() => incStable('1.2.3-next.0', Part.patch), throwsArgumentError);
      expect(() => incStable('1.2', Part.patch), throwsArgumentError);
    });
  });

  group('ordering', () {
    test('pre-releases precede their release and order as semver', () {
      final ordered = [
        '1.0.0-1.0',
        '1.0.0-alpha',
        '1.0.0-alpha.1',
        '1.0.0-beta.2',
        '1.0.0-beta.11',
        '1.0.0-next.2',
        '1.0.0-next.10',
        '1.0.0-rc.1',
        '1.0.0',
        '1.0.1',
      ];
      for (var i = 0; i + 1 < ordered.length; i++) {
        expect(gt(ordered[i + 1], ordered[i]), isTrue, reason: ordered[i]);
        expect(compare(ordered[i], ordered[i + 1]), -1);
      }
    });

    test('known difference: identifiers above 2^53 - 1 order exactly', () {
      // semver compares them as JavaScript numbers, which round both to
      // 2^53 and answer 0; pub_semver orders the exact integers. Accepted
      // under Q358: no channel counter gets near it.
      expect(
        compare('1.0.0-next.9007199254740992', '1.0.0-next.9007199254740993'),
        -1,
      );
    });

    test('compare refuses what is no version', () {
      expect(() => compare('1.0', '1.0.0'), throwsArgumentError);
      expect(() => gt('1.0.0', 'latest'), throwsArgumentError);
    });

    test('no version has no pre-release', () {
      expect(prerelease('latest'), isNull);
      expect(prerelease('1.0.0'), isNull);
    });
  });

  group('tester: semver input boundaries', () {
    test('metadata fills the length limit without changing precedence', () {
      final version = '1.2.3+${'b' * 250}';
      expect(version, hasLength(256));
      expect(valid(version), '1.2.3');
      expect(compare(version, '1.2.3'), 0);
      expect(valid('${version}b'), isNull);
    });

    test('non-ASCII and terminal controls cannot become identifiers', () {
      for (final value in ['界', '😀', 'e\u0301', '\u001b[31m', '\u0000']) {
        for (final version in ['1.2.3-$value.0', '1.2.3+$value']) {
          expect(valid(version), isNull, reason: jsonEncode(version));
          expect(prerelease(version), isNull);
        }
      }
    });

    test('the final numeric counter increments to the string boundary', () {
      expect(
        incChannel('1.2.3-next.9007199254740990', 'next'),
        '1.2.3-next.9007199254740991',
      );
      expect(
        () => incChannel('1.2.3-next.9007199254740991', 'next'),
        throwsArgumentError,
      );
    });
  });
}
