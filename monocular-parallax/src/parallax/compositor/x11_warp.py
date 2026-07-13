"""
X11 proof-of-concept: capture a window and apply homography warp
based on head Z-distance and X/Y angles.

Requires: python-xlib, opencv, an X11 session (not Wayland).

Usage:
    python -m parallax.compositor.x11_warp --window-id 0x3a00007 --socket /tmp/parallax-tracker.sock
"""

from __future__ import annotations

import argparse
import asyncio
import json
import logging
import sys
from typing import Optional

import cv2
import numpy as np

from parallax.types import HeadPose

logger = logging.getLogger(__name__)


def _off_axis_projection(
    yaw: float, pitch: float, z: float, width: int, height: int
) -> np.ndarray:
    """
    Build a 3x3 homography approximating asymmetric frustum shift.
    Stronger Z translation amplifies parallax (motion parallax cue).
    """
    fx = width * (1.0 + z * 0.5)
    fy = height * (1.0 + z * 0.5)
    cx = width / 2.0 + yaw * width * 0.4
    cy = height / 2.0 + pitch * height * 0.4

    # Homography from off-center projection (simplified pinhole model)
    H = np.array(
        [
            [fx, 0.0, cx - width / 2.0],
            [0.0, fy, cy - height / 2.0],
            [0.0, 0.0, 1.0],
        ],
        dtype=np.float64,
    )
    # Normalize to keep image in frame
    H[0, 2] /= width
    H[1, 2] /= height
    return H


class X11WindowWarper:
    """Captures an X11 window via XGetImage and warps with head pose."""

    def __init__(self, window_id: int):
        if sys.platform != "linux":
            raise RuntimeError("X11 warp requires Linux")

        from Xlib import X, display

        self._display = display.Display()
        self._window = self._display.create_resource_object("window", window_id)
        self._geo = self._window.get_geometry()
        self._width = self._geo.width
        self._height = self._geo.height

    def capture_and_warp(self, pose: HeadPose) -> Optional[np.ndarray]:
        from Xlib import X

        try:
            raw = self._window.get_image(
                0, 0, self._width, self._height, X.ZPixmap, 0xFFFFFFFF
            )
        except Exception as exc:
            logger.error("XGetImage failed: %s", exc)
            return None

        frame = np.frombuffer(raw.data, dtype=np.uint8).reshape(
            self._height, self._width, 4
        )
        bgr = cv2.cvtColor(frame, cv2.COLOR_BGRA2BGR)

        if not pose.tracking_ok:
            return bgr

        H = _off_axis_projection(pose.yaw, pose.pitch, pose.z, self._width, self._height)
        warped = cv2.warpPerspective(
            bgr, H, (self._width, self._height), flags=cv2.INTER_LINEAR
        )
        return warped


async def _pose_listener(socket_path: str, on_pose) -> None:
    while True:
        try:
            reader, writer = await asyncio.open_unix_connection(socket_path)
            while True:
                line = await reader.readline()
                if not line:
                    break
                msg = json.loads(line.decode())
                if msg.get("type") == "pose":
                    on_pose(HeadPose.from_dict(msg["data"]))
        except (ConnectionRefusedError, FileNotFoundError):
            await asyncio.sleep(0.5)


async def main_async(window_id: int, socket_path: str, show_preview: bool) -> None:
    warper = X11WindowWarper(window_id)
    latest_pose = HeadPose()

    def on_pose(p: HeadPose) -> None:
        nonlocal latest_pose
        latest_pose = p

    listener = asyncio.create_task(_pose_listener(socket_path, on_pose))

    while True:
        loop = asyncio.get_running_loop()
        frame = await loop.run_in_executor(
            None, warper.capture_and_warp, latest_pose
        )
        if frame is not None and show_preview:
            cv2.imshow("Parallax Warp PoC", frame)
            if cv2.waitKey(1) & 0xFF == ord("q"):
                break
        await asyncio.sleep(1.0 / 60.0)

    listener.cancel()
    cv2.destroyAllWindows()


def main() -> None:
    logging.basicConfig(level=logging.INFO)
    parser = argparse.ArgumentParser(description="X11 window homography warp PoC")
    parser.add_argument("--window-id", type=lambda x: int(x, 0), required=True)
    parser.add_argument("--socket", default="/tmp/parallax-tracker.sock")
    parser.add_argument("--preview", action="store_true", default=True)
    args = parser.parse_args()
    asyncio.run(main_async(args.window_id, args.socket, args.preview))


if __name__ == "__main__":
    main()
