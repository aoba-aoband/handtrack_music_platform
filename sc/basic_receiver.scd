/*
Basic SuperCollider OSC receiver for platform control events.

This file should receive generic control events from the Python platform.
The neutral /hand/... events can be posted for inspection only.
The /sample/... mappings are example musical mappings layered on top of the
neutral /hand/... control events. They are not fixed platform rules.

Coordinate notes:
- /hand/0 is the first hand reported by MediaPipe, not a fixed right or left hand.
- Image y is normalized top-to-bottom: top is 0, bottom is 1.
*/

(
s.waitForBoot({
    ~debugHandEvents = false;
    ~debugSampleEvents = false;

    SynthDef(\basicOscProbe, { |out = 0, freq = 440, amp = 0.05|
        var sig;
        sig = SinOsc.ar(Lag.kr(freq, 0.08), 0, Lag.kr(amp, 0.08));
        Out.ar(out, sig ! 2);
    }).add;

    s.sync;

    ~basicReceiverSynth.notNil.if({
        ~basicReceiverSynth.free;
    });
    "creating probe synth".postln;
    ~basicReceiverSynth = Synth(\basicOscProbe);

    ~postControlEvent = { |msg, addr|
        var value;
        value = msg[1].asFloat;
        ~debugHandEvents.if({
            ["received", msg[0], value, "from", addr].postln;
        });
    };

    OSCdef(\handIndexX, { |msg, time, addr, recvPort|
        ~postControlEvent.(msg, addr);
    }, "/hand/0/index/x");

    OSCdef(\handIndexY, { |msg, time, addr, recvPort|
        ~postControlEvent.(msg, addr);
    }, "/hand/0/index/y");

    OSCdef(\handThumbX, { |msg, time, addr, recvPort|
        ~postControlEvent.(msg, addr);
    }, "/hand/0/thumb/x");

    OSCdef(\handThumbY, { |msg, time, addr, recvPort|
        ~postControlEvent.(msg, addr);
    }, "/hand/0/thumb/y");

    OSCdef(\handPinch, { |msg, time, addr, recvPort|
        ~postControlEvent.(msg, addr);
    }, "/hand/0/pinch");

    // Legacy sample probe value: kept for inspection, not Synth control.
    // Right hand index/y is inverted because image y has top = 0.
    OSCdef(\sampleRightIndexYInverted, { |msg, time, addr, recvPort|
        var value;
        value = msg[1].asFloat.clip(0, 1);
        ~debugSampleEvents.if({
            ["sample pitch norm legacy", value].postln;
        });
    }, "/sample/right/index/y_inverted");

    // Sample mapping only: Python computes the base pitch frequency.
    // Kept for inspection; Synth freq is controlled by final_freq below.
    OSCdef(\sampleRightPitchFreq, { |msg, time, addr, recvPort|
        var freq;
        freq = msg[1].asFloat.max(0);
        ~debugSampleEvents.if({
            ["sample pitch freq base", freq].postln;
        });
    }, "/sample/right/pitch/freq");

    // Sample mapping only: Python computes whether the octave gesture is active.
    // Kept for inspection; SuperCollider does not calculate pitch from it.
    OSCdef(\sampleRightPitchOctaveShift, { |msg, time, addr, recvPort|
        var value;
        value = msg[1].asFloat;
        ~debugSampleEvents.if({
            ["sample octave shift", value].postln;
        });
    }, "/sample/right/pitch/octave_shift");

    // Sample mapping only: Python computes the continuous pitch with octave.
    // Kept for inspection; Synth freq is controlled by final_freq below.
    OSCdef(\sampleRightPitchFreqWithOctave, { |msg, time, addr, recvPort|
        var freq;
        freq = msg[1].asFloat.max(0);
        ~debugSampleEvents.if({
            ["sample pitch freq with octave", freq].postln;
        });
    }, "/sample/right/pitch/freq_with_octave");

    // Sample mapping only: Python computes the quantized pitch candidate.
    // Kept for inspection; SuperCollider does not quantize pitch here.
    OSCdef(\sampleRightPitchQuantizedFreq, { |msg, time, addr, recvPort|
        var freq;
        freq = msg[1].asFloat.max(0);
        ~debugSampleEvents.if({
            ["sample pitch quantized freq", freq].postln;
        });
    }, "/sample/right/pitch/quantized_freq");

    // Sample mapping only: Python selects continuous or quantized final pitch.
    // SuperCollider uses the received final frequency directly for synthesis.
    OSCdef(\sampleRightPitchFinalFreq, { |msg, time, addr, recvPort|
        var freq;
        freq = msg[1].asFloat.max(0);
        ~basicReceiverSynth.set(\freq, freq);
        ~debugSampleEvents.if({
            ["sample pitch final freq", freq].postln;
        });
    }, "/sample/right/pitch/final_freq");

    // Sample mapping only: /sample/left/pinch -> amp.
    // Left hand pinch is used as an amplitude candidate in this example patch.
    // This confirms a sample patch mapping, not a platform-level volume rule.
    OSCdef(\sampleLeftPinch, { |msg, time, addr, recvPort|
        var value, amp;
        value = msg[1].asFloat.clip(0, 1);
        amp = value.linlin(0, 1, 0.02, 0.25);
        ~basicReceiverSynth.set(\amp, amp);
        ~debugSampleEvents.if({
            ["sample amp", value, amp].postln;
        });
    }, "/sample/left/pinch");

    "Listening for generic hand control events on port 57120".postln;
    "Listening for sample mapping events that control the probe synth.".postln;
    "Set ~debugHandEvents or ~debugSampleEvents to true for per-event logs.".postln;
});
)
