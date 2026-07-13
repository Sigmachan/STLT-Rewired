"""V4L2 camera capture with hardware max FPS and reconnect handling."""

from __future__ import annotations

import asyncio
import logging
import re
import subprocess
import sys
import time
from pathlib import Path
from typing import AsyncIterator, Optional, Tuple

import cv2
import numpy as np

logger = logging.getLogger(__name__)


def _parse_v4l2_fps(device: str) -> Optional[float]:
    """Query maximum frame interval via v4l2-ctl."""
    try:
        result = subprocess.run(
            ["v4l2-ctl", "-d", device, "--list-formats-ext"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        if result.returncode != 0:
            return None
        intervals = re.findall(r"Interval:\s+Discrete\s+([\d.]+)s", result.stdout)
        if not intervals:
            return None
        min_interval = min(float(i) for i in intervals)
        return 1.0 / min_interval if min_interval > 0 else None
    except (FileNotFoundError, subprocess.TimeoutExpired, ValueError):
        return None


def _set_v4l2_fps_ioctl(device: str, fps: float) -> bool:
    """Fallback: set frame rate via V4L2 ioctl when v4l2-ctl is unavailable."""
    if sys.platform != "linux":
        return False
    try:
        import fcntl
        import struct

        VIDIOC_S_PARM = 0xC0CC5605
        V4L2_BUF_TYPE_VIDEO_CAPTURE = 1

        # struct v4l2_streamparm { enum type; union { struct capture { ... timeperframe } } }
        # timeperframe: numerator (uint32), denominator (uint32) at offset 20
        with open(device, "rb") as fd:
            denom = max(int(fps), 1)
            buf = bytearray(204)
            struct.pack_into("I", buf, 0, V4L2_BUF_TYPE_VIDEO_CAPTURE)
            struct.pack_into("I", buf, 20, 1)       # numerator
            struct.pack_into("I", buf, 24, denom)   # denominator
            fcntl.ioctl(fd, VIDIOC_S_PARM, buf)
            return True
    except (OSError, ImportError, struct.error):
        return False


def _set_v4l2_fps(device: str, fps: float) -> bool:
    """Force frame rate via v4l2-ctl before opening with OpenCV."""
    if _set_v4l2_fps_v4l2ctl(device, fps):
        return True
    return _set_v4l2_fps_ioctl(device, fps)


def _set_v4l2_fps_v4l2ctl(device: str, fps: float) -> bool:
    try:
        result = subprocess.run(
            ["v4l2-ctl", "-d", device, f"--set-parm={int(fps)}"],
            capture_output=True,
            text=True,
            timeout=5,
            check=False,
        )
        return result.returncode == 0
    except (FileNotFoundError, subprocess.TimeoutExpired):
        return False


class V4L2Camera:
    """Async-friendly camera wrapper with disconnect recovery."""

    def __init__(
        self,
        device: str = "/dev/video0",
        width: int = 640,
        height: int = 480,
        fps: float = 0,
        reconnect_delay: float = 1.0,
    ):
        self.device = device
        self.width = width
        self.height = height
        self.requested_fps = fps
        self.reconnect_delay = reconnect_delay
        self._cap: Optional[cv2.VideoCapture] = None
        self._actual_fps: float = 30.0
        self._running = False

    @property
    def actual_fps(self) -> float:
        return self._actual_fps

    def _resolve_fps(self) -> float:
        if self.requested_fps > 0:
            return self.requested_fps
        hw_max = _parse_v4l2_fps(self.device)
        if hw_max:
            logger.info("Detected hardware max FPS %.1f on %s", hw_max, self.device)
            return hw_max
        return 60.0

    def _open(self) -> bool:
        if self._cap is not None:
            self._cap.release()
            self._cap = None

        if not Path(self.device).exists():
            logger.warning("Camera device %s not found", self.device)
            return False

        target_fps = self._resolve_fps()
        _set_v4l2_fps(self.device, target_fps)

        cap = cv2.VideoCapture(self.device, cv2.CAP_V4L2)
        if not cap.isOpened():
            logger.warning("Failed to open %s", self.device)
            return False

        cap.set(cv2.CAP_PROP_FRAME_WIDTH, self.width)
        cap.set(cv2.CAP_PROP_FRAME_HEIGHT, self.height)
        cap.set(cv2.CAP_PROP_FPS, target_fps)
        cap.set(cv2.CAP_PROP_BUFFERSIZE, 1)

        reported = cap.get(cv2.CAP_PROP_FPS)
        self._actual_fps = reported if reported > 0 else target_fps
        self._cap = cap
        logger.info(
            "Camera open: %s %dx%d @ %.1f fps",
            self.device,
            int(cap.get(cv2.CAP_PROP_FRAME_WIDTH)),
            int(cap.get(cv2.CAP_PROP_FRAME_HEIGHT)),
            self._actual_fps,
        )
        return True

    def close(self) -> None:
        self._running = False
        if self._cap is not None:
            self._cap.release()
            self._cap = None

    def read_frame(self) -> Tuple[bool, Optional[np.ndarray]]:
        if self._cap is None or not self._cap.isOpened():
            return False, None
        ok, frame = self._cap.read()
        if not ok or frame is None:
            return False, None
        return True, frame

    async def frames(self) -> AsyncIterator[np.ndarray]:
        """Yield BGR frames; reconnect on device loss."""
        self._running = True
        frame_period = 1.0 / max(self._actual_fps, 1.0)

        while self._running:
            if self._cap is None or not self._cap.isOpened():
                if not self._open():
                    await asyncio.sleep(self.reconnect_delay)
                    continue
                frame_period = 1.0 / max(self._actual_fps, 1.0)

            loop = asyncio.get_running_loop()
            t0 = time.perf_counter()
            ok, frame = await loop.run_in_executor(None, self.read_frame)

            if not ok or frame is None:
                logger.warning("Frame read failed — reconnecting")
                self.close()
                self._cap = None
                await asyncio.sleep(self.reconnect_delay)
                continue

            yield frame

            elapsed = time.perf_counter() - t0
            sleep_time = frame_period - elapsed
            if sleep_time > 0:
                await asyncio.sleep(sleep_time)
