/** CHD-606's words on the existing status-notice line. */
import type { CredentialNotice } from '../../session/credentials.ts';

export function credentialWords(notice: CredentialNotice): string {
  const provider = notice.provider === 'codex' ? 'ChatGPT' : 'Grok';

  switch (notice.state) {
    case 'unsaved':
      return `${provider} sign-in refreshed but not saved; will retry.`;
    case 'saved':
      return `${provider} sign-in saved.`;
    case 'signed_out':
      return `${provider} sign-in removed. This session is signed out.`;
    case 'account_changed':
      return `${provider} account changed. This session is signed out.`;
  }
}
