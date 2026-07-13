"""
Neuro-calibration GUI — gain, smoothing, deadzone sliders and 3D parallax preview.

Connects to the tracking daemon via Unix socket; falls back to embedded
camera tracking when the daemon is offline (useful for first-time setup).
"""

from __future__ import annotations

import asyncio
import logging
import sys
import threading
import time
from pathlib import Path
from typing import Optional

import yaml
from PySide6.QtCore import Qt, QThread, QTimer, Signal
from PySide6.QtGui import QImage, QPixmap
from PySide6.QtWidgets import (
    QApplication,
    QComboBox,
    QFormLayout,
    QGroupBox,
    QHBoxLayout,
    QLabel,
    QMainWindow,
    QPushButton,
    QSlider,
    QSplitter,
    QStatusBar,
    QVBoxLayout,
    QWidget,
)

from parallax.gui.preview_gl import ParallaxCubeWidget
from parallax.ipc import PoseSubscriber
from parallax.tracking import MinimalFaceTracker, V4L2Camera, create_filter
from parallax.types import CalibrationParams, HeadPose

logger = logging.getLogger(__name__)

DEFAULT_CONFIG = Path(__file__).resolve().parents[3] / "config" / "default.yaml"


def _load_config(path: Path) -> dict:
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


def _slider_row(
    label: str,
    minimum: int,
    maximum: int,
    default: int,
    scale: float,
    on_change,
) -> QWidget:
    """Build a labeled horizontal slider; `scale` maps int → float value."""
    container = QWidget()
    row = QHBoxLayout(container)
    row.setContentsMargins(0, 0, 0, 0)
    name = QLabel(label)
    name.setMinimumWidth(140)
    value_lbl = QLabel(f"{default / scale:.3f}")
    value_lbl.setMinimumWidth(56)
    value_lbl.setAlignment(Qt.AlignmentFlag.AlignRight)

    slider = QSlider(Qt.Orientation.Horizontal)
    slider.setRange(minimum, maximum)
    slider.setValue(default)

    def _changed(v: int) -> None:
        fv = v / scale
        value_lbl.setText(f"{fv:.3f}")
        on_change(fv)

    slider.valueChanged.connect(_changed)
    row.addWidget(name)
    row.addWidget(slider, stretch=1)
    row.addWidget(value_lbl)
    return container


class EmbeddedTrackerThread(QThread):
    """Fallback local tracking when daemon IPC is unavailable."""

    pose_ready = Signal(object)
    frame_ready = Signal(object)
    status = Signal(str)

    def __init__(self, config: dict, parent=None):
        super().__init__(parent)
        self._config = config
        self._running = False
        self._calibration = CalibrationParams.from_config(config)
        self._lock = threading.Lock()
        self._reset_requested = False

    def set_calibration(self, params: CalibrationParams) -> None:
        with self._lock:
            self._calibration = params

    def reset_baseline(self) -> None:
        with self._lock:
            self._reset_requested = True

    def run(self) -> None:
        cam_cfg = self._config.get("camera", {})
        track_cfg = self._config.get("tracking", {})
        filt_cfg = self._config.get("filter", {})

        camera = V4L2Camera(
            device=cam_cfg.get("device", "/dev/video0"),
            width=int(cam_cfg.get("width", 640)),
            height=int(cam_cfg.get("height", 480)),
            fps=float(cam_cfg.get("fps", 0)),
        )
        tracker = MinimalFaceTracker(
            functional_eye=track_cfg.get("functional_eye", "left"),
            model_complexity=int(track_cfg.get("model_complexity", 0)),
            refine_landmarks=bool(track_cfg.get("refine_landmarks", False)),
        )
        pose_filter = create_filter(
            filt_cfg.get("type", "one_euro"),
            min_cutoff=filt_cfg.get("min_cutoff", 1.5),
            beta=filt_cfg.get("beta", 0.007),
            d_cutoff=filt_cfg.get("d_cutoff", 1.0),
        )

        self._running = True
        self.status.emit("Embedded camera tracking active")

        async def _loop() -> None:
            prev_ts = time.perf_counter()
            async for frame in camera.frames():
                if not self._running:
                    break
                t0 = time.perf_counter()
                raw = tracker.process(frame)
                dt = max(t0 - prev_ts, 1e-4)
                prev_ts = t0

                with self._lock:
                    cal = self._calibration
                    filt = pose_filter
                    if self._reset_requested:
                        tracker.calibrate()
                        filt.reset()
                        self._reset_requested = False

                filtered = filt.update(raw, dt)
                pose = cal.apply(filtered)
                self.pose_ready.emit(pose)

                debug = tracker.draw_debug(frame)
                self.frame_ready.emit(debug)

        try:
            asyncio.run(_loop())
        finally:
            camera.close()
            tracker.close()

    def stop(self) -> None:
        self._running = False


