'''gewis-minutes-watcher — regenerate a meeting's minutes.typ outline from
its agenda.typ's own heading structure, via TINO's API, whenever a commit
touches that agenda.typ. Also carries a completed meeting's still-open
action items forward into the *next* meeting, once, the first time that
meeting is seen.

Design notes (see the nix-config service that runs this):

- A "meeting" is any directory, at any depth inside any TINO bucket except
  the reserved `packages` one, that itself contains both agenda.typ and
  minutes.typ — not a bucket of its own. One committee's bucket can hold
  many meetings this way (e.g. `2026/61/`, `2026/62/`), sharing one
  committee-info.typ at the bucket root that each meeting imports via a
  relative path (`"../../committee-info.typ"`) — the gewis-meeting
  template no longer dictates a fixed nesting depth, just that the pair
  sits together somewhere under a bucket. Add a new meeting by copying the
  template's agenda.typ/minutes.typ into a new directory; nothing else to
  register.
- Every `typst` invocation below passes `--root <bucket>` for exactly this
  reason: Typst sandboxes relative imports to a project root, and without
  it a meeting's own `"../../committee-info.typ"` fails with "path would
  escape the project root" the moment it's nested below the bucket's own
  top level (confirmed empirically — a bare `--in` with no `--root` uses
  the input file's *own* directory as the root, which a relative import
  reaching for a shared file above it can never satisfy).
- Reads (detecting new commits, extracting agenda.typ's headings, reading
  minutes.typ's current content for the merge) go straight to the
  filesystem — this runs on the same host as TINO, so that's just a local
  read, no reason to round-trip through HTTP for it.
- Writes go through TINO's own REST API (PUT .../files/{path}) with the
  file path relative to the *bucket*, not the meeting directory (e.g.
  `2026/62/minutes.typ`), authenticated with a TINO API key — the same
  write path the editor's own save button uses, so TINO's app layer
  (path validation, git-status view) sees the change exactly like a
  human edit. Deliberately PUT-only, no POST /git/commit: the file
  lands in the bucket's working tree as an unsaved modification and
  *committing stays a human action in TINO's UI* — the watcher used to
  commit as `apikey:...`, which put machine authorship in the
  committee's document history; now it just prepares the change and
  whoever reviews it presses commit. (Cost, accepted: the PUT route
  doesn't broadcast the `files-changed` websocket event the commit
  route does, so an open TINO tab refreshes its git-status badge only
  on its next interaction — the editor buffer itself was never
  force-reloaded by that event anyway, and a stale editor save would
  clobber the regeneration with or without the commit.)
- The merge is by heading *title*, not position: existing prose under a
  heading survives verbatim as long as that heading's title still exists
  somewhere in the agenda. A renamed point starts a fresh (empty) section
  rather than silently carrying old notes onto an unrelated heading, and a
  removed point's notes are simply dropped along with the heading — the
  agenda is the source of truth for structure.
- Point titles must be plain text — no Typst code/interpolation in the
  heading itself (e.g. `= Minutes of the previous meeting`, not
  `= Minutes #ordinal(n) meeting`). agenda_headings() below reads titles
  *rendered* (via `typst eval`, which evaluates any interpolation), but
  existing_sections() reads minutes.typ's current titles from raw *source*
  text (a plain regex over `= ` lines, deliberately — mapping a compiled
  heading's location back to a source byte range isn't something Typst's
  query API exposes). A title that differs between rendered and source
  form can never match itself across a regeneration, silently orphaning
  whatever prose was under it. Put anything dynamic in the body instead.
- Only the region between the "BEGIN GENERATED OUTLINE" / "END GENERATED
  OUTLINE" markers in minutes.typ is ever rewritten; the preamble (imports,
  page style, meeting-title/presence) and the appendix (action-item-list/
  decision-list) are untouched.

Carrying action items forward, separately:

- gewis-agenda-page/gewis-minutes-page publish each meeting's resolved
  chair/meeting-number (<gewis-meeting-info>) and action-item-list()
  publishes its resolved rows — id/deadline/owner/description, *raw*, not
  display-formatted (<gewis-open-action-items>) — as queryable Typst
  metadata. Meeting order is determined from meeting-number, not a
  directory's name or creation time, and scoped to meetings sharing the
  *same bucket* — two different committees each numbering their own
  meetings from 1 must never be treated as one series just because they
  happen to sort adjacently.
- A `datetime` value round-trips through `typst eval`'s own JSON
  serialization as the literal Typst source that constructs it (confirmed
  empirically: `{"deadline": "datetime(year: 2026, month: 7, day: 1)"}`),
  so it's reused verbatim rather than reconstructed by hand; a plain
  string deadline serializes as just that string. A `person` is a plain
  {first, prefix, last} dict either way, reconstructed as a person(...)
  call — Typst dictionaries compare structurally, not by identity, so a
  freshly-reconstructed person() is `==` to the committee-info.typ value
  it was resolved from, and short-name()'s collision detection still
  works.
- This only ever runs *once* per meeting (tracked in state as
  "<bucket>/<rel path>:carried"), the first time that meeting's previous
  one is found to actually have open items recorded — not on every poll —
  so a secretary who has since deleted a resolved item from
  open-action-items by hand never sees it silently reappear. If the
  previous meeting's minutes.typ exists but has no action points recorded
  yet (still being written), this is left as *not yet settled* and
  retried on a later poll rather than treated as "nothing to carry,
  forever."
- Only the region between "BEGIN CARRIED ACTION ITEMS" / "END CARRIED
  ACTION ITEMS" markers is touched, in both agenda.typ and minutes.typ —
  the same reasoning as the outline markers above. minutes.typ's pair
  sits *inside* the outline region (under the "Action points" heading);
  the outline-sync mechanism treats that heading's whole body as opaque
  existing prose to preserve, so the two mechanisms don't conflict.
'''

