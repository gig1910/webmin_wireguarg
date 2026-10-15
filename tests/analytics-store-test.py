#!/usr/bin/env python3
"""Offline SQLite analytics regression without running WireGuard or Webmin."""
import importlib.util
import json
import os
import sqlite3
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
        events=self.conn.execute(
            "SELECT at,type,endpoint,previous_endpoint FROM events WHERE peer_id=? "
            "ORDER BY at",(self.key_a,)).fetchall()
        self.assertEqual(events,[
            (1188,"endpoint_ip_observed","192.0.2.1",""),
            (1209,"endpoint_ip_changed","198.51.100.4","192.0.2.1")])
        self.assertEqual(self.conn.execute(
            "SELECT handshake,handshake_ip FROM peers WHERE id=?",
            (self.key_a,)).fetchone(),(1209,"198.51.100.4"))

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

    def test_time_cutoff_preserves_intersecting_bucket(self):
        self.sample(self.a,1190,100,100)
        self.sample(self.a,1210,300,300)
        store.maintain(self.conn,{"action":"delete_before","before":1205,
                                  "confirm":"DELETE"},str(self.db))
        periods=[x[0] for x in self.conn.execute("SELECT period FROM buckets")]
        self.assertEqual(periods,[1200])

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

    def test_retention_and_clear(self):
        self.sample(self.a,1000,10,10)
        self.sample(self.a,1600,50,50)
        store.maintain(self.conn,{"action":"prune","before":1500},str(self.db))
        self.assertEqual(self.conn.execute("SELECT COUNT(*) FROM peers").fetchone()[0],1)
        self.assertGreater(self.conn.execute("SELECT COUNT(*) FROM buckets").fetchone()[0],0)
        result=store.maintain(self.conn,{"action":"purge","confirm":"DELETE"},str(self.db))
        self.assertTrue(Path(result["backup"]).is_file())
        self.assertEqual(self.conn.execute("SELECT COUNT(*) FROM peers").fetchone()[0],0)
        self.assertEqual(self.conn.execute("SELECT COUNT(*) FROM events").fetchone()[0],0)

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
        self.sample(self.a,1000,100,100,handshake=995)
        self.sample(self.a,1005,110,130,"192.0.2.2:40404",handshake=1003)
        result=store.query(self.conn,{"peer_id":self.key_a,"from":900,"to":1100})
        self.assertTrue(result["db_bytes"]>0)
        self.assertEqual(result["totals"]["rx"],10)
        self.assertEqual(
            [e["type"] for e in result["events"]],
            ["endpoint_ip_changed","endpoint_ip_observed"])


    def test_handshake_without_ip_change_is_coalesced(self):
        self.sample(self.a,1000,1,2,handshake=995)
        for t in range(1005,2000,5):
            self.sample(self.a,t,t,t,endpoint="192.0.2.1:"+str(50000+t),
                        handshake=t-1)
        rows=self.conn.execute("SELECT at,type FROM events WHERE peer_id=?",
                               (self.key_a,)).fetchall()
        self.assertEqual(rows,[(995,"endpoint_ip_observed")])
        self.assertEqual(self.conn.execute(
            "SELECT handshake,handshake_ip FROM peers WHERE id=?",
            (self.key_a,)).fetchone(),(1994,"192.0.2.1"))

    def test_endpoint_changes_need_new_handshake(self):
        self.sample(self.a,1000,10,20,handshake=997)
        self.sample(self.a,1005,11,22,endpoint="203.0.113.25:1234",handshake=997)
        self.assertEqual(self.conn.execute(
            "SELECT COUNT(*) FROM events").fetchone()[0],1)
        # Transient zero handshake must not lower the confirmed timestamp.
        self.sample(self.a,1010,15,30,endpoint="203.0.113.25:1234",handshake=0)
        self.assertEqual(self.conn.execute(
            "SELECT handshake FROM peers WHERE id=?",(self.key_a,)).fetchone(),(997,))
        self.sample(self.a,1015,20,40,endpoint="203.0.113.25:1234",handshake=1013)
        events=self.conn.execute(
            "SELECT at,type,endpoint,previous_endpoint FROM events WHERE peer_id=? "
            "ORDER BY at",(self.key_a,)).fetchall()
        self.assertEqual(events,[
            (997,"endpoint_ip_observed","192.0.2.1",""),
            (1013,"endpoint_ip_changed","203.0.113.25","192.0.2.1")])

    def test_ipv6_port_changes_no_event(self):
        self.sample(self.a,1500,100,200,endpoint="[2001:db8::1]:1234",
                    handshake=1498)
        self.sample(self.a,1510,120,240,endpoint="[2001:0db8::1]:9999",
                    handshake=1508)
        self.sample(self.a,1520,130,260,endpoint="[2001:db8::2]:9999",
                    handshake=1518)
        self.assertEqual(self.conn.execute(
            "SELECT at,type,endpoint,previous_endpoint FROM events ORDER BY at"
        ).fetchall(),[
            (1498,"endpoint_ip_observed","2001:db8::1",""),
            (1518,"endpoint_ip_changed","2001:db8::2","2001:db8::1")])
        self.assertEqual(store.endpoint_ip("(none)"),"")
        self.assertEqual(store.endpoint_ip("example.org:51820"),"")

    def test_disabled_preserves_last_handshake_and_ip(self):
        self.sample(self.a,1000,10,20,handshake=997)
        store.ingest(self.conn,{"timestamp":1005,
                        "interfaces":{"wg0":{"peer_list":[]}}})
        self.assertEqual(self.conn.execute(
            "SELECT active,handshake,handshake_ip FROM peers WHERE id=?",
            (self.key_a,)).fetchone(),(0,997,"192.0.2.1"))
        self.sample(self.b,1010,10,20,endpoint="192.0.2.1:50000",
                    handshake=1009)
        self.assertEqual(self.conn.execute(
            "SELECT COUNT(*) FROM events WHERE peer_id=?", (self.key_a,)
        ).fetchone()[0],1)
        self.assertEqual(self.conn.execute(
            "SELECT COUNT(*) FROM events WHERE peer_id=?", (self.key_b,)
        ).fetchone()[0],1)

    def test_legacy_activity_compaction_is_idempotent_and_backed_up(self):
        # Simulate a DB written by the previous release, without handshake_ip.
        self.conn.close()
        os.unlink(self.db)
        conn=sqlite3.connect(self.db)
        conn.executescript(store.SCHEMA.replace(
            " handshake_ip TEXT NOT NULL DEFAULT '',\n", ""))
        ident=self.key_a
        conn.execute("INSERT INTO peers(id,public_key,first_seen,last_seen,active,"
                     "interface,endpoint,handshake) VALUES(?,?,?,?,?,?,?,?)",
                     (ident,self.a,1000,1200,1,"wg0","198.51.100.2:4500",1180))
        for t,kind,endpoint,detail in (
            (1000,"first_seen","192.0.2.1:2000",""),
            (1000,"handshake_observed","192.0.2.1:2000","998"),
            (1005,"handshake_observed","192.0.2.1:2001","1004"),
            (1010,"endpoint_changed","192.0.2.1:2002",""),
            (1010,"handshake_observed","192.0.2.1:2002","1009"),
            (1120,"endpoint_changed","198.51.100.2:4500",""),
            (1120,"handshake_observed","198.51.100.2:4500","1118"),
            (1122,"inactive","198.51.100.2:4500",""),
            (1130,"sample_gap","198.51.100.2:4500","8")):
            conn.execute("INSERT INTO events(peer_id,at,type,interface,endpoint,"
                         "detail) VALUES(?,?,?,?,?,?)",
                         (ident,t,kind,"wg0",endpoint,detail))
        conn.commit()
        conn.close()
        self.conn=store.connect(str(self.db))
        self.assertIn("handshake_ip",{
            row[1] for row in self.conn.execute("PRAGMA table_info(peers)")})
        store.ingest(self.conn,{"timestamp":1200,"interfaces":{"wg0":{"peer_list":[]}}})
        compact=self.conn.execute(
            "SELECT at,type,endpoint,previous_endpoint FROM events ORDER BY at"
        ).fetchall()
        self.assertEqual(compact,[
            (998,"endpoint_ip_observed","192.0.2.1",""),
            (1118,"endpoint_ip_changed","198.51.100.2","192.0.2.1")])
        self.assertEqual(self.conn.execute(
            "SELECT handshake_ip FROM peers WHERE id=?",
            (ident,)).fetchone(),("198.51.100.2",))
        backups=list((self.db.parent/"backups").glob("analytics-*.sqlite3"))
        self.assertEqual(len(backups),1)
        with sqlite3.connect(backups[0]) as older:
            self.assertEqual(older.execute("SELECT COUNT(*) FROM events"
                                          ).fetchone()[0],9)
        store.ingest(self.conn,{"timestamp":1210,"interfaces":{"wg0":{"peer_list":[]}}})
        self.assertEqual(self.conn.execute(
            "SELECT at,type,endpoint,previous_endpoint FROM events ORDER BY at"
        ).fetchall(),compact)
        self.assertEqual(len(list((self.db.parent/"backups").glob("analytics-*.sqlite3"))),1)

    def test_reset_and_gap_do_not_create_activity_entries(self):
        self.sample(self.a,1000,1000,1000,handshake=999)
        self.sample(self.a,1100,2000,2000,handshake=999)
        self.sample(self.a,1110,10,20,handshake=999)
        self.assertEqual(self.conn.execute("SELECT COUNT(*) FROM events"
                                          ).fetchone()[0],1)
        self.assertEqual(self.conn.execute(
            "SELECT SUM(resets),SUM(gaps) FROM buckets WHERE peer_id=?",
            (self.key_a,)).fetchone(),(1,1))

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
