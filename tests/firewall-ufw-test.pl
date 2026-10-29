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

# Missing UFW must not tear down wg-quick in either hook direction.
my ($missing_ok, $missing_message) = WebminWireGuardFirewall::manage(
    'up', 'wg_vpn', 38250,
    ufw => "$temp/no-ufw-binary", lock_path => "$temp/missing.lock"
);
die "Missing UFW blocked interface startup: $missing_message\n"
    unless ($missing_ok && $missing_message =~ /WARNING: UFW unavailable/);
($missing_ok, $missing_message) = WebminWireGuardFirewall::manage(
    'down', 'wg_vpn', undef,
    ufw => "$temp/no-ufw-binary", lock_path => "$temp/missing.lock"
);
die "Missing UFW blocked interface shutdown: $missing_message\n"
    unless ($missing_ok && $missing_message =~ /rule management skipped/);

my @inactive_calls;
my $inactive_runner = sub {
    my ($argv) = @_;
    push(@inactive_calls, [ @$argv ]);
    return (1, "Status: inactive\n");
};
my %inactive_opts = (
    runner => $inactive_runner, lock_path => "$temp/inactive.lock"
);
for my $action ('up', 'down') {
    my ($ok, $output) = WebminWireGuardFirewall::manage(
        $action, 'wg_vpn', $action eq 'up' ? 38250 : undef,
        %inactive_opts
    );
    die "Inactive UFW blocked $action: $output\n"
        unless ($ok && $output =~ /WARNING: UFW inactive/);
}
die "Inactive UFW changed firewall rules\n"
    if (grep { $_->[1] ne 'status' } @inactive_calls);

my $failed_runner = sub { return (0, 'UFW status command failed'); };
my ($failed_ok) = WebminWireGuardFirewall::manage(
    'up', 'wg_vpn', 38250,
    runner => $failed_runner, lock_path => "$temp/failed.lock"
);
die "Failed UFW status was silently bypassed\n" if ($failed_ok);
my $unknown_runner = sub { return (1, "Status: unexpected\n"); };
my ($unknown_ok) = WebminWireGuardFirewall::manage(
    'up', 'wg_vpn', 38250,
    runner => $unknown_runner, lock_path => "$temp/unknown.lock"
);
die "Unknown UFW status was silently bypassed\n" if ($unknown_ok);

{
    no warnings 'redefine';
    local *main::wg_firewall_ufw_state = sub { return 'missing'; };
    die "Missing UFW failed preflight\n" if (wg_firewall_preflight(38250));
    die "Missing UFW warning absent\n"
        unless (wg_firewall_status_warning() eq $text{'warning_firewall_ufw_missing'});
}
{
    no warnings 'redefine';
    local *main::wg_firewall_ufw_state = sub { return 'inactive'; };
    die "Inactive UFW failed preflight\n" if (wg_firewall_preflight(38250));
    die "Inactive UFW warning absent\n"
        unless (wg_firewall_status_warning() eq $text{'warning_firewall_ufw_inactive'});
}
{
    no warnings 'redefine';
    local *main::wg_firewall_ufw_state = sub { return 'unknown'; };
    die "Unknown UFW status passed preflight\n" if (!wg_firewall_preflight(38250));
}

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

# Runtime preflight must still reject an unknown/error state BEFORE stopping a tunnel.
my $config_path = "$temp/wg_safe.conf";
open(my $conf_fh, '>', $config_path) or die $!;
print {$conf_fh} "[Interface]\nAddress = 10.10.10.1/24\nPrivateKey = TEST_PRIVATE\nListenPort = 38250\n#WebminFirewall = ufw\n";
close($conf_fh);
$config{'conf_dir'} = $temp;
my $stop_calls = 0;
{
    no warnings 'redefine';
    local *main::wg_firewall_preflight = sub { return 'UFW inactive test'; };
    local *main::action_stop_interface = sub { $stop_calls++; return (1, 'stopped'); };
    my ($start_ok, $start_error) = action_start_interface('wg_safe');
    die "start did not block before wg-quick\n" if ($start_ok || $start_error ne 'UFW inactive test');
    my ($restart_ok, $restart_error) = action_restart_interface('wg_safe');
    die "restart did not preflight before shutdown\n"
        if ($restart_ok || $restart_error ne 'UFW inactive test' || $stop_calls);
}

print "tagged UFW rule lifecycle, ownership and generated hook tests passed\n";
