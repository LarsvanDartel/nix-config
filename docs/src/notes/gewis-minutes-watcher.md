# gewis-minutes-watcher

Source: `modules/den/aspects/services/_gewis/minutes-watcher.py`.

## Meetings

A meeting is any directory under a TINO bucket (except `packages`, which holds Typst packages) that holds both `agenda.typ` and `minutes.typ`. A bucket may nest many meetings that share a `committee-info.typ` at the bucket root. The previous meeting is the one with the highest lower meeting number in the *same bucket*; directory names and ctimes are not trusted for order.

## Typst root

Every `typst` call passes `--root <bucket>`. Without it Typst roots at the input file's directory, and a nested meeting's `"../../committee-info.typ"` import fails with "path would escape the project root".

## Writes

Writes are PUT-only through TINO's API and never committed: committing stays a human action in TINO's UI. The API key therefore has *editor* access only. Only marker-delimited regions are rewritten; a file missing either marker has opted out. `minutes.typ`'s CARRIED pair sits inside the OUTLINE region under "Action points", whose body the outline merge preserves as opaque prose.

## Outline merge

The merge matches headings by *title*: a renamed point starts empty and a removed point drops its notes. Point titles must be plain text, because agenda titles are read rendered but minutes titles from raw source; an interpolated title never matches and orphans its prose.

## Carrying action items

Open action items are carried from the previous meeting once per meeting (state key `<key>:carried`), so hand-deleted items never reappear. If the previous minutes have no action points yet, carrying is retried later rather than settled. `typst eval` serializes a datetime as its constructing Typst source (`datetime(year: ..., ...)`), which is reused verbatim; reconstructed `person()` values compare structurally equal, so `short-name()` collision detection still works.
