#!/usr/bin/env python3
"""Tổng hợp toàn bộ âm thanh của game (chiptune) thành file WAV, không cần thư viện ngoài.

Chạy:  python3 tools/gen_audio.py     ->  assets/audio/*.wav
"""
import math
import os
import random
import struct
import wave

SR = 22050
OUT = os.path.join(os.path.dirname(__file__), '..', 'assets', 'audio')
random.seed(7)


def hz(note):
    """note = số nửa cung so với A4 (A4 = 0)."""
    return 440.0 * 2 ** (note / 12.0)


# Tên nốt -> nửa cung so với A4
N = {'C': -9, 'D': -7, 'E': -5, 'F': -4, 'G': -2, 'A': 0, 'B': 2}


def n(name, octave=4):
    return N[name] + (octave - 4) * 12


def osc(kind, phase, duty=0.5):
    p = phase % 1.0
    if kind == 'sine':
        return math.sin(2 * math.pi * p)
    if kind == 'square':
        return 1.0 if p < duty else -1.0
    if kind == 'tri':
        return 4 * abs(p - 0.5) - 1
    if kind == 'saw':
        return 2 * p - 1
    raise ValueError(kind)


def env(t, dur, a=0.005, r=0.08):
    if t < a:
        return t / a
    if t > dur - r:
        return max(0.0, (dur - t) / r)
    return 1.0


def tone(freq, dur, kind='square', vol=0.5, a=0.004, r=0.06, duty=0.5, slide=0.0, vib=0.0, vib_hz=7.0, decay=0.0):
    """Một nốt. slide = tổng số nửa cung trượt trong suốt nốt; decay = tắt dần theo hàm mũ."""
    out = []
    phase = 0.0
    total = int(dur * SR)
    for i in range(total):
        t = i / SR
        f = freq * 2 ** ((slide * t / dur) / 12.0)
        if vib:
            f *= 2 ** ((vib * math.sin(2 * math.pi * vib_hz * t)) / 12.0)
        phase += f / SR
        e = env(t, dur, a, r)
        if decay:
            e *= math.exp(-decay * t)
        out.append(osc(kind, phase, duty) * vol * e)
    return out


def noise(dur, vol=0.5, lp=0.3, decay=6.0, a=0.002):
    """Nhiễu trắng qua lọc thông thấp một cực, tắt dần."""
    out = []
    y = 0.0
    for i in range(int(dur * SR)):
        t = i / SR
        y += lp * (random.uniform(-1, 1) - y)
        out.append(y * vol * math.exp(-decay * t) * min(1.0, t / a if a else 1.0))
    return out


def mix(*tracks, offsets=None):
    offsets = offsets or [0.0] * len(tracks)
    length = max(int(o * SR) + len(t) for t, o in zip(tracks, offsets))
    out = [0.0] * length
    for t, o in zip(tracks, offsets):
        s = int(o * SR)
        for i, v in enumerate(t):
            out[s + i] += v
    return out


def seq(notes):
    """notes = [(freq, dur, kwargs)] nối tiếp nhau."""
    out = []
    for f, d, kw in notes:
        out += tone(f, d, **kw)
    return out


def save(name, samples, gain=1.0, peak=0.92):
    m = max(1e-9, max(abs(v) for v in samples))
    scale = min(gain, peak / m) if gain else peak / m
    path = os.path.join(OUT, name + '.wav')
    with wave.open(path, 'wb') as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(b''.join(struct.pack('<h', int(max(-1, min(1, v * scale)) * 32767)) for v in samples))
    print(f'{name:14s} {len(samples) / SR:5.2f}s  {os.path.getsize(path) // 1024} KB')


