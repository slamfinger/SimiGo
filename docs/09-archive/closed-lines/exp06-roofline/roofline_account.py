#!/usr/bin/env python3
"""SimiGo 2.0 Track A: Roofline accounting.

Input CSV columns:
  kernel,measured_ms,actual_bytes

Required model arguments describe a causal GQA workload. The K/V formula is a
theoretical lower bound; Instruments actual traffic remains authoritative for
the measured kernel.

No production SimiGo code is imported or modified.
"""

import argparse
import csv
import math
from pathlib import Path


def kv_lower_bound_bytes(layers, tokens, kv_heads, head_dim, element_bytes):
    pairs = tokens * (tokens + 1) // 2
    return layers * pairs * kv_heads * head_dim * 2 * element_bytes


def classify(ratio):
    if ratio <= 1.5:
        return "CLOSE"
    if ratio >= 3.0:
        return "OPEN"
    return "MIDDLE"


def main():
    p = argparse.ArgumentParser()
    p.add_argument("--csv", required=True, type=Path)
    p.add_argument("--layers", required=True, type=int)
    p.add_argument("--tokens", required=True, type=int)
    p.add_argument("--kv-heads", required=True, type=int)
    p.add_argument("--head-dim", required=True, type=int)
    p.add_argument("--element-bytes", required=True, type=float)
    p.add_argument("--peak-bandwidth-gbs", required=True, type=float)
    args = p.parse_args()

    lower = kv_lower_bound_bytes(
        args.layers, args.tokens, args.kv_heads, args.head_dim, args.element_bytes
    )
    floor_ms = lower / (args.peak_bandwidth_gbs * 1e9) * 1e3

    print(f"theoretical_KV_lower_bound_bytes={lower}")
    print(f"theoretical_floor_ms={floor_ms:.6f}")
    print("kernel,measured_ms,actual_bytes,actual_gbs,ratio_to_floor,decision")

    with args.csv.open(newline="") as f:
        for row in csv.DictReader(f):
            measured_ms = float(row["measured_ms"])
            actual_bytes = float(row["actual_bytes"])
            actual_gbs = actual_bytes / (measured_ms / 1000.0) / 1e9
            ratio = measured_ms / floor_ms if floor_ms else math.inf
            print(
                f'{row["kernel"]},{measured_ms:.6f},{actual_bytes:.0f},'
                f'{actual_gbs:.3f},{ratio:.3f},{classify(ratio)}'
            )


if __name__ == "__main__":
    main()
