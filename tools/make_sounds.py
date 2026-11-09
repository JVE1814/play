#!/usr/bin/env python3
"""Synthesises the app's original sound effects (short mono 16-bit WAVs).

Run from the repository root: python3 tools/make_sounds.py
"""
import math, os, random, struct, wave

RATE = 44100
OUT = os.path.join(os.path.dirname(__file__), "..", "Packages", "PlayKit", "Sources", "PlayKit", "Resources", "Sounds")


def write(name, samples):
    os.makedirs(OUT, exist_ok=True)
    peak = max(1e-9, max(abs(s) for s in samples))
    with wave.open(os.path.join(OUT, name + ".wav"), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(32767 * 0.8 * s / peak)) for s in samples))


def tone(freq, dur, decay=30.0, harmonics=(1.0, 0.3, 0.1), attack=0.004):
    n = int(RATE * dur)
    out = []
    for i in range(n):
        t = i / RATE
        env = min(1.0, t / attack) * math.exp(-decay * t)
        out.append(env * sum(a * math.sin(2 * math.pi * freq * (k + 1) * t) for k, a in enumerate(harmonics)))
    return out


def mix(*parts):
    length = max(len(p) for p, _ in parts) if parts else 0
    out = [0.0] * length
    for p, offset in parts:
        for i, s in enumerate(p):
            if i + offset < length:
                out[i + offset] += s
    return out


def pad(samples, total):
    return samples + [0.0] * max(0, total - len(samples))


random.seed(7)
# A soft wooden "tock" for placing a card.
click = [random.uniform(-1, 1) * math.exp(-180 * i / RATE) for i in range(int(RATE * 0.03))]
write("place", mix((tone(520, 0.09, decay=55, harmonics=(1, 0.2)), 0), ([c * 0.35 for c in click], 0)))
# A quick airy swish for drawing.
swish = [random.uniform(-1, 1) * math.sin(math.pi * i / (RATE * 0.07)) ** 2 for i in range(int(RATE * 0.07))]
write("draw", [s * 0.5 for s in swish])
# A gentle low double blip for "no move".
write("invalid", mix((tone(220, 0.08, decay=40), 0), (tone(196, 0.1, decay=40), int(RATE * 0.09))))
# A bright rising arpeggio for a win.
notes = [523.25, 659.25, 783.99, 1046.5]
write("win", pad(mix(*[(tone(f, 0.35, decay=9), int(RATE * 0.09 * k)) for k, f in enumerate(notes)]), int(RATE * 0.7)))
# A tiny tick for buttons.
write("tap", tone(880, 0.04, decay=90, harmonics=(1,)))
# A bowstring let go: a low plucked twang whose pitch settles as it rings, over a soft whoosh.
twang = []
for i in range(int(RATE * 0.22)):
    t = i / RATE
    phase = 2 * math.pi * 98 * (t + 0.35 * (1 - math.exp(-40 * t)) / 40)
    env = min(1.0, t / 0.002) * math.exp(-16 * t)
    twang.append(env * (math.sin(phase) + 0.5 * math.sin(2 * phase) + 0.25 * math.sin(3 * phase) + 0.12 * math.sin(5 * phase)))
whoosh = [random.uniform(-1, 1) * math.sin(math.pi * i / (RATE * 0.12)) ** 2 * 0.18 for i in range(int(RATE * 0.12))]
write("release", mix((twang, 0), (whoosh, 0)))
# An arrow into straw: a dull low thump with a short, muffled crunch.
thump = tone(82, 0.16, decay=28, harmonics=(1, 0.45, 0.15), attack=0.001)
crunch = []
level = 0.0
for i in range(int(RATE * 0.05)):
    level += 0.25 * (random.uniform(-1, 1) - level)  # a simple low-pass keeps it soft
    crunch.append(level * math.exp(-90 * i / RATE) * 1.6)
write("hit", mix((thump, 0), (crunch, 0)))
# A coin picked up: two bright notes, the second a fifth above.
write("coin", mix((tone(1318.5, 0.07, decay=38, harmonics=(1, 0.25)), 0),
                  (tone(1975.5, 0.13, decay=26, harmonics=(1, 0.2)), int(RATE * 0.045))))
# A jump: a short tone that slides up an octave.
jump = []
for i in range(int(RATE * 0.16)):
    t = i / RATE
    phase = 2 * math.pi * (250 * t + 250 * t * t / 0.32)
    jump.append(min(1.0, t / 0.005) * math.sin(math.pi * t / 0.16) * (math.sin(phase) + 0.2 * math.sin(2 * phase)))
write("jump", jump)
# Running into something: a heavy thud under a burst of clatter.
thud = tone(64, 0.3, decay=13, harmonics=(1, 0.5, 0.2), attack=0.001)
clatter = []
level = 0.0
for i in range(int(RATE * 0.2)):
    level += 0.45 * (random.uniform(-1, 1) - level)
    clatter.append(level * math.exp(-22 * i / RATE) * 1.3)
write("crash", mix((thud, 0), (clatter, 0)))
# A power-up: three quick rising notes.
write("powerUp", pad(mix(*[(tone(f, 0.18, decay=14, harmonics=(1, 0.3)), int(RATE * 0.06 * k))
                          for k, f in enumerate([659.25, 880.0, 1318.5])]), int(RATE * 0.34)))
print("wrote sounds to", os.path.abspath(OUT))
