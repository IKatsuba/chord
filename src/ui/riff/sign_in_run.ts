/** Window effects for riff only; protocol sessions continue to read the store. */
import { useEffect, useMemo, useRef, useState } from 'react';
import type { FxFetch } from 'libfx/node';
import type { Secrets, SecretProvider } from '../../platform/secrets.ts';
import {
  SecretStoreTimeout,
  SecretStoreUnavailable,
} from '../../platform/secrets.ts';
import { runSignIn, type SignInSave } from '../../riff/sign_in_run.ts';
import { signOut, signedOutWords } from '../../riff/sign_out.ts';
import type { SignInEvent, SignInChoice } from '../../riff/sign_in.ts';
import type { ConversationEvent } from '../../session/conversation.ts';
import { chordStateDir } from '../../session/state_dir.ts';
import type { LinkOpener } from '../../links.ts';
import { copies, copyNote, type Copy } from '../app/selection.ts';
import type { useSessions } from '../app/sessions.ts';
import type { AppState, WindowedAction } from '../app/state.ts';
import {
  initialRiff,
  providerName,
  reduceRiff,
  type RiffAction,
  type RiffState,
  type RiffNotice,
} from './state.ts';

export interface RiffAccess {
  readonly store: Secrets;
  readonly fetch: FxFetch;
  readonly run?: typeof runSignIn;
  readonly fixture?: boolean;
  readonly provider?: SecretProvider;
  readonly changed?: (provider: SecretProvider | undefined) => void;
}