import json
import logging
import os
import re
import subprocess
import time
import urllib.error
import urllib.request
from dataclasses import dataclass
from pathlib import Path

BUCKETS_DIR = Path(
    os.environ.get('TINO_BUCKET_DIR', '/var/lib/tino/buckets'))
PACKAGE_DIR = Path(
    os.environ.get('TINO_PACKAGE_DIR', BUCKETS_DIR / 'packages'))
STATE_FILE = Path(
    os.environ.get(
        'WATCHER_STATE_FILE', '/var/lib/gewis-minutes-watcher/state.json'))
TINO_URL = os.environ.get('TINO_URL', 'http://127.0.0.1:3040')
POLL_SECONDS = int(os.environ.get('WATCHER_POLL_SECONDS', '60'))
API_KEY = os.environ['TINO_API_KEY']

BEGIN_MARKER = '// BEGIN GENERATED OUTLINE'
END_MARKER = '// END GENERATED OUTLINE'
CARRIED_BEGIN = '// BEGIN CARRIED ACTION ITEMS'
CARRIED_END = '// END CARRIED ACTION ITEMS'

logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s %(levelname)s %(message)s')
log = logging.getLogger('gewis-minutes-watcher')


@dataclass(frozen=True)
class Meeting:
    '''One agenda.typ+minutes.typ pair. `bucket` is the TINO bucket (and
    git repository) it lives under; `dir` is the meeting's own directory,
    which may be the bucket root itself or nested arbitrarily deep.
    '''
    bucket: Path
    dir: Path

    @property
    def rel(self) -> Path:
        '''This meeting's directory, relative to its bucket — `.` if the
        meeting *is* the bucket root.
        '''
        return self.dir.relative_to(self.bucket)

    @property
    def key(self) -> str:
        '''Identity used for state-file keys and log lines — stable
        across polls regardless of what TINO calls the bucket internally.
        '''
        if self.rel == Path('.'):
            return self.bucket.name
        return f'{self.bucket.name}/{self.rel.as_posix()}'

    def path(self, filename: str) -> Path:
        return self.dir / filename

    def api_path(self, filename: str) -> str:
        '''This meeting's file path relative to the *bucket* — what TINO's
        file-write API expects, as opposed to `path()` above which is an
        absolute filesystem path for local reads.
        '''
        return filename if self.rel == Path(
            '.') else f'{self.rel.as_posix()}/{filename}'


