import 'package:chord/distribution.dart';
import 'package:test/test.dart';

void main() {
  test("the names are the owner's", () {
    expect(npmPackage, '@chorded/chord');
    expect(platformPackage('darwin', 'arm64'), '@chorded/chord-darwin-arm64');
    expect(githubRepo, 'IKatsuba/chord');
    expect(homebrewTap, 'ikatsuba/tap');
    expect(homebrewTapRepo, 'IKatsuba/homebrew-tap');
    expect(homebrewFormula, 'chord');
  });
}
