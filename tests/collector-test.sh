#!/bin/sh
set -eu
BASE=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/wg" <<'EOF'
#!/bin/sh
printf '%s\n' \
'wg0	PRIVATE0	PUBLIC0	51820	off' \
'wg0	PEER1	(none)	198.51.100.2:50000	10.0.0.2/32	1700000000	1024	2048	25'
EOF
chmod +x "$TMP/wg"
cat > "$TMP/config" <<EOF
wg_cmd=$TMP/wg
stats_dir=$TMP/stats
stats_refresh_interval=5
stats_history_retention=86400
stats_history_enabled=1
runtime_timeout=2
EOF
WEBMIN_WIREGUARD_CONFIG="$TMP/config" WEBMIN_WIREGUARD_ONCE=1 perl "$BASE/stats-collector.pl"
test -s "$TMP/stats/runtime.json"
test -s "$TMP/stats/wg0-interface.jsonl"
perl -MJSON::PP -e '
  local $/; open my $fh, "<", $ARGV[0] or die $!; my $d=decode_json(<$fh>);
  die "missing wg0" unless $d->{interfaces}{wg0};
  die "wrong port" unless $d->{interfaces}{wg0}{interface}{listen_port} eq "51820";
  die "private key leaked" if $d->{interfaces}{wg0}{interface}{private_key};
  die "wrong totals" unless $d->{interfaces}{wg0}{rx_bytes} == 1024 && $d->{interfaces}{wg0}{tx_bytes} == 2048;
' "$TMP/stats/runtime.json"
echo "collector runtime cache tests passed"
# Bounded history: pre-load more than the configured point limit. The one-shot
# run performs compaction and must keep the file bounded.
now=$(date +%s)
: > "$TMP/stats/wg0-peer-test.jsonl"
i=1
while [ "$i" -le 150 ]; do
    printf '{"timestamp":%s,"rx":%s,"tx":%s}\n' "$now" "$i" "$i" >> "$TMP/stats/wg0-peer-test.jsonl"
    i=$((i+1))
done
cat >> "$TMP/config" <<EOF
stats_max_points=100
stats_max_file_bytes=262144
stats_max_total_bytes=1048576
stats_health_interval=5
EOF
WEBMIN_WIREGUARD_CONFIG="$TMP/config" WEBMIN_WIREGUARD_ONCE=1 perl "$BASE/stats-collector.pl"
lines=$(wc -l < "$TMP/stats/wg0-peer-test.jsonl")
[ "$lines" -le 100 ] || { echo "history point cap failed: $lines" >&2; exit 1; }
test -s "$TMP/stats/health.json"
perl -MJSON::PP -0777 -e '$d=decode_json(<>); die "health missing limit" unless $d->{max_total_bytes}; die "health pid missing" unless $d->{pid};' < "$TMP/stats/health.json"
# Graceful stop: a long polling interval must not delay systemd-style TERM.
cat > "$TMP/config-stop" <<EOF2
wg_cmd=$TMP/wg
stats_dir=$TMP/stats-stop
stats_refresh_interval=60
stats_history_enabled=0
runtime_timeout=2
stats_health_interval=5
EOF2
WEBMIN_WIREGUARD_CONFIG="$TMP/config-stop" perl "$BASE/stats-collector.pl" >"$TMP/collector.out" 2>&1 &
collector_pid=$!
i=0
while [ ! -s "$TMP/stats-stop/runtime.json" ] && [ "$i" -lt 50 ]; do
    sleep 0.1
    i=$((i+1))
done
test -s "$TMP/stats-stop/runtime.json"
kill -TERM "$collector_pid"
i=0
while kill -0 "$collector_pid" 2>/dev/null && [ "$i" -lt 50 ]; do
    sleep 0.1
    i=$((i+1))
done
if kill -0 "$collector_pid" 2>/dev/null; then
    kill -KILL "$collector_pid" 2>/dev/null || true
    wait "$collector_pid" 2>/dev/null || true
    echo "collector did not stop promptly after TERM" >&2
    exit 1
