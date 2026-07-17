#!/usr/bin/env bash
# install/Linux-Unlock.sh — ACCELA + SLSsteam only (via enter-the-wired / Headcrab).
#   curl -fsSL https://sigmachan.ru/unlock | bash
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
  # Match install/Linux.sh unlock_already_present (native + config + Flatpak).
  local has_accela=0 has_sls=0
  [[ -d "$HOME/.local/share/ACCELA" ]] && has_accela=1
  [[ -d "$HOME/.config/ACCELA" ]] && has_accela=1
  [[ -d "$HOME/.var/app/com.valvesoftware.Steam/.local/share/ACCELA" ]] && has_accela=1
  [[ -d "$HOME/.var/app/com.valvesoftware.Steam/.config/ACCELA" ]] && has_accela=1
  [[ -d "$HOME/.local/share/SLSsteam" ]] && has_sls=1
  [[ -d "$HOME/.config/SLSsteam" ]] && has_sls=1
  [[ -d "$HOME/.var/app/com.valvesoftware.Steam/.local/share/SLSsteam" ]] && has_sls=1
  [[ -d "$HOME/.var/app/com.valvesoftware.Steam/.config/SLSsteam" ]] && has_sls=1
  (( has_accela && has_sls ))
}

if [[ "$FORCE" != "1" ]] && already_present; then
  ok "ACCELA + SLSsteam already look installed."
  info "Force reinstall: FORCE=1 curl -fsSL https://sigmachan.ru/unlock | bash"
  exit 0
fi
if [[ "$FORCE" == "1" ]] && already_present; then
  warn "FORCE=1 — re-running unlock installer even though ACCELA/SLS look present."
fi

info "Installing ACCELA + SLSsteam via enter-the-wired..."
info "Upstream: https://github.com/ciscosweater/enter-the-wired"
info "SLSsteam (Headcrab): https://github.com/Deadboy666/h3adcr-b · AceSLS/SLSsteam"

# Help combo installers find Flatpak / custom Steam roots (Bazzite, etc.).
if [[ -n "${STEAM_PATH:-}" ]]; then
  export STEAM_DIR="${STEAM_DIR:-$STEAM_PATH}"
elif [[ -n "${STEAM_ROOT:-}" ]]; then
  export STEAM_PATH="${STEAM_PATH:-$STEAM_ROOT}"
  export STEAM_DIR="${STEAM_DIR:-$STEAM_ROOT}"
fi

# Template must end in XXXXXX (GNU/BSD mktemp); do not put .sh after the X's.
tmp="$(mktemp "${TMPDIR:-/tmp}/rewired-enter-the-wired.XXXXXX")"
trap 'rm -f "$tmp"' EXIT
curl -fsSL --retry 3 --retry-delay 2 "$ENTER_THE_WIRED_URL" -o "$tmp"
chmod +x "$tmp"
bash "$tmp"

ok "Unlock install finished."
info "Quit Steam fully, then relaunch. Use ACCELA for add-game / depot flows when needed."
info "Local helper scripts (if saved): ~/enter-the-wired/{accela,slssteam,fix-deps,uninstall}"
