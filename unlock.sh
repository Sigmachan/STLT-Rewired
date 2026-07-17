#!/usr/bin/env bash
# Linux unlock-only entrypoint (ACCELA + SLSsteam).
#   curl -fsSL https://sigmachan.ru/unlock | bash
#   curl -fsSL https://sigmachan.ru/unlock | FORCE=1 bash
set -euo pipefail
URL="https://cdn.jsdelivr.net/gh/Sigmachan/STLT-Rewired@main/install/Linux-Unlock.sh"
if [[ -n "${BASH_SOURCE[0]:-}" && -f "${BASH_SOURCE[0]}" ]]; then
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$HERE/install/Linux-Unlock.sh" ]]; then
    exec bash "$HERE/install/Linux-Unlock.sh" "$@"
  fi
fi
curl -fsSL "$URL" | bash -s -- "$@"
