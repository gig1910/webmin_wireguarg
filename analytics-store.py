#!/usr/bin/env python3
"""Persistent WireGuard peer analytics, using Python's standard sqlite3 module.

Protocol: argv = ACTION DATABASE_PATH; stdin = one JSON object; stdout = JSON.
Never stores WireGuard private keys. All identities are SHA256(public_key).
"""
import json
import os
import re
import sqlite3
import sys
import tempfile
import time
import hashlib
import ipaddress
from pathlib import Path
from network_store import NETWORK_SCHEMA, network_record, network_lookup, network_manage

SCHEMA = """
CREATE TABLE IF NOT EXISTS peers (
 id TEXT PRIMARY KEY, public_key TEXT NOT NULL UNIQUE,
 first_seen INTEGER NOT NULL, last_seen INTEGER NOT NULL,
 name TEXT NOT NULL DEFAULT '',
 active INTEGER NOT NULL DEFAULT 0, interface TEXT NOT NULL,
 endpoint TEXT NOT NULL DEFAULT '', handshake INTEGER NOT NULL DEFAULT 0,
 handshake_ip TEXT NOT NULL DEFAULT '',
 sample_at INTEGER, rx INTEGER, tx INTEGER
);
CREATE TABLE IF NOT EXISTS buckets (
 peer_id TEXT NOT NULL, period INTEGER NOT NULL,
 rx_bytes INTEGER NOT NULL DEFAULT 0, tx_bytes INTEGER NOT NULL DEFAULT 0,
 samples INTEGER NOT NULL DEFAULT 0, resets INTEGER NOT NULL DEFAULT 0,
 gaps INTEGER NOT NULL DEFAULT 0,
 PRIMARY KEY(peer_id,period)
);
CREATE INDEX IF NOT EXISTS buckets_period ON buckets(period);
CREATE TABLE IF NOT EXISTS events (
 id INTEGER PRIMARY KEY AUTOINCREMENT, peer_id TEXT NOT NULL,
 at INTEGER NOT NULL, type TEXT NOT NULL, interface TEXT NOT NULL,
 endpoint TEXT NOT NULL DEFAULT '', previous_endpoint TEXT NOT NULL DEFAULT '',
 detail TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS events_peer_time ON events(peer_id,at);
CREATE INDEX IF NOT EXISTS events_time ON events(at);
CREATE TABLE IF NOT EXISTS properties (key TEXT PRIMARY KEY, value TEXT NOT NULL);
"""
KEY = re.compile(r"^[0-9a-f]{64}$")
IFACE = re.compile(r"^[A-Za-z0-9_=+.-]{1,15}$")
VALID_METRICS = ("traffic", "peer_state", "handshake", "events", "collector")


def peer_id(public_key):
    if not isinstance(public_key, str) or not public_key:
        raise ValueError("public key required")
    return hashlib.sha256(public_key.encode("ascii")).hexdigest()


def connect(path):
    p = Path(path)
    if not p.is_absolute() or p.is_symlink() or p.suffix != ".sqlite3":
        raise ValueError("invalid database path")
    p.parent.mkdir(mode=0o700, parents=True, exist_ok=True)
    conn = sqlite3.connect(str(p), timeout=10)
    conn.execute("PRAGMA busy_timeout=10000")
    conn.execute("PRAGMA journal_mode=WAL")
    conn.executescript(SCHEMA)
    conn.executescript(NETWORK_SCHEMA)
    # CREATE TABLE IF NOT EXISTS does not add columns to pre-existing databases.
    columns = {row[1] for row in conn.execute("PRAGMA table_info(peers)")}
    if "handshake_ip" not in columns:
        conn.execute("ALTER TABLE peers ADD COLUMN handshake_ip TEXT NOT NULL DEFAULT ''")
    if "name" not in columns:
        conn.execute("ALTER TABLE peers ADD COLUMN name TEXT NOT NULL DEFAULT ''")
    conn.commit()
    if p.exists():
        os.chmod(p, 0o600)
    return conn


