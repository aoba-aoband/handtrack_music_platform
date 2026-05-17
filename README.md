# Handtrack Music Platform

This project is a small platform for turning hand landmark data into generic
control events. It is not designed as a fixed theremin patch. The current goal
is to keep hand tracking, neutral features, event mapping, and output adapters
separate so SuperCollider, Ableton Live, Max for Live, or other systems can
interpret the same control stream differently.

## Current Status

- Git tracking is initialized.
- Python can send OSC to SuperCollider.
- OpenCV can display a webcam preview and quit with `q`.
- MediaPipe Hands can draw hand landmarks on the camera preview.
- Hand landmarks can be converted into neutral `HandFeatures`.
- `HandFeatures` can be mapped to generic `ControlEvent` addresses such as:
  - `/hand/0/index/x`
  - `/hand/0/index/y`
  - `/hand/0/middle/x`
  - `/hand/0/middle/y`
  - `/hand/0/thumb/x`
  - `/hand/0/thumb/y`
  - `/hand/0/pinch`
- `python main.py hands --send-osc` can send generated hand `ControlEvent`
  values to SuperCollider.
- Python generates sample pitch events including `/sample/right/pitch/norm`,
  `/sample/right/pitch/freq`, `/sample/right/pitch/octave_shift`, and
  `/sample/right/pitch/freq_with_octave`.
- The sample middle-finger octave gesture is minimally implemented: when
  `middle_tip_y < index_tip_y`, `octave_shift` becomes `1.0` and
  `freq_with_octave` becomes the base pitch frequency doubled.
- Python also emits `/sample/right/pitch/final_freq`. Without
  `--quantize-pitch`, `final_freq` matches `freq_with_octave`; with
  `--quantize-pitch`, it uses `quantized_freq`.
- The SuperCollider probe uses `/sample/right/pitch/final_freq` directly for
  the confirmation Synth's pitch, so `--quantize-pitch` can switch the audible
  probe between continuous and scale-snapped pitch.
- A minimal sample pitch guide-line overlay is available in the camera preview.
  It supports `simple`, `chromatic`, and `scale` display modes from the same
  Python pitch range settings used by the sample mapper.
- Scale guide display can use a root note and scale to show only matching
  guide notes. Pitch quantization is now minimally implemented for the sample
  probe via `--quantize-pitch`.

## Run Commands

OSC connectivity smoke test:

```powershell
python main.py
```

Raw camera smoke test:

```powershell
python main.py camera
```

MediaPipe Hands landmark preview:

```powershell
python main.py hands
```

Show neutral feature values on the preview:

```powershell
python main.py hands --show-features
```

Show generated generic `ControlEvent` values on the preview:

```powershell
python main.py hands --show-events
```

Send generated hand `ControlEvent` values over OSC:

```powershell
python main.py hands --show-events --send-osc
```

Try the handedness-based sample musical mapping with continuous pitch:

```powershell
python main.py hands --show-events --sample-mapping --send-osc
```

Try the sample mapping with quantized pitch:

```powershell
python main.py hands --show-events --sample-mapping --send-osc --quantize-pitch --pitch-root A --pitch-scale minor-pentatonic
```

Try quantized pitch with matching scale guide lines:

```powershell
python main.py hands --show-events --sample-mapping --send-osc --quantize-pitch --pitch-root A --pitch-scale minor-pentatonic --show-pitch-guides --pitch-guide-mode scale --pitch-guide-root A --pitch-guide-scale minor-pentatonic
```

Show simple sample pitch guide lines on the preview:

```powershell
python main.py hands --sample-mapping --show-pitch-guides
```

Show chromatic guide lines and emphasize the root pitch class:

```powershell
python main.py hands --sample-mapping --show-pitch-guides --pitch-guide-mode chromatic --pitch-guide-root A
```

Show A minor pentatonic guide lines:

```powershell
python main.py hands --sample-mapping --show-pitch-guides --pitch-guide-mode scale --pitch-guide-root A --pitch-guide-scale minor-pentatonic
```

