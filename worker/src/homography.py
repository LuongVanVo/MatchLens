# Mục đích: transform vị trí pixel sang position_field normalized 0-100

import numpy as np
import cv2

class HomographyProjector:
    def __init__(self, image_points: list[list[float]], field_points: list[list[float]]) -> None:
        if len(image_points) != 4 or len(field_points) != 4:
            raise ValueError("Homography requires exactly 4 anchor points")

        src = np.array(image_points, dtype=np.float32)
        dst = np.array(field_points, dtype=np.float32)
        matrix, _ = cv2.findHomography(src, dst)

        if matrix is None:
            raise RuntimeError("Failed to compute homography matrix")

        self.matrix = matrix

    def project(self, x: float, y: float) -> tuple[float, float]:
        point = np.array([[[x, y]]], dtype=np.float32)
        transformed = cv2.perspectiveTransform(point, self.matrix)[0][0]
        px, py = float(transformed[0]), float(transformed[1])

        nx = min(max(px, 0.0), 100.0)
        ny = min(max(py, 0.0), 100.0)

        return nx, ny