#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/stub";
use lib "$FindBin::Bin/..";
our (%config, %text);
$config{'conf_dir'} = $FindBin::Bin;
$config{'backup_dir'} = "$FindBin::Bin/backups";
require "$FindBin::Bin/../wireguard-lib.pl";

my $path = "$FindBin::Bin/ip-allocation.conf";
open(my $fh, '>', $path) or die $!;
print {$fh} <<'CONF';
[Interface]
Address = 10.66.66.1/24, fd66::1/64
PrivateKey = TEST

[Peer] #Peer-2
PublicKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
AllowedIPs = 10.66.66.2/32, 192.168.10.0/24

[Peer] #Peer-3-and-range
PublicKey = BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=
AllowedIPs = 10.66.66.3/32, 10.66.66.4/30

# Webmin-Disabled-Peer-Begin
#[Peer] #Disabled-v6
#PublicKey = CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=
#AllowedIPs = fd66::2/128
# Webmin-Disabled-Peer-End
CONF
close($fh);

my ($cfg, $err) = parse_wireguard_config($path);
die "parse failed: $err\n" if (!$cfg);

my ($free, $network) = first_free_peer_address($cfg);
die "wrong first free address: ".($free // 'undef')."\n" if (($free || '') ne '10.66.66.8/32');
die "wrong source network: ".($network // 'undef')."\n" if (($network || '') ne '10.66.66.1/24');

die "IPv4 overlap missed\n" if (!cidrs_overlap('10.66.66.6/32', '10.66.66.4/30'));
die "IPv4 false overlap\n" if (cidrs_overlap('10.66.66.8/32', '10.66.66.4/30'));
die "IPv6 overlap missed\n" if (!cidrs_overlap('fd66::2/128', 'fd66::/64'));
die "cross-family false overlap\n" if (cidrs_overlap('10.66.66.2/32', 'fd66::2/128'));

my $conflict = peer_allowed_ip_conflict($cfg, [ '10.66.66.6/32' ], undef);
die "peer conflict missed\n" if (!$conflict);
die "wrong conflicting peer\n" if (($conflict->{'peer_name'} || '') ne 'Peer-3-and-range');
die "wrong existing range\n" if (($conflict->{'existing'} || '') ne '10.66.66.4/30');

my $disabled_conflict = peer_allowed_ip_conflict($cfg, [ 'fd66::2/128' ], undef);
die "disabled peer conflict missed\n" if (!$disabled_conflict || !$disabled_conflict->{'disabled'});

my $skip_conflict = peer_allowed_ip_conflict($cfg, [ '10.66.66.2/32' ], 0);
die "editing peer conflicts with itself\n" if ($skip_conflict);

my $route_conflict = peer_allowed_ip_conflict($cfg, [ '192.168.10.128/25' ], undef);
die "routed subnet overlap missed\n" if (!$route_conflict);

my $clean = peer_allowed_ip_conflict($cfg, [ '172.16.0.0/16' ], undef);
die "false peer conflict\n" if ($clean);

unlink($path);
print "IP allocation and overlap tests passed\n";
