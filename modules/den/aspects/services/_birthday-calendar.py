# birthday-calendar — mirror the birthdays in an account's CardDAV address
# books into one CalDAV calendar, configured by
# services/birthday-calendar.nix.
#
# One yearly all-day event per contact with a BDAY. Each is stored under a
# hash of its content (without DTSTAMP, the upload time), so a run deletes
# what changed or vanished and uploads what is new; unchanged events are
# never rewritten.
import base64
import hashlib
import http.client
import json
import os
import re
import sys
import urllib.parse
from datetime import date, datetime, timedelta, timezone
from xml.etree import ElementTree
from xml.sax.saxutils import escape

from icalendar import Calendar, Event

DAV = "{DAV:}"
CARD = "{urn:ietf:params:xml:ns:carddav}"
PRODID = "-//lvdar.nl//birthday-calendar//EN"
PROPFIND = (
    b'<?xml version="1.0"?><d:propfind xmlns:d="DAV:">'
    b"<d:prop><d:resourcetype/></d:prop></d:propfind>"
)
# Earlier years are placeholders for a yearless birthday, written by
# clients that cannot store one (vCard 3 has none): Apple's 1604, 0000.
FIRST_YEAR = 1900
DATE = re.compile(r"(\d{4}|--)-?(\d{2})-?(\d{2})")


def unescape(value):
    return re.sub(
        r"\\(.)", lambda m: " " if m[1] in "nN" else m[1], value
    ).strip()


def split_unescaped(value, sep):
    return re.split(r"(?<!\\)" + re.escape(sep), value)


def properties(card):
    # (NAME, {PARAM: value}, value) per content line, group prefix dropped.
    for line in re.sub(r"\r?\n[ \t]", "", card).splitlines():
        quoted = False
        for i, char in enumerate(line):
            if char == '"':
                quoted = not quoted
            elif char == ":" and not quoted:
                break
        else:
            continue
        head, value = line[:i], line[i + 1:]
        name, *params = head.split(";")
        yield (
            name.rsplit(".", 1)[-1].upper(),
            {
                key.upper(): val.strip('"')
                for key, _, val in (p.partition("=") for p in params)
            },
            value,
        )


def birthday(params, value):
    # (year or None, month, day), or None when it is no full date.
    if params.get("VALUE", "").lower() == "text":
        return None
    m = DATE.fullmatch(value.split("T", 1)[0].strip())
    if not m:
        return None
    year = None if m[1] == "--" else int(m[1])
    if year is not None and (
        year < FIRST_YEAR or "X-APPLE-OMIT-YEAR" in params
    ):
        year = None
    month, day = int(m[2]), int(m[3])
    try:
        # 2000 is a leap year: a yearless 29 February is valid.
        date(year or 2000, month, day)
    except ValueError:
        return None
    return year, month, day


def contact(card):
    # (name, (year, month, day)) or None without a name or birthday.
    fn = n = bday = None
    for name, params, value in properties(card):
        if name == "FN" and fn is None:
            fn = unescape(value)
        elif name == "N" and n is None:
            parts = [unescape(p) for p in split_unescaped(value, ";")]
            # family;given;additional;prefixes;suffixes
            n = " ".join(p for p in parts[1:3] + parts[:1] if p)
        elif name == "BDAY" and bday is None:
            bday = birthday(params, value)
    name = fn or n
    if not name or not bday:
        return None
    return name, bday


def event(key, name, bday):
    year, month, day = bday
    start = date(year or 2000, month, day)
    ev = Event()
    ev.add("UID", f"{key}@birthday-calendar.lvdar.nl")
    ev.add("DTSTART", start)
    ev.add("DTEND", start + timedelta(days=1))
    # A plain yearly rule skips 29 February in common years; the last day
    # of February is the 29th in leap years and the 28th otherwise.
    if (month, day) == (2, 29):
        ev.add("RRULE", {"FREQ": "YEARLY", "BYMONTH": 2, "BYMONTHDAY": -1})
    else:
        ev.add("RRULE", {"FREQ": "YEARLY"})
    ev.add(
        "SUMMARY",
        f"Verjaardag {name}" + (f" ({year})" if year else ""),
    )
    ev.add("CATEGORIES", ["Birthday"])
    ev.add("TRANSP", "TRANSPARENT")

    cal = Calendar()
    cal.add("VERSION", "2.0")
    cal.add("PRODID", PRODID)
    cal.add_component(ev)

    resource = hashlib.sha256(cal.to_ical()).hexdigest()[:32] + ".ics"
    ev.add("DTSTAMP", datetime.now(timezone.utc))
    return resource, cal.to_ical()


