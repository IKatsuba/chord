/// The web's stand-in for resource_arch_ffi.dart: a browser runs no
/// provider executable whose architecture would matter.
library;

/// This machine's architecture as Node names it, which a browser cannot say.
String nodeArch() => throw UnsupportedError(
  'the machine architecture is not available on the web',
);
