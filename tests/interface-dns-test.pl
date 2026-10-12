#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
use File::Spec;
use lib "$FindBin::Bin/stub";
use lib "$FindBin::Bin/..";
our (%config, %text);
require "$FindBin::Bin/../wireguard-lib.pl";

$text{'error_dns_resolvconf_missing'} = 'resolvconf dependency unavailable';
my $tmp = tempdir(CLEANUP => 1);
local $ENV{'PATH'} = $tmp;
die "unexpected resolvconf found\n" if (wg_quick_resolvconf_command());
die "empty host DNS must not require resolvconf\n"
    if (wg_quick_dns_dependency_error([]));
die "missing resolvconf not detected\n"
    if (wg_quick_dns_dependency_error(['10.10.10.1']) ne $text{'error_dns_resolvconf_missing'});

my $helper = File::Spec->catfile($tmp, 'resolvconf');
open(my $bin, '>', $helper) or die $!;
print {$bin} "#!/bin/sh\nexit 0\n";
close($bin);
die "non-executable resolvconf accepted\n" if (wg_quick_resolvconf_command());
chmod(0700, $helper) or die $!;
die "executable resolvconf not found\n" if (wg_quick_resolvconf_command() ne $helper);
die "installed resolvconf incorrectly blocked DNS\n"
    if (wg_quick_dns_dependency_error(['10.10.10.1']));
unlink($helper) or die $!;

my %new = (
    addresses => ['10.10.10.1/24'], listen_port => '51820',
    private_key => 'TEST_KEY', public_key => 'TEST_PUBLIC',
    dns => [], clientdns => '10.10.10.1'
);
my $block = build_interface_block(\%new, undef);
die "host DNS incorrectly added\n" if ($block =~ /^DNS\s*=/m);
die "client DNS metadata missing\n" if ($block !~ /^#ClientDNS = 10\.10\.10\.1$/m);
$new{'dns'} = ['9.9.9.9'];
$block = build_interface_block(\%new, undef);
die "explicit host DNS missing\n" if ($block !~ /^DNS\s*=\s*9\.9\.9\.9$/m);

$config{'conf_dir'} = $tmp;
my $conf = File::Spec->catfile($tmp, 'wg_dns.conf');
open(my $out, '>', $conf) or die $!;
print {$out} "[Interface]\nAddress = 10.10.10.1/24\nPrivateKey = TEST_KEY\nDNS = 9.9.9.9\n";
close($out);
my ($up_ok, $up_error) = action_start_interface('wg_dns');
die "start was not blocked before invoking wg-quick\n"
    if ($up_ok || $up_error ne $text{'error_dns_resolvconf_missing'});

my $stop_calls = 0;
{
    no warnings 'redefine';
    local *main::action_stop_interface = sub { $stop_calls++; return (1, 'stopped'); };
    my ($restart_ok, $restart_error) = action_restart_interface('wg_dns');
    die "restart was not blocked before stopping a live interface\n"
        if ($restart_ok || $restart_error ne $text{'error_dns_resolvconf_missing'} || $stop_calls);
}
print "interface host DNS dependency and client DNS separation tests passed\n";
