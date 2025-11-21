#!/usr/bin/env bash

###################################################################
# Script Name : qrz_lookup.sh
# Description : This script performs a callsign lookup using qrz.com's API.
# Author      : Paul Duran
# Date        : 2025-11-07
# Version     : 1.0
# Usage       : ./qrz_lookup.sh <callsign> [--csv|--json]
###################################################################

# hi

set -euo pipefail

SESSION_FILE="$HOME/.qrz_session"
SESSION_LIFETIME_MINUTES=60   # Typical QRZ session timeout

# --- Helper: check if session key is valid ---
check_session_valid() {
  local session_key=$1
  # Try a harmless lookup to see if it returns an error
  local response
  response=$(curl -sSL "https://xmldata.qrz.com/xml/current/?s=${session_key};callsign=TEST")
  echo "here 1" >&2
  if echo "$response" | grep -q "<Error>Invalid session key"; then
    return 1
  fi
  #if echo "$response" | grep -q "<Error>"; then
   # return 1
  #fi
  # If XML contains <QRZDatabase>, assume valid
  echo "$response" | grep -q "Not found: TEST"
}

# --- Helper: get a new session key and cache it ---
get_new_session() {
  read -p "QRZ username: " QRZ_USER
  read -s -p "QRZ password: " QRZ_PASS
  echo
  local login_xml session
  login_xml=$(curl -sSL -G \
    --data-urlencode "username=${QRZ_USER}" \
    --data-urlencode "password=${QRZ_PASS}" \
    -A "qrz-cli/1.0" \
    "https://xmldata.qrz.com/xml/current/")
  session=$(printf '%s' "$login_xml" | sed -n 's:.*<Key>\(.*\)</Key>.*:\1:p' | tr -d '\r\n' | head -n1)
echo "here 2" >&2
  if [ -z "$session" ]; then
    echo "❌ Failed to get session key. Server response:"
    echo "$login_xml"
    exit 1
  fi

  echo "$session" > "$SESSION_FILE"
  touch -m "$SESSION_FILE"
  echo "🔑 Got new session key: $session"
}

# --- Helper: get current session key (cached or new) ---
get_session() {
  if [ -f "$SESSION_FILE" ]; then
    local file_age_mins=$(( ( $(date +%s) - $(stat -f %m "$SESSION_FILE") ) / 60 ))
    local cached_key
    cached_key=$(tr -d '\r\n' < "$SESSION_FILE")

    if [ "$file_age_mins" -lt "$SESSION_LIFETIME_MINUTES" ]; then
      printf "🕐 Checking cached session key...\n" >&2
      if check_session_valid "$cached_key"; then
        printf "✅ Using cached session key: $cached_key\n" >&2
        echo "$cached_key"   # 👈 This is the “return value”
        return 0
      else
        echo "⚠️ Cached session key invalid or expired." >&2
      fi
    else
      echo "⚠️ Cached session file too old (${file_age_mins} min)." >&2
    fi
  fi

  # If not valid, get a new one and echo that
  get_new_session
}

# --- MAIN SCRIPT ---

if [ $# -lt 1 ]; then
  echo "Usage: $0 CALLSIGN [--csv]"
  echo "Example: $0 N8CUB --csv"
  exit 1
fi

CALLSIGN=$(echo "$1" | tr '[:lower:]' '[:upper:]')
EXPORT_CSV=${2:-}

SESSION=$(get_session)

# --- Perform lookup ---

CALL_XML=$(curl -sSL -G \
  --data-urlencode "s=${SESSION}" \
  --data-urlencode "callsign=${CALLSIGN}" \
  "https://xmldata.qrz.com/xml/current/")
echo "here 3" >&2
# --- Extract fields ---
CALL=$(printf '%s' "$CALL_XML" | sed -n 's:.*<call>\(.*\)</call>.*:\1:p' | head -n1)
FNAME=$(printf '%s' "$CALL_XML" | sed -n 's:.*<fname>\(.*\)</fname>.*:\1:p' | head -n1)
NAME=$(printf '%s' "$CALL_XML" | sed -n 's:.*<name>\(.*\)</name>.*:\1:p' | head -n1)
ADDR=$(printf '%s' "$CALL_XML" | sed -n 's:.*<addr2>\(.*\)</addr2>.*:\1:p' | head -n1)
STATE=$(printf '%s' "$CALL_XML" | sed -n 's:.*<state>\(.*\)</state>.*:\1:p' | head -n1)
COUNTRY=$(printf '%s' "$CALL_XML" | sed -n 's:.*<country>\(.*\)</country>.*:\1:p' | head -n1)

echo
echo "📡 Callsign lookup result:"
echo "  Call:     $CALL"
echo "  Name:     $FNAME $NAME"
echo "  Location: $ADDR, $STATE"
echo "  Country:  $COUNTRY"
echo


# --- Optional Unified CSV export ---
if [ "$EXPORT_CSV" = "--csv" ]; then
  CSV_FILE="${CSV_FILE:-qrz_callsigns.csv}"
  # Write header only if file doesn’t exist yet
  if [ ! -f "$CSV_FILE" ]; then
    printf "call,fname,name,addr,state,country,timestamp\n" > "$CSV_FILE"
  fi
  timestamp=$(date +'%Y-%m-%d %H:%M:%S')
  printf '"%s","%s","%s","%s","%s","%s","%s"\n' \
    "$CALL" "$FNAME" "$NAME" "$ADDR" "$STATE" "$COUNTRY" "$timestamp" >> "$CSV_FILE"
  echo "💾 Appended to $CSV_FILE"
fi

# --- Optional Unified JSON export ---
if [ "$EXPORT_CSV" = "--json" ]; then
  JSON_FILE="${JSON_FILE:-qrz_callsigns.json}"

  # Create a temporary JSON object for this record
  NEW_ENTRY=$(mktemp)
  cat <<EOF > "$NEW_ENTRY"
{
  "call": "$CALL",
  "fname": "$FNAME",
  "name": "$NAME",
  "addr": "$ADDR",
  "state": "$STATE",
  "country": "$COUNTRY",
  "timestamp": "$(date +'%Y-%m-%d %H:%M:%S')"
}
EOF

  # If file doesn't exist or is empty, start a new JSON array
  if [ ! -s "$JSON_FILE" ]; then
    echo "[" > "$JSON_FILE"
    cat "$NEW_ENTRY" >> "$JSON_FILE"
    echo "]" >> "$JSON_FILE"
  else
    # Ensure JSON_FILE contains a valid array, even if damaged
    if ! jq empty "$JSON_FILE" >/dev/null 2>&1; then
      echo "⚠️  Warning: fixing invalid JSON file."
      echo "[" > "$JSON_FILE"
      cat "$NEW_ENTRY" >> "$JSON_FILE"
      echo "]" >> "$JSON_FILE"
    else
      # Append safely using jq
      jq --slurpfile new "$NEW_ENTRY" '. + $new' "$JSON_FILE" > "${JSON_FILE}.tmp" && mv "${JSON_FILE}.tmp" "$JSON_FILE"
    fi
  fi

  rm -f "$NEW_ENTRY"
  echo "💾 Appended to $JSON_FILE"
fi

