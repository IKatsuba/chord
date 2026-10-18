/**
 * The question forms the adapters send, each laid out as that adapter's
 * source lays it out, shared by the fake agent's scenarios that ask them and
 * the tests that read them: claude-agent-acp 0.93.0's AskUserQuestion,
 * codex-acp 2.2.2's `request_user_input`, factory-droid 0.236.0's, opencode's
 * and dimcode's.
 */
import type { CreateElicitationRequest } from '@agentclientprotocol/sdk';

/** A form request, before the session it goes to is named. */
export type QuestionForm = Omit<
  Extract<CreateElicitationRequest, { mode: 'form' }>,
  'sessionId'
>;

const OTHER_SINGLE =
  'Type your own answer, or add a note to the option you chose above (optional).';
const OTHER_MULTI =
  'Type your own answer to add to your selection above (optional).';

/** claude, two questions, the second taking several picks. */
export const CLAUDE_QUESTIONS: QuestionForm = {
  mode: 'form',
  message: 'Please answer the following questions.',
  requestedSchema: {
    type: 'object',
    properties: {
      question_0: {
        type: 'string',
        title: 'Language',
        description: 'Which language should helper scripts use?',
        oneOf: [
          {
            const: 'Deno (TypeScript) (Recommended)',
            title: 'Deno (TypeScript) (Recommended)',
            description:
              'Runs from source with inline npm: and jsr: imports, no package manager',
          },
          {
            const: 'Python',
            title: 'Python',
            description: 'Only where a library has no JS or TS equivalent',
            _meta: {
              '_claude/askUserQuestionOption': { preview: 'print("hi")' },
            },
          },
        ],
      },
      question_0_custom: {
        type: 'string',
        title: 'Other',
        description: OTHER_SINGLE,
      },
      question_1: {
        type: 'array',
        title: 'Checks',
        description: 'Which checks should run before a commit?',
        items: {
          anyOf: [
            { const: 'Types', title: 'Types' },
            { const: 'Lint', title: 'Lint' },
            { const: 'Tests', title: 'Tests' },
          ],
        },
      },
      question_1_custom: {
        type: 'string',
        title: 'Other',
        description: OTHER_MULTI,
      },
    },
  },
};

/** claude, one question, which is the message. */
export const CLAUDE_QUESTION: QuestionForm = {
  mode: 'form',
  message: 'Which language should helper scripts use?',
  requestedSchema: {
    type: 'object',
    properties: {
      question_0: {
        type: 'string',
        title: 'Language',
        oneOf: [
          { const: 'Deno', title: 'Deno' },
          { const: 'Python', title: 'Python' },
        ],
      },
      question_0_custom: {
        type: 'string',
        title: 'Other',
        description: OTHER_SINGLE,
      },
    },
  },
};

/**
 * codex, a question with options and its note, and a secret typed one; codex
 * answers for the person after five minutes.
 */
export const CODEX_QUESTIONS: QuestionForm = {
  mode: 'form',
  message: 'Codex needs your input to continue.',
  _meta: { codex: { autoResolutionMs: 300_000 } },
  requestedSchema: {
    type: 'object',
    properties: {
      next: {
        type: 'string',
        title: 'What would you like to focus on next?',
        description: 'Next step',
        _meta: { codex: { isOther: true, isSecret: false } },
        oneOf: [
          {
            const: 'Plan a change (Recommended)',
            title: 'Plan a change (Recommended)',
          },
          {
            const: 'Review existing work',
            title: 'Review existing work',
            description: 'Read what is there first',
          },
          {
            const: 'None of the above',
            title: 'None of the above',
            description: 'Provide a different answer in the note field.',
          },
        ],
      },
      next_note: {
        type: 'string',
        title: 'Additional answer or note',
        _meta: {
          codex: { questionId: 'next', role: 'user_note', isSecret: false },
        },
      },
      token: {
        type: 'string',
        title: 'Paste the API token for the staging deploy.',
        description: 'Token',
        _meta: { codex: { isOther: false, isSecret: true } },
      },
    },
    required: ['next', 'token'],
  },
};

/**
 * factory-droid, a question with its `other` answer, one taking several
 * picks, and a typed one.
 */
export const DROID_QUESTIONS: QuestionForm = {
  mode: 'form',
  message: 'Droid needs your answers to continue.',
  requestedSchema: {
    type: 'object',
    properties: {
      question_0: {
        type: 'string',
        title: 'Storage',
        description: 'Where should uploads be kept?',
        oneOf: [
          { const: 'option_0', title: 'Local disk' },
          { const: 'option_1', title: 'S3 bucket' },
          { const: 'other', title: 'Other answer' },
        ],
      },
      question_0_other: { type: 'string', title: 'Storage: Other answer' },
      question_1: {
        type: 'array',
        title: 'Formats',
        description: 'Which formats should be accepted?',
        minItems: 1,
        uniqueItems: true,
        items: {
          anyOf: [
            { const: 'option_0', title: 'PNG' },
            { const: 'option_1', title: 'JPEG' },
            { const: 'other', title: 'Other answer' },
          ],
        },
      },
      question_1_other: { type: 'string', title: 'Formats: Other answer' },
      question_2: {
        type: 'string',
        title: 'Bucket',
        description: 'What should the bucket be called?',
        minLength: 1,
      },
    },
    required: ['question_0', 'question_1', 'question_2'],
  },
};

/** opencode, one question with its own answer. */
export const OPENCODE_QUESTIONS: QuestionForm = {
  mode: 'form',
  message: 'Questions',
  requestedSchema: {
    type: 'object',
    properties: {
      q0: {
        type: 'string',
        title: 'Tests',
        description: 'Where should the new tests go?',
        oneOf: [
          {
            const: 'Beside the module',
            title: 'Beside the module',
            description: 'tests/ mirrors src/',
          },
          { const: 'In one file', title: 'In one file' },
        ],
      },
      q0_custom: { type: 'string', title: '(other)' },
    },
  },
};

/** dimcode, one question whose own answer stands instead of a pick. */
export const DIMCODE_QUESTIONS: QuestionForm = {
  mode: 'form',
  message: 'Please answer the following questions.',
  _meta: {
    lody: {
      elicitation: {
        questions: [
          {
            id: 'deploy',
            header: 'Deploy',
            question: 'Where should it deploy?',
            options: [{ label: 'Staging' }, { label: 'Production' }],
          },
        ],
      },
    },
  },
  requestedSchema: {
    type: 'object',
    properties: {
      deploy: {
        type: 'string',
        title: 'Deploy',
        description: 'Where should it deploy?',
        oneOf: [
          { const: 'Staging', title: 'Staging' },
          { const: 'Production', title: 'Production' },
        ],
      },
      __custom_0: {
        type: 'string',
        title: 'Deploy: custom answer',
        _meta: { lody: { elicitation: { customAnswerFor: 'deploy' } } },
      },
    },
  },
};
