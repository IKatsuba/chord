import { expect, test } from 'bun:test';
import stripAnsi from 'strip-ansi';
import {
  fenceLanguage,
  highlightLines,
  pathLanguage,
} from '../../../src/ui/transcript/highlight.ts';
import { PALETTES } from '../../../src/ui/theme/theme.ts';

test('a fence names its language by the first word of its label', () => {
  expect(fenceLanguage('ts')).toStrictEqual('ts');
  expect(fenceLanguage('TypeScript title="a.ts"')).toStrictEqual('typescript');
  expect(fenceLanguage('sh')).toStrictEqual('sh');
  expect(fenceLanguage('')).toStrictEqual(undefined);
  expect(fenceLanguage(undefined)).toStrictEqual(undefined);
  expect(fenceLanguage('nolang')).toStrictEqual(undefined);
});

test('a file names its language by its extension or its name', () => {
  expect(pathLanguage('src/ui/App.tsx')).toStrictEqual('tsx');
  expect(pathLanguage('scripts/run.sh')).toStrictEqual('sh');
  expect(pathLanguage('Makefile')).toStrictEqual('makefile');
  expect(pathLanguage('C:\\src\\main.rs')).toStrictEqual('rs');
  expect(pathLanguage('notes.unknown')).toStrictEqual(undefined);
  expect(pathLanguage('README')).toStrictEqual(undefined);
});

test('code is coloured for the ground it is drawn on', () => {
  const { terminal: ground, tint: tinted } = PALETTES.light.code!;
  const [terminal] = highlightLines('const a = 1;', 'ts', ground);
  const [tint] = highlightLines('const a = 1;', 'ts', tinted);

  expect(terminal!.includes('\x1b['), 'coloured').toBeTruthy();
  expect(terminal).not.toStrictEqual(tint);
  expect(stripAnsi(terminal!)).toStrictEqual(stripAnsi(tint!));
});

test('each theme colours code in its own tones', () => {
  const [dark] = highlightLines(
    'const a = 1;',
    'ts',
    PALETTES.dark.code!.terminal,
  );
  const [light] = highlightLines(
    'const a = 1;',
    'ts',
    PALETTES.light.code!.terminal,
  );
  const [sixteen] = highlightLines(
    'const a = 1;',
    'ts',
    PALETTES['dark-ansi'].code!.terminal,
  );

  expect(dark).not.toStrictEqual(light);
  // The 16-colour themes name the terminal's own colours, never a hex.
  expect(
    !sixteen!.includes('38;2;') && !sixteen!.includes('38;5;'),
  ).toBeTruthy();
  expect(
    sixteen!.includes('\x1b[95m'),
    'keyword in bright magenta',
  ).toBeTruthy();
});

test('no tones, no colour', () => {
  expect(highlightLines('const a = 1;', 'ts', undefined)).toStrictEqual([
    'const a = 1;',
  ]);
});
