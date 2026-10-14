/**
 * Layout rules Prettier cannot express: it preserves blank lines but never
 * inserts them, and it does not move imports. `eslint --fix` applies the
 * blank-line fixes; misplaced imports are reported only.
 */

import type { TSESLint, TSESTree } from '@typescript-eslint/utils';

type Node = TSESTree.Node;
type Context = TSESLint.RuleContext<string, []>;
type Rule = TSESLint.RuleModule<string, []>;

const BLANK_LINE = /\n[ \t]*\r?\n/;

/** A rule's metadata: one message, and whether `--fix` applies it. */
function meta(message: string, fixable = true): Rule['meta'] {
  return {
    type: 'layout',
    docs: { description: message },
    ...(fixable ? { fixable: 'whitespace' as const } : {}),
    messages: { blank: message },
    schema: [],
  };
}

function siblings(node: Node): readonly Node[] | undefined {
  const parent = node.parent as Record<string, unknown> | undefined;

  if (!parent) {
    return undefined;
  }

  if (parent.type === 'SwitchCase') {
    return parent.consequent as Node[];
  }

  return Array.isArray(parent.body) ? (parent.body as Node[]) : undefined;
}

function previous(node: Node): Node | undefined {
  const list = siblings(node);
  const index = list?.indexOf(node) ?? -1;

  return index > 0 ? list![index - 1] : undefined;
}

/** The declared statement, looking through `export`. */
function declared(node: Node): Node {
  if (
    (node.type === 'ExportNamedDeclaration' ||
      node.type === 'ExportDefaultDeclaration') &&
    node.declaration !== null
  ) {
    return node.declaration;
  }

  return node;
}

function isDeclaration(node: Node): boolean {
  const type = declared(node).type;

  return type === 'VariableDeclaration' || type === 'FunctionDeclaration';
}

function isVariables(node: Node): boolean {
  return declared(node).type === 'VariableDeclaration';
}

/** Requires a blank line between `before` and `node`, ignoring comments. */
function requireBlankLine(
  context: Context,
  before: Node,
  node: Node,
  messageId = 'blank',
): void {
  const text = context.sourceCode.text;
  const gap = text.slice(before.range[1], node.range[0]);

  if (BLANK_LINE.test(gap)) {
    return;
  }

  const lineEnd = gap.indexOf('\n');

  if (lineEnd === -1) {
    return;
  }

  const at = before.range[1] + lineEnd;

  context.report({
    node,
    messageId,
    fix: (fixer) => fixer.insertTextAfterRange([at, at], '\n'),
  });
}

const importsFirst: Rule = {
  meta: meta('Imports must come before any other statement.', false),
  defaultOptions: [],
  create(context) {
    return {
      Program(program) {
        let seenCode = false;

        for (const statement of program.body) {
          if (statement.type !== 'ImportDeclaration') {
            seenCode = true;
          } else if (seenCode) {
            context.report({ node: statement, messageId: 'blank' });
          }
        }
      },
    };
  },
};

const blankAfterImports: Rule = {
  meta: meta('Blank line required after the import block.'),
  defaultOptions: [],
  create(context) {
    return {
      Program(program) {
        const body = program.body;
        const last = body.findLastIndex((s) => s.type === 'ImportDeclaration');

        if (last === -1 || last === body.length - 1) {
          return;
        }

        requireBlankLine(context, body[last]!, body[last + 1]!);
      },
    };
  },
};

const blankBeforeExit: Rule = {
  meta: {
    ...meta('Blank line required before return.'),
    messages: {
      return: 'Blank line required before return.',
      throw: 'Blank line required before throw.',
    },
  },
  defaultOptions: [],
  create(context) {
    const check = (node: Node) => {
      const before = previous(node);

      if (before) {
        requireBlankLine(
          context,
          before,
          node,
          node.type === 'ReturnStatement' ? 'return' : 'throw',
        );
      }
    };

    return {
      ReturnStatement: check,
      ThrowStatement: check,
    };
  },
};

const blankBeforeDeclaration: Rule = {
  meta: meta('Blank line required before a declaration block.'),
  defaultOptions: [],
  create(context) {
    const check = (node: Node) => {
      if (!isDeclaration(node)) {
        return;
      }

      const before = previous(node);

      // Only consecutive variable declarations form one block; every function
      // stands apart. Imports are covered by blank-after-imports.
      if (
        !before ||
        (isVariables(node) && isVariables(before)) ||
        before.type === 'ImportDeclaration'
      ) {
        return;
      }

      requireBlankLine(context, before, node);
    };

    return {
      VariableDeclaration: check,
      FunctionDeclaration: check,
      ExportNamedDeclaration: check,
      ExportDefaultDeclaration: check,
    };
  },
};

