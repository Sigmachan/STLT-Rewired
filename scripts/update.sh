#!/usr/bin/env bash
# Compat shim — prefer: curl -fsSL https://sigmachan.ru/install | bash
set -euo pipefail
ROOT_URL="https://cdn.jsdelivr.net/gh/Sigmachan/STLT-Rewired@main/install.sh"
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$HERE/../install.sh" ]]; then
    exec bash "$HERE/../install.sh" "$@"
  fi
fi
exec bash <(curl -fsSL "$ROOT_URL") "$@"