Show C major guide lines:

```powershell
python main.py hands --sample-mapping --show-pitch-guides --pitch-guide-mode scale --pitch-guide-root C --pitch-guide-scale major
```

Show sample pitch events and guide lines together:

```powershell
python main.py hands --show-events --sample-mapping --show-pitch-guides
```

Override the sample pitch range at startup:

```powershell
python main.py hands --sample-mapping --show-pitch-guides --pitch-min 110 --pitch-max 440
```

The `--pitch-min` and `--pitch-max` options also update the guide-line Hz
labels.

Use another camera:

```powershell
python main.py hands --camera-index 1
```

## SuperCollider Probe

Evaluate `sc/basic_receiver.scd` in SuperCollider before running a Python OSC
test. The receiver listens on `127.0.0.1:57120`, matching `config.py`.

The current SuperCollider receiver treats `/hand/...` as neutral
`ControlEvent` data for inspection. The `/hand/0/...` handlers can post
received values to the SuperCollider Post window when debugging is enabled, but
they do not control the probe Synth's `freq` or `amp`.

Per-event Post window logging is off by default so sound checks stay readable.
Set `~debugHandEvents = true` for `/hand/...` logs or
`~debugSampleEvents = true` for sample `freq` / `amp` logs.

The temporary probe Synth is controlled only by the sample musical mapping
events:

- `/sample/right/pitch/final_freq` to `freq`
- `/sample/left/pinch` to `amp`

`/sample/right/pitch/freq` is still received as a base-pitch value for
inspection. `/sample/right/pitch/octave_shift`,
`/sample/right/pitch/freq_with_octave`, and
`/sample/right/pitch/quantized_freq` can be posted for debugging.
SuperCollider does not calculate octave shifts, scale, key, or quantization;
it uses the final frequency candidate sent by Python.

This sample uses MediaPipe `handedness`, but it is still an example patch, not
a platform rule. The sample mapping debounces handedness labels for a few
frames so a single-frame Left/Right misclassification is less likely to swap
the sample pitch and amplitude roles.

This project is a platform for converting hand landmark information into music
control streams, not a single fixed theremin design. Future musical mappings
should be treated as configurable patches or examples.

Future debug TODO: the Python side can generate neutral events for multiple
hands, including `/hand/1/index/x`, `/hand/1/index/y`, `/hand/1/thumb/x`,
`/hand/1/thumb/y`, and `/hand/1/pinch`. The current
`sc/basic_receiver.scd` probe only posts the `/hand/0/...` neutral events.
When debugging two-hand behavior, either add matching Post display handlers for
`/hand/1/...` or consider a generic OSC logger for the `/hand/...` event family.

### Smoothing and Portamento Notes

The current `basicOscProbe` Synth in `sc/basic_receiver.scd` applies
`Lag.kr(..., 0.08)` to both `freq` and `amp`. This is a temporary connection
probe value, not a fixed instrument specification. Depending on the piece,
ensemble context, and playing style, the best feel may be fast tracking,
deliberately delayed smooth motion, or something in between.

It is useful to separate two related ideas:

- Smoothing reduces MediaPipe-derived jitter and tiny control-value wobble.
- Portamento defines the musical movement between pitch targets.

The current `Lag.kr` value does a little of both. That is fine for a probe, but
a playable instrument should expose these choices as adjustable parameters.
Future control surfaces could include a UI panel, OpenCV overlay controls, MIDI
CC, OSC settings messages, config values, or CLI startup options.

Future settings candidates:

- `freq_smoothing_time`
- `amp_smoothing_time`
- `portamento_time`
- `portamento_mode`
- `quantized_pitch_glide`
- `snap_strength`
- Hysteresis / deadband.

Implementation direction: Python should decide pitch, scale, quantization, and
`final_freq`. SuperCollider should decide how the Synth follows and sounds that
received `final_freq`. Those follow/response values should eventually be
changeable at runtime, for example as Synth arguments or OSC settings, rather
than being permanently embedded as fixed `SynthDef` constants.

