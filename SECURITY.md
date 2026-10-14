# Security

## Reporting a vulnerability

Please do not open a public issue. Report it privately through GitHub's
[security advisories](https://github.com/IKatsuba/chord/security/advisories/new)
for this repository, with what you found, how to reproduce it, and the
version of chord (`chord --version`).

You will hear back within a week. Once a fix is released, the advisory is
published with credit to you, unless you would rather not be named.

## Supported versions

Fixes go into the latest release only. `chord upgrade` installs it.

## What is in scope

chord runs agents on your machine and gives them what you allow: it answers
their permission requests through you, serves its own MCP server to them on
the loopback with a token per session, runs the shell commands you and they
start, and keeps session records in its state directory. A way for an agent
or another local process to get past any of that is in scope.

What an agent itself does with the permissions you grant it is that agent's
own matter, and goes to its maintainers.
