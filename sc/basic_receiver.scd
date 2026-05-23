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

    ~probeDefaults = (
        freqLag: 0.08,
        ampLag: 0.08,
        portamentoOn: 0,
        portamentoTime: 0.15,
        softClipOn: 0,
        softClipDrive: 2.0,
        softClipMix: 1.0,
        outputLevel: 0.7,
        ampMin: 0.02,
        ampMax: 0.25
    );
    ~probeParams = ~probeDefaults.copy;
    ~probeSynthParamKeys = [
        \freqLag,
        \ampLag,
        \portamentoOn,
        \portamentoTime,
        \softClipOn,
        \softClipDrive,
        \softClipMix,
        \outputLevel
    ];

    SynthDef(\basicOscProbe, { |out = 0, freq = 440, amp = 0.05,
        freqLag = 0.08, ampLag = 0.08,
        portamentoOn = 0, portamentoTime = 0.15,
        softClipOn = 0, softClipDrive = 2.0, softClipMix = 1.0,
        outputLevel = 0.7|

        var freqFollowTime, followedFreq, followedAmp;
        var dry, clipped, shaped, sig;

        freqFollowTime = Select.kr(
            portamentoOn.clip(0, 1),
            [freqLag.max(0), portamentoTime.max(0)]
        );
        followedFreq = Lag.kr(freq.max(20), freqFollowTime);
        followedAmp = Lag.kr(amp.max(0), ampLag.max(0));

        dry = SinOsc.ar(followedFreq) * followedAmp;
        clipped = (dry * softClipDrive.max(1)).tanh;
        shaped = SelectX.ar(
            softClipOn.clip(0, 1) * softClipMix.clip(0, 1),
            [dry, clipped]
        );
        sig = shaped * outputLevel.clip(0, 1);
        Out.ar(out, sig ! 2);
    }).add;

    s.sync;

    ~basicReceiverSynth.notNil.if({
        ~basicReceiverSynth.free;
    });
    "creating probe synth".postln;
    ~basicReceiverSynth = Synth(\basicOscProbe, [
        \freqLag, ~probeParams[\freqLag],
        \ampLag, ~probeParams[\ampLag],
        \portamentoOn, ~probeParams[\portamentoOn],
        \portamentoTime, ~probeParams[\portamentoTime],
        \softClipOn, ~probeParams[\softClipOn],
        \softClipDrive, ~probeParams[\softClipDrive],
        \softClipMix, ~probeParams[\softClipMix],
        \outputLevel, ~probeParams[\outputLevel]
    ]);

    ~setProbeParam = { |key, value|
        ~probeParams[key] = value;
        (~basicReceiverSynth.notNil and: {
            ~probeSynthParamKeys.includes(key)
        }).if({
            ~basicReceiverSynth.set(key, value);
        });
    };

    ~resetProbeParams = {
        ~probeDefaults.keysValuesDo({ |key, value|
            ~setProbeParam.(key, value);
        });
    };

    {
        ~probeWindow.notNil.if({
            ~probeWindow.close;
        });

        ~probeWindow = Window("Probe Synth Controls", Rect(100, 100, 420, 430));
        ~probeControls = ();

        ~makeProbeSlider = { |label, key, minValue, maxValue, step = 0|
            var slider;
            slider = EZSlider(
                ~probeWindow,
                390@24,
                label,
                ControlSpec(minValue, maxValue, \lin, step, ~probeParams[key]),
                { |view| ~setProbeParam.(key, view.value); },
                ~probeParams[key]
            );
            ~probeControls[key] = slider;
            slider.view;
        };

        ~makeProbeToggle = { |label, key|
            var button;
            button = Button()
                .states_([
                    [label ++ ": OFF", Color.black, Color.gray(0.85)],
                    [label ++ ": ON", Color.white, Color(0.2, 0.45, 0.8)]
                ])
                .value_(~probeParams[key].asInteger)
                .action_({ |view| ~setProbeParam.(key, view.value); });
            ~probeControls[key] = button;
            button;
        };

        ~probeWindow.layout = VLayout(
            StaticText().string_("Sample mapping probe synth controls"),
            ~makeProbeSlider.("freqLag", \freqLag, 0.0, 0.3, 0.001),
            ~makeProbeSlider.("ampLag", \ampLag, 0.0, 0.3, 0.001),
            ~makeProbeToggle.("portamento", \portamentoOn),
            ~makeProbeSlider.("portamentoTime", \portamentoTime, 0.0, 1.0, 0.001),
            ~makeProbeToggle.("softClip", \softClipOn),
            ~makeProbeSlider.("softClipDrive", \softClipDrive, 1.0, 20.0, 0.01),
            ~makeProbeSlider.("softClipMix", \softClipMix, 0.0, 1.0, 0.001),
            ~makeProbeSlider.("outputLevel", \outputLevel, 0.0, 1.0, 0.001),
            ~makeProbeSlider.("ampMin", \ampMin, 0.0, 0.2, 0.001),
            ~makeProbeSlider.("ampMax", \ampMax, 0.01, 0.8, 0.001),
            Button()
                .states_([["Reset defaults", Color.black, Color.gray(0.85)]])
                .action_({
                    ~resetProbeParams.();
                    ~probeControls.keysValuesDo({ |key, control|
                        control.valueAction_(~probeParams[key]);
                    });
                })
        );
        ~probeWindow.front;
    }.defer;

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
        var value, amp, ampMin, ampMax;
        value = msg[1].asFloat.clip(0, 1);
        ampMin = ~probeParams[\ampMin].min(~probeParams[\ampMax]);
        ampMax = ~probeParams[\ampMin].max(~probeParams[\ampMax]);
        amp = value.linlin(0, 1, ampMin, ampMax);
        ~basicReceiverSynth.set(\amp, amp);
        ~debugSampleEvents.if({
            ["sample amp", value, amp].postln;
        });
    }, "/sample/left/pinch");

    "Listening for generic hand control events on port 57120".postln;
    "Listening for sample mapping events that control the probe synth.".postln;
    "Probe synth controls are available in the SuperCollider UI window.".postln;
    "Set ~debugHandEvents or ~debugSampleEvents to true for per-event logs.".postln;
});
)
