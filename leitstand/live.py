"""Public YouTube numbers of Strange Knowns for the Dashboard page (run by .github/workflows/leitstand.yml).

Three Data API calls (3 quota units): channel statistics and uploads playlist, the public uploads, their
statistics. Only public numbers, nothing private. Writes the file on every run, so ``at`` is the time of
the last check (every 5 minutes, Felix 30.10.: live); update.sh decides where it goes.

``history.json`` next to it keeps the numbers over time (Felix 30.10.: views per hour, a curve per video,
the week before): one point an hour for the last 72 hours and the last point of each day for 120 days.
"""

import json
import os
import sys
import urllib.parse
import urllib.request
from datetime import UTC, datetime, timedelta

CHANNEL = "UC5cRtZX7PDB4y4lhJFPgvXQ"
API = "https://www.googleapis.com/youtube/v3/"


def get(endpoint, **params):
    params["key"] = os.environ["YOUTUBE_API_KEY"]
    with urllib.request.urlopen(API + endpoint + "?" + urllib.parse.urlencode(params), timeout=30) as r:
        return json.load(r)


def main(path):
    ch = get("channels", part="statistics,contentDetails", id=CHANNEL)["items"][0]
    s = ch["statistics"]
    uploads = ch["contentDetails"]["relatedPlaylists"]["uploads"]
    items = get("playlistItems", part="contentDetails", playlistId=uploads, maxResults=50).get("items", [])
    ids = [x["contentDetails"]["videoId"] for x in items]
    published = {x["contentDetails"]["videoId"]: x["contentDetails"].get("videoPublishedAt") for x in items}
    videos = {}
    if ids:
        for v in get("videos", part="statistics", id=",".join(ids)).get("items", []):
            st = v.get("statistics", {})
            videos[v["id"]] = {k: int(st[k]) for k in ("viewCount", "likeCount", "commentCount") if k in st}
    numbers = {"channel": {"subscribers": int(s.get("subscriberCount", 0)), "views": int(s.get("viewCount", 0)),
                           "videos": int(s.get("videoCount", 0))},
               "videos": {k: {"views": v.get("viewCount"), "likes": v.get("likeCount"),
                              "comments": v.get("commentCount"), "published": published.get(k)}
                          for k, v in videos.items()}}
    now = datetime.now(UTC)
    remember(os.path.join(os.path.dirname(path) or ".", "history.json"), now, numbers)
    with open(path, "w") as f:
        json.dump({"at": now.strftime("%Y-%m-%dT%H:%M:%SZ"), **numbers}, f, indent=1)
        f.write("\n")
    print(f"{numbers['channel']['subscribers']} Abos, {numbers['channel']['views']} Aufrufe, {len(videos)} Videos")


HOURLY_HOURS, DAILY_DAYS = 72, 120


def add_point(hist, now, numbers):
    """``hist`` with this run's numbers: a new hourly point when the last one is 55 minutes old, and
    today's (UTC) daily point replaced by it. Returns None when it is too early for a new point."""
    point = {"t": now.strftime("%Y-%m-%dT%H:%M:%SZ"), "s": numbers["channel"]["subscribers"],
             "c": numbers["channel"]["views"],
             "v": {k: v["views"] for k, v in numbers["videos"].items() if v.get("views") is not None}}
    hourly, daily = list(hist.get("hourly", [])), list(hist.get("daily", []))
    if hourly and now - datetime.fromisoformat(hourly[-1]["t"].replace("Z", "+00:00")) < timedelta(minutes=55):
        return None
    first = (now - timedelta(hours=HOURLY_HOURS)).strftime("%Y-%m-%dT%H:%M:%SZ")
    hourly = [p for p in hourly + [point] if p["t"] >= first]
    first_day = (now - timedelta(days=DAILY_DAYS)).strftime("%Y-%m-%d")
    daily = [p for p in daily if p["t"][:10] != point["t"][:10] and p["t"][:10] >= first_day] + [point]
    return {"hourly": hourly, "daily": daily}


def remember(path, now, numbers):
    try:
        hist = json.load(open(path))
    except (OSError, ValueError):
        hist = {}
    new = add_point(hist, now, numbers)
    if new is not None:
        with open(path, "w") as f:
            json.dump(new, f, separators=(",", ":"))
            f.write("\n")


def _selfcheck():
    t0 = datetime(2026, 10, 30, 10, 0, tzinfo=UTC)
    nums = {"channel": {"subscribers": 2, "views": 10}, "videos": {"a": {"views": 5}, "b": {"views": None}}}
    h = add_point({}, t0, nums)
    assert h["hourly"][0]["v"] == {"a": 5} and len(h["daily"]) == 1
    assert add_point(h, t0 + timedelta(minutes=15), nums) is None
    h = add_point(h, t0 + timedelta(hours=1), nums)
    assert len(h["hourly"]) == 2 and len(h["daily"]) == 1 and h["daily"][0]["t"].endswith("11:00:00Z")
    h = add_point(h, t0 + timedelta(hours=80), nums)
    assert len(h["hourly"]) == 1 and len(h["daily"]) == 2


if __name__ == "__main__" and sys.argv[1:] == ["--check"]:
    _selfcheck()
    print("ok")
elif __name__ == "__main__":
    main(sys.argv[1])
