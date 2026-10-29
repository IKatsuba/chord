/**
 * clear_agent: a parent clears a child it opened, which keeps its id and
 * name in a fresh session that knows nothing of earlier turns (CHD-476).
 */
import { expect, test } from 'bun:test';
import { DOWN, ready, send, until, UP, type Window } from '../app/render.tsx';
import { count, withAgents } from './agents_window.tsx';
import { withTeams } from './teams_window.tsx';

/** Picks `name` in the list under the prompt and shows it. */
async function pick(window: Window, name: string) {
  await window.press(DOWN);
  await until(`${name} picked in the list`, async () => {
    if (new RegExp(`❯ (└─ )?${name} `).test(window.frame())) {
      return true;
    }

    await window.press(DOWN);

    return false;
  });

  await window.press('\r');
  await window.shows(`╭─ ${name} `);
}

test('main clears its working child: the queued message is not delivered and said so, the next is its first, an unknown name is refused, and main is told nothing more', () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'agentcost');
    await window.shows('Open(parser)');
    await until('parser at work', () =>
      /^ {4}parser .*✻/m.test(window.frame()),
    );
    await send(window, 'agentclear');
    await window.shows('parser was cleared.');

    expect(window.frame()).toContain('Clear(parser)');
    expect(window.frame()).toMatch(/Fresh session · id \w+/);
    expect(window.frame()).toContain(
      '1 queued message from main was not delivered.',
    );
    expect(window.frame()).toContain('Clear(nobody)');
    expect(window.frame()).not.toContain('The person cleared');
    expect(count(window, '    parser ')).toBe(1);

    // Its view has the message sent after the clear and its answer, and
    // nothing of the work before it.
    await pick(window, 'parser');
    await window.shows('This reply came in chunks.');

    expect(window.frame()).not.toContain('Queued before the clear.');
    await window.press(DOWN);
    await window.press(UP);
  }));

test("a lead clears its member: the member's next message carries the team's part again, as a first one does", () =>
  withTeams(async (window) => {
    await ready(window);
    await send(window, '/team run bugfix leadclear');
    await window.shows('└─ tester ');
    await pick(window, 'bugfix');
    await window.shows('tester was cleared.');

    expect(window.frame()).toContain('Clear(tester)');
    await pick(window, 'tester');
    await window.shows('The team part from bugfix reached this session.');
  }));

test('the old session of a cleared child reaches no one once it is let go, even as it still runs', () =>
  withAgents(async (window) => {
    await ready(window);
    await send(window, 'agentlate');
    await window.shows('Open(parser)');
    await until('parser at work', () =>
      /^ {4}parser .*✻/m.test(window.frame()),
    );
    await send(window, 'agentclearonly');
    await window.shows('parser was cleared.');
    // Another round trip of main's, by which the old turn has tried.
    await send(window, 'text');
    await window.shows('This reply came in chunks.');

    expect(window.frame()).not.toContain('Late from the old session.');
  }));

test('two clears at once: one is refused, and a message sent meanwhile goes once to the fresh session, as its first', () =>
  withTeams(async (window) => {
    await ready(window);
    await send(window, '/team run bugfix leadclearrace');
    await window.shows('└─ tester ');
    await pick(window, 'bugfix');
    await window.shows('tester was cleared once.');

    expect(window.frame()).toContain(
      'Could not clear tester: it is being cleared already',
    );
    expect(window.frame()).toMatch(/Fresh session · id \w+/);
    await pick(window, 'tester');
    await window.shows('The team part from bugfix reached this session.');

    expect(
      count(window, 'The team part from bugfix reached this session.'),
    ).toBe(1);
  }));

test("the person's first message to a member its lead cleared carries the team's part, as a first one does", () =>
  withTeams(async (window) => {
    await ready(window);
    await send(window, '/team run bugfix leadclearonly');
    await window.shows('└─ tester ');
    await pick(window, 'bugfix');
    await window.shows('tester was cleared.');
    await pick(window, 'tester');
    await send(window, 'teampartof');
    await window.shows('The team part from the person reached this session.');
  }));
