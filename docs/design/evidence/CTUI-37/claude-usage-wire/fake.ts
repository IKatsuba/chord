// A fake `claude` for recording what SDK 0.3.325 sends for the usage
// getter: logs argv, the SDK-related environment and every stdin line,
// and answers the two control requests. No real claude, no network.
const [log, ...argv] = Deno.args;
const keep = /CLAUDE|SDK|NODE_OPTIONS|DEBUG/;
const env = Object.fromEntries(
  Object.entries(Deno.env.toObject()).filter(([name]) => keep.test(name)),
);
await Deno.writeTextFile(log, JSON.stringify({ argv, env }) + "\n");

const out = (line: unknown) =>
  Deno.stdout.writeSync(new TextEncoder().encode(JSON.stringify(line) + "\n"));

const decoder = new TextDecoderStream();
let rest = "";
for await (const chunk of Deno.stdin.readable.pipeThrough(decoder)) {
  rest += chunk;
  let at;
  while ((at = rest.indexOf("\n")) >= 0) {
    const line = rest.slice(0, at);
    rest = rest.slice(at + 1);
    if (line.trim() === "") continue;
    await Deno.writeTextFile(log, line + "\n", { append: true });
    const message = JSON.parse(line);
    if (message.type !== "control_request") continue;
    const response = message.request.subtype === "initialize"
      ? {
        commands: [],
        agents: [],
        models: [],
        account: {},
        output_style: "default",
        available_output_styles: ["default"],
      }
      : {
        rate_limits_available: true,
        rate_limits: { five_hour: { utilization: 1, resets_at: null } },
      };
    out({
      type: "control_response",
      response: { subtype: "success", request_id: message.request_id, response },
    });
  }
}
await Deno.writeTextFile(log, "EOF\n", { append: true });