def flatten(node) -> str:
    '''Turn a Typst content JSON node (as returned by `typst eval --format
    json`) back into plain text. A heading's body is a single `text` leaf
    for a plain title, but becomes a `sequence` of leaves the moment it
    contains anything Typst treats specially (e.g. "&"), so this has to
    walk the tree rather than assume `.text` is always present.
    '''
    if isinstance(node, str):
        return node
    func = node.get('func')
    if func == 'text':
        return node.get('text', '')
    if func == 'sequence':
        return ''.join(flatten(c) for c in node.get('children', ()))
    if func == 'space':
        return ' '
    return node.get('text', '')


def typst_eval_json(meeting: Meeting, filename: str, expression: str):
    '''Run `typst eval <expression> --in <meeting's file> --root <bucket>
    --format json` and parse the result. Shared by every query below —
    agenda headings, meeting info, open action items. `--root` is the
    meeting's *bucket*, not its own directory, so a nested meeting's
    relative import of a shared committee-info.typ above it can resolve —
    see the module docstring.
    '''
    proc = subprocess.run(
        [
            'typst', 'eval', expression,
            '--in', str(meeting.path(filename)),
            '--root', str(meeting.bucket),
            '--package-path', str(PACKAGE_DIR),
            '--format', 'json',
        ],
        capture_output=True, text=True, check=True,
    )
    return json.loads(proc.stdout)


def agenda_headings(meeting: Meeting) -> list[dict]:
    '''Query agenda.typ's own heading structure directly — this is the
    entire point of using plain headings instead of a bespoke data format:
    nothing here needs to understand GEWIS's document model, only Typst's.
    '''
    raw = typst_eval_json(meeting, 'agenda.typ', 'query(heading)')
    return [{'level': h['level'], 'title': flatten(h['body'])} for h in raw]


def meeting_info(meeting: Meeting,
                 filename: str = 'agenda.typ') -> dict | None:
    '''gewis-agenda-page/gewis-minutes-page publish `meeting.get()`
    unconditionally, so this is None only if the file doesn't use one of
    those page shells at all (not a real GEWIS meeting document).
    '''
    raw = typst_eval_json(meeting, filename, 'query(<gewis-meeting-info>)')
    return raw[0]['value'] if raw else None


def open_action_items(meeting: Meeting) -> list[dict]:
    '''action-item-list() only publishes <gewis-open-action-items> if it
    actually found at least one action point figure to build a table
    from — so an empty result here is the ordinary "no action points were
    recorded in this meeting" case, not an error.
    '''
    raw = typst_eval_json(
        meeting,
        'minutes.typ',
        'query(<gewis-open-action-items>)')
    return raw[0]['value'] if raw else []


def last_commit_touching(meeting: Meeting, filename: str) -> str | None:
    proc = subprocess.run(
        ['git', '-C', str(meeting.bucket), 'log', '-1',
         '--format=%H', '--', meeting.api_path(filename)],
        capture_output=True, text=True,
    )
    return proc.stdout.strip() or None


HEADING_RE = re.compile(r'^(=+) (.+)$', re.MULTILINE)


def existing_sections(generated_region: str) -> dict[str, str]:
    '''Map heading title -> its body (everything up to the next heading)
    from the *current* generated region of minutes.typ, so regenerating
    doesn't discard prose that's already been written.
    '''
    matches = list(HEADING_RE.finditer(generated_region))
    sections = {}
    for i, m in enumerate(matches):
        title = m.group(2).strip()
        start = m.end()
        end = matches[i + 1].start() if i + \
            1 < len(matches) else len(generated_region)
        sections[title] = generated_region[start:end].strip('\n')
    return sections


def render_generated_region(
        headings: list[dict], existing: dict[str, str]) -> str:
    lines = []
    for h in headings:
        lines.append(f'{"=" * h["level"]} {h["title"]}')
        body = existing.get(h['title'], '').strip()
        if body:
            lines.append(body)
        lines.append('')
    return '\n'.join(lines).rstrip('\n')


def replace_marked_region(text: str, begin: str, end: str,
                          new_region: str) -> str | None:
    '''Returns None if the markers aren't both present (a hand-edited file
    that opted out of auto-generation — leave it alone rather than
    guessing), the same convention regenerate_minutes() already used.
    '''
    if begin not in text or end not in text:
        return None
    before, rest = text.split(begin, 1)
    _, after = rest.split(end, 1)
    return f'{before}{begin}\n{new_region}\n{end}{after}'


