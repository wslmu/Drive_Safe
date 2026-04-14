from __future__ import annotations

import math
from typing import Sequence


LEFT_EYE = [362, 385, 387, 263, 373, 380]
RIGHT_EYE = [33, 160, 158, 133, 153, 144]
MOUTH = [13, 14, 78, 308]
RIGHT_EYE_CORNER = 33
LEFT_EYE_CORNER = 263
NOSE_TIP = 4
NOSE_BRIDGE = 6


def distance(point_a, point_b) -> float:
    return math.sqrt((point_a.x - point_b.x) ** 2 + (point_a.y - point_b.y) ** 2)


def calculate_ear(points: Sequence, indices: Sequence[int]) -> float:
    p1 = points[indices[0]]
    p2 = points[indices[1]]
    p3 = points[indices[2]]
    p4 = points[indices[3]]
    p5 = points[indices[4]]
    p6 = points[indices[5]]
    vertical_1 = distance(p2, p6)
    vertical_2 = distance(p3, p5)
    horizontal = distance(p1, p4)
    if horizontal == 0:
        return 0.0
    return (vertical_1 + vertical_2) / (2.0 * horizontal)


def calculate_mar(points: Sequence, indices: Sequence[int]) -> float:
    top = points[indices[0]]
    bottom = points[indices[1]]
    left = points[indices[2]]
    right = points[indices[3]]
    vertical = distance(top, bottom)
    horizontal = distance(left, right)
    if horizontal == 0:
        return 0.0
    return vertical / horizontal


def calculate_head_angle(points: Sequence) -> float:
    right_corner = points[RIGHT_EYE_CORNER]
    left_corner = points[LEFT_EYE_CORNER]
    dx = left_corner.x - right_corner.x
    dy = left_corner.y - right_corner.y
    return math.degrees(math.atan2(dy, dx))


def calculate_forward_drop(points: Sequence) -> float:
    nose_tip = points[NOSE_TIP]
    nose_bridge = points[NOSE_BRIDGE]
    return nose_tip.y - nose_bridge.y


def calculate_fatigue_score(
    ear: float,
    mar: float,
    angle: float,
    blinks_per_minute: int,
    forward_drop: float,
    eye_threshold: float,
    mouth_threshold: float,
    head_angle_threshold: float,
    blink_rate_threshold: int,
) -> int:
    score = 0
    if ear < eye_threshold:
        score += 30
    elif ear < 0.28:
        score += 10

    if mar > mouth_threshold:
        score += 20
    elif mar > 0.35:
        score += 5

    if abs(angle) > head_angle_threshold:
        score += 25
    elif abs(angle) > 10:
        score += 8

    if blinks_per_minute > blink_rate_threshold:
        score += 15

    if forward_drop > 0.08:
        score += 10

    return min(score, 100)
