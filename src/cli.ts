import { Command, EnumType } from '@cliffy/command';
import process from 'node:process';
import manifest from '../package.json' with { type: 'json' };
import { OUTPUT_FORMATS } from './headless.ts';

/**
 * chord's flags, without what it does with them, so a test parses argv
 * through the very declarations `main.tsx` runs on.
 */
export function chordCommand() {
  return new Command()
    .name('chord')
    .version(manifest.version)
    .description(
      'A full-screen terminal client for ACP coding agents. A new unnamed interactive start asks which agent to use for this invocation; explicit commands, headless and resume routes keep their existing behavior.',
    )
    .type('format', new EnumType(OUTPUT_FORMATS))
    .arguments('[agent:string]')
    .option('-C, --cwd <dir:string>', 'Directory the session works in.', {
      default: process.cwd(),
    })
    .option(
      '--agent-command <command:string>',
      "Start this ACP agent command instead of chord's own; [agent] only names it.",
    )
    .option(
      '-m, --model <model:string>',
      "Start each of [agent]'s sessions on this model, by its id for it.",
      { conflicts: ['print'] },
    )
    .option(
      '--effort <effort:string>',
      "Start each of [agent]'s sessions on this effort, by its id for it.",
    )
    .option(
      '--permission-mode <mode:string>',
      "Start each of [agent]'s sessions in this mode, by its id for it.",
    )
    .option(
      '-c, --continue',
      "Open the agent's latest session in this directory again.",
      { conflicts: ['resume'] },
    )
    .option(
      '-r, --resume [id:string]',
      'Open a session by the id chord prints on quit; with no id, pick one.',
    )
    .option(
      '-p, --print <prompt:string>',
      'Send this prompt, print the reply and exit; piped input joins it.',
      { conflicts: ['continue', 'resume'] },
    )
    .option(
      '--dangerously-skip-permissions',
      'Allow every permission the agent asks for. Only with -p.',
    )
    .option(
      '--output-format <format:format>',
      'How -p prints: the reply as it streams, or one JSON object at the end.',
      { depends: ['print'] },
    )
    .example('Claude Code', 'chord claude')
    .example('Pick up where you left off', 'chord claude --continue')
    .example('Pick an earlier session', 'chord --resume')
    .example('Codex in another directory', 'chord codex -C ~/src/app')
    .example('One question, for a script', 'chord -p "What does this do?"')
    .example(
      'Piped input with the prompt',
      'git diff | chord -p "Review this" --output-format json',
    )
    .example(
      'An agent chord does not know',
      'chord my-agent --agent-command "my-agent --acp"',
    );
}
