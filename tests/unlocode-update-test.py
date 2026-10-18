#!/usr/bin/env python3
"""Offline updater regression: archive validation and preservation on failure."""
import csv
import importlib.util
import io
import json
import sqlite3
import sys
import tempfile
import unittest
import zipfile
from pathlib import Path
from unittest.mock import patch

ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0,str(ROOT))
spec=importlib.util.spec_from_file_location("unlocode_updater",ROOT/"unlocode-update.py")
worker=importlib.util.module_from_spec(spec)
spec.loader.exec_module(worker)

def archive(rows):
    stream=io.StringIO(newline="")
    writer=csv.writer(stream)
    for code,name in rows:
        writer.writerow(["","RU",code,name,name,"","","AA","2401","","",""])
    out=io.BytesIO()
    with zipfile.ZipFile(out,"w",compression=zipfile.ZIP_DEFLATED) as dest:
        dest.writestr("2025-1 UNLOCODE CodeListPart1.csv",stream.getvalue())
    return out.getvalue()

class RefreshTest(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root=Path(self.temp.name)
        self.db=self.root/"analytics.sqlite3"
        sqlite3.connect(self.db).close()
        self.state=self.root/"state"

    def test_refresh_and_failed_download_preserves_previous_entries(self):
        valid=archive([("MOW","Moskva"),("LED","Sankt Peterburg")])
        with patch.object(worker,"MIN_ENTRIES",2),patch.object(worker,"fetch",return_value=valid):
            status=worker.refresh(self.db,self.state,urls=["https://service.unece.org/trade/locode/loc251csv.zip"])
        self.assertEqual(status["entries"],2)
        with sqlite3.connect(self.db) as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM unlocode_places").fetchone()[0],2)
        with patch.object(worker,"MIN_ENTRIES",2),patch.object(worker,"fetch",return_value=archive([("MOW","Moskva")])):
            with self.assertRaises(RuntimeError):
                worker.refresh(self.db,self.state,urls=["https://service.unece.org/trade/locode/loc251csv.zip"])
        with sqlite3.connect(self.db) as db:
            self.assertEqual(db.execute("SELECT COUNT(*) FROM unlocode_places").fetchone()[0],2)
        self.assertEqual(json.loads((self.state/"unlocode-status.json").read_text())["entries"],2)
        self.assertTrue((self.state/"unlocode-last-error.txt").exists())
        self.assertIn("partial", (self.state/"unlocode-last-error.txt").read_text())

    def test_rejects_non_official_sources(self):
        for url in ("http://service.unece.org/test.zip",
                    "https://untrusted.example/locode.zip",
                    "https://service.unece.org.evil.example/archive.zip"):
            with self.assertRaises(ValueError):
                worker.fetch(url)

if __name__=="__main__":
    unittest.main()
