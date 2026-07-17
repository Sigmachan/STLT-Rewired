#!/usr/bin/env bash
# install/Linux.sh — Rewired AIO for many Linux distros
# (CachyOS, Bazzite, ChimeraOS, Nobara, Ximper, Ubuntu, Fedora, Arch, …).
#   curl -fsSL https://sigmachan.ru/install | bash
#
# Env overrides:
#   STEAM_PATH=...           Steam root (native or Flatpak data dir)
#   SKIP_MILLENNIUM=1        do not install Millennium
#   SKIP_UNLOCK=1            do not install ACCELA + SLSsteam
#   SKIP_PLUGIN=1            do not install/update the Rewired plugin
#   MILLENNIUM_VERSION=...   pin Millennium tag (default v3.4.0-beta.9)
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

# Prefer python3, fall back to python (some minimal images).
resolve_python() {
  if command -v python3 >/dev/null 2>&1; then
    echo python3
  elif command -v python >/dev/null 2>&1; then
    echo python
  else
    die "Missing required command: python3 (or python)"
  fi
}

PYTHON_BIN="$(resolve_python)"
need_cmd curl
command -v unzip >/dev/null 2>&1 || need_cmd busybox
need_cmd tar

detect_distro() {
  local id="" like="" name=""
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    id="${ID:-}"
    like="${ID_LIKE:-}"
    name="${NAME:-$id}"
  fi
  # Normalize common gaming / desktop distros (labels only — Steam paths are shared).
  case "${id,,}" in
    cachyos*) echo "CachyOS" ;;
    bazzite*) echo "Bazzite" ;;
    chimeraos*|chameleon*) echo "ChimeraOS" ;;
    ximper*|altlinux*|altlinux) echo "Ximper/ALT" ;;
    steamos*|holo*|holoiso*) echo "SteamOS" ;;
    nobara*) echo "Nobara" ;;
    garuda*) echo "Garuda" ;;
    endeavouros*) echo "EndeavourOS" ;;
    arch*|manjaro*|artix*) echo "${name:-Arch}" ;;
    fedora*|rhel*|centos*|rocky*|almalinux*|ol*) echo "${name:-Fedora}" ;;
    ubuntu*|debian*|linuxmint*|pop*|elementary*|zorin*|kali*) echo "${name:-Debian/Ubuntu}" ;;
    opensuse*|suse*) echo "${name:-openSUSE}" ;;
    void*) echo "Void" ;;
    gentoo*|calculate*) echo "Gentoo" ;;
    nixos*) echo "NixOS" ;;
    solus*) echo "Solus" ;;
    *)
      if [[ "${like,,}" == *arch* ]]; then echo "${name:-Arch-like}"
      elif [[ "${like,,}" == *fedora* ]] || [[ "${like,,}" == *rhel* ]]; then echo "${name:-Fedora-like}"
      elif [[ "${like,,}" == *debian* ]] || [[ "${like,,}" == *ubuntu* ]]; then echo "${name:-Debian-like}"
      else echo "${name:-Linux}"
      fi
      ;;
  esac
}

is_steam_root() {
  local p="$1"
  [[ -d "$p" ]] || return 1
  # Resolve symlinks (.steam/root → real data dir on Arch/CachyOS/Ximper).
  if command -v readlink >/dev/null 2>&1; then
    p="$(readlink -f "$p" 2>/dev/null || echo "$p")"
  fi
  [[ -f "$p/steam.sh" ]] && return 0
  [[ -d "$p/steamapps" ]] && return 0
  [[ -d "$p/ubuntu12_32" ]] && return 0
  [[ -f "$p/steamclient.so" || -f "$p/linux64/steamclient.so" ]] && return 0
  return 1
}

