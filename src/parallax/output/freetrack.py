"""FreeTrack / OpenTrack UDP protocol output (port 4242)."""

from __future__ import annotations

import logging
import socket
import struct
from typing import Optional

from parallax.types import HeadPose

logger = logging.getLogger(__name__)

# FreeTrack wire format (compatible with opentrack UDP receiver)
_DATA_ID = 0x1234
PACKET_FMT = "<HHffffffI"
PACKET_SIZE = struct.calcsize(PACKET_FMT)


def _checksum(data: bytes) -> int:
    return sum(data) & 0xFFFF


class FreeTrackServer:
    """Sends head pose packets to opentrack or any FreeTrack-compatible client."""

    def __init__(self, host: str = "127.0.0.1", port: int = 4242):
        self.host = host
        self.port = port
        self._sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._addr = (host, port)
        logger.info("FreeTrack UDP target %s:%d", host, port)

    def close(self) -> None:
        self._sock.close()

    def send(self, pose: HeadPose) -> None:
        if not pose.tracking_ok:
            return

        # Convert radians to degrees for FreeTrack convention
        roll_deg = pose.roll * 57.2957795
        pitch_deg = pose.pitch * 57.2957795
        yaw_deg = pose.yaw * 57.2957795

        # Translation in arbitrary units (scaled for opentrack)
        tx = pose.x * 100.0
        ty = pose.y * 100.0
        tz = pose.z * 100.0

        body = struct.pack(
            "<HHffffff",
            _DATA_ID,
            0,  # placeholder checksum
            roll_deg,
            pitch_deg,
            yaw_deg,
            tx,
            ty,
            tz,
        )
        cksum = _checksum(body)
        packet = struct.pack(
            PACKET_FMT,
            _DATA_ID,
            cksum,
            roll_deg,
            pitch_deg,
            yaw_deg,
            tx,
            ty,
            tz,
            0,
        )
        self._sock.sendto(packet, self._addr)
