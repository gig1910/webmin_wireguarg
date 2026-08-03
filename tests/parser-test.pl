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
my ($cfg, $err) = parse_wireguard_config("$FindBin::Bin/sample-wg0.conf");
die "parse failed: $err\n" if (!$cfg);
die "interface missing\n" if (!$cfg->{'interface'});
die "address mismatch\n" if ((get_section_value($cfg->{'interface'}, 'Address') || '') ne '10.66.66.1/24');
die "repeated PostUp lost\n" if (scalar(get_section_values($cfg->{'interface'}, 'PostUp')) != 2);
die "client endpoint metadata lost\n" if ((get_meta_value($cfg->{'interface'}, 'clientendpoint') || '') ne 'vpn.example.test:443');
die "peer count mismatch\n" if (@{$cfg->{'peers'}} != 2);
die "peer name mismatch\n" if (peer_display_name($cfg->{'peers'}->[0], 0) ne 'Laptop');
die "private key metadata mismatch\n" if (($cfg->{'peers'}->[0]->{'private_key'} || '') ne 'TEST_PRIVATE_LAPTOP');
die "disabled peer not detected\n" if (!$cfg->{'peers'}->[1]->{'disabled'});
die "disabled peer private key mismatch\n" if (($cfg->{'peers'}->[1]->{'private_key'} || '') ne 'TEST_PRIVATE_PHONE');
my $p = $cfg->{'peers'}->[0];
my ($client_address, $routes) = peer_client_address_and_routes($p);
die "client address was not split from AllowedIPs
" if ($client_address ne '10.66.66.2/32');
die "routed network split mismatch
" if (@$routes != 1 || $routes->[0] ne '192.168.0.0/24');
my %data = (
 name => 'Laptop Renamed', private_key => $p->{'private_key'},
 public_key => get_section_value($p, 'PublicKey'),
 clientaddress => $client_address, allowed_ips => [ join(', ', $client_address, @$routes) ],
 endpoint => '', keepalive => 25, clientendpoint => '', clientdns => '', clientallowedips => '', clientmtu => '', disabled => 1,
);
my $block = build_peer_block(\%data, $p);
die "disabled marker missing\n" if ($block !~ /Webmin-Disabled-Peer-Begin/);
die "preshared key not preserved\n" if ($block !~ /PresharedKey/);
die "combined AllowedIPs missing\n" if ($block !~ /AllowedIPs\s*=\s*10\.66\.66\.2\/32, 192\.168\.0\.0\/24/);
my $new = replace_section($cfg, $p, $block);
my $tmp = "$FindBin::Bin/result.conf";
open(my $fh, '>', $tmp) or die $!; print {$fh} $new; close($fh);
my ($cfg2, $err2) = parse_wireguard_config($tmp);
die "reparse failed: $err2\n" if (!$cfg2);
die "reparsed peer not disabled\n" if (!$cfg2->{'peers'}->[0]->{'disabled'});
die "reparsed peer name lost\n" if (peer_display_name($cfg2->{'peers'}->[0],0) ne 'Laptop Renamed');
die "reparsed private key lost\n" if (($cfg2->{'peers'}->[0]->{'private_key'}||'') ne 'TEST_PRIVATE_LAPTOP');
unlink($tmp);
print "parser and rewrite tests passed\n";
