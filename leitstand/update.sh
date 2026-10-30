#!/usr/bin/env bash
# One update of the Dashboard data (called every 15 minutes by .github/workflows/leitstand.yml):
# the sealed data of the last night/repair run from the private repo's data branch, the channel's
# public YouTube numbers and their history. Commits and pushes only when something changed.
set -u
cd "$(dirname "$0")/.."

if [ -z "${TOKEN:-}" ]; then echo "::warning::Secret LEITSTAND_READ_TOKEN fehlt"
else
  url="https://api.github.com/repos/felixcashmoney-spec/Youtube-Automation/contents/leitstand/data.json?ref=claude/ytauto-data"
  tmp="$(mktemp)"
  if curl -sSf -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github.raw" "$url" -o "$tmp" \
     && python3 -c "import json,sys; b=json.load(open(sys.argv[1])); assert b['v'] == 1 and b['iv'] and b['ct']" "$tmp"; then
    cp "$tmp" leitstand/data.json
  else echo "::warning::data.json nicht geholt"; fi
  rm -f "$tmp"
fi

if [ -z "${YOUTUBE_API_KEY:-}" ]; then echo "::warning::Secret YOUTUBE_API_KEY fehlt"
else python3 leitstand/live.py leitstand/live.json || echo "::warning::YouTube-Zahlen nicht geholt"; fi

git add leitstand/data.json leitstand/live.json leitstand/history.json 2>/dev/null || true
if git diff --cached --quiet; then echo "nothing new"; exit 0; fi
git -c user.name="leitstand-bot" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  commit -q -m "Dashboard $(date -u +%Y-%m-%dT%H:%MZ)"
for i in 1 2 3; do git pull -q --rebase origin main && git push -q && break; sleep 5; done
# pushes with the workflow token may not start a Pages build by themselves
curl -sS -X POST -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$GITHUB_REPOSITORY/pages/builds" -o /dev/null -w "Pages build: %{http_code}\n" || true
