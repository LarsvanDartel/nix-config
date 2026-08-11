"""Re-encode library video files to AV1 on the GPU, in place.

Driven by services/transcode.nix, which is where the reasoning about *why*
this exists lives. Everything configurable arrives as an environment variable
so this file is a plain script: run it with the same environment the unit sets
and it behaves identically outside systemd, which is how to debug it.

Underscore-prefixed so import-tree leaves the directory alone.
"""

import json
import logging
import os
import subprocess
import sys
import time
import xml.etree.ElementTree as ET
from pathlib import Path
from urllib import error, request

FFMPEG = os.environ["FFMPEG"]
FFPROBE = os.environ["FFPROBE"]
DEVICE = os.environ["DEVICE"]
LIBRARIES = [Path(p) for p in json.loads(os.environ["LIBRARIES"])]
SKIP_CODECS = {c.lower() for c in json.loads(os.environ["SKIP_CODECS"])}
ARRS = json.loads(os.environ["ARRS"])
MIN_SIZE = int(os.environ["MIN_SIZE_MIB"]) * 1024 * 1024
MIN_FREE = int(os.environ["MIN_FREE_GIB"]) * 1024 ** 3
MIN_SAVING = float(os.environ["MIN_SAVING"])
MAX_PER_RUN = int(os.environ["MAX_PER_RUN"])
QUALITY = os.environ["QUALITY"]
DRY_RUN = os.environ["DRY_RUN"] == "1"
UNMONITOR = os.environ["UNMONITOR"] == "1"
STATE_FILE = Path(os.environ["STATE_FILE"])

# Containers worth looking inside. Everything else in a library is
# artwork, .nfo or bazarr's .srt sidecars.
SUFFIXES = {".mkv", ".mp4", ".m4v", ".avi", ".mov", ".ts", ".wmv", ".mpg"}

# A file still being written by an import is not a candidate. The arrs
# move completed downloads in, and catching one mid-move would mean
# probing a truncated file.
SETTLE = 600

LOGGER = logging.getLogger("transcode")


def run(argv, **kw):
    return subprocess.run(argv, capture_output=True, text=True, **kw)


def probe(path):
    """ffprobe -> (video codec, duration, n_audio, n_subs), or None."""
    res = run([
        FFPROBE, "-v", "error", "-print_format", "json",
        "-show_format", "-show_streams", str(path),
    ])
    if res.returncode != 0:
        LOGGER.warning("%s: ffprobe failed: %s", path, res.stderr.strip()[:200])
        return None
    try:
        data = json.loads(res.stdout)
    except json.JSONDecodeError:
        return None

    streams = data.get("streams", [])
    video = [s for s in streams if s.get("codec_type") == "video"]
    if not video:
        return None
    try:
        duration = float(data.get("format", {}).get("duration", 0.0))
    except (TypeError, ValueError):
        duration = 0.0
    return {
        "codec": (video[0].get("codec_name") or "").lower(),
        "duration": duration,
        "audio": len([s for s in streams if s.get("codec_type") == "audio"]),
        "subs": len([s for s in streams if s.get("codec_type") == "subtitle"]),
    }


def load_state():
    try:
        return json.loads(STATE_FILE.read_text())
    except (OSError, json.JSONDecodeError):
        return {}


def save_state(state):
    tmp = STATE_FILE.with_suffix(".tmp")
    tmp.write_text(json.dumps(state, indent=1, sort_keys=True))
    os.replace(tmp, STATE_FILE)


def identity(st):
    """What makes a state entry stale: the file changed underneath us."""
    return f"{st.st_size}:{st.st_mtime_ns}"


def vaapi_works():
    """Encode two seconds of test pattern. Cheap, and unambiguous."""
    res = run([
        FFMPEG, "-hide_banner", "-loglevel", "error",
        "-init_hw_device", f"vaapi=va:{DEVICE}",
        "-f", "lavfi", "-i", "testsrc=size=640x480:rate=25:duration=2",
        "-vf", "format=nv12,hwupload", "-c:v", "av1_vaapi",
        "-f", "null", "-",
    ])
    if res.returncode != 0:
        LOGGER.error("VAAPI unusable, nothing will be encoded: %s",
                     res.stderr.strip()[:400])
        return False
    return True


def free_bytes(path):
    st = os.statvfs(path)
    return st.f_bavail * st.f_frsize


