#!/bin/bash
# Install the 5-minute poller as a user launchd job. Run once per machine.
#
#   ./install.sh            install and start
#   ./install.sh --remove   stop and remove
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LABEL="${PR_WATCH_LABEL:-com.instacart.pr-watch.poll}"   # override to avoid clashes
PLIST="$HOME/Library/LaunchAgents/$LABEL.plist"
POLL="$HERE/poll.sh"
SECONDS_BETWEEN=$(python3 -c 'import json,os
try: print(json.load(open(os.path.join("'"$HERE"'","..","config.json"))).get("pollSeconds",300))
except Exception: print(300)')
LOG="$HOME/Library/Logs/pr-watch-poll.log"

if [ "${1:-}" = "--remove" ]; then
  launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
  rm -f "$PLIST"
  echo "removed $LABEL"
  exit 0
fi

mkdir -p "$HOME/Library/LaunchAgents" "$HOME/Library/Logs"
cat > "$PLIST" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>$LABEL</string>
  <key>ProgramArguments</key>
  <array><string>/bin/bash</string><string>$POLL</string></array>
  <key>RunAtLoad</key><true/>
  <key>StartInterval</key><integer>$SECONDS_BETWEEN</integer>
  <key>StandardOutPath</key><string>$LOG</string>
  <key>StandardErrorPath</key><string>$LOG</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key><string>/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>HOME</key><string>$HOME</string>
  </dict>
</dict>
</plist>
PL

launchctl bootout "gui/$(id -u)/$LABEL" 2>/dev/null
launchctl bootstrap "gui/$(id -u)" "$PLIST" || exit 1
echo "installed $LABEL — every ${SECONDS_BETWEEN}s, log at $LOG"
