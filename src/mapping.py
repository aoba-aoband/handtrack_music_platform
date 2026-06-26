"""Map extracted hand features into generic control events.

Mappings should be configurable so the platform can target SuperCollider,
Ableton Live, Max for Live, or other systems without hard-coded gesture roles.
"""

from src.features import HandFeatures
from src.pitch import (
    norm_to_freq as _norm_to_freq,
    quantize_freq_to_scale,
)


DEFAULT_MIN_FREQ = 220.0
DEFAULT_MAX_FREQ = 880.0


class ControlEvent:
    """A generic control message produced from hand-derived features."""

    def __init__(self, address, value, metadata=None):
        self.address = address
        self.value = value
        self.metadata = metadata or {}


class Mapper:
    """Convert feature dictionaries into generic control events."""

    def __init__(self, mapping_config=None):
        self.mapping_config = mapping_config or {}

    def map(self, features):
        """Return control events for the given feature values."""
        raise NotImplementedError


class HandFeatureMapper(Mapper):
    """Map neutral hand features to generic hand control events."""

    def map(self, features):
        """Return generic control events for one or more hands."""
        if isinstance(features, HandFeatures):
            features = [features]

        events = []
        for hand_index, hand_features in enumerate(features or []):
            events.extend(map_hand_features(hand_features, hand_index))

        return events


class SampleMusicalMapper(Mapper):
    """Map neutral hand features to sample musical control events."""

    def map(self, features):
        """Return sample events based on MediaPipe handedness labels."""
        if isinstance(features, HandFeatures):
            features = [features]

        events = []
        for hand_index, hand_features in enumerate(features or []):
            events.extend(
                map_sample_musical_features(
                    hand_features,
                    hand_index,
                    self.mapping_config,
                )
            )

        return events


def map_hand_features(features, hand_index=0):
    """Convert one HandFeatures object into generic ControlEvents."""
    metadata = {
        "hand_index": hand_index,
        "handedness": features.handedness,
        "landmarks_count": features.landmarks_count,
    }
    prefix = f"/hand/{hand_index}"

    return [
        ControlEvent(
            f"{prefix}/index/x",
            features.index_tip_x,
            {**metadata, "feature": "index_tip_x"},
        ),
        ControlEvent(
            f"{prefix}/index/y",
            features.index_tip_y,
            {**metadata, "feature": "index_tip_y"},
        ),
        ControlEvent(
            f"{prefix}/middle/x",
            features.middle_tip_x,
            {**metadata, "feature": "middle_tip_x"},
        ),
        ControlEvent(
            f"{prefix}/middle/y",
            features.middle_tip_y,
            {**metadata, "feature": "middle_tip_y"},
        ),
        ControlEvent(
            f"{prefix}/thumb/x",
            features.thumb_tip_x,
            {**metadata, "feature": "thumb_tip_x"},
        ),
        ControlEvent(
            f"{prefix}/thumb/y",
            features.thumb_tip_y,
            {**metadata, "feature": "thumb_tip_y"},
        ),
        ControlEvent(
            f"{prefix}/pinch",
            features.pinch,
            {**metadata, "feature": "pinch"},
        ),
    ]


