#!/usr/bin/env python3
"""Refresh UN/LOCODE from UNECE production archives; safe, offline when unavailable.

Only HTTPS on the official UNECE download host is allowed. Imports into the
existing SQLite catalog; failed downloads and invalid releases preserve data.
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import re
import sqlite3
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

from unlocode_store import SCHEMA, import_release

HOST = "service.unece.org"
MAX_DOWNLOAD = 32 * 1024 * 1024
MIN_ENTRIES = 50000


def candidates(now=None):
    year = (now or dt.datetime.now(dt.timezone.utc)).year
    # UNECE's production code archives follow locYYNcsv.zip. Prefer newest.
    # A failed/missing candidate is not an installation failure.
    for y in range(year, max(2023, year - 3), -1):
        for edition in (2, 1):
            yield f"https://{HOST}/trade/locode/loc{y % 100:02d}{edition}csv.zip"


class OfficialOnlyRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, fp, code, msg, headers, newurl):
        from urllib.parse import urlsplit
        parsed = urlsplit(newurl)
        if parsed.scheme != "https" or parsed.hostname != HOST or parsed.username:
            raise ValueError("UN/LOCODE redirect outside official UNECE host")
        return super().redirect_request(request, fp, code, msg, headers, newurl)


def fetch(url):
    from urllib.parse import urlsplit
    parsed = urlsplit(url)
    if parsed.scheme != "https" or parsed.hostname != HOST or parsed.username:
        raise ValueError("only official UNECE HTTPS releases are permitted")
    opener = urllib.request.build_opener(OfficialOnlyRedirect())
    req = urllib.request.Request(url, headers={"User-Agent": "Webmin-WireGuard-UNLOCODE/1"})
    with opener.open(req, timeout=20) as response:
        data = response.read(MAX_DOWNLOAD + 1)
    if len(data) > MAX_DOWNLOAD or not data.startswith(b"PK\x03\x04"):
        raise ValueError("UN/LOCODE download invalid or exceeds size limit")
    return data


def refresh(database, state, *, urls=None):
    state.mkdir(mode=0o700, parents=True, exist_ok=True)
    status_path = state / "unlocode-status.json"
    database = Path(database)
    if not database.is_absolute() or database.is_symlink() or not database.is_file():
        raise ValueError("analytics database must already exist at a safe absolute path")
    errors = []
    for url in (urls if urls is not None else candidates()):
        try:
            payload = fetch(url)
            digest = hashlib.sha256(payload).hexdigest()
            with tempfile.TemporaryDirectory(dir=state) as tmp:
                archive = Path(tmp) / "official.zip"
                archive.write_bytes(payload)
                # First validate a full release independently of the live database.
                staged = sqlite3.connect(":memory:")
                try:
                    staged.executescript(SCHEMA)
                    count = import_release(staged, archive)
                    if count < MIN_ENTRIES:
                        raise ValueError(f"partial UN/LOCODE release ({count} locations)")
                    with sqlite3.connect(database, timeout=30) as live:
                        live.executescript(SCHEMA)
                        # All-or-nothing replacement of the existing catalog.
                        live.execute("ATTACH DATABASE ':memory:' AS scratch")
                        # Use bulk rows from the validated staging database.
                        rows = staged.execute(
                            "SELECT country,code,name,ascii_name,subdivision,name_key,ascii_key "
                            "FROM unlocode_places").fetchall()
                        live.execute("DELETE FROM unlocode_places")
                        live.executemany(
                            "INSERT INTO unlocode_places "
                            "(country,code,name,ascii_name,subdivision,name_key,ascii_key) "
                            "VALUES(?,?,?,?,?,?,?)", rows)
                finally:
                    staged.close()
            status = {"updated_at": int(dt.datetime.now(dt.timezone.utc).timestamp()),
                      "entries": count, "release_url": url, "sha256": digest, "error": ""}
            tmp_status = status_path.with_suffix(".json.tmp")
            tmp_status.write_text(json.dumps(status), encoding="utf-8")
            os.chmod(tmp_status, 0o600)
            tmp_status.replace(status_path)
            return status
        except (OSError, ValueError, sqlite3.Error, urllib.error.URLError) as exc:
            errors.append(f"{url}: {str(exc)[:160]}")
    raise RuntimeError("No valid UNECE production release available: " + "; ".join(errors[-3:]))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("database", type=Path)
    parser.add_argument("state", type=Path)
    args = parser.parse_args()
    status = refresh(args.database, args.state)
    print(f"UN/LOCODE updated: {status['entries']} locations")


if __name__ == "__main__":
    main()
