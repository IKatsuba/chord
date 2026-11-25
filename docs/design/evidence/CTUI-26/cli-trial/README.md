# Optional resume argument trial

The existing port dependency is args 2.7.0. Its public ArgParser.addOption
has no optional-value setting: mandatory controls presence of the option,
not whether a present option may omit its value. The retained probe was
compiled with dart compile exe against the port's package configuration;
the resulting binary produced result.txt. No production file was changed.
The source is retained as text because this is a design-only task.

This shows both the missing optional argument and the last-value-wins
repeat policy. Neither matches the original resume flag. Main approved
one bounded token adapter for -r/--resume before args. The ship unit must
freeze the original CLI oracle before implementing it; the trial is not
runtime proof of the future adapter.

oracle.json is observed output from the original chordCommand declarations
at commit 577b58167672e12c999aeaf4eed2a1a988513dc2, with noExit/throwErrors
and a recording action, following its tests/cli_test.ts. No agent started.
The retained Bun oracle script accepts the checkout as an argument.
Cases include accepted oddities: --resume=c and --resume=-r ask for a picker,
--resume= leaves resume absent, --agent-command --resume treats the latter
as the command value, and tokens after -- are not adapted. These are parser
observations; future port assertions must preserve its existing approved
help/unknown-option differences while matching this flag's accepted scope.
