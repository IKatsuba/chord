/// The names chord is distributed under (the owner's Q360, Q361, Q371 and
/// Q372): the npm packages, the GitHub repository whose releases carry the
/// archives, and the Homebrew tap and formula. The release tools and the
/// upgrade read them from here alone.
library;

/// The npm scope every package of chord is published under.
const npmScope = '@chorded';

/// The npm package a person installs: the shim and its optional platform
/// packages.
const npmPackage = '$npmScope/chord';

/// The npm package holding the binary for [os] and [cpu], spelt as npm's
/// `os` and `cpu` fields spell them.
String platformPackage(String os, String cpu) => '$npmScope/chord-$os-$cpu';

/// The GitHub repository whose releases carry the archives.
const githubRepo = 'IKatsuba/chord';

/// The Homebrew tap, as `brew` names it.
const homebrewTap = 'ikatsuba/tap';

/// The GitHub repository of [homebrewTap], where the owner commits the
/// formula.
const homebrewTapRepo = 'IKatsuba/homebrew-tap';

/// The one Homebrew formula, stable releases only.
const homebrewFormula = 'chord';

/// The licence every npm package declares, the repository's LICENSE.
const npmLicense = 'MIT';
