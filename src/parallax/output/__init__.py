"""Output backends for head tracking data."""

from __future__ import annotations

import logging
from typing import List, Protocol

from parallax.types import HeadPose

logger = logging.getLogger(__name__)


class OutputBackend(Protocol):
    def send(self, pose: HeadPose) -> None: ...
    def close(self) -> None: ...


def create_outputs(mode: str, freetrack_cfg: dict, uinput_cfg: dict) -> List[OutputBackend]:
    backends: List[OutputBackend] = []

    if mode in ("freetrack", "both"):
        from parallax.output.freetrack import FreeTrackServer

        backends.append(
            FreeTrackServer(
                host=freetrack_cfg.get("host", "127.0.0.1"),
                port=int(freetrack_cfg.get("port", 4242)),
            )
        )

    if mode in ("uinput", "both"):
        try:
            from parallax.output.uinput_device import UInputDevice

            backends.append(
                UInputDevice(device_name=uinput_cfg.get("device_name", "Monocular Parallax Tracker"))
            )
        except RuntimeError as exc:
            logger.error("uinput unavailable: %s", exc)

    return backends


class MultiOutput:
    def __init__(self, backends: List[OutputBackend]):
        self._backends = backends

    def send(self, pose: HeadPose) -> None:
        for b in self._backends:
            b.send(pose)

    def close(self) -> None:
        for b in self._backends:
            b.close()
