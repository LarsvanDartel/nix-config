#!/usr/bin/env python3
# git-remote-tino — git remote helper bridging git to a TINO bucket's REST API; see docs/src/notes/git-remote-tino.md#usage.

import json
import os
import subprocess
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

DEFAULT_BASE = 'https://tino.lvdar.nl'
BRANCH = 'master'
# Server-side cap on the log endpoint (routers/git.py, le=500); refuse rather than silently
# truncate history past it.
LOG_PAGE = 500


def log(msg: str) -> None:
    '''Helper protocol errors go to stderr (gitremote-helpers(7)).'''
    print(f'git-remote-tino: {msg}', file=sys.stderr, flush=True)


class Tino:
    '''The REST half of the bridge: one bucket on one TINO server.'''

    def __init__(self) -> None:
        url_base, key, slug = self._parse_url()
        self.base = (url_base or self._configured_base()).rstrip('/')
        self.slug = slug
        self.key = key or self._key_from_env_or_file()
        if not self.key:
            raise SystemExit(
                'no API key: set TINO_API_KEY, put one in '
                '~/.config/tino/api-key, or use tino://<key>@host/<bucket>')

    @staticmethod
    def _parse_url() -> tuple[str | None, str | None, str]:
        # git passes `<remote> <url>` (url `tino::<bucket>` or `tino://[key@]host/<bucket>`), or only
        # the remote when found via remote.<name>.vcs. Only `tino://` carries a base.
        url = sys.argv[2] if len(sys.argv) > 2 else sys.argv[1]
        if url.startswith('tino://'):
            rest = url[len('tino://'):]
            key = None
            if '@' in rest:
                key, rest = rest.split('@', 1)
            host, _, path = rest.partition('/')
            return f'https://{host}', key, path.strip('/')
        if url.startswith('tino::'):
            return None, None, url[len('tino::'):]
        return None, None, url

    @staticmethod
    def _configured_base() -> str:
        '''`TINO_URL` env, then `git config tino.url` (git itself layers
        repo-local over --global, so this one lookup already respects
        both), then the public default. A bare git-config lookup with no
        repository in scope just fails closed to the default — this
        runs from the repo being cloned/fetched/pushed, so there always
        is one.
        '''
        env = os.environ.get('TINO_URL')
        if env:
            return env
        proc = subprocess.run(
            ['git', 'config', '--get', 'tino.url'],
            capture_output=True, text=True, check=False)
        if proc.returncode == 0 and proc.stdout.strip():
            return proc.stdout.strip()
        return DEFAULT_BASE

    @staticmethod
    def _key_from_env_or_file() -> str | None:
        key = os.environ.get('TINO_API_KEY')
        if key:
            return key
        cfg = Path(os.environ.get('XDG_CONFIG_HOME', '~/.config')).expanduser()
        key_file = cfg / 'tino' / 'api-key'
        if key_file.is_file():
            return key_file.read_text().strip()
        return None

    def request(self, path: str, body: dict | None = None,
                method: str = 'GET') -> object:
        '''One REST call. 401/403/404 are fatal: the helper protocol
        says print to stderr and exit, and continuing after an auth
        rejection would only produce a more confusing failure later.
        '''
        req = urllib.request.Request(
            f'{self.base}{path}',
            data=json.dumps(body).encode() if body is not None else None,
            method=method,
            headers={
                'Authorization': f'Bearer {self.key}',
                'Content-Type': 'application/json',
            },
        )
        try:
            with urllib.request.urlopen(req, timeout=30) as resp:
                raw = resp.read()
            return json.loads(raw) if raw else None
        except urllib.error.HTTPError as exc:
            raise SystemExit(
                f'{method} {path}: HTTP {exc.code} {exc.reason} — '
                f'is the API key valid and {self.slug} accessible to it?'
            ) from exc

    def log(self) -> list[dict]:
        '''Newest-first commit list. Refuses truncated history.'''
        commits = self.request(
            f'/api/buckets/{self.slug}/git/log?max_count={LOG_PAGE}')
        assert isinstance(commits, list)
        if len(commits) == LOG_PAGE:
            raise SystemExit(
                f'bucket {self.slug} has more than {LOG_PAGE} commits; '
                'the log endpoint caps there and this helper would '
                'truncate history')
        return commits

    def changed(self, sha: str) -> list[str]:
        out = self.request(f'/api/buckets/{self.slug}/git/changed/{sha}')
        assert isinstance(out, list)
        return out

    def show(self, sha: str, path: str) -> bytes | None:
        '''File content at a commit; None = not present (deleted).'''
        out = self.request(
            f'/api/buckets/{self.slug}/git/show/{sha}/content/'
            f'{self._qp(path)}')
        if out is None or out.get('content') is None:
            return None
        if out.get('binary'):
            raise SystemExit(
                f'{path}@{sha[:8]} is binary; this bridge is text-only '
                '(TINO decodes show() as UTF-8 and GEWIS documents are '
                'Typst source)')
        return out['content'].encode()

    @staticmethod
    def _qp(path: str) -> str:
        '''Percent-encode a repo path for a URL path segment, keeping `/`
        (FastAPI's {path:path} routes capture the decoded remainder incl.
        slashes) — without this, a file named "notes with spaces.txt"
        makes http.client reject the URL outright.
        '''
        return urllib.parse.quote(path, safe='/')

    def put(self, path: str, content: bytes) -> None:
        self.request(
            f'/api/buckets/{self.slug}/files/{self._qp(path)}',
            {'content': content.decode()},
            method='PUT')

    def delete(self, path: str) -> None:
        self.request(
            f'/api/buckets/{self.slug}/files/{self._qp(path)}',
            method='DELETE')

    def commit(self, files: list[str], message: str) -> dict:
        out = self.request(
            f'/api/buckets/{self.slug}/git/commit',
            {'files': files, 'message': message},
            method='POST')
        assert isinstance(out, dict)
        return out


