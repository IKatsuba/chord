import { describe, expect, test } from 'bun:test';
import {
  classifySetting,
  notSavedLine,
  settingRefusal,
} from '../src/settings_tool.ts';

const known = ['claude', 'codex', 'my.agent'];
const set = (value: unknown) => ({ set: value });
const remove = { remove: true } as const;

describe('CHD-568 U2 tester: validation boundaries', () => {
  test('a malformed list is refused before any unknown agent is considered', () => {
    const offered = ['unknown-first', null, 'codex'];

    expect(settingRefusal(['offeredAgents'], set(offered), known)).toStartWith(
      'offeredAgents cannot be ["unknown-first",null,"codex"]: ',
    );
    expect(offered).toEqual(['unknown-first', null, 'codex']);
    expect(
      settingRefusal(
        ['offeredAgents'],
        set(['codex', 'unknown-second']),
        known,
      ),
    ).toBe(
      'chord knows no agent named "unknown-second"; list_agents names every one',
    );
  });

  test('known own agent names may resemble object methods or contain terminal controls', () => {
    const names = ['toString', 'hasOwnProperty', 'agent.\u009b\u202e'];

    for (const name of names) {
      expect(
        settingRefusal(['agents', name, 'model'], set('external-model'), names),
      ).toBeUndefined();
      expect(settingRefusal(['agent'], set(name), names)).toBeUndefined();
      expect(
        settingRefusal(['teamSelection', 'prefer', 'agent'], set(name), names),
      ).toBeUndefined();
    }

    const refused = settingRefusal(
      ['agents', names[2]!, 'effort'],
      set('external-effort'),
      [],
    );

    expect(refused).toContain('agent.\\u009b\\u202e');
    expect(refused).not.toMatch(/[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]/u);
  });

  test('forbidden keys stay unknown even below hand-edit branches', () => {
    for (const key of ['__proto__', 'constructor', 'prototype']) {
      for (const path of [
        ['mcpServers', 'server', 'env', key],
        ['agents', 'codex', 'command', key],
        ['teamSelection', 'constraints', 'models', key],
      ]) {
        expect(classifySetting(path)).toEqual({ kind: 'unknown' });
        expect(settingRefusal(path, remove, known)).toStartWith('No setting ');
        expect(settingRefusal(path, set(null), known)).toStartWith(
          'No setting ',
        );
      }
    }
  });

  test('null resets only the nullable preference, and removal accepts an unknown effort owner', () => {
    expect(
      settingRefusal(['teamSelection', 'prefer', 'model'], set(null), []),
    ).toBeUndefined();

    for (const path of [
      ['agents', 'codex', 'model'],
      ['agents', 'codex', 'effort'],
      ['teamSelection', 'prefer', 'agent'],
      ['teamSelection', 'intent'],
    ]) {
      expect(settingRefusal(path, set(null), known)).toContain(
        'cannot be null:',
      );
    }

    expect(
      settingRefusal(['agents', 'gone.agent', 'effort'], remove, []),
    ).toBeUndefined();
    expect(
      settingRefusal(['agents', 'codex', 'model'], set('unknown.model'), known),
    ).toBeUndefined();
  });
});

describe('classifySetting', () => {
  test.each([
    [['theme'], true, 'now'],
    [['editorMode'], true, 'now'],
    [['mouse'], true, 'next start'],
    [['copyOnSelect'], true, 'next start'],
    [['offeredAgents'], true, 'now'],
    [['preferredNotifChannel'], false, 'next start'],
    [['agent'], false, 'next start'],
    [['agents', 'codex', 'model'], false, 'next start'],
    [['agents', 'codex', 'effort'], false, 'next start'],
    [['teamSelection', 'intent'], false, 'now'],
    [['teamSelection', 'prefer', 'agent'], false, 'now'],
    [['teamSelection', 'prefer', 'model'], false, 'now'],
  ])('%j is writable', (path, userOnly, takesEffect) => {
    expect(classifySetting(path)).toMatchObject({
      kind: 'leaf',
      userOnly,
      takesEffect,
    });
  });

  test.each([
    [['agents', 'codex', 'command']],
    [['agents', 'codex', 'command', '0']],
    [['agents', 'codex', 'permissionMode']],
    [['agents', 'codex', 'mcpServers']],
    [['mcpServers']],
    [['mcpServers', 'linear']],
    [['mcpServers', 'linear', 'env', 'TOKEN']],
    [['teamSelection', 'constraints']],
    [['teamSelection', 'constraints', 'agents']],
    [['teamSelection', 'constraints', 'models', 'codex']],
  ])('%j stays a hand edit', (path) => {
    expect(classifySetting(path)).toStrictEqual({ kind: 'hand' });
  });

  test.each([
    [['nope']],
    [['theme', 'deeper']],
    [['toString']],
    [['agents', 'codex', 'modle']],
    [['agents', 'codex', 'model', 'deeper']],
    [['agents', 'codex', 'toString']],
    [['teamSelection', 'nope']],
    [['teamSelection', 'intent', 'deeper']],
    [['teamSelection', 'prefer', 'nope']],
    [['teamSelection', 'prefer', 'toString']],
    [['teamSelection', 'prefer', 'model', 'deeper']],
    [['__proto__']],
    [['constructor']],
    [['prototype']],
    [['agents', '__proto__', 'model']],
    [['agents', 'constructor', 'model']],
    [['theme', '__proto__']],
    [[]],
  ])('%j is no setting', (path) => {
    expect(classifySetting(path)).toStrictEqual({ kind: 'unknown' });
  });
});