fi
wait "$collector_pid" 2>/dev/null || true
perl -MJSON::PP -0777 -e '$d=decode_json(<>); die "collector did not record stopped state" unless ($d->{state}||"") eq "stopped" && !$d->{running};' < "$TMP/stats-stop/health.json"
echo "collector graceful-stop tests passed"
# Existing history must be trimmed immediately when retention/point/size limits
# are reduced and the collector is restarted.
POLICY_DIR="$TMP/stats-policy"
mkdir -p "$POLICY_DIR"
old=$((now-10000))
: > "$POLICY_DIR/wg0-peer-policy.jsonl"
i=1
while [ "$i" -le 50 ]; do
    printf '{"timestamp":%s,"rx":%s,"tx":%s,"pad":"old"}\n' "$old" "$i" "$i" >> "$POLICY_DIR/wg0-peer-policy.jsonl"
    i=$((i+1))
done
i=1
while [ "$i" -le 180 ]; do
    printf '{"timestamp":%s,"rx":%s,"tx":%s,"pad":"new"}\n' "$now" "$i" "$i" >> "$POLICY_DIR/wg0-peer-policy.jsonl"
    i=$((i+1))
done
cat > "$TMP/config-policy" <<EOF3
wg_cmd=$TMP/wg
stats_dir=$POLICY_DIR
stats_refresh_interval=5
stats_history_retention=300
stats_history_enabled=1
runtime_timeout=2
stats_max_points=100
stats_max_file_bytes=262144
stats_max_total_bytes=1048576
stats_health_interval=5
EOF3
WEBMIN_WIREGUARD_CONFIG="$TMP/config-policy" WEBMIN_WIREGUARD_ONCE=1 perl "$BASE/stats-collector.pl"
lines=$(wc -l < "$POLICY_DIR/wg0-peer-policy.jsonl")
[ "$lines" -le 100 ] || { echo "reduced point limit was not applied: $lines" >&2; exit 1; }
if grep -q '"pad":"old"' "$POLICY_DIR/wg0-peer-policy.jsonl"; then
    echo "reduced retention was not applied" >&2
    exit 1
fi
perl -MJSON::PP -0777 -e '$d=decode_json(<>); die "fingerprint missing" unless $d->{config_fingerprint}; die "compaction summary missing" unless $d->{last_compaction}; die "wrong point policy" unless $d->{max_points} == 100;' < "$POLICY_DIR/health.json"

# Per-file and aggregate byte limits must apply to already existing data.
PAD=$(printf '%01024d' 0)
for n in 1 2 3 4; do
    f="$POLICY_DIR/wg0-peer-big$n.jsonl"
    : > "$f"
    i=1
    while [ "$i" -le 180 ]; do
        printf '{"timestamp":%s,"rx":%s,"tx":%s,"pad":"%s"}\n' "$now" "$i" "$i" "$PAD" >> "$f"
        i=$((i+1))
    done