def _actor_parts(author: str) -> tuple[str, str]:
    '''"Name <email>" -> (name, email); bare names get TINO's own
    `<name>@tino` fallback so the fast-import line always parses.
    '''
    if '<' in author and author.endswith('>'):
        name, email = author[:-1].rsplit('<', 1)
        return name.strip() or 'TINO', email.strip()
    return author.strip() or 'TINO', f'{author.strip() or "tino"}@tino'


def _epoch(timestamp: str) -> tuple[int, str]:
    '''ISO timestamp -> (epoch, +HHMM offset) for fast-import.'''
    from datetime import datetime
    dt = datetime.fromisoformat(timestamp)
    offset = dt.strftime('%z') or '+0000'
    return int(dt.timestamp()), offset


class Stream:
    '''Binary stdout wrapper speaking fast-import's data-block format:
    every payload is `data <byte-length>\\n<raw bytes>`.
    '''

    def __init__(self) -> None:
        self.out = sys.stdout.buffer

    def line(self, text: str) -> None:
        self.out.write(text.encode() + b'\n')

    def data(self, payload: bytes) -> None:
        self.out.write(f'data {len(payload)}\n'.encode() + payload)

    def message(self, text: str) -> None:
        self.data(text.encode())


def emit_import(tino: Tino, ref: str) -> None:
    '''One deterministic fast-import stream for the whole bucket history.

    Writes the branch git asked for (refs/heads/master, per the
    advertised refspec *:*) *and* resets the private refs/tino/<slug>/
    master marker to the same tip — gitremote-helpers(7) explicitly
    allows an import to touch other refs, and the marker is what push
    later replays from.
    '''
    commits = tino.log()          # newest first
    stream = Stream()
    stream.line('feature done')

    for mark, c in enumerate(reversed(commits), start=1):
        sha, message = c['sha'], c['message']
        name, email = _actor_parts(c['author'])
        epoch, offset = _epoch(c['timestamp'])

        stream.line(f'commit {ref}')
        stream.line(f'mark :{mark}')
        stream.line(f'author {name} <{email}> {epoch} {offset}')
        stream.line(f'committer {name} <{email}> {epoch} {offset}')
        stream.message(message + '\n')

        # The root commit's contents come from the whole tree (as the server's changed_files() does);
        # every later one from its own diff.
        paths = (tino.changed(sha) if mark > 1
                 else _root_paths(tino, sha))
        for path in paths:
            content = tino.show(sha, path)
            if content is None:
                stream.line(f'D {path}')
            else:
                stream.line(f'M 100644 inline {path}')
                stream.data(content)

    if commits:
        # The private marker push base, pointing at the same tip git is
        # importing (marks, not SHAs — our SHAs are never the server's).
        stream.line(f'reset refs/tino/{tino.slug}/{BRANCH}')
        stream.line(f'from :{len(commits)}')
    stream.line('done')
    stream.out.flush()
    _remember_tip(tino, commits[0]['sha'] if commits else '')


