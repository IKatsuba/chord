/**
 * What the window does past its own state, as hooks: the terminal told chord
 * waits, ctrl+g's editor, ctrl+v's clipboard and the image files a draft
 * names, bash mode's commands, the links an agent asks to open, the files
 * `@` offers, and OpenTUI's selection followed and copied.
 */
import { CliRenderEvents } from '@opentui/core';
import { useRenderer, useSelectionHandler } from '@opentui/react';
import {
  type Dispatch,
  useEffect,
  useLayoutEffect,
  useMemo,
  useRef,
} from 'react';
import { type EditorEnd, editorRefused } from '../../editor.ts';
import type { ClipboardReader, ImageFileReader } from '../../images.ts';
import type { LinkOpener } from '../../links.ts';
import {
  notificationBytes,
  type Notifications,
  type Wait,
} from '../../notify.ts';
import type { Conversation } from '../../session/conversation.ts';
import type { ElicitationWait } from '../../session/transcript/types.ts';
import type { ShellOptions, ShellProcess } from '../../shell.ts';
import {
  imagePathCount,
  insertImage,
  type PastedImage,
  takeImagePaths,
} from '../prompt/images.ts';
import { type Cursor, endOf, unholdable } from '../prompt/prompt.ts';
import { useApp, useStdout } from './renderer.tsx';
import { type Copy, copies } from './selection.ts';
import type { AppAction, AppState, WindowedAction } from './state.ts';

/**
 * Tells the terminal chord waits on the person, as `notifications` asks,
 * on stdout between frames.
 */
export function useNotify(
  notifications: Notifications | undefined,
): (wait: Wait | undefined, name: string) => void {
  const { write } = useStdout();

  return (wait, name) => {
    if (notifications === undefined || wait === undefined) {
      return;
    }

    const bytes = notificationBytes(
      wait,
      notifications.channel,
      notifications.env,
      name,
    );

    if (bytes !== undefined) {
      write(bytes);
    }
  };
}

/** Bash mode's commands, one running at most in each session. */
export function useShell(
  shell: (command: string, options: ShellOptions) => ShellProcess,
  /** The directory the session a key names works in. */
  cwdOf: (key: number) => string,
  dispatch: Dispatch<WindowedAction>,
): {
  /** Runs `command` in the session `key`'s directory. */
  run: (key: number, command: string) => void;
  /** Stops the command running in session `key`, if one runs. */
  stop: (key: number) => void;
} {
  // The command running in each session, by its key, so Esc, `/clear`,
  // closing the session and quitting can stop the one that is its.
  const running = useRef(new Map<number, ShellProcess>());

  useEffect(
    () => () => {
      for (const child of running.current.values()) {
        child.stop();
      }
    },
    [],
  );

  const stop = (key: number) => running.current.get(key)?.stop();

  // The run is the session's it started in, in front or not by its end.
  const run = (key: number, command: string) => {
    const id = crypto.randomUUID();
    const inSession = (action: AppAction) =>
      dispatch({ type: 'in_session', key, action });

    inSession({ type: 'shell_started', turnId: id, command });

    const child = shell(command, {
      cwd: cwdOf(key),
      onOutput: (stream, text) =>
        inSession({ type: 'shell_output', turnId: id, stream, text }),
    });

    running.current.set(key, child);

    void child.ended.then((end) => {
      if (running.current.get(key) === child) {
        running.current.delete(key);
      }

      inSession({ type: 'shell_ended', turnId: id, ...end });
    });
  };

  return { run, stop };
}

/**
 * ctrl+g: the renderer gives the terminal up, the editor has the draft,
 * and the renderer takes it back and draws the window afresh with what the
 * editor left.
 */
