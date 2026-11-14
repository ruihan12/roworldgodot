#!/usr/bin/env python3
"""Build the clean music bed and PCM copies of the OpenFront effects.

Music is original (not the rejected themes). Effect WAVs are 16-bit PCM of the
CC BY-SA mp3s so playback does not depend on the MP3 importer or a .godot cache.
"""
import subprocess
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SR = 44100


def write_wav(path: Path, samples: np.ndarray, sr: int = SR) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    pcm = np.clip(samples, -1.0, 1.0)
    ints = (pcm * 32767.0).astype(np.int16)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(ints.tobytes())


def snap(freq: float, dur: float) -> float:
    return max(1, int(round(freq * dur))) / dur


def build_bed() -> None:
    dur = 24.0
    n = int(SR * dur)
    t = np.arange(n, dtype=np.float64) / SR

    def tone(freq: float, amp: float) -> np.ndarray:
        f = snap(freq, dur)
        return amp * np.sin(2.0 * np.pi * f * t)

    def ring(center: float, width: float) -> np.ndarray:
        d = (t - center + dur / 2.0) % dur - dur / 2.0
        x = np.clip(1.0 - np.abs(d) / width, 0.0, 1.0)
        return x * x * (3.0 - 2.0 * x)

    chords = [
        (0.0, [(110.00, 0.09), (164.81, 0.05), (220.00, 0.07), (261.63, 0.045), (329.63, 0.03)]),
        (6.0, [(87.31, 0.08), (130.81, 0.05), (174.61, 0.07), (220.00, 0.05), (261.63, 0.03)]),
        (12.0, [(130.81, 0.08), (196.00, 0.045), (261.63, 0.065), (329.63, 0.04), (392.00, 0.025)]),
        (18.0, [(98.00, 0.085), (146.83, 0.05), (196.00, 0.065), (246.94, 0.04), (293.66, 0.028)]),
    ]
    acc = np.zeros(n, dtype=np.float64)
    for center, notes in chords:
        env = ring(center, 5.2)
        for freq, amp in notes:
            acc += tone(freq, amp) * env
    # A repeating figure. Envelopes are periodic over `dur`, and every sine
    # completes an integer number of cycles, so sample 0 continues sample -1.
    figure = [220.00, 261.63, 329.63, 392.00, 329.63, 261.63, 293.66, 246.94]
    step = 0.75
    for i in range(int(dur / step)):
        center = (i + 0.5) * step
        d = (t - center + dur / 2.0) % dur - dur / 2.0
        u = (d + 0.04) / 0.62
        env = np.where((u > 0.0) & (u < 1.0), np.sin(np.pi * np.clip(u, 0.0, 1.0)) ** 2, 0.0)
        acc += tone(figure[i % len(figure)], 0.035) * env
    trem = 0.86 + 0.14 * np.sin(2.0 * np.pi * snap(2.0 / dur, dur) * t)
    acc *= trem
    peak = float(np.max(np.abs(acc)))
    acc *= 0.20 / max(peak, 1e-8)
    step_med = float(np.median(np.abs(np.diff(acc))))
    edge = float(abs(acc[0] - acc[-1]))
    print(f"bed peak={float(np.max(np.abs(acc))):.3f} rms={float(np.sqrt(np.mean(acc*acc))):.4f} edge={edge:.6f} median_step={step_med:.6f}")
    if edge > step_med * 8:
        raise SystemExit("music loop boundary is a click")
    write_wav(ROOT / "sounds" / "music" / "frontline_bed.wav", acc.astype(np.float32))


def build_order() -> None:
    n = int(SR * 0.16)
    t = np.arange(n, dtype=np.float64) / SR
    env = np.sin(np.pi * t / t[-1]) ** 2
    y = (0.35 * np.sin(2 * np.pi * 523.25 * t) + 0.22 * np.sin(2 * np.pi * 659.25 * t)) * env
    y *= 0.45 / max(float(np.max(np.abs(y))), 1e-8)
    write_wav(ROOT / "sounds" / "play" / "order.wav", y.astype(np.float32))


def convert_effects() -> None:
    src = ROOT / "sounds"
    dst = ROOT / "sounds" / "play"
    dst.mkdir(parents=True, exist_ok=True)
    names = [
        "click", "click-1", "click-2", "click-3", "slider", "game-start", "spawn",
        "atom-launch", "hydrogen-launch", "mirv-launch", "atom-hit", "hydrogen-hit",
        "nuke-warning", "sam-shoot", "sam-hit", "build-city", "build-port", "build-factory",
        "build-defense-post", "sam-built", "silo-built", "build-warship", "build-train-station",
        "warship-shot", "warship-lost", "transport-ship", "conquered", "ka-ching",
        "alliance-suggested", "alliance-accepted", "alliance-declined", "alliance-broken",
        "victory", "defeat",
    ]
    for name in names:
        mp3 = src / f"{name}.mp3"
        wav = dst / f"{name}.wav"
        subprocess.check_call([
            "ffmpeg", "-y", "-v", "error", "-i", str(mp3),
            "-ac", "1", "-ar", str(SR), "-c:a", "pcm_s16le", str(wav),
        ])
        print("wav", name, wav.stat().st_size)


if __name__ == "__main__":
    build_bed()
    build_order()
    convert_effects()
