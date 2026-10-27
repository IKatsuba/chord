/** A native-compiled fake for the official SDK's documented control messages. */
import split from 'split2';
import process from 'node:process';
import { appendFileSync, writeFileSync } from 'node:fs';

const scenario = process.env.CHORD_FAKE_CLAUDE_SCENARIO ?? 'normal';
const record = process.env.CHORD_FAKE_CLAUDE_RECORD;
let lateRequest: string | undefined;

function usage() {
  return {
    rate_limits_available: true,
    rate_limits: {
      five_hour: { utilization: 0, resets_at: null },
      seven_day: { utilization: 25.125, resets_at: '2026-10-28T13:00:00Z' },
    },
  };
}

if (record !== undefined) {
  writeFileSync(record, JSON.stringify({ pid: process.pid }) + '\n');
}

if (scenario === 'stubborn') {
  process.on('SIGTERM', () => {});

  setInterval(() => {}, 1000);
}

if (scenario === 'late') {
  setInterval(() => {}, 1000);
  process.stdout.on('error', () => {});

  process.on('SIGTERM', () => {
    if (lateRequest !== undefined) {
      if (record !== undefined) {
        appendFileSync(record, JSON.stringify({ lateResponse: true }) + '\n');
      }

      process.stdout.write(
        JSON.stringify({
          type: 'control_response',
          response: {
            subtype: 'success',
            request_id: lateRequest,
            response: usage(),
          },
        }) + '\n',
      );
    }
  });
}

process.stderr.write('private SDK stderr fixture must not escape\n');

process.stdin.pipe(split()).on('data', (line: string) => {
  const message = JSON.parse(line) as {
    type: string;
    request_id?: string;
    request?: { subtype: string; skip_behaviors?: boolean };
  };

  if (record !== undefined) {
    appendFileSync(
      record,
      JSON.stringify({
        type: message.type,
        subtype: message.request?.subtype,
        skipBehaviors: message.request?.skip_behaviors,
      }) + '\n',
    );
  }

  if (message.type !== 'control_request' || message.request === undefined) {
    return;
  }

  if (
    scenario === 'init-hang' ||
    scenario === 'stubborn' ||
    (scenario === 'getter-hang' && message.request.subtype === 'get_usage')
  ) {
    return;
  }

  if (scenario === 'late' && message.request.subtype === 'get_usage') {
    lateRequest = message.request_id;

    return;
  }

  const response =
    message.request.subtype === 'initialize'
      ? {
          commands: [],
          agents: [],
          models: [],
          account: {},
          output_style: 'default',
          available_output_styles: ['default'],
        }
      : scenario === 'unavailable'
        ? { rate_limits_available: false, rate_limits: null }
        : scenario === 'null-windows'
          ? {
              rate_limits_available: true,
              rate_limits: { five_hour: null, seven_day: null },
            }
          : usage();

  process.stdout.write(
    JSON.stringify({
      type: 'control_response',
      response: {
        subtype: 'success',
        request_id: message.request_id,
        response,
      },
    }) + '\n',
  );
});

process.stdin.on('end', () => {
  if (scenario !== 'stubborn' && scenario !== 'late') {
    process.exit(0);
  }
});
