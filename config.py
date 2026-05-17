"""Project configuration for hand-control output targets."""


OSC_TARGETS = {
    "supercollider": {
        "host": "127.0.0.1",
        "port": 57120,
    },
}

SAMPLE_MAPPING = {
    "pitch_min_freq": 220.0,
    "pitch_max_freq": 880.0,
}
