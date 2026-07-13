"""Minimal MediaPipe face mesh tracker — functional eye + nose bridge only."""

from __future__ import annotations

import logging
import math
import time
from typing import Literal, Optional, Tuple

import cv2
import mediapipe as mp
import numpy as np

from parallax.types import HeadPose

logger = logging.getLogger(__name__)

# MediaPipe Face Mesh landmark indices
LEFT_EYE_INDICES = (33, 133, 160, 159, 158, 157, 173, 155, 154, 153, 145, 144, 163, 7)
RIGHT_EYE_INDICES = (362, 263, 387, 386, 385, 384, 398, 382, 381, 380, 374, 373, 390, 249)
NOSE_BRIDGE = 6
NOSE_TIP = 1


def _landmark_xy(landmarks, idx: int, w: int, h: int) -> np.ndarray:
    lm = landmarks[idx]
    return np.array([lm.x * w, lm.y * h], dtype=np.float64)


def _eye_center(landmarks, indices: Tuple[int, ...], w: int, h: int) -> np.ndarray:
    pts = np.array([_landmark_xy(landmarks, i, w, h) for i in indices])
    return pts.mean(axis=0)


class MinimalFaceTracker:
    """
    Tracks only the functional eye center and nose bridge for low CPU load.
    Derives yaw/pitch/roll and translation proxy from 2-point geometry.
    """

    def __init__(
        self,
        functional_eye: Literal["left", "right"] = "left",
        model_complexity: int = 0,
        refine_landmarks: bool = False,
    ):
        self.functional_eye = functional_eye
        self._mp_face = mp.solutions.face_mesh
        self._face_mesh = self._mp_face.FaceMesh(
            static_image_mode=False,
            max_num_faces=1,
            refine_landmarks=refine_landmarks,
            min_detection_confidence=0.5,
            min_tracking_confidence=0.5,
            model_complexity=model_complexity,
        )
        self._baseline: Optional[np.ndarray] = None
        self._baseline_angle: float = 0.0
        self._baseline_dist: float = 1.0
        self._calibrated = False

    def close(self) -> None:
        self._face_mesh.close()

    def calibrate(self) -> None:
        """Reset neutral pose baseline — call when user is centered."""
        self._baseline = None
        self._calibrated = False

    def _eye_indices(self) -> Tuple[int, ...]:
        return LEFT_EYE_INDICES if self.functional_eye == "left" else RIGHT_EYE_INDICES

    def process(self, frame_bgr: np.ndarray) -> HeadPose:
        t = time.perf_counter()
        h, w = frame_bgr.shape[:2]
        rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        rgb.flags.writeable = False
        result = self._face_mesh.process(rgb)

        if not result.multi_face_landmarks:
            return HeadPose(timestamp=t, tracking_ok=False)

        landmarks = result.multi_face_landmarks[0].landmark
        eye = _eye_center(landmarks, self._eye_indices(), w, h)
        nose = _landmark_xy(landmarks, NOSE_BRIDGE, w, h)

        # Vector from nose bridge to functional eye
        vec = eye - nose
        dist = float(np.linalg.norm(vec))
        angle = math.atan2(vec[1], vec[0])

        if not self._calibrated or self._baseline is None:
            self._baseline = vec.copy()
            self._baseline_angle = angle
            self._baseline_dist = max(dist, 1e-3)
            self._calibrated = True
            return HeadPose(timestamp=t, tracking_ok=True)

        # Normalized deltas relative to neutral
        dx = (vec[0] - self._baseline[0]) / w
        dy = (vec[1] - self._baseline[1]) / h
        dz = (dist - self._baseline_dist) / self._baseline_dist

        d_angle = angle - self._baseline_angle
        # Small-angle mapping: horizontal eye shift → yaw, vertical → pitch
        yaw = d_angle + dx * 2.0
        pitch = dy * 3.0
        roll = d_angle * 0.3

        return HeadPose(
            yaw=yaw,
            pitch=pitch,
            roll=roll,
            x=dx,
            y=dy,
            z=dz,
            timestamp=t,
            tracking_ok=True,
        )

    def draw_debug(self, frame_bgr: np.ndarray) -> np.ndarray:
        """Overlay tracked points for GUI preview."""
        h, w = frame_bgr.shape[:2]
        rgb = cv2.cvtColor(frame_bgr, cv2.COLOR_BGR2RGB)
        result = self._face_mesh.process(rgb)
        out = frame_bgr.copy()
        if not result.multi_face_landmarks:
            return out

        landmarks = result.multi_face_landmarks[0].landmark
        eye = _eye_center(landmarks, self._eye_indices(), w, h).astype(int)
        nose = _landmark_xy(landmarks, NOSE_BRIDGE, w, h).astype(int)

        cv2.circle(out, tuple(eye), 4, (0, 255, 0), -1)
        cv2.circle(out, tuple(nose), 4, (0, 200, 255), -1)
        cv2.line(out, tuple(nose), tuple(eye), (255, 180, 0), 1)
        return out
