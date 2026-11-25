// Drives SDK 0.3.325 with exactly the original's resource_worker.ts options
// against ./fake-claude: initialize, the usage getter, close.
import { query } from "npm:@anthropic-ai/claude-agent-sdk@0.3.325";

const here = new URL(".", import.meta.url).pathname;
const input = Promise.withResolvers<void>();
async function* noMessages() {
  await input.promise;
}

const reading = query({
  prompt: noMessages(),
  options: {
    cwd: here,
    pathToClaudeCodeExecutable: here + "fake-claude",
    settingSources: [],
    persistSession: false,
    strictMcpConfig: true,
    mcpServers: {},
    tools: [],
    settings: { disableAllHooks: true },
    stderr: () => {},
  },
});
await reading.initializationResult();
const usage = await reading
  .usage_EXPERIMENTAL_MAY_CHANGE_DO_NOT_RELY_ON_THIS_API_YET({
    skipBehaviors: true,
  });
console.log(JSON.stringify(usage));
input.resolve();
reading.close();
