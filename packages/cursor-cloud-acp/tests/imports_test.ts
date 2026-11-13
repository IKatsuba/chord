import { expect, test } from 'bun:test';
import { readdirSync, readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

// Only the wiring reaches the real SDK and keyring: cursor.ts and
// keyring.ts are the real implementations, main.ts alone imports them, and
// bin.ts imports main.ts. Every other module, serve.ts's graph among them,
// imports them for types at most, so a test drives it with fakes alone
// (CHD-622, "The seam").
const REAL = new Set(['cursor.ts', 'keyring.ts']);
const WIRING = new Set(['main.ts', 'bin.ts', ...REAL]);
const RUNTIME_ONLY = /^(@cursor\/sdk|@napi-rs\/keyring)(\/|$)/;

const src = fileURLToPath(new URL('../src/', import.meta.url));
// Bun's transpiler drops type-only imports, as the build does.
const transpiler = new Bun.Transpiler({ loader: 'ts' });

/** The modules `file` imports at run time. */
function imports(file: string): string[] {
  return transpiler
    .scanImports(readFileSync(`${src}${file}`, 'utf8'))
    .map((each) => each.path);
}

const files = readdirSync(src).filter((file) => file.endsWith('.ts'));

test('the source has modules to check', () => {
  expect(files).toContain('port.ts');
  expect(files).toContain('cursor.ts');
});

test.each(files.filter((file) => !WIRING.has(file)))(
  '%s imports no SDK, keyring, nor their real implementations at run time',
  (file) => {
    expect(
      imports(file).filter(
        (path) =>
          RUNTIME_ONLY.test(path) ||
          [...WIRING].some((wiring) => path === `./${wiring}`),
      ),
    ).toEqual([]);
  },
);

test('port.ts takes the SDK for its types, not at run time', () => {
  expect(readFileSync(`${src}port.ts`, 'utf8')).toContain("from '@cursor/sdk'");
  expect(imports('port.ts')).toEqual([]);
});
