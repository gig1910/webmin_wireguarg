#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;

sub slurp {
    my ($path) = @_;
    open(my $fh, '<', $path) or die "$path: $!\n";
    local $/;
    my $data = <$fh>;
    close($fh);
    return $data;
}

my $toggle = slurp("$FindBin::Bin/../toggle_peer.cgi");
die "peer toggle does not refresh the shared runtime snapshot\n"
    if $toggle !~ /refresh_runtime_snapshot\(0\)/;
die "peer toggle refresh happens after runtime apply\n"
    if index($toggle, 'refresh_runtime_snapshot(0)') < index($toggle, 'action_apply_interface');
die "peer toggle JSON does not report runtime refresh state\n"
    if $toggle !~ /runtime_refreshed/;

my $save = slurp("$FindBin::Bin/../save_peer.cgi");
die "peer create does not refresh runtime snapshot\n"
    if $save !~ /refresh_runtime_snapshot\(0\)/;
die "new peer does not return directly to the interface table\n"
    if $save !~ /\$is_new\s*&&\s*\$apply_ok[\s\S]+redirect\('edit_interface\.cgi\?name='/;
die "peer create redirects before refreshing runtime\n"
    if index($save, 'redirect(') < index($save, 'refresh_runtime_snapshot(0)');

my $delete = slurp("$FindBin::Bin/../delete_peer.cgi");
die "peer delete does not refresh runtime snapshot\n"
    if $delete !~ /refresh_runtime_snapshot\(0\)/;
die "peer delete does not return directly to the interface table\n"
    if $delete !~ /redirect\('edit_interface\.cgi\?name='/;
die "peer delete redirects before refreshing runtime\n"
    if index($delete, 'redirect(') < index($delete, 'refresh_runtime_snapshot(0)');

my $runtime = slurp("$FindBin::Bin/../runtime.cgi");
die "runtime endpoint lacks an explicit force-refresh mode\n"
    if $runtime !~ /force_refresh/ || $runtime !~ /refresh_runtime_snapshot\(\$force_refresh \? 0/;
die "forced runtime requests are not rate limited\n"
    if $runtime !~ /request_rate_limit\('runtime_refresh'/;

my $metrics = slurp("$FindBin::Bin/../lib/metrics-lib.pl");
die "runtime poller exposes no refresh method\n"
    if $metrics !~ /state\.refresh=function/;
die "runtime poller does not support refresh=1\n"
    if $metrics !~ /refresh=1&_wg_now=/;

print "peer CRUD runtime refresh tests passed\n";
