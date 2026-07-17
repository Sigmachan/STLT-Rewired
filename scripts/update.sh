#!/usr/bin/env bash
# Compat shim — prefer: curl -fsSL …/install/Linux-Update.sh | bash
set -euo pipefail
ROOT_URL="https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/install/Linux-Update.sh"
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$HERE/../install/Linux-Update.sh" ]]; then
    exec bash "$HERE/../install/Linux-Update.sh" "$@"
  fi
fi
exec bash <(curl -fsSL "$ROOT_URL") "$@"
