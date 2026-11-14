#!/usr/bin/env python3
"""Listening-equivalent checks for Frontline music and SFX.

Prints normalized cross-correlation of the clean pad and the rejected themes against the
OpenFront transport-ship and conquered samples. A PLAY/BLOCK line from --audiotest is not
this measurement: this script decodes the files.
"""
import hashlib
import json
import subprocess
import sys
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[1]
SR = 22050


def dec(path: Path) -> np.ndarray:
    data = subprocess.check_output(
        ["ffmpeg", "-v", "error", "-i", str(path), "-ac", "1", "-ar", str(SR), "-f", "f32le", "-"]
    )
    return np.frombuffer(data, dtype=np.float32).astype(np.float64)


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    h.update(path.read_bytes())
    return h.hexdigest()


def ncc_max(hay: np.ndarray, needle: np.ndarray):
    n = needle - needle.mean()
    nn = np.linalg.norm(n)
    if nn < 1e-8 or hay.size <= needle.size:
        return 0.0, 0.0
    N = 1
    while N < hay.size + needle.size:
        N *= 2
    corr = np.fft.irfft(np.fft.rfft(hay, N) * np.conj(np.fft.rfft(n, N)), N)[: hay.size - needle.size + 1]
    hs = hay * hay
    csum = np.empty(hay.size + 1)
    csum[0] = 0.0
    np.cumsum(hs, out=csum[1:])
    w = n.size
    energy = np.sqrt(np.maximum(csum[w : w + corr.size] - csum[: corr.size], 1e-18))
    sc = corr / (energy * nn)
    i = int(np.argmax(sc))
    return float(sc[i]), i / SR


def main() -> int:
    boat = dec(ROOT / "sounds" / "transport-ship.mp3")
    conq = dec(ROOT / "sounds" / "conquered.mp3")
    # Loudest 2.0 s of each one-shot, which is the part a listener names.
    def head(x, sec=2.0):
        return x[: min(x.size, int(sec * SR))]

    tracks = {
        "pad": ROOT / "sounds" / "music" / "frontline_pad.ogg",
        "rejected_menu": ROOT / "sounds" / "rejected" / "roworld_menu.mp3",
        "rejected_war": ROOT / "sounds" / "rejected" / "roworld_war.mp3",
        "city_ambience": ROOT / "sounds" / "city.mp3",
    }
    report = {"sr": SR, "tracks": {}, "sfx_sha256": {}}
    needles = {"transport_ship_2s": head(boat), "conquered_2s": head(conq)}
    # Calibration: mix the real boat into a copy of the pad at known gains.
    pad = dec(tracks["pad"])
    # Tile the pad so the bed is longer than the needle.
    bed = np.tile(pad, 3)
    cal = {}
    for db in (0, -12, -24, -30):
        mix = bed.copy()
        g = 10 ** (db / 20.0)
        at = int(2 * SR)
        sl = needles["transport_ship_2s"]
        mix[at : at + sl.size] += g * sl
        score, t = ncc_max(mix, sl)
        cal[str(db)] = {"ncc": round(score, 4), "t": round(t, 3)}
    report["calibration_boat_mixed_into_pad_db"] = cal
    for name, path in tracks.items():
        hay = dec(path)
        entry = {
            "sha256": sha256(path),
            "seconds": round(hay.size / SR, 3),
            "rms": round(float(np.sqrt(np.mean(hay ** 2))), 4),
            "ncc": {},
        }
        for nk, nd in needles.items():
            score, t = ncc_max(hay, nd)
            entry["ncc"][nk] = {"max": round(score, 4), "at_s": round(t, 3)}
        report["tracks"][name] = entry
        print(f"{name:16} {entry['seconds']:7.2f}s rms={entry['rms']:.4f} "
              f"boat={entry['ncc']['transport_ship_2s']['max']:.3f} "
              f"conquer={entry['ncc']['conquered_2s']['max']:.3f}")
    print("calibration (boat mixed into pad):", cal)
    for p in sorted((ROOT / "sounds").glob("*.mp3")):
        report["sfx_sha256"][p.name] = sha256(p)
    out = ROOT / "docs" / "audio_measurements.json"
    out.parent.mkdir(exist_ok=True)
    out.write_text(json.dumps(report, indent=2) + "\n")
    print("wrote", out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
