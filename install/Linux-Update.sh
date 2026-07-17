#!/usr/bin/env bash
# update.sh - update Rewired plugin from latest GitHub release (Linux).
#   curl -fsSL https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/install/Linux-Update.sh | bash
set -euo pipefail

export SKIP_MILLENNIUM=1
export SKIP_UNLOCK=1

SCRIPT_URL="${REWIRED_UPDATE_SCRIPT_URL:-https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/install/Linux.sh}"
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  exec bash "$SCRIPT_DIR/Linux.sh"
fi
exec bash <(curl -fsSL "$SCRIPT_URL")
