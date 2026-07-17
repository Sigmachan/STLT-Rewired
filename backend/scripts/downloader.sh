#!/usr/bin/env bash
# Async download + extract helper for Linux (used by downloads.lua / fixes.lua).
# Usage: downloader.sh <url> <dest_zip> <extract_or_install_dir> <state_json> [cookie]
set -euo pipefail

URL="${1:-}"
DEST_ZIP="${2:-}"
EXTRACT_DIR="${3:-}"
STATE_FILE="${4:-}"
COOKIE="${5:-}"

write_state() {
  local status="$1"
  local err="${2:-}"
  if [[ -n "$err" ]]; then
    printf '{"status":"%s","error":%s}\n' "$status" "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$err")" >"$STATE_FILE"
  else
    printf '{"status":"%s"}\n' "$status" >"$STATE_FILE"
  fi
}

fail() {
  write_state "failed" "$1"
  echo "ERROR: $1" >&2
  sleep 2
  exit 1
}

[[ -n "$URL" && -n "$DEST_ZIP" && -n "$EXTRACT_DIR" && -n "$STATE_FILE" ]] || fail "missing arguments"

mkdir -p "$(dirname "$DEST_ZIP")" "$(dirname "$STATE_FILE")" "$EXTRACT_DIR"
write_state "downloading"

CURL_ARGS=(-fsSL -A "discord(dot)gg/luatools" -o "$DEST_ZIP" "$URL")
if [[ -n "$COOKIE" ]]; then
  CURL_ARGS=(-H "Cookie: $COOKIE" "${CURL_ARGS[@]}")
fi

if ! curl "${CURL_ARGS[@]}"; then
  fail "curl download failed"
fi
[[ -f "$DEST_ZIP" ]] || fail "downloaded archive missing"

write_state "extracting"
if ! unzip -o -q "$DEST_ZIP" -d "$EXTRACT_DIR"; then
  # Some fix archives are tar-compatible via bsdtar/tar
  if command -v tar >/dev/null 2>&1 && tar -xf "$DEST_ZIP" -C "$EXTRACT_DIR" 2>/dev/null; then
    :
  else
    fail "extract failed"
  fi
fi

write_state "extracted"
exit 0