class Dav:
    def __init__(self, url, user, password):
        parts = urllib.parse.urlsplit(url)
        self.conn = http.client.HTTPConnection(
            parts.hostname, parts.port, timeout=60
        )
        token = base64.b64encode(f"{user}:{password}".encode()).decode()
        self.auth = {"Authorization": f"Basic {token}"}

    def request(self, method, path, ok, body=None, headers=None):
        self.conn.request(
            method, path, body=body, headers={**self.auth, **(headers or {})}
        )
        resp = self.conn.getresponse()
        data = resp.read()
        if resp.status not in ok:
            sys.exit(f"{method} {path}: {resp.status} {data[:500]!r}")
        return resp.status, data

    def children(self, path, ok=(207,)):
        # None on 404, else {href: resourcetype tags} below path.
        status, data = self.request(
            "PROPFIND",
            path,
            ok,
            PROPFIND,
            {"Depth": "1", "Content-Type": "application/xml"},
        )
        if status == 404:
            return None
        out = {}
        for resp in ElementTree.fromstring(data).iter(DAV + "response"):
            href = resp.findtext(DAV + "href", "")
            if urllib.parse.unquote(href).rstrip("/") == (
                urllib.parse.unquote(path).rstrip("/")
            ):
                continue
            out[href] = {
                kind.tag for kind in resp.findall(f".//{DAV}resourcetype/*")
            }
        return out

    def cards(self, home):
        # {(book href, card href): vCard text} across every address book.
        out = {}
        for book, kinds in self.children(home).items():
            if CARD + "addressbook" not in kinds:
                continue
            hrefs = [
                href
                for href, kinds in self.children(book).items()
                if DAV + "collection" not in kinds
            ]
            if not hrefs:
                continue
            _, data = self.request(
                "REPORT",
                book,
                (207,),
                '<?xml version="1.0"?><c:addressbook-multiget'
                ' xmlns:d="DAV:" xmlns:c="urn:ietf:params:xml:ns:carddav">'
                "<d:prop><c:address-data/></d:prop>"
                + "".join(f"<d:href>{escape(h)}</d:href>" for h in hrefs)
                + "</c:addressbook-multiget>",
                {"Depth": "1", "Content-Type": "application/xml"},
            )
            for resp in ElementTree.fromstring(data).iter(DAV + "response"):
                text = resp.findtext(f".//{CARD}address-data")
                if text:
                    out[book, resp.findtext(DAV + "href", "")] = text
        return out

    def events(self, path, name):
        found = self.children(path, (207, 404))
        if found is None:
            self.request(
                "MKCALENDAR",
                path,
                (201,),
                '<?xml version="1.0"?><c:mkcalendar xmlns:d="DAV:"'
                ' xmlns:c="urn:ietf:params:xml:ns:caldav"><d:set><d:prop>'
                f"<d:displayname>{escape(name)}</d:displayname>"
                "</d:prop></d:set></c:mkcalendar>",
                {"Content-Type": "application/xml"},
            )
            print(f"created {path}")
            return set()
        return {
            urllib.parse.unquote(href).rsplit("/", 1)[1]
            for href in found
            if href.endswith(".ics")
        }


def main():
    with open(sys.argv[1]) as f:
        cfg = json.load(f)
    with open(os.path.join(os.environ["CREDENTIALS_DIRECTORY"], "admin")) as f:
        password = f.read().strip()

    dav = Dav(cfg["calendar"], cfg["user"], password)
    calendar = urllib.parse.urlsplit(cfg["calendar"]).path
    cards = dav.cards(urllib.parse.urlsplit(cfg["addressBooks"]).path)

    want = {}
    for (book, href), card in sorted(cards.items()):
        found = contact(card)
        if found:
            key = hashlib.sha256(f"{book}\0{href}".encode()).hexdigest()[:32]
            resource, body = event(key, *found)
            want[resource] = body
    have = dav.events(calendar, cfg["name"])

    # Deletions first: a changed event keeps its UID, and a calendar may not
    # hold two resources with the same UID.
    stale = have - want.keys()
    for resource in sorted(stale):
        dav.request("DELETE", calendar + resource, (200, 204, 404))
    new = want.keys() - have
    for resource in sorted(new):
        dav.request(
            "PUT",
            calendar + resource,
            (201, 204),
            want[resource],
            {
                "Content-Type": "text/calendar; charset=utf-8",
                "If-None-Match": "*",
            },
        )
    print(
        f"{len(cards)} contacts, {len(want)} birthdays: {len(new)} added, "
        f"{len(stale)} removed, {len(want) - len(new)} unchanged"
    )


if __name__ == "__main__":
    main()
