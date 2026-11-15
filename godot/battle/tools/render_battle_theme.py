#!/usr/bin/env python3
"""Renders the looping battle theme asset (original work, CC0) from a fixed score.

Usage: python3 render_battle_theme.py out.wav   (then convert to OGG with ffmpeg -c:a libvorbis -q:a 4)
The score is deterministic: same script, same file. Edit NOTES/DRUMS below to change the tune.
"""
import sys
import numpy as np

RATE = 32000
BPM = 72
BEAT = 60.0 / BPM
BARS = 16
LOOP_SECONDS = BARS * 4 * BEAT
D = 73.42  # D2
# D dorian, semitone offsets from D2
SCALE = [0, 2, 3, 5, 7, 9, 10]


def freq(step, octave=0):
    return D * 2 ** ((SCALE[step % 7] + 12 * (step // 7) + 12 * octave) / 12)


# melody: (beat position, scale step relative to D3, length in beats)
MELODY = [
    (0, 0, 3), (3, 2, 1), (4, 4, 2), (6, 3, 2),
    (8, 2, 3), (11, 1, 1), (12, 0, 4),
    (16, 4, 2), (18, 5, 1), (19, 4, 1), (20, 2, 3), (23, 3, 1),
    (24, 1, 2), (26, 2, 2), (28, 0, 4),
    (32, 7, 3), (35, 5, 1), (36, 4, 2), (38, 2, 2),
    (40, 3, 3), (43, 2, 1), (44, 1, 4),
    (48, 4, 2), (50, 2, 2), (52, 1, 2), (54, 0, 2),
    (56, 2, 4), (60, 0, 4),
]
BASS_STEPS = [0, 0, 5, 3]  # per 4-bar phrase pattern of roots (D, D, G, F)


def env(n, attack, decay_to, sr=RATE):
    t = np.arange(n) / sr
    a = np.minimum(t / attack, 1.0)
    d = np.exp(-t * decay_to)
    return a * d


def add(buf, start, sig):
    i = int(start * RATE)
    n = min(len(sig), len(buf) - i)
    if n > 0:
        buf[i:i + n] += sig[:n]
    # wrap the tail so the loop is seamless
    rest = len(sig) - n
    if rest > 0:
        buf[:rest] += sig[n:n + rest]


def lowpass(x, cutoff):
    a = 1.0 - np.exp(-2 * np.pi * cutoff / RATE)
    y = np.empty_like(x)
    acc = 0.0
    for i, v in enumerate(x):
        acc += (v - acc) * a
        y[i] = acc
    return y


def main(out):
    n = int(LOOP_SECONDS * RATE)
    buf = np.zeros(n)
    # drone pad: D + A fifth, slow beating
    t = np.arange(n) / RATE
    # whole number of cycles per loop, so the pad has no seam at the loop point
    def periodic(f):
        return round(f * LOOP_SECONDS) / LOOP_SECONDS
    for f, g in [(D, 0.10), (D * 1.5, 0.07), (D * 2, 0.04)]:
        buf += g * (np.sin(2 * np.pi * periodic(f) * t) + 0.5 * np.sin(2 * np.pi * periodic(f * 1.004) * t))
    # bass notes
    for bar in range(BARS):
        root = BASS_STEPS[bar % 4]
        k = int(BEAT * 4 * RATE)
        tt = np.arange(k) / RATE
        sig = 0.20 * np.sin(2 * np.pi * freq(root) * tt) * env(k, 0.03, 0.7)
        add(buf, bar * 4 * BEAT, sig)
    # melody: soft saw through low-pass, like the old voice but with phrasing
    for beat, step, length in MELODY:
        dur = length * BEAT * 1.15
        k = int(dur * RATE)
        tt = np.arange(k) / RATE
        f = freq(step, 1)
        saw = 2 * ((tt * f) % 1.0) - 1.0
        sig = lowpass(saw, 900.0) * 0.16 * env(k, 0.05, 1.6 / max(length, 1))
        add(buf, beat * BEAT, sig)
    # drums: war drum on 1 and the "and" of 3, soft pick-up in the last bar of each phrase
    k = int(0.5 * RATE)
    tt = np.arange(k) / RATE
    sweep = 90 * (40 / 90) ** np.minimum(tt / 0.25, 1.0)
    phase = np.cumsum(sweep) / RATE
    drum = np.sin(2 * np.pi * phase) * env(k, 0.002, 9.0)
    for bar in range(BARS):
        add(buf, bar * 4 * BEAT, 0.55 * drum)
        add(buf, (bar * 4 + 2.5) * BEAT, 0.35 * drum)
        if bar % 4 == 3:
            add(buf, (bar * 4 + 3.5) * BEAT, 0.25 * drum)
    # echo (circular so it loops) + normalize
    delay = int(0.38 * RATE)
    out_buf = buf.copy()
    gain = 1.0
    for tap in range(1, 6):
        gain *= 0.45
        out_buf += gain * np.roll(buf, delay * tap)
    out_buf /= np.max(np.abs(out_buf)) / 0.6
    pcm = (out_buf * 32767).astype("<i2")
    import wave
    with wave.open(out, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(pcm.tobytes())
    print("loop %.1f s" % LOOP_SECONDS)


if __name__ == "__main__":
    main(sys.argv[1])
