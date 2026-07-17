#!/usr/bin/env bash
# Alias of Linux.sh — re-run full AIO anytime (unlock/Millennium skip if present).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [[ -f "$HERE/Linux.sh" ]]; then
  exec bash "$HERE/Linux.sh" "$@"
fi
exec bash <(curl -fsSL "https://cdn.jsdelivr.net/gh/Sigmachan/STLT-Rewired@main/install/Linux.sh") "$@"