done
cat > "$TMP/config-policy-tight" <<EOF4
wg_cmd=$TMP/wg
stats_dir=$POLICY_DIR
stats_refresh_interval=5
stats_history_retention=300
stats_history_enabled=1
runtime_timeout=2
stats_max_points=10000
stats_max_file_bytes=262144
stats_max_total_bytes=262144
stats_health_interval=5
EOF4
WEBMIN_WIREGUARD_CONFIG="$TMP/config-policy-tight" WEBMIN_WIREGUARD_ONCE=1 perl "$BASE/stats-collector.pl"
history_total=$(find "$POLICY_DIR" -maxdepth 1 -type f -name '*.jsonl' -printf '%s\n' | awk '{s+=$1} END {print s+0}')
[ "$history_total" -le 262144 ] || { echo "aggregate history limit was not applied: $history_total" >&2; exit 1; }
for f in "$POLICY_DIR"/*.jsonl; do
    [ -e "$f" ] || continue
    size=$(wc -c < "$f")
    [ "$size" -le 262144 ] || { echo "per-file history limit was not applied: $f $size" >&2; exit 1; }
done
perl -MJSON::PP -0777 -e '$d=decode_json(<>); die "health storage exceeds policy" if $d->{history_storage_bytes} > $d->{max_total_bytes};' < "$POLICY_DIR/health.json"
echo "collector reduced-policy compaction tests passed"

# TERM must interrupt a blocked wg command, not wait for runtime_timeout or
# systemd TimeoutStopSec.
cat > "$TMP/wg-slow" <<EOF5
#!/bin/sh
trap 'exit 0' TERM INT HUP
touch "$TMP/wg-slow.started"
sleep 30
EOF5
chmod +x "$TMP/wg-slow"
cat > "$TMP/config-slow" <<EOF6
wg_cmd=$TMP/wg-slow
stats_dir=$TMP/stats-slow
stats_refresh_interval=60
stats_history_enabled=0
runtime_timeout=60
stats_health_interval=5
EOF6
WEBMIN_WIREGUARD_CONFIG="$TMP/config-slow" perl "$BASE/stats-collector.pl" >"$TMP/collector-slow.out" 2>&1 &
slow_pid=$!
i=0
while [ ! -e "$TMP/wg-slow.started" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done
test -e "$TMP/wg-slow.started"
kill -TERM "$slow_pid"
i=0
while kill -0 "$slow_pid" 2>/dev/null && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i+1)); done
if kill -0 "$slow_pid" 2>/dev/null; then
    kill -KILL "$slow_pid" 2>/dev/null || true
    wait "$slow_pid" 2>/dev/null || true
    echo "collector did not interrupt a blocked wg command" >&2
    exit 1
fi
wait "$slow_pid" 2>/dev/null || true
perl -MJSON::PP -0777 -e '$d=decode_json(<>); die "slow collector did not record stopped state" unless ($d->{state}||"") eq "stopped" && !$d->{running};' < "$TMP/stats-slow/health.json"
echo "collector blocked-command stop test passed"

# TERM during deliberately slowed startup compaction must leave the original
# history valid and stop promptly.
mkdir -p "$TMP/stats-compact-stop"
: > "$TMP/stats-compact-stop/wg0-peer-stop.jsonl"
i=1
while [ "$i" -le 500 ]; do
    printf '{"timestamp":%s,"rx":%s,"tx":%s}\n' "$now" "$i" "$i" >> "$TMP/stats-compact-stop/wg0-peer-stop.jsonl"
    i=$((i+1))
done
cat > "$TMP/config-compact-stop" <<EOF7
wg_cmd=$TMP/wg
stats_dir=$TMP/stats-compact-stop
stats_refresh_interval=60
stats_history_retention=300
stats_history_enabled=1
runtime_timeout=2
stats_max_points=100
stats_max_file_bytes=262144
stats_max_total_bytes=1048576
stats_health_interval=5
EOF7
WEBMIN_WIREGUARD_TEST_COMPACT_DELAY_USEC=10000 WEBMIN_WIREGUARD_CONFIG="$TMP/config-compact-stop" perl "$BASE/stats-collector.pl" >"$TMP/collector-compact.out" 2>&1 &
compact_pid=$!
i=0
while [ ! -s "$TMP/stats-compact-stop/health.json" ] && [ "$i" -lt 50 ]; do sleep 0.1; i=$((i+1)); done
test -s "$TMP/stats-compact-stop/health.json"
kill -TERM "$compact_pid"
i=0
while kill -0 "$compact_pid" 2>/dev/null && [ "$i" -lt 30 ]; do sleep 0.1; i=$((i+1)); done
if kill -0 "$compact_pid" 2>/dev/null; then
    kill -KILL "$compact_pid" 2>/dev/null || true
    wait "$compact_pid" 2>/dev/null || true
    echo "collector did not interrupt history compaction" >&2
    exit 1
fi
wait "$compact_pid" 2>/dev/null || true
perl -MJSON::PP -ne 'decode_json($_); END { print "" }' "$TMP/stats-compact-stop/wg0-peer-stop.jsonl"
perl -MJSON::PP -0777 -e '$d=decode_json(<>); die "compacting collector did not record stopped state" unless ($d->{state}||"") eq "stopped" && !$d->{running};' < "$TMP/stats-compact-stop/health.json"
echo "collector compaction stop test passed"
