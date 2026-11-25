import 'dart:convert';

import 'package:chord/channel.dart';
import 'package:test/test.dart';

/// bun's `%p`: a string quoted as pretty-format quotes it.
String p(String value) => jsonEncode(value);

Matcher throwsVersionError(String text) => throwsA(
  isA<VersionError>().having((e) => e.message, 'message', contains(text)),
);

void main() {
  group('channelOf', () {
    for (final version in ['0.67.0', '1.0.0', '1.0.0+build']) {
      test('$version is stable', () {
        expect(channelOf(version), isNull);
      });
    }

    for (final version in [
      'latest',
      '',
      '1.0',
      '1.0.0-next.01',
      '1.0.0-next.',
      '1.0.0-',
    ]) {
      test('${p(version)} is no version, and is refused rather than taken for '
          'stable', () {
        expect(
          () => channelOf(version),
          throwsVersionError('$version is no version'),
        );
      });
    }

    for (final (version, channel) in [
      ('1.0.0-next.0', 'next'),
      ('1.0.0-next.12', 'next'),
      ('2.3.4-beta.0', 'beta'),
      ('1.0.0-release-candidate.1', 'release-candidate'),
    ]) {
      test('$version is on $channel', () {
        expect(channelOf(version), channel);
      });
    }

    for (final (name, version) in [
      ('no number', '1.0.0-next'),
      ('a word for a number', '1.0.0-next.one'),
      ('too many identifiers', '1.0.0-next.0.1'),
      ('a number for a label', '1.0.0-1.0'),
      ('build metadata', '1.0.0-next.0+build'),
      ('a leading v', 'v1.0.0-next.0'),
      ('the label latest', '1.0.0-latest.0'),
      ('the label main', '1.0.0-main.0'),
      ('a label npm takes for a range', '1.0.0-x.0'),
      ('a label with capitals', '1.0.0-Next.0'),
    ]) {
      test('refuses $name', () {
        expect(() => channelOf(version), throwsA(isA<VersionError>()));
      });
    }

    test('says how a pre-release is written', () {
      expect(
        () => channelOf('1.0.0-next'),
        throwsA(
          isA<VersionError>().having(
            (e) => e.toString(),
            'text',
            '1.0.0-next is not a release of a channel: a pre-release is '
                'written <x.y.z>-<channel>.<n>',
          ),
        ),
      );
    });

    test('a stable version with a leading v is stable, as semver '
        'normalises it', () {
      expect(channelOf('v1.0.0'), isNull);
    });
  });

  group('checkChannel', () {
    for (final name in ['next', 'beta', 'rc', 'release-candidate', 'rc2']) {
      test('takes $name', () {
        expect(() => checkChannel(name), returnsNormally);
      });
    }

    for (final (name, why) in [
      ('', 'lower-case letter'),
      ('Next', 'lower-case letter'),
      ('1next', 'lower-case letter'),
      ('next.1', 'lower-case letter'),
      ('-next', 'lower-case letter'),
      ('next/1', 'lower-case letter'),
      ('x', 'version range'),
      ('v1', 'version range'),
      ('latest', "npm's latest"),
      ('main', 'stable branch'),
    ]) {
      test('refuses ${p(name)}', () {
        expect(() => checkChannel(name), throwsVersionError(why));
      });
    }
  });

  group('tester: CHD-577 channel boundaries', () {
    for (final channel in [
      ' next',
      'next ',
      'next\n',
      'next_1',
      'next@1',
      'next..1',
    ]) {
      test(
        'refuses a channel with whitespace or tag punctuation: ${p(channel)}',
        () {
          expect(() => checkChannel(channel), throwsA(isA<VersionError>()));
        },
      );
    }

    for (final version in [
      '1.0.0-next.-1',
      '1.0.0-next.1a',
      '1.0.0-next.0.extra',
    ]) {
      test('refuses a malformed channel counter: $version', () {
        expect(() => channelOf(version), throwsA(isA<VersionError>()));
      });
    }

    test('a digit or hyphen in the channel stays part of its tag', () {
      expect(channelOf('2.0.0-rc2.10'), 'rc2');
      expect(channelOf('2.0.0-release-candidate.10'), 'release-candidate');
    });
  });

  group('tester: release channel boundaries', () {
    test('only exactly represented numeric counters identify a channel', () {
      expect(channelOf('1.2.3-next.9007199254740990'), 'next');
      expect(
        () => channelOf('1.2.3-next.9007199254740991'),
        throwsA(isA<VersionError>()),
      );
    });

    test('normalising a pre-release cannot silently choose its channel', () {
      for (final version in [
        ' 1.2.3-next.0',
        '1.2.3-next.0\t',
        '1.2.3-next.0\n',
        '\uFEFF1.2.3-next.0',
      ]) {
        expect(() => channelOf(version), throwsA(isA<VersionError>()));
      }
    });

    test('Unicode and escape sequences cannot become npm tags', () {
      for (final name in ['界', '😀', 'e\u0301', 'next\u001b[31m']) {
        expect(() => checkChannel(name), throwsA(isA<VersionError>()));
      }
    });
  });
}