def regenerate_minutes(minutes_text: str, headings: list[dict]) -> str | None:
    if BEGIN_MARKER not in minutes_text or END_MARKER not in minutes_text:
        return None
    region = minutes_text.split(BEGIN_MARKER, 1)[1].split(END_MARKER, 1)[0]
    new_region = render_generated_region(headings, existing_sections(region))
    return replace_marked_region(
        minutes_text, BEGIN_MARKER, END_MARKER, new_region)


def typst_string(s: str) -> str:
    '''A Typst string literal. Typst's own escapes for "..." (quotes,
    backslash) match JSON's closely enough for our purposes that reusing
    json.dumps is safe rather than hand-rolling an escaper.
    '''
    return json.dumps(s)


def typst_person(value) -> str:
    '''`owner` came back from meta.value as either a plain string or the
    {first, prefix, last} shape person() always produces — reconstructed
    as a person() call rather than a bare dict literal so it reads like
    something a human would actually write.
    '''
    if isinstance(value, str):
        return typst_string(value)
    parts = [typst_string(value['first'])]
    if value.get('prefix') is not None:
        parts.append(f'prefix: {typst_string(value["prefix"])}')
    if value.get('last') is not None:
        parts.append(f'last: {typst_string(value["last"])}')
    return f'person({", ".join(parts)})'


def typst_deadline(value) -> str:
    if isinstance(value, str) and value.startswith('datetime('):
        return value  # already valid Typst source, see module docstring
    return typst_string(value)


def render_actionpoint_call(row: dict) -> str:
    return (
        '  actionpoint(\n'
        f'    id: {typst_string(row["id"])},\n'
        f'    deadline: {typst_deadline(row["deadline"])},\n'
        f'    owner: {typst_person(row["owner"])},\n'
        f'    description: {typst_string(row["description"])},\n'
        '  ),\n'
    )


def render_open_action_items(rows: list[dict]) -> str:
    if not rows:
        return '()'
    return '(\n' + ''.join(render_actionpoint_call(r) for r in rows) + ')'


def api_request(method: str, path: str, body: dict | None = None) -> dict:
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        f'{TINO_URL}{path}',
        data=data,
        method=method,
        headers={
            'Authorization': f'Bearer {API_KEY}',
            'Content-Type': 'application/json',
        },
    )
    with urllib.request.urlopen(req, timeout=10) as resp:
        return json.loads(resp.read() or b'{}')


def write_files_via_api(meeting: Meeting, files: dict[str, str]) -> None:
    '''`files` maps filename (e.g. "minutes.typ") to new content — turned
    into bucket-relative paths here so every caller just thinks in terms
    of the meeting's own two files. PUT-only, no commit: see the module
    docstring — the change lands as an unsaved working-tree
    modification, committing stays a human action in TINO's UI.
    '''
    for filename, content in files.items():
        api_request('PUT',
                    f'/api/buckets/{
                        meeting.bucket.name}/files/{
                        meeting.api_path(filename)}',
                    {'content': content})


def load_state() -> dict:
    if STATE_FILE.exists():
        return json.loads(STATE_FILE.read_text())
    return {}


def save_state(state: dict) -> None:
    STATE_FILE.parent.mkdir(parents=True, exist_ok=True)
    STATE_FILE.write_text(json.dumps(state))


def all_meetings() -> list[Meeting]:
    '''Every meeting across every bucket — see Meeting's own docstring for
    what makes a directory count as one. `packages` is reserved (it's
    where gewis's own Typst packages live, not a committee's documents).
    '''
    if not BUCKETS_DIR.is_dir():
        return []
    meetings = []
    for bucket in sorted(BUCKETS_DIR.iterdir()):
        if bucket.name == 'packages' or not bucket.is_dir():
            continue
        for agenda_path in sorted(bucket.rglob('agenda.typ')):
            meeting_dir = agenda_path.parent
            if (meeting_dir / 'minutes.typ').is_file():
                meetings.append(Meeting(bucket=bucket, dir=meeting_dir))
    return meetings


