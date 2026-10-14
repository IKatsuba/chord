/**
 * The slash commands the fake agent advertises in every session, apart from
 * the agent so a test can name them without starting one.
 */
import type { AvailableCommand } from '@agentclientprotocol/sdk';

export const FAKE_COMMANDS: AvailableCommand[] = [
  { name: 'greet', description: 'Say hello from the fake agent' },
  {
    name: 'echo',
    description: 'Repeat what follows the command',
    input: { hint: 'text to repeat' },
  },
];