## Coordinate Notes

- `/hand/0` means the first hand reported by MediaPipe in the current frame.
  It is not guaranteed to be the right hand or the left hand.
- MediaPipe also reports `handedness` labels such as `Left` and `Right`.
  These are currently displayed for inspection with `--show-features` or
  `--show-events`, but they are not yet used for fixed right-hand or left-hand
  musical routing.
- MediaPipe image coordinates are normalized. `x` and `y` are roughly `0..1`.
- Image `y` is top-to-bottom: the top of the image is `0`, and the bottom is
  `1`. Raising a hand generally makes `index_tip_y` smaller.
- The camera preview in `hands` mode is mirrored for easier interaction, but
  the extracted feature values remain based on the original detection frame.
  Handedness can be confusing when comparing camera input, mirrored display,
  and user perspective, so it should be verified before using it for a musical
  mapping.

## Hand Index, Handedness, and Roles

`/hand/0` and `/hand/1` are detection indexes, not stable right-hand or
left-hand identities. `/hand/0` is the first hand returned by MediaPipe for the
current frame, numbered by the Python feature/event layer. If a patch uses
`/hand/0` directly for pitch and `/hand/1` directly for amplitude, those roles
can wobble when MediaPipe changes detection order, loses a hand, or redetects
hands.

The `/sample/right/...` and `/sample/left/...` event streams are different:
they are sample-only musical events built from MediaPipe `handedness` labels.
The current `--sample-mapping` mode aims for Right-hand and Left-hand sample
roles, but its stabilization is only a debounce per `hand_index`. That helps
with brief handedness label flicker, but it is not a complete solution when
the order of `hand 0` and `hand 1` itself swaps.

For a more instrument-like mapping, add a role/identity layer before assigning
musical meaning. Possible future names include `stable_right_hand`,
`stable_left_hand`, `role_id`, or a hand identity tracker. That layer should
own the question "which physical hand has this musical role?" instead of
putting that responsibility on `/hand/0` or `/hand/1`.

## Design Boundary

The Python side currently produces neutral control data:

```text
MediaPipe Hands -> HandFeatures -> ControlEvent -> output adapter
```

Musical interpretation belongs after this boundary. For example, right-hand Y
to pitch or left-hand pinch to amplitude should be implemented as a patch,
configuration, or example mapping, not as a fixed platform rule.

## Future Pitch Mapping Notes

The current sample mapper keeps `/sample/right/index/y_inverted` as a
normalized `0..1` value and also emits `/sample/right/pitch/norm`,
`/sample/right/pitch/freq`, `/sample/right/pitch/octave_shift`, and
`/sample/right/pitch/freq_with_octave`. For now, Python maps pitch norm to a
base frequency with a configurable exponential range, then applies the sample
middle-finger octave gesture to produce `freq_with_octave`. This is a working
sample mapping, not a final pitch design.

The current order is roughly:

```text
pitch norm -> base freq -> octave shift -> freq_with_octave
```

When scale, key, and quantization are introduced, this order should be
revisited. Possible future orders include:

- `norm -> scale/key quantization -> octave shift -> final freq`
- `norm -> octave shift -> quantization -> final freq`

The camera guide-line overlay now has `simple`, `chromatic`, and `scale`
display modes. `simple` draws evenly spaced horizontal lines for
`pitch_norm = 0.0, 0.25, 0.5, 0.75, 1.0`. `chromatic` draws semitone guide
lines across the active pitch range and emphasizes the configured root pitch
class. `scale` draws only the semitone guide lines that belong to the selected
root and scale. These guide modes are visual only; they do not quantize
`/sample/right/pitch/freq` or `/sample/right/pitch/freq_with_octave`.
`--quantize-pitch` switches `/sample/right/pitch/final_freq` from continuous
`freq_with_octave` to scale-snapped `quantized_freq`, and the current
SuperCollider probe plays `final_freq`.