def candidates(state):
    """Files worth encoding, largest first — biggest win per unit of risk."""
    found = []
    now = time.time()

    for library in LIBRARIES:
        for path in sorted(library.rglob("*")):
            if path.suffix.lower() not in SUFFIXES or not path.is_file():
                continue
            try:
                st = path.stat()
            except OSError:
                continue
            if st.st_size < MIN_SIZE or now - st.st_mtime < SETTLE:
                continue

            key = str(path)
            entry = state.get(key)
            # A recorded verdict stands until the file itself changes,
            # so a 421-file library is probed once, not every night.
            if entry and entry.get("id") == identity(st):
                continue

            info = probe(path)
            if info is None:
                state[key] = {"id": identity(st), "status": "unreadable"}
                continue
            if info["codec"] in SKIP_CODECS:
                state[key] = {"id": identity(st), "status": "skip",
                              "codec": info["codec"]}
                continue

            found.append((st.st_size, path, info))

    found.sort(reverse=True, key=lambda t: t[0])
    return found


def encode(path, info):
    """Encode beside the original. Returns the temp path, or None."""
    tmp = path.with_name(path.name + ".transcode.mkv")
    argv = [
        FFMPEG, "-nostdin", "-y", "-hide_banner", "-loglevel", "error",
        "-init_hw_device", f"vaapi=va:{DEVICE}", "-filter_hw_device", "va",
        "-i", str(path),
        # The primary video stream only: a cover-art mjpeg stream would
        # otherwise be handed to the AV1 encoder. Audio, subtitles and
        # attachments (fonts, which subtitles need) come across as-is —
        # this is about video, and re-encoding audio would lose more
        # than it saves.
        "-map", "0:v:0", "-map", "0:a?", "-map", "0:s?", "-map", "0:t?",
        "-map_chapters", "0",
        "-c", "copy",
        # -q:v, not -qp. av1_vaapi has no `qp` option at all and
        # silently ignores one: every value from 30 to 160 produced a
        # byte-identical bitrate. VAAPI encoders take their quality
        # through global_quality, which is what -q:v sets.
        "-c:v", "av1_vaapi", "-vf", "format=nv12,hwupload",
        "-rc_mode", "CQP", "-q:v", QUALITY,
        str(tmp),
    ]
    started = time.time()
    res = run(argv)
    if res.returncode != 0:
        LOGGER.error("%s: encode failed: %s", path.name,
                     res.stderr.strip()[:400])
        tmp.unlink(missing_ok=True)
        return None
    LOGGER.info("%s: encoded in %.0f min", path.name,
                (time.time() - started) / 60)
    return tmp


def acceptable(tmp, info):
    """Refuse to replace anything with an output we cannot vouch for."""
    out = probe(tmp)
    if out is None:
        LOGGER.error("%s: output unreadable", tmp.name)
        return False
    if out["codec"] != "av1":
        LOGGER.error("%s: output is %s, not av1", tmp.name, out["codec"])
        return False
    if info["duration"] and abs(out["duration"] - info["duration"]) > 1.0:
        LOGGER.error("%s: duration %.1fs != source %.1fs",
                     tmp.name, out["duration"], info["duration"])
        return False
    if (out["audio"], out["subs"]) != (info["audio"], info["subs"]):
        LOGGER.error("%s: streams %da/%ds != source %da/%ds", tmp.name,
                     out["audio"], out["subs"], info["audio"], info["subs"])
        return False
    return True


def api(base, key, path, method="GET", body=None):
    req = request.Request(
        f"{base}/api/v3/{path}", method=method,
        headers={"X-Api-Key": key, "Content-Type": "application/json"},
        data=None if body is None else json.dumps(body).encode(),
    )
    with request.urlopen(req, timeout=60) as resp:
        raw = resp.read()
    return json.loads(raw) if raw else None


def api_key(name):
    """The arr's own config.xml, handed over by systemd as a credential.

    Deliberately not a copy in sops: the key is generated by the arr and
    can be rolled from its UI, and a second copy would silently go stale.
    """
    cred = Path(os.environ["CREDENTIALS_DIRECTORY"]) / f"{name}-config"
    return ET.fromstring(cred.read_text()).findtext("ApiKey")