def find_previous_meeting(meeting: Meeting,
                          siblings: list[Meeting]) -> Meeting | None:
    '''The meeting with the highest meeting-number strictly less than this
    one's, among meetings in the *same bucket* only — two different
    committees numbering their own meetings from 1 must never be treated
    as one series just because they happen to share a poll cycle. Order
    comes from each meeting's own queryable meeting-number, not its
    directory name or creation time (either of which could be anything).
    '''
    current = meeting_info(meeting)
    if current is None:
        return None
    best, best_number = None, None
    for other in siblings:
        if other.bucket != meeting.bucket or other.dir == meeting.dir:
            continue
        info = meeting_info(other)
        if info is None:
            continue
        n = info['meeting-number']
        if n < current['meeting-number'] and (
                best_number is None or n > best_number):
            best, best_number = other, n
    return best


def carry_forward_action_items(
        meeting: Meeting, siblings: list[Meeting]) -> str:
    '''Populates this meeting's open-action-items (agenda.typ) and
    minutes-actionlist() argument (minutes.typ) from the previous
    meeting's still-open items, if any. Returns 'done' (settled — a
    caller should stop retrying, whether or not anything was written),
    or 'pending' (the previous meeting exists but has no action points
    recorded yet — worth checking again on a later poll).
    '''
    prev = find_previous_meeting(meeting, siblings)
    if prev is None:
        return 'done'  # no earlier meeting, and numbering is fixed
    rows = open_action_items(prev)
    if not rows:
        return 'pending'

    block = render_open_action_items(rows)
    agenda_text = meeting.path('agenda.typ').read_text()
    new_agenda = replace_marked_region(
        agenda_text,
        CARRIED_BEGIN,
        CARRIED_END,
        f'#let open-action-items = {block}',
    )
    minutes_text = meeting.path('minutes.typ').read_text()
    new_minutes = replace_marked_region(
        minutes_text,
        CARRIED_BEGIN,
        CARRIED_END,
        f'#minutes-actionlist({block})',
    )

    changed = {}
    if new_agenda is not None and new_agenda != agenda_text:
        changed['agenda.typ'] = new_agenda
    if new_minutes is not None and new_minutes != minutes_text:
        changed['minutes.typ'] = new_minutes
    if changed:
        write_files_via_api(meeting, changed)
    return 'done'


def poll_once(state: dict) -> None:
    meetings = all_meetings()

    for meeting in meetings:
        carried_key = f'{meeting.key}:carried'
        if not state.get(carried_key):
            try:
                result = carry_forward_action_items(meeting, meetings)
            except (
                subprocess.CalledProcessError,
                urllib.error.URLError,
                OSError,
            ) as exc:
                log.error(
                    '%s: carrying action items forward failed: %s',
                    meeting.key, exc,
                )
            else:
                if result == 'done':
                    state[carried_key] = True
                    save_state(state)
                    log.info(
                        '%s: open action items carried (or none to carry)',
                        meeting.key,
                    )

    for meeting in meetings:
        commit = last_commit_touching(meeting, 'agenda.typ')
        if commit is None or state.get(meeting.key) == commit:
            continue

        log.info(
            '%s: agenda.typ changed (%s), regenerating minutes.typ',
            meeting.key, commit[:12],
        )
        try:
            headings = agenda_headings(meeting)
            minutes_text = meeting.path('minutes.typ').read_text()
            new_text = regenerate_minutes(minutes_text, headings)
            if new_text is None:
                log.warning(
                    '%s: minutes.typ has no OUTLINE markers, skipping',
                    meeting.key,
                )
            elif new_text == minutes_text:
                log.info(
                    '%s: outline unchanged, nothing to write',
                    meeting.key)
            else:
                write_files_via_api(
                    meeting, {'minutes.typ': new_text})
                log.info('%s: minutes.typ updated', meeting.key)
        except (
            subprocess.CalledProcessError,
            urllib.error.URLError,
            OSError,
        ) as exc:
            log.error('%s: regeneration failed: %s', meeting.key, exc)
            continue  # leave state untouched, retried next poll

        state[meeting.key] = commit
        save_state(state)


def main() -> None:
    state = load_state()
    log.info('watching %s every %ss', BUCKETS_DIR, POLL_SECONDS)
    while True:
        poll_once(state)
        time.sleep(POLL_SECONDS)


if __name__ == '__main__':
    main()
