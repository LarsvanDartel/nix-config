# apparmor-match — lists the apparmor.d profiles whose attachment matches an executable in collect.sh output.
# Regenerating the profile lists: see docs/src/notes/apparmor-match.md#regenerating-the-profile-lists.
import collections
import os
import re
import sys


def aa_to_regex(pattern):
    out, i, depth = "", 0, 0
    while i < len(pattern):
        c = pattern[i]
        if pattern.startswith("**", i):
            out += ".*"
            i += 2
            continue
        if c == "*":
            out += "[^/]*"
        elif c == "?":
            out += "[^/]"
        elif c == "{":
            out += "(?:"
            depth += 1
        elif c == "}":
            out += ")"
            depth -= 1
        elif c == "," and depth > 0:
            out += "|"
        elif c == "[":
            j = pattern.index("]", i)
            out += pattern[i : j + 1]
            i = j + 1
            continue
        else:
            out += re.escape(c)
        i += 1
    return re.compile("^" + out + "$")


def attachments(profile_dir):
    header = re.compile(r"\s*profile\s+(\S+)\s+(/\S+)\s+(flags=\S*\s*)?\{\s*$")
    found = {}
    for name in sorted(os.listdir(profile_dir)):
        path = os.path.join(profile_dir, name)
        if not os.path.isfile(path):
            continue
        with open(path, errors="ignore") as f:
            for line in f:
                m = header.match(line)
                if m:
                    found[name] = aa_to_regex(m.group(2))
                    break
    return found


def main():
    profile_dir, tsvs = sys.argv[1], sys.argv[2:]
    profiles = attachments(profile_dir)
    per_host = {}
    for tsv in tsvs:
        paths = set()
        with open(tsv) as f:
            for line in f:
                if "\t" in line:
                    paths.add(line.rstrip("\n").split("\t", 1)[1])
        per_host[os.path.basename(tsv).removesuffix(".tsv")] = {
            name for name, rx in profiles.items() if any(rx.match(p) for p in paths)
        }
    common = set.intersection(*per_host.values())
    print("# common")
    print("\n".join(sorted(common)))
    for host, names in per_host.items():
        print(f"# {host}")
        print("\n".join(sorted(names - common)))


main()