export function useEditor(
  editor: (draft: string) => Promise<EditorEnd>,
  dispatch: Dispatch<WindowedAction>,
  showDraft: (text: string, at: Cursor) => void,
): (draft: string) => Promise<void> {
  const { suspendTerminal } = useApp();
  // Set while the editor has the terminal, which is given up only once.
  const editing = useRef(false);

  return async (draft) => {
    if (editing.current) {
      return;
    }

    editing.current = true;

    dispatch({ type: 'editor_opened' });

    let end: EditorEnd | undefined;

    try {
      await suspendTerminal(async () => {
        end = await editor(draft);
      });
    } catch (error) {
      end = {
        failed: `The editor did not start: ${
          error instanceof Error ? error.message : String(error)
        }`,
      };
    } finally {
      editing.current = false;
    }

    if (end === undefined || 'failed' in end) {
      return end && dispatch({ type: 'editor_failed', message: end.failed });
    }

    const refused = unholdable(end.text);

    if (refused !== undefined) {
      return dispatch({
        type: 'editor_failed',
        message: editorRefused(refused),
      });
    }

    dispatch({ type: 'draft_edited' });
    showDraft(end.text, endOf(end.text));
  };
}

/** What the image hooks read and write the sessions through. */
export interface ImageSessions {
  /** The session in front. */
  readonly front: number;
  /** The window as the session `key` fills it now; none once it has closed. */
  stateOf(key: number): AppState | undefined;
  /** Puts `text` in the box of the session `key`, in front or not. */
  showDraftIn(key: number, text: string, at: Cursor): void;
  /** Sends a prompt to the session `key`; see `useSessions`. */
  send(
    text: string,
    key: number,
    images?: readonly PastedImage[],
    left?: string,
  ): void;
}

/**
 * ctrl+v's clipboard image, and the image files a pasted or typed path
 * names, each put in the draft as `[Image #N]`.
 */
