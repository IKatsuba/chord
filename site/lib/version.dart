/// chord's version, as the build reads it from the root pubspec and passes
/// with `-DCHORD_VERSION`; `dev` where nothing passed it.
const chordVersion = String.fromEnvironment(
  'CHORD_VERSION',
  defaultValue: 'dev',
);

/// Where chord's source lives.
const repositoryUrl = 'https://github.com/IKatsuba/chord';
