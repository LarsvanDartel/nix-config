# holiday-calendar — mirror public ICS feeds into one CalDAV calendar,
# configured by services/holiday-calendar.nix.
#
# Each event is stored under a hash of its content (without DTSTAMP, the
# upload time), so a run deletes what changed or vanished and uploads what
# is new; unchanged events are never rewritten.
import base64
import hashlib
import http.client
import json
import os
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from xml.etree import ElementTree
from xml.sax.saxutils import escape

from icalendar import Calendar, Event

DAV = "{DAV:}"
PRODID = "-//lvdar.nl//holiday-calendar//EN"
KEEP = ("UID", "DTSTART", "DTEND", "DURATION", "RRULE", "SUMMARY")
PROPFIND = (
    b'<?xml version="1.0"?><d:propfind xmlns:d="DAV:">'
    b"<d:prop><d:resourcetype/></d:prop></d:propfind>"
)
# agenda-abonnement.nl sends REFRESH-INTERVAL:P6H (not PT6H), which fails
# the whole parse; feed-level properties are discarded anyway.
Calendar.ignore_exceptions = True


def fetch(url):
    req = urllib.request.Request(
        url, headers={"User-Agent": "holiday-calendar"}
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return Calendar.from_ical(resp.read())


def convert(src, feed, timezones):
    ev = Event()
    for key in KEEP:
        if key in src:
            ev[key] = src[key]
    if feed["suffix"]:
        summary = str(src.get("SUMMARY", ""))
        if summary.endswith(")"):
            summary = f"{summary[:-1]}, {feed['suffix']})"
        else:
            summary = f"{summary} ({feed['suffix']})"
        ev["SUMMARY"] = summary
    if feed["description"] and "DESCRIPTION" in src:
        lines = str(src["DESCRIPTION"]).splitlines()
        if lines:
            ev.add("DESCRIPTION", lines[0])
    # Feeds leave TRANSP out; the default, OPAQUE, books a six-week summer
    # holiday as busy time.
    ev.add("TRANSP", "TRANSPARENT")

    cal = Calendar()
    cal.add("VERSION", "2.0")
    cal.add("PRODID", PRODID)
    for tzid in {
        getattr(src.get(key), "params", {}).get("TZID")
        for key in ("DTSTART", "DTEND")
    }:
        if tzid in timezones:
            cal.add_component(timezones[tzid])
    cal.add_component(ev)

    name = hashlib.sha256(cal.to_ical()).hexdigest()[:32] + ".ics"
    # Upload time; agenda-abonnement.nl's stamps are floating and in the
    # future.
    ev.add("DTSTAMP", datetime.now(timezone.utc))
    return str(src["UID"]), name, cal.to_ical()


def desired(feeds):
    events = {}
    uids = set()
    for feed in feeds:
        source = fetch(feed["url"])
        found = source.walk("VEVENT")
        # An empty or broken feed must not wipe its events.
        if not found:
            sys.exit(f"{feed['url']}: no events")
        timezones = {str(tz["TZID"]): tz for tz in source.walk("VTIMEZONE")}
        for src in found:
            uid, name, body = convert(src, feed, timezones)
            if uid in uids:
                sys.exit(f"{feed['url']}: duplicate UID {uid}")
            uids.add(uid)
            events[name] = body
    return events


class Dav:
    def __init__(self, url, user, password):
        parts = urllib.parse.urlsplit(url)
        self.conn = http.client.HTTPConnection(
            parts.hostname, parts.port, timeout=60
        )
        self.path = parts.path
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

    def existing(self, name):
        status, data = self.request(
            "PROPFIND",
            self.path,
            (207, 404),
            PROPFIND,
            {"Depth": "1", "Content-Type": "application/xml"},
        )
        if status == 404:
            self.request(
                "MKCALENDAR",
                self.path,
                (201,),
                '<?xml version="1.0"?><c:mkcalendar xmlns:d="DAV:"'
                ' xmlns:c="urn:ietf:params:xml:ns:caldav"><d:set><d:prop>'
                f"<d:displayname>{escape(name)}</d:displayname>"
                "</d:prop></d:set></c:mkcalendar>",
                {"Content-Type": "application/xml"},
            )
            print(f"created {self.path}")
            return set()
        names = set()
        for resp in ElementTree.fromstring(data).iter(DAV + "response"):
            href = urllib.parse.unquote(resp.findtext(DAV + "href", ""))
            if href.endswith(".ics"):
                names.add(href.rsplit("/", 1)[1])
        return names


def main():
    with open(sys.argv[1]) as f:
        cfg = json.load(f)
    with open(os.path.join(os.environ["CREDENTIALS_DIRECTORY"], "admin")) as f:
        password = f.read().strip()

    want = desired(cfg["feeds"])
    dav = Dav(cfg["calendar"], cfg["user"], password)
    have = dav.existing(cfg["name"])

    # Deletions first: a changed event keeps its UID, and a calendar may not
    # hold two resources with the same UID.
    stale = have - want.keys()
    for name in sorted(stale):
        dav.request("DELETE", dav.path + name, (200, 204, 404))
    new = want.keys() - have
    for name in sorted(new):
        dav.request(
            "PUT",
            dav.path + name,
            (201, 204),
            want[name],
            {
                "Content-Type": "text/calendar; charset=utf-8",
                "If-None-Match": "*",
            },
        )
    print(
        f"{len(want)} events: {len(new)} added, {len(stale)} removed, "
        f"{len(want) - len(new)} unchanged"
    )


if __name__ == "__main__":
    main()
