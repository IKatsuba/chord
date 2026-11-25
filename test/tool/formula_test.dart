import 'dart:io';

import 'package:chord/channel.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/formula.dart';
import '../../tool/release/archive.dart';
import '../../tool/release/runner.dart';
import '../../tool/targets.dart';

Matcher dies(String text) => throwsA(
  isA<ReleaseError>().having((e) => e.message, 'message', contains(text)),
);

String sumOf(String c) => c * 64;

final fixedSums = {
  'chord-darwin-arm64.tar.gz': sumOf('a'),
  'chord-darwin-x64.tar.gz': sumOf('b'),
  'chord-linux-x64.tar.gz': sumOf('c'),
  'chord-linux-arm64.tar.gz': sumOf('d'),
};

void main() {
  test('the formula of a stable release, from its sums', () {
    const base = 'https://github.com/IKatsuba/chord/releases/download/v1.2.3';
    expect(renderFormula('1.2.3', fixedSums), '''
class Chord < Formula
  desc "Full-screen terminal client for ACP coding agents"
  homepage "https://github.com/IKatsuba/chord"
  version "1.2.3"
  license "MIT"

  on_macos do
    on_arm do
      url "$base/chord-darwin-arm64.tar.gz"
      sha256 "${sumOf('a')}"
    end
    on_intel do
      url "$base/chord-darwin-x64.tar.gz"
      sha256 "${sumOf('b')}"
    end
  end

  on_linux do
    on_arm do
      url "$base/chord-linux-arm64.tar.gz"
      sha256 "${sumOf('d')}"
    end
    on_intel do
      url "$base/chord-linux-x64.tar.gz"
      sha256 "${sumOf('c')}"
    end
  end

  def install
    bin.install "chord"
  end

  test do
    assert_match version.to_s, shell_output("#{bin}/chord --version")
  end
end
''');
  });

  test('a pre-release has no formula', () {
    expect(
      () => renderFormula('1.3.0-next.0', fixedSums),
      dies(
        '1.3.0-next.0 is a pre-release; Homebrew carries stable releases only',
      ),
    );
  });

  test('no version has no formula', () {
    expect(
      () => renderFormula('latest', fixedSums),
      throwsA(isA<VersionError>()),
    );
  });

  test('an archive without a sum has no formula', () {
    expect(
      () => renderFormula('1.2.3', {...fixedSums}..remove(targets[3].archive)),
      dies('SHA256SUMS has no sum for chord-linux-arm64.tar.gz'),
    );
  });

  test("sums are read in sha256sum's format, binary mark or not", () {
    expect(parseSums('${sumOf('a')}  x.tar.gz\n${sumOf('b')} *y\nbad\n'), {
      'x.tar.gz': sumOf('a'),
      'y': sumOf('b'),
    });
  });

  group('written from the archives', () {
    late Directory root;
    setUp(() {
      root = Directory.systemTemp.createTempSync('formula_test');
      final folder = Directory(p.join(root.path, archivesFolder))
        ..createSync(recursive: true);
      for (final target in targets) {
        File(
          p.join(folder.path, target.archive),
        ).writeAsStringSync('archive of $target');
      }
      recordSums(folder.path, [for (final target in targets) target.archive]);
    });
    tearDown(() => root.deleteSync(recursive: true));

    test('into the build output, with the recorded sums', () {
      writeFormula(root.path, '1.2.3');
      final text = File(p.join(root.path, formulaPath)).readAsStringSync();
      final sums = parseSums(
        File(
          p.join(root.path, archivesFolder, 'SHA256SUMS'),
        ).readAsStringSync(),
      );
      expect(text, renderFormula('1.2.3', sums));
      expect(formulaPath, 'build/release/chord.rb');
    });

    test('an archive changed since it was summed is refused', () {
      File(
        p.join(root.path, archivesFolder, targets[0].archive),
      ).writeAsStringSync('changed');
      expect(
        () => writeFormula(root.path, '1.2.3'),
        dies('chord-darwin-arm64.tar.gz has sha256'),
      );
      expect(File(p.join(root.path, formulaPath)).existsSync(), isFalse);
    });

    test('missing sums are refused', () {
      File(p.join(root.path, archivesFolder, 'SHA256SUMS')).deleteSync();
      expect(
        () => writeFormula(root.path, '1.2.3'),
        dies('SHA256SUMS is missing'),
      );
    });

    for (final (where, order) in [('after', 0), ('before', 1)]) {
      test('a second sum for a checked archive, $where it, is refused', () {
        final file = File(p.join(root.path, archivesFolder, 'SHA256SUMS'));
        final other = '${sumOf('f')}  ${targets[0].archive}\n';
        final text = file.readAsStringSync();
        file.writeAsStringSync(order == 0 ? '$text$other' : '$other$text');
        expect(
          () => writeFormula(root.path, '1.2.3'),
          dies('SHA256SUMS records chord-darwin-arm64.tar.gz more than once'),
        );
        expect(File(p.join(root.path, formulaPath)).existsSync(), isFalse);
      });
    }

    test('an archive with no recorded sum is refused', () {
      final file = File(p.join(root.path, archivesFolder, 'SHA256SUMS'));
      file.writeAsStringSync(
        file
            .readAsLinesSync()
            .where((line) => !line.endsWith(targets[2].archive))
            .map((line) => '$line\n')
            .join(),
      );
      expect(
        () => writeFormula(root.path, '1.2.3'),
        dies('SHA256SUMS has no sum for'),
      );
      expect(File(p.join(root.path, formulaPath)).existsSync(), isFalse);
    });
  });

  group('tester: formula sum boundaries', () {
    test('every target must have its own checksum', () {
      for (final target in targets) {
        expect(
          () => renderFormula('1.2.3', {...fixedSums}..remove(target.archive)),
          dies('SHA256SUMS has no sum for ${target.archive}'),
        );
      }
    });

    test('checksum row order does not change the platform mapping', () {
      final reversed = Map.fromEntries(fixedSums.entries.toList().reversed);
      expect(
        renderFormula('1.2.3', reversed),
        renderFormula('1.2.3', fixedSums),
      );
    });

    test('identical repeated sums with different mode markers are refused', () {
      expect(
        () => parseSums('${sumOf('a')}  x.tar.gz\n${sumOf('a')} *x.tar.gz\n'),
        dies('records x.tar.gz more than once'),
      );
    });

    test('a refused version preserves an existing formula', () {
      final root = Directory.systemTemp.createTempSync('formula_version_test');
      addTearDown(() => root.deleteSync(recursive: true));
      final folder = Directory(p.join(root.path, archivesFolder))
        ..createSync(recursive: true);
      for (final target in targets) {
        File(
          p.join(folder.path, target.archive),
        ).writeAsStringSync(target.name);
      }
      recordSums(folder.path, [for (final target in targets) target.archive]);
      final previous = File(p.join(root.path, formulaPath))
        ..writeAsStringSync('previous formula');
      expect(
        () => writeFormula(root.path, '1.2.3-next.0'),
        dies('pre-release'),
      );
      expect(previous.readAsStringSync(), 'previous formula');
      expect(
        () => writeFormula(root.path, 'latest'),
        throwsA(isA<VersionError>()),
      );
      expect(previous.readAsStringSync(), 'previous formula');
    });
  });
}
