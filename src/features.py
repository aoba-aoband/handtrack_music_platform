"""Extract neutral control features from hand landmarks.

Features in this module should describe hand motion or shape, not fixed
musical destinations such as pitch, volume, or filter cutoff.
"""

from dataclasses import dataclass
from math import hypot


THUMB_TIP = 4
INDEX_TIP = 8
MIDDLE_TIP = 12


@dataclass(frozen=True)
class HandFeatures:
    """Neutral hand-derived values suitable for later control mapping."""

    handedness: str
    index_tip_x: float
    index_tip_y: float
    middle_tip_x: float
    middle_tip_y: float
    thumb_tip_x: float
    thumb_tip_y: float
    pinch: float
    landmarks_count: int


def _handedness_label(handedness):
    """Return a readable MediaPipe handedness label."""
    if handedness is None:
        return "Unknown"

    if isinstance(handedness, str):
        return handedness

    if isinstance(handedness, (list, tuple)):
        if not handedness:
            return "Unknown"
        handedness = handedness[0]

    return (
        getattr(handedness, "category_name", None)
        or getattr(handedness, "display_name", None)
        or "Unknown"
    )


def extract_hand_features(hand_landmarks, handedness=None):
    """Convert one detected hand's landmarks into neutral feature values."""
    landmarks = list(hand_landmarks or [])
    landmarks_count = len(landmarks)
    required_count = max(THUMB_TIP, INDEX_TIP, MIDDLE_TIP) + 1
    if landmarks_count < required_count:
        raise ValueError(
            "Expected at least "
            f"{required_count} hand landmarks, got {landmarks_count}"
        )

    thumb_tip = landmarks[THUMB_TIP]
    index_tip = landmarks[INDEX_TIP]
    middle_tip = landmarks[MIDDLE_TIP]
    pinch = hypot(index_tip.x - thumb_tip.x, index_tip.y - thumb_tip.y)

    return HandFeatures(
        handedness=_handedness_label(handedness),
        index_tip_x=index_tip.x,
        index_tip_y=index_tip.y,
        middle_tip_x=middle_tip.x,
        middle_tip_y=middle_tip.y,
        thumb_tip_x=thumb_tip.x,
        thumb_tip_y=thumb_tip.y,
        pinch=max(0.0, min(pinch, 1.0)),
        landmarks_count=landmarks_count,
    )


def extract_features(hand_frame):
    """Convert a MediaPipe hand result into neutral feature values."""
    hand_landmarks = getattr(hand_frame, "hand_landmarks", [])
    handednesses = getattr(hand_frame, "handedness", [])

    features = []
    for index, landmarks in enumerate(hand_landmarks):
        handedness = handednesses[index] if index < len(handednesses) else None
        features.append(extract_hand_features(landmarks, handedness))

    return features
