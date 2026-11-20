# holiday-calendar — mirrors public ICS feeds into one CalDAV calendar.
import base64
import hashlib
import http.client
import json
import os
import sys
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from xml.etree import ElementTree
from xml.sax.saxutils import escape

from dateutil.easter import easter
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


def label(regions):
    if len(regions) == 1:
        return regions[0]
    return ", ".join(regions[:-1]) + " & " + regions[-1]


def convert(src, timezones, description, regions=None, uid=None):
    ev = Event()
    for key in KEEP:
        if key in src:
            ev[key] = src[key]
    if uid:
        ev["UID"] = uid
    if regions:
        summary = str(src.get("SUMMARY", ""))
        if summary.endswith(")"):
            summary = f"{summary[:-1]}, {label(regions)})"
        else:
            summary = f"{summary} ({label(regions)})"
        ev["SUMMARY"] = summary
    if description and "DESCRIPTION" in src:
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
    # Added after hashing: the upload time must not change the name.
    # agenda-abonnement.nl's own stamps are floating and in the future.
    ev.add("DTSTAMP", datetime.now(timezone.utc))
    return str(ev["UID"]), name, cal.to_ical()


def synthetic(key, summary, start, end, description=None):
    ev = Event()
    ev.add("UID", f"{key}@holiday-calendar.lvdar.nl")
    ev.add("DTSTART", start)
    ev.add("DTEND", end)
    ev.add("SUMMARY", summary)
    if description:
        ev.add("DESCRIPTION", description)
    return convert(ev, {}, True)


def carnaval(years, spring, region):
    # In no feed: Sunday to Tuesday before Ash Wednesday.
    out = []
    for year in sorted(years):
        sunday = easter(year) - timedelta(days=49)
        wednesday = sunday + timedelta(days=3)
        out.append(
            synthetic(f"carnaval-{year}", "Carnaval", sunday, wednesday)
        )
        # The region's spring holiday is only advised; where it misses
        # carnaval, many schools there move it to the week around carnaval.
        advised = [span for span in spring if span[0].year == year]
        if advised and not any(
            start <= sunday and wednesday <= end for start, end in advised
        ):
            dates = ", ".join(
                f"{start:%d-%m} t/m {end - timedelta(days=1):%d-%m}"
                for start, end in advised
            )
            out.append(
                synthetic(
                    f"carnavalvakantie-{year}",
                    f"Carnavalvakantie ({region})",
                    sunday - timedelta(days=1),
                    sunday + timedelta(days=8),
                    f"Afwijkend van het advies ({dates}), dat carnaval "
                    f"mist; veel scholen in regio {region} doen dit.",
                )
            )
    return out


def desired(feeds, carnaval_region):
    regions = [feed["region"] for feed in feeds if feed["region"]]
    converted = []
    years = set()
    spring = []
    shared = {}
    for feed in feeds:
        source = fetch(feed["url"])
        found = source.walk("VEVENT")
        # An empty or broken feed must not wipe its events.
        if not found:
            sys.exit(f"{feed['url']}: no events")
        timezones = {str(tz["TZID"]): tz for tz in source.walk("VTIMEZONE")}
        for src in found:
            years.add(src["DTSTART"].dt.year)
            if feed["region"] == carnaval_region and str(
                src.get("SUMMARY", "")
            ).startswith("Voorjaarsvakantie"):
                spring.append((src["DTSTART"].dt, src["DTEND"].dt))
            if feed["region"]:
                key = tuple(
                    src[k].to_ical() if k in src else b""
                    for k in ("SUMMARY", "DTSTART", "DTEND")
                )
                shared.setdefault(key, []).append(
                    (feed["region"], feed, src, timezones)
                )
            else:
                converted.append(
                    convert(src, timezones, feed["description"])
                )

    for members in shared.values():
        names = [region for region, _, _, _ in members]
        _, feed, src, timezones = members[0]
        uid = None
        if len(members) > 1:
            # Stable across runs: changes only with the merged events.
            joined = " ".join(sorted(str(m[2]["UID"]) for m in members))
            digest = hashlib.sha256(joined.encode()).hexdigest()[:32]
            uid = f"{digest}@holiday-calendar.lvdar.nl"
        converted.append(
            convert(
                src,
                timezones,
                feed["description"],
                None if sorted(names) == sorted(regions) else names,
                uid,
            )
        )
    converted += carnaval(years, spring, carnaval_region)

    events = {}
    uids = set()
    for uid, name, body in converted:
        if uid in uids:
            sys.exit(f"duplicate UID {uid}")
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

    want = desired(cfg["feeds"], cfg["carnavalRegion"])
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
