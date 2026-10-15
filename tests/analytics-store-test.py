#!/usr/bin/env python3
"""Offline SQLite analytics regression without running WireGuard or Webmin."""
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parent.parent
spec=importlib.util.spec_from_file_location("wg_store",ROOT/"analytics-store.py")
store=importlib.util.module_from_spec(spec)
spec.loader.exec_module(store)


class AnalyticsTest(unittest.TestCase):
    def setUp(self):
        self.tmp=tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.db=Path(self.tmp.name)/"analytics.sqlite3"
        self.conn=store.connect(str(self.db))
        self.addCleanup(self.conn.close)
        self.a="A"*43+"="
        self.b="B"*43+"="
        self.key_a=store.peer_id(self.a)
        self.key_b=store.peer_id(self.b)

    def sample(self,key,at,rx,tx,endpoint="192.0.2.1:50000",handshake=0):
        return store.ingest(self.conn,{
            "timestamp":at,"interval":5,
            "interfaces":{"wg0":{"peer_list":[{
                "public_key":key,"endpoint":endpoint,
                "latest_handshake":handshake,"rx_bytes":rx,"tx_bytes":tx
            }]}}
        })

    def test_10min_bucket_and_endpoint(self):
        self.sample(self.a,1190,100,200,handshake=1188)
        self.sample(self.a,1210,300,400,"198.51.100.4:54321",handshake=1209)
        buckets=self.conn.execute("SELECT period,rx_bytes,tx_bytes FROM buckets "
                                  "WHERE peer_id=? ORDER BY period",(self.key_a,)).fetchall()
        self.assertEqual(buckets,[(600,100,100),(1200,100,100)])
        kinds=[r[0] for r in self.conn.execute("SELECT type FROM events WHERE peer_id=?",
                                               (self.key_a,))]
        self.assertIn("endpoint_changed",kinds)
        self.assertIn("handshake_observed",kinds)

    def test_deactivate_recreate_same_ip_different_key(self):
        self.sample(self.a,1000,10,10)
        self.sample(self.a,1005,20,20)
        store.ingest(self.conn,{"timestamp":1010,"interfaces":{"wg0":{"peer_list":[]}}})
        self.assertEqual(self.conn.execute("SELECT active FROM peers WHERE id=?",
                                          (self.key_a,)).fetchone(),(0,))
        self.sample(self.b,1015,200,200)
        self.sample(self.b,1020,250,250)
        self.assertNotEqual(self.key_a,self.key_b)
        self.assertEqual(self.conn.execute("SELECT COUNT(*) FROM peers").fetchone()[0],2)
        self.assertEqual(self.conn.execute("SELECT SUM(rx_bytes) FROM buckets WHERE peer_id=?",
                                          (self.key_a,)).fetchone()[0],10)
        self.assertEqual(self.conn.execute("SELECT SUM(rx_bytes) FROM buckets WHERE peer_id=?",
                                          (self.key_b,)).fetchone()[0],50)

    def test_reset_excluded(self):
        self.sample(self.a,1000,1000,2000)
        self.sample(self.a,1005,1400,2500)
        self.sample(self.a,1010,5,10)
        self.assertEqual(self.conn.execute("SELECT SUM(rx_bytes),SUM(tx_bytes),SUM(resets)"
                         " FROM buckets WHERE peer_id=?",(self.key_a,)).fetchone(),
                         (400,500,1))

    def test_backup_delete_and_vacuum(self):
        self.sample(self.a,1000,1,1)
        self.sample(self.a,1005,20,20)
        result=store.maintain(self.conn,{"action":"delete_peer",
                               "peer_id":self.key_a,"confirm":"DELETE"},str(self.db))
        self.assertTrue(Path(result["backup"]).is_file())
        self.assertEqual(self.conn.execute("SELECT COUNT(*) FROM peers").fetchone()[0],0)
        store.maintain(self.conn,{"action":"vacuum"},str(self.db))
        with self.assertRaises(ValueError):
            store.maintain(self.conn,{"action":"purge"},str(self.db))

    def test_legacy_mapping(self):
        legacy=Path(self.tmp.name)
        filename="wg0-peer-"+store.hashlib.sha256(self.a.encode()).hexdigest()+".jsonl"
        (legacy/filename).write_text(
            '\n'.join(json.dumps({"timestamp":t,"rx":rx,"tx":rx})
                      for t,rx in ((900,10),(905,50),(910,100)))+'\n')
        store.ingest(self.conn,{"timestamp":1000,"interval":5,"legacy_dir":str(legacy),
                  "interfaces":{"wg0":{"peer_list":[{
                      "public_key":self.a,"rx_bytes":110,"tx_bytes":110
                  }]}}})
        self.assertEqual(self.conn.execute(
            "SELECT SUM(rx_bytes) FROM buckets WHERE peer_id=?",
            (self.key_a,)).fetchone()[0],90)
        self.assertTrue((legacy/filename).exists())
        # No re-import after restart
        self.sample(self.a,1005,120,120)
        self.assertEqual(self.conn.execute(
            "SELECT SUM(rx_bytes) FROM buckets WHERE peer_id=?",
            (self.key_a,)).fetchone()[0],100)

    def test_exact_bucket_end_excludes_next_bucket(self):
        self.sample(self.a,1190,100,100)
        self.sample(self.a,1210,300,300)
        partial=store.query(self.conn,{"peer_id":self.key_a,"from":1200,"to":1800})
        self.assertEqual(len(partial["buckets"]),1)
        self.assertEqual(partial["buckets"][0]["period"],1200)
        self.assertEqual(partial["totals"]["rx"],100)

    def test_filtered_events_and_db_size(self):
        self.sample(self.a,1000,100,100)
        self.sample(self.a,1005,110,130,"192.0.2.2:40404")
        result=store.query(self.conn,{"peer_id":self.key_a,"from":900,"to":1100})
        self.assertTrue(result["db_bytes"]>0)
        self.assertEqual(result["totals"]["rx"],10)
        self.assertTrue(any(e["type"]=="endpoint_changed" for e in result["events"]))

    def test_prometheus_text_contains_only_fingerprints(self):
        self.sample(self.a,1000,100,200,endpoint="192.0.2.5:12345")
        self.sample(self.a,1005,200,300)
        output=store.render_prometheus_text(self.conn,{"traffic","peer_state","handshake"})
        self.assertIn('peer="'+self.key_a+'"',output)
        self.assertIn("# TYPE webmin_wg_peer_stored_rx_bytes gauge",output)
        self.assertNotIn(self.a,output)
        self.assertNotIn("192.0.2.5",output)
        self.assertNotIn("PrivateKey",output)

    def test_reopen_preserves_records(self):
        self.sample(self.a,1000,10,10)
        self.conn.close()
        self.conn=store.connect(str(self.db))
        self.assertEqual(self.conn.execute("SELECT COUNT(*) FROM peers").fetchone()[0],1)

    def test_prometheus_rejects_unapproved_path(self):
        with self.assertRaises(ValueError):
            store.prometheus(self.conn,{"path":str(self.db)+".prom",
                "metrics":["traffic"]})


if __name__=="__main__":
    unittest.main()
