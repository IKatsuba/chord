# CHD-638: three directions for a site-like terminal

The owner asked for the site to look more like a website: "the terminal should
look like a site after all", a hybrid. Each direction below is real chord_tui
widgets compiled with `dart compile wasm` and drawn by wterm 0.6.0 (WebGL) in
headless Chrome. They are not drawings. Everything is still made of cells. The
page's CSS sets the font size, row height and default colours for each
direction, and wterm's padding, radius and shadow are removed so the grid
fills the window. The mock code was scratch work outside the repository and
is not committed.

Captures: desktop is 1440x900 at device pixel ratio 2, phone is 390x844 at
ratio 3. The file names give direction, page and size.

## A. Landing (`a-landing-*`)

A long scrolling landing page, dark, mint-to-violet accent. A three-row nav
bar with numbered items and GitHub, version and `?` on the right. A centred
hero: the wordmark in half-block display type with a colour gradient, a
tagline, two buttons (a filled primary and an outlined secondary, each with
its key under it) and a copyable install line. A framed "screenshot" of a
chord window, then sections in a centred 116-column measure: feature cards,
the framework with highlighted code beside it, install cards and a footer.
A one-column scrollbar sits on the right. The inner page is the gallery, a
3x3 grid of example cards with previews, filter chips and a selected card.
14 px on desktop (about 171x52 cells), 12 px on the phone (about 54 columns),
where the nav folds into `☰ menu m` and everything stacks.

- `a-landing-home-*`: the top of the page.
- `a-landing-home-scrolled-*`: the same page scrolled to the sections.
- `a-landing-gallery-*`: the gallery.

Cost: medium. The current pages turn into section lists inside one
`ListView`, and the shell gets a nav bar and footer. What is new for the
framework: a `Scrollbar` beside a `ScrollController`, a block-letter
display-text widget (a 5x7 bitmap font drawn in half or full blocks), and a
focusable `Button` / link pair with Enter and a key. Jumping to a section
from the nav needs `jumpToAnchor` to a list item, which exists. Equal-height
cards in a row need `CrossAxisAlignment.stretch` with an unbounded height
(`IntrinsicHeight`), or fixed body heights as the mock uses. Keys stay as
they are: the nav numbers, Esc, `?` and scrolling with arrows, PgUp/PgDn
and the wheel.

## B. Docs (`b-docs-*`)

A docs site on paper: light background, ink text, one blue. A top bar with
the name, a search field (`/` focuses it) and section links. A left sidebar
with grouped pages and an active marker. A wide reading column of at most 92
columns with breadcrumbs, `##` headings, a callout, code blocks with a label
and `copy c`, link cards, and a next-page pager (`]`). An "on this page" rail
on the right, which appears from 150 columns up. Home is "Introduction" with
a tinted hero. The inner page is chord_tui's `ListView` reference, with a
live example frame, usage, a parameters table and a "since" diff note. On
the phone the sidebar and rail fold away, and a breadcrumb bar with a
`contents ▾` toggle takes their place.

Cost: medium to large, mostly content. The layout is plain Row, Column and
ListView. What is new: a search field over page titles and headings (fuzzy
matching exists in `fzf.dart`), a sidebar tree with expandable groups (close
to `Fold` plus a list), a page model with anchors that the "on this page"
rail follows as you scroll (the item extents and the anchors exist), and a
light theme for the site. The pages' text would naturally come from
markdown that the existing `Markdown` widget draws, with a docs theme
(heading rules, callouts, framed code).

## C. Poster (`c-poster-*`)

Editorial and loud: ink black, cream type, one signal orange. A thin top line
with numbered sections (`01 APP …`) in caps. A giant `CHORD.` in full-block
display type, 14 rows tall and filling the width. A short statement, a
full-width orange band of slogans, and four numbered columns with
half-block numerals. The inner page is "01 / The app": a giant `APP.`, an
index of facts between rules on the left, and a cream "Fig. 1" panel on the
right showing a permission ask, laid out like a photo plate. 17 px on desktop
(fewer, bigger cells). On the phone the display word breaks as `CHO` /
`RD.` and the columns stack.

Cost: small to medium. It is the fewest widgets: the display-text widget
from A, bands as `DecoratedBox` backgrounds, and rules. The pages are short
and mostly static. The "Fig." panels can be real `Playback` frames of
chord's recordings, which exist already. The risk is reading: the caps-heavy
style suits a landing page, and suits long text such as the framework guide
less well.

## Recommendation

A for the front of the site (home, chord, gallery, install), and B's
sidebar-and-reading-column layout for chord_tui's framework pages behind it,
both on A's dark palette. A reads as a website at first sight and still
shows chord's own screens inside it. B is the right shape for reference text,
and the current pages already hold that text. C is the most striking, but it
reads poorly once there is more than a paragraph. Its display type and
orange band could still serve A's hero if the owner wants it louder.

The framework widgets this needs, which A and C share:

- display text in block cells (a bitmap font in half or full blocks, with a
  per-cell colour),
- a `Scrollbar` for a `ScrollController`,
- a focusable `Button` and a `Link`, each with Enter and an optional key.

A page-level `ListView` of sections with anchors for the nav already exists
(`jumpToAnchor`).

Known mock shortcuts, not design: equal card heights are fixed body heights;
the "window" title is drawn in the theme's dim border colour; the cells
are 14 px on desktop (A and B), 17 px (C) and 12 px on the phone.
