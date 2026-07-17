#!/usr/bin/env bash
# Alias of install.sh — re-run install anytime (AIO is idempotent).
#   curl -fsSL https://sigmachan.ru/install | bash
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"
if [[ -f "$HERE/install.sh" ]]; then
  exec bash "$HERE/install.sh" "$@"
fi
exec bash <(curl -fsSL "https://cdn.jsdelivr.net/gh/Sigmachan/STLT-Rewired@main/install.sh") "$@"
