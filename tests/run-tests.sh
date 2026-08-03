#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
export PERL5LIB="tests/stub"
for file in wireguard-lib.pl ./*.cgi acl_security.pl install_check.pl stats-collector.pl diagnostic-worker.pl postinstall.pl postuninstall.pl uninstall.pl; do
    perl -c "$file"
done
perl tests/parser-test.pl
perl tests/parser-fuzz-test.pl
perl tests/ip-allocation-test.pl
perl tests/key-client-test.pl
perl tests/atomic-test.pl
perl tests/saveconfig-stop-test.pl
perl tests/ui-helper-test.pl
perl tests/export-navigation-test.pl
perl tests/json-utf8-test.pl
perl tests/dependency-test.pl
perl tests/runtime-async-test.pl
perl tests/install-check-test.pl
perl tests/version-consistency-test.pl
perl tests/postinstall-fresh-test.pl
perl tests/uninstall-preservation-test.pl
perl tests/async-js-test.pl
perl tests/api-json-test.pl
perl tests/miniserv-json-test.pl
perl tests/peer-list-actions-test.pl
perl tests/interface-controller-root-test.pl
perl tests/peer-runtime-refresh-test.pl
perl tests/diagnostic-js-test.pl
perl tests/security-regression-test.pl
perl tests/service-hardening-test.pl
perl tests/collector-config-test.pl
perl tests/ui-ux-test.pl
./tests/diagnostic-test.sh
./tests/collector-test.sh

echo "all tests passed"
