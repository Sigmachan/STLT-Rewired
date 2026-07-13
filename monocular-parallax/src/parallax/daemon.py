"""Async head-tracking daemon — camera loop, filter, output."""

from __future__ import annotations

import asyncio
import logging
import signal
import time
from pathlib import Path
from typing import Any, Optional

import yaml

from parallax.ipc import PoseBroadcaster
from parallax.output import MultiOutput, create_outputs
from parallax.tracking import MinimalFaceTracker, V4L2Camera, create_filter
from parallax.tracking.filters import OneEuroPoseFilter
from parallax.types import CalibrationParams, HeadPose

logger = logging.getLogger(__name__)


def load_config(path: str | Path) -> dict:
    with open(path, encoding="utf-8") as f:
        return yaml.safe_load(f)


class TrackingDaemon:
    def __init__(self, config: dict):
        self.config = config
        cam = config.get("camera", {})
        track = config.get("tracking", {})
        filt = config.get("filter", {})
        out = config.get("output", {})
        daemon = config.get("daemon", {})

        self.calibration = CalibrationParams.from_config(config)
        self.camera = V4L2Camera(
            device=cam.get("device", "/dev/video0"),
            width=int(cam.get("width", 640)),
            height=int(cam.get("height", 480)),
            fps=float(cam.get("fps", 0)),
        )
        self.tracker = MinimalFaceTracker(
            functional_eye=track.get("functional_eye", "left"),
            model_complexity=int(track.get("model_complexity", 0)),
            refine_landmarks=bool(track.get("refine_landmarks", False)),
        )
        self.pose_filter = create_filter(
            filt.get("type", "one_euro"),
            min_cutoff=filt.get("min_cutoff", 1.5),
            beta=filt.get("beta", 0.007),
            d_cutoff=filt.get("d_cutoff", 1.0),
        )
        backends = create_outputs(
            out.get("mode", "freetrack"),
            out.get("freetrack", {}),
            out.get("uinput", {}),
        )
        self.output = MultiOutput(backends)
        self.ipc = PoseBroadcaster(daemon.get("ipc_socket", "/tmp/parallax-tracker.sock"))
        self.ipc.on_calibration = self._on_calibration  # type: ignore[attr-defined]
        self.ipc.on_reset_baseline = self._on_reset_baseline  # type: ignore[attr-defined]
        self.target_period_ms = float(daemon.get("target_period_ms", 0))
        self._last_ts: Optional[float] = None
        self._running = False
        self._latency_samples: list[float] = []

    def _on_calibration(self, params: CalibrationParams) -> None:
        self.calibration = params
        if isinstance(self.pose_filter, OneEuroPoseFilter):
            self.pose_filter.set_params(
                params.filter_min_cutoff,
                params.filter_beta,
                params.filter_d_cutoff,
            )

    def _on_reset_baseline(self) -> None:
        self.tracker.calibrate()
        self.pose_filter.reset()

    async def run(self) -> None:
        self._running = True
        await self.ipc.start()

        prev_ts = time.perf_counter()
        async for frame in self.camera.frames():
            if not self._running:
                break

            t_capture = time.perf_counter()
            loop = asyncio.get_running_loop()
            raw_pose = await loop.run_in_executor(None, self.tracker.process, frame)

            dt = max(t_capture - prev_ts, 1e-4)
            prev_ts = t_capture

            filtered = self.pose_filter.update(raw_pose, dt)
            calibrated = self.calibration.apply(filtered)

            t_out = time.perf_counter()
            self.output.send(calibrated)
            self.ipc.broadcast_pose(calibrated)

            latency_ms = (t_out - raw_pose.timestamp) * 1000.0
            self._latency_samples.append(latency_ms)
            if len(self._latency_samples) >= 120:
                avg = sum(self._latency_samples) / len(self._latency_samples)
                if avg > 20.0:
                    logger.warning("E2E latency avg %.1f ms exceeds 20 ms target", avg)
                else:
                    logger.debug("E2E latency avg %.1f ms", avg)
                self._latency_samples.clear()

    async def stop(self) -> None:
        self._running = False
        self.camera.close()
        self.tracker.close()
        self.output.close()
        await self.ipc.close()


async def main_async(config_path: str) -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s [%(levelname)s] %(name)s: %(message)s",
    )
    config = load_config(config_path)
    daemon = TrackingDaemon(config)

    loop = asyncio.get_running_loop()
    stop_event = asyncio.Event()

    def _signal_handler() -> None:
        stop_event.set()

    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, _signal_handler)

    run_task = asyncio.create_task(daemon.run())
    await stop_event.wait()
    await daemon.stop()
    run_task.cancel()
    try:
        await run_task
    except asyncio.CancelledError:
        pass


def main() -> None:
    import argparse

    parser = argparse.ArgumentParser(description="Monocular Parallax tracking daemon")
    parser.add_argument(
        "-c",
        "--config",
        default=str(Path(__file__).resolve().parents[2] / "config" / "default.yaml"),
    )
    args = parser.parse_args()
    asyncio.run(main_async(args.config))


if __name__ == "__main__":
    main()
