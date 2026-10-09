#!/usr/bin/env python3
"""Summarise HSTracker per-game performance logs (docs/perf-log.md).

Usage:
  scripts/perf-summary.py              # newest 20 games in ~/Library/Logs/HSTracker/perf
  scripts/perf-summary.py -n 50
  scripts/perf-summary.py FILE...      # specific files
"""
import argparse
import glob
import json
import os
import sys

PERF_DIR = os.path.expanduser("~/Library/Logs/HSTracker/perf")


def load(path):
    start, end, samples = {}, {}, []
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                rec = json.loads(line)
            except json.JSONDecodeError:
                continue
            ev = rec.get("event")
            if ev == "game_start":
                start = rec
            elif ev == "game_end":
                end = rec
            elif ev == "sample":
                samples.append(rec)
    return start, end, samples


def pct(values, p):
    if not values:
        return None
    s = sorted(values)
    return s[min(len(s) - 1, max(0, int((len(s) - 1) * p)))]


def fmt(v, unit=""):
    return "-" if v is None else f"{v:.1f}{unit}"


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("files", nargs="*")
    ap.add_argument("-n", type=int, default=20)
    args = ap.parse_args()

    files = args.files or sorted(glob.glob(os.path.join(PERF_DIR, "perf-*.jsonl")))[-args.n:]
    if not files:
        print(f"no perf logs in {PERF_DIR}", file=sys.stderr)
        return 1

    header = ("file", "build", "mode", "min", "cpu avg", "cpu p95", "mem start", "mem max",
              "refresh/s", "refresh ms/s", "lag p95", "gpu p95", "end")
    print("  ".join(header))
    for path in files:
        start, end, samples = load(path)
        cpu = [s["cpu_pct"] for s in samples if "cpu_pct" in s]
        mem = [s["footprint_mb"] for s in samples if "footprint_mb" in s]
        lag = [s["main_lag_ms"] for s in samples if "main_lag_ms" in s]
        gpu = [s["gpu_sys_pct"] for s in samples if "gpu_sys_pct" in s]
        n = max(len(samples), 1)
        refreshes = sum(s.get("refreshes", 0) for s in samples)
        refresh_ms = sum(s.get("refresh_ms", 0) for s in samples)
        duration = samples[-1]["t"] if samples else 0
        print("  ".join([
            os.path.basename(path),
            start.get("build", "?"),
            end.get("mode") or start.get("mode", "?"),
            f"{duration / 60:.1f}",
            fmt(sum(cpu) / len(cpu) if cpu else None, "%"),
            fmt(pct(cpu, 0.95), "%"),
            fmt(mem[0] if mem else None, "MB"),
            fmt(max(mem) if mem else None, "MB"),
            f"{refreshes / n:.2f}",
            f"{refresh_ms / n:.2f}",
            fmt(pct(lag, 0.95), "ms"),
            fmt(pct(gpu, 0.95), "%"),
            end.get("reason", "open"),
        ]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
