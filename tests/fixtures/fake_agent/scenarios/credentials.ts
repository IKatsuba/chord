/** Credential status facts without a store or provider behind them. */
import type { Play, Turn } from '../turn.ts';
import { gateOpened, GATE_RELEASE } from './agents.ts';

async function notice(turn: Turn, state: string): Promise<'end_turn'> {
  await turn.say('Credential fixture ready.');
  await gateOpened(turn, GATE_RELEASE);
  await turn.client.notify('_chord/credentials', { provider: 'codex', state });

  return 'end_turn';
}

export const CREDENTIALS = {
  credentialsunsaved: (turn) => notice(turn, 'unsaved'),
  credentialssaved: (turn) => notice(turn, 'saved'),
  credentialssignedout: (turn) => notice(turn, 'signed_out'),
  credentialsaccountchanged: (turn) => notice(turn, 'account_changed'),
} satisfies Record<string, Play>;