class IpcBridgeThread(QThread):
    """Runs asyncio PoseSubscriber in a background thread."""

    pose_ready = Signal(object)
    connected = Signal()
    disconnected = Signal()

    def __init__(self, socket_path: str, parent=None):
        super().__init__(parent)
        self._socket_path = socket_path
        self._subscriber: Optional[PoseSubscriber] = None
        self._loop: Optional[asyncio.AbstractEventLoop] = None
        self._calibration_queue: list[CalibrationParams] = []

    def send_calibration(self, params: CalibrationParams) -> None:
        self._calibration_queue.append(params)
        if self._loop and self._subscriber:
            self._loop.call_soon_threadsafe(self._flush_calibration)

    def send_reset_baseline(self) -> None:
        if self._loop and self._subscriber:
            self._loop.call_soon_threadsafe(self._subscriber.send_reset_baseline)

    def _flush_calibration(self) -> None:
        if not self._subscriber:
            return
        while self._calibration_queue:
            params = self._calibration_queue.pop(0)
            self._subscriber.send_calibration(params)

    def run(self) -> None:
        self._loop = asyncio.new_event_loop()
        asyncio.set_event_loop(self._loop)

        def on_pose(pose: HeadPose) -> None:
            self.pose_ready.emit(pose)

        def on_connected() -> None:
            self.connected.emit()

        self._subscriber = PoseSubscriber(
            self._socket_path,
            on_pose=on_pose,
            on_connected=on_connected,
        )

        try:
            self._loop.run_until_complete(self._subscriber.connect())
        except Exception as exc:
            logger.debug("IPC thread ended: %s", exc)
        finally:
            self.disconnected.emit()
            self._loop.close()