export function useImages({
  clipboard,
  readImage,
  home,
  agent,
  state,
  dispatch,
  sessions,
}: {
  clipboard: ClipboardReader;
  readImage: ImageFileReader;
  home: string | undefined;
  agent: string;
  state: AppState;
  dispatch: Dispatch<WindowedAction>;
  sessions: ImageSessions;
}): {
  paste: (quiet?: boolean) => Promise<void>;
  takePastedPaths: (draft: string, end: number) => Promise<void>;
  sendWithPaths: (text: string) => Promise<void>;
  /** Whether the session `key`'s Enter is still reading image paths. */
  submitting: (key: number) => boolean;
} {
  const { stateOf, showDraftIn } = sessions;
  // The sessions whose Enter is reading typed image paths, so a second Enter
  // there does not send the prompt again, nor a later draft ahead of it.
  const submitting = useRef(new Set<number>());

  // The numbers images are given, ahead of the reducer while reads are out,
  // so two pastes in quick succession never share one.
  const imageIds = useRef(0);

  imageIds.current = Math.max(imageIds.current, state.imageCount);

  /** Why an image cannot go into the draft now, if it cannot. */
  const imageRefusal = () =>
    state.takesImages === false
      ? `${agent} does not take images`
      : state.takesImages === undefined
        ? `${agent} has not started yet`
        : undefined;

  /**
   * ctrl+v: the clipboard's image at the cursor, as `[Image #N]`. A `quiet`
   * one, an empty paste's, reads the clipboard first and says nothing when
   * it holds no image, as the person may have pasted nothing at all.
   */
  const paste = async (quiet = false) => {
    const key = sessions.front;
    const inSession = (action: AppAction) =>
      dispatch({ type: 'in_session', key, action });
    const refused = imageRefusal();

    if (refused !== undefined && !quiet) {
      return dispatch({ type: 'paste_failed', message: refused });
    }

    const read = await clipboard();

    if ('failed' in read) {
      return quiet
        ? undefined
        : inSession({ type: 'paste_failed', message: read.failed });
    }

    if (refused !== undefined) {
      return inSession({ type: 'paste_failed', message: refused });
    }

    const now = stateOf(key);

    if (now === undefined) {
      return;
    }

    const id = ++imageIds.current;
    const next = insertImage(now.draft, now.cursor, id);

    inSession({ type: 'images_added', images: [{ ...read.image, id }] });
    inSession({ type: 'draft_edited' });
    showDraftIn(key, next.text, next.cursor);
  };

  /**
   * A pasted path to an image file: the image in its place. `draft` is read
   * on both sides of `end`, where the paste ended, so the cursor stays after
   * what was pasted.
   */
  const takePastedPaths = async (draft: string, end: number) => {
    const key = sessions.front;
    const before = draft.slice(0, end);
    const after = draft.slice(end);
    const first = await takeImagePaths(
      before,
      imageIds.current + 1,
      readImage,
      home,
    );
    const second = await takeImagePaths(
      after,
      imageIds.current + 1 + first.images.length,
      readImage,
      home,
    );
    const images = [...first.images, ...second.images];

    // The draft moved on while the files were read; the paths stay text.
    if (images.length === 0 || stateOf(key)?.draft !== draft) {
      return;
    }

    imageIds.current += images.length;

    dispatch({
      type: 'in_session',
      key,
      action: { type: 'images_added', images },
    });
    showDraftIn(key, first.text + second.text, endOf(first.text));
  };

  /**
   * Enter on a draft that names image files by path, as typed: each one
   * read and put in as `[Image #N]` before the prompt goes.
   */
  const sendWithPaths = async (text: string) => {
    const key = sessions.front;

    submitting.current.add(key);

    // The numbers are kept before the reads, so a ctrl+v meanwhile takes
    // the one after; a path to no image leaves its number unused.
    const next = imageIds.current + 1;

    imageIds.current += imagePathCount(text, home);

    try {
      const taken = await takeImagePaths(text, next, readImage, home);
      const now = stateOf(key);

      if (now === undefined) {
        return;
      }

      dispatch({
        type: 'in_session',
        key,
        action: { type: 'images_added', images: taken.images },
      });
      sessions.send(
        taken.text,
        key,
        [...now.images, ...taken.images],
        now.draft === text ? '' : now.draft,
      );
    } finally {
      submitting.current.delete(key);
    }
  };

  return {
    paste,
    takePastedPaths,
    sendWithPaths,
    submitting: (key) => submitting.current.has(key),
  };
}

/**
 * The person's answer to a link the agent asked them to open: opened in the
 * system's browser first when they chose to.
 */
export function answerLink(
  openUrl: LinkOpener,
  conversation: Conversation | undefined,
  wait: Extract<ElicitationWait, { mode: 'url' }>,
  answer: 'open' | 'decline' | 'cancel',
): void {
  if (answer === 'open') {
    void openUrl(wait.url);
  }

  conversation?.answer(wait.id, {
    action: answer === 'open' ? 'accept' : answer,
  });
}

/**
 * Each time an `@` opens the finder the files are walked again, so ones
 * made since the last look are there; the last walk shows meanwhile.
 */
export function useFiles(
  files: (cwd: string) => Promise<readonly string[]>,
  cwd: string,
  mentioning: boolean,
  dispatch: Dispatch<WindowedAction>,
): void {
  // Held aside so that a walker passed inline does not walk on every draw.
  const walk = useRef(files);

  walk.current = files;

  useEffect(() => {
    if (!mentioning) {
      return;
    }

    let current = true;

    walk.current(cwd).then(
      (found) => current && dispatch({ type: 'files_listed', files: found }),
      () => {},
    );

    return () => {
      current = false;
    };
  }, [mentioning, cwd]);
}

/** What the window does to OpenTUI's selection, past following it. */
export interface SelectionHandle {
  /** The left button went down: a drag may have started. */
  pressed(): void;
  /** The selection shown, copied; nothing while one is out. */
  copy(): void;
  /** chord's own clear, before a key or a paste does its own. */
  clear(): void;
}

