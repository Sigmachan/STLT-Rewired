#!/usr/bin/env bash
# Linux install entrypoint (Millennium + plugin + ACCELA/SLSsteam).
#   curl -fsSL https://sigmachan.ru/install | bash
# Env overrides must be on the bash side of the pipe, e.g.:
#   curl -fsSL https://sigmachan.ru/install | STEAM_PATH="$HOME/.local/share/Steam" bash
set -euo pipefail
URL="https://cdn.jsdelivr.net/gh/Sigmachan/STLT-Rewired@main/install/Linux.sh"
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$HERE/install/Linux.sh" ]]; then
    exec bash "$HERE/install/Linux.sh" "$@"
  fi
fi
curl -fsSL "$URL" | bash -s -- "$@"