def gen_sfx():
    # Hứng trái: nốt tăng dần theo combo (thang ngũ cung), nghe như "pop-ding".
    scale = [n('C', 5), n('D', 5), n('E', 5), n('G', 5), n('A', 5), n('C', 6), n('D', 6), n('E', 6)]
    for i, note in enumerate(scale):
        f = hz(note)
        pop = tone(f * 0.5, 0.05, 'sine', 0.5, slide=12, r=0.02)
        ding = tone(f, 0.16, 'square', 0.28, duty=0.25, decay=9, r=0.05)
        ding2 = tone(f * 2, 0.12, 'sine', 0.2, decay=12, r=0.04)
        save(f'catch_{i}', mix(pop, ding, ding2, offsets=[0, 0.02, 0.02]))

    # Dưa hấu / bonus: "ka-ching"
    save('bonus', mix(
        tone(hz(n('E', 6)), 0.09, 'square', 0.3, duty=0.25, decay=8),
        tone(hz(n('A', 6)), 0.28, 'square', 0.3, duty=0.25, decay=6),
        tone(hz(n('A', 7)), 0.2, 'sine', 0.15, decay=10),
        offsets=[0, 0.08, 0.08]))

    # Bom: thịch + nổ
    boom = mix(
        tone(70, 0.5, 'sine', 0.9, slide=-24, decay=5, r=0.2),
        noise(0.55, 0.9, lp=0.25, decay=5),
        noise(0.12, 0.7, lp=0.9, decay=30))
    save('bomb', boom)

    # Ớt: "Á cay!" - tiếng rít xuống có rung
    save('chili', mix(
        tone(hz(n('A', 5)), 0.45, 'saw', 0.3, slide=-14, vib=1.5, vib_hz=14, decay=2.5, r=0.15),
        noise(0.25, 0.25, lp=0.7, decay=9)))

    # Tim: arpeggio lấp lánh
    save('heart', seq([
        (hz(n('C', 5)), 0.08, dict(kind='square', vol=0.3, duty=0.25, decay=6)),
        (hz(n('E', 5)), 0.08, dict(kind='square', vol=0.3, duty=0.25, decay=6)),
        (hz(n('G', 5)), 0.08, dict(kind='square', vol=0.3, duty=0.25, decay=6)),
        (hz(n('C', 6)), 0.30, dict(kind='square', vol=0.3, duty=0.25, decay=5, r=0.1)),
    ]))

    # Skill há miệng: whoosh lên rồi "nom nom" chord
    whoosh = tone(180, 0.45, 'saw', 0.28, slide=34, a=0.05, r=0.05)
    air = noise(0.45, 0.3, lp=0.5, decay=-0.0, a=0.2)
    chord = mix(
        tone(hz(n('C', 5)), 0.5, 'square', 0.22, duty=0.25, decay=5),
        tone(hz(n('E', 5)), 0.5, 'square', 0.22, duty=0.25, decay=5),
        tone(hz(n('G', 5)), 0.5, 'square', 0.22, duty=0.25, decay=5),
        tone(hz(n('C', 6)), 0.5, 'sine', 0.3, decay=4))
    save('skill', mix(whoosh, air, chord, offsets=[0, 0, 0.42]))

    # Mốc combo: chạy nốt lên nhanh
    save('combo', seq([
        (hz(n(x, o)), 0.06, dict(kind='square', vol=0.3, duty=0.25, decay=5))
        for x, o in [('C', 5), ('E', 5), ('G', 5), ('C', 6), ('E', 6), ('G', 6)]
    ] + [(hz(n('C', 7)), 0.25, dict(kind='square', vol=0.3, duty=0.25, decay=4, r=0.1))]))

    # Lên level: fanfare
    save('levelup', mix(
        seq([
            (hz(n('C', 5)), 0.11, dict(kind='square', vol=0.3, duty=0.5)),
            (hz(n('C', 5)), 0.11, dict(kind='square', vol=0.3, duty=0.5)),
            (hz(n('G', 5)), 0.11, dict(kind='square', vol=0.3, duty=0.5)),
            (hz(n('C', 6)), 0.45, dict(kind='square', vol=0.3, duty=0.5, vib=0.2, r=0.15)),
        ]),
        seq([
            (hz(n('E', 4)), 0.33, dict(kind='tri', vol=0.4)),
            (hz(n('G', 4)), 0.45, dict(kind='tri', vol=0.4, r=0.15)),
        ])))

    # Game over: "wah wah wah wahhh"
    save('gameover', seq([
        (hz(n('G', 4)), 0.28, dict(kind='saw', vol=0.3, vib=0.5, vib_hz=6, r=0.05)),
        (hz(n('F', 4) + 1), 0.28, dict(kind='saw', vol=0.3, vib=0.5, vib_hz=6, r=0.05)),
        (hz(n('F', 4)), 0.28, dict(kind='saw', vol=0.3, vib=0.5, vib_hz=6, r=0.05)),
        (hz(n('E', 4)), 0.9, dict(kind='saw', vol=0.3, slide=-3, vib=1.0, vib_hz=7, r=0.3)),
    ]))

    # Kỷ lục mới: nhạc chiến thắng
    notes = [('C', 5, .1), ('E', 5, .1), ('G', 5, .1), ('C', 6, .18), ('G', 5, .1), ('C', 6, .1), ('E', 6, .1), ('G', 6, .55)]
    save('newbest', mix(
        seq([(hz(n(x, o)), d, dict(kind='square', vol=0.28, duty=0.25, r=0.05)) for x, o, d in notes]),
        seq([(hz(n(x, o - 1)), d, dict(kind='tri', vol=0.35, r=0.05)) for x, o, d in notes])))

    # Đếm ngược
    save('tick', tone(hz(n('A', 5)), 0.09, 'square', 0.35, duty=0.5, r=0.03))
    save('go', mix(tone(hz(n('E', 6)), 0.3, 'square', 0.3, duty=0.25, decay=3, r=0.1),
                   tone(hz(n('A', 5)), 0.3, 'sine', 0.3, decay=3, r=0.1)))

    # Tạm dừng / tiếp tục
    save('pause', seq([(hz(n('E', 5)), 0.08, dict(kind='square', vol=0.3, duty=0.25)),
                       (hz(n('A', 4)), 0.14, dict(kind='square', vol=0.3, duty=0.25, r=0.06))]))
    save('resume', seq([(hz(n('A', 4)), 0.08, dict(kind='square', vol=0.3, duty=0.25)),
                        (hz(n('E', 5)), 0.14, dict(kind='square', vol=0.3, duty=0.25, r=0.06))]))

    # Bấm nút
    save('click', mix(tone(hz(n('A', 5)), 0.045, 'square', 0.3, duty=0.25, r=0.02),
                      noise(0.02, 0.2, lp=0.9, decay=40)))


