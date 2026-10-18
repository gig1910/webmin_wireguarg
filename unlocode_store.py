"""Offline UN/LOCODE catalog. Codes are official only when uniquely matched.

Catalog is installed from the UNECE downloadable 12-column CSV release.
No geolocation or external requests occur here.
"""
import csv
import re
import unicodedata
import zipfile
from pathlib import Path

SCHEMA = """
CREATE TABLE IF NOT EXISTS unlocode_places (
 country TEXT NOT NULL, code TEXT NOT NULL, name TEXT NOT NULL,
 ascii_name TEXT NOT NULL, subdivision TEXT NOT NULL DEFAULT '',
 name_key TEXT NOT NULL DEFAULT '', ascii_key TEXT NOT NULL DEFAULT '',
 PRIMARY KEY(country,code)
);
CREATE INDEX IF NOT EXISTS unlocode_country ON unlocode_places(country);
CREATE INDEX IF NOT EXISTS unlocode_names ON unlocode_places(country,name_key);
CREATE INDEX IF NOT EXISTS unlocode_ascii_names ON unlocode_places(country,ascii_key);
"""

ALIASES = {
    ("RU", "moscow"): "moskva",
    ("RU", "saint petersburg"): "sankt peterburg",
    ("RU", "st petersburg"): "sankt peterburg",
}

def normalize(name):
    value = unicodedata.normalize("NFKD", str(name or "").casefold())
    return re.sub(r"[^a-z0-9]+", " ", "".join(
        c for c in value if not unicodedata.combining(c))).strip()

def lookup(conn, country, city, subdivision=""):
    if not re.fullmatch(r"[A-Z]{2}", country or "") or not city:
        return ""
    wanted = normalize(city)
    alias = ALIASES.get((country, wanted))
    accepted = {wanted, alias} - {None, ""}
    matches = []
    for key in accepted:
        matches.extend(conn.execute(
            "SELECT code,subdivision FROM unlocode_places "
            "WHERE country=? AND (name_key=? OR ascii_key=?)",
            (country,key,key)).fetchall())
    if subdivision:
        matches = [(code,region) for code,region in matches
                   if region.upper() == subdivision.upper()]
    # No guess when multiple distinct locations share a name.
    codes = set(code for code,_ in matches)
    return country + next(iter(codes)) if len(codes) == 1 else ""

def import_release(conn, file_path):
    """Replace the catalog atomically from official split-column CSV files."""
    path = Path(file_path)
    if path.is_dir():
        sources = [(p.name, p.read_bytes()) for p in sorted(path.glob("*.csv"))]
    elif path.suffix.lower() == ".zip":
        # The published production artifact may itself contain ZIP bundles.
        import io
        def csv_members(payload, depth=0):
            with zipfile.ZipFile(io.BytesIO(payload)) as bundle:
                members = bundle.infolist()
                if len(members) > 128 or sum(x.file_size for x in members) > 100*1024*1024:
                    raise ValueError("UN/LOCODE archive exceeds safe extraction limit")
                result = []
                for info in members:
                    name = info.filename.lower().replace(" ", "")
                    if "codelistpart" in name and name.endswith(".csv"):
                        if info.file_size > 32*1024*1024:
                            raise ValueError("Oversized UN/LOCODE CSV")
                        result.append((info.filename,bundle.read(info)))
                    elif depth == 0 and name.endswith(".zip") and info.file_size < 64*1024*1024:
                        result.extend(csv_members(bundle.read(info),depth+1))
                return result
        sources = csv_members(path.read_bytes())
    elif path.suffix.lower() == ".csv":
        sources = [(path.name, path.read_bytes())]
    else:
        raise ValueError("Expected UNECE CSV directory, .csv or .zip")
    entries = {}
    for filename, raw in sources:
        try:
            decoded = raw.decode("utf-8-sig")
        except UnicodeDecodeError:
            decoded = raw.decode("latin-1")
        country = ""
        for row in csv.reader(decoded.splitlines()):
            if len(row) < 11:
                continue
            # Official CSV: change,country,location,name,name_without_diacritics,
            # subdivision,function,status,date,iata,coordinates,remarks.
            change, cc, code, name, plain, subdivision = [v.strip() for v in row[:6]]
            if re.fullmatch(r"[A-Z]{2}", cc):
                country = cc
            if change == "X" or not re.fullmatch(r"[A-Z0-9]{3}", code):
                continue
            if not re.fullmatch(r"[A-Z]{2}", country) or not name:
                continue
            entries[(country,code)] = (country,code,name,plain or name,subdivision,
                                       normalize(name),normalize(plain or name))
    if not entries:
        raise ValueError("No valid UN/LOCODE entries found; original catalog preserved")
    with conn:
        conn.executescript(SCHEMA)
        conn.execute("DELETE FROM unlocode_places")
        conn.executemany(
            "INSERT INTO unlocode_places(country,code,name,ascii_name,subdivision,name_key,ascii_key) VALUES(?,?,?,?,?,?,?)",
            list(entries.values()))
    return len(entries)
