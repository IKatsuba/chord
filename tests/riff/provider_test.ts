import { describe, expect, test } from 'bun:test';
import { providerOf } from '../../src/riff/provider.ts';

describe('riff part 4 provider selection', () => {
  test('none, one, or both entries choose exactly the provisional provider', () => {
    expect(providerOf({ codex: null, grok: null })).toBeUndefined();
    expect(providerOf({ codex: 'entry', grok: null })).toBe('codex');
    expect(providerOf({ codex: null, grok: 'entry' })).toBe('grok');
    expect(providerOf({ codex: 'entry', grok: 'entry' })).toBe('codex');
  });
});
