"""Constants, path helpers and tunable thresholds for the pace ETL pipeline."""

from __future__ import annotations

import os
from collections import OrderedDict

GENERATOR = "tools/pace-data/build_pace_data.py"
GENERATOR_VERSION = "1.0.0"

# --- Source ------------------------------------------------------------------

BASE_URL = "https://pub-13135300967546fd87973feae3df0bdc.r2.dev"

SOURCE_FILES = OrderedDict(
    [
        ("planner_meta", "/planner_meta.json"),
        ("events_meta", "/events_meta.json"),
        ("weekly_index", "/weekly/index.json"),
    ]
)

DIVISION_PATH = "/planner_divisions/{slug}.json"

# Upstream division slug -> HyroxDivision rawValue used by the app.
DIVISION_MAP = OrderedDict(
    [
        ("PRO_MEN", "menProSingle"),
        ("PRO_WOMEN", "womenProSingle"),
        ("MEN", "menOpenSingle"),
        ("WOMEN", "womenOpenSingle"),
        ("PRO_MEN_DOUBLES", "menProDouble"),
        ("PRO_WOMEN_DOUBLES", "womenProDouble"),
        ("MEN_DOUBLES", "menOpenDouble"),
        ("WOMEN_DOUBLES", "womenOpenDouble"),
        ("MIXED", "mixedDouble"),
    ]
)

# Upstream divisions deliberately not shipped (no matching HyroxDivision case).
EXCLUDED_SLUGS = ("ADAPTIVE_MEN", "ADAPTIVE_WOMEN")

# Upstream station display name -> StationKind rawValue used by the app.
STATION_MAP = OrderedDict(
    [
        ("1000m SkiErg", "skiErg"),
        ("50m Sled Push", "sledPush"),
        ("50m Sled Pull", "sledPull"),
        ("80m Burpee Broad Jump", "burpeeBroadJumps"),
        ("1000m Row", "rowing"),
        ("200m Farmers Carry", "farmersCarry"),
        ("100m Sandbag Lunges", "sandbagLunges"),
        ("Wall Balls", "wallBalls"),
    ]
)

STATION_KEYS = tuple(STATION_MAP.values())
SLED_KEYS = ("sledPush", "sledPull")

# --- Thresholds --------------------------------------------------------------

#: Minimum athletes per published bucket. Tail buckets below this are merged
#: into a neighbour so that a single athlete can never be singled out.
MIN_CELL_N = 30

#: A bucket is "statistically dense" above this count. Monotonicity gates and
#: the spike repair only look at dense buckets; below it the long tail wobbles.
DENSE_MIN_N = 250

#: A station value that sits this many seconds above/below BOTH dense
#: neighbours is treated as contaminated and replaced by interpolation.
SPIKE_TOL_S = 10

#: Buckets whose |run_rox + stations - overall| exceeds this fraction of
#: avg_overall are dropped outright (upstream split data is unusable there).
BROKEN_RESIDUAL_RATIO = 0.05

#: Above this residual the bucket components are rescaled onto avg_overall.
RECONCILE_TOL_S = 15

#: Hard gate: |run_rox + stations - overall| must stay within this.
RESIDUAL_GATE_S = 30

#: Tolerance for sum(count) vs upstream total_athletes.
COUNT_TOTAL_TOL_ABS = 60
COUNT_TOTAL_TOL_RATIO = 0.001  # 0.1 %

#: Cross-division sled comparison: percentile band and slack in seconds.
#: Below p25 the Open field contains elite athletes who simply out-pull the
#: Pro field, so the ordering only has to hold across the dense middle.
CROSS_DIVISION_BAND = (25.0, 95.0)
CROSS_DIVISION_STEP = 5.0
CROSS_DIVISION_TOL_S = 3

#: Run + RoxZone distance in km (upstream avg_pace_8_7 == run_rox / 8.7).
RUN_ROX_DISTANCE_KM = 8.7

#: Age groups below this sample size are omitted from the v4 payload.
AGE_GROUP_MIN_N = 200

#: v4 percentile grids.
GRID_P = [0.1, 0.5] + [float(p) for p in range(1, 100)] + [99.5, 99.9]
AGE_GRID_P = [float(p) for p in range(5, 100, 5)]

BUCKET_SIZE_MIN = 5
V3_SCHEMA_VERSION = 3
V4_SCHEMA_VERSION = 4
MANIFEST_VERSION = 1

# --- Paths -------------------------------------------------------------------

TOOL_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
REPO_ROOT = os.path.dirname(os.path.dirname(TOOL_DIR))

CACHE_DIR = os.path.join(TOOL_DIR, ".cache")
REFERENCE_DIR = os.path.join(TOOL_DIR, "reference")
LEGACY_REFERENCE_PATH = os.path.join(REFERENCE_DIR, "legacy_v3_reference.json")

V3_OUTPUT_PATH = os.path.join(
    REPO_ROOT, "Targets", "HyroxCore", "Resources", "PaceReference", "pace_planner.json"
)
DOCS_PACE_DIR = os.path.join(REPO_ROOT, "docs", "pace")
V4_DIR = os.path.join(DOCS_PACE_DIR, "v4")
MANIFEST_PATH = os.path.join(DOCS_PACE_DIR, "manifest.json")


def division_url(slug):
    return BASE_URL + DIVISION_PATH.format(slug=slug)


def rel(path):
    """Repo-relative path (handoff notes must not carry absolute paths)."""
    return os.path.relpath(path, REPO_ROOT)
