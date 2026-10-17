"""Network identity directory: manual icons, WHOIS ranges and exact-IP GeoIP.

This module owns network-directory persistence and matching logic. Its tables
currently share the same SQLite connection as peer analytics; their lifecycle
and API functions are separate. No network queries are issued on page load.
"""
import ipaddress
import re
import time

NETWORK_SCHEMA = """
CREATE TABLE IF NOT EXISTS network_cache (
    cidr TEXT PRIMARY KEY, owner TEXT NOT NULL DEFAULT '',
    country TEXT NOT NULL DEFAULT '', observed_at INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS network_icons (
    cidr TEXT PRIMARY KEY, icon TEXT NOT NULL DEFAULT '?',
    label TEXT NOT NULL DEFAULT ''
);
"""

# WHOIS prefix facts and administrator-assigned icons have independent lifecycles.
# A cache reset never removes icon mappings. Everything here is local SQLite.
def valid_network(value):
    if not isinstance(value, str) or len(value) > 64:
        raise ValueError("invalid network prefix")
    try:
        network = ipaddress.ip_network(value, strict=True)
    except ValueError as error:
        raise ValueError("invalid network prefix") from error
    return str(network)


def network_record(conn, req):
    """Called only after a user explicitly requests a confirmed handshake IP."""
    try:
        ip = ipaddress.ip_address(req.get("ip") or "")
    except ValueError as error:
        raise ValueError("invalid IP") from error
    if not ip.is_global:
        raise ValueError("only public IPs may enter lookup cache")
    fields = req.get("whois_fields") or []
    if not isinstance(fields, list) or len(fields) > 30:
        raise ValueError("invalid WHOIS fields")
    prefix_candidates = []
    owner, country = "", ""
    for item in fields:
        if not isinstance(item, dict):
            continue
        label, value = str(item.get("label") or ""), str(item.get("value") or "")
        if len(value) > 512:
            continue
        if label in ("Organization", "Network name") and not owner:
            owner = value[:120]
        if label == "Country" and not country:
            country = value[:70]
        if label in ("CIDR", "Network range"):
            for fragment in value.split(",")[:16]:
                fragment = fragment.strip()
                try:
                    if " - " in fragment:
                        lo, hi = fragment.split(" - ", 1)
                        first, last = ipaddress.ip_address(lo.strip()), ipaddress.ip_address(hi.strip())
                        if first.version != last.version or int(first) > int(last):
                            continue
                        parts = list(ipaddress.summarize_address_range(first, last))
                    else:
                        parts = [ipaddress.ip_network(fragment, strict=False)]
                    prefix_candidates += [x for x in parts if ip in x]
                except ValueError:
                    continue
    # Do not treat unverifiable network ranges as authoritative; store the
    # single confirmed IP as /32 or /128 until a valid WHOIS range is known.
    best = max(prefix_candidates, key=lambda n: n.prefixlen) if prefix_candidates else \
        ipaddress.ip_network(f"{ip}/{ip.max_prefixlen}")
    cidr = str(best)
    with conn:
        conn.execute(
            "INSERT INTO network_cache(cidr,owner,country,observed_at) VALUES(?,?,?,?) "
            "ON CONFLICT(cidr) DO UPDATE SET owner=excluded.owner,"
            "country=excluded.country,observed_at=excluded.observed_at",
            (cidr, owner, country, int(time.time())))
    return {"ok": True, "cidr": cidr}


def network_lookup(conn, req):
    ips = req.get("ips") or []
    if not isinstance(ips, list) or len(ips) > 128:
        raise ValueError("invalid IP list")
    cached = [(ipaddress.ip_network(net), owner, country) for net, owner, country
              in conn.execute("SELECT cidr,owner,country FROM network_cache")]
    icons = [(ipaddress.ip_network(net), icon, label) for net, icon, label
             in conn.execute("SELECT cidr,icon,label FROM network_icons")]
    result = {}
    for raw in ips:
        if not isinstance(raw, str) or len(raw) > 64:
            continue
        try:
            ip = ipaddress.ip_address(raw)
        except ValueError:
            continue
        hit = max((entry for entry in cached if ip in entry[0]), 
                  key=lambda entry: entry[0].prefixlen, default=None)
        manual = max((entry for entry in icons if ip in entry[0]),
                     key=lambda entry: entry[0].prefixlen, default=None)
        # Preserve the exact request literal as the map key. Browser runtime
        # endpoints can use a non-canonical IPv6 spelling (e.g. leading zeros).
        result[raw] = {
            "icon": manual[1] if manual else "?",
            "label": manual[2] if manual else (hit[1] if hit else ""),
            "cidr": str(manual[0] if manual else hit[0]) if (manual or hit) else "",
            "country": hit[2] if hit else "",
            "cached": bool(hit),
        }
    return {"ok": True, "results": result}


def network_manage(conn, req):
    action = req.get("action")
    if action == "list":
        cache = [dict(zip(("cidr", "owner", "country", "observed_at"), row)) for row
                 in conn.execute("SELECT cidr,owner,country,observed_at FROM network_cache "
                                 "ORDER BY observed_at DESC LIMIT 1000")]
        icons = [dict(zip(("cidr", "icon", "label"), row)) for row in
                 conn.execute("SELECT cidr,icon,label FROM network_icons ORDER BY cidr LIMIT 1000")]
        return {"ok": True, "cache": cache, "icons": icons}
    if action == "clear_cache":
        if req.get("confirm") != "CLEAR":
            raise ValueError("explicit cache reset confirmation required")
        with conn:
            count = conn.execute("SELECT COUNT(*) FROM network_cache").fetchone()[0]
            conn.execute("DELETE FROM network_cache")
        return {"ok": True, "deleted": count}
    if action not in ("set_icon", "delete_icon"):
        raise ValueError("invalid network icon action")
    cidr = valid_network(req.get("cidr"))
    if action == "delete_icon":
        with conn:
            conn.execute("DELETE FROM network_icons WHERE cidr=?", (cidr,))
        return {"ok": True}
    icon, label = req.get("icon") or "?", req.get("label") or ""
    if not isinstance(icon, str) or len(icon) > 8 or any(ord(c) < 32 for c in icon):
        raise ValueError("invalid icon")
    if not isinstance(label, str) or len(label) > 100 or any(ord(c) < 32 for c in label):
        raise ValueError("invalid label")
    with conn:
        conn.execute("INSERT INTO network_icons(cidr,icon,label) VALUES(?,?,?) "
                     "ON CONFLICT(cidr) DO UPDATE SET icon=excluded.icon,label=excluded.label",
                     (cidr, icon, label))
    return {"ok": True}