def gen_music():
    """Nhạc nền ~29s, loop: C - Am - F - G, 132 bpm, bass tam giác + arpeggio + giai điệu ngũ cung + hi-hat."""
    bpm = 132
    beat = 60.0 / bpm
    bars = 16
    total = int(bars * 4 * beat * SR)
    buf = [0.0] * total

    def put(track, t0):
        s = int(t0 * SR)
        for i, v in enumerate(track):
            if s + i < total:
                buf[s + i] += v

    chords = [('C', ['C', 'E', 'G']), ('A', ['A', 'C', 'E']), ('F', ['F', 'A', 'C']), ('G', ['G', 'B', 'D'])]
    # Giai điệu: mỗi ô nhịp 8 nốt móc đơn (tên nốt, quãng tám) hoặc None = nghỉ
    A = [
        [('E', 5), None, ('G', 5), ('E', 5), ('C', 5), None, ('D', 5), ('E', 5)],
        [('A', 5), None, ('G', 5), ('E', 5), ('C', 5), ('E', 5), None, ('G', 5)],
        [('A', 5), ('G', 5), ('E', 5), None, ('F', 5), ('A', 5), ('C', 6), None],
        [('D', 6), None, ('B', 5), ('G', 5), ('D', 5), None, ('G', 5), None],
    ]
    B = [
        [('G', 5), ('G', 5), ('E', 5), ('G', 5), ('A', 5), None, ('G', 5), ('E', 5)],
        [('E', 5), ('A', 5), ('C', 6), ('A', 5), ('E', 5), None, ('A', 5), None],
        [('F', 5), ('A', 5), ('C', 6), ('A', 5), ('F', 5), ('A', 5), ('C', 6), ('D', 6)],
        [('E', 6), None, ('D', 6), ('B', 5), ('G', 5), ('B', 5), ('D', 6), None],
    ]
    pattern = [A, A, B, A]  # 4 đoạn x 4 ô nhịp = 16 ô nhịp

    for bar in range(bars):
        root, tones = chords[bar % 4]
        t0 = bar * 4 * beat
        section = pattern[bar // 4][bar % 4]
        # Bass: gốc ở nhịp 1, quãng 5 ở nhịp 3, đánh móc
        for b in range(8):
            note = n(root, 2) if b % 4 in (0, 1) else n(tones[2], 2)
            if b % 2 == 0 or b == 7:
                put(tone(hz(note), beat * 0.45, 'tri', 0.40, r=0.03, decay=2), t0 + b * beat / 2)
        # Arpeggio nền (square 12.5%)
        for k in range(16):
            tn = tones[k % 3]
            put(tone(hz(n(tn, 4) + (12 if k % 6 >= 3 else 0)), beat / 4 * 0.8, 'square', 0.07, duty=0.125, r=0.02, decay=3),
                t0 + k * beat / 4)
        # Giai điệu
        for k, item in enumerate(section):
            if item:
                x, o = item
                put(tone(hz(n(x, o)), beat / 2 * 0.9, 'square', 0.16, duty=0.25, r=0.04, vib=0.12, decay=2),
                    t0 + k * beat / 2)
        # Trống: kick nhịp 1&3, hi-hat nhịp lẻ
        for b in range(4):
            if b in (0, 2):
                put(tone(120, 0.12, 'sine', 0.55, slide=-20, decay=14, r=0.03), t0 + b * beat)
            put(noise(0.04, 0.16, lp=0.9, decay=60), t0 + b * beat + beat / 2)
            if b in (1, 3):
                put(noise(0.1, 0.22, lp=0.6, decay=25), t0 + b * beat)

    save('music', buf, gain=0.0, peak=0.85)


if __name__ == '__main__':
    os.makedirs(OUT, exist_ok=True)
    gen_sfx()
    gen_music()
