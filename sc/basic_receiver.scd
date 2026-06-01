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
    ~debugProbeMonitor = false;

    ~probeDefaults = (
        freqLag: 0.08,
        ampLag: 0.08,
        portamentoOn: 0,
        portamentoTime: 0.15,
        softClipOn: 0,
        softClipDrive: 2.0,
        softClipMix: 1.0,
        filterOn: 0,
        filterCutoff: 5000,
        filterRq: 0.5,
        filterMix: 1.0,
        filterLag: 0.05,
        outputLevel: 0.7,
        performanceGate: 0,
        crescendoTime: 1.5,
        decrescendoTime: 1.5,
        monitorOn: 1,
        monitorRate: 10,
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
        \filterOn,
        \filterCutoff,
        \filterRq,
        \filterMix,
        \filterLag,
        \outputLevel,
        \performanceGate,
        \crescendoTime,
        \decrescendoTime,
        \monitorOn,
        \monitorRate
    ];

    ~probeMonitor = (
        targetFreq: 440.0,
        targetAmp: 0.05,
        followedFreq: 440.0,
        followedAmp: 0.05,
        performanceEnv: 0.0,
        filterFreq: 5000.0
    );
    ~probeHistoryMax = 50;
    ~probeHistory = [[440.0, 440.0]];

    SynthDef(\basicOscProbe, { |out = 0, freq = 440, amp = 0.05,
        freqLag = 0.08, ampLag = 0.08,
        portamentoOn = 0, portamentoTime = 0.15,
        softClipOn = 0, softClipDrive = 2.0, softClipMix = 1.0,
        filterOn = 0, filterCutoff = 5000, filterRq = 0.5,
        filterMix = 1.0, filterLag = 0.05,
        outputLevel = 0.7,
        performanceGate = 0, crescendoTime = 1.5, decrescendoTime = 1.5,
        monitorOn = 1, monitorRate = 10|

        var freqFollowTime, followedFreq, followedAmp;
        var performanceEnv, dry, clipped, shaped;
        var filterFreq, filtered, filteredMix, sig, monitorTrig;

        freqFollowTime = Select.kr(
            portamentoOn.clip(0, 1),
            [freqLag.max(0), portamentoTime.max(0)]
        );
        followedFreq = Lag.kr(freq.max(20), freqFollowTime);
        followedAmp = Lag.kr(amp.max(0), ampLag.max(0));
        performanceEnv = LagUD.kr(
            performanceGate.clip(0, 1),
            crescendoTime.max(0),
            decrescendoTime.max(0)
        );

        dry = SinOsc.ar(followedFreq) * followedAmp;
        clipped = (dry * softClipDrive.max(1)).tanh;
        shaped = SelectX.ar(
            softClipOn.clip(0, 1) * softClipMix.clip(0, 1),
            [dry, clipped]
        );
        filterFreq = Lag.kr(filterCutoff.clip(40, 18000), filterLag.max(0));
        filtered = RLPF.ar(shaped, filterFreq, filterRq.clip(0.05, 1.0));
        filteredMix = SelectX.ar(
            filterOn.clip(0, 1) * filterMix.clip(0, 1),
            [shaped, filtered]
        );
        sig = filteredMix * outputLevel.clip(0, 1) * performanceEnv;
        monitorTrig = Impulse.kr(monitorRate.clip(0.1, 30)) * monitorOn.clip(0, 1);
        SendReply.kr(
            monitorTrig,
            '/basicOscProbe/monitor',
            [followedFreq, followedAmp, performanceEnv, filterFreq]
        );
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
        \filterOn, ~probeParams[\filterOn],
        \filterCutoff, ~probeParams[\filterCutoff],
        \filterRq, ~probeParams[\filterRq],
        \filterMix, ~probeParams[\filterMix],
        \filterLag, ~probeParams[\filterLag],
        \outputLevel, ~probeParams[\outputLevel],
        \performanceGate, ~probeParams[\performanceGate],
        \crescendoTime, ~probeParams[\crescendoTime],
        \decrescendoTime, ~probeParams[\decrescendoTime],
        \monitorOn, ~probeParams[\monitorOn],
        \monitorRate, ~probeParams[\monitorRate]
    ]);

    ~fmtProbeNumber = { |value, step = 0.001|
        (value ? 0).asFloat.round(step).asString;
    };

    ~fmtProbeHz = { |value|
        ~fmtProbeNumber.(value, 0.1) ++ " Hz";
    };

    ~fmtProbeOnOff = { |value|
        ((value ? 0).asFloat >= 0.5).if({ "ON" }, { "OFF" });
    };

    ~refreshProbeMonitor = {
        var labels;
        labels = ~probeMonitorLabels;
        labels.notNil.if({
            labels[\freq].notNil.if({
                labels[\freq].string_(
                    "targetFreq: " ++ ~fmtProbeHz.(~probeMonitor[\targetFreq])
                    ++ "    followedFreq: " ++ ~fmtProbeHz.(~probeMonitor[\followedFreq])
                );
            });
            labels[\amp].notNil.if({
                labels[\amp].string_(
                    "targetAmp: " ++ ~fmtProbeNumber.(~probeMonitor[\targetAmp], 0.001)
                    ++ "    followedAmp: " ++ ~fmtProbeNumber.(~probeMonitor[\followedAmp], 0.001)
                );
            });
            labels[\gate].notNil.if({
                labels[\gate].string_(
                    "Gate: " ++ ~fmtProbeOnOff.(~probeParams[\performanceGate])
                    ++ "    env " ++ ~fmtProbeNumber.(~probeMonitor[\performanceEnv], 0.01)
                );
            });
            labels[\level].notNil.if({
                labels[\level].string_(
                    "outputLevel: " ++ ~fmtProbeNumber.(~probeParams[\outputLevel], 0.001)
                    ++ "    ampRange: "
                    ++ ~fmtProbeNumber.(~probeParams[\ampMin], 0.001)
                    ++ " - " ++ ~fmtProbeNumber.(~probeParams[\ampMax], 0.001)
                );
            });
            labels[\softClip].notNil.if({
                labels[\softClip].string_(
                    "SoftClip: " ++ ~fmtProbeOnOff.(~probeParams[\softClipOn])
                    ++ "    drive " ++ ~fmtProbeNumber.(~probeParams[\softClipDrive], 0.01)
                    ++ "    mix " ++ ~fmtProbeNumber.(~probeParams[\softClipMix], 0.001)
                );
            });
            labels[\filter].notNil.if({
                labels[\filter].string_(
                    "Filter: " ++ ~fmtProbeOnOff.(~probeParams[\filterOn])
                    ++ "    cutoff " ++ ~fmtProbeHz.(~probeParams[\filterCutoff])
                    ++ "    rq " ++ ~fmtProbeNumber.(~probeParams[\filterRq], 0.01)
                    ++ "    mix " ++ ~fmtProbeNumber.(~probeParams[\filterMix], 0.001)
                );
            });
            labels[\filterFreq].notNil.if({
                labels[\filterFreq].string_(
                    "filterFreq: " ++ ~fmtProbeHz.(~probeMonitor[\filterFreq])
                    ++ "    filterLag " ++ ~fmtProbeNumber.(~probeParams[\filterLag], 0.001)
                );
            });
        });
    };

    ~addProbeHistoryPoint = {
        ~probeHistory = ~probeHistory.add([
            (~probeMonitor[\targetFreq] ? 440).asFloat,
            (~probeMonitor[\followedFreq] ? 440).asFloat
        ]);
        (~probeHistory.size > ~probeHistoryMax).if({
            ~probeHistory = ~probeHistory.copyRange(
                ~probeHistory.size - ~probeHistoryMax,
                ~probeHistory.size - 1
            );
        });
    };

    ~drawProbeLine = { |startPoint, endPoint, color, width = 1|
        Pen.width = width;
        color.set;
        Pen.moveTo(startPoint);
        Pen.lineTo(endPoint);
        Pen.stroke;
    };

    ~drawProbePoints = { |points, color, width = 2|
        (points.size > 1).if({
            Pen.width = width;
            color.set;
            points.do({ |point, index|
                (index == 0).if({
                    Pen.moveTo(point);
                }, {
                    Pen.lineTo(point);
                });
            });
            Pen.stroke;
        });
    };

    ~probePanelRect = { |view|
        var bounds, rect;
        bounds = view.bounds;
        Color.gray(0.96).set;
        Pen.fillRect(bounds);
        rect = Rect(38, 14, bounds.width - 56, bounds.height - 34);
        Color.gray(0.72).set;
        Pen.width = 1;
        Pen.strokeRect(rect);
        rect;
    };

    ~probeLogFreqX = { |freq, rect|
        var minFreq, maxFreq, minLog, maxLog, valueLog, norm;
        minFreq = 80.0;
        maxFreq = 12000.0;
        minLog = minFreq.log;
        maxLog = maxFreq.log;
        valueLog = freq.clip(minFreq, maxFreq).log;
        norm = ((valueLog - minLog) / (maxLog - minLog)).clip(0, 1);
        rect.left + (norm * rect.width);
    };

    ~drawFilterVisual = { |view|
        var plot, cutoff, rq, mix, on, activeMix, cutoffX, points;
        var steps, minFreq, maxFreq, minLog, maxLog, steep, ratioLog, rolloff;
        var freq, norm, x, y, response, diff, bump;
        plot = ~probePanelRect.(view);
        cutoff = (~probeParams[\filterCutoff] ? 5000).asFloat.clip(80, 12000);
        rq = (~probeParams[\filterRq] ? 0.5).asFloat.clip(0.05, 1.0);
        mix = (~probeParams[\filterMix] ? 1.0).asFloat.clip(0, 1);
        on = (~probeParams[\filterOn] ? 0).asFloat.clip(0, 1);
        activeMix = on * mix;
        cutoffX = ~probeLogFreqX.(cutoff, plot);

        Color(0.55, 0.65, 0.95, activeMix * 0.25).set;
        Pen.fillRect(Rect(cutoffX, plot.top, plot.right - cutoffX, plot.height));
        ~drawProbeLine.(
            Point(plot.left, plot.top + (plot.height * 0.12)),
            Point(plot.right, plot.top + (plot.height * 0.12)),
            Color.gray(0.78),
            1
        );

        steps = 72;
        minFreq = 80.0;
        maxFreq = 12000.0;
        minLog = minFreq.log;
        maxLog = maxFreq.log;
        steep = rq.linlin(0.05, 1.0, 10.0, 2.0);
        points = [];
        steps.do({ |index|
            norm = index / (steps - 1);
            freq = (minLog + (norm * (maxLog - minLog))).exp;
            x = plot.left + (norm * plot.width);
            ratioLog = (freq / cutoff).log;
            rolloff = 1 / (1 + (ratioLog * steep).exp);
            response = (1 - activeMix) + (rolloff * activeMix);
            diff = (freq.log - cutoff.log) / (0.18 + (rq * 0.35));
            bump = ((diff * diff).neg.exp) * (1 - rq).clip(0, 1) * activeMix * 0.22;
            response = (response + bump).clip(0, 1.12);
            y = plot.bottom - ((response / 1.12) * plot.height);
            points = points.add(Point(x, y));
        });

        ~drawProbePoints.(
            points,
            (on >= 0.5).if({ Color(0.05, 0.22, 0.65) }, { Color.gray(0.55) }),
            2
        );
        ~drawProbeLine.(Point(cutoffX, plot.top), Point(cutoffX, plot.bottom), Color(0.85, 0.18, 0.12), 2);
        ~drawProbeLine.(Point(plot.left, plot.bottom), Point(plot.right, plot.bottom), Color.gray(0.4), 1);
        ~drawProbeLine.(Point(plot.left, plot.top), Point(plot.left, plot.bottom), Color.gray(0.4), 1);
    };

    ~drawSoftClipVisual = { |view|
        var plot, drive, mix, on, activeMix, dryPoints, shapedPoints;
        var steps, input, clipped, output, norm, x, dryY, shapedY, centerY;
        plot = ~probePanelRect.(view);
        drive = (~probeParams[\softClipDrive] ? 2.0).asFloat.clip(1, 20);
        mix = (~probeParams[\softClipMix] ? 1.0).asFloat.clip(0, 1);
        on = (~probeParams[\softClipOn] ? 0).asFloat.clip(0, 1);
        activeMix = on * mix;
        steps = 90;
        dryPoints = [];
        shapedPoints = [];
        centerY = plot.top + (plot.height * 0.5);

        ~drawProbeLine.(Point(plot.left, centerY), Point(plot.right, centerY), Color.gray(0.82), 1);
        ~drawProbeLine.(
            Point(plot.left + (plot.width * 0.5), plot.top),
            Point(plot.left + (plot.width * 0.5), plot.bottom),
            Color.gray(0.82),
            1
        );

        steps.do({ |index|
            norm = index / (steps - 1);
            input = -1.0 + (norm * 2.0);
            clipped = (input * drive).tanh;
            output = (input * (1 - activeMix)) + (clipped * activeMix);
            x = plot.left + (norm * plot.width);
            dryY = centerY - ((input / 1.12) * (plot.height * 0.5));
            shapedY = centerY - ((output / 1.12) * (plot.height * 0.5));
            dryPoints = dryPoints.add(Point(x, dryY));
            shapedPoints = shapedPoints.add(Point(x, shapedY));
        });

        ~drawProbePoints.(dryPoints, Color.gray(0.68), 1);
        ~drawProbePoints.(
            shapedPoints,
            (on >= 0.5).if({ Color(0.0, 0.42, 0.72) }, { Color.gray(0.45) }),
            2
        );
    };

    ~drawPitchFollowVisual = { |view|
        var plot, hist, minFreq, maxFreq, range, pointCount, denom;
        var targetPoints, followedPoints, freqToY, x;
        plot = ~probePanelRect.(view);
        hist = ~probeHistory ? [[440.0, 440.0]];
        minFreq = 20000.0;
        maxFreq = 20.0;
        hist.do({ |point|
            minFreq = minFreq.min(point[0]).min(point[1]);
            maxFreq = maxFreq.max(point[0]).max(point[1]);
        });
        range = (maxFreq - minFreq).max(1);
        minFreq = (minFreq - (range * 0.12)).max(20);
        maxFreq = maxFreq + (range * 0.12);
        freqToY = { |freq|
            plot.bottom - (((freq - minFreq) / (maxFreq - minFreq)).clip(0, 1) * plot.height);
        };
        pointCount = hist.size;
        denom = (pointCount - 1).max(1);
        targetPoints = [];
        followedPoints = [];

        ~drawProbeLine.(Point(plot.left, plot.top), Point(plot.left, plot.bottom), Color.gray(0.4), 1);
        ~drawProbeLine.(Point(plot.left, plot.bottom), Point(plot.right, plot.bottom), Color.gray(0.4), 1);
        hist.do({ |point, index|
            x = plot.left + ((index / denom) * plot.width);
            targetPoints = targetPoints.add(Point(x, freqToY.(point[0])));
            followedPoints = followedPoints.add(Point(x, freqToY.(point[1])));
        });
        ~drawProbePoints.(targetPoints, Color(0.1, 0.22, 0.82), 1.5);
        ~drawProbePoints.(followedPoints, Color(0.85, 0.28, 0.08), 2.5);
    };

    ~refreshProbeVisuals = {
        var labels, views;
        labels = ~probeVisualLabels;
        labels.notNil.if({
            labels[\filter].notNil.if({
                labels[\filter].string_(
                    "LPF / Filter    "
                    ++ ~fmtProbeOnOff.(~probeParams[\filterOn])
                    ++ "    cutoff " ++ ~fmtProbeHz.(~probeParams[\filterCutoff])
                    ++ "    rq " ++ ~fmtProbeNumber.(~probeParams[\filterRq], 0.01)
                    ++ "    mix " ++ ~fmtProbeNumber.(~probeParams[\filterMix], 0.001)
                    ++ "    lag " ++ ~fmtProbeNumber.(~probeParams[\filterLag], 0.001)
                );
            });
            labels[\softClip].notNil.if({
                labels[\softClip].string_(
                    "Soft Clip Curve    "
                    ++ ~fmtProbeOnOff.(~probeParams[\softClipOn])
                    ++ "    drive " ++ ~fmtProbeNumber.(~probeParams[\softClipDrive], 0.01)
                    ++ "    mix " ++ ~fmtProbeNumber.(~probeParams[\softClipMix], 0.001)
                );
            });
            labels[\pitch].notNil.if({
                labels[\pitch].string_(
                    "Pitch Follow / Portamento    target "
                    ++ ~fmtProbeHz.(~probeMonitor[\targetFreq])
                    ++ "    followed " ++ ~fmtProbeHz.(~probeMonitor[\followedFreq])
                    ++ "    mode " ++ ((~probeParams[\portamentoOn] ? 0).asInteger == 1).if({ "portamento" }, { "freqLag" })
                    ++ "    freqLag " ++ ~fmtProbeNumber.(~probeParams[\freqLag], 0.001)
                    ++ "    portamentoTime " ++ ~fmtProbeNumber.(~probeParams[\portamentoTime], 0.001)
                );
            });
        });

        views = ~probeVisualViews;
        views.notNil.if({
            views.keysValuesDo({ |key, view|
                view.notNil.if({
                    view.refresh;
                });
            });
        });
    };

    ~updateProbeMonitor = {
        {
            ~refreshProbeMonitor.();
            ~refreshProbeVisuals.();
        }.defer;
    };

    ~setProbeParam = { |key, value|
        ~probeParams[key] = value;
        (~basicReceiverSynth.notNil and: {
            ~probeSynthParamKeys.includes(key)
        }).if({
            ~basicReceiverSynth.set(key, value);
        });
        ~updateProbeMonitor.();
    };

    ~resetProbeParams = {
        ~probeDefaults.keysValuesDo({ |key, value|
            ~setProbeParam.(key, value);
        });
    };

    ~setPerformanceGate = { |value|
        var gate;
        gate = value.clip(0, 1).asInteger;
        ~setProbeParam.(\performanceGate, gate);
        ~probeControls.notNil.if({
            ~probeControls[\performanceGate].notNil.if({
                ~probeControls[\performanceGate].value_(gate);
            });
        });
    };

    ~togglePerformanceGate = {
        var current;
        current = (~probeParams[\performanceGate] ? 0).asInteger;
        ~setPerformanceGate.((1 - current).asInteger);
    };

    ~openProbeScope = {
        {
            try {
                s.scope(2);
            } { |error|
                ("Open Scope failed: " ++ error.asString).postln;
            };
        }.defer;
    };

    ~openProbeFreqScope = {
        {
            try {
                ~probeFreqScope = FreqScope.new;
            } { |error|
                ("Open FreqScope failed: " ++ error.asString).postln;
            };
        }.defer;
    };

    {
        ~probeWindow.notNil.if({
            ~probeWindow.close;
        });
        ~probeMonitorWindow.notNil.if({
            ~probeMonitorWindow.close;
        });
        ~probeVisualizerWindow.notNil.if({
            ~probeVisualizerWindow.close;
        });
        ~probeMonitorLabels = nil;
        ~probeVisualLabels = nil;
        ~probeVisualViews = nil;

        ~probeWindow = Window("Probe Synth Controls", Rect(100, 100, 420, 650));
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

        ~makePerformanceGateButton = {
            var button;
            button = Button()
                .states_([
                    ["Gate: OFF (space)", Color.black, Color.gray(0.85)],
                    ["Gate: ON (space)", Color.white, Color(0.2, 0.6, 0.25)]
                ])
                .value_(~probeParams[\performanceGate].asInteger)
                .action_({ ~togglePerformanceGate.(); });
            ~probeControls[\performanceGate] = button;
            button;
        };

        ~probeWindow.view.keyDownAction_({ |view, char, modifiers, unicode, keycode|
            ((unicode == 32) or: { keycode == 32 }).if({
                ~togglePerformanceGate.();
            });
        });

        ~probeWindow.layout = VLayout(
            StaticText().string_("Sample mapping probe synth controls"),
            StaticText().string_("Performance Gate starts OFF. Reset defaults returns it to OFF."),
            ~makePerformanceGateButton.(),
            ~makeProbeSlider.("crescendoTime", \crescendoTime, 0.0, 8.0, 0.001),
            ~makeProbeSlider.("decrescendoTime", \decrescendoTime, 0.0, 8.0, 0.001),
            ~makeProbeSlider.("freqLag", \freqLag, 0.0, 0.3, 0.001),
            ~makeProbeSlider.("ampLag", \ampLag, 0.0, 0.3, 0.001),
            ~makeProbeToggle.("portamento", \portamentoOn),
            ~makeProbeSlider.("portamentoTime", \portamentoTime, 0.0, 1.0, 0.001),
            ~makeProbeToggle.("softClip", \softClipOn),
            ~makeProbeSlider.("softClipDrive", \softClipDrive, 1.0, 20.0, 0.01),
            ~makeProbeSlider.("softClipMix", \softClipMix, 0.0, 1.0, 0.001),
            ~makeProbeToggle.("filter", \filterOn),
            ~makeProbeSlider.("filterCutoff", \filterCutoff, 80.0, 12000.0, 1.0),
            ~makeProbeSlider.("filterRq", \filterRq, 0.05, 1.0, 0.001),
            ~makeProbeSlider.("filterMix", \filterMix, 0.0, 1.0, 0.001),
            ~makeProbeSlider.("filterLag", \filterLag, 0.0, 0.3, 0.001),
            ~makeProbeSlider.("outputLevel", \outputLevel, 0.0, 1.0, 0.001),
            ~makeProbeSlider.("ampMin", \ampMin, 0.0, 0.2, 0.001),
            ~makeProbeSlider.("ampMax", \ampMax, 0.01, 0.8, 0.001),
            Button()
                .states_([["Reset defaults", Color.black, Color.gray(0.85)]])
                .action_({
                    ~resetProbeParams.();
                    ~probeControls.keysValuesDo({ |key, control|
                        (key == \performanceGate).if({
                            control.value_(~probeParams[key].asInteger);
                        }, {
                            control.valueAction_(~probeParams[key]);
                        });
                    });
                })
        );
        ~probeWindow.front;

        ~probeMonitorWindow = Window("Probe Synth Monitor", Rect(540, 100, 420, 260));
        ~probeMonitorLabels = ();

        ~makeProbeMonitorLabel = { |key|
            var label;
            label = StaticText().string_("");
            ~probeMonitorLabels[key] = label;
            label;
        };

        ~probeMonitorWindow.layout = VLayout(
            StaticText().string_("Probe synth sound monitor"),
            HLayout(
                Button()
                    .states_([["Open Scope", Color.black, Color.gray(0.85)]])
                    .action_({ ~openProbeScope.(); }),
                Button()
                    .states_([["Open FreqScope", Color.black, Color.gray(0.85)]])
                    .action_({ ~openProbeFreqScope.(); })
            ),
            ~makeProbeMonitorLabel.(\freq),
            ~makeProbeMonitorLabel.(\amp),
            ~makeProbeMonitorLabel.(\gate),
            ~makeProbeMonitorLabel.(\level),
            ~makeProbeMonitorLabel.(\softClip),
            ~makeProbeMonitorLabel.(\filter),
            ~makeProbeMonitorLabel.(\filterFreq)
        );
        ~refreshProbeMonitor.();
        ~probeMonitorWindow.front;

        ~probeVisualizerWindow = Window("Probe Synth Visualizer", Rect(540, 390, 620, 560));
        ~probeVisualLabels = ();
        ~probeVisualViews = ();

        ~makeProbeVisualLabel = { |key|
            var label;
            label = StaticText().string_("");
            ~probeVisualLabels[key] = label;
            label;
        };

        ~makeProbeVisualView = { |key, drawFunc|
            var view;
            view = UserView()
                .minHeight_(135)
                .background_(Color.gray(0.96))
                .drawFunc_({ |userView| drawFunc.(userView); });
            ~probeVisualViews[key] = view;
            view;
        };

        ~probeVisualizerWindow.layout = VLayout(
            StaticText().string_("Probe synth visual concepts"),
            StaticText().string_("Conceptual sound-design diagrams, not measurement scopes."),
            ~makeProbeVisualLabel.(\filter),
            ~makeProbeVisualView.(\filter, ~drawFilterVisual),
            ~makeProbeVisualLabel.(\softClip),
            ~makeProbeVisualView.(\softClip, ~drawSoftClipVisual),
            ~makeProbeVisualLabel.(\pitch),
            ~makeProbeVisualView.(\pitch, ~drawPitchFollowVisual)
        );
        ~refreshProbeVisuals.();
        ~probeVisualizerWindow.front;
    }.defer;

    OSCdef(\basicOscProbeMonitor, { |msg, time, addr, recvPort|
        var nodeID;
        ~debugProbeMonitor.if({
            msg.postln;
        });
        // SendReply arrives as [address, nodeID, replyID, followedFreq, followedAmp, env, filterFreq].
        (msg.size >= 7).if({
            nodeID = msg[1].asInteger;
            ((~basicReceiverSynth.isNil) or: {
                nodeID == ~basicReceiverSynth.nodeID
            }).if({
                ~probeMonitor[\followedFreq] = msg[3].asFloat;
                ~probeMonitor[\followedAmp] = msg[4].asFloat;
                ~probeMonitor[\performanceEnv] = msg[5].asFloat;
                ~probeMonitor[\filterFreq] = msg[6].asFloat;
                ~addProbeHistoryPoint.();
                ~updateProbeMonitor.();
            });
        }, {
            ~debugProbeMonitor.if({
                ["unexpected probe monitor msg", msg].postln;
            });
        });
    }, "/basicOscProbe/monitor");

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
        ~probeMonitor[\targetFreq] = freq;
        ~basicReceiverSynth.notNil.if({
            ~basicReceiverSynth.set(\freq, freq);
        });
        ~updateProbeMonitor.();
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
        ~probeMonitor[\targetAmp] = amp;
        ~basicReceiverSynth.notNil.if({
            ~basicReceiverSynth.set(\amp, amp);
        });
        ~updateProbeMonitor.();
        ~debugSampleEvents.if({
            ["sample amp", value, amp].postln;
        });
    }, "/sample/left/pinch");

    "Listening for generic hand control events on port 57120".postln;
    "Listening for sample mapping events that control the probe synth.".postln;
    "Probe synth controls are available in the SuperCollider UI window.".postln;
    "Probe synth monitor is available with Scope and FreqScope buttons.".postln;
    "Probe synth visualizer is available for conceptual tone-shaping diagrams.".postln;
    "Set ~debugHandEvents or ~debugSampleEvents to true for per-event logs.".postln;
});
)
