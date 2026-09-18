"""Small numeric helpers (stdlib only): quantiles, isotonic fit, rounding."""

from __future__ import annotations

import math


def quantile_type7(sorted_values, p):
    """Empirical quantile, R/numpy "type 7" definition.

    ``sorted_values`` must be sorted ascending, ``p`` is a percentile in 0..100.
    """
    n = len(sorted_values)
    if n == 0:
        raise ValueError("quantile of an empty sample")
    if n == 1:
        return float(sorted_values[0])
    h = (n - 1) * (p / 100.0)
    lo = int(math.floor(h))
    hi = min(lo + 1, n - 1)
    frac = h - lo
    return float(sorted_values[lo]) + frac * (float(sorted_values[hi]) - float(sorted_values[lo]))


def isotonic(values, weights=None):
    """Weighted isotonic (non-decreasing) regression via pool-adjacent-violators."""
    n = len(values)
    if n == 0:
        return []
    if weights is None:
        weights = [1.0] * n
    # block = [value, weight, size]
    blocks = []
    for value, weight in zip(values, weights):
        w = float(weight) if weight > 0 else 1e-9
        blocks.append([float(value), w, 1])
        while len(blocks) > 1 and blocks[-2][0] > blocks[-1][0]:
            v2, w2, n2 = blocks.pop()
            v1, w1, n1 = blocks.pop()
            blocks.append([(v1 * w1 + v2 * w2) / (w1 + w2), w1 + w2, n1 + n2])
    out = []
    for value, _weight, size in blocks:
        out.extend([value] * size)
    return out


def interp_series(xs, ys, x):
    """Linear interpolation over (xs, ys) with flat extrapolation at both ends."""
    if not xs:
        raise ValueError("empty series")
    if len(xs) == 1 or x <= xs[0]:
        return float(ys[0])
    if x >= xs[-1]:
        return float(ys[-1])
    lo, hi = 0, len(xs) - 1
    while hi - lo > 1:
        mid = (lo + hi) // 2
        if xs[mid] <= x:
            lo = mid
        else:
            hi = mid
    span = xs[hi] - xs[lo]
    if span <= 0:
        return float(ys[lo])
    t = (x - xs[lo]) / span
    return float(ys[lo]) + t * (float(ys[hi]) - float(ys[lo]))


def largest_remainder(values, total):
    """Scale ``values`` so their integer parts sum exactly to ``total``.

    Uses the largest-remainder (Hare) method, ties broken by index so the
    result is deterministic.
    """
    n = len(values)
    if n == 0:
        return []
    total = int(total)
    s = float(sum(values))
    if s <= 0:
        base = total // n
        out = [base] * n
        for i in range(total - base * n):
            out[i] += 1
        return out
    scaled = [max(0.0, float(v) * total / s) for v in values]
    floors = [int(math.floor(x)) for x in scaled]
    remainder = total - sum(floors)
    if remainder > 0:
        order = sorted(range(n), key=lambda i: (-(scaled[i] - floors[i]), i))
        for k in range(remainder):
            floors[order[k % n]] += 1
    elif remainder < 0:
        order = sorted(range(n), key=lambda i: (scaled[i] - floors[i], i))
        for k in range(-remainder):
            idx = order[k % n]
            if floors[idx] > 0:
                floors[idx] -= 1
    return floors


def round_half_up(x):
    """Deterministic rounding (Python's banker rounding is surprising here)."""
    return int(math.floor(float(x) + 0.5))


def strictly_increasing(values):
    """Bump integer values so the sequence strictly increases (min +1 steps)."""
    out = []
    previous = None
    for v in values:
        v = int(v)
        if previous is not None and v <= previous:
            v = previous + 1
        out.append(v)
        previous = v
    return out
