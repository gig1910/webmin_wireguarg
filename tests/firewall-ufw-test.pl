#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
use lib "$FindBin::Bin/stub";
use lib "$FindBin::Bin/..";
require "$FindBin::Bin/../lib/firewall-ufw-lib.pl";
our (%config, %text);
require "$FindBin::Bin/../wireguard-lib.pl";

my $temp = tempdir(CLEANUP => 1);
my @rules = ();
my @calls;
my $runner = sub {
    my ($argv) = @_;
    push(@calls, [ @$argv ]);
    if ($argv->[1] eq 'status') {
        return (1, "Status: active\n\nTo Action From\n-- ------ ----\n".
            join('', map {
                sprintf "[ %d] %d/udp ALLOW IN Anywhere # %s\n", $_->{'n'}, $_->{'port'}, $_->{'tag'}
            } @rules));
    }
    if ($argv->[1] eq 'allow') {
        my ($port) = $argv->[2] =~ /^(\d+)\/udp$/;
        push(@rules, { n => scalar(@rules)+1, port => int($port), tag => $argv->[4] });
        return (1, 'Rule added');
    }
    if ($argv->[1] eq '--force' && $argv->[2] eq 'delete') {
        my $num = $argv->[3];
        @rules = grep { $_->{'n'} != $num } @rules;
        my $i = 0; $_->{'n'} = ++$i for @rules;
        return (1, 'Rule deleted');
    }
    return (0, 'Unexpected command');
};
my %opts = (runner => $runner, lock_path => "$temp/fw.lock");
push(@rules, { n => 1, port => 38250, tag => 'manual SSH-safe rule' });
my ($ok, $msg) = WebminWireGuardFirewall::manage('up', 'wg_vpn', 38250, %opts);
die "up failed: $msg\n" if (!$ok);
die "expected own and manual rules\n" if (@rules != 2);
($ok, $msg) = WebminWireGuardFirewall::manage('up', 'wg_vpn', 38250, %opts);
die "repeat up failed or duplicated: $msg\n" if (!$ok || @rules != 2);
($ok, $msg) = WebminWireGuardFirewall::manage('up', 'wg_vpn', 38251, %opts);
die "port change failed: $msg\n" if (!$ok || @rules != 2 || $rules[1]->{'port'} != 38251);
($ok, $msg) = WebminWireGuardFirewall::manage('down', 'wg_vpn', undef, %opts);
die "down failed: $msg\n" if (!$ok || @rules != 1 || $rules[0]->{'tag'} ne 'manual SSH-safe rule');
die "invalid interface accepted\n" if ((WebminWireGuardFirewall::manage('up', 'wg;bad', 38250, %opts))[0]);
die "invalid port accepted\n" if ((WebminWireGuardFirewall::manage('up', 'wg_vpn', 0, %opts))[0]);

my %fields = (
    listen_port => '38250', firewall_managed => 1, firewall_ufw => 1,
    addresses => ['10.10.10.1/24'], preup => [], postup => ['echo custom'],
    predown => [], postdown => ['echo cleanup']
);
my $block = build_interface_block(\%fields, undef);
die "UFW PostUp missing\n" if ($block !~ /PostUp\s*=\s*.*wg-firewall-hook[.]pl.*up.*38250/m);
die "UFW PostDown missing\n" if ($block !~ /PostDown\s*=\s*.*wg-firewall-hook[.]pl.*down/m);
die "metadata missing\n" if ($block !~ /^#WebminFirewall = ufw$/m);
my $prev = { raw_lines => [ split(/(?<=\n)/, $block) ] };
$fields{'firewall_ufw'} = 0;
$block = build_interface_block(\%fields, $prev);
die "opt-out left an allow hook\n" if ($block =~ /PostUp\s*=\s*.*wg-firewall-hook[.]pl/m);
die "opt-out removed cleanup hook\n" if ($block !~ /PostDown\s*=\s*.*wg-firewall-hook[.]pl/m);
die "opt-out marker missing\n" if ($block !~ /^#WebminFirewall = off$/m);

print "tagged UFW rule lifecycle, ownership and generated hook tests passed\n";
