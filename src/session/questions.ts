/**
 * The questions an agent asks through a form, in one shape whichever adapter
 * sent them. Each adapter lays its questions out in a form of its own: which
 * of a field's title and description is the question, which text field is a
 * question's own answer, which option stands for one. An enricher reads that
 * layout by the adapter's own marks (`enrichers.ts`) and leaves this shape
 * beside the form under `_meta`, keeping the form as it was sent, so the
 * answer goes back under the adapter's own field ids and anything that does
 * not read the shape answers the same form.
 */
import type {
  CreateElicitationRequest,
  ElicitationContentValue,
} from '@agentclientprotocol/sdk';
import { recordOf } from './enrich.ts';

/** The `_meta` key on an elicitation request that holds its questions. */
export const QUESTIONS = 'chord/questions';

/** The adapters whose question forms chord reads. */
export type QuestionsAgent =
  'claude' | 'codex' | 'droid' | 'opencode' | 'dimcode';

/** A form's questions, as `_meta["chord/questions"]` holds them. */
export interface Questions {
  readonly agent: QuestionsAgent;
  readonly questions: readonly Question[];
  /**
   * How long the agent waits before it answers for the person (codex's
   * `autoResolutionMs`), counted from when the request came.
   */
  readonly expiresInMs?: number;
}

/** One question. */
export interface Question {
  /** The form field that takes the pick, or the typed answer with no options. */
  readonly id: string;
  /** A short label for the question, when the agent gave one. */
  readonly header?: string;
  /** The question itself. */
  readonly text: string;
  readonly multiSelect: boolean;
  readonly required: boolean;
  /** What is typed is not to be shown. */
  readonly secret?: boolean;
  /** The options to pick from; none for a question answered by typing. */
  readonly options: readonly QuestionOption[];
  /** The text the person may type besides, or instead of, a pick. */
  readonly own?: OwnAnswer;
}

export interface QuestionOption {
  /** What is sent: the option's `const`. */
  readonly value: string;
  readonly title: string;
  readonly description?: string;
  /** claude's preview of what the option makes, not drawn yet. */
  readonly preview?: string;
}

/**
 * A question's own answer, and how it goes with a pick:
 * - `beside`: both are sent, and the agent reads them together;
 * - `instead`: one or the other, as the agent refuses both;
 * - `withValue`: the text goes with `value` as the pick, the option the
 *   agent offers for it, which is taken out of `options`.
 */
export interface OwnAnswer {
  /** The form field the text goes in. */
  readonly field: string;
  readonly mode: 'beside' | 'instead' | 'withValue';
  readonly value?: string;
  /** The field's description, shown while it is empty. */
  readonly placeholder?: string;
}

/** The questions an elicitation request carries, when an enricher read any. */
export function questionsOf(
  request: Pick<CreateElicitationRequest, '_meta'>,
): Questions | undefined {
  const value = recordOf(request._meta?.[QUESTIONS]);

  return typeof value.agent === 'string' && Array.isArray(value.questions)
    ? (value as unknown as Questions)
    : undefined;
}

/** One property of a requested schema, as the readers take it. */
type Property = Readonly<Record<string, unknown>>;

/** A form's properties in order, and which it requires. */
export interface FormFields {
  readonly properties: readonly (readonly [string, Property])[];
  readonly required: ReadonlySet<string>;
}

/** The properties of a form request's schema; none for anything else. */
export function formFields(params: unknown): FormFields | undefined {
  const request = recordOf(params);
  const schema = recordOf(request.requestedSchema);
  const properties = Object.entries(recordOf(schema.properties)).map(
    ([key, value]) => [key, recordOf(value)] as const,
  );

  if (request.mode !== 'form' || properties.length === 0) {
    return undefined;
  }

  return {
    properties,
    required: new Set(
      Array.isArray(schema.required)
        ? schema.required.filter((key) => typeof key === 'string')
        : [],
    ),
  };
}

