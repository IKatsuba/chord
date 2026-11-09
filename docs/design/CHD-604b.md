# CHD-604b: riff's read, list and search, and their asks

CHD-485 ('The session', 'Permission prompts') settles how riff's calls and
asks look, and gives the "for this session" words for edit, write and shell
only. This settles the words for `read`, `list` and `search`, the three
tools of this slice, and how their rows and boxes read. Everything else is
CHD-485's: the box is the existing permission prompt, the rows the existing
renderer's, nothing new in `theme.ts`.

## What each grant covers

As the slice builds it (developer, confirmed by the lead):

| Tool | A session grant covers |
| --- | --- |
| `read` | that file's real path, any range |
| `list` | the real path of the directory the call names, that directory only |
| `search` | the same, its own grant: a list grant does not cover search |

`list` and `search` take no path of their own (fff's pattern and query
carry it), so their directory is always the session's: a grant covers every
list, or every search, in this session. No grant is a prefix grant.

## The words

Each option says exactly what the grant covers, the way edit's and shell's
do:

| Ask | Option 2 |
| --- | --- |
| read inside the directory | `Allow reads of src/greeting.ts for this session` |
| read outside it (ask, and auto until part 6) | `Allow reads of ~/notes/todo.md for this session` |
| list | `Allow every list in this directory for this session` |
| search | `Allow every search in this directory for this session` |

The path is the real path the grant holds, relative to the session's
directory inside it, `~`-shortened outside it, absolute otherwise; so a
symlink inside the project that points out shows where it points.
"Every … in this directory" says plainly that the grant is not for this one
pattern or query; "this directory" and not a path, since there is no other.
Option 1 is `Allow`, option 3 `Deny`, Esc rejects, as for every ask.

## The rows

Each tool sends a verb-first title, so the renderer draws the name from it
(`src/ui/transcript/tools/tools.ts`, `VERB_FIRST`):

| Tool | Title | Row |
| --- | --- | --- |
| `read` | `Read src/greeting.ts` | `⏺ Read(src/greeting.ts)` |
| `read`, a range | `Read src/greeting.ts:10-40` | `⏺ Read(src/greeting.ts:10-40)` |
| `read`, one line | `Read src/greeting.ts:10` | `⏺ Read(src/greeting.ts:10)` |
| `read` through a link | `Read docs/notes.txt → ~/.ssh/id_rsa` | `⏺ Read(docs/notes.txt → ~/.ssh/id_rsa)` |
| `list` | `List src/**/*.ts` | `⏺ List(src/**/*.ts)` |
| `search` | `Search welcome` | `⏺ Search(welcome)` |

The result under `⎿` is what the renderer already draws for a read and a
search from any agent; nothing riff-specific.

## Read in ask, 120x40, the rows that change

```text
 ⏺ Read(src/greeting.ts)
   ⎿  Waiting…

 ››› Waiting for permission… (2s)

╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Read src/greeting.ts                                                                                                 │
│                                                                                                                      │
│ Do you want to proceed?                                                                                              │
│ ❯ 1. Allow                                                                                                           │
│   2. Allow reads of src/greeting.ts for this session                                                                 │
│   3. Deny                                                                                                            │
│                                                                                                                      │
│ Esc to reject                                                                                                        │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
```

## Search in ask, 80x24, the whole window

```text
 › where is greeting used

 ⏺ List(src/**/*.ts)
   ⎿  Found 3 files

 ⏺ Search(greeting)
   ⎿  Waiting…

 ››› Waiting for permission… (3s)

╭──────────────────────────────────────────────────────────────────────────────╮
│ Search greeting                                                              │
│ /work/app                                                                    │
│                                                                              │
│ Do you want to proceed?                                                      │
│ ❯ 1. Allow                                                                   │
│   2. Allow every search in this directory for this session                   │
│   3. Deny                                                                    │
│                                                                              │
│ Esc to reject                                                                │
╰──────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                        ask · gpt-6.1-sol · medium · 4% context
```

