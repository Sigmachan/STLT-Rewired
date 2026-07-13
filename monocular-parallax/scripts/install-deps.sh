#!/usr/bin/env bash
# Install system dependencies for Monocular Parallax on Debian/Ubuntu.
set -euo pipefail

if [[ $EUID -ne 0 ]]; then
    echo "Run as root: sudo $0"
    exit 1
fi

apt-get update
apt-get install -y \
    python3 python3-pip python3-venv \
    libv4l-dev v4l-utils \
    libgl1-mesa-dev libglib2.0-0 \
    libevdev-dev

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"

python3 -m venv /opt/parallax/venv
/opt/parallax/venv/bin/pip install --upgrade pip
/opt/parallax/venv/bin/pip install -e "${PROJECT_ROOT}[linux]"

ln -sf /opt/parallax/venv/bin/parallax-daemon /usr/local/bin/parallax-daemon
ln -sf /opt/parallax/venv/bin/parallax-calibrate /usr/local/bin/parallax-calibrate
ln -sf /opt/parallax/venv/bin/parallax-x11-warp /usr/local/bin/parallax-x11-warp

install -d /etc/parallax
install -m 644 "${PROJECT_ROOT}/config/default.yaml" /etc/parallax/default.yaml
install -m 644 "${PROJECT_ROOT}/deploy/parallax-tracker.service" /etc/systemd/system/

echo "Done. Edit /etc/parallax/default.yaml, then:"
echo "  systemctl enable --now parallax-tracker"
