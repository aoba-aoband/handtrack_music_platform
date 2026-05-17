"""Capture hand landmark frames from an input device.

This module should stay focused on tracking hands and returning neutral
landmark data. It should not assign musical meaning to gestures.
"""

from dataclasses import replace
from pathlib import Path
import time

import cv2
import mediapipe as mp
from mediapipe.tasks.python import BaseOptions, vision

from src.features import extract_features
from src.pitch import (
    NOTE_NAMES,
    PITCH_GUIDE_MODE_NAMES,
    SCALE_NAMES,
    build_pitch_guides,
    format_midi_note,
    freq_to_midi,
    midi_to_freq,
    normalize_root,
    normalize_scale,
)
from src.mapping import (
    DEFAULT_MAX_FREQ,
    DEFAULT_MIN_FREQ,
    HandFeatureMapper,
    SampleMusicalMapper,
)


DEFAULT_HAND_MODEL_PATH = "models/hand_landmarker.task"
HANDEDNESS_STABLE_FRAMES = 3
SETTINGS_PANEL_WINDOW = "Pitch Settings"
SETTINGS_MIDI_MIN = 45
SETTINGS_MIDI_MAX = 84


class HandednessStabilizer:
    """Debounce handedness labels for sample mapping roles."""

    def __init__(self, required_frames=HANDEDNESS_STABLE_FRAMES):
        self.required_frames = required_frames
        self.states = {}

    def stabilize(self, features):
        """Return features with handedness labels stabilized per hand index."""
        stabilized = []
        active_indexes = set()

        for hand_index, hand_features in enumerate(features):
            active_indexes.add(hand_index)
            stable_handedness = self.stabilize_label(
                hand_index,
                hand_features.handedness,
            )
            if stable_handedness == hand_features.handedness:
                stabilized.append(hand_features)
            else:
                stabilized.append(replace(hand_features, handedness=stable_handedness))

        for hand_index in list(self.states):
            if hand_index not in active_indexes:
                del self.states[hand_index]

        return stabilized

    def stabilize_label(self, hand_index, raw_handedness):
        """Return a debounced handedness label for one hand index."""
        state = self.states.get(hand_index)
        if state is None:
            state = {
                "stable": raw_handedness,
                "candidate": raw_handedness,
                "count": self.required_frames,
            }
            self.states[hand_index] = state
            return raw_handedness

        if raw_handedness == state["stable"]:
            state["candidate"] = raw_handedness
            state["count"] = self.required_frames
            return state["stable"]

        if raw_handedness == state["candidate"]:
            state["count"] += 1
        else:
            state["candidate"] = raw_handedness
            state["count"] = 1

        if state["count"] >= self.required_frames:
            state["stable"] = raw_handedness
            state["count"] = self.required_frames

        return state["stable"]


class HandTracker:
    """Track hands and yield raw landmark frames."""

    def start(self):
        """Prepare the tracker and input device."""
        raise NotImplementedError

    def read(self):
        """Return the next hand landmark frame."""
        raise NotImplementedError

    def stop(self):
        """Release tracker resources."""
        raise NotImplementedError


class OpenCVCameraSmokeTest:
    """Open a webcam preview without hand tracking or OSC output."""

    def __init__(self, camera_index=0, window_name="Camera Smoke Test"):
        self.camera_index = camera_index
        self.window_name = window_name
        self.capture = None

    def start(self):
        """Open the configured camera."""
        self.capture = cv2.VideoCapture(self.camera_index)
        if not self.capture.isOpened():
            self.capture.release()
            self.capture = None
            raise RuntimeError(f"Could not open camera index {self.camera_index}")

    def read(self):
        """Read one raw camera frame."""
        if self.capture is None:
            raise RuntimeError("Camera has not been started")

        ok, frame = self.capture.read()
        if not ok:
            raise RuntimeError("Could not read frame from camera")

        return frame

    def run(self):
        """Show camera frames until q is pressed."""
        self.start()
        try:
            while True:
                frame = self.read()
                cv2.imshow(self.window_name, frame)

                if cv2.waitKey(1) & 0xFF == ord("q"):
                    break
        finally:
            self.stop()

    def stop(self):
        """Release camera and close the preview window."""
        if self.capture is not None:
            self.capture.release()
            self.capture = None

        try:
            cv2.destroyWindow(self.window_name)
        except cv2.error:
            pass


