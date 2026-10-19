#!/usr/bin/env python3
"""Offline SQLite analytics regression without running WireGuard or Webmin."""
import importlib.util
import json
import os
import sys
import sqlite3
import tempfile
import unittest
from pathlib import Path

ROOT=Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))  # analytics-store imports its adjacent network_store module
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

    def test_historical_whois_restricted_to_retained_peer_endpoint_events(self):
        self.sample(self.a, 1190, 1, 2, "8.8.8.8:50000", handshake=1188)
        self.sample(self.a, 1210, 4, 5, "1.1.1.1:50000", handshake=1209)
        self.sample(self.b, 1220, 1, 2, "9.9.9.9:50000", handshake=1219)
        old = store.peer_handshake_ip(self.conn, {
            "peer_id":self.key_a, "event_ip":"8.8.8.8", "event_at":1188
        })
        self.assertTrue(old["available"])
        self.assertTrue(old["public"])
        self.assertEqual(old["ip"],"8.8.8.8")
        # Both new and old endpoints are stored on the change event.
        former = store.peer_handshake_ip(self.conn, {
            "peer_id":self.key_a, "event_ip":"8.8.8.8", "event_at":1209
        })
        self.assertEqual(former["ip"],"8.8.8.8")
        # Arbitrary IP, foreign peer, wrong timestamp and missing credentials
        # must all fail before any external WHOIS query can run.
        for payload in [
            {"peer_id":self.key_a,"event_ip":"9.9.9.9","event_at":1219},
            {"peer_id":self.key_b,"event_ip":"8.8.8.8","event_at":1188},
            {"peer_id":self.key_a,"event_ip":"8.8.8.8","event_at":9999},
            {"peer_id":self.key_a,"event_ip":"8.8.8.8","event_at":True},
            {"peer_id":self.key_a,"event_ip":"localhost","event_at":1188},
        ]:
            with self.assertRaises(ValueError):
                store.peer_handshake_ip(self.conn, payload)

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


    def test_peer_name_is_metadata_not_identity(self):
        first = self.sample(self.a,1000,1,2,handshake=999)
        request = {
            "timestamp":1005, "interval":5, "peer_names":{self.a:"Tanya"},
            "interfaces":{"wg0":{"peer_list":[{
                "public_key":self.a,"endpoint":"192.0.2.1:50000",
                "latest_handshake":999,"rx_bytes":2,"tx_bytes":3
            }]}}
        }
        store.ingest(self.conn,request)
        row=self.conn.execute("SELECT id,name FROM peers WHERE id=?",
                              (self.key_a,)).fetchone()
        self.assertEqual(row,(self.key_a,"Tanya"))
        # Names can change, but every row remains attached to its key.
        request["timestamp"]=1010
        request["peer_names"]={self.a:"Таня",self.b:"Таня"}
        store.ingest(self.conn,request)
        self.assertEqual(self.conn.execute(
            "SELECT name FROM peers WHERE id=?",(self.key_a,)).fetchone(),
            ("Таня",))
        self.assertEqual(self.conn.execute(
            "SELECT COUNT(*) FROM peers").fetchone()[0],1)
        # Disabling does not erase its identity or last known name.
        store.ingest(self.conn,{"timestamp":1015,
            "interfaces":{"wg0":{"peer_list":[]}}})
        self.assertEqual(self.conn.execute(
            "SELECT name,active FROM peers WHERE id=?",(self.key_a,)).fetchone(),
            ("Таня",0))
        self.conn.close()
        self.conn=store.connect(str(self.db))
        self.assertEqual(self.conn.execute(
            "SELECT name FROM peers WHERE id=?",(self.key_a,)).fetchone(),
            ("Таня",))
        # Different key, same label/IP, remains entirely separate.
        store.ingest(self.conn,{"timestamp":1020,"interval":5,
           "peer_names":{self.b:"Таня"},
           "interfaces":{"wg0":{"peer_list":[{
             "public_key":self.b,"endpoint":"192.0.2.1:50000",
             "latest_handshake":1019,"rx_bytes":100,"tx_bytes":100
           }]}}})
        self.assertEqual(self.conn.execute(
            "SELECT id,name FROM peers ORDER BY id").fetchall(),
            sorted([(self.key_a,"Таня"),(self.key_b,"Таня")]))

    def test_preexisting_database_without_name_gets_migrated(self):
        self.conn.close()
        os.unlink(self.db)
        import sqlite3
        conn=sqlite3.connect(self.db)
        schema=store.SCHEMA.replace(" name TEXT NOT NULL DEFAULT '',\n", "")
        conn.executescript(schema)
        conn.commit()
        conn.close()
        self.conn=store.connect(str(self.db))
        self.assertIn("name",{
            row[1] for row in self.conn.execute("PRAGMA table_info(peers)")})
        self.assertEqual(self.conn.execute("SELECT COUNT(*) FROM peers").fetchone()[0],0)


    def test_interface_filter_is_applied_by_sqlite(self):
        self.sample(self.a,1200,100,100,handshake=1199)
        self.sample(self.a,1205,120,130,handshake=1204)
        # Same time bucket, distinct peer attached to another interface.
        store.ingest(self.conn,{"timestamp":1200,"interval":5,
            "interfaces":{"wg_other":{"peer_list":[{
                "public_key":self.b,"endpoint":"203.0.113.3:1234",
                "latest_handshake":1199,"rx_bytes":500,"tx_bytes":500
            }]}}})
        store.ingest(self.conn,{"timestamp":1205,"interval":5,
            "interfaces":{"wg_other":{"peer_list":[{
                "public_key":self.b,"endpoint":"203.0.113.3:1234",
                "latest_handshake":1204,"rx_bytes":530,"tx_bytes":540
            }]}}})
        # Both histories remain retained, but interface scoping must isolate.
        all_peers=store.query(self.conn,{"from":1150,"to":1800})
        wg0=store.query(self.conn,{"from":1150,"to":1800,
                                   "interface":"wg0"})
        other=store.query(self.conn,{"from":1150,"to":1800,
                                    "interface":"wg_other"})
        self.assertEqual(all_peers["totals"]["rx"],50)
        self.assertEqual(wg0["totals"]["rx"],20)
        self.assertEqual(wg0["totals"]["tx"],30)
        self.assertEqual(other["totals"]["rx"],30)
        self.assertEqual(other["totals"]["tx"],40)
        self.assertEqual({b["peer_id"] for b in wg0["buckets"]},{self.key_a})
        self.assertEqual({e["peer_id"] for e in other["events"]},{self.key_b})
        with self.assertRaises(ValueError):
            store.query(self.conn,{"from":1150,"to":1800,
                                  "interface":"../wg0"})
        with self.assertRaises(ValueError):
            store.query(self.conn,{"from":1150,"to":1800,
                                  "interface":"wg_other","peer_id":self.key_a})
        # Historical records survive a peer being removed from runtime dump.
        store.ingest(self.conn,{"timestamp":1210,"interfaces":{}})
        self.assertEqual(store.query(self.conn,{"from":1150,"to":1800,
                                               "interface":"wg0"})["totals"]["rx"],20)


    def test_long_window_chart_is_aggregated_without_truncating_totals(self):
        # A 365-day query for many peers crosses the original 20K row cap.
        # Verify that SQL grouping returns exact totals and 180 or fewer bins.
        start = 600
        with self.conn:
            self.conn.execute(
                "INSERT INTO peers(id,public_key,first_seen,last_seen,interface) "
                "VALUES(?,?,?,?,?)",
                (self.key_a,self.a,start,start,"wg0"))
            self.conn.executemany(
                "INSERT INTO buckets(peer_id,period,rx_bytes,tx_bytes,samples) "
                "VALUES(?,?,?,?,1)",
                ((self.key_a,start+i*600,1,2) for i in range(22000))
            )
        until=start+22000*600
        grouped=store.query(self.conn,{"from":start,"to":until,
                                       "chart_points":180})
        self.assertEqual(grouped["totals"]["rx"],22000)
        self.assertEqual(grouped["totals"]["tx"],44000)
        self.assertFalse(grouped["truncated"])
        self.assertLessEqual(len(grouped["buckets"]),180)
        self.assertGreater(grouped["bucket_seconds"],600)
        self.assertEqual(sum(p["rx"] for p in grouped["buckets"]),22000)
        self.assertEqual(sum(p["tx"] for p in grouped["buckets"]),44000)
        # The database has not been downsampled or truncated.
        self.assertEqual(self.conn.execute(
            "SELECT COUNT(*) FROM buckets").fetchone()[0],22000)

    def test_short_window_chart_retains_ten_minute_resolution(self):
        self.sample(self.a,1200,100,100,handshake=1199)
        self.sample(self.a,1205,140,160,handshake=1204)
        result=store.query(self.conn,{"from":1150,"to":2400,
                                      "chart_points":180})
        self.assertEqual(result["bucket_seconds"],600)
        self.assertEqual(result["totals"]["rx"],40)
        self.assertEqual(result["totals"]["tx"],60)
        self.assertFalse(result["truncated"])

    def test_peer_handshake_ip_only_uses_confirmed_sqlite_identity(self):
        a=self.key_a
        self.assertEqual(store.peer_handshake_ip(self.conn,{"peer_id":a}),
                         {"ok":True,"available":False,"handshake":0})
        self.sample(self.a,1000,10,20,endpoint="198.51.100.2:51720",handshake=999)
        result=store.peer_handshake_ip(self.conn,{"peer_id":a})
        self.assertTrue(result["available"])
        self.assertEqual((result["ip"],result["handshake"]),("198.51.100.2",999))
        self.assertFalse(result["public"])  # documentation/test range is non-global
        # Endpoint may move without a new handshake; must keep confirmed IP.
        self.sample(self.a,1005,15,25,endpoint="8.8.4.4:51721",handshake=999)
        self.assertEqual(store.peer_handshake_ip(self.conn,{"peer_id":a})["ip"],"198.51.100.2")
        # Handshake changes: now accept the new address.
        self.sample(self.a,1010,20,30,endpoint="8.8.4.4:51721",handshake=1009)
        result=store.peer_handshake_ip(self.conn,{"peer_id":a})
        self.assertEqual(result["ip"],"8.8.4.4")
        self.assertTrue(result["public"])
        # Disabled, then reused tunnel IP/name under another public key.
        store.ingest(self.conn,{"timestamp":1015,"interfaces":{"wg0":{"peer_list":[]}}})
        self.assertEqual(store.peer_handshake_ip(self.conn,{"peer_id":a})["ip"],"8.8.4.4")
        self.assertFalse(store.peer_handshake_ip(self.conn,{"peer_id":self.key_b})["available"])
        for ident in ("invalid","../config",self.a):
            with self.assertRaises(ValueError):
                store.peer_handshake_ip(self.conn,{"peer_id":ident})
        self.sample(self.b,1020,1,2,endpoint="10.66.66.1:1234",handshake=1018)
        self.assertFalse(store.peer_handshake_ip(self.conn,{"peer_id":self.key_b})["public"])


    def test_network_cache_only_manual_and_range_aware(self):
        from ipaddress import ip_address
        sample_ip="8.8.8.8"
        self.sample(self.a,1200,1,2,endpoint="8.8.8.8:443",handshake=1199)
        # Passive collection must NEVER create a new WHOIS prefix.
        self.assertEqual(self.conn.execute("SELECT COUNT(*) FROM network_cache").fetchone()[0],0)
        result=store.network_record(self.conn,{"ip":sample_ip,"whois_fields":[
            {"label":"Network range","value":"8.8.8.0 - 8.8.8.255"},
            {"label":"Organization","value":"Network Example"},
            {"label":"Country","value":"US"}]})
        self.assertEqual(result["cidr"],"8.8.8.0/24")
        got=store.network_lookup(self.conn,{"ips":["8.8.8.8","8.8.8.9","8.8.4.4"]})["results"]
        self.assertEqual(got["8.8.8.9"]["cidr"],"8.8.8.0/24")
        self.assertEqual(got["8.8.8.8"]["label"],"Network Example")
        self.assertEqual(got["8.8.8.8"]["icon"],"?")
        self.assertFalse(got["8.8.4.4"]["cached"])
        # CIDR is only accepted if it contains the verified request address.
        result=store.network_record(self.conn,{"ip":"8.8.4.4","whois_fields":[
            {"label":"CIDR","value":"1.1.1.0/24"}]})
        self.assertEqual(result["cidr"],"8.8.4.4/32")
        for invalid in ["192.168.1.5","127.0.0.1","2001:db8::1","not-an-ip"]:
            with self.assertRaises(ValueError):
                store.network_record(self.conn,{"ip":invalid,"whois_fields":[]})

    def test_network_icons_longest_match_and_independent_reset(self):
        store.network_record(self.conn,{"ip":"8.8.8.8","whois_fields":[
            {"label":"CIDR","value":"8.8.8.0/24"}]})
        for cidr,icon,label in [
            ("8.0.0.0/8","☁","Provider"),("8.8.8.0/24","★","Special"),
            ("2001:4860::/32","⌂","IPv6")]:
            store.network_manage(self.conn,{"action":"set_icon",
                "cidr":cidr,"icon":icon,"label":label})
        got=store.network_lookup(self.conn,{"ips":["8.8.8.8","8.1.2.3",
            "2001:4860:4860::8888","9.9.9.9"]})["results"]
        self.assertEqual(got["8.8.8.8"]["icon"],"★")
        self.assertEqual(got["8.8.8.8"]["label"],"Special")
        self.assertEqual(got["8.1.2.3"]["icon"],"☁")
        self.assertEqual(got["2001:4860:4860::8888"]["icon"],"⌂")
        self.assertEqual(got["9.9.9.9"]["icon"],"?")
        # Runtime IPv6 endpoints may not use Python's canonical spelling.
        mixed=store.network_lookup(self.conn,{"ips":["2001:4860:0000:0000:0000:0000:0000:8888"]})["results"]
        self.assertEqual(mixed["2001:4860:0000:0000:0000:0000:0000:8888"]["icon"],"⌂")
        with self.assertRaises(ValueError):
            store.network_manage(self.conn,{"action":"clear_cache"})
        result=store.network_manage(self.conn,{"action":"clear_cache","confirm":"CLEAR"})
        self.assertEqual(result["deleted"],1)
        self.assertEqual(self.conn.execute("SELECT COUNT(*) FROM network_cache").fetchone()[0],0)
        self.assertEqual(self.conn.execute("SELECT COUNT(*) FROM network_icons").fetchone()[0],3)
        after=store.network_lookup(self.conn,{"ips":["8.8.8.8"]})["results"]["8.8.8.8"]
        self.assertEqual(after["icon"],"★")
        self.assertFalse(after["cached"])
        store.network_manage(self.conn,{"action":"delete_icon","cidr":"8.8.8.0/24"})
        self.assertEqual(store.network_lookup(self.conn,{"ips":["8.8.8.8"]})
                         ["results"]["8.8.8.8"]["icon"],"☁")
        for invalid in ["8.8.8.1/24","foo","../etc/passwd"]:
            with self.assertRaises(ValueError):
                store.network_manage(self.conn,{"action":"set_icon","cidr":invalid})
        with self.assertRaises(ValueError):
            store.network_manage(self.conn,{"action":"set_icon",
                                           "cidr":"8.8.8.0/24","icon":"X"*100})
        with self.assertRaises(ValueError):
            store.network_lookup(self.conn,{"ips":["1.1.1.1"]*129})

    def test_exact_ip_refresh_preserves_manual_city_and_independent_sources(self):
        # An explicit WHOIS lookup must remain retryable even without a GeoIP match.
        store.network_record(self.conn,{"ip":"9.9.9.9","whois_fields":[]})
        self.assertTrue(store.network_manage(self.conn,{
            "action":"check_observed_ip","ip":"9.9.9.9"})["known"])
        self.assertEqual(store.network_manage(self.conn,{
            "action":"get_observed_ip","ip":"9.9.9.9"})["city"],"")
        store.network_record(self.conn,{
            "ip":"8.8.8.8","geoip_country_code":"RU","geoip_city":"Moscow",
            "whois_fields":[{"label":"CIDR","value":"8.8.8.0/24"},
                            {"label":"Organization","value":"Old provider"}]})
        self.assertTrue(store.network_manage(self.conn,{
            "action":"check_observed_ip","ip":"8.8.8.8"})["known"])
        self.assertFalse(store.network_manage(self.conn,{
            "action":"check_observed_ip","ip":"1.1.1.1"})["known"])
        with self.assertRaises(ValueError):
            store.network_manage(self.conn,{
                "action":"refresh_geoip","ip":"1.1.1.1",
                "country":"RU","city":"Moscow"})
        store.network_manage(self.conn,{
            "action":"set_icon","cidr":"8.8.8.0/24","city":"Manual city"})
        store.network_manage(self.conn,{
            "action":"refresh_geoip","ip":"8.8.8.8",
            "country":"RS","city":"Belgrade"})
        observed=store.network_manage(self.conn,{
            "action":"get_observed_ip","ip":"8.8.8.8"})
        self.assertEqual(observed["country"],"RS")
        self.assertEqual(observed["city"],"Belgrade")
        self.assertEqual(store.network_lookup(self.conn,{
            "ips":["8.8.8.8"]})["results"]["8.8.8.8"]["city"],"Manual city")
        store.network_manage(self.conn,{
            "action":"refresh_whois","ip":"8.8.8.8",
            "whois_fields":[{"label":"CIDR","value":"8.8.8.0/24"},
                            {"label":"Organization","value":"New provider"}]})
        self.assertEqual(store.network_manage(self.conn,{
            "action":"get_observed_ip","ip":"8.8.8.8"})["city"],"Belgrade")
        ranges=store.network_manage(self.conn,{"action":"list"})["cache"]
        target=next(x for x in ranges if x["cidr"]=="8.8.8.0/24")
        self.assertIn("8.8.8.8",target["observed_ips"])
        self.assertEqual(target["owner"],"New provider")

    def test_existing_network_database_city_migration(self):
        old = Path(self.tmp.name) / "legacy.sqlite3"
        connection = sqlite3.connect(old)
        connection.executescript("""
            CREATE TABLE network_icons (
              cidr TEXT PRIMARY KEY, icon TEXT NOT NULL DEFAULT '?',
              label TEXT NOT NULL DEFAULT ''
            );
            CREATE TABLE geoip_cache (
              ip TEXT PRIMARY KEY, country_code TEXT NOT NULL,
              observed_at INTEGER NOT NULL DEFAULT 0
            );
            INSERT INTO network_icons(cidr,icon,label)
              VALUES('8.8.8.0/24','?','Existing assignment');
            INSERT INTO geoip_cache(ip,country_code,observed_at)
              VALUES('8.8.8.8','US',9999999999);
        """)
        connection.commit()
        connection.close()
        upgraded = store.connect(str(old))
        try:
            result = store.network_lookup(
                upgraded, {"ips": ["8.8.8.8"]})["results"]["8.8.8.8"]
            self.assertEqual(result["label"], "Existing assignment")
            self.assertEqual(result["country"], "US")
            self.assertEqual(result["city_code"], "")
            self.assertIn("city", [x[1] for x in upgraded.execute(
                "PRAGMA table_info(network_icons)")])
            self.assertIn("city_code", [x[1] for x in upgraded.execute(
                "PRAGMA table_info(geoip_cache)")])
        finally:
            upgraded.close()

    def test_city_observation_manual_override_and_cache_lifecycle(self):
        import unlocode_store as locodes
        from io import StringIO
        import csv
        import time
        catalog = Path(self.tmp.name) / "unlocode.csv"
        def row(country, code, name):
            return ["",country,code,name,name,"","","AA","2401","","",""]
        with catalog.open("w",encoding="utf-8",newline="") as f:
            writer=csv.writer(f)
            writer.writerow(row("RU","MOW","Moskva"))
            writer.writerow(row("RS","BEG","Belgrade"))
        self.assertEqual(locodes.import_release(self.conn,catalog),2)
        store.network_manage(self.conn,{"action":"set_icon","cidr":"1.1.1.0/24",
                                        "city":"","city_code":"RUMOW"})
        item=next(x for x in store.network_manage(self.conn,{"action":"list"})["icons"]
                  if x["cidr"]=="1.1.1.0/24")
        self.assertEqual(item["city"],"Moskva")
        self.assertEqual(item["city_code"],"RUMOW")
        # Existing installations may contain old location rows without
        # populated normalized keys. Substring search must still work.
        self.conn.execute("UPDATE unlocode_places SET name_key='',ascii_key='' "
                          "WHERE country='RU' AND code='MOW'")
        self.assertEqual(store.network_manage(self.conn,{"action":"search_unlocode",
                          "term":"mos"})["total"],1)
        self.assertEqual(store.network_manage(self.conn,{"action":"search_unlocode",
                          "term":"Моск"})["matches"][0]["code"],"RUMOW")
        # Casefolding and Cyrillic transliteration must be independent of
        # user-entered letter case, including mixed-case Unicode.
        for term in ("mos", "MOS", "MoS", "mOsKv", "моск", "МОСК",
                     "МоСк", "МОСКВА", "Москва"):
            with self.subTest(unlocode_case=term):
                result=store.network_manage(self.conn,{
                    "action":"search_unlocode","term":term})
                self.assertEqual(result["total"],1)
                self.assertEqual(result["matches"][0]["code"],"RUMOW")
        for term in ("bel", "BEL", "BeL", "grad", "GRAD", "GrAd"):
            with self.subTest(unlocode_case=term):
                result=store.network_manage(self.conn,{
                    "action":"search_unlocode","term":term})
                self.assertEqual(result["total"],1)
                self.assertEqual(result["matches"][0]["code"],"RSBEG")
        # Restore keys for subsequent exact lookup checks.
        self.conn.execute("UPDATE unlocode_places SET name_key='moskva',"
                          "ascii_key='moskva' WHERE country='RU' AND code='MOW'")
        found_code=store.network_manage(self.conn,{"action":"search_unlocode",
                                                   "term":"RUMOW"})["matches"]
        self.assertEqual(found_code[0]["name"],"Moskva")

        found=store.network_manage(self.conn,{
            "action":"search_unlocode","term":"bel","country":"RS"})["matches"]
        self.assertEqual(store.network_manage(self.conn,{"action":"search_unlocode","term":"Москва","country":"RU"})["matches"][0]["code"],"RUMOW")
        self.assertEqual([(x["code"],x["name"]) for x in found],
                         [("RSBEG","Belgrade")])
        middle=store.network_manage(self.conn,{"action":"search_unlocode",
                                               "term":"grad"}) 
        self.assertEqual(middle["total"],1)
        self.assertEqual(middle["matches"][0]["code"],"RSBEG")
        self.assertEqual(store.network_manage(self.conn,{"action":"search_unlocode",
                     "term":"grad","offset":100})["matches"],[])

        self.assertEqual(store.network_manage(self.conn,{
            "action":"search_unlocode","term":"bel","country":"RU"})["matches"],[])
        # Zero-result diagnostics distinguish request normalization from a
        # missing or damaged on-disk catalog, without altering its contents.
        empty=store.network_manage(self.conn,{
            "action":"search_unlocode","term":"unlikely_location_xyz"})
        self.assertEqual(empty["total"],0)
        self.assertEqual(empty["diagnostic"]["normalized_term"],
                         "unlikely location xyz")
        self.assertEqual(empty["diagnostic"]["catalog_count"],2)
        self.assertEqual(empty["diagnostic"]["rumow"]["name"],"Moskva")


        store.network_record(self.conn, {
            "ip":"8.8.8.8","geoip_country_code":"RU",
            "geoip_city":"Moscow",
            "whois_fields":[{"label":"CIDR","value":"8.8.8.0/24"}]})
        got=store.network_lookup(self.conn,{"ips":["8.8.8.8","8.8.8.9"]})["results"]
        self.assertEqual(got["8.8.8.8"]["city_code"],"RUMOW")
        self.assertEqual(got["8.8.8.9"]["city_code"],"")
        store.network_manage(self.conn,{
            "action":"set_icon","cidr":"8.8.8.0/24",
            "city":"Belgrade","city_code":"RSBEG"})
        got=store.network_lookup(self.conn,{"ips":["8.8.8.8","8.8.8.9"]})["results"]
        self.assertEqual(got["8.8.8.8"]["city_code"],"RSBEG")
        self.assertEqual(got["8.8.8.9"]["city_code"],"RSBEG")
        listing=store.network_manage(self.conn,{"action":"list"})
        self.assertEqual(listing["cache"][0]["geoip_cities"],["RUMOW"])
        self.assertEqual(listing["cache"][0]["geoip_city_names"],["Moscow"])
        store.network_manage(self.conn,{"action":"clear_cache","confirm":"CLEAR"})
        self.assertEqual(store.network_lookup(
            self.conn,{"ips":["8.8.8.8"]})["results"]["8.8.8.8"]["city_code"],"RSBEG")
        for bad in ("MSK","RUXYZ","<script>"):
            with self.assertRaises(ValueError):
                store.network_manage(self.conn,{
                    "action":"set_icon","cidr":"8.8.8.0/24","city_code":bad})
        # One country/name pointing to two distinct codes must never be guessed.
        with catalog.open("w",encoding="utf-8",newline="") as f:
            writer=csv.writer(f)
            writer.writerow(row("RU","MOW","Moskva"))
            writer.writerow(row("RU","ABC","Moskva"))
        locodes.import_release(self.conn,catalog)
        self.assertEqual(locodes.lookup(self.conn,"RU","Moscow"),"")

    def test_geoip_country_is_exact_ip_not_whois_prefix(self):
        store.network_record(self.conn,{
            "ip":"8.8.8.8","geoip_country_code":"DE",
            "whois_fields":[
                {"label":"CIDR","value":"8.8.8.0/24"},
                {"label":"Country","value":"US"},
                {"label":"Organization","value":"Example Network"}]})
        got=store.network_lookup(self.conn,{"ips":["8.8.8.8","8.8.8.9"]})["results"]
        self.assertEqual(got["8.8.8.8"]["country"],"DE")
        self.assertEqual(got["8.8.8.8"]["country_source"],"geoip")
        self.assertEqual(got["8.8.8.8"]["whois_country"],"US")
        self.assertEqual(got["8.8.8.9"]["country"],"US")
        self.assertEqual(got["8.8.8.9"]["country_source"],"whois")
        self.assertEqual(self.conn.execute(
            "SELECT country FROM network_cache WHERE cidr='8.8.8.0/24'").fetchone()[0],"US")
        self.assertEqual(self.conn.execute(
            "SELECT country_code FROM geoip_cache WHERE ip='8.8.8.8'").fetchone()[0],"DE")
        with self.assertRaises(ValueError):
            store.network_record(self.conn,{
                "ip":"8.8.8.8","geoip_country_code":"<script>",
                "whois_fields":[]})
        store.network_manage(self.conn,{"action":"clear_cache","confirm":"CLEAR"})
        self.assertEqual(self.conn.execute("SELECT COUNT(*) FROM geoip_cache").fetchone()[0],0)

    def test_sqlite_wal_budget_and_checkpoint(self):
        # These caps are advisory; readers may temporarily keep WAL pages.
        # Verify settings are installed for each new backend connection.
        self.assertEqual(self.conn.execute("PRAGMA journal_mode").fetchone()[0], "wal")
        self.assertEqual(self.conn.execute("PRAGMA wal_autocheckpoint").fetchone()[0], 256)
        self.assertEqual(self.conn.execute("PRAGMA journal_size_limit").fetchone()[0], 4194304)
        self.assertEqual(self.conn.execute("PRAGMA cache_size").fetchone()[0], -8192)
        self.sample(self.a, 1200, 1, 2, handshake=1199)
        wal_path = Path(str(self.db) + "-wal")
        self.assertTrue(wal_path.is_file())
        # The supported VACUUM maintenance action already truncates WAL.
        self.assertTrue(store.maintain(self.conn, {"action": "vacuum"}, str(self.db))["ok"])
        self.assertLessEqual(wal_path.stat().st_size if wal_path.exists() else 0, 4194304)
        self.conn.close()
        self.conn = store.connect(str(self.db))
        self.assertEqual(self.conn.execute("PRAGMA wal_autocheckpoint").fetchone()[0], 256)

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
