#!/usr/bin/env python3
"""Generate all game audio procedurally (CC0, no external samples).
Usage: python3 tools/assets_gen/make_sounds.py   -> writes assets/audio/*.wav
Mono 16-bit 22.05 kHz. Every sound starts/ends at zero amplitude (no clicks);
loops (brush_loop, music_loop) are seamless."""
import math, os, random, struct, wave

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "assets", "audio")


def write(name, samples, peak=0.8):
    m = max(max(abs(s) for s in samples), 1e-9)
    g = peak / m
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "wb") as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s * g)) * 32767)) for s in samples))
    print(f"{name}.wav  {len(samples) / SR:.2f}s  {os.path.getsize(path) // 1024} KB")


def note(freq, dur, amp=1.0, decay=6.0, harm=(1.0,), attack=0.004, release=0.03):
    n = int(dur * SR)
    out = []
    for i in range(n):
        t = i / SR
        s = sum(h * math.sin(2 * math.pi * freq * (k + 1) * t) for k, h in enumerate(harm))
        e = math.exp(-decay * t) * min(1.0, t / attack) * min(1.0, (dur - t) / release)
        out.append(s * e * amp)
    return out


def mix(parts, total):
    out = [0.0] * int(total * SR)
    for start, samples in parts:
        o = int(start * SR)
        for i, s in enumerate(samples):
            if o + i < len(out):
                out[o + i] += s
    return out


def arp(freqs, gap, dur, decay, harm=(1.0, 0.35, 0.15)):
    parts = [(i * gap, note(f, dur, 0.7, decay, harm)) for i, f in enumerate(freqs)]
    return mix(parts, gap * len(freqs) + dur)


def brush_loop():
    rnd = random.Random(7)
    n, x = SR, SR // 20
    g, slow, fast = [], 0.0, 0.0
    for _ in range(n + x):
        v = rnd.uniform(-1, 1)
        fast += 0.22 * (v - fast)
        slow += 0.012 * (v - slow)
        g.append(fast - slow)
    out = [g[i] if i >= x else g[i] * (i / x) + g[n + i] * (1 - i / x) for i in range(n)]
    write("brush_loop", out, 0.6)


def music_loop():
    chords = [[110.0, 130.81, 164.81, 220.0], [87.31, 130.81, 174.61, 220.0],
              [98.0, 130.81, 164.81, 196.0], [98.0, 123.47, 146.83, 196.0]]
    seg = 4.0
    out = []
    for ci, chord in enumerate(chords):
        for i in range(int(seg * SR)):
            t = i / SR
            env = math.sin(math.pi * t / seg) ** 2
            s = 0.0
            for f in chord:
                s += math.sin(2 * math.pi * f * t) + 0.4 * math.sin(2 * math.pi * f * 2.003 * t) \
                    + 0.15 * math.sin(2 * math.pi * f * 3.01 * t)
            bell = math.sin(2 * math.pi * chord[(ci + int(t / 2)) % 4] * 4 * t) * math.exp(-3 * (t % 2)) * 0.25
            out.append((s * 0.18 + bell) * env)
    write("music_loop", out, 0.5)


def main():
    os.makedirs(OUT, exist_ok=True)
    write("ui_tap", note(1200, 0.07, 1.0, 45, (1.0, 0.3)), 0.5)
    write("buy", mix([(0, note(660, 0.16, 0.8, 9, (1.0, 0.3))), (0.09, note(990, 0.24, 0.8, 8, (1.0, 0.3)))], 0.35), 0.6)
    write("coin_tick", note(1568, 0.07, 1.0, 50, (1.0, 0.5)), 0.5)
    write("reveal_common", arp([523.25, 659.25], 0.09, 0.5, 7))
    write("reveal_uncommon", arp([523.25, 659.25, 783.99], 0.09, 0.55, 6.5))
    write("reveal_rare", arp([523.25, 659.25, 783.99, 1046.5], 0.08, 0.7, 5, (1.0, 0.4, 0.2, 0.1)))
    chord = [261.63, 329.63, 392.0, 523.25, 659.25]
    write("reveal_epic", mix([(0.0, note(f, 1.5, 0.5, 2.6, (1.0, 0.4, 0.2), 0.05, 0.3)) for f in chord], 1.5))
    run = [392.0, 523.25, 659.25, 783.99, 1046.5]
    big = [523.25, 659.25, 783.99, 1046.5, 1318.5]
    parts = [(i * 0.11, note(f, 0.5, 0.5, 6, (1.0, 0.4, 0.2))) for i, f in enumerate(run)]
    parts += [(0.7, note(f, 2.4, 0.45, 1.5, (1.0, 0.5, 0.25, 0.12), 0.02, 0.5)) for f in big]
    write("reveal_legendary", mix(parts, 3.1))
    brush_loop()
    music_loop()


if __name__ == "__main__":
    main()
