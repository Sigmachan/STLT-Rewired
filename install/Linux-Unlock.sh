#!/usr/bin/env bash
# install-linux-unlock.sh - Install ACCELA + SLSsteam (via enter-the-wired / Headcrab).
#   curl -fsSL https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/install/Linux-Unlock.sh | bash
#
# This does NOT install Millennium or the Rewired plugin — use install/Linux.sh for the full stack.
# Force reinstall even if present: FORCE=1 ...
set -euo pipefail

ENTER_THE_WIRED_URL="${ENTER_THE_WIRED_URL:-https://raw.githubusercontent.com/ciscosweater/enter-the-wired/main/enter-the-wired}"
FORCE="${FORCE:-0}"

info() { printf '\033[36m%s\033[0m\n' "$*"; }
ok() { printf '\033[32m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

command -v curl >/dev/null 2>&1 || die "Missing required command: curl"
command -v tar >/dev/null 2>&1 || die "Missing required command: tar"

already_present() {
  [[ -d "$HOME/.local/share/ACCELA" ]] || return 1
  if [[ -d "$HOME/.local/share/SLSsteam" ]] || [[ -d "$HOME/.var/app/com.valvesoftware.Steam/.local/share/SLSsteam" ]]; then
    return 0
  fi
  return 1
}

if [[ "$FORCE" != "1" ]] && already_present; then
  ok "ACCELA + SLSsteam already look installed."
  info "ACCELA:  $HOME/.local/share/ACCELA"
  info "Force reinstall: FORCE=1 curl -fsSL https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/install/Linux-Unlock.sh | bash"
  exit 0
fi

info "Installing ACCELA + SLSsteam via enter-the-wired..."
info "Upstream: https://github.com/ciscosweater/enter-the-wired"
info "SLSsteam (Headcrab): https://github.com/Deadboy666/h3adcr-b · AceSLS/SLSsteam"

tmp="$(mktemp -t rewired-enter-the-wired.XXXX.sh)"
trap 'rm -f "$tmp"' EXIT
curl -fsSL --retry 3 --retry-delay 2 "$ENTER_THE_WIRED_URL" -o "$tmp"
chmod +x "$tmp"
bash "$tmp"

ok "Unlock install finished."
info "Quit Steam fully, then relaunch. Use ACCELA for add-game / depot flows when needed."
info "Local helper scripts (if saved): ~/enter-the-wired/{accela,slssteam,fix-deps,uninstall}"