const blankBeforeControlFlow: Rule = {
  meta: meta('Blank line required before a control-flow statement.'),
  defaultOptions: [],
  create(context) {
    const check = (node: Node) => {
      const before = previous(node);

      // An `else if` has no previous sibling, so it is never reported.
      if (!before || before.type === 'ImportDeclaration') {
        return;
      }

      requireBlankLine(context, before, node);
    };

    return {
      IfStatement: check,
      ForStatement: check,
      ForInStatement: check,
      ForOfStatement: check,
      WhileStatement: check,
      DoWhileStatement: check,
      SwitchStatement: check,
      TryStatement: check,
    };
  },
};

const CONTROL_FLOW = new Set([
  'IfStatement',
  'ForStatement',
  'ForInStatement',
  'ForOfStatement',
  'WhileStatement',
  'DoWhileStatement',
  'SwitchStatement',
  'TryStatement',
]);

/** Whether an earlier rule already requires a blank line between the pair. */
function coveredBefore(before: Node, node: Node): boolean {
  return (
    before.type === 'ImportDeclaration' ||
    node.type === 'ReturnStatement' ||
    node.type === 'ThrowStatement' ||
    CONTROL_FLOW.has(node.type) ||
    (isDeclaration(node) && !(isVariables(node) && isVariables(before)))
  );
}

/**
 * Walks every statement list once the whole tree is known, so block ends can
 * be told apart from object-literal braces.
 */
function afterRule(
  requires: (
    before: Node,
    node: Node,
    blockEnds: Set<number>,
    text: string,
  ) => boolean,
  message: string,
): Rule {
  return {
    meta: meta(message),
    defaultOptions: [],
    create(context) {
      const lists: (readonly Node[])[] = [];
      const blockEnds = new Set<number>();
      const block = (node: Node) => {
        blockEnds.add(node.range[1]);
      };

      return {
        Program(node) {
          lists.push(node.body);
        },
        BlockStatement(node) {
          block(node);
          lists.push(node.body);
        },
        StaticBlock(node) {
          block(node);
          lists.push(node.body);
        },
        SwitchCase(node) {
          lists.push(node.consequent);
        },
        ClassBody: block,
        SwitchStatement: block,
        'Program:exit'() {
          for (const list of lists) {
            for (let i = 1; i < list.length; i++) {
              const before = list[i - 1]!;
              const node = list[i]!;

              if (
                !coveredBefore(before, node) &&
                requires(before, node, blockEnds, context.sourceCode.text)
              ) {
                requireBlankLine(context, before, node);
              }
            }
          }
        },
      };
    },
  };
}

/**
 * Ends with the closing brace of a block, ignoring trailing `)` and `;`, so
 * callback-style calls such as `test(() => { ... });` count as blocks.
 */
function isBlockLike(
  node: Node,
  text: string,
  blockEnds: Set<number>,
): boolean {
  if (node.type === 'DoWhileStatement') {
    return true;
  }

  const source = text
    .slice(node.range[0], node.range[1])
    .replace(/[);\s]+$/, '');

  return source.endsWith('}') && blockEnds.has(node.range[0] + source.length);
}

const blankAfterDeclaration = afterRule(
  (before, node) => isVariables(before) && !isVariables(node),
  'Blank line required after a variable block.',
);

const blankAfterBlock = afterRule(
  (before, node, blockEnds, text) =>
    // A block-bodied variable is already handled as a variable block.
    !(isVariables(before) && !isVariables(node)) &&
    isBlockLike(before, text, blockEnds),
  'Blank line required after a block.',
);

function isAssignment(node: Node): boolean {
  return (
    node.type === 'ExpressionStatement' &&
    node.expression.type === 'AssignmentExpression'
  );
}

const blankAroundAssignment = afterRule(
  (before, node, blockEnds, text) =>
    isAssignment(before) !== isAssignment(node) &&
    !(isVariables(before) && !isVariables(node)) &&
    !isBlockLike(before, text, blockEnds),
  'Blank line required between assignments and other statements.',
);

const plugin = {
  meta: { name: 'style' },
  rules: {
    'imports-first': importsFirst,
    'blank-after-imports': blankAfterImports,
    'blank-before-exit': blankBeforeExit,
    'blank-before-declaration': blankBeforeDeclaration,
    'blank-before-control-flow': blankBeforeControlFlow,
    'blank-after-declaration': blankAfterDeclaration,
    'blank-after-block': blankAfterBlock,
    'blank-around-assignment': blankAroundAssignment,
  },
} satisfies TSESLint.FlatConfig.Plugin;

export default plugin;
