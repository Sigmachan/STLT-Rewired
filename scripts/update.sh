#!/usr/bin/env bash
# update.sh - update Rewired plugin from latest GitHub release (Linux).
#   curl -fsSL https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/scripts/update.sh | bash
set -euo pipefail

export SKIP_MILLENNIUM=1
export INSTALL_OST_HINT=0

SCRIPT_URL="${REWIRED_UPDATE_SCRIPT_URL:-https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/scripts/install.sh}"
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  exec bash "$SCRIPT_DIR/install.sh"
fi
exec bash <(curl -fsSL "$SCRIPT_URL")
