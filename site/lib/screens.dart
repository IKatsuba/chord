/// What each of chord's recorded screens shows, after the README's and the
/// guide's descriptions of their pictures; in the order the site lists them.
const screenCaptions = {
  'start': 'the title page above the agent picker',
  'team': 'an issue handed to a team: lead, coder, tester, reviewer',
  'proposal': 'a proposed team, and where to save it',
  'edit': 'an Edit tool call drawn as a coloured diff',
  'permission': 'the permission prompt: allow, always allow, deny',
  'subagents': 'two subagents running in parallel under one block',
  'agents': 'the agents list, with one waiting on a permission',
  'resume': 'chord --resume, above the earlier sessions',
  'codeblocks': "a reply's code blocks, with copy and run buttons",
  'fork': 'a fork beside main in the agents list',
};

/// The recordings the site has, in [screenCaptions]' order, unknown names
/// after it.
List<String> orderedScreens(Iterable<String> names) => [
  for (final name in screenCaptions.keys)
    if (names.contains(name)) name,
  for (final name in names)
    if (!screenCaptions.containsKey(name)) name,
];
