import { expect, jest, test } from 'bun:test';
import { act, useState } from 'react';
import { initialSignIn } from '../../../src/riff/sign_in.ts';
import { SignInBox } from '../../../src/ui/riff/SignIn.tsx';
import { initialRiff, type RiffState } from '../../../src/ui/riff/state.ts';
import { draw } from '../harness.tsx';
import { until } from '../app/render.tsx';

test('a code arriving between clock ticks never displays sixteen minutes for fifteen-minute validity', async () => {
  let change: (state: RiffState) => void = () => {};

  function Box() {
    const [state, setState] = useState({
      ...initialRiff(),
      flow: initialSignIn(),
    } as RiffState);

    change = setState;

    return (
      <SignInBox
        state={state}
        store='fixture store'
        width={80}
        room={20}
        onChoose={() => {}}
        onBack={() => {}}
      />
    );
  }

  const app = await draw(<Box />, { columns: 80, rows: 24 });

  try {
    jest.setSystemTime(Date.now() + 10_000);
    await act(() =>
      change({
        ...initialRiff(),
        flow: {
          attempt: 3,
          step: {
            kind: 'code',
            provider: 'grok',
            way: 'code',
            address: 'https://example.invalid/device',
            code: 'WXYZ-1234',
            expiresAt: Date.now() + 15 * 60_000,
          },
        },
      }),
    );
    await until('the code', () => app.frame().includes('WXYZ-1234'));
    expect(app.frame()).toContain('The code expires in 15 minutes.');
    expect(app.frame()).not.toContain('16 minutes');
  } finally {
    jest.setSystemTime();
    await app.unmount();
  }
});
