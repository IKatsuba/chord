/** Only riff's checked, credential-free status facts cross this boundary. */
import { z } from '@zod/zod';

const NOTICE = z.object({
  provider: z.enum(['codex', 'grok']),
  state: z.enum(['unsaved', 'saved', 'signed_out', 'account_changed']),
});

export type CredentialNotice = z.infer<typeof NOTICE>;

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
