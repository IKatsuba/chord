// The file the fake agent's `bigask` scenario asks to write, as the
// original's tests/fixtures/release_notes.ts has it (CHD-246).

const _changes = [
  'the prompt keeps its draft',
  'a turn can be resumed',
  'headlines wrap',
  'the box scrolls',
  'tests run in parallel',
];

/// A heading, a paragraph wider than any window, and thirty changes.
final String releaseNotes = [
  '# Release 0.56.0',
  '',
  'This release changes how chord draws long requests: the permission box '
      'now caps its height, keeps its options on screen and lets the person '
      'scroll through the whole argument before answering, at any window '
      'size, including 80 by 24.',
  '',
  '## Changes',
  '',
  for (var index = 0; index < 30; index++)
    '- Change ${index + 1}: ${_changes[index % _changes.length]}',
  '',
].join('\n');