/**
 * OpenTUI's selection as the window follows it, through public API alone
 * (docs/design/CHD-172.md, "The lifecycle"): a drag's start read off the
 * press, its end off the renderer's `selection` event, OpenTUI's own clears
 * off the `frame` after them while one is held, and chord's state of none
 * made OpenTUI's too. Release copies when `copyOnSelect` is on; `copy` is
 * `main.tsx`'s write, or nothing at all.
 */
export function useSelection({
  state,
  dispatch,
  copy,
  copyOnSelect,
  size,
}: {
  state: AppState;
  dispatch: Dispatch<WindowedAction>;
  copy: Copy | undefined;
  copyOnSelect: boolean;
  /** The terminal's size: a resize rewraps what was selected. */
  size: string;
}): SelectionHandle {
  const renderer = useRenderer();
  const latest = useRef(state);
  const window = useMemo(() => copy && copies(copy), [copy]);
  const held = state.selection !== undefined && state.selection.kind !== 'none';

  latest.current = state;

  // The copy of what is highlighted now, captured before anything moves it.
  const start = (auto: boolean) => {
    const text = renderer.getSelection()?.getSelectedText() ?? '';

    if (window === undefined || text === '') {
      return;
    }

    dispatch({ type: 'copy_started' });
    // A copy superseded or disposed says nothing: the one after it will.
    void window
      .start(text)
      .then(
        (result) =>
          result !== undefined &&
          dispatch({ type: 'copy_noted', result, auto }),
      );
  };

  useSelectionHandler((selection) => {
    const text = selection.getSelectedText();

    dispatch({ type: 'selection_released', text });

    if (text !== '' && copyOnSelect) {
      start(true);
    }
  });

  // OpenTUI says nothing when it clears a selection itself, so a frame
  // after it is read, and only while chord holds one.
  useEffect(() => {
    if (!held) {
      return;
    }

    const read = () => {
      if (!renderer.hasSelection) {
        dispatch({ type: 'selection_gone' });
      } else if (
        // Its text gone, a plan step unmounted under it, OpenTUI still
        // holds a selection of nothing (owner, 2026-10-15).
        latest.current.selection?.kind === 'shown' &&
        renderer.getSelection()?.getSelectedText() === ''
      ) {
        renderer.clearSelection();
        dispatch({ type: 'selection_gone' });
      }
    };

    renderer.on(CliRenderEvents.FRAME, read);

    return () => {
      renderer.off(CliRenderEvents.FRAME, read);
    };
  }, [held, renderer, dispatch]);

  // chord's state of none is OpenTUI's too: a tab switched, `/clear`, ctrl+o,
  // the copy key's work done, release's note gone.
  useLayoutEffect(() => {
    if (!held && renderer.hasSelection) {
      renderer.clearSelection();
    }
  }, [held, renderer]);

  const resized = useRef(size);

  useLayoutEffect(() => {
    if (resized.current !== size) {
      resized.current = size;

      if (latest.current.selection !== undefined) {
        renderer.clearSelection();
        dispatch({ type: 'selection_gone' });
      }
    }
  }, [size, renderer, dispatch]);

  // Every way out reaches `destroy`; a copy still out says nothing after.
  useEffect(() => {
    if (window === undefined) {
      return;
    }

    const dispose = () => window.dispose();

    renderer.on(CliRenderEvents.DESTROY, dispose);

    return () => {
      renderer.off(CliRenderEvents.DESTROY, dispose);
    };
  }, [window, renderer]);

  return {
    pressed() {
      const selection = renderer.getSelection();

      if (selection?.isStart && selection.isDragging) {
        dispatch({ type: 'selection_started' });
      }
    },
    copy() {
      if (latest.current.selection?.kind === 'shown') {
        start(false);
      }
    },
    clear() {
      if (latest.current.selection !== undefined) {
        renderer.clearSelection();
        dispatch({ type: 'selection_gone' });
      }
    },
  };
}
