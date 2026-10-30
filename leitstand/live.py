"""Public YouTube numbers of Strange Knowns for the Dashboard page (run by .github/workflows/leitstand.yml).

Three Data API calls (3 quota units): channel statistics and uploads playlist, the public uploads, their
statistics. Only public numbers, nothing private. Writes the file only when a number changed or the
last write is older than an hour, so the repo does not get a commit every 15 minutes.
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
    videos = {}
    if ids:
        for v in get("videos", part="statistics", id=",".join(ids)).get("items", []):
            st = v.get("statistics", {})
            videos[v["id"]] = {k: int(st[k]) for k in ("viewCount", "likeCount", "commentCount") if k in st}
    numbers = {"channel": {"subscribers": int(s.get("subscriberCount", 0)), "views": int(s.get("viewCount", 0)),
                           "videos": int(s.get("videoCount", 0))},
               "videos": {k: {"views": v.get("viewCount"), "likes": v.get("likeCount"),
                              "comments": v.get("commentCount")} for k, v in videos.items()}}
    now = datetime.now(UTC)
    try:
        old = json.load(open(path))
        fresh = now - datetime.fromisoformat(old["at"].replace("Z", "+00:00")) < timedelta(minutes=55)
        if fresh and {k: old.get(k) for k in numbers} == numbers:
            print("unchanged")
            return
    except (OSError, ValueError, KeyError):
        pass
    with open(path, "w") as f:
        json.dump({"at": now.strftime("%Y-%m-%dT%H:%M:%SZ"), **numbers}, f, indent=1)
        f.write("\n")
    print(f"{numbers['channel']['subscribers']} Abos, {numbers['channel']['views']} Aufrufe, {len(videos)} Videos")


if __name__ == "__main__":
    main(sys.argv[1])
