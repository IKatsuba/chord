/** Names offered by `@@` must fit its literal, single-line quoted syntax. */
import { z } from '@zod/zod';

/** The same refusal before starting a child and when reading a saved team. */
export function agentNameProblem(name: string): string | undefined {
  const bad = [...name].find((character) => {
    const code = character.charCodeAt(0);

    return character === '"' || code < 32 || code === 127;
  });

  return bad === undefined
    ? undefined
    : bad === '"'
      ? 'must not contain the character "'
      : `must not contain the control character U+${bad.charCodeAt(0).toString(16).toUpperCase().padStart(4, '0')}`;
}

export const agentName = z.string().superRefine((name, context) => {
  const problem = agentNameProblem(name);

  if (problem !== undefined) {
    context.addIssue({ code: 'custom', message: problem });
  }
});
