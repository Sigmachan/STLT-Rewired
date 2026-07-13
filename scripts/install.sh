#!/usr/bin/env bash
# install.sh - Rewired plugin + Millennium on Linux (Steam native only).
#   curl -fsSL https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/scripts/install.sh | bash
set -euo pipefail

REWIRED_OWNER="${REWIRED_OWNER:-Sigmachan}"
REWIRED_REPO="${REWIRED_REPO:-STLT-Rewired}"
PLUGIN_ASSET="${PLUGIN_ASSET:-STLT-Rewired.zip}"
TAG_PREFIX="${TAG_PREFIX:-v}"
SKIP_MILLENNIUM="${SKIP_MILLENNIUM:-0}"
INSTALL_OST_HINT="${INSTALL_OST_HINT:-1}"

info() { printf '\033[36m%s\033[0m\n' "$*"; }
ok() { printf '\033[32m%s\033[0m\n' "$*"; }
warn() { printf '\033[33m%s\033[0m\n' "$*"; }
die() { printf '\033[31m%s\033[0m\n' "$*" >&2; exit 1; }

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "Missing required command: $1"
}

need_cmd curl
need_cmd unzip
need_cmd python3

detect_steam() {
  if [[ -n "${STEAM_PATH:-}" && -d "$STEAM_PATH" ]]; then
    echo "$STEAM_PATH"
    return
  fi
  for p in "$HOME/.steam/root" "$HOME/.steam/steam" "$HOME/.local/share/Steam"; do
    if [[ -d "$p" && -f "$p/steam.sh" ]]; then
      echo "$p"
      return
    fi
  done
  die "Steam not found. Set STEAM_PATH to your Steam root."
}

fetch_latest_release() {
  curl -fsSL "https://api.github.com/repos/${REWIRED_OWNER}/${REWIRED_REPO}/releases/latest"
}

plugin_download_url() {
  fetch_latest_release | python3 -c "
import json,sys,os
d=json.load(sys.stdin)
asset=os.environ.get('PLUGIN_ASSET','STLT-Rewired.zip')
for a in d.get('assets',[]):
    if a.get('name')==asset:
        print(a['browser_download_url'])
        break
"
}

release_version() {
  fetch_latest_release | python3 -c "
import json,sys
d=json.load(sys.stdin)
tag=d.get('tag_name','')
prefix='${TAG_PREFIX}'
print(tag[len(prefix):] if prefix and tag.startswith(prefix) else tag)
"
}

install_millennium_if_needed() {
  local steam="$1"
  if [[ "$SKIP_MILLENNIUM" == "1" ]]; then
    warn "Skipping Millennium install (SKIP_MILLENNIUM=1)."
    return
  fi
  if [[ -d "$steam/millennium/bin" && -f "$steam/wsock32.dll" || -f "$steam/millennium/wsock32.dll" ]]; then
    info "Millennium appears installed."
    return
  fi
  info "Installing Millennium via steambrew.app installer..."
  curl -fsSL "https://steambrew.app/install.sh" | bash
}

install_plugin() {
  local steam="$1"
  local url="$2"
  local work plugin_root preserved
  work="$(mktemp -d)"
  plugin_root="$steam/millennium/plugins/luatools"
  trap 'rm -rf "$work"' EXIT

  curl -fsSL "$url" -o "$work/plugin.zip"
  unzip -q "$work/plugin.zip" -d "$work/extract"

  if [[ -d "$plugin_root/backend/data" ]]; then
    preserved="$work/preserved-data"
    cp -a "$plugin_root/backend/data" "$preserved"
  fi

  rm -rf "$plugin_root"
  mkdir -p "$(dirname "$plugin_root")"
  cp -a "$work/extract/." "$plugin_root/"

  if [[ -n "${preserved:-}" && -d "$preserved" ]]; then
    mkdir -p "$plugin_root/backend/data"
    cp -a "$preserved/." "$plugin_root/backend/data/"
  fi

  ok "Plugin installed -> $plugin_root"
}

write_shared_config() {
  local steam="$1"
  local cfg_dir="$HOME/.local/share/Rewired"
  mkdir -p "$cfg_dir"
  cat >"$cfg_dir/rewired.json" <<EOF
{
  "version": 1,
  "steamPath": "$steam",
  "unlockBackend": "auto",
  "millenniumOptional": false,
  "pluginPath": "$steam/millennium/plugins/luatools"
}
EOF
  ok "Shared config -> $cfg_dir/rewired.json"
}

main() {
  local steam url ver
  steam="$(detect_steam)"
  url="$(plugin_download_url)"
  [[ -n "$url" ]] || die "No ${PLUGIN_ASSET} on latest GitHub release."
  ver="$(release_version)"
  info "Rewired ${ver} -> Steam at ${steam}"

  install_millennium_if_needed "$steam"
  install_plugin "$steam" "$url"
  write_shared_config "$steam"

  if [[ "$INSTALL_OST_HINT" == "1" ]]; then
    warn "Linux unlock stack is not bundled here."
    warn "Install SLSsteam + ACCELA (see LuaToolsLinux / enter-the-wired), then restart Steam through that stack."
    warn "  https://github.com/ciscosweater/enter-the-wired"
    warn "  https://github.com/AceSLS/SLSsteam"
  fi

  ok "Done. Restart Steam. Enable luatools (Rewired) in Millennium -> Plugins."
  info "Update later: curl -fsSL https://raw.githubusercontent.com/${REWIRED_OWNER}/${REWIRED_REPO}/main/scripts/update.sh | bash"
}

main "$@"