def _root_paths(tino: Tino, sha: str) -> list[str]:
    out = tino.request(f'/api/buckets/{tino.slug}/git/tree/{sha}')
    assert isinstance(out, list)
    return out


def _tip_cache(tino: Tino) -> Path:
    '''Server-tip sha cached at the last import/push, for the
    `unchanged` attribute on list. Lives under GIT_DIR so it is per
    repository, like the private marker ref.
    '''
    git_dir = os.environ.get('GIT_DIR', '.git')
    return Path(git_dir) / f'tino-remote-{tino.slug}.tip'


def _remember_tip(tino: Tino, sha: str) -> None:
    _tip_cache(tino).write_text(sha)


def _git(*args: str, text: bool = True) -> str:
    proc = subprocess.run(
        ['git', *args], capture_output=True, text=text, check=False)
    if proc.returncode != 0:
        raise SystemExit(
            f'git {" ".join(args)} failed: '
            f'{proc.stderr.strip() if text else proc.stderr!r}')
    return proc.stdout


def do_push(tino: Tino, specs: list[str]) -> list[tuple[str, str]]:
    '''Replay local commits onto the bucket, one server commit per local
    commit, in order. Returns (status, dst) pairs for the protocol
    reply. Fast-forward only: the bucket's history must be exactly what
    we last materialized (refs/tino/<slug>/master), because TINO's
    commit route has no merge and no force — it just snapshots whatever
    files the request lists onto the current server head.
    '''
    marker = f'refs/tino/{tino.slug}/{BRANCH}'
    results = []
    # One bucket, one branch: any refs/heads/* destination lands on master (an empty-bucket clone
    # names its branch after init.defaultBranch); two source branches in one batch are refused.
    sources = set()
    for spec in specs:
        body = spec[1:] if spec.startswith('+') else spec
        src, _, _dst = body.partition(':')
        sources.add(src)
    if len(sources) > 1:
        return [('refs/heads/master',
                 'the bucket is a single branch; push one branch at a time')]

    for spec in specs:
        forced = spec.startswith('+')
        body = spec[1:] if forced else spec
        src, _, dst = body.partition(':')

        if not src or not dst.startswith('refs/heads/'):
            results.append((dst or spec,
                            'only pushing a branch is supported '
                            '(deleting remote refs is not)'))
            continue
        if forced:
            results.append((dst, 'forced push is not supported '
                            '(TINO has no force; fetch and rebase instead)'))
            continue

        local = _git('rev-parse', '--verify', src).strip()
        if not _ref_exists(marker):
            # No materialized base: fatal for a bucket with history, but an empty one replays every
            # local commit from the root.
            if tino.log():
                results.append((dst, f'no {marker} — run `git fetch` '
                                'first so the push base is known'))
                continue
            shas = _git('rev-list', '--reverse', local).split()
            for sha in shas:
                _replay_commit(tino, sha)
            _git('update-ref', marker, local)
            results.append((dst, 'ok'))
            continue
        base = _git('rev-parse', marker).strip()
        if not _is_ancestor(base, local):
            results.append((dst, 'non-fast-forward: the bucket has '
                            'commits this repo has not materialized — '
                            'fetch and rebase first'))
            continue

        for sha in _git('rev-list', '--reverse',
                        f'{base}..{local}').split():
            _replay_commit(tino, sha)
        _git('update-ref', marker, local)
        results.append((dst, 'ok'))

    # The server tip after a replay is whatever TINO says it is — ask
    # it, so the next list/fetch sees the true state.
    commits = tino.log()
    _remember_tip(tino, commits[0]['sha'] if commits else '')
    return results


def _marker_sha(tino: Tino) -> str | None:
    '''The materialized-tip sha from the private marker ref, or None when
    this repository has never imported/pushed the bucket.
    '''
    proc = subprocess.run(
        ['git', 'rev-parse', '--verify', '--quiet',
         f'refs/tino/{tino.slug}/{BRANCH}'],
        capture_output=True, text=True)
    if proc.returncode != 0:
        return None
    return proc.stdout.strip() or None


