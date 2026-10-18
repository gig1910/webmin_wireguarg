#!/usr/bin/env python3
"""Import official UNECE UN/LOCODE CSV/ZIP data into module analytics DB.

Usage: python3 scripts/import-unlocode.py /absolute/analytics.sqlite3 /path/to/unece.zip
No network calls, no modification to WHOIS observations or manual network icons.
"""
import argparse
import os
import sqlite3
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))
from unlocode_store import SCHEMA, import_release  # noqa: E402

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("database", type=Path)
    parser.add_argument("release", type=Path)
    args = parser.parse_args()
    if not args.database.is_absolute() or args.database.is_symlink():
        parser.error("database must be an absolute, non-symlink path")
    if not args.database.is_file():
        parser.error("analytics database must already exist")
    conn = sqlite3.connect(args.database)
    try:
        conn.executescript(SCHEMA)
        count = import_release(conn, args.release)
    finally:
        conn.close()
    print(f"UN/LOCODE: imported {count} entries")
if __name__ == "__main__":
    main()
