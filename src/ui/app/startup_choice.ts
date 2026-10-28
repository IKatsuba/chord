/** Only a new unnamed interactive start asks for an agent. */
export function chooseAgentAtStart({
  named,
  agentCommand,
  print,
  continue: continuing,
  resume,
  stdinTTY,
  stdoutTTY,
}: {
  named: string | undefined;
  agentCommand?: string | undefined;
  print?: string | undefined;
  continue?: boolean | undefined;
  resume?: string | true | undefined;
  stdinTTY: boolean;
  stdoutTTY: boolean;
}): boolean {
  return (
    named === undefined &&
    agentCommand === undefined &&
    print === undefined &&
    !continuing &&
    resume === undefined &&
    stdinTTY &&
    stdoutTTY
  );
}
