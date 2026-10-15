#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT INT TERM
export WIREGUARD_DIAGNOSTIC_DIR="$TMP"
export PERL5LIB=tests/stub
TOKEN="$(perl -e 'require "./wireguard-lib.pl"; print csrf_token()')"

body_only() {
    sed 's/\r$//' | awk 'seen { print } /^$/ { seen=1 }'
}
json_field() {
    perl -MJSON::PP -0777 -e '$k=shift @ARGV; $x=decode_json(<STDIN>); $v=$x->{$k}; print defined($v)?$v:""' "$1"
}

start="$(REQUEST_METHOD=POST QUERY_STRING="name=wg0&peer=0&target=127.0.0.1&operation=ping&ping_count=2&_wg_csrf=$TOKEN" perl ./diagnostic.cgi)"
start_body="$(printf '%s\n' "$start" | body_only)"
job="$(printf '%s' "$start_body" | json_field job_id)"
[ -n "$job" ] || { echo "No diagnostic job ID" >&2; exit 1; }

offset=0
combined=''
state=''
i=0
while [ "$i" -lt 50 ]; do
    response="$(REQUEST_METHOD=GET QUERY_STRING="job=$job&offset=$offset" perl ./diagnostic_status.cgi)"
    response_body="$(printf '%s\n' "$response" | body_only)"
    state="$(printf '%s' "$response_body" | json_field state)"
    offset="$(printf '%s' "$response_body" | json_field offset)"
    chunk="$(printf '%s' "$response_body" | perl -MMIME::Base64 -MJSON::PP -0777 -e '$x=decode_json(<>); print decode_base64($x->{chunk_b64}||"")')"
    combined="$combined$chunk"
    [ "$state" = done ] && break
    i=$((i+1))
    sleep 0.1
done

[ "$state" = done ] || { echo "Diagnostic job did not finish" >&2; exit 1; }
printf '%s\n' "$combined" | grep -q 'bytes from'
printf '%s\n' "$combined" | grep -q '2 packets transmitted'
printf '%s\n' "$combined" | grep -q 'Command completed successfully.'
printf '%s\n' "$combined" | grep -q '^---$'

grep -q 'diagnostic_status.cgi' edit_peer.cgi
grep -q 'diagnostic_stop.cgi' edit_peer.cgi
if grep -q 'response.body.getReader' edit_peer.cgi; then
    echo "Old streaming fetch is still present" >&2
    exit 1
fi

# Start a continuous ping, request Stop through the CGI, and verify that both
# the job and its actual command process terminate. This catches UI-independent
# regressions where the stop marker is written but the server process survives.
start_inf="$(REQUEST_METHOD=POST QUERY_STRING="name=wg0&peer=0&target=127.0.0.1&operation=ping&infinite=1&_wg_csrf=$TOKEN" perl ./diagnostic.cgi)"
start_inf_body="$(printf '%s\n' "$start_inf" | body_only)"
job_inf="$(printf '%s' "$start_inf_body" | json_field job_id)"
[ -n "$job_inf" ] || { echo "No continuous diagnostic job ID" >&2; exit 1; }

child_pid=''
i=0
while [ "$i" -lt 50 ]; do
    if [ -r "$TMP/$job_inf/status.json" ]; then
        child_pid="$(perl -MJSON::PP -0777 -e '$x=decode_json(<>); print $x->{child_pid}||""' < "$TMP/$job_inf/status.json")"
        state_inf="$(perl -MJSON::PP -0777 -e '$x=decode_json(<>); print $x->{state}||""' < "$TMP/$job_inf/status.json")"
        [ "$state_inf" = running ] && [ -n "$child_pid" ] && break
    fi
    i=$((i+1))
    sleep 0.1
done
[ -n "$child_pid" ] || { echo "Continuous diagnostic child did not start" >&2; exit 1; }
kill -0 "$child_pid" 2>/dev/null || { echo "Continuous diagnostic child is not running" >&2; exit 1; }

stop_inf="$(REQUEST_METHOD=POST QUERY_STRING="job=$job_inf&_wg_csrf=$TOKEN" perl ./diagnostic_stop.cgi)"
stop_inf_body="$(printf '%s\n' "$stop_inf" | body_only)"
printf '%s' "$stop_inf_body" | perl -MJSON::PP -0777 -e '$x=decode_json(<>); die "stop failed\n" if !$x->{ok}; die "no stop signal\n" if !($x->{term_sent} || $x->{kill_sent})'

i=0
state_inf=''
while [ "$i" -lt 50 ]; do
    response_inf="$(REQUEST_METHOD=GET QUERY_STRING="job=$job_inf&offset=0" perl ./diagnostic_status.cgi)"
    response_inf_body="$(printf '%s\n' "$response_inf" | body_only)"
    state_inf="$(printf '%s' "$response_inf_body" | json_field state)"
    [ "$state_inf" = stopped ] && break
    i=$((i+1))
    sleep 0.1
done
[ "$state_inf" = stopped ] || { echo "Continuous diagnostic did not reach stopped state" >&2; exit 1; }
if kill -0 "$child_pid" 2>/dev/null; then
    echo "Continuous diagnostic child survived Stop" >&2
    exit 1
fi
grep -q 'Command stopped by user.' "$TMP/$job_inf/output.log"

echo "diagnostic asynchronous job, completion and forced-stop tests passed"
