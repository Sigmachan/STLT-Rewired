"""Virtual uinput joystick for native game / simulator head tracking."""

from __future__ import annotations

import logging
import sys

from parallax.types import HeadPose

logger = logging.getLogger(__name__)

_AXIS_MAX = 32767


class UInputDevice:
    """Maps head pose to a virtual joystick via python-uinput."""

    def __init__(self, device_name: str = "Monocular Parallax Tracker"):
        if sys.platform != "linux":
            raise RuntimeError("uinput output requires Linux")

        try:
            import uinput
        except ImportError as exc:
            raise RuntimeError("Install python-uinput: pip install python-uinput") from exc

        self._uinput = uinput
        self._device = uinput.Device(
            [
                uinput.ABS_X + (0, _AXIS_MAX, 0, 0),
                uinput.ABS_Y + (0, _AXIS_MAX, 0, 0),
                uinput.ABS_Z + (0, _AXIS_MAX, 0, 0),
                uinput.ABS_RX + (0, _AXIS_MAX, 0, 0),
                uinput.ABS_RY + (0, _AXIS_MAX, 0, 0),
                uinput.ABS_RZ + (0, _AXIS_MAX, 0, 0),
            ],
            name=device_name,
        )
        self._center = _AXIS_MAX // 2
        logger.info("uinput device '%s' created", device_name)

    def close(self) -> None:
        del self._device

    def _axis(self, value: float) -> int:
        clamped = max(-1.0, min(1.0, value))
        return self._center + int(clamped * self._center)

    def send(self, pose: HeadPose) -> None:
        if not pose.tracking_ok:
            return

        self._device.emit(self._uinput.ABS_X, self._axis(pose.yaw), syn=False)
        self._device.emit(self._uinput.ABS_Y, self._axis(pose.pitch), syn=False)
        self._device.emit(self._uinput.ABS_Z, self._axis(pose.z), syn=False)
        self._device.emit(self._uinput.ABS_RX, self._axis(pose.roll), syn=False)
        self._device.emit(self._uinput.ABS_RY, self._axis(pose.x), syn=False)
        self._device.emit(self._uinput.ABS_RZ, self._axis(pose.y), syn=False)
        self._device.syn()
