import { expect, test } from 'bun:test';
import {
  boundedWarnings,
  RESOURCE_CLEANUP_FAILED,
  RESOURCE_SHUTDOWN_UNVERIFIED,
  WARNINGS_OMITTED,
} from '../../src/session/resource_warnings.ts';
import { POOL_SCOPE_INCOMPLETE } from '../../src/session/resource_filter.ts';

test('full warning reports retain cleanup, fixed projection uncertainty and explicit omission', () => {
  const before = [
    ...Array.from({ length: 254 }, (_, i) => `Coverage warning ${i}.`),
    RESOURCE_CLEANUP_FAILED,
    RESOURCE_SHUTDOWN_UNVERIFIED,
  ];
  const copy = [...before];
  const result = boundedWarnings(before, [
    POOL_SCOPE_INCOMPLETE,
    POOL_SCOPE_INCOMPLETE,
  ]);

  expect(result).toHaveLength(256);
  expect(new Set(result).size).toBe(256);
  expect(result).toContain(RESOURCE_CLEANUP_FAILED);
  expect(result).toContain(RESOURCE_SHUTDOWN_UNVERIFIED);
  expect(result).toContain(POOL_SCOPE_INCOMPLETE);
  expect(result).toContain(WARNINGS_OMITTED);
  expect(before).toEqual(copy);
  expect(boundedWarnings(result, [POOL_SCOPE_INCOMPLETE])).toEqual(result);
});
