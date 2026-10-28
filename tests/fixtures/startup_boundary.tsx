/** Observe the actual CLI handler while its agent choice remains unresolved. */
import { spyOn } from 'bun:test';
import { useRenderer } from '@opentui/react';
import type { CliRenderer } from '@opentui/core';
import { isValidElement, type ReactNode } from 'react';
import assert from 'node:assert/strict';
import { draw } from '../ui/harness.tsx';

Object.defineProperty(process.stdin, 'isTTY', {
  value: true,
  configurable: true,
});
Object.defineProperty(process.stdout, 'isTTY', {
  value: true,
  configurable: true,
});

let renderer: CliRenderer | undefined;

function Probe() {
  renderer = useRenderer();

  return null;
}

const view = await draw(<Probe />);

assert(renderer);

const { cli, startServices } = await import('../../src/main.tsx');
const counts = { session: 0, server: 0, resources: 0, copier: 0 };
const stop = new Error('fixture stopped after choice');
const spies: { mockRestore(): void }[] = [
  spyOn(startServices, 'openSession').mockImplementation(() => {
    counts.session++;

    throw stop;
  }),
  spyOn(startServices, 'serveChord').mockImplementation(() => {
    counts.server++;

    throw stop;
  }),
  spyOn(startServices, 'createResources').mockImplementation(() => {
    counts.resources++;

    throw stop;
  }),
  spyOn(startServices, 'copier').mockImplementation(() => {
    counts.copier++;

    throw stop;
  }),
  spyOn(startServices, 'openTerminal').mockResolvedValue({
    renderer,
    dark: true,
  }),
];
let choose: ((name: string | undefined) => void) | undefined;
const waiting = Promise.withResolvers<void>();

spies.push(
  spyOn(startServices, 'render').mockImplementation((node: ReactNode) => {
    assert(
      isValidElement<{ onPick: (name: string | undefined) => void }>(node),
    );

    choose = node.props.onPick;

    waiting.resolve();

    return {
      rerender: () => {},
      waitUntilExit: () => Promise.resolve(),
      unmount: () => Promise.resolve(),
    };
  }),
);

try {
  const run = cli
    .noExit()
    .throwErrors()
    .parse(['-C', process.env['CHORD_START_PROJECT']!]);

  await waiting.promise;
  assert.deepEqual(counts, { session: 0, server: 0, resources: 0, copier: 0 });
  assert(choose);

  choose(process.argv.includes('--choose') ? 'fixture' : undefined);

  try {
    await run;
    assert(!process.argv.includes('--choose'));
  } catch (error) {
    assert.equal(error, stop);
    assert(process.argv.includes('--choose'));
  }

  console.log(JSON.stringify(counts));
} finally {
  for (const spy of spies) {
    spy.mockRestore();
  }

  await view.unmount();
}