def _ref_exists(ref: str) -> bool:
    return subprocess.run(
        ['git', 'rev-parse', '--verify', '--quiet', ref],
        capture_output=True).returncode == 0


def _is_ancestor(older: str, newer: str) -> bool:
    return subprocess.run(
        ['git', 'merge-base', '--is-ancestor', older, newer],
        capture_output=True).returncode == 0


def _replay_commit(tino: Tino, sha: str) -> None:
    '''One local commit -> PUT/DELETE its files, then one server commit
    listing exactly those paths (TINO's commit stages existing files
    and drops listed-but-absent ones, so the deletion case works too).
    '''
    message = _git('log', '-1', '--format=%B', sha).rstrip('\n')
    changed, removed = [], []
    # -z keeps paths with spaces or newlines intact; --root lists a first commit's files;
    # no -M, so a rename is a delete + add pair, which TINO needs.
    raw = _git('diff-tree', '-r', '--root', '--no-commit-id', '-z',
               sha, text=False)
    fields = raw.split(b'\0')
    for i in range(0, len(fields) - 1, 2):
        meta, path = fields[i], fields[i + 1]
        if not meta.startswith(b':') or not path:
            continue
        status = meta.rsplit(b' ', 1)[-1][:1].decode()
        path = path.decode('utf-8', 'surrogateescape')
        if status == 'D':
            removed.append(path)
        else:
            changed.append(path)

    for path in changed:
        blob = _git('cat-file', 'blob', f'{sha}:{path}', text=False)
        tino.put(path, blob)
    for path in removed:
        tino.delete(path)

    tino.commit(changed + removed, message)


def main() -> None:
    tino = Tino()
    say = sys.stdout

    imports: list[str] = []
    pushes: list[str] = []

    def flush_imports() -> None:
        if not imports:
            return
        # All `import` lines of a batch share one stream: there is only refs/heads/master.
        emit_import(tino, f'refs/heads/{BRANCH}')
        imports.clear()

    def flush_pushes() -> None:
        if not pushes:
            return
        for dst, why in do_push(tino, pushes):
            if why == 'ok':
                say.write(f'ok {dst}\n')
            else:
                say.write(f'error {dst} {why}\n')
        say.write('\n')
        say.flush()
        pushes.clear()

    while True:
        line = sys.stdin.readline()
        if not line:
            break
        cmd = line.strip()
        if not cmd:
            # Batch terminator: blank line after import/push commands.
            flush_imports()
            flush_pushes()
            continue
        parts = cmd.split()

        if parts[0] == 'capabilities':
            say.write('list\nimport\npush\noption\n')
            # *:* keeps clone and fetch writing plain refs/heads/master; see docs/src/notes/git-remote-tino.md#refs.
            say.write('refspec refs/heads/*:refs/heads/*\n')
            say.write('\n')
            say.flush()
        elif parts[0] == 'list':
            commits = tino.log()
            if not commits:
                # A log holding only TINO's hidden "Initialize bucket" commit is empty: report no refs, so
                # clone says "empty repository" instead of dying.
                say.write('\n')
                say.flush()
                continue
            # The marker ref's sha while the server tip matches the cached one, else `?`; never `unchanged`.
            # See docs/src/notes/git-remote-tino.md#list-reporting.
            marker = _marker_sha(tino)
            fresh = (_tip_cache(tino).is_file()
                     and _tip_cache(tino).read_text() == commits[0]['sha'])
            value = marker if (marker and fresh) else '?'
            say.write(f'{value} refs/heads/{BRANCH}\n')
            say.write(f'@refs/heads/{BRANCH} HEAD\n')
            say.write('\n')
            say.flush()
        elif parts[0] == 'import':
            imports.append(cmd)
        elif parts[0] == 'push':
            pushes.append(' '.join(parts[1:]))
        elif parts[0] == 'option':
            name = parts[1] if len(parts) > 1 else ''
            if name in ('verbosity', 'progress'):
                say.write('ok\n')
            else:
                say.write('unsupported\n')
            say.flush()
        else:
            raise SystemExit(f'unknown helper command: {cmd}')


if __name__ == '__main__':
    main()
