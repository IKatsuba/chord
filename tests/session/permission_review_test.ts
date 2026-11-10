import { expect, test } from 'bun:test';
import { permissionPresentation } from '../../src/session/permission_review.ts';

test('permission presentation validates independent optional fields for any agent', () => {
  expect(
    permissionPresentation({
      'chord/permission': {
        review: { outcome: 'caution', reason: 'rationale' },
        deadlineAt: 1234,
      },
    }),
  ).toEqual({
    review: { outcome: 'caution', reason: 'rationale' },
    deadlineAt: 1234,
  });
  expect(
    permissionPresentation({
      'chord/permission': {
        review: { outcome: 'invented', reason: 'rationale' },
        deadlineAt: 1234,
      },
    }),
  ).toEqual({ deadlineAt: 1234 });
  expect(
    permissionPresentation({
      'chord/permission': {
        review: { outcome: 'failed', reason: 'unavailable' },
        deadlineAt: -1,
      },
    }),
  ).toEqual({ review: { outcome: 'failed', reason: 'unavailable' } });

  for (const meta of [undefined, null, {}, { 'chord/permission': 'invalid' }]) {
    expect(permissionPresentation(meta)).toEqual({});
  }
});
