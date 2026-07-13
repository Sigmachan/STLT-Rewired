"""Unix socket IPC for daemon ↔ GUI communication."""

from __future__ import annotations

import asyncio
import json
import logging
import os
from pathlib import Path
from typing import Callable, Optional

from parallax.types import CalibrationParams, HeadPose

logger = logging.getLogger(__name__)


class PoseBroadcaster:
    """Publishes pose JSON lines to connected GUI clients."""

    def __init__(self, socket_path: str):
        self.socket_path = socket_path
        self._clients: set[asyncio.StreamWriter] = set()
        self._server: Optional[asyncio.Server] = None

    async def start(self) -> None:
        path = Path(self.socket_path)
        if path.exists():
            path.unlink()
        self._server = await asyncio.start_unix_server(self._on_client, path=self.socket_path)
        os.chmod(self.socket_path, 0o666)
        logger.info("IPC listening on %s", self.socket_path)

    async def _on_client(
        self, reader: asyncio.StreamReader, writer: asyncio.StreamWriter
    ) -> None:
        self._clients.add(writer)
        try:
            while True:
                line = await reader.readline()
                if not line:
                    break
                # GUI may send calibration updates
                try:
                    msg = json.loads(line.decode())
                    if msg.get("type") == "calibration" and hasattr(self, "on_calibration"):
                        self.on_calibration(CalibrationParams(**msg["data"]))  # type: ignore
                    elif msg.get("type") == "reset_baseline" and hasattr(self, "on_reset_baseline"):
                        self.on_reset_baseline()  # type: ignore
                except (json.JSONDecodeError, KeyError, TypeError):
                    pass
        finally:
            self._clients.discard(writer)
            writer.close()
            await writer.wait_closed()

    def broadcast_pose(self, pose: HeadPose) -> None:
        payload = json.dumps({"type": "pose", "data": pose.as_dict()}) + "\n"
        data = payload.encode()
        dead: list[asyncio.StreamWriter] = []
        for w in self._clients:
            try:
                w.write(data)
                # Schedule drain without blocking the tracking loop.
                asyncio.get_running_loop().create_task(self._safe_drain(w))
            except Exception:
                dead.append(w)
        for w in dead:
            self._clients.discard(w)

    @staticmethod
    async def _safe_drain(writer: asyncio.StreamWriter) -> None:
        try:
            await writer.drain()
        except (ConnectionError, OSError):
            pass

    async def close(self) -> None:
        if self._server:
            self._server.close()
            await self._server.wait_closed()
        for w in list(self._clients):
            w.close()
        self._clients.clear()
        p = Path(self.socket_path)
        if p.exists():
            p.unlink()


class PoseSubscriber:
    """GUI client that receives poses and sends calibration updates."""

    def __init__(
        self,
        socket_path: str,
        on_pose: Callable[[HeadPose], None],
        on_connected: Optional[Callable[[], None]] = None,
    ):
        self.socket_path = socket_path
        self.on_pose = on_pose
        self.on_connected = on_connected
        self._writer: Optional[asyncio.StreamWriter] = None
        self._task: Optional[asyncio.Task] = None

    async def connect(self) -> None:
        while True:
            try:
                reader, writer = await asyncio.open_unix_connection(self.socket_path)
                self._writer = writer
                if self.on_connected:
                    self.on_connected()
                await self._read_loop(reader)
            except (ConnectionRefusedError, FileNotFoundError):
                await asyncio.sleep(0.5)

    async def _read_loop(self, reader: asyncio.StreamReader) -> None:
        while True:
            line = await reader.readline()
            if not line:
                break
            try:
                msg = json.loads(line.decode())
                if msg.get("type") == "pose":
                    self.on_pose(HeadPose.from_dict(msg["data"]))
            except (json.JSONDecodeError, KeyError):
                pass

    def send_calibration(self, params: CalibrationParams) -> None:
        if not self._writer:
            return
        payload = json.dumps({"type": "calibration", "data": params.to_dict()}) + "\n"
        try:
            self._writer.write(payload.encode())
            asyncio.get_running_loop().create_task(self._safe_drain(self._writer))
        except (ConnectionError, OSError):
            pass

    def send_reset_baseline(self) -> None:
        if not self._writer:
            return
        payload = json.dumps({"type": "reset_baseline"}) + "\n"
        try:
            self._writer.write(payload.encode())
            asyncio.get_running_loop().create_task(self._safe_drain(self._writer))
        except (ConnectionError, OSError):
            pass

    @staticmethod
    async def _safe_drain(writer: asyncio.StreamWriter) -> None:
        try:
            await writer.drain()
        except (ConnectionError, OSError):
            pass

    def start_background(self) -> asyncio.Task:
        self._task = asyncio.create_task(self.connect())
        return self._task