export function useRiffSignIn({
  access,
  key,
  agent,
  state,
  stateDir,
  sessions,
  dispatch,
  openUrl,
  copy,
}: {
  access: RiffAccess | undefined;
  key: number;
  agent: string;
  state: AppState;
  stateDir: string | undefined;
  sessions: ReturnType<typeof useSessions>;
  dispatch: (action: WindowedAction) => void;
  openUrl: LinkOpener;
  copy: Copy | undefined;
}) {
  const [states, setStates] = useState<Record<number, RiffState>>({});
  const latest = useRef(states);
  const attempts = useRef(new Map<number, AbortController>());
  const saves = useRef(new Map<number, SignInSave>());
  const lifetime = useRef(new AbortController());
  const suppressed = useRef(new Set<number>());
  const reasons = useRef(new Map<number, 'signed_out' | 'account_changed'>());
  const pending = useRef(new Map<number, SecretProvider>());
  const current = states[key] ?? initialRiff();
  const clipboard = useMemo(
    () => (copy === undefined ? undefined : copies(copy)),
    [copy],
  );
  const root = stateDir ?? chordStateDir();

  const get = (at: number) => latest.current[at] ?? initialRiff();
  const update = (at: number, action: RiffAction) => {
    const value = reduceRiff(get(at), action);

    latest.current = { ...latest.current, [at]: value };

    setStates(latest.current);

    return value;
  };

  const note = (at: number, notice: Omit<RiffNotice, 'at'>) =>
    update(at, {
      type: 'notice',
      notice: {
        at: sessions.stateOf(at)?.transcript.entries.length ?? 0,
        ...notice,
      },
    });
  const show = (at: number) => {
    attempts.current.get(at)?.abort();
    saves.current.get(at)?.discard();
    saves.current.delete(at);

    return update(at, { type: 'open', now: Date.now() });
  };

  const ownedSignal = (at: number, controller: AbortController) => {
    const owner = sessions.conversationAt(at);
    const signal = AbortSignal.any([
      controller.signal,
      lifetime.current.signal,
      owner?.launchSignal ?? AbortSignal.abort(),
    ]);

    signal.addEventListener(
      'abort',
      () => {
        if (attempts.current.get(at) === controller) {
          attempts.current.delete(at);
          saves.current.get(at)?.discard();
          saves.current.delete(at);
        }
      },
      { once: true },
    );

    return signal;
  };

  const event = (at: number, value: SignInEvent): RiffState => {
    const before = get(at);
    const next = update(at, { type: 'event', event: value, now: Date.now() });

    if (next.flow?.attempt !== before.flow?.attempt) {
      if (
        value.type === 'choose' &&
        value.choice === 'retry_store' &&
        saves.current.has(at)
      ) {
        // The OAuth attempt has ended. Transfer its private save handle
        // before cancelling the old UI generation.
        attempts.current.delete(at);
      } else {
        attempts.current.get(at)?.abort();
        saves.current.get(at)?.discard();
        saves.current.delete(at);
      }
    }

    if (
      next.flow?.step.kind === 'starting' &&
      next.flow.attempt !== before.flow?.attempt &&
      access !== undefined
    ) {
      const controller = new AbortController();
      const { provider, way } = next.flow.step;

      attempts.current.set(at, controller);

      const signal = ownedSignal(at, controller);

      void (access.run ?? runSignIn)({
        attempt: next.flow.attempt,
        provider,
        way,
        stateDir: root,
        store: access.store,
        fetch: access.fetch,
        signal,
        retainSave: (save) => {
          if (signal.aborted) {
            save.discard();
          } else {
            saves.current.set(at, save);
          }
        },
        emit: (attempt, step) => {
          if (signal.aborted) {
            return;
          }

          const value = event(at, { type: 'progress', attempt, step });

          if (value.flow?.attempt !== attempt || value.flow.step !== step) {
            return;
          }

          if (step.kind === 'browser') {
            void openUrl(step.address).then((failure) => {
              if (failure !== undefined && !signal.aborted) {
                dispatch({ type: 'sessions_noted', message: failure });
              }
            });
          } else if (step.kind === 'success') {
            const active =
              sessions.conversationAt(at)?.session !== undefined &&
              !get(at).signedOut;
            const receipt = `Signed in to ${providerName(provider)} ${way === 'code' ? 'with a code' : 'in the browser'}. Kept in the ${step.store}.`;

            access.changed?.(provider);
            pending.current.set(at, provider);
            suppressed.current.delete(at);
            note(at, {
              ...(active
                ? { title: `New riff session · ${providerName(provider)}` }
                : {}),
              text: receipt,
            });
            update(at, { type: 'close' });
            sessions.restartRiff(at, true);
          }
        },
      });
    }

    return next;
  };

  const retryStore = (at: number) => {
    if (access === undefined) {
      return;
    }

    const controller = new AbortController();
    const flow = get(at).flow;

    if (flow?.step.kind !== 'reading_store') {
      return;
    }

    attempts.current.set(at, controller);

    const signal = ownedSignal(at, controller);

    const save = saves.current.get(at);

    if (save !== undefined) {
      void save.retry(flow.attempt, signal).then((saved) => {
        if (saved || signal.aborted) {
          saves.current.delete(at);
        }
      });

      return;
    }

    void (async () => {
      try {
        const codex = await access.store.get('codex');
        const grok = await access.store.get('grok');

        if (signal.aborted) {
          return;
        }

        if (codex !== null || grok !== null) {
          suppressed.current.delete(at);
          update(at, { type: 'close' });
          sessions.restartRiff(at, true);
        } else {
          event(at, { type: 'store_ready', attempt: flow.attempt });
        }
      } catch (error) {
        if (signal.aborted) {
          return;
        }

        event(at, {
          type: 'progress',
          attempt: flow.attempt,
          step: {
            kind:
              error instanceof SecretStoreTimeout ? 'store_slow' : 'no_store',
            provider:
              flow.step.kind === 'reading_store'
                ? flow.step.provider
                : undefined,
            store: access.store.name,
            message:
              error instanceof Error
                ? error.message
                : new SecretStoreUnavailable(access.store.name).message,
          },
        });
      }
    })();
  };

  const heard = (at: number, runtime: string, heard: ConversationEvent) => {
    if (access === undefined || runtime !== 'riff') {
      return;
    }

    if (heard.type === 'connected') {
      reasons.current.delete(at);

      const provider =
        sessions.conversationAt(at)?.session?.riffProvider ??
        pending.current.get(at) ??
        access.provider;

      if (provider !== undefined) {
        update(at, { type: 'provider', provider });
      }

      if (get(at).flow?.step.kind === 'reading_store') {
        update(at, { type: 'close' });
      }
    } else if (heard.type === 'connect_failed' && heard.signIn === undefined) {
      update(at, { type: 'start_failed' });
    } else if (
      heard.type === 'credentials' &&
      (heard.state === 'signed_out' || heard.state === 'account_changed')
    ) {
      reasons.current.set(at, heard.state);
    } else if (
      heard.type === 'connect_failed' &&
      heard.signIn !== undefined &&
      !suppressed.current.has(at)
    ) {
      attempts.current.get(at)?.abort();
      update(at, { type: 'signed_out' });

      if (get(at).notices.length === 0) {
        note(at, { title: 'riff needs a sign-in to a ChatGPT or Grok plan' });
      }

      show(at);

      if (heard.signIn.store !== undefined) {
        const store = heard.signIn.store;

        event(at, {
          type: 'read_store',
          provider: undefined,
          store: store.name,
        });
        event(at, {
          type: 'progress',
          attempt: get(at).flow?.attempt ?? 0,
          step: {
            kind: store.state === 'timeout' ? 'store_slow' : 'no_store',
            provider: undefined,
            store: store.name,
            message: store.message,
          },
        });
      }
    } else if (
      heard.type === 'result' &&
      heard.result.status === 'failed' &&
      heard.result.error.code === '-32000'
    ) {
      update(at, { type: 'signed_out' });

      const provider =
        get(at).provider ?? sessions.conversationAt(at)?.session?.riffProvider;
      const reason = reasons.current.get(at);

      if (provider !== undefined && reason !== undefined) {
        update(at, { type: 'hide_error', turnId: heard.turnId });
        note(at, {
          title: `riff is signed out of ${providerName(provider)}`,
          text: `${reason === 'account_changed' ? 'The account changed' : 'The sign-in was removed'}, here or in another chord. Sign in again to go on; this transcript stays above.`,
          error: true,
        });
      }

      show(at);
    }
  };

  useEffect(
    () => () => {
      lifetime.current.abort();
      clipboard?.dispose();

      for (const controller of attempts.current.values()) {
        controller.abort();
      }
    },
    [],
  );

  // Initial events can precede the effect that first draws this hook.
  useEffect(() => {
    if (
      access !== undefined &&
      agent === 'riff' &&
      state.connection.status === 'starting' &&
      current.flow === undefined &&
      current.provider === undefined
    ) {
      update(key, { type: 'signed_out' });
      show(key);
      event(key, {
        type: 'read_store',
        provider: undefined,
        store: access.store.name,
      });
    }

    if (
      access !== undefined &&
      agent === 'riff' &&
      state.connection.status === 'ready' &&
      current.provider === undefined
    ) {
      const provider =
        sessions.conversation()?.session?.riffProvider ?? access.provider;

      if (provider !== undefined) {
        update(key, { type: 'provider', provider });
      }
    }
  }, [key, agent, state.connection.status, current.provider, access]);

  const login = () => {
    if (agent !== 'riff') {
      void sessions.newTyped('riff').then((shown) => {
        if (shown.kind === 'ran') {
          dispatch({
            type: 'in_session',
            key,
            action: {
              type: 'team_shown',
              turnId: `login-${crypto.randomUUID()}`,
              command: 'login',
              shown,
            },
          });
        } else if (shown.kind === 'said') {
          dispatch({
            type: 'in_session',
            key,
            action: {
              type: 'noted',
              turnId: `login-${crypto.randomUUID()}`,
              command: 'login',
              text: shown.text,
              failed: true,
            },
          });
        }
      });

      return;
    }

    attempts.current.get(key)?.abort();
    show(key);
  };

  const logout = () => {
    const provider =
      current.provider ??
      sessions.conversation()?.session?.riffProvider ??
      access?.provider;

    if (agent === 'riff' && provider !== undefined) {
      update(key, { type: 'logout', provider });
    }
  };

  const choose = (value: string) => {
    const selected = get(key);

    if (selected.logout !== undefined) {
      if (value === 'keep') {
        update(key, { type: 'close' });
      } else if (
        value === 'logout' &&
        !selected.logout.pending &&
        access !== undefined
      ) {
        update(key, { type: 'logout_pending', now: Date.now() });
        void signOut({
          provider: selected.logout.provider,
          stateDir: root,
          store: access.store,
          fetch: access.fetch,
          signal: lifetime.current.signal,
          cancel: () => sessions.cancelRiff(),
          deleted: () => {
            suppressed.current.add(key);
            access.changed?.(undefined);
            update(key, { type: 'signed_out' });
            sessions.endRiff(key);
          },
        }).then(
          (result) => {
            note(key, { command: 'logout', text: signedOutWords(result) });

            if (get(key).logout?.pending) {
              update(key, { type: 'close' });
            }
          },
          (error: unknown) =>
            update(key, {
              type: 'logout_failed',
              message:
                error instanceof Error
                  ? error.message
                  : 'The sign-in could not be removed.',
            }),
        );
      }

      return;
    }

    const step = selected.flow?.step;

    if (step?.kind === 'provider' && (value === 'codex' || value === 'grok')) {
      event(key, { type: 'provider', provider: value });
    } else if (
      step?.kind === 'way' &&
      (value === 'browser' || value === 'code')
    ) {
      event(key, { type: 'way', way: value });
    } else if (
      (step?.kind === 'browser' || step?.kind === 'code') &&
      value === 'open'
    ) {
      void openUrl(step.address);
    } else if (
      (step?.kind === 'browser' || step?.kind === 'code') &&
      (value === 'copy_address' || value === 'copy_code')
    ) {
      const text =
        value === 'copy_code' && step.kind === 'code'
          ? step.code
          : step.address;

      void clipboard?.start(text).then((result) => {
        if (result !== undefined) {
          dispatch({ type: 'sessions_noted', message: copyNote(result) });
        }
      });
    } else {
      const next = event(key, {
        type: 'choose',
        choice: value as SignInChoice,
      });

      if (next.flow?.step.kind === 'reading_store') {
        retryStore(key);
      }
    }
  };

  const back = () => {
    if (get(key).logout !== undefined) {
      update(key, { type: 'close' });

      return;
    }

    const next = event(key, { type: 'back' });

    if (next.flow?.step.kind === 'cancelled') {
      if (next.signedOut) {
        suppressed.current.add(key);
        note(key, {
          text: 'Not signed in. /login to sign in, or /new for another agent.',
        });
      }

      update(key, { type: 'close' });
    }
  };

  return {
    state: current,
    status: (at: number): 'waiting' | 'signed_out' | undefined => {
      const state = get(at);

      return !state.signedOut
        ? undefined
        : state.flow === undefined
          ? 'signed_out'
          : 'waiting';
    },
    heard,
    login,
    logout,
    choose,
    back,
    enabled: access !== undefined && agent === 'riff',
    box: current.flow !== undefined || current.logout !== undefined,
  };
}
