/// The Homebrew formula of a stable release, rendered from its SHA256SUMS
/// and the archive contract (the owner's Q371 and Q372): one formula
/// `chord`, its URLs on the GitHub release `v<version>`, written into the
/// build output for the owner to review and commit to the tap, as the
/// archives exist only once the owner publishes the draft.
library;

import 'dart:io';

import 'package:chord/channel.dart';
import 'package:chord/distribution.dart';
import 'package:path/path.dart' as p;

import 'release/archive.dart';
import 'release/runner.dart';
import 'targets.dart';

/// Where the formula is written, from the root.
final formulaPath = p.join('build', 'release', '$homebrewFormula.rb');

/// The formula's description: the npm package's, in the form brew's desc audit
/// takes, with no leading article and no full stop (the owner's choice).
const formulaDesc = 'Full-screen terminal client for ACP coding agents';

final _sumLine = RegExp(r'^([0-9a-f]{64}) [ *](.+)$');

/// The sums SHA256SUMS' [text] records, by archive name. A name recorded
/// twice is refused: which of its sums was checked would be a guess.
Map<String, String> parseSums(String text) {
  final recorded = <String, String>{};
  for (final line in text.split('\n')) {
    if (_sumLine.firstMatch(line) case final match?) {
      if (recorded.containsKey(match[2])) {
        die('$sums records ${match[2]} more than once');
      }
      recorded[match[2]!] = match[1]!;
    }
  }
  return recorded;
}

/// The formula of [version] with the archives' [recorded] sums. Refuses a
/// pre-release, as Homebrew carries stable releases only, and a target
/// whose archive has no sum.
String renderFormula(String version, Map<String, String> recorded) {
  if (channelOf(version) != null) {
    die('$version is a pre-release; Homebrew carries stable releases only');
  }
  String block(String os, String cpu) {
    final target = targets.firstWhere((t) => t.os == os && t.cpu == cpu);
    final sum =
        recorded[target.archive] ??
        die('$sums has no sum for ${target.archive}');
    return '    ${cpu == 'arm64' ? 'on_arm' : 'on_intel'} do\n'
        '      url "https://github.com/$githubRepo/releases/download/'
        'v$version/${target.archive}"\n'
        '      sha256 "$sum"\n'
        '    end\n';
  }

  return 'class ${homebrewFormula[0].toUpperCase()}'
      '${homebrewFormula.substring(1)} < Formula\n'
      '  desc "$formulaDesc"\n'
      '  homepage "https://github.com/$githubRepo"\n'
      '  version "$version"\n'
      '  license "$npmLicense"\n'
      '\n'
      '  on_macos do\n'
      '${block('darwin', 'arm64')}${block('darwin', 'x64')}'
      '  end\n'
      '\n'
      '  on_linux do\n'
      '${block('linux', 'arm64')}${block('linux', 'x64')}'
      '  end\n'
      '\n'
      '  def install\n'
      '    bin.install "chord"\n'
      '  end\n'
      '\n'
      '  test do\n'
      '    assert_match version.to_s, shell_output("#{bin}/chord --version")\n'
      '  end\n'
      'end\n';
}

/// Writes [formulaPath] in [root] for [version] from the SHA256SUMS of the
/// archives, each archive checked against it first.
void writeFormula(String root, String version) {
  final folder = p.join(root, archivesFolder);
  final sumsFile = File(p.join(folder, sums));
  if (!sumsFile.existsSync()) die('${sumsFile.path} is missing');
  // One reading of the sums both checks the archives and fills the formula.
  final recorded = parseSums(sumsFile.readAsStringSync());
  for (final target in targets) {
    final path = p.join(folder, target.archive);
    final want = recorded[target.archive] ?? die('$sums has no sum for $path');
    final actual = sha256Of(path);
    if (actual != want) die('$path has sha256 $actual; $sums recorded $want');
  }
  File(
    p.join(root, formulaPath),
  ).writeAsStringSync(renderFormula(version, recorded));
}
