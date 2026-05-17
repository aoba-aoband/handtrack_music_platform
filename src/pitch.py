"""Pitch helper functions shared by mapping and preview guide display.

This module should stay independent from camera tracking and output adapters so
future quantization can reuse the same pitch and guide calculations.
"""

from math import ceil, floor, log


PITCH_GUIDE_NORMS = (0.0, 0.25, 0.5, 0.75, 1.0)
PITCH_GUIDE_EPSILON = 1e-9
PITCH_GUIDE_MODE_NAMES = ("simple", "chromatic", "scale")
NOTE_NAMES = ("C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B")
ROOT_NOTE_NAMES = NOTE_NAMES
NOTE_NAME_TO_PITCH_CLASS = {
    "C": 0,
    "B#": 0,
    "C#": 1,
    "DB": 1,
    "D": 2,
    "D#": 3,
    "EB": 3,
    "E": 4,
    "FB": 4,
    "F": 5,
    "E#": 5,
    "F#": 6,
    "GB": 6,
    "G": 7,
    "G#": 8,
    "AB": 8,
    "A": 9,
    "A#": 10,
    "BB": 10,
    "B": 11,
    "CB": 11,
}
SCALE_NAMES = (
    "chromatic",
    "major",
    "minor",
    "major-pentatonic",
    "minor-pentatonic",
)
PITCH_GUIDE_SCALES = {
    "chromatic": (0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11),
    "major": (0, 2, 4, 5, 7, 9, 11),
    "minor": (0, 2, 3, 5, 7, 8, 10),
    "major-pentatonic": (0, 2, 4, 7, 9),
    "minor-pentatonic": (0, 3, 5, 7, 10),
}


def norm_to_freq(norm, min_freq, max_freq):
    """Map a normalized pitch value to frequency using exponential scaling."""
    norm = max(0.0, min(1.0, norm))
    return min_freq * ((max_freq / min_freq) ** norm)


def build_pitch_guides(
    mode,
    pitch_min_freq,
    pitch_max_freq,
    root="A",
    scale="minor-pentatonic",
):
    """Build pitch guide labels and normalized vertical positions."""
    if mode == "chromatic":
        return build_chromatic_pitch_guides(
            pitch_min_freq,
            pitch_max_freq,
            root=root,
        )

    if mode == "scale":
        return build_scale_pitch_guides(
            pitch_min_freq,
            pitch_max_freq,
            root=root,
            scale=scale,
        )

    return build_simple_pitch_guides(pitch_min_freq, pitch_max_freq)


def build_simple_pitch_guides(pitch_min_freq, pitch_max_freq):
    """Build five evenly spaced continuous pitch guide lines."""
    if not is_valid_pitch_range(pitch_min_freq, pitch_max_freq):
        return []

    guides = []
    for pitch_norm in PITCH_GUIDE_NORMS:
        freq = norm_to_freq(
            pitch_norm,
            min_freq=pitch_min_freq,
            max_freq=pitch_max_freq,
        )
        guides.append(
            {
                "pitch_norm": pitch_norm,
                "label": f"{freq:.0f}Hz",
                "is_root": False,
            }
        )

    return guides


def build_chromatic_pitch_guides(pitch_min_freq, pitch_max_freq, root="A"):
    """Build semitone guide lines within the active pitch range."""
    root_pitch_class = pitch_class_for_root(root)
    return build_semitone_pitch_guides(
        pitch_min_freq,
        pitch_max_freq,
        allowed_pitch_classes=None,
        root_pitch_class=root_pitch_class,
    )


def build_scale_pitch_guides(
    pitch_min_freq,
    pitch_max_freq,
    root="A",
    scale="minor-pentatonic",
):
    """Build scale-filtered semitone guide lines within the pitch range."""
    root_pitch_class = pitch_class_for_root(root)
    allowed_pitch_classes = pitch_classes_for_scale(root, scale)
    return build_semitone_pitch_guides(
        pitch_min_freq,
        pitch_max_freq,
        allowed_pitch_classes=allowed_pitch_classes,
        root_pitch_class=root_pitch_class,
    )


def quantize_freq_to_scale(freq, root="A", scale="minor-pentatonic"):
    """Snap a frequency to the nearest MIDI note in the selected scale."""
    normalized_root = normalize_root(root)
    normalized_scale = normalize_scale(scale)
    if freq <= 0:
        return {
            "source_freq": freq,
            "quantized_freq": 0.0,
            "quantized_midi": None,
            "note_name": "",
            "root": normalized_root,
            "scale": normalized_scale,
        }

    midi_value = freq_to_midi(freq)
    allowed_pitch_classes = pitch_classes_for_scale(
        normalized_root,
        normalized_scale,
    )
    nearest_midi = nearest_midi_in_pitch_classes(
        midi_value,
        allowed_pitch_classes,
    )
    quantized_freq = midi_to_freq(nearest_midi)

    return {
        "source_freq": freq,
        "quantized_freq": quantized_freq,
        "quantized_midi": nearest_midi,
        "note_name": format_midi_note(nearest_midi),
        "root": normalized_root,
        "scale": normalized_scale,
    }


