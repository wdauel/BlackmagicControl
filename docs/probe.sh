#!/bin/zsh
# Probes the endpoints added/uncertain in the clip-browser + overlays work so the
# models can be verified against a real device. Run from a Mac on the same LAN as
# the iPhone (the CC sandbox can't route to it).
#
#   ./docs/probe.sh                 # uses default host below
#   ./docs/probe.sh 10.11.1.186 4444
#
# Needs curl (jq optional — pretty-prints JSON if present).
HOST="${1:-10.11.1.186}"
PORT="${2:-4444}"
BASE="https://$HOST:$PORT/control/api/v1"
DISPLAY="Device"   # from /monitoring/display

# Resolve curl explicitly — a trimmed PATH (e.g. inside a sandbox) may hide it.
CURL="$(command -v curl 2>/dev/null)"
[[ -z "$CURL" && -x /usr/bin/curl ]] && CURL=/usr/bin/curl
if [[ -z "$CURL" ]]; then
  print -r -- "error: curl not found. Run this in a normal Terminal window on your Mac"
  print -r -- "(not via the '!' prefix inside Claude Code — that sandbox has no curl and"
  print -r -- "cannot reach your LAN)."
  exit 1
fi

pp() { command -v jq >/dev/null 2>&1 && jq . 2>/dev/null || command -v /usr/bin/jq >/dev/null 2>&1 && /usr/bin/jq . 2>/dev/null; }

probe() {  # probe <path>
  local path="$1"
  local body code
  body=$("$CURL" -k -s -m 5 -w $'\n%{http_code}' "$BASE$path")
  code="${body##*$'\n'}"
  body="${body%$'\n'*}"
  printf '\n=== GET %s  [%s] ===\n' "$path" "$code"
  if [[ -n "$body" ]]; then
    if command -v jq >/dev/null 2>&1; then printf '%s' "$body" | jq . 2>/dev/null || printf '%s\n' "$body"
    else printf '%s\n' "$body"; fi
  fi
}

print -r -- "Probing $BASE"

# Endpoints that returned 200 — need their JSON bodies to lock the models.
probe "/monitoring/display"
probe "/clips"
probe "/timelines/0"
probe "/monitoring/Device/frameGrids"
probe "/monitoring/frameGrids"
probe "/monitoring/Device/safeArea"
probe "/monitoring/safeAreaPercent"
probe "/monitoring/Device/displayLUT"
probe "/monitoring/Device/brightness"
probe "/video/shutter/measurement"
probe "/video/supportedShutters"
probe "/lens/focus/autoFocus"
probe "/lens/opticalImageStabilization"
probe "/system/product"

print -r -- "\nDone. Paste this output back and the models get locked to reality."
