# Monocular Parallax Tracker

High-performance Linux daemon and calibration GUI that exploits **motion parallax** to stimulate depth perception for users with congenital monocular vision (no stereopsis). The system tracks micro head movements and maps them to camera translation / view frustum shifts with **end-to-end latency under 20 ms** to avoid vestibular-visual mismatch.

## Architecture

```
Webcam (V4L2 max FPS)
    → MediaPipe Face Mesh (functional eye + nose bridge only)
    → One Euro / Kalman filter
    → Gain + deadzone calibration
    → Output backends:
        A) FreeTrack UDP → OpenTrack / games
        B) uinput virtual joystick → native simulators
        C) X11 homography warp PoC (per-window)
    ↔ Unix socket IPC ↔ PySide6 calibration GUI (OpenGL cube preview)
```

## System Dependencies (Debian/Ubuntu)

```bash
sudo apt update
sudo apt install -y \
    python3 python3-pip python3-venv \
    libv4l-dev v4l-utils \
    libgl1-mesa-dev libglib2.0-0 \
    libevdev-dev linux-headers-generic
```

For **uinput** output, add your user to the `input` group:

```bash
sudo usermod -aG input "$USER"
# log out and back in
```

## Quick Start

```bash
cd monocular-parallax
python3 -m venv .venv
source .venv/bin/activate
pip install -e ".[linux]"

# Edit config — set functional_eye: left | right
nano config/default.yaml

# Terminal 1 — tracking daemon
parallax-daemon -c config/default.yaml

# Terminal 2 — calibration GUI
parallax-calibrate -c config/default.yaml
```

The GUI connects to the daemon via `/tmp/parallax-tracker.sock`. If the daemon is offline, the GUI falls back to embedded camera tracking for setup.

## Configuration

| Section | Key | Description |
|---------|-----|-------------|
| `camera` | `device`, `fps` | V4L2 device; `fps: 0` auto-detects hardware maximum |
| `tracking` | `functional_eye` | `left` or `right` — the user's working eye |
| `filter` | `type`, `beta` | `one_euro` (default) or `kalman`; beta controls responsiveness |
| `calibration` | `gain`, `deadzone` | Per-axis sensitivity and micro-movement deadzone |
| `output` | `mode` | `freetrack`, `uinput`, or `both` |

## Output Backends

### A — FreeTrack / OpenTrack (recommended)

Set `output.mode: freetrack` and configure [OpenTrack](https://github.com/opentrack/opentrack):

1. Input: **UDP over network**
2. Port: `4242` (default)
3. Map axes to your game profile

### B — uinput Virtual Joystick

Set `output.mode: uinput`. A virtual joystick appears as `/dev/input/event*`. Map axes in your game's joystick settings or via `evtest`.

### C — X11 Window Warp (proof-of-concept)

For app-specific perspective shifting on X11 (not Wayland):

```bash
# Find window ID: xwininfo -name "Your Game"
parallax-x11-warp --window-id 0x3a00007 --socket /tmp/parallax-tracker.sock
```

Applies a real-time homography warp based on head yaw, pitch, and Z translation.

## Neuro-Calibration GUI

Sliders adjust parameters live over IPC:

- **Tracking Sensitivity (Gain)** — per-axis scaling for micro neck movements
- **Smoothing** — One Euro `beta` (responsiveness) and `min_cutoff` (jitter suppression)
- **Deadzone** — uniform radius to suppress camera noise at rest
- **3D Preview** — OpenGL wireframe cube with asymmetric frustum projection

Target: latency display in the status bar should stay **below 20 ms**. Increase `beta` for snappier response; increase `min_cutoff` for steadier image.

## systemd Service

```bash
sudo cp deploy/parallax-tracker.service /etc/systemd/system/
sudo cp config/default.yaml /etc/parallax/default.yaml
# edit /etc/parallax/default.yaml for your camera and eye
sudo systemctl enable --now parallax-tracker
```

## Performance Notes

- MediaPipe runs with `model_complexity: 0` and only 2 landmark regions (eye center + nose bridge).
- Camera buffer size is set to 1 frame to minimize capture latency.
- `v4l2-ctl --set-parm` forces hardware max FPS before OpenCV opens the device.
- The asyncio daemon offloads MediaPipe to a thread pool so the event loop stays responsive.

## Troubleshooting

| Issue | Fix |
|-------|-----|
| Camera not found | Check `ls /dev/video*`; set `camera.device` in config |
| Permission denied (uinput) | `sudo usermod -aG input $USER`, re-login |
| High latency (>20 ms) | Lower resolution, use USB 3 port, reduce `model_complexity` |
| No face detected | Improve lighting; center face in frame; click **Reset Neutral Pose** |
| Wayland session | Use FreeTrack/uinput (Approach A); X11 warp requires X11 |

## License

MIT
