# SuperCollider Probe Mapping

`sc/basic_receiver.scd` is a connection probe, not a fixed instrument design.
It receives neutral hand `ControlEvent` messages and can post the
`/hand/0/...` values to the SuperCollider Post window for inspection. Those
`/hand/...` events do not control the Synth's `freq` or `amp`.

Per-event logging is disabled by default. Set `~debugHandEvents = true` to
show `/hand/...` logs, or `~debugSampleEvents = true` to show sample `freq` /
`amp` logs while keeping the same Synth control behavior.

The simple SuperCollider Synth is controlled only by sample musical mapping
events:

- `/sample/right/pitch/freq` -> `freq`
- `/sample/left/pinch` -> `amp`

This setup proves that the path from MediaPipe Hands to SuperCollider works:

```text
camera -> MediaPipe -> HandFeatures -> ControlEvent -> OSC -> SuperCollider
```

`/hand/...` events are neutral platform data. `/sample/...` events are an
example music mapping layered on top of that data. This project is a platform
for turning hand landmark information into music control streams, not a single
fixed theremin design. A later patch may choose right-hand Y for pitch,
left-hand pinch for amplitude, a Max for Live parameter, an Ableton Live macro,
or something else entirely.

`--sample-mapping` adds one such example patch stream:

- `/sample/right/index/y`
- `/sample/right/index/y_inverted`
- `/sample/right/pitch/norm`
- `/sample/right/pitch/freq`
- `/sample/left/pinch`

In `sc/basic_receiver.scd`, `/sample/right/pitch/freq` is assigned directly to
`freq`, and `/sample/left/pinch` is temporarily assigned to `amp`. This is a
sample musical mapping, not a fixed platform contract.
The sample mapping uses a short handedness debounce so brief Left/Right
misclassifications do not immediately swap the sample roles.

## Pitch Mapping Is Temporary

The sample mapper now keeps `/sample/right/index/y_inverted` as a legacy
normalized `0..1` value and also emits `/sample/right/pitch/norm` plus
`/sample/right/pitch/freq`. For now, Python maps pitch norm to frequency with a
simple 220 Hz to 880 Hz exponential range. This matches the earlier
SuperCollider-side probe behavior, but it moves the first pitch conversion step
into Python.

The longer-term direction is still to keep `features.py` limited to neutral
hand features while `mapping.py` or a future `src/music/` layer owns key,
scale, range, quantization, and normalized-to-pitch conversion. The preview
guide lines can then read the same pitch mapping logic as the outgoing events,
instead of duplicating `0..1 -> freq` math separately from SuperCollider.

Possible future event shapes:

- `/sample/right/pitch/norm`
- `/sample/right/pitch/freq`
- `/sample/right/pitch/midi`
- `/sample/right/pitch/degree`
- `/sample/right/pitch/quantized`

In that design, SuperCollider would lean toward synthesis from received `freq`
values or MIDI-derived values, while Python owns the mapping that also informs
the visual guides. The trade-off is similar to smoothing: normalized values are
useful, but final musical meaning should have one source of truth.

## Amp Mapping Is Temporary

The current SuperCollider probe maps `/sample/left/pinch` to `amp` with
`value.linlin(0, 1, 0.02, 0.25)`. Since the lower bound is `0.02`,
`pinch = 0` still leaves some sound. That is convenient for a connection
probe, but it is not a fixed instrument behavior.

When this becomes more instrument-like, left-hand pinch should be revisited.
Possible options:

- Fully mute near `pinch = 0`.
- Add a `gate` or ASR envelope.
- Use a dB or exponential curve instead of linear amplitude.
- Adjust the maximum amp.
- Use different lag times for `freq` and `amp`.
- Use pinch for filter cutoff, reverb send, delay send, or another control
  instead of volume.

## Smoothing and Latency

The current `basicOscProbe` Synth uses `Lag.kr(..., 0.08)` for both `freq` and
`amp`. This is temporary smoothing for abrupt OSC changes and MediaPipe-derived
jitter. It is also a likely thing to check if the SuperCollider probe feels a
little slower in pitch response than an earlier Python-only sound test.

For connection testing, `0.08` seconds is intentionally safe. For performance,
it may be too slow. Future comparisons worth trying:

- Lower `freq` lag from `0.08` to about `0.02` or `0.03`.
- Let `amp` stay slightly smoother than `freq` if that feels better.
- Decide how to split smoothing between SC-side `Lag.kr` / `VarLag.kr` and
  Python-side filters such as a One Euro Filter.
- Balance tracking responsiveness against reduced jitter and stepping.

## Tracking Dropout TODO

When the hand moves quickly, MediaPipe can briefly lose the hand. When it
detects the hand again, the new coordinates may jump far from the previous
frame, which can feel like a control-value warp and can produce unnatural
texture in the SuperCollider sound. This does not mean the OSC connection or
probe failed; it is a tracking dropout / reacquisition problem for the
instrument phase.

Possible future handling:

- Hold the last value during short dropouts.
- Close `gate` or `amp` after a short lost-hand timeout.
- Fade in after reacquisition.
- Treat very large coordinate jumps as outliers.
- Try a slew limiter or One Euro Filter.
- Use tracking confidence or presence confidence when deciding whether to
  accept a control value.

## Hand Indexes Are Not Roles

`/hand/0` and `/hand/1` are the first and second hands returned by MediaPipe in
the current frame, then numbered by Python. They are not fixed right-hand or
left-hand IDs. Mapping `/hand/0` directly to pitch and `/hand/1` directly to
amplitude can feel unstable if detection order changes, one hand disappears,
or MediaPipe redetects the scene.

`/sample/right/...` and `/sample/left/...` are sample mapping events built from
MediaPipe `handedness` labels. The current `--sample-mapping` mode tries to
create Right-hand and Left-hand sample roles, but its debounce is tracked per
`hand_index`, so it does not fully solve cases where `hand 0` and `hand 1`
swap order.

For a real instrument mapping, consider adding a stable role or identity layer
before routing controls to sound parameters. For example: `stable_right_hand`,
`stable_left_hand`, `role_id`, or a hand identity tracker.

## Two-Hand Debug TODO

The Python side can emit neutral events for more than one detected hand. For a
second hand, that includes `/hand/1/index/x`, `/hand/1/index/y`,
`/hand/1/thumb/x`, `/hand/1/thumb/y`, and `/hand/1/pinch`. At the moment,
`sc/basic_receiver.scd` only posts the `/hand/0/...` neutral events.

For future two-hand observation, either add explicit Post display handlers for
the `/hand/1/...` addresses or make a generic OSC logger for the `/hand/...`
event family. This is a debugging aid, not a change to the musical mapping
contract.

## Important Notes

- `/hand/0` means the first detected hand in the current MediaPipe result. It
  is not guaranteed to be the right hand or the left hand.
- MediaPipe `handedness` labels are currently for inspection. Because the
  preview is mirrored while feature values come from the original detection
  frame, confirm how `Left` and `Right` appear in your setup before using them
  for routing.
- Image coordinates are normalized. `y = 0` is the top of the image, and
  `y = 1` is the bottom.
- The `hands` preview is mirrored for display, but the current feature values
  are based on MediaPipe's original detection frame.
- No pitch inversion, scale quantization, handedness-fixed routing, or sound
  design is implemented in this probe.

Run the probe with:

```powershell
python main.py hands --show-events --send-osc
```

Run the handedness-based sample mapping with:

```powershell
python main.py hands --show-events --sample-mapping --send-osc
```
