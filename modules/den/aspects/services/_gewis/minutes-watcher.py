'''gewis-minutes-watcher — regenerate a meeting's minutes.typ outline from
its agenda.typ headings whenever a commit touches agenda.typ, and carry a
previous meeting's open action items forward once.

- A meeting is any directory under a TINO bucket (except `packages`) holding
  both agenda.typ and minutes.typ; buckets may nest many meetings sharing a
  committee-info.typ at the bucket root.
- Every `typst` call passes `--root <bucket>`: without it Typst roots at the
  input file's directory and a nested meeting's `"../../committee-info.typ"`
  import fails with "path would escape the project root".
- Writes are PUT-only through TINO's API, never committed: committing stays a
  human action in TINO's UI (machine-authored commits polluted history).
- The outline merge is by heading *title*: renamed points start empty,
  removed points drop their notes.
- Point titles must be plain text: agenda titles are read rendered but
  minutes titles from raw source, so interpolated titles never match and
  orphan their prose.
- Previous meeting = highest lower meeting-number in the *same bucket*.
- `typst eval` serializes a datetime as its constructing Typst source
  (`datetime(year: ..., ...)`), reused verbatim. Reconstructed person()
  values compare structurally equal, so short-name() collision detection
  still works.
- Carrying runs once per meeting (state key "<key>:carried") so hand-deleted
  items never reappear; if the previous minutes have no action points yet
  it's retried later rather than settled.
- Only marker-delimited regions are rewritten. minutes.typ's CARRIED pair
  sits inside the OUTLINE region under "Action points", whose body the
  outline merge preserves as opaque prose.
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
    '''`dir` may be the bucket root itself or nested arbitrarily deep.'''
    bucket: Path
    dir: Path

    @property
    def rel(self) -> Path:
        '''`.` if the meeting *is* the bucket root.'''
        return self.dir.relative_to(self.bucket)

    @property
    def key(self) -> str:
        '''State-file key and log label.'''
        if self.rel == Path('.'):
            return self.bucket.name
        return f'{self.bucket.name}/{self.rel.as_posix()}'

    def path(self, filename: str) -> Path:
        return self.dir / filename

    def api_path(self, filename: str) -> str:
        '''Path relative to the *bucket*, as TINO's file API expects.'''
        return filename if self.rel == Path(
            '.') else f'{self.rel.as_posix()}/{filename}'


def flatten(node) -> str:
    '''Turn a Typst content JSON node back into plain text. Headings with
    special characters (e.g. "&") become a `sequence`, not a `text` leaf.
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
    '''`typst eval` with `--root` at the bucket — see module docstring.'''
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
    '''Query agenda.typ's heading structure.'''
    raw = typst_eval_json(meeting, 'agenda.typ', 'query(heading)')
    return [{'level': h['level'], 'title': flatten(h['body'])} for h in raw]


def meeting_info(meeting: Meeting,
                 filename: str = 'agenda.typ') -> dict | None:
    '''None if the file doesn't use a gewis page shell.'''
    raw = typst_eval_json(meeting, filename, 'query(<gewis-meeting-info>)')
    return raw[0]['value'] if raw else None


def open_action_items(meeting: Meeting) -> list[dict]:
    '''Empty when no action points were recorded — not an error.'''
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
    '''Map heading title -> body in minutes.typ's current generated region.'''
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
    '''None if either marker is missing: a hand-edited file opted out.'''
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
    '''Typst's string escapes match JSON's closely enough for json.dumps.'''
    return json.dumps(s)


def typst_person(value) -> str:
    '''`owner` is a plain string or person()'s {first, prefix, last} dict.'''
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
    '''`files` maps meeting filename -> content. PUT-only, no commit.'''
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
    '''Every meeting across every bucket; `packages` holds Typst packages.'''
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
    '''Highest lower meeting-number in the *same bucket* only — committees
    each number from 1. Directory names/ctimes are not trusted for order.
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
    '''Fill this meeting's carried regions from the previous meeting's open
    items. Returns 'done' (settled) or 'pending' (previous meeting has no
    action points yet; retry later).
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