def notify_arr(path):
    """Unmonitor the item, then rescan it.

    In that order on purpose. A rescan tells the arr the file changed;
    if it were still monitored it could read the new file as a
    downgrade from what its records say and go looking for the original
    again — re-downloading exactly what was just re-encoded, forever.
    """
    entry = next((a for a in ARRS
                  if str(path).startswith(a["library"] + "/")), None)
    if entry is None:
        return
    key = api_key(entry["name"])
    if not key:
        LOGGER.warning("%s: no api key, not notifying", entry["name"])
        return

    try:
        if entry["kind"] == "movie":
            movies = api(entry["url"], key, "movie")
            movie = next((m for m in movies
                          if (m.get("movieFile") or {}).get("path") == str(path)),
                         None)
            if movie is None:
                LOGGER.warning("radarr does not know %s", path)
                return
            movie["monitored"] = False
            api(entry["url"], key, f"movie/{movie['id']}", "PUT", movie)
            api(entry["url"], key, "command", "POST",
                {"name": "RefreshMovie", "movieIds": [movie["id"]]})
            LOGGER.info("radarr: unmonitored and rescanned %s", movie["title"])
        else:
            all_series = api(entry["url"], key, "series")
            series = next((s for s in all_series
                           if str(path).startswith(s["path"] + "/")), None)
            if series is None:
                LOGGER.warning("sonarr does not know %s", path)
                return
            files = api(entry["url"], key,
                        f"episodefile?seriesId={series['id']}")
            ef = next((f for f in files if f.get("path") == str(path)), None)
            episodes = api(entry["url"], key,
                           f"episode?seriesId={series['id']}")
            # The episode, never the series: unmonitoring the series
            # would stop every future episode from being downloaded.
            ids = [e["id"] for e in episodes
                   if ef and e.get("episodeFileId") == ef["id"]]
            if ids:
                api(entry["url"], key, "episode/monitor", "PUT",
                    {"episodeIds": ids, "monitored": False})
            api(entry["url"], key, "command", "POST",
                {"name": "RescanSeries", "seriesId": series["id"]})
            LOGGER.info("sonarr: unmonitored %d episode(s) of %s",
                        len(ids), series["title"])
    except (error.URLError, error.HTTPError, ET.ParseError, OSError) as exc:
        # The file is already replaced and correct; a failed API call is
        # worth a warning, not a failed run.
        LOGGER.warning("%s: could not notify: %s", entry["name"], exc)


def main():
    logging.basicConfig(
        level=logging.INFO, stream=sys.stdout,
        format="%(levelname)s %(message)s",
    )

    if not vaapi_works():
        # Exit clean. A failing unit during activation is what makes
        # deploy-rs roll the whole deploy back, and there is nothing
        # here worth doing that to. Software fallback is deliberately
        # not offered: these are 2.1GHz Broadwell cores and a silent
        # fallback would mean days of encoding nobody asked for.
        return 0

    state = load_state()
    found = candidates(state)
    save_state(state)

    total = sum(size for size, _, _ in found)
    LOGGER.info("%d candidate(s), %.1f GiB", len(found), total / 1024 ** 3)

    if DRY_RUN:
        for size, path, info in found:
            LOGGER.info("would encode %s (%s, %.1f GiB)",
                        path, info["codec"], size / 1024 ** 3)
        LOGGER.info("dry run, nothing changed")
        return 0

    done = 0
    for size, path, info in found:
        if done >= MAX_PER_RUN:
            break

        free = free_bytes(path.parent)
        # ZFS is copy-on-write: the new file exists in full alongside
        # the old one before the rename frees anything.
        if free - size < MIN_FREE:
            LOGGER.warning("stopping: %.0f GiB free, need headroom for %s",
                           free / 1024 ** 3, path.name)
            break

        tmp = encode(path, info)
        if tmp is None:
            state[str(path)] = {"id": identity(path.stat()),
                                "status": "failed"}
            save_state(state)
            continue

        new_size = tmp.stat().st_size
        if not acceptable(tmp, info):
            tmp.unlink(missing_ok=True)
            state[str(path)] = {"id": identity(path.stat()),
                                "status": "failed"}
            save_state(state)
            continue

        saving = 1 - new_size / size
        if saving < MIN_SAVING:
            tmp.unlink(missing_ok=True)
            LOGGER.info("%s: only %.0f%% smaller, keeping the original",
                        path.name, saving * 100)
            state[str(path)] = {"id": identity(path.stat()),
                                "status": "no-gain", "codec": info["codec"]}
            save_state(state)
            done += 1
            continue

        links = path.stat().st_nlink
        if links > 1:
            # Almost certainly a hardlink to still-seeding torrent data.
            # Renaming over it breaks the link rather than corrupting
            # the torrent, which is what we want — but the old blocks
            # stay allocated until that torrent is removed.
            LOGGER.info("%s: had %d links, space returns when the "
                        "torrent goes", path.name, links)

        os.chmod(tmp, 0o664)
        os.replace(tmp, path)
        LOGGER.info("%s: %.1f -> %.1f GiB (%.0f%% smaller)", path.name,
                    size / 1024 ** 3, new_size / 1024 ** 3, saving * 100)

        state[str(path)] = {"id": identity(path.stat()),
                            "status": "done", "codec": "av1",
                            "was": info["codec"]}
        save_state(state)

        if UNMONITOR:
            notify_arr(path)
        done += 1

    LOGGER.info("processed %d file(s) this run", done)
    return 0


if __name__ == "__main__":
    sys.exit(main())
