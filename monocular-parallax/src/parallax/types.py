"""Shared data types for the tracking pipeline."""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Dict


@dataclass
class HeadPose:
    """Head pose in normalized coordinates and radians."""

    yaw: float = 0.0
    pitch: float = 0.0
    roll: float = 0.0
    x: float = 0.0
    y: float = 0.0
    z: float = 0.0
    timestamp: float = 0.0
    tracking_ok: bool = False

    def as_dict(self) -> Dict[str, float]:
        return {
            "yaw": self.yaw,
            "pitch": self.pitch,
            "roll": self.roll,
            "x": self.x,
            "y": self.y,
            "z": self.z,
            "timestamp": self.timestamp,
            "tracking_ok": float(self.tracking_ok),
        }

    @classmethod
    def from_dict(cls, data: Dict[str, float]) -> HeadPose:
        return cls(
            yaw=float(data.get("yaw", 0.0)),
            pitch=float(data.get("pitch", 0.0)),
            roll=float(data.get("roll", 0.0)),
            x=float(data.get("x", 0.0)),
            y=float(data.get("y", 0.0)),
            z=float(data.get("z", 0.0)),
            timestamp=float(data.get("timestamp", 0.0)),
            tracking_ok=bool(data.get("tracking_ok", 0.0)),
        )


@dataclass
class CalibrationParams:
    """Runtime-adjustable calibration from the GUI."""

    gain_yaw: float = 1.0
    gain_pitch: float = 1.0
    gain_roll: float = 0.5
    gain_x: float = 1.0
    gain_y: float = 1.0
    gain_z: float = 1.0
    deadzone_yaw: float = 0.02
    deadzone_pitch: float = 0.02
    deadzone_roll: float = 0.02
    deadzone_x: float = 0.005
    deadzone_y: float = 0.005
    deadzone_z: float = 0.005
    filter_min_cutoff: float = 1.5
    filter_beta: float = 0.007
    filter_d_cutoff: float = 1.0

    def apply(self, pose: HeadPose) -> HeadPose:
        """Apply gain scaling and deadzone to a pose."""

        def dz(value: float, radius: float) -> float:
            if abs(value) < radius:
                return 0.0
            sign = 1.0 if value >= 0 else -1.0
            return sign * (abs(value) - radius)

        return HeadPose(
            yaw=dz(pose.yaw, self.deadzone_yaw) * self.gain_yaw,
            pitch=dz(pose.pitch, self.deadzone_pitch) * self.gain_pitch,
            roll=dz(pose.roll, self.deadzone_roll) * self.gain_roll,
            x=dz(pose.x, self.deadzone_x) * self.gain_x,
            y=dz(pose.y, self.deadzone_y) * self.gain_y,
            z=dz(pose.z, self.deadzone_z) * self.gain_z,
            timestamp=pose.timestamp,
            tracking_ok=pose.tracking_ok,
        )

    def to_dict(self) -> Dict[str, float]:
        return {k: getattr(self, k) for k in self.__dataclass_fields__}

    @classmethod
    def from_config(cls, cfg: dict) -> CalibrationParams:
        cal = cfg.get("calibration", cfg)
        gain = cal.get("gain", {})
        dead = cal.get("deadzone", {})
        filt = cfg.get("filter", {})
        return cls(
            gain_yaw=float(gain.get("yaw", 1.0)),
            gain_pitch=float(gain.get("pitch", 1.0)),
            gain_roll=float(gain.get("roll", 0.5)),
            gain_x=float(gain.get("x", 1.0)),
            gain_y=float(gain.get("y", 1.0)),
            gain_z=float(gain.get("z", 1.0)),
            deadzone_yaw=float(dead.get("yaw", 0.02)),
            deadzone_pitch=float(dead.get("pitch", 0.02)),
            deadzone_roll=float(dead.get("roll", 0.02)),
            deadzone_x=float(dead.get("x", 0.005)),
            deadzone_y=float(dead.get("y", 0.005)),
            deadzone_z=float(dead.get("z", 0.005)),
            filter_min_cutoff=float(filt.get("min_cutoff", 1.5)),
            filter_beta=float(filt.get("beta", 0.007)),
            filter_d_cutoff=float(filt.get("d_cutoff", 1.0)),
        )