def map_sample_musical_features(features, hand_index=0, mapping_config=None):
    """Convert one HandFeatures object into sample mapping ControlEvents."""
    mapping_config = mapping_config or {}
    pitch_min_freq = mapping_config.get("pitch_min_freq", DEFAULT_MIN_FREQ)
    pitch_max_freq = mapping_config.get("pitch_max_freq", DEFAULT_MAX_FREQ)
    quantize_pitch = bool(mapping_config.get("quantize_pitch", False))
    pitch_root = mapping_config.get("pitch_root", "A")
    pitch_scale = mapping_config.get("pitch_scale", "minor-pentatonic")
    handedness = (features.handedness or "").strip().lower()
    metadata = {
        "source_hand_index": hand_index,
        "handedness": features.handedness,
        "landmarks_count": features.landmarks_count,
        "mapping": "sample_musical",
    }

    if handedness == "right":
        inverted_y = max(0.0, min(1.0, 1.0 - features.index_tip_y))
        pitch_norm = inverted_y
        octave_shift = 1.0 if features.middle_tip_y < features.index_tip_y else 0.0
        pitch_freq = norm_to_freq(
            pitch_norm,
            min_freq=pitch_min_freq,
            max_freq=pitch_max_freq,
        )
        freq_with_octave = pitch_freq * (2.0 if octave_shift >= 1.0 else 1.0)
        quantized_pitch = quantize_freq_to_scale(
            freq_with_octave,
            root=pitch_root,
            scale=pitch_scale,
        )
        quantized_freq = quantized_pitch["quantized_freq"]
        final_freq = quantized_freq if quantize_pitch else freq_with_octave
        return [
            ControlEvent(
                "/sample/right/index/y",
                features.index_tip_y,
                {**metadata, "feature": "index_tip_y", "role": "pitch_candidate"},
            ),
            ControlEvent(
                "/sample/right/index/y_inverted",
                inverted_y,
                {
                    **metadata,
                    "feature": "index_tip_y_inverted",
                    "role": "pitch_candidate",
                },
            ),
            ControlEvent(
                "/sample/right/pitch/norm",
                pitch_norm,
                {
                    **metadata,
                    "feature": "pitch_norm",
                    "role": "pitch_candidate",
                },
            ),
            ControlEvent(
                "/sample/right/pitch/octave_shift",
                octave_shift,
                {
                    **metadata,
                    "feature": "middle_above_index",
                    "role": "octave_candidate",
                },
            ),
            ControlEvent(
                "/sample/right/pitch/freq",
                pitch_freq,
                {
                    **metadata,
                    "feature": "pitch_freq",
                    "role": "pitch_candidate",
                    "min_freq": pitch_min_freq,
                    "max_freq": pitch_max_freq,
                },
            ),
            ControlEvent(
                "/sample/right/pitch/freq_with_octave",
                freq_with_octave,
                {
                    **metadata,
                    "feature": "pitch_freq_with_octave",
                    "role": "pitch_candidate",
                    "octave_shift": octave_shift,
                    "base_freq": pitch_freq,
                    "min_freq": pitch_min_freq,
                    "max_freq": pitch_max_freq,
                },
            ),
            ControlEvent(
                "/sample/right/pitch/quantized_freq",
                quantized_freq,
                {
                    **metadata,
                    "feature": "pitch_quantized_freq",
                    "role": "pitch_candidate",
                    "root": quantized_pitch["root"],
                    "scale": quantized_pitch["scale"],
                    "source_freq": freq_with_octave,
                    "quantized_midi": quantized_pitch["quantized_midi"],
                    "quantized_note": quantized_pitch["note_name"],
                },
            ),
            ControlEvent(
                "/sample/right/pitch/final_freq",
                final_freq,
                {
                    **metadata,
                    "feature": "pitch_final_freq",
                    "role": "pitch_candidate",
                    "quantized": quantize_pitch,
                    "root": quantized_pitch["root"],
                    "scale": quantized_pitch["scale"],
                    "source_freq": freq_with_octave,
                    "quantized_freq": quantized_freq,
                    "quantized_note": quantized_pitch["note_name"],
                },
            ),
        ]

    if handedness == "left":
        tone_norm = max(0.0, min(1.0, features.index_tip_x))
        return [
            ControlEvent(
                "/sample/left/pinch",
                features.pinch,
                {**metadata, "feature": "pinch", "role": "amp_candidate"},
            ),
            ControlEvent(
                "/sample/left/tone/norm",
                tone_norm,
                {
                    **metadata,
                    "feature": "index_tip_x",
                    "role": "tone_candidate",
                },
            ),
        ]

    return []


def norm_to_freq(norm, min_freq=DEFAULT_MIN_FREQ, max_freq=DEFAULT_MAX_FREQ):
    """Map a normalized pitch value to frequency using exponential scaling."""
    return _norm_to_freq(norm, min_freq, max_freq)
