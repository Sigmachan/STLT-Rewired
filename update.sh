#!/usr/bin/env bash
# Alias of install.sh — re-run install anytime (AIO is idempotent).
#   curl -fsSL https://sigmachan.ru/update | bash
set -euo pipefail
URL="https://cdn.jsdelivr.net/gh/Sigmachan/STLT-Rewired@main/install.sh"
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$HERE/install.sh" ]]; then
    exec bash "$HERE/install.sh" "$@"
  fi
fi
curl -fsSL "$URL" | bash -s -- "$@"
