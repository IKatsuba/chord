/** Only riff's checked, credential-free status facts cross this boundary. */
import { z } from '@zod/zod';

const NOTICE = z.object({
  provider: z.enum(['codex', 'grok']),
  state: z.enum(['unsaved', 'saved', 'signed_out', 'account_changed']),
});

export type CredentialNotice = z.infer<typeof NOTICE>;

export const RIFF_STORE = z.object({
  state: z.enum(['unavailable', 'timeout']),
  name: z.string(),
  message: z.string(),
});

export type RiffStoreFailure = z.infer<typeof RIFF_STORE>;

export function riffStoreFailure(error: unknown): RiffStoreFailure | undefined {
  for (
    let each = error;
    each !== null && typeof each === 'object';
    each = each instanceof Error ? each.cause : undefined
  ) {
    if (
      'data' in each &&
      each.data !== null &&
      typeof each.data === 'object' &&
      'riffStore' in each.data
    ) {
      const parsed = RIFF_STORE.safeParse(each.data.riffStore);

      if (parsed.success) {
        return parsed.data;
      }
    }
  }

  return undefined;
}

export function riffProvider(meta: unknown): 'codex' | 'grok' | undefined {
  const parsed = z
    .object({ 'chord/riffProvider': z.enum(['codex', 'grok']) })
    .safeParse(meta);

  return parsed.success ? parsed.data['chord/riffProvider'] : undefined;
}

const ENVELOPE = z.object({
  method: z.literal('_chord/credentials'),
  params: NOTICE,
});

export function credentialNotice(
  message: unknown,
): CredentialNotice | undefined {
  const envelope = ENVELOPE.safeParse(message);

  return envelope.success ? envelope.data.params : undefined;
}
