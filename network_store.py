"""Network identity directory: manual icons, WHOIS ranges and exact-IP GeoIP.

This module owns network-directory persistence and matching logic. Its tables
currently share the same SQLite connection as peer analytics; their lifecycle
and API functions are separate. No network queries are issued on page load.
"""
import ipaddress
import re
import time
from unlocode_store import lookup as locode_lookup

NETWORK_SCHEMA = """
CREATE TABLE IF NOT EXISTS network_cache (
    cidr TEXT PRIMARY KEY, owner TEXT NOT NULL DEFAULT '',
    country TEXT NOT NULL DEFAULT '', observed_at INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS network_icons (
    cidr TEXT PRIMARY KEY, icon TEXT NOT NULL DEFAULT '?',
    label TEXT NOT NULL DEFAULT '', city TEXT NOT NULL DEFAULT '',
    city_code TEXT NOT NULL DEFAULT ''
);
CREATE TABLE IF NOT EXISTS geoip_cache (
    ip TEXT PRIMARY KEY,
    country_code TEXT NOT NULL, city TEXT NOT NULL DEFAULT '',
    city_code TEXT NOT NULL DEFAULT '', observed_at INTEGER NOT NULL DEFAULT 0
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
    geoip_country = req.get("geoip_country_code") or ""
    if not isinstance(geoip_country, str) or (geoip_country and
            not re.fullmatch(r"[A-Z]{2}", geoip_country)):
        raise ValueError("invalid GeoIP country code")
    geoip_city = req.get("geoip_city") or ""
    geoip_city_code = locode_lookup(conn, geoip_country, geoip_city)
    if not isinstance(geoip_city, str) or len(geoip_city) > 100 or any(ord(c)<32 for c in geoip_city):
        raise ValueError("invalid GeoIP city")
    if not isinstance(geoip_city_code, str) or not re.fullmatch(r"(?:[A-Z]{2}[A-Z0-9]{3})?",geoip_city_code):
        raise ValueError("invalid GeoIP city abbreviation")
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
        # Retain every explicitly queried IP, including one with no GeoIP result.
        # Otherwise absent City/Country entries could never be retried.
        conn.execute(
            "INSERT INTO geoip_cache(ip,country_code,city,city_code,observed_at) VALUES(?,?,?,?,?) "
            "ON CONFLICT(ip) DO UPDATE SET country_code=excluded.country_code,"
            "city=excluded.city,city_code=excluded.city_code,"
            "observed_at=excluded.observed_at",
            (str(ip), geoip_country, geoip_city,geoip_city_code,int(time.time())))
    return {"ok": True, "cidr": cidr}


def network_lookup(conn, req):
    ips = req.get("ips") or []
    if not isinstance(ips, list) or len(ips) > 128:
        raise ValueError("invalid IP list")
    cached = [(ipaddress.ip_network(net), owner, country) for net, owner, country
              in conn.execute("SELECT cidr,owner,country FROM network_cache")]
    icons = [(ipaddress.ip_network(net), icon, label, city, city_code) for net, icon, label, city, city_code
             in conn.execute("SELECT cidr,icon,label,city,city_code FROM network_icons")]
    geoip = {ip: (code,city,city_code) for ip, code, city, city_code in conn.execute(
        "SELECT ip,country_code,city,city_code FROM geoip_cache WHERE observed_at>=?",
        (int(time.time())-30*86400,))}
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
        country_code,city,city_code = geoip.get(str(ip), ("","",""))
        if city and country_code:
            city_code = locode_lookup(conn,country_code,city)
        registered_country = hit[2] if hit else ""
        # Preserve the exact request literal as the map key. Browser runtime
        # endpoints can use a non-canonical IPv6 spelling (e.g. leading zeros).
        result[raw] = {
            "icon": manual[1] if manual else "?",
            "label": manual[2] if manual else (hit[1] if hit else ""),
            "cidr": str(manual[0] if manual else hit[0]) if (manual or hit) else "",
            "country": country_code or registered_country,
            "country_source": "geoip" if country_code else ("whois" if registered_country else ""),
            "whois_country": registered_country,
            "geoip_country": country_code,
            "city": (manual[3] if manual and manual[3] else city),
            "city_code": (manual[4] if manual and manual[4] else city_code),
            "city_source": "manual" if manual and (manual[3] or manual[4]) else ("unlocode" if city_code else ("geoip" if city else "")),
            "cached": bool(hit or country_code),
        }
    return {"ok": True, "results": result}


def network_manage(conn, req):
    action = req.get("action")
    if action == "list":
        cache = [dict(zip(("cidr", "owner", "country", "observed_at"), row)) for row
                 in conn.execute("SELECT cidr,owner,country,observed_at FROM network_cache "
                                 "ORDER BY observed_at DESC LIMIT 1000")]
        icons = [dict(zip(("cidr", "icon", "label", "city", "city_code"), row)) for row in
                 conn.execute("SELECT cidr,icon,label,city,city_code FROM network_icons ORDER BY cidr LIMIT 1000")]
        observations = [
            (ipaddress.ip_address(ip), code,city,city_code)
            for ip, code, city, city_code in conn.execute(
                "SELECT ip,country_code,city,city_code FROM geoip_cache "
                "ORDER BY observed_at DESC LIMIT 1000")]
        for item in cache:
            prefix=ipaddress.ip_network(item["cidr"])
            item["observed_ips"]=[str(ip) for ip,code,city,city_code in observations
                                  if ip in prefix]
            prefix = ipaddress.ip_network(item["cidr"])
            # These are observed IP countries, NOT a location assigned to
            # the entire WHOIS prefix. Preserve this distinction in the UI.
            item["geoip_countries"] = sorted({
                code for ip, code, city, city_code in observations if ip in prefix
            })
            item["geoip_city_names"] = sorted({
                city for ip, code, city, city_code in observations
                if ip in prefix and city
            })
            item["geoip_cities"] = sorted({
                locode_lookup(conn, code, city) or city
                for ip, code, city, city_code in observations
                if ip in prefix and city
            })
        count=conn.execute("SELECT COUNT(*) FROM unlocode_places").fetchone()[0]
        return {"ok": True, "cache": cache, "icons": icons, "unlocode_count": count}
    if action == "search_unlocode":
        term=req.get("term") or ""
        country=req.get("country") or ""
        if not isinstance(term,str) or len(term)>80 or len(term.strip())<2:
            return {"ok":True,"matches":[]}
        if not isinstance(country,str) or (country and not re.fullmatch(r"[A-Z]{2}",country)):
            raise ValueError("invalid country filter")
        from unlocode_store import normalize
        key=normalize(term)
        if not key or len(key)<2:
            return {"ok":True,"matches":[]}
        escaped=key.replace("\\","\\\\").replace("%","\\%").replace("_","\\_")
        where="WHERE (name_key LIKE ? ESCAPE '\\' OR ascii_key LIKE ? ESCAPE '\\')"
        args=[escaped+"%",escaped+"%"]
        if country:
            where+=" AND country=?"
            args.append(country)
        if re.fullmatch(r"[A-Z]{2}[A-Z0-9]{3}",term.strip().upper()):
            where+=" OR (country || code)=?"
            args.append(term.strip().upper())
        rows=conn.execute("SELECT country,code,name,subdivision FROM unlocode_places "+
                          where+" ORDER BY name_key,country,code LIMIT 25",args).fetchall()
        return {"ok":True,"matches":[{"code":c+loc,"name":name,"country":c,
                                      "subdivision":sub} for c,loc,name,sub in rows]}
    if action == "check_observed_ip":
        raw=req.get("ip") or ""
        try:
            ip=ipaddress.ip_address(raw)
        except ValueError as exc:
            raise ValueError("invalid observed IP") from exc
        if not ip.is_global:
            raise ValueError("only public addresses may be refreshed")
        known=conn.execute("SELECT 1 FROM geoip_cache WHERE ip=?",(str(ip),)).fetchone()
        return {"ok":True,"known":bool(known)}
    if action == "get_observed_ip":
        raw=req.get("ip") or ""
        try:
            ip=ipaddress.ip_address(raw)
        except ValueError as exc:
            raise ValueError("invalid observed IP") from exc
        if not ip.is_global:
            raise ValueError("invalid observed IP")
        row=conn.execute("SELECT country_code,city,city_code FROM geoip_cache WHERE ip=?",
                         (str(ip),)).fetchone()
        if not row:
            raise ValueError("IP is not in the observed cache")
        return {"ok":True,"country":row[0],"city":row[1],"city_code":row[2]}
    if action == "refresh_geoip":
        raw=req.get("ip") or ""
        try:
            ip=ipaddress.ip_address(raw)
        except ValueError as exc:
            raise ValueError("invalid observed IP") from exc
        if not ip.is_global or not conn.execute(
                "SELECT 1 FROM geoip_cache WHERE ip=?",(str(ip),)).fetchone():
            raise ValueError("IP is not in the observed cache")
        country=req.get("country") or ""
        city=req.get("city") or ""
        if country and not re.fullmatch(r"[A-Z]{2}",country):
            raise ValueError("invalid country")
        if not isinstance(city,str) or len(city)>100 or any(ord(c)<32 for c in city):
            raise ValueError("invalid city")
        code=locode_lookup(conn,country,city)
        with conn:
            conn.execute("UPDATE geoip_cache SET country_code=?,city=?,city_code=?,observed_at=? "
                         "WHERE ip=?",(country,city,code,int(time.time()),str(ip)))
        return {"ok":True,"city_code":code}
    if action == "refresh_whois":
        raw=req.get("ip") or ""
        try:
            ip=ipaddress.ip_address(raw)
        except ValueError as exc:
            raise ValueError("invalid observed IP") from exc
        if not ip.is_global or not conn.execute(
                "SELECT 1 FROM geoip_cache WHERE ip=?",(str(ip),)).fetchone():
            raise ValueError("IP is not in the observed cache")
        # Keep existing per-IP GeoIP fields when refreshing WHOIS only.
        record=conn.execute("SELECT country_code,city FROM geoip_cache WHERE ip=?",
                            (str(ip),)).fetchone()
        return network_record(conn,{"ip":str(ip),
            "geoip_country_code":record[0],"geoip_city":record[1],
            "whois_fields":req.get("whois_fields") or []})
    if action == "clear_cache":
        if req.get("confirm") != "CLEAR":
            raise ValueError("explicit cache reset confirmation required")
        with conn:
            count = conn.execute("SELECT COUNT(*) FROM network_cache").fetchone()[0]
            conn.execute("DELETE FROM network_cache")
            conn.execute("DELETE FROM geoip_cache")
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
    city,city_code=req.get("city") or "",req.get("city_code") or ""
    # A manually supplied 5-character UN/LOCODE is allowed only if catalog-backed.
    city_code = city_code.strip().upper() if isinstance(city_code,str) else city_code
    if city_code:
        if not re.fullmatch(r"[A-Z]{2}[A-Z0-9]{3}", city_code):
            raise ValueError("invalid UN/LOCODE")
        found=conn.execute("SELECT name FROM unlocode_places WHERE country=? AND code=?",
                           (city_code[:2],city_code[2:])).fetchone()
        if not found:
            raise ValueError("unknown UN/LOCODE")
        # A selected official code also supplies the canonical place name.
        # Preserve a manually entered spelling when one was explicitly given.
        if not city.strip():
            city=found[0]
    elif city:
        # A CIDR override may span locations; without explicit country no guessing.
        city_code = ""
    if not isinstance(city,str) or len(city)>100 or any(ord(c)<32 for c in city):
        raise ValueError("invalid manual city")
    if not isinstance(city_code,str) or not re.fullmatch(r"(?:[A-Z]{2}[A-Z0-9]{3})?",city_code):
        raise ValueError("invalid manual city code")
    with conn:
        conn.execute("INSERT INTO network_icons(cidr,icon,label,city,city_code) VALUES(?,?,?,?,?) "
                     "ON CONFLICT(cidr) DO UPDATE SET icon=excluded.icon,label=excluded.label,"
                     "city=excluded.city,city_code=excluded.city_code",
                     (cidr, icon, label, city,city_code))
    return {"ok": True}