A list's box is the same with `List src/**/*.ts` and `Allow every list in
this directory for this session`.

A list's and a search's box keep the location line the existing box draws
under the title: the session's directory, absolute as ACP's locations are
(`/work/app` above stands for it). It says which directory "this
directory" is. A read's box has no location line: its title already names
the file, and the box drops a location the title repeats.

## A read through a link that points elsewhere

When the real path differs from the path asked for (a link inside the
project pointing out, or a link in the path itself, such as macOS's `/etc`
to `/private/etc`), the title names both, the asked path, ` → `, and the
real path, so a person choosing plain `Allow` sees where it points. The
real path is spelled as option 2 spells it; the row carries the same title.
A link inside the directory that points out is an outside read, so auto
asks for it too.

120x40, the box:

```text
╭──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╮
│ Read docs/notes.txt → ~/.ssh/id_rsa                                                                                  │
│                                                                                                                      │
│ Do you want to proceed?                                                                                              │
│ ❯ 1. Allow                                                                                                           │
│   2. Allow reads of ~/.ssh/id_rsa for this session                                                                   │
│   3. Deny                                                                                                            │
│                                                                                                                      │
│ Esc to reject                                                                                                        │
╰──────────────────────────────────────────────────────────────────────────────────────────────────────────────────────╯
```

80x24, a title too long for the row: it wraps at its spaces as the box wraps
any title, so the arrow ends the first row and the real path takes the next,
at the title's indent; a path longer than a whole row breaks at the row's
edge. Nothing is cut or shortened with `…`: the person must see the whole
real path.

```text
╭──────────────────────────────────────────────────────────────────────────────╮
│ Read docs/reference/generated/api-notes.txt →                                │
│ ~/work/shared/secrets/api-notes.txt                                          │
│                                                                              │
│ Do you want to proceed?                                                      │
│ ❯ 1. Allow                                                                   │
│   2. Allow reads of ~/work/shared/secrets/api-notes.txt for this session     │
│   3. Deny                                                                    │
│                                                                              │
│ Esc to reject                                                                │
╰──────────────────────────────────────────────────────────────────────────────╯
```

## A read outside the directory in auto, 80x24, the whole window

Auto admits reads inside the directory with no ask. Until part 6 brings the
safety review, a read outside it asks as ask mode does, with the same three
options and no rationale. Part 6 replaces this box with CHD-485's held-review
box (`Allow once`, `Deny`, the reviewer's rationale) when the review
cautions.

```text
 › compare with my notes

 ⏺ Read(~/notes/todo.md)
   ⎿  Waiting…

 ››› Waiting for permission… (4s)

╭──────────────────────────────────────────────────────────────────────────────╮
│ Read ~/notes/todo.md                                                         │
│                                                                              │
│ Do you want to proceed?                                                      │
│ ❯ 1. Allow                                                                   │
│   2. Allow reads of ~/notes/todo.md for this session                         │
│   3. Deny                                                                    │
│                                                                              │
│ Esc to reject                                                                │
╰──────────────────────────────────────────────────────────────────────────────╯

╭──────────────────────────────────────────────────────────────────────────────╮
│ ›                                                                            │
╰──────────────────────────────────────────────────────────────────────────────╯
  ? for shortcuts                       auto · gpt-6.1-sol · medium · 4% context
```

## States

- **Empty, streaming**: as any agent's (CHD-485 'The session').
- **Waiting on the person**: the boxes above; `››› Waiting for
  permission…` as today.
- **Denied**: the row's `⎿` says the call was denied, as for any agent.
- **Error** (a binary file, a missing path, a refused symlink swap): the
  tool's error text under `⎿`, coloured `error` as any failed call.
- **Narrow**: a long path in option 2 wraps inside the box under its own
  text, as the existing box wraps any option; nothing is cut.

## Colour roles

As CHD-485: the box's border, title and `❯` `permission`; the `⎿` dim.

## Keys

Nothing new: `1–9`, `↑ ↓`, `enter` choose, `esc` rejects, `shift+tab`
toggles ask and auto, as listed today.

## Compared with

The fake agent's write ask on origin/main at both sizes,
`main-fake-write-ask-120x40.png` and `main-fake-write-ask-80x24.png` under
`docs/design/evidence/CHD-604b/`: riff's boxes keep its layout, and only the
second option's words differ (`Always allow` there is the fake's own).
