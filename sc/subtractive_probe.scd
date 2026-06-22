/*
Subtractive synthesis probe for the handtrack_music_platform sample mapping.

This is intentionally separate from basic_receiver.scd. Python decides pitch,
quantization, and final_freq; this file decides how that received frequency is
followed, voiced, filtered, and brought into a performance.
*/

(
var subtractiveProbeInstance;

// A probe owns the sample-mapping OSC handlers while it is active.  Evaluating
// either probe first runs the previous probe's cleanup, preventing double sound.
~activeProbeCleanup.notNil.if({
    ~activeProbeCleanup.();
});
~activeProbeCleanup = nil;
// Invalidate a basic-receiver evaluation that may still be waiting for boot.
~basicProbeInstance = (~basicProbeInstance ? 0) + 1;
subtractiveProbeInstance = (~subtractiveProbeInstance ? 0) + 1;
~subtractiveProbeInstance = subtractiveProbeInstance;

s.waitForBoot({
    (~subtractiveProbeInstance == subtractiveProbeInstance).if({
        ~subtractiveDebugEvents = false;

        ~subtractiveDefaults = (
            freqLag: 0.08,
            ampAttack: 0.05,
            ampRelease: 0.12,
            performanceGate: 0,
            crescendoTime: 1.5,
            decrescendoTime: 1.5,
            outputLevel: 0.35,
            ampMin: 0.01,
            ampMax: 0.16,
            osc1Wave: 0,
            osc2On: 0,
            osc2Wave: 0,
            osc2Octave: 0,
            osc2DetuneCents: 0,
            oscMix: 0.0,
            pulseWidth: 0.5,
            subMix: 0.0,
            noiseMix: 0.0,
            filterOn: 1,
            filterCutoff: 2400,
            filterRq: 0.7,
            filterMix: 1.0,
            filterLag: 0.08,
            keyTracking: 0.35,
            monitorOn: 1,
            monitorRate: 8
        );
        ~subtractiveParams = ~subtractiveDefaults.copy;
        ~subtractiveSynthParamKeys = [
            \freqLag,
            \ampAttack,
            \ampRelease,
            \performanceGate,
            \crescendoTime,
            \decrescendoTime,
            \outputLevel,
            \osc1Wave,
            \osc2On,
            \osc2Wave,
            \osc2Octave,
            \osc2DetuneCents,
            \oscMix,
            \pulseWidth,
            \subMix,
            \noiseMix,
            \filterOn,
            \filterCutoff,
            \filterRq,
            \filterMix,
            \filterLag,
            \keyTracking,
            \monitorOn,
            \monitorRate
        ];
        ~subtractiveMonitor = (
            targetFreq: 440.0,
            targetAmp: 0.05,
            followedFreq: 440.0,
            followedAmp: 0.05,
            performanceEnv: 0.0,
            effectiveCutoff: 2400.0
        );

        SynthDef(\subtractiveProbe, { |out = 0, freq = 440, amp = 0.05,
            freqLag = 0.08, ampAttack = 0.05, ampRelease = 0.12,
            performanceGate = 0, crescendoTime = 1.5, decrescendoTime = 1.5,
            outputLevel = 0.35,
            osc1Wave = 0, osc2On = 0, osc2Wave = 0, osc2Octave = 0,
            osc2DetuneCents = 0, oscMix = 0, pulseWidth = 0.5,
            subMix = 0, noiseMix = 0,
            filterOn = 1, filterCutoff = 2400, filterRq = 0.7,
            filterMix = 1, filterLag = 0.08, keyTracking = 0.35,
            monitorOn = 1, monitorRate = 8|

            var followedFreq, followedAmp, performanceEnv;
            var width, osc1, osc2Freq, osc2, osc2Blend, oscillatorMix;
            var sub, noise, sourceMix, sourceDenom;
            var trackedCutoff, effectiveCutoff, filtered, filterBlend, postFilter;
            var afterAmp, afterGate, sig, monitorTrig;

            followedFreq = Lag.kr(freq.clip(20, 20000), freqLag.max(0));
            followedAmp = LagUD.kr(
                amp.max(0),
                ampAttack.max(0.001),
                ampRelease.max(0.001)
            );
            performanceEnv = LagUD.kr(
                performanceGate.clip(0, 1),
                crescendoTime.max(0.001),
                decrescendoTime.max(0.001)
            );
            width = pulseWidth.clip(0.05, 0.95);

            // oscillator source: 0 = Saw, 1 = Pulse, 2 = Triangle
            osc1 = Select.ar(osc1Wave.clip(0, 2), [
                Saw.ar(followedFreq),
                Pulse.ar(followedFreq, width),
                LFTri.ar(followedFreq)
            ]);
            osc2Freq = followedFreq
                * (2 ** osc2Octave.clip(-2, 2))
                * (2 ** (osc2DetuneCents.clip(-50, 50) / 1200));
            osc2 = Select.ar(osc2Wave.clip(0, 2), [
                Saw.ar(osc2Freq),
                Pulse.ar(osc2Freq, width),
                LFTri.ar(osc2Freq)
            ]);
            osc2Blend = osc2On.clip(0, 1) * oscMix.clip(0, 1);
            oscillatorMix = SelectX.ar(osc2Blend, [osc1, osc2]);

            sub = SinOsc.ar(followedFreq * 0.5);
            noise = PinkNoise.ar;
            // source mix: normalize optional sub/noise so their mix changes
            // remain controlled before the resonant filter.
            sourceDenom = (1 + subMix.clip(0, 1) + noiseMix.clip(0, 1)).max(1);
            sourceMix = (
                oscillatorMix
                + (sub * subMix.clip(0, 1))
                + (noise * noiseMix.clip(0, 1))
            ) / sourceDenom;

            // keyTracking raises cutoff for higher notes so their relative
            // brightness can stay more consistent.  At 0 it is fixed.
            trackedCutoff = filterCutoff.clip(40, 16000)
                * ((followedFreq / 440).clip(0.125, 8) ** keyTracking.clip(0, 1));
            effectiveCutoff = Lag.kr(
                trackedCutoff.clip(40, 16000),
                filterLag.max(0)
            );
            filtered = RLPF.ar(
                sourceMix,
                effectiveCutoff,
                filterRq.clip(0.05, 1.0)
            );
            // filterOn OFF always selects dry source, regardless of filterMix.
            filterBlend = filterOn.clip(0, 1) * filterMix.clip(0, 1);
            postFilter = SelectX.ar(filterBlend, [sourceMix, filtered]);

            // Signal path:
            // oscillator source -> source mix -> RLPF -> amplitude response
            // -> performance gate -> LeakDC -> Limiter -> stereo Out
            afterAmp = postFilter * followedAmp;
            afterGate = afterAmp
                * performanceEnv
                * outputLevel.clip(0, 0.8);
            sig = LeakDC.ar(afterGate ! 2);
            sig = Limiter.ar(sig, 0.8, 0.01);

            monitorTrig = Impulse.kr(monitorRate.clip(0.5, 20)) * monitorOn.clip(0, 1);
            SendReply.kr(
                monitorTrig,
                '/subtractiveProbe/monitor',
                [freq, amp, followedFreq, followedAmp, performanceEnv, effectiveCutoff]
            );
            Out.ar(out, sig);
        }).add;

        s.sync;

        ~subtractiveSynth.notNil.if({
            ~subtractiveSynth.free;
        });
        "creating subtractive probe synth".postln;
        ~subtractiveSynth = Synth(\subtractiveProbe, [
            \freqLag, ~subtractiveParams[\freqLag],
            \ampAttack, ~subtractiveParams[\ampAttack],
            \ampRelease, ~subtractiveParams[\ampRelease],
            \performanceGate, ~subtractiveParams[\performanceGate],
            \crescendoTime, ~subtractiveParams[\crescendoTime],
            \decrescendoTime, ~subtractiveParams[\decrescendoTime],
            \outputLevel, ~subtractiveParams[\outputLevel],
            \osc1Wave, ~subtractiveParams[\osc1Wave],
            \osc2On, ~subtractiveParams[\osc2On],
            \osc2Wave, ~subtractiveParams[\osc2Wave],
            \osc2Octave, ~subtractiveParams[\osc2Octave],
            \osc2DetuneCents, ~subtractiveParams[\osc2DetuneCents],
            \oscMix, ~subtractiveParams[\oscMix],
            \pulseWidth, ~subtractiveParams[\pulseWidth],
            \subMix, ~subtractiveParams[\subMix],
            \noiseMix, ~subtractiveParams[\noiseMix],
            \filterOn, ~subtractiveParams[\filterOn],
            \filterCutoff, ~subtractiveParams[\filterCutoff],
            \filterRq, ~subtractiveParams[\filterRq],
            \filterMix, ~subtractiveParams[\filterMix],
            \filterLag, ~subtractiveParams[\filterLag],
            \keyTracking, ~subtractiveParams[\keyTracking],
            \monitorOn, ~subtractiveParams[\monitorOn],
            \monitorRate, ~subtractiveParams[\monitorRate]
        ]);

        ~fmtSubtractiveNumber = { |value, step = 0.001|
            (value ? 0).asFloat.round(step).asString;
        };
        ~fmtSubtractiveHz = { |value|
            ~fmtSubtractiveNumber.(value, 0.1) ++ " Hz";
        };
        ~fmtSubtractiveOnOff = { |value|
            ((value ? 0).asFloat >= 0.5).if({ "ON" }, { "OFF" });
        };
        ~subtractiveWaveName = { |value|
            ["Saw", "Pulse", "Triangle"][value.asInteger.clip(0, 2)];
        };

        ~refreshSubtractiveMonitor = {
            var labels;
            labels = ~subtractiveMonitorLabels;
            labels.notNil.if({
                labels[\freq].notNil.if({
                    labels[\freq].string_(
                        "targetFreq: " ++ ~fmtSubtractiveHz.(~subtractiveMonitor[\targetFreq])
                        ++ "    followedFreq: "
                        ++ ~fmtSubtractiveHz.(~subtractiveMonitor[\followedFreq])
                    );
                });
                labels[\amp].notNil.if({
                    labels[\amp].string_(
                        "targetAmp: "
                        ++ ~fmtSubtractiveNumber.(~subtractiveMonitor[\targetAmp])
                        ++ "    followedAmp: "
                        ++ ~fmtSubtractiveNumber.(~subtractiveMonitor[\followedAmp])
                    );
                });
                labels[\gate].notNil.if({
                    labels[\gate].string_(
                        "performanceGate: "
                        ++ ~fmtSubtractiveOnOff.(~subtractiveParams[\performanceGate])
                        ++ "    envelope: "
                        ++ ~fmtSubtractiveNumber.(~subtractiveMonitor[\performanceEnv], 0.01)
                    );
                });
                labels[\filter].notNil.if({
                    labels[\filter].string_(
                        "effective cutoff: "
                        ++ ~fmtSubtractiveHz.(~subtractiveMonitor[\effectiveCutoff])
                        ++ "    filter " ++ ~fmtSubtractiveOnOff.(~subtractiveParams[\filterOn])
                        ++ "    mix "
                        ++ ~fmtSubtractiveNumber.(~subtractiveParams[\filterMix])
                    );
                });
                labels[\oscillators].notNil.if({
                    labels[\oscillators].string_(
                        "osc1: " ++ ~subtractiveWaveName.(~subtractiveParams[\osc1Wave])
                        ++ "    osc2: "
                        ++ ~fmtSubtractiveOnOff.(~subtractiveParams[\osc2On])
                        ++ " / " ++ ~subtractiveWaveName.(~subtractiveParams[\osc2Wave])
                    );
                });
                labels[\output].notNil.if({
                    labels[\output].string_(
                        "outputLevel: "
                        ++ ~fmtSubtractiveNumber.(~subtractiveParams[\outputLevel])
                        ++ "    amp range: "
                        ++ ~fmtSubtractiveNumber.(~subtractiveParams[\ampMin])
                        ++ " - "
                        ++ ~fmtSubtractiveNumber.(~subtractiveParams[\ampMax])
                    );
                });
            });
        };

        ~updateSubtractiveMonitor = {
            { ~refreshSubtractiveMonitor.(); }.defer;
        };

        ~setSubtractiveParam = { |key, value|
            ~subtractiveParams[key] = value;
            (~subtractiveSynth.notNil and: {
                ~subtractiveSynthParamKeys.includes(key)
            }).if({
                ~subtractiveSynth.set(key, value);
            });
            ~updateSubtractiveMonitor.();
        };

        ~setSubtractivePerformanceGate = { |value|
            var gate;
            gate = value.clip(0, 1).asInteger;
            ~setSubtractiveParam.(\performanceGate, gate);
            {
                ~subtractiveControls.notNil.if({
                    ~subtractiveControls[\performanceGate].notNil.if({
                        ~subtractiveControls[\performanceGate].value_(gate);
                    });
                });
            }.defer;
        };

        ~toggleSubtractivePerformanceGate = {
            var current;
            current = (~subtractiveParams[\performanceGate] ? 0).asInteger;
            ~setSubtractivePerformanceGate.((1 - current).asInteger);
        };

        ~resetSubtractiveParams = {
            ~subtractiveDefaults.keysValuesDo({ |key, value|
                ~setSubtractiveParam.(key, value);
            });
            {
                ~subtractiveControls.notNil.if({
                    ~subtractiveControls.keysValuesDo({ |key, control|
                        control.value_(~subtractiveParams[key]);
                    });
                });
            }.defer;
        };

        ~openSubtractiveScope = {
            {
                try {
                    s.scope(2);
                } { |error|
                    ("Open Scope failed: " ++ error.asString).postln;
                };
            }.defer;
        };

        ~openSubtractiveFreqScope = {
            {
                try {
                    ~subtractiveFreqScope = FreqScope.new;
                } { |error|
                    ("Open FreqScope failed: " ++ error.asString).postln;
                };
            }.defer;
        };

        {
            (~subtractiveProbeInstance == subtractiveProbeInstance).if({
                ~subtractiveWindow.notNil.if({
                    ~subtractiveWindow.close;
                });
                ~subtractiveMonitorWindow.notNil.if({
                    ~subtractiveMonitorWindow.close;
                });
                ~subtractiveMonitorLabels = nil;
                ~subtractiveWindow = Window(
                    "Subtractive Probe Controls",
                    Rect(100, 80, 480, 820)
                );
                ~subtractiveControls = ();

                ~makeSubtractiveSlider = {
                    |label, key, minValue, maxValue, step = 0, warp = \lin|
                    var slider;
                    slider = EZSlider(
                        ~subtractiveWindow,
                        450@22,
                        label,
                        ControlSpec(
                            minValue,
                            maxValue,
                            warp,
                            step,
                            ~subtractiveParams[key]
                        ),
                        { |view| ~setSubtractiveParam.(key, view.value); },
                        ~subtractiveParams[key]
                    );
                    ~subtractiveControls[key] = slider;
                    slider.view;
                };

                ~makeSubtractiveToggle = { |label, key|
                    var button;
                    button = Button()
                        .states_([
                            [label ++ ": OFF", Color.black, Color.gray(0.85)],
                            [label ++ ": ON", Color.white, Color(0.2, 0.45, 0.8)]
                        ])
                        .value_(~subtractiveParams[key].asInteger)
                        .action_({ |view| ~setSubtractiveParam.(key, view.value); });
                    ~subtractiveControls[key] = button;
                    button;
                };

                ~makeSubtractiveWaveMenu = { |label, key|
                    var menu;
                    menu = PopUpMenu()
                        .items_(["Saw", "Pulse", "Triangle"])
                        .value_(~subtractiveParams[key].asInteger)
                        .action_({ |view| ~setSubtractiveParam.(key, view.value); });
                    ~subtractiveControls[key] = menu;
                    HLayout(
                        StaticText().string_(label).minWidth_(165),
                        menu
                    );
                };

                ~makeSubtractiveGateButton = {
                    var button;
                    button = Button()
                        .states_([
                            ["Gate: OFF (space)", Color.black, Color.gray(0.85)],
                            ["Gate: ON (space)", Color.white, Color(0.2, 0.6, 0.25)]
                        ])
                        .value_(~subtractiveParams[\performanceGate].asInteger)
                        .action_({ ~toggleSubtractivePerformanceGate.(); });
                    ~subtractiveControls[\performanceGate] = button;
                    button;
                };

                ~subtractiveWindow.view.keyDownAction_({
                    |view, char, modifiers, unicode, keycode|
                    ((unicode == 32) or: { keycode == 32 }).if({
                        ~toggleSubtractivePerformanceGate.();
                    });
                });

                ~subtractiveWindow.layout = VLayout(
                    StaticText().string_("Subtractive synthesis: source -> RLPF -> amp -> gate"),
                    StaticText().string_("Performance / Response"),
                    ~makeSubtractiveGateButton.(),
                    ~makeSubtractiveSlider.("crescendoTime", \crescendoTime, 0.0, 8.0, 0.001),
                    ~makeSubtractiveSlider.("decrescendoTime", \decrescendoTime, 0.0, 8.0, 0.001),
                    ~makeSubtractiveSlider.("freqLag", \freqLag, 0.0, 0.5, 0.001),
                    ~makeSubtractiveSlider.("ampAttack", \ampAttack, 0.001, 1.0, 0.001),
                    ~makeSubtractiveSlider.("ampRelease", \ampRelease, 0.001, 1.5, 0.001),
                    ~makeSubtractiveSlider.("outputLevel", \outputLevel, 0.0, 0.8, 0.001),
                    ~makeSubtractiveSlider.("ampMin", \ampMin, 0.0, 0.2, 0.001),
                    ~makeSubtractiveSlider.("ampMax", \ampMax, 0.01, 0.4, 0.001),
                    StaticText().string_("Oscillators"),
                    ~makeSubtractiveWaveMenu.("osc1Wave", \osc1Wave),
                    ~makeSubtractiveToggle.("osc2On", \osc2On),
                    ~makeSubtractiveWaveMenu.("osc2Wave", \osc2Wave),
                    ~makeSubtractiveSlider.("osc2Octave", \osc2Octave, -2.0, 2.0, 1.0),
                    ~makeSubtractiveSlider.("osc2DetuneCents", \osc2DetuneCents, -50.0, 50.0, 1.0),
                    ~makeSubtractiveSlider.("oscMix", \oscMix, 0.0, 1.0, 0.001),
                    ~makeSubtractiveSlider.("pulseWidth", \pulseWidth, 0.05, 0.95, 0.001),
                    ~makeSubtractiveSlider.("subMix", \subMix, 0.0, 1.0, 0.001),
                    ~makeSubtractiveSlider.("noiseMix", \noiseMix, 0.0, 0.5, 0.001),
                    StaticText().string_("Filter"),
                    ~makeSubtractiveToggle.("filterOn", \filterOn),
                    ~makeSubtractiveSlider.("filterCutoff", \filterCutoff, 40.0, 16000.0, 1.0, \exp),
                    StaticText().string_("filterRq: low rq = sharper / more resonant"),
                    ~makeSubtractiveSlider.("filterRq", \filterRq, 0.05, 1.0, 0.001),
                    ~makeSubtractiveSlider.("filterMix", \filterMix, 0.0, 1.0, 0.001),
                    ~makeSubtractiveSlider.("filterLag", \filterLag, 0.0, 0.5, 0.001),
                    ~makeSubtractiveSlider.("keyTracking", \keyTracking, 0.0, 1.0, 0.001),
                    StaticText().string_("Utility"),
                    Button()
                        .states_([["Reset defaults", Color.black, Color.gray(0.85)]])
                        .action_({ ~resetSubtractiveParams.(); })
                );
                ~subtractiveWindow.front;

                ~subtractiveMonitorWindow = Window(
                    "Subtractive Probe Monitor",
                    Rect(610, 80, 500, 310)
                );
                ~subtractiveMonitorLabels = ();

                ~makeSubtractiveMonitorLabel = { |key|
                    var label;
                    label = StaticText().string_("");
                    ~subtractiveMonitorLabels[key] = label;
                    label;
                };

                ~subtractiveMonitorWindow.layout = VLayout(
                    StaticText().string_("Subtractive probe monitor"),
                    HLayout(
                        Button()
                            .states_([["Open Scope", Color.black, Color.gray(0.85)]])
                            .action_({ ~openSubtractiveScope.(); }),
                        Button()
                            .states_([["Open FreqScope", Color.black, Color.gray(0.85)]])
                            .action_({ ~openSubtractiveFreqScope.(); })
                    ),
                    ~makeSubtractiveMonitorLabel.(\freq),
                    ~makeSubtractiveMonitorLabel.(\amp),
                    ~makeSubtractiveMonitorLabel.(\gate),
                    ~makeSubtractiveMonitorLabel.(\filter),
                    ~makeSubtractiveMonitorLabel.(\oscillators),
                    ~makeSubtractiveMonitorLabel.(\output)
                );
                ~refreshSubtractiveMonitor.();
                ~subtractiveMonitorWindow.front;
            });
        }.defer;

        OSCdef(\subtractiveProbeMonitor, { |msg, time, addr, recvPort|
            var nodeID;
            ~subtractiveDebugEvents.if({
                msg.postln;
            });
            // SendReply: [address, nodeID, replyID, targetFreq, targetAmp,
            // followedFreq, followedAmp, performanceEnv, effectiveCutoff].
            (msg.size >= 9).if({
                nodeID = msg[1].asInteger;
                ((~subtractiveSynth.isNil) or: {
                    nodeID == ~subtractiveSynth.nodeID
                }).if({
                    ~subtractiveMonitor[\targetFreq] = msg[3].asFloat;
                    ~subtractiveMonitor[\targetAmp] = msg[4].asFloat;
                    ~subtractiveMonitor[\followedFreq] = msg[5].asFloat;
                    ~subtractiveMonitor[\followedAmp] = msg[6].asFloat;
                    ~subtractiveMonitor[\performanceEnv] = msg[7].asFloat;
                    ~subtractiveMonitor[\effectiveCutoff] = msg[8].asFloat;
                    ~updateSubtractiveMonitor.();
                });
            });
        }, "/subtractiveProbe/monitor");

        // Python remains the source of truth for musical pitch.  This probe
        // follows final_freq only; it does not calculate scale or quantization.
        OSCdef(\subtractiveProbeFinalFreq, { |msg, time, addr, recvPort|
            var freq;
            freq = msg[1].asFloat.max(0);
            ~subtractiveMonitor[\targetFreq] = freq;
            ~subtractiveSynth.notNil.if({
                ~subtractiveSynth.set(\freq, freq);
            });
            ~updateSubtractiveMonitor.();
            ~subtractiveDebugEvents.if({
                ["subtractive final freq", freq].postln;
            });
        }, "/sample/right/pitch/final_freq");

        // /sample/left/pinch is mapped locally to the user-visible amp range.
        OSCdef(\subtractiveProbeLeftPinch, { |msg, time, addr, recvPort|
            var value, amp, ampMin, ampMax;
            value = msg[1].asFloat.clip(0, 1);
            ampMin = ~subtractiveParams[\ampMin].min(~subtractiveParams[\ampMax]);
            ampMax = ~subtractiveParams[\ampMin].max(~subtractiveParams[\ampMax]);
            amp = value.linlin(0, 1, ampMin, ampMax);
            ~subtractiveMonitor[\targetAmp] = amp;
            ~subtractiveSynth.notNil.if({
                ~subtractiveSynth.set(\amp, amp);
            });
            ~updateSubtractiveMonitor.();
            ~subtractiveDebugEvents.if({
                ["subtractive amp", value, amp].postln;
            });
        }, "/sample/left/pinch");

        // Shared, intentionally small probe-switch protocol.  It closes both
        // windows, frees this Synth, and unregisters only this probe's OSCdefs.
        ~activeProbeCleanup = {
            var windows, oscdefKeys;
            ~subtractiveProbeInstance = (~subtractiveProbeInstance ? 0) + 1;
            ~subtractiveSynth.notNil.if({
                ~subtractiveSynth.free;
            });
            ~subtractiveSynth = nil;

            oscdefKeys = [
                \subtractiveProbeMonitor,
                \subtractiveProbeFinalFreq,
                \subtractiveProbeLeftPinch
            ];
            oscdefKeys.do({ |key|
                try {
                    OSCdef(key).free;
                } { |error| };
            });

            windows = [~subtractiveWindow, ~subtractiveMonitorWindow];
            windows.do({ |window|
                window.notNil.if({
                    try {
                        window.close;
                    } { |error| };
                });
            });
            ~subtractiveWindow = nil;
            ~subtractiveMonitorWindow = nil;
            ~subtractiveFreqScope.notNil.if({
                try {
                    ~subtractiveFreqScope.kill;
                } { |error| };
            });
            ~subtractiveFreqScope = nil;
            ~subtractiveControls = nil;
            ~subtractiveMonitorLabels = nil;
            (~activeProbeName == \subtractiveProbe).if({
                ~activeProbeName = nil;
            });
        };
        ~activeProbeName = \subtractiveProbe;

        "Listening for sample mapping events with the subtractive probe.".postln;
        "Subtractive Probe Controls and Monitor windows are available.".postln;
        "Use the Gate button or spacebar in the control window to perform.".postln;
    });
});
)