For a fuller instrument design, keeping key, scale, range, quantization, and
normalized-to-pitch conversion in Python should let the camera preview guide
lines and the emitted `pitch`, `freq`, or `midi` values share the same logic.
If SuperCollider owns its own separate `0..1 -> freq` conversion, Python
guide-line calculation and SC pitch conversion can drift over time.

Normalized pitch-like values are still useful, but final musical pitch mapping
is a candidate for `mapping.py` or a future `src/music/` layer rather than
`features.py`. Current and possible future event names include:

- `/sample/right/pitch/norm`
- `/sample/right/pitch/freq`
- `/sample/right/pitch/octave_shift`
- `/sample/right/pitch/freq_with_octave`
- `/sample/right/pitch/midi`
- `/sample/right/pitch/degree`
- `/sample/right/pitch/quantized`

Possible future structure:

- `features.py` keeps only neutral hand-derived features.
- `src/pitch.py` keeps shared pitch helpers such as note names, pitch classes,
  scale definitions, frequency/MIDI conversion, and guide-line generation.
- `mapping.py` or `src/music/` handles key, scale, range, quantization, and
  pitch conversion.
- Camera guide-line drawing reads the same pitch mapping logic and uses the
  same final pitch information that the sound output uses.
- SuperCollider focuses on synthesis from received `freq` values or
  MIDI-derived values.

## Future Scale / Key / Quantization Notes

Before adding scale, key, or quantization, the pitch terms should stay clear:

- `pitch_norm`: a continuous `0.0..1.0` pitch candidate derived from neutral
  hand data such as right-hand `index_tip_y`.
- `pitch/freq`: a continuous base frequency converted from `pitch_norm`.
- `octave_shift`: an octave-change candidate from a sample gesture such as
  the middle finger moving above the index finger.
- `freq_with_octave`: the continuous frequency candidate after applying
  `octave_shift` to the base frequency.
- `final_freq`: the current frequency value used by the SuperCollider probe;
  continuous unless `--quantize-pitch` selects `quantized_freq`.
- Quantized pitch: a pitch candidate after snapping or rounding to a selected
  scale and key.

The order for scale, key, and quantization is still undecided. Candidate
orders include:

- A: `pitch_norm -> scale/key quantization -> octave shift -> final freq`
- B: `pitch_norm -> octave shift -> scale/key quantization -> final freq`
- C: `pitch_norm -> continuous freq` and `pitch_norm -> quantized freq`, with
  both streams emitted for comparison or patch choice.

A likely important direction is that Python should be the single source of
truth for sample pitch mapping. The guide-line overlay and OSC output should
read the same pitch mapping logic. If SuperCollider has a separate scale/key
conversion, the preview guide lines and the audible pitch can drift apart.

The current guide-line code can already display root and scale information,
and Python can emit and play quantized pitch candidates through `final_freq`.
The next pitch-design steps include unifying guide settings with quantization
settings, tuning snap strength, adding hysteresis, deciding how portamento
should behave around snapped notes, and designing a scale/key UI.

Possible future pitch events:

- `/sample/right/pitch/midi`
- `/sample/right/pitch/degree`
- `/sample/right/pitch/quantized_norm`
- `/sample/right/pitch/quantized_freq`
- `/sample/right/pitch/final_freq`

The current guide lines can be evenly spaced, chromatic, or scale-filtered.
They can already match the notes that the quantizer can choose when the same
root and scale are used. The remaining design work is making that relationship
ergonomic and explicit so the active pitch range, key, scale, octave-shift
behavior, guide display, and final emitted pitch value stay aligned.

## Future Settings UI Notes

The current sample pitch range can be changed without editing `mapping.py`.
`config.py` defines `SAMPLE_MAPPING` values such as `pitch_min_freq` and
`pitch_max_freq`, and the hands smoke test can override them at startup with
CLI arguments:

