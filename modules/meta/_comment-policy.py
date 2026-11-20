# comment-policy — pre-commit check for the comment rules in docs/src/conventions.md#comments.
import pathlib
import re
import sys

MAX_BLOCK = 2
HEADER = re.compile(r"^# \S.* \u2014 \S")
COMMENT = re.compile(r"^\s*#( |$)")
DIRECTIVE = re.compile(r"^\s*# ?(deadnix:|shellcheck |noqa|type: ignore|pylint:|fmt:)")
DATE = re.compile(r"\b20\d\d-[01]\d(-[0-3]\d)?\b")
DOC_REF = re.compile(r"docs/src/[\w./-]+?\.md(?:#([\w-]+))?")
MD_HEADING = re.compile(r"^#{1,6}\s+(.*?)\s*#*\s*$")
_anchors = {}


def slug(text):
    text = re.sub(r"[`*]", "", text)
    return "".join(
        c.lower() if c.isalnum() or c in "_-" else "-" if c.isspace() else ""
        for c in text
    )


def anchors(md):
    if md not in _anchors:
        found, fenced = set(), False
        for line in pathlib.Path(md).read_text(encoding="utf-8").splitlines():
            if line.startswith("```"):
                fenced = not fenced
            elif not fenced and (m := MD_HEADING.match(line)):
                found.add(slug(m.group(1)))
        _anchors[md] = found
    return _anchors[md]


def is_comment(line):
    return bool(COMMENT.match(line)) and not DIRECTIVE.match(line)


def check(path):
    errors = []
    lines = pathlib.Path(path).read_text(encoding="utf-8").splitlines()
    start = 1 if lines and lines[0].startswith("#!") else 0
    body = start
    if path.endswith(".nix"):
        if start >= len(lines) or not HEADER.match(lines[start]):
            errors.append((start + 1, 'first line must be the header "# <name> — <what it is>"'))
        else:
            body = start + 1
            if body < len(lines) and is_comment(lines[body]):
                errors.append((body + 1, "the header is one line; no comment directly below it"))
    run, run_start = 0, 0
    for i in range(body, len(lines) + 1):
        if i < len(lines) and is_comment(lines[i]):
            run_start = i if run == 0 else run_start
            run += 1
            continue
        if run > MAX_BLOCK:
            errors.append((run_start + 1, f"comment block is {run} lines (max {MAX_BLOCK}); move the rationale to docs/src/notes/"))
        run = 0
    for i, line in enumerate(lines):
        if not COMMENT.match(line):
            continue
        if DATE.search(line):
            errors.append((i + 1, "no dates in comments; history belongs in git"))
        for m in DOC_REF.finditer(line):
            md = m.group(0).split("#")[0]
            if not pathlib.Path(md).is_file():
                errors.append((i + 1, f"{md} does not exist"))
            elif m.group(1) and m.group(1) not in anchors(md):
                errors.append((i + 1, f"{md} has no heading #{m.group(1)}"))
    return [f"{path}:{n}: {msg}" for n, msg in errors]


def main():
    errors = [e for p in sys.argv[1:] for e in check(p)]
    print("\n".join(errors)) if errors else None
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
