"""OpenGL wireframe cube with asymmetric frustum projection from head pose."""

from __future__ import annotations

import math
from typing import Optional

import numpy as np
from OpenGL.GL import (
    GL_COLOR_BUFFER_BIT,
    GL_DEPTH_BUFFER_BIT,
    GL_DEPTH_TEST,
    GL_LINES,
    glBegin,
    glClear,
    glClearColor,
    glColor3f,
    glEnable,
    glEnd,
    glFrustum,
    glLoadIdentity,
    glMatrixMode,
    glRotatef,
    glTranslatef,
    glVertex3f,
    glViewport,
    GL_MODELVIEW,
    GL_PROJECTION,
)
from OpenGL.GLU import gluPerspective
from PySide6.QtOpenGLWidgets import QOpenGLWidget

from parallax.types import HeadPose


# Unit cube vertices
_VERTICES = [
    (-1, -1, -1),
    (1, -1, -1),
    (1, 1, -1),
    (-1, 1, -1),
    (-1, -1, 1),
    (1, -1, 1),
    (1, 1, 1),
    (-1, 1, 1),
]

_EDGES = [
    (0, 1),
    (1, 2),
    (2, 3),
    (3, 0),
    (4, 5),
    (5, 6),
    (6, 7),
    (7, 4),
    (0, 4),
    (1, 5),
    (2, 6),
    (3, 7),
]


def _asymmetric_frustum(
    yaw: float,
    pitch: float,
    z: float,
    fov: float = 45.0,
    aspect: float = 1.0,
    near: float = 0.1,
    far: float = 100.0,
) -> np.ndarray:
    """
    Build a 4x4 projection matrix with shifted frustum center.
    Mimics off-axis projection for monocular parallax depth cues.
    """
    f = 1.0 / math.tan(math.radians(fov) / 2.0)
    shift_x = yaw * 2.0
    shift_y = pitch * 2.0
    depth_scale = 1.0 + z * 0.3

    left = (-aspect + shift_x) * near / depth_scale
    right = (aspect + shift_x) * near / depth_scale
    bottom = (-1.0 + shift_y) * near / depth_scale
    top = (1.0 + shift_y) * near / depth_scale

    m = np.zeros((4, 4), dtype=np.float64)
    m[0, 0] = 2.0 * near / (right - left)
    m[1, 1] = 2.0 * near / (top - bottom)
    m[0, 2] = (right + left) / (right - left)
    m[1, 2] = (top + bottom) / (top - bottom)
    m[2, 2] = -(far + near) / (far - near)
    m[2, 3] = -2.0 * far * near / (far - near)
    m[3, 2] = -1.0
    return m


class ParallaxCubeWidget(QOpenGLWidget):
    """Real-time 3D preview — wireframe cube shifts with head pose."""

    def __init__(self, parent=None):
        super().__init__(parent)
        self._pose = HeadPose()
        self.setMinimumSize(400, 300)

    def set_pose(self, pose: HeadPose) -> None:
        self._pose = pose
        self.update()

    def initializeGL(self) -> None:
        glClearColor(0.08, 0.09, 0.12, 1.0)
        glEnable(GL_DEPTH_TEST)

    def resizeGL(self, w: int, h: int) -> None:
        glViewport(0, 0, w, max(h, 1))

    def paintGL(self) -> None:
        glClear(GL_COLOR_BUFFER_BIT | GL_DEPTH_BUFFER_BIT)

        w = max(self.width(), 1)
        h = max(self.height(), 1)
        aspect = w / h

        glMatrixMode(GL_PROJECTION)
        glLoadIdentity()

        if self._pose.tracking_ok:
            shift_x = self._pose.yaw * 0.8
            shift_y = self._pose.pitch * 0.8
            depth = 6.0 - self._pose.z * 2.0
            glFrustum(
                (-aspect + shift_x) * 0.5,
                (aspect + shift_x) * 0.5,
                -1.0 + shift_y,
                1.0 + shift_y,
                depth * 0.15,
                100.0,
            )
        else:
            gluPerspective(45.0, aspect, 0.1, 100.0)

        glMatrixMode(GL_MODELVIEW)
        glLoadIdentity()

        if self._pose.tracking_ok:
            glTranslatef(0.0, 0.0, -6.0 + self._pose.z * 2.0)
            glRotatef(math.degrees(self._pose.roll), 0.0, 0.0, 1.0)
            glRotatef(math.degrees(self._pose.yaw), 0.0, 1.0, 0.0)
            glRotatef(math.degrees(self._pose.pitch), 1.0, 0.0, 0.0)
        else:
            glTranslatef(0.0, 0.0, -6.0)

        # Wireframe cube
        glColor3f(0.2, 0.85, 0.95)
        glBegin(GL_LINES)
        for i, j in _EDGES:
            glVertex3f(*_VERTICES[i])
            glVertex3f(*_VERTICES[j])
        glEnd()

        # Floor grid for depth reference
        glColor3f(0.25, 0.3, 0.35)
        glBegin(GL_LINES)
        for i in range(-3, 4):
            glVertex3f(float(i), -1.5, -3.0)
            glVertex3f(float(i), -1.5, 3.0)
            glVertex3f(-3.0, -1.5, float(i))
            glVertex3f(3.0, -1.5, float(i))
        glEnd()
