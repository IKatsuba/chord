// The slash commands the fake agent advertises in every session, apart from
// the agent so a test can name them without starting one, as the original's
// tests/fixtures/commands.ts.

/// The fake agent's commands, as `available_commands_update` lists them.
const fakeCommands = [
  {'name': 'greet', 'description': 'Say hello from the fake agent'},
  {
    'name': 'echo',
    'description': 'Repeat what follows the command',
    'input': {'hint': 'text to repeat'},
  },
];