/** A string, when `value` is a non-empty one. */
export function text(value: unknown): string | undefined {
  return typeof value === 'string' && value !== '' ? value : undefined;
}

/**
 * A property's titled options, and whether it takes several: a string's
 * `oneOf` or an array's `anyOf`, each option a `const`. Anything else, such
 * as a plain `enum` or no options at all, is none, as the readers take only
 * the shapes the adapters send.
 */
export function choices(
  property: Property,
): { options: QuestionOption[]; multiSelect: boolean } | undefined {
  const multiSelect = property.type === 'array';
  const list = multiSelect
    ? recordOf(property.items).anyOf
    : property.type === 'string'
      ? property.oneOf
      : undefined;

  if (!Array.isArray(list) || list.length === 0) {
    return undefined;
  }

  const options: QuestionOption[] = [];

  for (const entry of list.map(recordOf)) {
    const value = entry.const;

    if (typeof value !== 'string') {
      return undefined;
    }

    const description = text(entry.description);
    const meta = recordOf(entry._meta);
    const preview = text(
      recordOf(meta['_claude/askUserQuestionOption']).preview,
    );

    options.push({
      value,
      title: text(entry.title) ?? value,
      ...(description === undefined ? {} : { description }),
      ...(preview === undefined ? {} : { preview }),
    });
  }

  return { options, multiSelect };
}

/** A plain text property, as an own answer or a typed question takes. */
export function isText(property: Property): boolean {
  return (
    property.type === 'string' &&
    property.oneOf === undefined &&
    property.enum === undefined
  );
}

/**
 * What the person gave one question: the options picked, by value; the text
 * typed as the answer to a question with no options; the text typed in its
 * own answer; and, where that text stands for an option (`instead`,
 * `withValue`), whether its row is the one chosen.
 */
export interface QuestionAnswer {
  readonly picks: readonly string[];
  readonly text: string;
  readonly own: string;
  readonly ownChosen: boolean;
}

/**
 * The content an accepted form sends for `answers`, under the agent's own
 * field ids: each pick in its question's field (a list where it takes
 * several), or the text typed for a question with no options; the own text
 * in its own field, beside the pick, instead of it when its row is chosen,
 * or, with `withValue`, with the option it stands for. A question left
 * without an answer sends nothing.
 */
export function answerOf(
  questions: Questions,
  answers: Readonly<Record<string, QuestionAnswer>>,
): Record<string, ElicitationContentValue> {
  const content: Record<string, ElicitationContentValue> = {};

  for (const question of questions.questions) {
    const answer = answers[question.id];

    if (answer === undefined) {
      continue;
    }

    const { own } = question;
    const typed = answer.own.trim();
    const ownSent =
      own !== undefined &&
      typed !== '' &&
      (own.mode === 'beside' || answer.ownChosen);
    const picks =
      own?.mode === 'instead' && ownSent
        ? []
        : own?.mode === 'withValue' && ownSent && own.value !== undefined
          ? [...answer.picks, own.value]
          : [...answer.picks];
    const text = answer.text.trim();

    if (question.options.length === 0) {
      if (text !== '') {
        content[question.id] = text;
      }
    } else if (question.multiSelect) {
      if (picks.length > 0) {
        content[question.id] = picks;
      }
    } else {
      const pick = picks.at(-1);

      if (pick !== undefined) {
        content[question.id] = pick;
      }
    }

    if (ownSent) {
      content[own.field] = typed;
    }
  }

  return content;
}

/**
 * `content` without what was given for a secret question, which must not
 * reach a file: its own field and its own answer's.
 */
export function withoutSecrets(
  questions: Questions | undefined,
  content: Readonly<Record<string, ElicitationContentValue>>,
): Record<string, ElicitationContentValue> {
  const hidden = new Set(
    (questions?.questions ?? []).flatMap((question) =>
      question.secret === true
        ? [question.id, ...(question.own ? [question.own.field] : [])]
        : [],
    ),
  );

  return Object.fromEntries(
    Object.entries(content).filter(([key]) => !hidden.has(key)),
  );
}
