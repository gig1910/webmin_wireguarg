#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/stub";
use lib "$FindBin::Bin/..";
our (%config, %text);
$config{'wg_cmd'} = '/usr/bin/wg';
require "$FindBin::Bin/../wireguard-lib.pl";

my $sample = join("\n",
    "wg0\tPRIVATE0\tPUBLIC0\t51820\toff",
    "wg0\tPEER1\tPSK1\t198.51.100.2:50000\t10.0.0.2/32\t1700000000\t1024\t2048\t25",
    "wg0\tPEER2\t(none)\t(none)\t10.0.0.3/32\t0\t4096\t8192\t0",
    "wg1\tPRIVATE1\tPUBLIC1\t443\t1234",
    "wg1\tPEER3\t(none)\t203.0.113.5:60000\t10.1.0.2/32\t1700000100\t10\t20\t60",
)."\n";

{
    no warnings qw(redefine once);
    local *main::has_command = sub { 1 };
    local *main::run_command = sub { return (1, $sample, 0, 'wg show all dump'); };
    my ($all, $error) = get_all_runtime_dump();
    die "runtime parser error: $error\n" if ($error);
    die "wg0 missing\n" if (!$all->{'wg0'});
    die "wg1 missing\n" if (!$all->{'wg1'});
    die "interface public key mismatch\n" if ($all->{'wg0'}->{'interface'}->{'public_key'} ne 'PUBLIC0');
    die "interface listen port mismatch\n" if ($all->{'wg1'}->{'interface'}->{'listen_port'} ne '443');
    die "peer count mismatch\n" if (@{$all->{'wg0'}->{'peer_list'}} != 2);
    die "rx aggregation mismatch\n" if ($all->{'wg0'}->{'rx_bytes'} != 5120);
    die "tx aggregation mismatch\n" if ($all->{'wg0'}->{'tx_bytes'} != 10240);
    die "peer endpoint mismatch\n" if ($all->{'wg0'}->{'peers'}->{'PEER1'}->{'endpoint'} ne '198.51.100.2:50000');
}


use File::Temp qw(tempdir);
use JSON::PP qw(encode_json);
my $cache_dir = tempdir(CLEANUP => 1);
$config{'stats_dir'} = $cache_dir;
open(my $cache, '>', "$cache_dir/runtime.json") or die $!;
print {$cache} encode_json({ timestamp => 1700000000, interfaces => { wg0 => { interface => { public_key => 'PUB', listen_port => '51820', fwmark => 'off' }, peer_list => [], peers => {}, rx_bytes => 0, tx_bytes => 0 } } });
close($cache);
my ($cached, $cache_error) = read_runtime_snapshot();
die "runtime cache read failed: $cache_error\n" if (!$cached);
die "runtime cache content mismatch\n" if ($cached->{'interfaces'}->{'wg0'}->{'interface'}->{'listen_port'} ne '51820');

unlink("$cache_dir/runtime.json") or die $!;
{
    no warnings 'redefine';
    local *main::get_all_runtime_dump = sub {
        return ({
            wg0 => {
                name => 'wg0',
                interface => { public_key => 'FALLBACK', listen_port => '443', fwmark => 'off' },
                peers => {}, peer_list => [], rx_bytes => 0, tx_bytes => 0,
            },
        }, undef);
    };
    my ($fallback, $fallback_error, $refreshed) = refresh_runtime_snapshot(15);
    die "fallback refresh failed: $fallback_error\n" if (!$fallback);
    die "fallback was not marked refreshed\n" if (!$refreshed);
    die "fallback cache was not written\n" if (!-s "$cache_dir/runtime.json");
    die "fallback cache content mismatch\n"
        if ($fallback->{'interfaces'}->{'wg0'}->{'interface'}->{'listen_port'} ne '443');
}

for my $file (qw(index.cgi edit_interface.cgi edit_peer.cgi runtime.cgi)) {
    open(my $fh, '<', "$FindBin::Bin/../$file") or die $!;
    local $/;
    my $source = <$fh>;
    close($fh);
    die "$file still performs synchronous active-interface lookup\n" if $source =~ /get_active_interfaces\s*\(/;
    die "$file still performs synchronous interface dump\n" if $source =~ /get_interface_dump\s*\(/;
}

print "runtime parser and asynchronous page tests passed\n";