class MediaPipeHandsSmokeTest:
    """Draw MediaPipe hand landmarks on a webcam preview."""

    def __init__(
        self,
        camera_index=0,
        window_name="MediaPipe Hands Smoke Test",
        max_num_hands=2,
        model_path=DEFAULT_HAND_MODEL_PATH,
        show_features=False,
        show_events=False,
        sample_mapping=False,
        show_pitch_guides=False,
        pitch_guide_mode="simple",
        pitch_guide_root="A",
        pitch_guide_scale="minor-pentatonic",
        show_settings_panel=False,
        sample_mapping_config=None,
        event_sink=None,
    ):
        self.camera_index = camera_index
        self.window_name = window_name
        self.max_num_hands = max_num_hands
        self.model_path = model_path
        self.show_features = show_features
        self.show_events = show_events
        self.sample_mapping = sample_mapping
        self.show_pitch_guides = show_pitch_guides
        self.pitch_guide_mode = pitch_guide_mode
        self.pitch_guide_root = pitch_guide_root
        self.pitch_guide_scale = pitch_guide_scale
        self.show_settings_panel = show_settings_panel
        self.sample_mapping_config = dict(sample_mapping_config or {})
        self.event_sink = event_sink
        self.capture = None
        self.landmarker = None
        self.settings_panel_started = False
        self.mapper = HandFeatureMapper()
        self.sample_mapper = SampleMusicalMapper(
            mapping_config=self.sample_mapping_config
        )
        self.handedness_stabilizer = HandednessStabilizer()
        self.last_timestamp_ms = 0
        self.current_features = []
        self.current_sample_features = []
        self.current_events = []
        self.current_sample_events = []
        self.current_hand_labels = []

    def start(self):
        """Open the configured camera and initialize MediaPipe Hands."""
        model_path = Path(self.model_path)
        if not model_path.exists():
            raise RuntimeError(
                "Could not find MediaPipe hand landmarker model file at "
                f"{str(model_path)!r}."
            )

        self.capture = cv2.VideoCapture(self.camera_index)
        if not self.capture.isOpened():
            self.capture.release()
            self.capture = None
            raise RuntimeError(f"Could not open camera index {self.camera_index}")

        options = vision.HandLandmarkerOptions(
            base_options=BaseOptions(model_asset_path=str(model_path)),
            running_mode=vision.RunningMode.VIDEO,
            num_hands=self.max_num_hands,
            min_hand_detection_confidence=0.5,
            min_hand_presence_confidence=0.5,
            min_tracking_confidence=0.5,
        )
        try:
            self.landmarker = vision.HandLandmarker.create_from_options(options)
        except ValueError as exc:
            self.stop()
            raise RuntimeError(
                "Could not start MediaPipe HandLandmarker. "
                f"Expected model file at {str(model_path)!r}."
            ) from exc

        self.start_settings_panel()

    def read(self):
        """Read one camera frame."""
        if self.capture is None:
            raise RuntimeError("Camera has not been started")

        ok, frame = self.capture.read()
        if not ok:
            raise RuntimeError("Could not read frame from camera")

        return frame

    def draw_landmarks(self, frame):
        """Draw detected hand landmarks and connections on a frame."""
        if self.landmarker is None:
            raise RuntimeError("MediaPipe HandLandmarker has not been started")

        rgb_frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
        mp_image = mp.Image(image_format=mp.ImageFormat.SRGB, data=rgb_frame)
        timestamp_ms = max(int(time.monotonic() * 1000), self.last_timestamp_ms + 1)
        self.last_timestamp_ms = timestamp_ms
        results = self.landmarker.detect_for_video(mp_image, timestamp_ms)
        self.current_features = extract_features(results)
        self.current_sample_features = self.current_features
        self.current_events = self.mapper.map(self.current_features)
        self.current_sample_events = []
        if self.sample_mapping:
            self.current_sample_features = self.handedness_stabilizer.stabilize(
                self.current_features
            )
            self.current_sample_events = self.sample_mapper.map(
                self.current_sample_features
            )
        self.current_hand_labels = self.build_hand_labels(results.hand_landmarks)
        output_events = self.current_events + self.current_sample_events
        if self.event_sink is not None and output_events:
            self.event_sink(output_events)

        if results.hand_landmarks:
            for hand_landmarks in results.hand_landmarks:
                vision.drawing_utils.draw_landmarks(
                    frame,
                    hand_landmarks,
                    vision.HandLandmarksConnections.HAND_CONNECTIONS,
                    vision.drawing_styles.get_default_hand_landmarks_style(),
                    vision.drawing_styles.get_default_hand_connections_style(),
                )

        return frame

    def build_hand_labels(self, hand_landmarks):
        """Build handedness labels positioned near each detected hand."""
        labels = []
        for hand_index, landmarks in enumerate(hand_landmarks or []):
            if not landmarks:
                continue

            xs = [landmark.x for landmark in landmarks]
            ys = [landmark.y for landmark in landmarks]
            handedness = self.format_handedness_label(hand_index)

            labels.append(
                {
                    "text": f"hand {hand_index}: {handedness}",
                    "display_anchor_x": 1.0 - max(xs),
                    "anchor_y": min(ys),
                }
            )

        return labels

    def format_handedness_label(self, hand_index):
        """Return the display label for raw and stabilized handedness."""
        if hand_index >= len(self.current_features):
            return "Unknown"

        raw_handedness = self.current_features[hand_index].handedness
        if not self.sample_mapping or hand_index >= len(self.current_sample_features):
            return raw_handedness

        stable_handedness = self.current_sample_features[hand_index].handedness
        if stable_handedness == raw_handedness:
            return stable_handedness

        return f"{stable_handedness} (raw {raw_handedness})"

    def draw_hand_labels(self, frame):
        """Draw hand index and handedness labels near detected hands."""
        if not self.show_features and not self.show_events:
            return frame

        height, width = frame.shape[:2]
        font = cv2.FONT_HERSHEY_SIMPLEX
        scale = 0.6
        color = (0, 255, 255)
        shadow = (0, 0, 0)
        thickness = 1
        margin = 8

        for label in self.current_hand_labels:
            text = label["text"]
            text_size, _ = cv2.getTextSize(text, font, scale, thickness)
            x = int(label["display_anchor_x"] * width)
            y = int(label["anchor_y"] * height) - margin
            x = max(margin, min(x, width - text_size[0] - margin))
            y = max(24, min(y, height - margin))
            origin = (x, y)

            cv2.putText(frame, text, origin, font, scale, shadow, thickness + 3)
            cv2.putText(frame, text, origin, font, scale, color, thickness)

        return frame

    def draw_status_overlay(self, frame):
        """Draw optional neutral feature and event values on the display frame."""
        if not self.show_features and not self.show_events:
            return frame

        font = cv2.FONT_HERSHEY_SIMPLEX
        scale = 0.5
        color = (255, 255, 255)
        shadow = (0, 0, 0)
        thickness = 1
        line_height = 20
        x = 12
        y = 24

        lines = []
        if self.show_features:
            lines.append(f"hands: {len(self.current_features)}")
            for hand_index, features in enumerate(self.current_features):
                lines.extend(
                    [
                        (
                            f"hand {hand_index}: "
                            f"{self.format_handedness_label(hand_index)} "
                            f"landmarks={features.landmarks_count}"
                        ),
                        (
                            f"index=({features.index_tip_x:.3f}, "
                            f"{features.index_tip_y:.3f})"
                        ),
                        (
                            f"middle=({features.middle_tip_x:.3f}, "
                            f"{features.middle_tip_y:.3f})"
                        ),
                        (
                            f"thumb=({features.thumb_tip_x:.3f}, "
                            f"{features.thumb_tip_y:.3f}) "
                            f"pinch={features.pinch:.3f}"
                        ),
                    ]
                )

        if self.show_events:
            if lines:
                lines.append("")
            if not self.show_features:
                lines.append(f"hands: {len(self.current_features)}")
                for hand_index, features in enumerate(self.current_features):
                    lines.append(
                        f"hand {hand_index}: "
                        f"{self.format_handedness_label(hand_index)}"
                    )
                if self.current_features:
                    lines.append("")
            lines.append(f"events: {len(self.current_events)}")
            for event in self.current_events:
                lines.append(f"{event.address} {event.value:.3f}")

            if self.sample_mapping:
                lines.append("")
                lines.append(f"sample events: {len(self.current_sample_events)}")
                for event in self.current_sample_events:
                    lines.append(f"{event.address} {event.value:.3f}")

        for offset, line in enumerate(lines):
            origin = (x, y + offset * line_height)
            cv2.putText(frame, line, origin, font, scale, shadow, thickness + 2)
            cv2.putText(frame, line, origin, font, scale, color, thickness)

        return frame

    def draw_pitch_guides(self, frame):
        """Draw sample pitch guide lines on the display frame."""
        if not self.show_pitch_guides or not self.sample_mapping:
            return frame

        height, width = frame.shape[:2]
        pitch_min_freq = self.sample_mapping_config.get(
            "pitch_min_freq",
            DEFAULT_MIN_FREQ,
        )
        pitch_max_freq = self.sample_mapping_config.get(
            "pitch_max_freq",
            DEFAULT_MAX_FREQ,
        )
        pitch_guides = build_pitch_guides(
            self.pitch_guide_mode,
            pitch_min_freq,
            pitch_max_freq,
            root=self.pitch_guide_root,
            scale=self.pitch_guide_scale,
        )
        font = cv2.FONT_HERSHEY_SIMPLEX
        scale = 0.45
        line_color = (0, 210, 255)
        text_color = (255, 255, 255)
        shadow = (0, 0, 0)
        base_thickness = 1
        margin = 10

        for guide in pitch_guides:
            pitch_norm = guide["pitch_norm"]
            label = guide["label"]
            line_thickness = 2 if guide.get("is_root") else base_thickness
            display_y_norm = 1.0 - pitch_norm
            y = int(display_y_norm * (height - 1))
            text_size, _ = cv2.getTextSize(label, font, scale, base_thickness)
            text_x = max(margin, width - text_size[0] - margin)
            text_y = max(16, min(height - margin, y - 4))

            cv2.line(frame, (0, y), (width - 1, y), line_color, line_thickness)
            cv2.putText(
                frame,
                label,
                (text_x, text_y),
                font,
                scale,
                shadow,
                base_thickness + 2,
            )
            cv2.putText(
                frame,
                label,
                (text_x, text_y),
                font,
                scale,
                text_color,
                base_thickness,
            )

        return frame

    def start_settings_panel(self):
        """Create the prototype settings panel if requested."""
        if not self.show_settings_panel:
            return

        cv2.namedWindow(SETTINGS_PANEL_WINDOW)
        initial_min_midi = self.freq_setting_to_midi(
            "pitch_min_freq",
            DEFAULT_MIN_FREQ,
        )
        initial_max_midi = self.freq_setting_to_midi(
            "pitch_max_freq",
            DEFAULT_MAX_FREQ,
        )
        initial_min_midi, initial_max_midi = self.normalize_midi_range(
            initial_min_midi,
            initial_max_midi,
        )
        root_name = normalize_root(
            self.sample_mapping_config.get("pitch_root", self.pitch_guide_root)
        )
        scale_name = normalize_scale(
            self.sample_mapping_config.get("pitch_scale", self.pitch_guide_scale)
        )

        cv2.createTrackbar(
            "Pitch Min note",
            SETTINGS_PANEL_WINDOW,
            initial_min_midi - SETTINGS_MIDI_MIN,
            SETTINGS_MIDI_MAX - SETTINGS_MIDI_MIN,
            self.on_settings_trackbar,
        )
        cv2.createTrackbar(
            "Pitch Max note",
            SETTINGS_PANEL_WINDOW,
            initial_max_midi - SETTINGS_MIDI_MIN,
            SETTINGS_MIDI_MAX - SETTINGS_MIDI_MIN,
            self.on_settings_trackbar,
        )
        cv2.createTrackbar(
            "Root",
            SETTINGS_PANEL_WINDOW,
            self.index_or_default(NOTE_NAMES, root_name, "A"),
            len(NOTE_NAMES) - 1,
            self.on_settings_trackbar,
        )
        cv2.createTrackbar(
            "Scale",
            SETTINGS_PANEL_WINDOW,
            self.index_or_default(SCALE_NAMES, scale_name, "minor-pentatonic"),
            len(SCALE_NAMES) - 1,
            self.on_settings_trackbar,
        )
        cv2.createTrackbar(
            "Quantize",
            SETTINGS_PANEL_WINDOW,
            1 if self.sample_mapping_config.get("quantize_pitch", False) else 0,
            1,
            self.on_settings_trackbar,
        )
        cv2.createTrackbar(
            "Guide Mode",
            SETTINGS_PANEL_WINDOW,
            self.index_or_default(
                PITCH_GUIDE_MODE_NAMES,
                self.pitch_guide_mode,
                "simple",
            ),
            len(PITCH_GUIDE_MODE_NAMES) - 1,
            self.on_settings_trackbar,
        )
        self.settings_panel_started = True
        self.update_settings_from_panel()

    def on_settings_trackbar(self, value):
        """OpenCV trackbar callback placeholder."""
        return None

    def update_settings_from_panel(self):
        """Read settings panel values and apply them to sample and guide config."""
        if not self.show_settings_panel or not self.settings_panel_started:
            return

        try:
            min_midi = SETTINGS_MIDI_MIN + cv2.getTrackbarPos(
                "Pitch Min note",
                SETTINGS_PANEL_WINDOW,
            )
            max_midi = SETTINGS_MIDI_MIN + cv2.getTrackbarPos(
                "Pitch Max note",
                SETTINGS_PANEL_WINDOW,
            )
            root_index = cv2.getTrackbarPos("Root", SETTINGS_PANEL_WINDOW)
            scale_index = cv2.getTrackbarPos("Scale", SETTINGS_PANEL_WINDOW)
            quantize = cv2.getTrackbarPos("Quantize", SETTINGS_PANEL_WINDOW)
            guide_mode_index = cv2.getTrackbarPos("Guide Mode", SETTINGS_PANEL_WINDOW)
        except cv2.error:
            return

        min_midi, max_midi = self.normalize_midi_range(min_midi, max_midi)
        self.sync_trackbar("Pitch Min note", min_midi - SETTINGS_MIDI_MIN)
        self.sync_trackbar("Pitch Max note", max_midi - SETTINGS_MIDI_MIN)

        root_name = NOTE_NAMES[max(0, min(root_index, len(NOTE_NAMES) - 1))]
        scale_name = SCALE_NAMES[max(0, min(scale_index, len(SCALE_NAMES) - 1))]
        guide_mode = PITCH_GUIDE_MODE_NAMES[
            max(0, min(guide_mode_index, len(PITCH_GUIDE_MODE_NAMES) - 1))
        ]

        self.sample_mapping_config["pitch_min_freq"] = midi_to_freq(min_midi)
        self.sample_mapping_config["pitch_max_freq"] = midi_to_freq(max_midi)
        self.sample_mapping_config["pitch_root"] = root_name
        self.sample_mapping_config["pitch_scale"] = scale_name
        self.sample_mapping_config["quantize_pitch"] = bool(quantize)
        self.pitch_guide_root = root_name
        self.pitch_guide_scale = scale_name
        self.pitch_guide_mode = guide_mode
        self.sample_mapper.mapping_config = self.sample_mapping_config

    def draw_settings_overlay(self, frame):
        """Draw the current prototype settings on the preview frame."""
        if not self.show_settings_panel:
            return frame

        pitch_min_freq = self.sample_mapping_config.get(
            "pitch_min_freq",
            DEFAULT_MIN_FREQ,
        )
        pitch_max_freq = self.sample_mapping_config.get(
            "pitch_max_freq",
            DEFAULT_MAX_FREQ,
        )
        min_note = format_midi_note(round(freq_to_midi(pitch_min_freq)))
        max_note = format_midi_note(round(freq_to_midi(pitch_max_freq)))
        quantize_state = (
            "ON" if self.sample_mapping_config.get("quantize_pitch", False) else "OFF"
        )
        root = self.sample_mapping_config.get("pitch_root", self.pitch_guide_root)
        scale = self.sample_mapping_config.get("pitch_scale", self.pitch_guide_scale)
        text = (
            f"Settings: {root} {scale} | Quantize {quantize_state} | "
            f"Range {min_note} {pitch_min_freq:.0f}Hz - "
            f"{max_note} {pitch_max_freq:.0f}Hz | Guide {self.pitch_guide_mode}"
        )

        height, _ = frame.shape[:2]
        font = cv2.FONT_HERSHEY_SIMPLEX
        scale_value = 0.45
        color = (255, 255, 255)
        shadow = (0, 0, 0)
        thickness = 1
        origin = (12, max(20, height - 16))
        cv2.putText(frame, text, origin, font, scale_value, shadow, thickness + 2)
        cv2.putText(frame, text, origin, font, scale_value, color, thickness)
        return frame

    def freq_setting_to_midi(self, key, default_freq):
        """Return a clamped MIDI note for a frequency setting."""
        freq = self.sample_mapping_config.get(key, default_freq)
        try:
            if freq <= 0:
                raise ValueError
            midi_note = round(freq_to_midi(freq))
        except (TypeError, ValueError):
            midi_note = round(freq_to_midi(default_freq))

        return self.clamp_midi(midi_note)

    def normalize_midi_range(self, min_midi, max_midi):
        """Keep settings panel MIDI range valid and ordered."""
        min_midi = self.clamp_midi(min_midi)
        max_midi = self.clamp_midi(max_midi)
        if min_midi >= max_midi:
            if min_midi >= SETTINGS_MIDI_MAX:
                min_midi = SETTINGS_MIDI_MAX - 1
            max_midi = min_midi + 1
        return min_midi, max_midi

    def clamp_midi(self, midi_note):
        """Clamp a MIDI note to the prototype panel range."""
        return max(SETTINGS_MIDI_MIN, min(SETTINGS_MIDI_MAX, int(midi_note)))

    def sync_trackbar(self, name, value):
        """Set a trackbar position, ignoring panel-close races."""
        try:
            cv2.setTrackbarPos(name, SETTINGS_PANEL_WINDOW, value)
        except cv2.error:
            pass

    def index_or_default(self, options, value, default):
        """Return the index of a value in a tuple, falling back to a default."""
        try:
            return options.index(value)
        except ValueError:
            return options.index(default)

    def run(self):
        """Show camera frames with hand landmarks until q is pressed."""
        self.start()
        try:
            while True:
                frame = self.read()
                self.update_settings_from_panel()
                frame = self.draw_landmarks(frame)
                display_frame = cv2.flip(frame, 1)
                display_frame = self.draw_pitch_guides(display_frame)
                display_frame = self.draw_settings_overlay(display_frame)
                display_frame = self.draw_status_overlay(display_frame)
                display_frame = self.draw_hand_labels(display_frame)
                cv2.imshow(self.window_name, display_frame)

                if cv2.waitKey(1) & 0xFF == ord("q"):
                    break
        finally:
            self.stop()

    def stop(self):
        """Release MediaPipe, camera, and preview resources."""
        if self.landmarker is not None:
            self.landmarker.close()
            self.landmarker = None

        if self.capture is not None:
            self.capture.release()
            self.capture = None

        try:
            cv2.destroyWindow(self.window_name)
        except cv2.error:
            pass

        if self.settings_panel_started:
            try:
                cv2.destroyWindow(SETTINGS_PANEL_WINDOW)
            except cv2.error:
                pass
            self.settings_panel_started = False
