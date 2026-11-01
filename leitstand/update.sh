#!/usr/bin/env bash
# One update of the Dashboard data (called every 5 minutes by .github/workflows/leitstand.yml):
# the sealed data of the last night/repair run from the private repo's data branch, the channel's
# public YouTube numbers and their history.
#
# Live (Felix 30.10.): the files go to the branch "live" as one fresh commit each time (force push, so
# the branch never grows). The page reads them from there through raw.githubusercontent.com by commit,
# without the Pages cache and build. main gets them at most once an hour, as the page's fallback.
set -u
cd "$(dirname "$0")/.."
FILES="leitstand/data.json leitstand/live.json leitstand/history.json"

# first call of a run: carry on from the live branch, it is newer than main
if [ ! -f .git/live-restored ] && git fetch -q origin live 2>/dev/null; then
  for f in $FILES; do git show "FETCH_HEAD:$f" > "$f.tmp" 2>/dev/null && mv "$f.tmp" "$f" || rm -f "$f.tmp"; done
fi
touch .git/live-restored

if [ -z "${TOKEN:-}" ]; then echo "::warning::Secret LEITSTAND_READ_TOKEN fehlt"
else
  url="https://api.github.com/repos/felixcashmoney-spec/Youtube-Automation/contents/leitstand/data.json?ref=claude/ytauto-data"
  tmp="$(mktemp)"
  if curl -sSf -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github.raw" "$url" -o "$tmp" \
     && python3 -c "import json,sys; b=json.load(open(sys.argv[1])); assert b['v'] == 1 and b['iv'] and b['ct']" "$tmp"; then
    cp "$tmp" leitstand/data.json
  else echo "::warning::data.json nicht geholt"; fi
  rm -f "$tmp"
  # dead-man alarm without Claude: no new data for 28 h means night and repair both did not run
  # (e.g. the Claude Pro weekly limit is used up). Telegram every 6 h (round at :01 of 0/6/12/18 UTC).
  if [ -n "${TELEGRAM_BOT_TOKEN:-}" ] && [ $(( $(date +%s) % 21600 )) -lt 300 ]; then
    when=$(curl -sSf -H "Authorization: Bearer $TOKEN" \
      "https://api.github.com/repos/felixcashmoney-spec/Youtube-Automation/commits?sha=claude/ytauto-data&path=leitstand/data.json&per_page=1" \
      | python3 -c "import json,sys; print(json.load(sys.stdin)[0]['commit']['committer']['date'])" 2>/dev/null)
    age=$(( ($(date +%s) - $(date -d "${when:-1970-01-01}" +%s)) / 3600 ))
    if [ "$age" -ge 28 ]; then
      curl -sS -o /dev/null -w "Telegram: %{http_code}\n" "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
        --data-urlencode "chat_id=$TELEGRAM_CHAT_ID" \
        --data-urlencode "text=Strange Knowns: seit $age Stunden kein neuer Stand. Nachtlauf und Reparatur sind nicht gelaufen (Claude-Wochenlimit? geplante Aufgaben aus?). Dashboard: https://felixcashmoney-spec.github.io/leitstand/" || true
    fi
  fi
  # the page itself: web/leitstand/index.html on the private repo's main (CI there checks its script)
  url="https://api.github.com/repos/felixcashmoney-spec/Youtube-Automation/contents/web/leitstand/index.html?ref=main"
  tmp="$(mktemp)"
  if curl -sSf -H "Authorization: Bearer $TOKEN" -H "Accept: application/vnd.github.raw" "$url" -o "$tmp" \
     && grep -q '</html>' "$tmp"; then
    cp "$tmp" leitstand/index.html
  else echo "::warning::index.html nicht geholt"; fi
  rm -f "$tmp"
fi

if [ -z "${YOUTUBE_API_KEY:-}" ]; then echo "::warning::Secret YOUTUBE_API_KEY fehlt"
else python3 leitstand/live.py leitstand/live.json || echo "::warning::YouTube-Zahlen nicht geholt"; fi

stamp="Dashboard $(date -u +%Y-%m-%dT%H:%MZ)"
tree=$(export GIT_INDEX_FILE=.git/live-index; rm -f "$GIT_INDEX_FILE"; git add $FILES 2>/dev/null; git write-tree)
commit=$(git -c user.name="leitstand-bot" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" commit-tree "$tree" -m "$stamp")
for i in 1 2 3; do git push -q -f origin "$commit:refs/heads/live" && echo "live: $commit" && break; sleep 5; done

# main only hourly (no Pages build every 5 minutes; GitHub allows about 10 an hour), a new page right away
last=$(git log -1 --format=%ct origin/main -- leitstand/live.json 2>/dev/null || echo 0)
if git diff --quiet -- leitstand/index.html && [ $(( $(date +%s) - ${last:-0} )) -lt 3300 ]; then exit 0; fi
git add $FILES leitstand/index.html 2>/dev/null || true
if git diff --cached --quiet; then echo "nothing new"; exit 0; fi
git -c user.name="leitstand-bot" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
  commit -q -m "$stamp"
for i in 1 2 3; do git pull -q --rebase origin main && git push -q && break; sleep 5; done
# pushes with the workflow token may not start a Pages build by themselves
curl -sS -X POST -H "Authorization: Bearer $GH_TOKEN" -H "Accept: application/vnd.github+json" \
  "https://api.github.com/repos/$GITHUB_REPOSITORY/pages/builds" -o /dev/null -w "Pages build: %{http_code}\n" || true
