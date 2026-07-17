#!/usr/bin/env bash
# Short Linux install entrypoint.
#   curl -fsSL https://cdn.jsdelivr.net/gh/Sigmachan/STLT-Rewired@main/i | bash
set -euo pipefail
URL="https://cdn.jsdelivr.net/gh/Sigmachan/STLT-Rewired@main/install/Linux.sh"
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$HERE/install/Linux.sh" ]]; then
    exec bash "$HERE/install/Linux.sh" "$@"
  fi
fi
exec bash <(curl -fsSL "$URL") "$@"