def event(conn, ident, stamp, kind, interface, endpoint="", previous="", detail=""):
    conn.execute(
        "INSERT INTO events(peer_id,at,type,interface,endpoint,previous_endpoint,detail) "
        "VALUES(?,?,?,?,?,?,?)",
        (ident, stamp, kind, interface, endpoint, previous, detail),
    )


def endpoint_ip(endpoint):
    """IP without port, including IPv6 [address]:port; do not infer hostnames."""
    endpoint = str(endpoint or "").strip()
    if not endpoint or endpoint == "(none)":
        return ""
    if endpoint.startswith("["):
        endpoint = endpoint[1:].split("]", 1)[0] if "]" in endpoint else ""
    elif endpoint.count(":") == 1:
        endpoint = endpoint.rsplit(":", 1)[0]
    try:
        return str(ipaddress.ip_address(endpoint))
    except ValueError:
        return ""


def compact_legacy_activity(conn, path):
    """Back up and reduce old per-handshake events to meaningful IP changes."""
    marker = "handshake_ip_compaction_v1"
    if conn.execute("SELECT 1 FROM properties WHERE key=?", (marker,)).fetchone():
        return
    old_events = conn.execute(
        "SELECT COUNT(*) FROM events WHERE type NOT IN "
        "('endpoint_ip_observed','endpoint_ip_changed')"
    ).fetchone()[0]
    if old_events:
        backup(conn, path)  # SQLite online backup *before* destructive cleanup
    with conn:
        conn.execute("BEGIN IMMEDIATE")
        baseline = {}
        # Existing handshake_observed.detail stores the actual UNIX timestamp.
        # The observation time (events.at) can be later than the handshake.
        changes = []
        # Stream the old activity history; a multi-year installation can have
        # millions of handshakes and must not exhaust the collector's memory.
        historical = conn.execute(
            "SELECT peer_id,interface,endpoint,detail FROM events "
            "WHERE type='handshake_observed' "
            "ORDER BY peer_id,CAST(detail AS INTEGER),id"
        )
        for ident, interface, endpoint, detail in historical:
            if not str(detail).isdigit() or int(detail) <= 0:
                continue
            ip = endpoint_ip(endpoint)
            if not ip:
                continue
            previous = baseline.get(ident, "")
            if ip != previous:
                changes.append((ident, int(detail),
                                "endpoint_ip_changed" if previous else "endpoint_ip_observed",
                                interface, ip, previous))
                baseline[ident] = ip
        historical.close()
        for ident, stamp, kind, interface, ip, previous in changes:
            event(conn, ident, stamp, kind, interface, ip, previous)
        # When no recorded handshake events are available, preserve an IP
        # baseline without inventing historical connection events.
        for ident, endpoint, handshake in conn.execute(
            "SELECT id,endpoint,handshake FROM peers"
        ).fetchall():
            ip = baseline.get(ident) or (endpoint_ip(endpoint) if handshake else "")
            conn.execute("UPDATE peers SET handshake_ip=? WHERE id=?", (ip, ident))
        conn.execute(
            "DELETE FROM events WHERE type NOT IN "
            "('endpoint_ip_observed','endpoint_ip_changed')"
        )
        conn.execute("INSERT OR IGNORE INTO properties(key,value) VALUES(?,?)",
                     (marker, "1"))


def record_handshake_ip(conn, ident, interface, endpoint, handshake, previous):
    ip = endpoint_ip(endpoint)
    if not ip or not handshake or ip == previous:
        return previous
    event(conn, ident, handshake,
          "endpoint_ip_changed" if previous else "endpoint_ip_observed",
          interface, ip, previous)
    return ip


