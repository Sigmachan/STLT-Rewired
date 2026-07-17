#!/usr/bin/env bash
# Alias of Linux.sh — re-run full AIO anytime (unlock/Millennium skip if present).
set -euo pipefail
URL="https://cdn.jsdelivr.net/gh/Sigmachan/STLT-Rewired@main/install/Linux.sh"
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$HERE/Linux.sh" ]]; then
    exec bash "$HERE/Linux.sh" "$@"
  fi
fi
curl -fsSL "$URL" | bash -s -- "$@"
