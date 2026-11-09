// The files src/platform/libfx.ts imports `with { type: 'file' }`, which Bun
// gives as paths: an embedded one in a compiled binary.

/** The target's libfx addon, resolved by scripts/dev/compile.ts's plugin. */
declare module 'chord:libfx-native' {
  const path: string;
  export default path;
}

declare module '*.wasm' {
  const path: string;
  export default path;
}
