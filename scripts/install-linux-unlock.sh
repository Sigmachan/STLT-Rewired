#!/usr/bin/env bash
# Compat shim — prefer: curl -fsSL …/install/Linux-Unlock.sh | bash
set -euo pipefail
ROOT_URL="https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/install/Linux-Unlock.sh"
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$HERE/../install/Linux-Unlock.sh" ]]; then
    exec bash "$HERE/../install/Linux-Unlock.sh" "$@"
  fi
fi
exec bash <(curl -fsSL "$ROOT_URL") "$@"