def bucket(conn, ident, stamp, rx, tx, samples=0, resets=0, gaps=0):
    slot = (int(stamp) // 600) * 600
    conn.execute(
        "INSERT INTO buckets(peer_id,period,rx_bytes,tx_bytes,samples,resets,gaps) "
        "VALUES(?,?,?,?,?,?,?) ON CONFLICT(peer_id,period) DO UPDATE SET "
        "rx_bytes=rx_bytes+excluded.rx_bytes,tx_bytes=tx_bytes+excluded.tx_bytes,"
        "samples=samples+excluded.samples,resets=resets+excluded.resets,"
        "gaps=gaps+excluded.gaps",
        (ident, slot, max(0,int(rx)), max(0,int(tx)), samples, resets, gaps),
    )


def split_delta(conn, ident, before, after, rx, tx, gap=0):
    """Allocate measured counter growth proportionally at 10-minute borders.

    This interpolation is an approximation, not exact packet timing.
    """
    if before >= after:
        return
    chunks = []
    start = before
    while start < after:
        stop = min(after, ((start // 600) + 1) * 600)
        chunks.append((stop, stop - start))
        start = stop
    total = after - before
    accounted_rx = accounted_tx = 0
    for index, (stop, duration) in enumerate(chunks):
        last = index == len(chunks)-1
        part_rx = rx-accounted_rx if last else (rx*duration)//total
        part_tx = tx-accounted_tx if last else (tx*duration)//total
        accounted_rx += part_rx
        accounted_tx += part_tx
        bucket(conn, ident, stop-1, part_rx, part_tx,
               samples=1 if last else 0, gaps=gap if last else 0)


def migrate_legacy(conn, ident, public, interface, directory, stamp, interval):
    """Import once for a known key. Old JSONL filenames contain SHA256(key).

    The irreversible old filename hash cannot identify already deleted peers.
    We intentionally do not guess based on reused IP addresses or names.
    """
    marker="legacy_import:"+ident
    if conn.execute("SELECT 1 FROM properties WHERE key=?",(marker,)).fetchone():
        return
    imported=0
    if directory:
        filename=interface+"-peer-"+hashlib.sha256(public.encode("ascii")).hexdigest()+".jsonl"
        old=Path(directory)/filename
        if old.is_file() and not old.is_symlink():
            last=None
            with old.open("r",encoding="utf-8") as stream:
                for line in stream:
                    try:
                        record=json.loads(line)
                        t=int(record["timestamp"])
                        rx=int(record["rx"])
                        tx=int(record["tx"])
                        if t <= 0 or rx < 0 or tx < 0:
                            continue
                    except (ValueError,KeyError,TypeError,OverflowError):
                        continue
                    if last and t > last[0]:
                        before,old_rx,old_tx=last
                        if rx < old_rx or tx < old_tx:
                            bucket(conn,ident,t,0,0,resets=1)
                        else:
                            gap=int(t-before > max(60,3*interval))
                            split_delta(conn,ident,before,t,rx-old_rx,tx-old_tx,gap)
                            imported+=1
                    last=(t,rx,tx)
    # Import statistics without adding a noisy activity event.
    conn.execute("INSERT INTO properties(key,value) VALUES(?,?)",
                 (marker,str(imported)))


def ingest(conn, request):
    now = int(request.get("timestamp") or time.time())
    interval = max(2, min(3600, int(request.get("interval") or 5)))
    instances = request.get("interfaces") or {}
    observed = set()
    # Peer labels are *metadata*, not identity. Never merge based on a name.
    requested_names = request.get("peer_names") or {}
    names = requested_names if isinstance(requested_names, dict) else {}
    compact_legacy_activity(conn, conn.execute("PRAGMA database_list").fetchone()[2])
    with conn:
        conn.execute("BEGIN IMMEDIATE")
        for interface, data in instances.items():
            if not IFACE.fullmatch(interface):
                continue
            for peer in (data.get("peer_list") or []):
                public = peer.get("public_key", "")
                try:
                    ident = peer_id(public)
                except (ValueError, UnicodeError):
                    continue
                observed.add(ident)
                candidate_name = names.get(public, "")
                peer_name = candidate_name.strip()[:200] if isinstance(candidate_name, str) else ""
                endpoint = str(peer.get("endpoint") or "")
                if endpoint == "(none)":
                    endpoint = ""
                handshake = max(0, int(peer.get("latest_handshake") or 0))
                rx = max(0, int(peer.get("rx_bytes") or 0))
                tx = max(0, int(peer.get("tx_bytes") or 0))
                previous = conn.execute(
                    "SELECT active,endpoint,handshake,sample_at,rx,tx,interface,handshake_ip "
                    "FROM peers WHERE id=?", (ident,)).fetchone()
                if previous is None:
                    migrate_legacy(conn,ident,public,interface,request.get("legacy_dir"),
                                   now,interval)
                    confirmed_ip = record_handshake_ip(
                        conn, ident, interface, endpoint, handshake, "")
                    conn.execute("INSERT INTO peers(id,public_key,first_seen,last_seen,name,active,interface,"
                                 "endpoint,handshake,handshake_ip,sample_at,rx,tx) "
                                 "VALUES(?,?,?,?,?,?,?,?,?,?,?,?,?)",
                                 (ident,public,now,now,peer_name,1,interface,endpoint,
                                  handshake,confirmed_ip,now,rx,tx))
                    bucket(conn,ident,now,0,0,samples=1)
                    continue
                active, old_endpoint, old_handshake, before, old_rx, old_tx, old_interface, old_ip = previous
                confirmed_ip = old_ip
                if handshake > (old_handshake or 0):
                    confirmed_ip = record_handshake_ip(
                        conn, ident, interface, endpoint, handshake, old_ip)
                # Zero during a restart does not erase the latest known handshake.
                last_handshake = max(handshake, old_handshake or 0)
                reset = 0
                gap = 0
                if active and before is not None and now > before:
                    if rx < old_rx or tx < old_tx:
                        reset = 1
                        # Bucket reset counter remains; no event-log spam.
                        bucket(conn,ident,now,0,0,samples=1,resets=1)
                    else:
                        gap = int(now - before > max(60, interval * 3))
                        # Bucket gap counter remains; no event-log spam.
                        split_delta(conn,ident,int(before),now,rx-old_rx,tx-old_tx,gap)
                else:
                    bucket(conn,ident,now,0,0,samples=1,gaps=1 if not active else 0)
                conn.execute("UPDATE peers SET active=1,interface=?,last_seen=?,endpoint=?,"
                             "handshake=?,handshake_ip=?,sample_at=?,rx=?,tx=?,"
                             "name=CASE WHEN ?<>'' THEN ? ELSE name END WHERE id=?",
                             (interface,now,endpoint,last_handshake,confirmed_ip,
                              now,rx,tx,peer_name,peer_name,ident))
        # Update labels also for peers disabled in wg-quick configs: they
        # are absent from 'wg show dump' but remain in SQLite and in the
        # declarative config source of truth.
        for public, value in names.items():
            if isinstance(public, str) and isinstance(value, str):
                label = value.strip()[:200]
                if label:
                    conn.execute("UPDATE peers SET name=? WHERE public_key=?",
                                 (label, public))
        for ident, interface, endpoint in conn.execute(
            "SELECT id,interface,endpoint FROM peers WHERE active=1"
        ).fetchall():
            if ident not in observed:
                conn.execute("UPDATE peers SET active=0,sample_at=NULL,rx=NULL,tx=NULL WHERE id=?",
                             (ident,))
                # No routine disconnected event; history remains keyed to public key.
    return {"ok": True, "observed": len(observed)}


def query(conn, request):
    since = int(request.get("from") or (time.time()-86400))
    until = int(request.get("to") or time.time())
    if since < 0 or since >= until or until > time.time()+60 or until-since > 366*86400:
        raise ValueError("invalid range")
    ident = request.get("peer_id") or ""
    if ident and not KEY.fullmatch(ident):
        raise ValueError("invalid peer key fingerprint")
    interface = request.get("interface") or ""
    if interface and (not isinstance(interface,str) or
                      not re.fullmatch(r"[A-Za-z0-9_=+.-]{1,15}", interface)):
        raise ValueError("invalid interface")
    peers = [dict(zip(("id","public_key","first_seen","last_seen","name","active","interface","endpoint","handshake","handshake_ip"),
                      row)) for row in conn.execute(
            "SELECT id,public_key,first_seen,last_seen,name,active,interface,endpoint,handshake,handshake_ip "
            "FROM peers ORDER BY last_seen DESC LIMIT 2000")]
    if ident:
        row = conn.execute("SELECT interface FROM peers WHERE id=?", (ident,)).fetchone()
        if not row:
            raise ValueError("peer not found")
        if interface and row[0] != interface:
            raise ValueError("peer does not belong to the selected interface")
    # Windows are 10-minute quantized; include intersecting buckets.
    bfrom = (since//600)*600
    bto = ((until-1)//600)*600
    if ident:
        where, scope = "peer_id=? AND ", [ident]
    elif interface:
        where, scope = "peer_id IN (SELECT id FROM peers WHERE interface=?) AND ", [interface]
    else:
        where, scope = "", []
    args = scope + [bfrom,bto]
    chart_points = int(request.get("chart_points") or 0)
    if chart_points:
        # Group inside SQLite before exporting. Even a one-year all-peer
        # report must include *all* rows, never only the newest 20,000.
        chart_points = max(1, min(720, chart_points))
        count = (bto-bfrom)//600+1
        factor = max(1, (count+chart_points-1)//chart_points)
        step = factor*600
        rows = conn.execute(
            "SELECT ((period-?)/?)*?+?,SUM(rx_bytes),SUM(tx_bytes),"
            "SUM(samples),SUM(resets),SUM(gaps) FROM buckets WHERE "+
            where+"period>=? AND period<=? GROUP BY 1 ORDER BY 1",
            [bfrom,step,step,bfrom]+args).fetchall()
        buckets = [dict(zip(("period","rx","tx","samples","resets","gaps"),r))
                   for r in rows]
        truncated = False
    else:
        # Retained for compatibility with existing raw-bucket API callers.
        step = 600
        rows = conn.execute(
            "SELECT peer_id,period,rx_bytes,tx_bytes,samples,resets,gaps FROM buckets WHERE "+
            where+"period>=? AND period<=? ORDER BY period DESC LIMIT 20001",args).fetchall()
        truncated = len(rows) > 20000
        rows = rows[:20000]
        buckets = [dict(zip(("peer_id","period","rx","tx","samples","resets","gaps"),r))
                   for r in reversed(rows)]
    eargs = scope + [since,until]
    # Event predicates deliberately do not reuse bucket WHERE (period column).
    condition = where
    events = conn.execute(
        "SELECT peer_id,at,type,interface,endpoint,previous_endpoint,detail "
        "FROM events WHERE "+condition+"type IN ('endpoint_ip_observed','endpoint_ip_changed') "
        "AND at>=? AND at<=? "
        "ORDER BY at DESC,id DESC LIMIT 2001",eargs).fetchall()
    events_truncated=len(events)>2000
    events=events[:2000]
    report = {"ok":True,"from":since,"to":until,"bucket_seconds":step,
              "truncated":truncated,"events_truncated":events_truncated,
              "db_bytes":os.stat(conn.execute("PRAGMA database_list").fetchone()[2]).st_size,
              "peers":peers,"buckets":buckets,
              "events":[dict(zip(("peer_id","at","type","interface","endpoint","previous","detail"),e))
                        for e in events],
              "totals":{"rx":sum(b["rx"] for b in buckets),
                        "tx":sum(b["tx"] for b in buckets),
                        "resets":sum(b["resets"] for b in buckets),
                        "gaps":sum(b["gaps"] for b in buckets)}}
    return report


def backup(conn, path):
    target = Path(path).parent / "backups"
    target.mkdir(mode=0o700,exist_ok=True)
    dest = target / ("analytics-"+str(int(time.time()))+"-"+str(os.getpid())+".sqlite3")
    with sqlite3.connect(str(dest)) as other:
        conn.backup(other)
    os.chmod(dest,0o600)
    files=sorted(target.glob("analytics-*.sqlite3"), key=lambda p:p.stat().st_mtime,reverse=True)
    for old in files[5:]:
        old.unlink()
    return str(dest)


def maintain(conn, request, path):
    action=request.get("action")
    if action not in ("delete_before","delete_peer","purge","vacuum","prune"):
        raise ValueError("invalid maintenance action")
    if action in ("delete_before","delete_peer","purge") and request.get("confirm") != "DELETE":
        raise ValueError("explicit confirmation required")
    ident=request.get("peer_id") or ""
    if action=="delete_peer" and not KEY.fullmatch(ident):
        raise ValueError("invalid peer fingerprint")
    cutoff=int(request.get("before") or 0)
    if action in ("delete_before","prune") and cutoff <= 0:
        raise ValueError("valid cutoff required")
    copy_path = backup(conn,path) if action in ("delete_before","delete_peer","purge") else ""
    with conn:
        conn.execute("BEGIN IMMEDIATE")
        if action in ("delete_before","prune"):
            # Ten-minute buckets cannot be sliced by individual seconds.
            # Delete only buckets wholly before the timestamp boundary.
            bucket_cutoff=(cutoff//600)*600
            conn.execute("DELETE FROM buckets WHERE period<?",(bucket_cutoff,))
            conn.execute("DELETE FROM events WHERE at<?",(cutoff,))
            # Do not erase peer identities/states on retention maintenance.
        elif action=="delete_peer":
            conn.execute("DELETE FROM buckets WHERE peer_id=?",(ident,))
            conn.execute("DELETE FROM events WHERE peer_id=?",(ident,))
            conn.execute("DELETE FROM peers WHERE id=?",(ident,))
        elif action=="purge":
            for table in ("buckets","events","peers"):
                conn.execute("DELETE FROM "+table)
    if action=="vacuum":
        conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        conn.execute("VACUUM")
    return {"ok":True,"action":action,"backup":copy_path}


def prometheus(conn, request):
    path=request.get("path") or ""
    if not re.fullmatch(
        r"/(?:var/lib/node_exporter/textfile_collector|var/lib/prometheus/node-exporter)/"
        r"[A-Za-z0-9_.-]+\.prom",path
    ) or ".." in path:
        raise ValueError("Prometheus path must be in an approved node exporter textfile directory")
    dest=Path(path)
    if not dest.parent.is_dir() or dest.is_symlink():
        raise ValueError("Prometheus target directory missing or unsafe")
    enabled=set(request.get("metrics") or [])
    if not enabled.issubset(VALID_METRICS):
        raise ValueError("invalid metrics selection")
    output=render_prometheus_text(conn,enabled)
    fd,tmp=tempfile.mkstemp(dir=str(dest.parent),prefix=".webmin-wg-",suffix=".tmp")
    try:
        with os.fdopen(fd,"w",encoding="utf-8") as f:
            f.write(output)
            f.flush()
            os.fsync(f.fileno())
        os.chmod(tmp,0o644)
        os.replace(tmp,path)
    finally:
        if os.path.exists(tmp): os.unlink(tmp)
    return {"ok":True,"metrics":len(output.splitlines())}


def render_prometheus_text(conn,enabled):
    out=[]
    def metric(name,description,kind,rows):
        out.append("# HELP "+name+" "+description)
        out.append("# TYPE "+name+" "+kind)
        out.extend(rows)
    peers=conn.execute("SELECT id,active,handshake FROM peers").fetchall()
    if "traffic" in enabled:
        all_usage=conn.execute("SELECT peer_id,SUM(rx_bytes),SUM(tx_bytes) FROM buckets GROUP BY peer_id")
        rx=[];tx=[]
        for ident,rec,send in all_usage:
            rx.append('webmin_wg_peer_stored_rx_bytes{peer="'+ident+'"} '+str(rec or 0))
            tx.append('webmin_wg_peer_stored_tx_bytes{peer="'+ident+'"} '+str(send or 0))
        metric("webmin_wg_peer_stored_rx_bytes","Recorded RX bytes in retained history","gauge",rx)
        metric("webmin_wg_peer_stored_tx_bytes","Recorded TX bytes in retained history","gauge",tx)
    if "peer_state" in enabled:
        metric("webmin_wg_peer_active","Peer present in last successful WireGuard snapshot","gauge",
               ['webmin_wg_peer_active{peer="'+i+'"} '+str(a) for i,a,h in peers])
    if "handshake" in enabled:
        metric("webmin_wg_peer_last_handshake_timestamp_seconds",
               "Last observed handshake UNIX timestamp","gauge",
               ['webmin_wg_peer_last_handshake_timestamp_seconds{peer="'+i+'"} '+str(h or 0)
                for i,a,h in peers])
    if "events" in enabled:
        metric("webmin_wg_stored_events","Events retained in SQLite","gauge",
               ["webmin_wg_stored_events "+str(conn.execute("SELECT count(*) FROM events").fetchone()[0])])
    if "collector" in enabled:
        metric("webmin_wg_analytics_export_timestamp_seconds","Last successful exporter run","gauge",
               ["webmin_wg_analytics_export_timestamp_seconds "+str(int(time.time()))])
    return "\n".join(out)+"\n"


def peer_handshake_ip(conn, request):
    """Read only the IP observed at the last confirmed handshake for a key."""
    ident = request.get("peer_id")
    if not isinstance(ident,str) or not KEY.fullmatch(ident):
        raise ValueError("invalid peer key fingerprint")
    row=conn.execute(
        "SELECT handshake,handshake_ip FROM peers WHERE id=?", (ident,)
    ).fetchone()
    if not row or not row[0] or not row[1]:
        return {"ok":True,"available":False,"handshake":int(row[0]) if row else 0}
    try:
        ip=ipaddress.ip_address(row[1])
    except ValueError:
        return {"ok":True,"available":False,"handshake":int(row[0])}
    return {"ok":True,"available":True,"ip":str(ip),"handshake":int(row[0]),
            "public":ip.is_global}


def main():
    os.umask(0o077)
    if len(sys.argv)!=3 or sys.argv[1] not in ("ingest","query","peer_ip","network_record","network_lookup","network_manage","maintain","prometheus","health"):
        raise ValueError("usage: analytics-store.py ACTION /absolute/path.sqlite3")
    action,path=sys.argv[1:]
    body=json.load(sys.stdin)
    conn=connect(path)
    try:
        if action=="ingest": result=ingest(conn,body)
        elif action=="query": result=query(conn,body)
        elif action=="peer_ip": result=peer_handshake_ip(conn,body)
        elif action=="network_record": result=network_record(conn,body)
        elif action=="network_lookup": result=network_lookup(conn,body)
        elif action=="network_manage": result=network_manage(conn,body)
        elif action=="maintain": result=maintain(conn,body,path)
        elif action=="prometheus": result=prometheus(conn,body)
        else:
            result={"ok":True,"peers":conn.execute("SELECT COUNT(*) FROM peers").fetchone()[0],
                    "buckets":conn.execute("SELECT COUNT(*) FROM buckets").fetchone()[0],
                    "events":conn.execute("SELECT COUNT(*) FROM events").fetchone()[0],
                    "db_bytes":os.stat(path).st_size}
        print(json.dumps(result,ensure_ascii=True,separators=(",",":")))
    finally:
        conn.close()


if __name__=="__main__":
    try: main()
    except Exception as exc:
        print(json.dumps({"ok":False,"error":str(exc)},ensure_ascii=True))
        sys.exit(1)
