#!/usr/bin/env bash
# Compat shim — prefer: curl -fsSL …/install/Linux.sh | bash
set -euo pipefail
ROOT_URL="https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/install/Linux.sh"
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$HERE/../install/Linux.sh" ]]; then
    exec bash "$HERE/../install/Linux.sh" "$@"
  fi
fi
exec bash <(curl -fsSL "$ROOT_URL") "$@"
