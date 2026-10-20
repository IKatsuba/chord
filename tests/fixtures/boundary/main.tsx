/**
 * A component that throws, drawn on OpenTUI's test renderer, for a build as
 * chord's binary is built: what OpenTUI's root ErrorBoundary paints is
 * printed, then chord's crash screen around it, or how a fallback failed
 * (CHD-468).
 */
import { createTestRenderer } from '@opentui/core/testing';
import { createRoot } from '@opentui/react';
import type { ReactNode } from 'react';
import { CrashBoundary } from '../../../src/ui/app/Crash.tsx';

function Throws(): never {
  throw new Error('the boundary caught this');
}

async function frameOf(node: ReactNode): Promise<string> {
  const setup = await createTestRenderer({ width: 80, height: 24 });

  try {
    createRoot(setup.renderer).render(node);
    await setup.renderOnce();
    await setup.renderOnce();

    return setup.captureCharFrame();
  } finally {
    setup.renderer.destroy();
  }
}

console.log(await frameOf(<Throws />));
console.log(
  await frameOf(
    <CrashBoundary quit={() => {}}>
      <Throws />
    </CrashBoundary>,
  ),
);
