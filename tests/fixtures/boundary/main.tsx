/**
 * A component that throws, drawn on OpenTUI's test renderer, for a build as
 * chord's binary is built: what the root ErrorBoundary paints is printed,
 * or how its fallback failed (CHD-468).
 */
import { createTestRenderer } from '@opentui/core/testing';
import { createRoot } from '@opentui/react';

function Throws(): never {
  throw new Error('the boundary caught this');
}

const setup = await createTestRenderer({ width: 80, height: 24 });

try {
  createRoot(setup.renderer).render(<Throws />);
  await setup.renderOnce();
  await setup.renderOnce();
  console.log(setup.captureCharFrame());
} finally {
  setup.renderer.destroy();
}