def pitch_classes_for_scale(root="A", scale="minor-pentatonic"):
    """Return pitch classes included in a root-relative scale."""
    root_pitch_class = pitch_class_for_root(root)
    scale_intervals = PITCH_GUIDE_SCALES[normalize_scale(scale)]
    return {(root_pitch_class + interval) % 12 for interval in scale_intervals}


def nearest_midi_in_pitch_classes(midi_value, allowed_pitch_classes):
    """Return the nearest integer MIDI note in the allowed pitch classes."""
    midi_min = floor(midi_value) - 12
    midi_max = ceil(midi_value) + 12
    candidates = [
        midi_note
        for midi_note in range(midi_min, midi_max + 1)
        if midi_note % 12 in allowed_pitch_classes
    ]
    return min(
        candidates,
        key=lambda midi_note: (abs(midi_note - midi_value), midi_note),
    )


def build_semitone_pitch_guides(
    pitch_min_freq,
    pitch_max_freq,
    allowed_pitch_classes,
    root_pitch_class,
):
    """Build semitone guides, optionally filtered by pitch class."""
    if not is_valid_pitch_range(pitch_min_freq, pitch_max_freq):
        return []

    midi_min = ceil(freq_to_midi(pitch_min_freq) - PITCH_GUIDE_EPSILON)
    midi_max = floor(freq_to_midi(pitch_max_freq) + PITCH_GUIDE_EPSILON)
    guides = []

    for midi_note in range(midi_min, midi_max + 1):
        freq = midi_to_freq(midi_note)
        pitch_class = midi_note % 12
        if (
            allowed_pitch_classes is not None
            and pitch_class not in allowed_pitch_classes
        ):
            continue

        if (
            freq < pitch_min_freq - PITCH_GUIDE_EPSILON
            or freq > pitch_max_freq + PITCH_GUIDE_EPSILON
        ):
            continue

        pitch_norm = freq_to_pitch_norm(
            freq,
            pitch_min_freq,
            pitch_max_freq,
        )
        if pitch_norm is None:
            continue

        label = f"{format_midi_note(midi_note)} {freq:.0f}Hz"
        guides.append(
            {
                "pitch_norm": pitch_norm,
                "label": label,
                "is_root": pitch_class == root_pitch_class,
            }
        )

    return guides


def pitch_class_for_root(root):
    """Return the configured root pitch class, defaulting to A."""
    return NOTE_NAME_TO_PITCH_CLASS[normalize_root(root)]


def normalize_root(root):
    """Normalize a root note name, defaulting unknown names to A."""
    root = str(root or "A").strip().upper()
    return root if root in NOTE_NAME_TO_PITCH_CLASS else "A"


def normalize_scale(scale):
    """Normalize a scale name, defaulting unknown names to minor pentatonic."""
    scale = str(scale or "minor-pentatonic").strip()
    return scale if scale in PITCH_GUIDE_SCALES else "minor-pentatonic"


def freq_to_pitch_norm(freq, pitch_min_freq, pitch_max_freq):
    """Map frequency back to the normalized pitch guide position."""
    if not is_valid_pitch_range(pitch_min_freq, pitch_max_freq):
        return None

    pitch_norm = log(freq / pitch_min_freq) / log(pitch_max_freq / pitch_min_freq)
    return max(0.0, min(1.0, pitch_norm))


def is_valid_pitch_range(pitch_min_freq, pitch_max_freq):
    """Return whether the pitch range can be used for pitch calculations."""
    return pitch_min_freq > 0 and pitch_max_freq > pitch_min_freq


def freq_to_midi(freq):
    """Convert frequency to fractional MIDI note number using A4 = 440Hz."""
    return 69 + 12 * (log(freq / 440.0) / log(2.0))


def midi_to_freq(midi_note):
    """Convert MIDI note number to frequency using A4 = 440Hz."""
    return 440.0 * (2.0 ** ((midi_note - 69) / 12.0))


def format_midi_note(midi_note):
    """Return a compact pitch label such as C4 or F#3."""
    note_name = NOTE_NAMES[midi_note % 12]
    octave = (midi_note // 12) - 1
    return f"{note_name}{octave}"
