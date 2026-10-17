/**
 * The file the fake agent's `bigask` scenario asks to write, that of the
 * mocks in docs/design/CHD-246.md: a heading, a paragraph wider than any
 * window, and thirty changes.
 */
const CHANGES = [
  'the prompt keeps its draft',
  'a turn can be resumed',
  'headlines wrap',
  'the box scrolls',
  'tests run in parallel',
];

export const RELEASE_NOTES = [
  '# Release 0.56.0',
  '',
  'This release changes how chord draws long requests: the permission box ' +
    'now caps its height, keeps its options on screen and lets the person ' +
    'scroll through the whole argument before answering, at any window ' +
    'size, including 80 by 24.',
  '',
  '## Changes',
  '',
  ...Array.from(
    { length: 30 },
    (_, index) => `- Change ${index + 1}: ${CHANGES[index % CHANGES.length]}`,
  ),
  '',
].join('\n');