# Score: prefer roots that already have a library / millennium / unlock scripts.
steam_root_score() {
  local p="$1" score=0
  [[ -f "$p/steam.sh" ]] && score=$((score + 2))
  [[ -d "$p/steamapps" ]] && score=$((score + 3))
  [[ -d "$p/config" ]] && score=$((score + 1))
  [[ -d "$p/millennium" ]] && score=$((score + 2))
  [[ -d "$p/config/stplug-in" ]] && score=$((score + 2))
  # Flatpak Steam is primary on Bazzite — slight boost when under .var/app.
  case "$p" in
    *".var/app/com.valvesoftware.Steam"*) score=$((score + 1)) ;;
  esac
  echo "$score"
}

detect_steam() {
  local p cand best="" best_score=-1 score
  if [[ -n "${STEAM_PATH:-}" ]]; then
    p="$STEAM_PATH"
    if command -v readlink >/dev/null 2>&1; then
      p="$(readlink -f "$p" 2>/dev/null || echo "$p")"
    fi
    if is_steam_root "$p"; then
      echo "$p"
      return
    fi
    die "STEAM_PATH is set but does not look like a Steam root: $STEAM_PATH"
  fi

  # Ordered candidates: native first, then Flatpak (Bazzite), Snap, Deck/home variants.
  local candidates=(
    "$HOME/.local/share/Steam"
    "$HOME/.steam/steam"
    "$HOME/.steam/root"
    "$HOME/.steam/debian-installation"
    "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"
    "$HOME/.var/app/com.valvesoftware.Steam/data/Steam"
    "$HOME/snap/steam/common/.local/share/Steam"
    "$HOME/.local/share/steam"          # rare lowercase
    "/usr/share/steam"                  # system packages (some ALT/RPM)
  )

  for cand in "${candidates[@]}"; do
    [[ -e "$cand" ]] || continue
    p="$cand"
    if command -v readlink >/dev/null 2>&1; then
      p="$(readlink -f "$cand" 2>/dev/null || echo "$cand")"
    fi
    is_steam_root "$p" || continue
    score="$(steam_root_score "$p")"
    if (( score > best_score )); then
      best="$p"
      best_score=$score
    fi
  done

  if [[ -n "$best" ]]; then
    echo "$best"
    return
  fi

  die "Steam not found (checked native, Flatpak, and Snap paths).
Set STEAM_PATH to your Steam root, e.g.:
  export STEAM_PATH=\"\$HOME/.local/share/Steam\"                    # CachyOS / Ximper / Arch
  export STEAM_PATH=\"\$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam\"  # Bazzite Flatpak"
}

unzip_into() {
  local zip="$1" dest="$2"
  mkdir -p "$dest"
  if command -v unzip >/dev/null 2>&1; then
    unzip -q "$zip" -d "$dest"
  elif command -v busybox >/dev/null 2>&1; then
    busybox unzip -q "$zip" -d "$dest"
  else
    "$PYTHON_BIN" - "$zip" "$dest" <<'PY'
import sys, zipfile
zipfile.ZipFile(sys.argv[1]).extractall(sys.argv[2])
PY
  fi
}

DISTRO_LABEL="$(detect_distro)"

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
  if url="$(fetch_latest_release 2>/dev/null | "$PYTHON_BIN" -c "
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
  if ver="$(fetch_latest_release 2>/dev/null | "$PYTHON_BIN" -c "
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
  [[ -d "$HOME/.local/share/ACCELA" ]] || [[ -d "$HOME/.config/ACCELA" ]] || return 1
  if [[ -d "$HOME/.local/share/SLSsteam" ]] \
    || [[ -d "$HOME/.config/SLSsteam" ]] \
    || [[ -d "$HOME/.var/app/com.valvesoftware.Steam/.local/share/SLSsteam" ]]; then
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
    info "Force unlock reinstall: FORCE=1 curl -fsSL https://sigmachan.ru/unlock | bash"
    return
  fi

  need_cmd tar
  info "Installing Linux unlock stack (ACCELA + SLSsteam via enter-the-wired)..."
  info "Source: ${ENTER_THE_WIRED_URL}"
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/rewired-enter-the-wired.XXXXXX")"
  curl -fsSL --retry 3 --retry-delay 2 "$ENTER_THE_WIRED_URL" -o "$tmp"
  chmod +x "$tmp"
  # Help combo installers find Flatpak / custom Steam roots (Bazzite, etc.).
  if [[ -n "${STEAM_ROOT:-}" ]]; then
    export STEAM_PATH="${STEAM_PATH:-$STEAM_ROOT}"
    export STEAM_DIR="${STEAM_DIR:-$STEAM_ROOT}"
  fi
  if ! bash "$tmp"; then
    rm -f "$tmp"
    warn "Unlock installer reported an error."
    warn "You can retry with: curl -fsSL https://sigmachan.ru/unlock | bash"
    warn "Or install manually: https://github.com/ciscosweater/enter-the-wired"
    return 1
  fi
  rm -f "$tmp"
  ok "Unlock stack installer finished (ACCELA + SLSsteam)."
}

