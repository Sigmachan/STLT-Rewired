#!/usr/bin/env bash
# install.sh - Rewired plugin + Millennium + Linux unlock stack (ACCELA + SLSsteam).
#   curl -fsSL https://raw.githubusercontent.com/Sigmachan/STLT-Rewired/main/install/Linux.sh | bash
#
# Env overrides:
#   STEAM_PATH=...           Steam root
#   SKIP_MILLENNIUM=1        do not install Millennium
#   SKIP_UNLOCK=1            do not install ACCELA + SLSsteam
#   SKIP_PLUGIN=1            do not install/update the Rewired plugin
#   GITHUB_TOKEN / GH_TOKEN  higher GitHub API rate limit
set -euo pipefail

REWIRED_OWNER="${REWIRED_OWNER:-Sigmachan}"
REWIRED_REPO="${REWIRED_REPO:-STLT-Rewired}"
PLUGIN_ASSET="${PLUGIN_ASSET:-STLT-Rewired.zip}"
TAG_PREFIX="${TAG_PREFIX:-v}"
SKIP_MILLENNIUM="${SKIP_MILLENNIUM:-0}"
SKIP_UNLOCK="${SKIP_UNLOCK:-0}"
SKIP_PLUGIN="${SKIP_PLUGIN:-0}"

# Community Linux unlock combo installer (ACCELA + Headcrab/SLSsteam).
ENTER_THE_WIRED_URL="${ENTER_THE_WIRED_URL:-https://raw.githubusercontent.com/ciscosweater/enter-the-wired/main/enter-the-wired}"

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
  local headers=()
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    headers=(-H "Authorization: Bearer ${GITHUB_TOKEN}")
  elif [[ -n "${GH_TOKEN:-}" ]]; then
    headers=(-H "Authorization: Bearer ${GH_TOKEN}")
  fi
  curl -fsSL "${headers[@]}" "https://api.github.com/repos/${REWIRED_OWNER}/${REWIRED_REPO}/releases/latest"
}

plugin_download_url() {
  local url=""
  if url="$(fetch_latest_release 2>/dev/null | python3 -c "
import json,sys,os
d=json.load(sys.stdin)
asset=os.environ.get('PLUGIN_ASSET','STLT-Rewired.zip')
for a in d.get('assets',[]):
    if a.get('name')==asset:
        print(a['browser_download_url'])
        break
" 2>/dev/null)"; then
    if [[ -n "$url" ]]; then
      echo "$url"
      return
    fi
  fi
  warn "GitHub API unavailable or rate limited; using direct download URL."
  warn "Tip: export GITHUB_TOKEN for a higher API limit."
  echo "https://github.com/${REWIRED_OWNER}/${REWIRED_REPO}/releases/latest/download/${PLUGIN_ASSET}"
}

release_version() {
  local ver=""
  if ver="$(fetch_latest_release 2>/dev/null | python3 -c "
import json,sys
d=json.load(sys.stdin)
tag=d.get('tag_name','')
prefix='${TAG_PREFIX}'
print(tag[len(prefix):] if prefix and tag.startswith(prefix) else tag)
" 2>/dev/null)"; then
    if [[ -n "$ver" ]]; then
      echo "$ver"
      return
    fi
  fi
  echo "latest"
}

unlock_already_present() {
  [[ -d "$HOME/.local/share/ACCELA" ]] || return 1
  if [[ -d "$HOME/.local/share/SLSsteam" ]] || [[ -d "$HOME/.var/app/com.valvesoftware.Steam/.local/share/SLSsteam" ]]; then
    return 0
  fi
  return 1
}

install_unlock_stack() {
  if [[ "$SKIP_UNLOCK" == "1" ]]; then
    warn "Skipping ACCELA + SLSsteam install (SKIP_UNLOCK=1)."
    return
  fi

  if unlock_already_present; then
    ok "ACCELA + SLSsteam already present — skipping unlock installer."
    info "Re-run unlock only: curl -fsSL https://raw.githubusercontent.com/${REWIRED_OWNER}/${REWIRED_REPO}/main/install/Linux-Unlock.sh | bash"
    return
  fi

  need_cmd tar
  info "Installing Linux unlock stack (ACCELA + SLSsteam via enter-the-wired)..."
  info "Source: ${ENTER_THE_WIRED_URL}"
  # Download to a temp file so the remote script can resolve its own path, then run.
  local tmp
  tmp="$(mktemp -t rewired-enter-the-wired.XXXX.sh)"
  # shellcheck disable=SC2064
  trap 'rm -f "'"$tmp"'"' RETURN
  curl -fsSL --retry 3 --retry-delay 2 "$ENTER_THE_WIRED_URL" -o "$tmp"
  chmod +x "$tmp"
  if ! bash "$tmp"; then
    warn "Unlock installer reported an error."
    warn "You can retry with: curl -fsSL https://raw.githubusercontent.com/${REWIRED_OWNER}/${REWIRED_REPO}/main/install/Linux-Unlock.sh | bash"
    warn "Or install manually: https://github.com/ciscosweater/enter-the-wired"
    return 1
  fi
  ok "Unlock stack installer finished (ACCELA + SLSsteam)."
}

install_millennium_if_needed() {
  local steam="$1"
  if [[ "$SKIP_MILLENNIUM" == "1" ]]; then
    warn "Skipping Millennium install (SKIP_MILLENNIUM=1)."
    return
  fi
  if [[ -d "$steam/millennium/bin" ]] && { [[ -f "$steam/wsock32.dll" ]] || [[ -f "$steam/millennium/wsock32.dll" ]] || [[ -f "$steam/millennium/libmillennium_x86.so" ]] || [[ -d "$steam/millennium/lib" ]]; }; then
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
  # shellcheck disable=SC2064
  trap 'rm -rf "'"$work"'"' RETURN

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
  "unlockBackend": "steamtools",
  "millenniumOptional": false,
  "pluginPath": "$steam/millennium/plugins/luatools",
  "linuxUnlock": "slssteam+accela"
}
EOF
  ok "Shared config -> $cfg_dir/rewired.json"
}

ensure_stplugin_dir() {
  local steam="$1"
  local dir="$steam/config/stplug-in"
  mkdir -p "$dir"
  ok "Unlock script dir -> $dir"
}

main() {
  local steam url ver
  steam="$(detect_steam)"
  ver="$(release_version)"
  info "Rewired ${ver} -> Steam at ${steam}"

  # Unlock first so Steam restarts pick up SLSsteam/ACCELA.
  install_unlock_stack || warn "Continuing without a fresh unlock install."

  install_millennium_if_needed "$steam"

  if [[ "$SKIP_PLUGIN" == "1" ]]; then
    warn "Skipping Rewired plugin install (SKIP_PLUGIN=1)."
  else
    url="$(plugin_download_url)"
    [[ -n "$url" ]] || die "No ${PLUGIN_ASSET} on latest GitHub release."
    install_plugin "$steam" "$url"
  fi

  ensure_stplugin_dir "$steam"
  write_shared_config "$steam"

  ok "Done."
  info "1. Fully quit Steam, then relaunch through your unlock stack (or normal Steam if SLSsteam already patched it)."
  info "2. Enable luatools (Rewired) in Millennium -> Plugins."
  info "Unlock-only reinstall: curl -fsSL https://raw.githubusercontent.com/${REWIRED_OWNER}/${REWIRED_REPO}/main/install/Linux-Unlock.sh | bash"
  info "Plugin update later: curl -fsSL https://raw.githubusercontent.com/${REWIRED_OWNER}/${REWIRED_REPO}/main/install/Linux-Update.sh | bash"
}

main "$@"
