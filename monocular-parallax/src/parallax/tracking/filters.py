"""Predictive smoothing filters for head pose — optimized for <20ms latency."""

from __future__ import annotations

import math
from abc import ABC, abstractmethod
from typing import Dict

from parallax.types import HeadPose


class PoseFilter(ABC):
    @abstractmethod
    def reset(self) -> None:
        ...

    @abstractmethod
    def update(self, pose: HeadPose, dt: float) -> HeadPose:
        ...


class OneEuroFilter:
    """1€ filter — adaptive low-pass with minimal lag on fast motion."""

    def __init__(self, min_cutoff: float = 1.5, beta: float = 0.007, d_cutoff: float = 1.0):
        self.min_cutoff = min_cutoff
        self.beta = beta
        self.d_cutoff = d_cutoff
        self._x_prev: float | None = None
        self._dx_prev: float = 0.0

    def reset(self) -> None:
        self._x_prev = None
        self._dx_prev = 0.0

    @staticmethod
    def _alpha(cutoff: float, dt: float) -> float:
        tau = 1.0 / (2.0 * math.pi * cutoff)
        return 1.0 / (1.0 + tau / max(dt, 1e-6))

    def update(self, x: float, dt: float) -> float:
        if self._x_prev is None:
            self._x_prev = x
            return x

        dx = (x - self._x_prev) / max(dt, 1e-6)
        a_d = self._alpha(self.d_cutoff, dt)
        dx_hat = a_d * dx + (1.0 - a_d) * self._dx_prev

        cutoff = self.min_cutoff + self.beta * abs(dx_hat)
        a = self._alpha(cutoff, dt)
        x_hat = a * x + (1.0 - a) * self._x_prev

        self._x_prev = x_hat
        self._dx_prev = dx_hat
        return x_hat


class OneEuroPoseFilter(PoseFilter):
    """Independent 1€ filters on each pose axis."""

    FIELDS = ("yaw", "pitch", "roll", "x", "y", "z")

    def __init__(self, min_cutoff: float = 1.5, beta: float = 0.007, d_cutoff: float = 1.0):
        self._filters: Dict[str, OneEuroFilter] = {
            f: OneEuroFilter(min_cutoff, beta, d_cutoff) for f in self.FIELDS
        }

    def set_params(self, min_cutoff: float, beta: float, d_cutoff: float) -> None:
        for filt in self._filters.values():
            filt.min_cutoff = min_cutoff
            filt.beta = beta
            filt.d_cutoff = d_cutoff

    def reset(self) -> None:
        for filt in self._filters.values():
            filt.reset()

    def update(self, pose: HeadPose, dt: float) -> HeadPose:
        if not pose.tracking_ok:
            return pose
        out = HeadPose(timestamp=pose.timestamp, tracking_ok=True)
        for field in self.FIELDS:
            raw = getattr(pose, field)
            setattr(out, field, self._filters[field].update(raw, dt))
        return out


class KalmanPoseFilter(PoseFilter):
    """Simple 1D Kalman per axis — constant-velocity model."""

    def __init__(self, process_noise: float = 0.01, measurement_noise: float = 0.1):
        self.q = process_noise
        self.r = measurement_noise
        self._state: Dict[str, tuple[float, float, float]] = {}

    def reset(self) -> None:
        self._state.clear()

    def _step(self, key: str, z: float, dt: float) -> float:
        if key not in self._state:
            self._state[key] = (z, 0.0, 1.0)
            return z

        x, v, p = self._state[key]
        # Predict
        x = x + v * dt
        p = p + self.q

        # Update
        k = p / (p + self.r)
        x = x + k * (z - x)
        v = v + k * (z - x) / max(dt, 1e-6)
        p = (1.0 - k) * p

        self._state[key] = (x, v, p)
        return x

    def update(self, pose: HeadPose, dt: float) -> HeadPose:
        if not pose.tracking_ok:
            return pose
        return HeadPose(
            yaw=self._step("yaw", pose.yaw, dt),
            pitch=self._step("pitch", pose.pitch, dt),
            roll=self._step("roll", pose.roll, dt),
            x=self._step("x", pose.x, dt),
            y=self._step("y", pose.y, dt),
            z=self._step("z", pose.z, dt),
            timestamp=pose.timestamp,
            tracking_ok=True,
        )


def create_filter(filter_type: str, **kwargs) -> PoseFilter:
    if filter_type == "kalman":
        return KalmanPoseFilter(
            process_noise=kwargs.get("process_noise", 0.01),
            measurement_noise=kwargs.get("measurement_noise", 0.1),
        )
    return OneEuroPoseFilter(
        min_cutoff=kwargs.get("min_cutoff", 1.5),
        beta=kwargs.get("beta", 0.007),
        d_cutoff=kwargs.get("d_cutoff", 1.0),
    )
