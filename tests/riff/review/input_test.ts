import { describe, expect, test } from 'bun:test';
import { Buffer } from 'node:buffer';
import {
  excerpt,
  reviewInput,
  type ReviewAction,
} from '../../../src/riff/review/input.ts';

const requests = { current: 'current', first: 'first', recent: ['recent'] };
const shell = { tool: 'shell', command: 'pwd', cwd: '/project' } as const;
const mutation = {
  tool: 'write',
  real: '/outside/a',
  existed: false,
  additions: 1,
  deletions: 0,
  diff: '+hello',
} as const;

function build(action: ReviewAction = shell, results: string[] = []) {
  const result = reviewInput({
    action,
    requests,
    results: results.map((text, index) => ({
      id: String(index),
      tool: 'read',
      text,
    })),
  });

  if (result.outcome !== 'ready') {
    throw new Error(result.reason);
  }

  return result.text;
}

describe('review input', () => {
  test('only shell and outside reads carry user requests', () => {
    for (const action of [
      shell,
      { tool: 'read', real: '/outside/a' },
    ] as const) {
      expect(build(action)).toContain(
        '<current_request>current</current_request>',
      );
      expect(build(action)).toContain('<first_root_user_request>first');
      expect(build(action)).toContain('<recent_request>recent');
    }

    expect(build(mutation)).not.toContain('trusted_root_context');
    expect(build(mutation)).toContain('<existed>false</existed>');
    expect(build(mutation)).toContain('<diff>+hello</diff>');
  });

  test('escapes XML and terminal controls without introducing structural tags', () => {
    const text = build({ ...shell, command: '<&"\'>\u001b[31mred\u0007' });

    expect(text).toContain('&lt;&amp;&quot;&#39;&gt;red\\u0007');
    expect(text).not.toContain('\u001b');
    expect(text).not.toContain('\u0007');
  });

  test('any cut action field is incomplete, including an aggregate diff', () => {
    for (const action of [
      { ...shell, command: 'x'.repeat(65537) },
      { ...shell, cwd: 'x'.repeat(65537) },
      { ...mutation, diff: 'x'.repeat(65537) },
      { ...mutation, real: 'x'.repeat(65537) },
    ]) {
      expect(reviewInput({ action, requests, results: [] }).outcome).toBe(
        'incomplete',
      );
    }

    expect(build({ ...shell, command: 'x'.repeat(65536) })).toContain(
      '</command>',
    );
  });

  test('keeps tool result head and tail, with 16 results and 8 KiB total at most', () => {
    const text = build(
      shell,
      Array.from(
        { length: 20 },
        (_, i) => `${i}head${'x'.repeat(2000)}tail${i}`,
      ),
    );

    expect(text).toContain('0head');
    expect(text).toContain('tail0');
    expect(text).toContain('...[evidence omitted]...');
    expect(text.match(/<result>/g)?.length).toBe(8);
    expect(text).toContain('<omitted_results>12</omitted_results>');
    expect(text).toContain('trust="untrusted"');
    expect(
      build(shell, Array(20).fill('small')).match(/<result>/g)?.length,
    ).toBe(16);
  });

  test('caps requests together, branches separately, and leaves assistant prose absent', () => {
    const result = reviewInput({
      action: shell,
      requests: { ...requests, current: 'a'.repeat(2000) },
      branch: 'b'.repeat(300),
      results: [],
    });

    expect(result.outcome).toBe('ready');

    if (result.outcome === 'ready') {
      expect(result.text).toContain(
        '<first_root_user_request></first_root_user_request>',
      );
      expect(result.text).not.toContain('assistant');
      expect(
        result.text.match(/<current_branch>(.*?)<\/current_branch>/)?.[1]
          ?.length,
      ).toBe(255);
      expect(
        result.text.match(/<current_request>(.*?)<\/current_request>/)?.[1]
          ?.length,
      ).toBe(1024);
    }
  });

  test('UTF-8 cuts preserve code points and stay within the byte limit', () => {
    const cut = excerpt('🙂'.repeat(1000), 1024);

    expect(Buffer.byteLength(cut)).toBeLessThanOrEqual(1024);
    expect(cut).not.toContain('\ufffd');
    expect(cut.startsWith('🙂')).toBe(true);
    expect(cut.endsWith('🙂')).toBe(true);
  });
});