describe('settingRefusal', () => {
  test.each<[string[], string]>([
    [['agents', 'claude', 'modle'], 'No setting agents.claude.modle'],
    [['__proto__'], 'No setting __proto__'],
    [['agents', 'my.agent', 'x'], 'No setting agents."my.agent".x'],
    [
      ['agents', 'claude', 'command'],
      'chord does not write agents.claude.command; edit the settings file by hand',
    ],
    [
      ['mcpServers', 'x'],
      'chord does not write mcpServers.x; edit the settings file by hand',
    ],
    [
      ['agents', 'codex'],
      'agents.codex is not one setting; name agents.codex.model or agents.codex.effort',
    ],
    [
      ['agents'],
      'agents is not one setting; name agents.<name>.model or agents.<name>.effort',
    ],
    [
      ['teamSelection'],
      'teamSelection is not one setting; name teamSelection.intent, teamSelection.prefer.agent or teamSelection.prefer.model',
    ],
    [
      ['teamSelection', 'prefer'],
      'teamSelection.prefer is not one setting; name teamSelection.prefer.agent or teamSelection.prefer.model',
    ],
  ])('%j is refused on set and remove alike', (path, line) => {
    expect(settingRefusal(path, set('x'), known)).toBe(line);
    expect(settingRefusal(path, remove, known)).toBe(line);
  });

  test('the path is checked before the value', () => {
    expect(settingRefusal(['nope'], set(undefined), [])).toBe(
      'No setting nope',
    );
  });

  test.each<[string[], unknown, string]>([
    [
      ['editorMode'],
      'emacs',
      'editorMode cannot be "emacs": Invalid option: expected one of "normal"|"vim"',
    ],
    [
      ['mouse'],
      'yes',
      'mouse cannot be "yes": Invalid input: expected boolean, received string',
    ],
    [
      ['agent'],
      '',
      'agent cannot be "": Too small: expected string to have >=1 characters',
    ],
    [
      ['offeredAgents'],
      ['claude', 3],
      'offeredAgents cannot be ["claude",3]: expected a list of one or more agent names',
    ],
    [
      ['offeredAgents'],
      [],
      'offeredAgents cannot be []: expected a list of one or more agent names',
    ],
    [
      ['agents', 'claude', 'model'],
      null,
      'agents.claude.model cannot be null: Invalid input: expected string, received null',
    ],
  ])('%j with %j is refused by its own schema', (path, value, line) => {
    expect(settingRefusal(path, set(value), known)).toBe(line);
  });

  test('a value left out is refused, not written as nothing', () => {
    expect(settingRefusal(['theme'], set(undefined), known)).toStartWith(
      'theme cannot be left out: ',
    );
    expect(
      settingRefusal(
        ['teamSelection', 'prefer', 'model'],
        set(undefined),
        known,
      ),
    ).toStartWith('teamSelection.prefer.model cannot be left out: ');
  });

  test('a value that holds a control reads escaped in the refusal', () => {
    expect(settingRefusal(['theme'], set('\u009b31m'), known)).toStartWith(
      'theme cannot be "\\u009b31m": ',
    );
  });

  test.each<[string[], unknown]>([
    [['theme'], 'dark'],
    [['editorMode'], 'vim'],
    [['mouse'], false],
    [['copyOnSelect'], true],
    [['offeredAgents'], ['claude', 'codex']],
    [['preferredNotifChannel'], 'bell'],
    [['agent'], 'claude'],
    [['agents', 'my.agent', 'model'], 'any-id-at-all'],
    [['agents', 'codex', 'effort'], 'unheard-of'],
    [['teamSelection', 'intent'], 'economy'],
    [['teamSelection', 'prefer', 'agent'], 'codex'],
    [['teamSelection', 'prefer', 'model'], 'any-id'],
    [['teamSelection', 'prefer', 'model'], null],
  ])('%j takes %j', (path, value) => {
    expect(settingRefusal(path, set(value), known)).toBeUndefined();
  });

  test.each<[string[], unknown, string]>([
    [['agents', 'nope', 'model'], 'm', 'nope'],
    [['agent'], 'nope', 'nope'],
    [['offeredAgents'], ['claude', 'nope', 'other'], 'nope'],
    [['teamSelection', 'prefer', 'agent'], 'nope', 'nope'],
    [['agents', 'a"b', 'effort'], 'm', 'a\\"b'],
  ])('%j with %j names an agent chord lacks', (path, value, name) => {
    expect(settingRefusal(path, set(value), known)).toBe(
      `chord knows no agent named "${name}"; list_agents names every one`,
    );
  });

  test('the schema is checked before the names', () => {
    expect(
      settingRefusal(['agents', 'nope', 'model'], set(''), known),
    ).toStartWith('agents.nope.model cannot be "": ');
  });

  test('a remove checks no name and no value', () => {
    for (const path of [
      ['agents', 'stale', 'model'],
      ['agent'],
      ['offeredAgents'],
      ['theme'],
    ]) {
      expect(settingRefusal(path, remove, known)).toBeUndefined();
    }
  });

  test('a file refusal ends with what the writer said', () => {
    expect(
      notSavedLine('~/.config/chord/settings.json', 'it is not valid JSON'),
    ).toBe('~/.config/chord/settings.json was not saved: it is not valid JSON');
  });
});