install_millennium_if_needed() {
  local steam="$1"
  local ver="${MILLENNIUM_VERSION:-v3.4.0-beta.9}"
  local url work
  if [[ "$SKIP_MILLENNIUM" == "1" ]]; then
    warn "Skipping Millennium install (SKIP_MILLENNIUM=1)."
    return
  fi
  if [[ -d "$steam/millennium/bin" ]] && { [[ -f "$steam/wsock32.dll" ]] || [[ -f "$steam/millennium/wsock32.dll" ]] || [[ -f "$steam/millennium/libmillennium_x86.so" ]] || [[ -d "$steam/millennium/lib" ]]; }; then
    info "Millennium appears installed."
    return
  fi
  if [[ -f "$steam/millennium/libmillennium_x86.so" ]] || [[ -f "$steam/millennium/lib/libmillennium_x86.so" ]]; then
    info "Millennium appears installed."
    return
  fi

  need_cmd tar
  info "Installing Millennium ${ver} from GitHub releases..."
  url="https://github.com/SteamClientHomebrew/Millennium/releases/download/${ver}/millennium-${ver}-linux-x86_64.tar.gz"
  work="$(mktemp -d)"
  curl -fsSL --retry 3 --retry-delay 2 "$url" -o "$work/millennium.tar.gz"
  mkdir -p "$work/extract"
  tar -xzf "$work/millennium.tar.gz" -C "$work/extract"
  mkdir -p "$steam/millennium"
  if [[ -d "$work/extract/usr/lib/millennium" ]]; then
    cp -a "$work/extract/usr/lib/millennium/." "$steam/millennium/"
  elif [[ -d "$work/extract/millennium" ]]; then
    cp -a "$work/extract/millennium/." "$steam/millennium/"
  else
    rm -rf "$work"
    die "Millennium archive layout unrecognized (expected usr/lib/millennium)."
  fi
  rm -rf "$work"
  ok "Millennium ${ver} -> $steam/millennium"
}

install_plugin() {
  local steam="$1"
  local url="$2"
  local work plugin_root preserved
  work="$(mktemp -d)"
  plugin_root="$steam/millennium/plugins/luatools"

  curl -fsSL "$url" -o "$work/plugin.zip"
  unzip_into "$work/plugin.zip" "$work/extract"

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

  rm -rf "$work"
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
  info "Distro: ${DISTRO_LABEL}"
  steam="$(detect_steam)"
  STEAM_ROOT="$steam"
  export STEAM_ROOT STEAM_PATH="${STEAM_PATH:-$steam}" STEAM_DIR="${STEAM_DIR:-$steam}"
  ver="$(release_version)"
  info "Rewired ${ver} -> Steam at ${steam}"
  case "$steam" in
    *".var/app/com.valvesoftware.Steam"*)
      info "Flatpak Steam detected (common on Bazzite). Launch Steam via Flatpak after install."
      ;;
  esac

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
  info "Re-run anytime: curl -fsSL https://sigmachan.ru/install | bash"
}

main "$@"