```powershell
python main.py hands --show-events --sample-mapping --send-osc --pitch-min 110 --pitch-max 440
```

The camera guide display can also be adjusted from the CLI with
`--pitch-guide-mode`, `--pitch-guide-root`, and `--pitch-guide-scale`.

This is an intermediate step toward a more playable settings workflow. In the
future, performance-facing settings should be adjustable without direct code
edits. The exact UI shape is still open. Possible directions include:

- Simple controls overlaid on the OpenCV preview.
- A separate settings panel window.
- A Web UI.
- MIDI controller or MIDI CC control.
- Hot reloading from a settings file.

Settings that may eventually belong in that layer include:

- Pitch range.
- Pitch guide mode.
- Root note.
- Scale.
- Quantization on/off.
- Smoothing amount.
- Portamento time / mode.
- Quantized pitch glide.
- Snap strength.
- Hysteresis / deadband.
- Gesture mappings.
- Amp range.

This is only a planning note for now. The current implementation should remain
focused on configurable sample mapping, not a fixed theremin design or a final
settings UI.

## Future Gesture Mapping Notes

The middle-finger octave gesture is now minimally implemented as a sample
mapping. When the middle finger moves higher than the index finger, Python
emits an octave candidate. MediaPipe image coordinates use `y = 0` at the top
of the image and `y = 1` at the bottom, so the current raw condition is
`middle_tip_y < index_tip_y`.

`features.py` now exposes neutral middle-finger features, `middle_tip_x` and
`middle_tip_y`. Those values remain landmark-derived features, not fixed
musical roles.

Current sample events include:

- `/sample/right/pitch/octave_shift`
- `/sample/right/pitch/freq_with_octave`

`octave_shift` is `1.0` when `middle_tip_y < index_tip_y`, otherwise `0.0`.
`freq_with_octave` currently doubles the base `/sample/right/pitch/freq` when
`octave_shift` is active. The SuperCollider probe now uses
`/sample/right/pitch/final_freq` for the confirmation Synth's pitch, so the
same octave behavior is audible when `final_freq` is continuous.

This is not a fixed platform rule. It should still be treated as a sample
musical mapping candidate. Future refinements include false-trigger
protection, hysteresis, a gesture threshold or margin, smoothing/debounce, and
integration with scale, key, quantization, and guide-line logic.

Any octave gesture design should stay compatible with future scale, key,
quantization, and camera guide-line logic.

## Future Amp Mapping Notes

The current `sc/basic_receiver.scd` probe maps `/sample/left/pinch` to `amp`
with `value.linlin(0, 1, 0.02, 0.25)`. Because the minimum amp is `0.02`,
`pinch = 0` does not become complete silence. That is useful for connection
checking because the synth remains audible, but it is not a fixed volume
control specification.

For a fuller instrument design, revisit what left-hand pinch should mean.
Possible directions:

- Mute completely near `pinch = 0`.
- Add a `gate` or ASR envelope instead of treating pinch as raw continuous amp.
- Use a dB or exponential loudness curve instead of a linear `amp` curve.
- Tune the maximum amp separately from the gesture range.
- Give `freq` and `amp` separate lag times.
- Keep open the possibility that pinch controls filter cutoff, reverb send,
  delay send, or another expressive parameter instead of volume.

## Future Tracking Dropout Notes

When the hand moves quickly, MediaPipe can briefly lose tracking. On
reacquisition, landmark coordinates may jump far from the previous values,
which can look like a control-value warp. That jump can create unnatural
texture in the SuperCollider sound. This is not a connection-check failure; it
is a tracking dropout / reacquisition issue to handle during the instrument
design phase.

Possible future responses:

- Hold the last value while a hand is briefly lost.
- Close `gate` or `amp` after the hand has been lost for a short timeout.
- Fade in after reacquisition.
- Ignore coordinate jumps that are too large as outliers.
- Consider a slew limiter or One Euro Filter.
- Decide whether to accept control values based on tracking confidence or
  presence confidence.
