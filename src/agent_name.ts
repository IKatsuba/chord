/** Names offered by `@@` must fit its literal, unescaped quoted syntax. */
import { z } from '@zod/zod';

export const agentName = z.string().refine((name) => !name.includes('"'), {
  message: 'must not contain the character "',
});

/** The same refusal before starting a child and when reading a saved team. */
export function agentNameProblem(name: string): string | undefined {
  const result = agentName.safeParse(name);

  return result.success ? undefined : result.error.issues[0]?.message;
}
