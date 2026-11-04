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

[Peer] #Default-route
PublicKey = DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD=
AllowedIPs = 0.0.0.0/0, ::/0

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
die "wrong first free address: ".($free // 'undef')."\n" if (($free || '') ne '10.66.66.4/32');
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

# Wide prefixes are routing entries, not allocations. Exact hosts still
# cannot be handed out twice, including addresses belonging to disabled peers.
my $host_dup = peer_exact_host_conflict($cfg, ['10.66.66.2/32'], undef);
die "exact IPv4 host conflict missed\n" if (!$host_dup || $host_dup->{'peer_index'} != 0);
my $host_dup6 = peer_exact_host_conflict($cfg, ['fd66::2/128'], undef);
die "disabled exact IPv6 host conflict missed\n" if (!$host_dup6 || !$host_dup6->{'disabled'});
die "broad IPv4 route treated as duplicate host\n"
    if (peer_exact_host_conflict($cfg, ['10.66.66.4/32'], undef));
die "broad IPv6 route treated as duplicate host\n"
    if (peer_exact_host_conflict($cfg, ['fd66::3/128'], undef));
die "skip index ignored for exact hosts\n"
    if (peer_exact_host_conflict($cfg, ['10.66.66.2/32'], 0));
my $broad_conflict = peer_allowed_ip_conflict($cfg, ['10.66.66.4/32'], undef);
die "broad route overlap warning missed\n" if (!$broad_conflict);

# Reverse the interface address order to test IPv6 allocation in the presence
# of a default IPv6 route and a disabled exact IPv6 host assignment.
# Parse a separate minimal config to avoid relying on parser internals.
my $v6_path = "$FindBin::Bin/ip-allocation-v6.conf";
open(my $v6_fh, '>', $v6_path) or die $!;
print {$v6_fh} <<'V6CONF';
[Interface]
Address = fd66::1/120
PrivateKey = TEST

[Peer]
PublicKey = AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=
AllowedIPs = ::/0

# Webmin-Disabled-Peer-Begin
#[Peer]
#PublicKey = BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=
#AllowedIPs = fd66::2/128
# Webmin-Disabled-Peer-End
V6CONF
close($v6_fh);
my ($parsed_v6, $v6_error) = parse_wireguard_config($v6_path);
die "v6 parse failed: $v6_error\n" if (!$parsed_v6);
my ($free_v6) = first_free_peer_address($parsed_v6);
die "IPv6 allocation incorrectly blocked: ".($free_v6 // 'undef')."\n"
    if (($free_v6 || '') ne 'fd66::3/128');
unlink($v6_path);

unlink($path);
print "IP allocation and overlap tests passed\n";
