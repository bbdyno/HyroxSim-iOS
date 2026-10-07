"""Download and cache the public planner JSON endpoints.

Only the static R2 bucket is used. results.hyrox.com is disallowed by its
robots.txt and is never contacted by this pipeline.
"""

from __future__ import annotations

import hashlib
import json
import os
import time
import urllib.error
import urllib.request

from . import config

USER_AGENT = "HyroxSim-pace-data/{v} (+repo tools/pace-data)".format(v=config.GENERATOR_VERSION)
CACHE_META_NAME = "_cache_meta.json"


class FetchError(RuntimeError):
    pass


def _cache_path(cache_dir, name):
    return os.path.join(cache_dir, name + ".json")


def _load_cache_meta(cache_dir):
    path = os.path.join(cache_dir, CACHE_META_NAME)
    if os.path.exists(path):
        try:
            with open(path, "r", encoding="utf-8") as fh:
                return json.load(fh)
        except (ValueError, OSError):
            return {}
    return {}


def _save_cache_meta(cache_dir, meta):
    path = os.path.join(cache_dir, CACHE_META_NAME)
    with open(path, "w", encoding="utf-8") as fh:
        json.dump(meta, fh, indent=2, sort_keys=True)
        fh.write("\n")


def _download(url, timeout):
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=timeout) as response:  # noqa: S310
        if getattr(response, "status", 200) != 200:
            raise FetchError("HTTP {s} for {u}".format(s=response.status, u=url))
        return response.read()


class Fetcher:
    """Caching fetcher. ``offline=True`` never touches the network."""

    def __init__(self, cache_dir=None, offline=False, timeout=180, log=print):
        self.cache_dir = cache_dir or config.CACHE_DIR
        self.offline = offline
        self.timeout = timeout
        self.log = log
        self.meta = _load_cache_meta(self.cache_dir)
        self.stats = {"downloaded": 0, "cached": 0, "bytes": 0}

    def get(self, name, url):
        """Return parsed JSON for ``url``, caching the raw bytes under ``name``."""
        path = _cache_path(self.cache_dir, name)
        if self.offline:
            if not os.path.exists(path):
                raise FetchError(
                    "--offline 이지만 캐시가 없습니다: {p} (먼저 온라인으로 1회 실행하세요)".format(
                        p=config.rel(path)
                    )
                )
            self.stats["cached"] += 1
            return self._read(path)

        os.makedirs(self.cache_dir, exist_ok=True)
        try:
            payload = _download(url, self.timeout)
        except (urllib.error.URLError, FetchError, OSError) as exc:
            if os.path.exists(path):
                self.log("  ! 다운로드 실패({e}) — 캐시 사용: {n}".format(e=exc, n=name))
                self.stats["cached"] += 1
                return self._read(path)
            raise FetchError("다운로드 실패 {u}: {e}".format(u=url, e=exc))

        digest = hashlib.sha256(payload).hexdigest()
        with open(path, "wb") as fh:
            fh.write(payload)
        self.meta[name] = {
            "url": url,
            "sha256": digest,
            "bytes": len(payload),
            "fetched_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        }
        _save_cache_meta(self.cache_dir, self.meta)
        self.stats["downloaded"] += 1
        self.stats["bytes"] += len(payload)
        return json.loads(payload.decode("utf-8"))

    def _read(self, path):
        with open(path, "rb") as fh:
            payload = fh.read()
        self.stats["bytes"] += len(payload)
        return json.loads(payload.decode("utf-8"))

    def cache_digest(self, name):
        entry = self.meta.get(name)
        if entry:
            return entry.get("sha256")
        path = _cache_path(self.cache_dir, name)
        if os.path.exists(path):
            with open(path, "rb") as fh:
                return hashlib.sha256(fh.read()).hexdigest()
        return None


def fetch_all(fetcher):
    """Fetch metadata + every mapped division. Returns a dict of raw payloads."""
    raw = {}
    for key, path in config.SOURCE_FILES.items():
        raw[key] = fetcher.get(key, config.BASE_URL + path)
    divisions = {}
    for slug in config.DIVISION_MAP:
        name = "planner_divisions_{s}".format(s=slug)
        divisions[slug] = fetcher.get(name, config.division_url(slug))
    raw["divisions"] = divisions
    return raw