class CalibrationWindow(QMainWindow):
    def __init__(self, config_path: Path):
        super().__init__()
        self.setWindowTitle("Monocular Parallax — Neuro-Calibration")
        self.resize(1100, 720)

        self._config = _load_config(config_path)
        self._params = CalibrationParams.from_config(self._config)
        daemon_cfg = self._config.get("daemon", {})
        self._socket_path = daemon_cfg.get("ipc_socket", "/tmp/parallax-tracker.sock")

        self._latest_pose = HeadPose()
        self._ipc_thread: Optional[IpcBridgeThread] = None
        self._embedded_thread: Optional[EmbeddedTrackerThread] = None
        self._using_embedded = False
        self._ipc_connected = False

        self._build_ui()
        self._start_ipc()

        self._refresh_timer = QTimer(self)
        self._refresh_timer.timeout.connect(self._update_status)
        self._refresh_timer.start(100)

    def _build_ui(self) -> None:
        central = QWidget()
        self.setCentralWidget(central)
        root = QHBoxLayout(central)

        splitter = QSplitter(Qt.Orientation.Horizontal)
        root.addWidget(splitter)

        # --- Controls panel ---
        controls = QWidget()
        controls_layout = QVBoxLayout(controls)
        controls.setMaximumWidth(360)

        gain_box = QGroupBox("Tracking Sensitivity (Gain)")
        gain_form = QFormLayout(gain_box)
        for axis, default in (
            ("yaw", self._params.gain_yaw),
            ("pitch", self._params.gain_pitch),
            ("roll", self._params.gain_roll),
            ("x", self._params.gain_x),
            ("y", self._params.gain_y),
            ("z", self._params.gain_z),
        ):
            row = _slider_row(
                axis.upper(),
                10,
                500,
                int(default * 100),
                100.0,
                lambda v, a=axis: self._on_gain(a, v),
            )
            gain_form.addRow(row)
        controls_layout.addWidget(gain_box)

        filter_box = QGroupBox("Smoothing (One Euro Filter)")
        filter_layout = QVBoxLayout(filter_box)
        filter_layout.addWidget(
            _slider_row(
                "Beta (responsiveness)",
                1,
                100,
                int(self._params.filter_beta * 1000),
                1000.0,
                self._on_beta,
            )
        )
        filter_layout.addWidget(
            _slider_row(
                "Min cutoff (jitter)",
                5,
                500,
                int(self._params.filter_min_cutoff * 100),
                100.0,
                self._on_cutoff,
            )
        )
        controls_layout.addWidget(filter_box)

        dead_box = QGroupBox("Deadzone Radius")
        dead_layout = QVBoxLayout(dead_box)
        dead_layout.addWidget(
            _slider_row(
                "Uniform deadzone",
                0,
                100,
                int(self._params.deadzone_yaw * 1000),
                1000.0,
                self._on_deadzone,
            )
        )
        controls_layout.addWidget(dead_box)

        eye_box = QGroupBox("Functional Eye")
        eye_layout = QVBoxLayout(eye_box)
        self._eye_combo = QComboBox()
        self._eye_combo.addItems(["left", "right"])
        track_cfg = self._config.get("tracking", {})
        eye = track_cfg.get("functional_eye", "left")
        self._eye_combo.setCurrentText(eye)
        self._eye_combo.setEnabled(False)  # requires daemon restart
        eye_layout.addWidget(QLabel("Set in config / restart daemon"))
        eye_layout.addWidget(self._eye_combo)
        controls_layout.addWidget(eye_box)

        btn_row = QHBoxLayout()
        self._reset_btn = QPushButton("Reset Neutral Pose")
        self._reset_btn.clicked.connect(self._reset_neutral)
        btn_row.addWidget(self._reset_btn)
        controls_layout.addLayout(btn_row)
        controls_layout.addStretch()

        splitter.addWidget(controls)

        # --- Preview panel ---
        preview = QWidget()
        preview_layout = QVBoxLayout(preview)

        self._gl = ParallaxCubeWidget()
        preview_layout.addWidget(self._gl, stretch=3)

        self._cam_label = QLabel("Camera preview (embedded mode)")
        self._cam_label.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self._cam_label.setMinimumHeight(180)
        self._cam_label.setStyleSheet("background: #12141a; color: #888;")
        preview_layout.addWidget(self._cam_label, stretch=1)

        splitter.addWidget(preview)
        splitter.setStretchFactor(1, 1)

        self._status = QStatusBar()
        self.setStatusBar(self._status)

    def _start_ipc(self) -> None:
        self._ipc_thread = IpcBridgeThread(self._socket_path)
        self._ipc_thread.pose_ready.connect(self._on_pose)
        self._ipc_thread.connected.connect(self._on_ipc_connected)
        self._ipc_thread.disconnected.connect(self._on_ipc_disconnected)
        self._ipc_thread.start()
        self._status.showMessage(f"Connecting to daemon at {self._socket_path}…")
        QTimer.singleShot(3000, self._ipc_connect_timeout)

    def _ipc_connect_timeout(self) -> None:
        if self._ipc_connected or self._using_embedded:
            return
        self._status.showMessage("Daemon not found — starting embedded camera…")
        self._start_embedded()

    def _on_ipc_connected(self) -> None:
        self._ipc_connected = True
        self._using_embedded = False
        self._stop_embedded()
        self._status.showMessage("Connected to tracking daemon")
        self._push_calibration()

    def _on_ipc_disconnected(self) -> None:
        if not self._using_embedded:
            self._status.showMessage("Daemon offline — starting embedded camera…")
            self._start_embedded()

    def _start_embedded(self) -> None:
        if self._embedded_thread and self._embedded_thread.isRunning():
            return
        self._using_embedded = True
        self._embedded_thread = EmbeddedTrackerThread(self._config)
        self._embedded_thread.pose_ready.connect(self._on_pose)
        self._embedded_thread.frame_ready.connect(self._on_frame)
        self._embedded_thread.status.connect(self._status.showMessage)
        self._embedded_thread.start()

    def _stop_embedded(self) -> None:
        if self._embedded_thread:
            self._embedded_thread.stop()
            self._embedded_thread.wait(2000)
            self._embedded_thread = None

    def _on_pose(self, pose: HeadPose) -> None:
        self._latest_pose = pose
        self._gl.set_pose(pose)

    def _on_frame(self, frame_bgr) -> None:
        import cv2

        rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        h, w, ch = rgb.shape
        img = QImage(rgb.data, w, h, ch * w, QImage.Format.Format_RGB888)
        self._cam_label.setPixmap(
            QPixmap.fromImage(img).scaled(
                self._cam_label.width(),
                self._cam_label.height(),
                Qt.AspectRatioMode.KeepAspectRatio,
                Qt.TransformationMode.SmoothTransformation,
            )
        )

    def _push_calibration(self) -> None:
        if self._ipc_thread and not self._using_embedded:
            self._ipc_thread.send_calibration(self._params)
        if self._embedded_thread:
            self._embedded_thread.set_calibration(self._params)

    def _on_gain(self, axis: str, value: float) -> None:
        setattr(self._params, f"gain_{axis}", value)
        self._push_calibration()

    def _on_beta(self, value: float) -> None:
        self._params.filter_beta = value
        self._push_calibration()

    def _on_cutoff(self, value: float) -> None:
        self._params.filter_min_cutoff = value
        self._push_calibration()

    def _on_deadzone(self, value: float) -> None:
        self._params.deadzone_yaw = value
        self._params.deadzone_pitch = value
        self._params.deadzone_roll = value
        self._params.deadzone_x = value * 0.25
        self._params.deadzone_y = value * 0.25
        self._params.deadzone_z = value * 0.25
        self._push_calibration()

    def _reset_neutral(self) -> None:
        self._status.showMessage("Neutral pose reset — hold still for 1 second")
        if self._ipc_thread and not self._using_embedded:
            self._ipc_thread.send_reset_baseline()
        elif self._embedded_thread:
            self._embedded_thread.reset_baseline()

    def _update_status(self) -> None:
        pose = self._latest_pose
        if pose.tracking_ok and pose.timestamp > 0:
            latency_ms = (time.perf_counter() - pose.timestamp) * 1000.0
            mode = "embedded" if self._using_embedded else "daemon"
            extra = f" | latency ~{latency_ms:.0f} ms"
            if latency_ms > 20:
                extra += " ⚠"
            self._status.showMessage(
                f"Mode: {mode} | yaw={pose.yaw:.3f} pitch={pose.pitch:.3f} z={pose.z:.3f}{extra}"
            )

    def closeEvent(self, event) -> None:
        self._stop_embedded()
        if self._ipc_thread:
            self._ipc_thread.terminate()
            self._ipc_thread.wait(1000)
        super().closeEvent(event)


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Monocular Parallax calibration GUI")
    parser.add_argument("-c", "--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("-v", "--verbose", action="store_true")
    args = parser.parse_args()

    logging.basicConfig(
        level=logging.DEBUG if args.verbose else logging.WARNING,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )

    app = QApplication(sys.argv)
    app.setStyle("Fusion")
    win = CalibrationWindow(args.config)
    win.show()
    sys.exit(app.exec())


if __name__ == "__main__":
    main()
