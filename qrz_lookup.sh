#!/usr/bin/env bash

set -euo pipefail

SESSION_FILE="./.qrz_session"
SESSION_LIFETIME_MINUTES=60   # Typical QRZ session timeout

# --- Helper: check if session key is valid ---
check_session_valid() {
  local session_key=$1
  local response
  response=$(curl -sSL "https://xmldata.qrz.com/xml/current/?s=${session_key};callsign=TEST")
  if echo "$response" | grep -q "<Error>Invalid session key"; then
    return 1
  fi
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
    local file_age_mins=$(( ( $(date +%s) - $(get_mtime "$SESSION_FILE") ) / 60 ))
    #local file_age_mins=$(( ( $(date +%s) - $(stat -f %m "$SESSION_FILE") ) / 60 ))
    local cached_key
    cached_key=$(tr -d '\r\n' < "$SESSION_FILE")

    if [ "$file_age_mins" -lt "$SESSION_LIFETIME_MINUTES" ]; then
      printf "🕐 Checking cached session key...\n" >&2
      if check_session_valid "$cached_key"; then
        printf "✅ Using cached session key: $cached_key\n" >&2
        echo "$cached_key"
        return 0
      else
        echo "⚠️ Cached session key invalid or expired." >&2
      fi
    else
      echo "⚠️ Cached session file too old (${file_age_mins} min)." >&2
    fi
  fi

  get_new_session
}

# --- Helper: perform a callsign lookup ---
perform_lookup() {
  local session=$1
  local callsign=$2

  local call_xml
  call_xml=$(curl -sSL -G \
    --data-urlencode "s=${session}" \
    --data-urlencode "callsign=${callsign}" \
    "https://xmldata.qrz.com/xml/current/")

 # Check for <Error> in the XML; quit if found
  if echo "$call_xml" | grep -q "<Error>"; then
    echo "❌ Grabbed new QRZ session. Exiting." >&2
    exit 1
  fi

  # --- Extract fields (global variables) ---
  CALL=$(printf '%s' "$call_xml" | sed -n 's:.*<call>\(.*\)</call>.*:\1:p' | head -n1)
  FNAME=$(printf '%s' "$call_xml" | sed -n 's:.*<fname>\(.*\)</fname>.*:\1:p' | head -n1)
  NAME=$(printf '%s' "$call_xml" | sed -n 's:.*<name>\(.*\)</name>.*:\1:p' | head -n1)
  ADDR=$(printf '%s' "$call_xml" | sed -n 's:.*<addr2>\(.*\)</addr2>.*:\1:p' | head -n1)
  STATE=$(printf '%s' "$call_xml" | sed -n 's:.*<state>\(.*\)</state>.*:\1:p' | head -n1)
  COUNTRY=$(printf '%s' "$call_xml" | sed -n 's:.*<country>\(.*\)</country>.*:\1:p' | head -n1)

  # --- Print result ---
  echo
  echo "📡 Callsign lookup result:"
  echo "  Call:     $CALL"
  echo "  Name:     $FNAME $NAME"
  echo "  Location: $ADDR, $STATE"
  echo "  Country:  $COUNTRY"
  echo
}

# --- Helper: export to CSV ---
export_csv() {
  local csv_file="${CSV_FILE:-qrz_callsigns.csv}"
  [ ! -f "$csv_file" ] && printf "call,fname,name,addr,state,country,timestamp\n" > "$csv_file"
  local timestamp
  timestamp=$(date +'%Y-%m-%d %H:%M:%S')
  printf '"%s","%s","%s","%s","%s","%s","%s"\n' \
    "$CALL" "$FNAME" "$NAME" "$ADDR" "$STATE" "$COUNTRY" "$timestamp" >> "$csv_file"
  echo "💾 Appended to $csv_file"
}

# --- Helper: export to JSON ---
export_json() {
  local json_file="${JSON_FILE:-qrz_callsigns.json}"
  local new_entry
  new_entry=$(mktemp)
  cat <<EOF > "$new_entry"
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

  if [ ! -s "$json_file" ]; then
    echo "[" > "$json_file"
    cat "$new_entry" >> "$json_file"
    echo "]" >> "$json_file"
  else
    if ! jq empty "$json_file" >/dev/null 2>&1; then
      echo "⚠️  Warning: fixing invalid JSON file."
      echo "[" > "$json_file"
      cat "$new_entry" >> "$json_file"
      echo "]" >> "$json_file"
    else
      jq --slurpfile new "$new_entry" '. + $new' "$json_file" > "${json_file}.tmp" && mv "${json_file}.tmp" "$json_file"
    fi
  fi
  rm -f "$new_entry"
  echo "💾 Appended to $json_file"
}

# --- Helper: cross-platform stat mtime ---
get_mtime() {
  if stat --version >/dev/null 2>&1; then
    stat -c %Y "$1"        # Linux (GNU)
  else
    stat -f %m "$1"        # macOS (BSD)
  fi
}

# --- MAIN SCRIPT ---

if [ $# -lt 1 ]; then
  echo "Usage: $0 CALLSIGN [--csv|--json]"
  echo "Example: $0 N8CUB --csv"
  exit 1
fi

CALLSIGN=$(echo "$1" | tr '[:lower:]' '[:upper:]')
EXPORT_OPTION=${2:-}

SESSION=$(get_session)

perform_lookup "$SESSION" "$CALLSIGN"

case "$EXPORT_OPTION" in
  --csv)  
    export_csv
    ;;
  --json) 
    export_json
    ;;
  --both|--csvjson)
    export_csv
    export_json
    ;;
  "")
    # No export requested
    ;;
  *)
    echo "⚠️ Unknown export option: $EXPORT_OPTION"
    ;;
esac
