#!/usr/bin/perl
use strict;
use warnings;
use File::Temp qw(tempdir);
use File::Spec;
use FindBin;
chdir "$FindBin::Bin/.." or die $!;
require './wireguard-lib.pl';
our %config;

my $spec = optional_dependency_spec('qrencode');
die "missing qrencode spec\n" if (!$spec || $spec->{'package'} ne 'qrencode');
die "arbitrary dependency accepted\n" if (optional_dependency_spec('curl'));

my $tmp = tempdir(CLEANUP => 1);
my $dpkg = File::Spec->catfile($tmp, 'dpkg-query');
open(my $dfh, '>', $dpkg) or die $!;
print {$dfh} "#!/bin/sh\nprintf 'install ok installed\\t4.1.1-1\\n'\n";
close($dfh);
chmod 0755, $dpkg;

my $apt = File::Spec->catfile($tmp, 'apt-get');
open(my $afh, '>', $apt) or die $!;
print {$afh} "#!/bin/sh\nexit 0\n";
close($afh);
chmod 0755, $apt;

my $missing = File::Spec->catfile($tmp, 'qrencode-missing');
$config{'dpkg_query_cmd'} = $dpkg;
$config{'apt_get_cmd'} = $apt;
$config{'qrencode_cmd'} = $missing;

my $status = optional_dependency_status('qrencode');
die "package not detected\n" if (!$status->{'package_installed'});
die "wrong version\n" if ($status->{'package_version'} ne '4.1.1-1');
die "missing command reported available\n" if ($status->{'command_available'});

my $qr = File::Spec->catfile($tmp, 'qrencode');
open(my $qfh, '>', $qr) or die $!;
print {$qfh} "#!/bin/sh\nexit 0\n";
close($qfh);
chmod 0755, $qr;
$config{'qrencode_cmd'} = $qr;
$status = optional_dependency_status('qrencode');
die "command not detected\n" if (!$status->{'command_available'});

die "unknown dependency returned status\n" if (defined optional_dependency_status('not-allowed'));

my $geo=optional_dependency_spec('geoip');
die "GeoIP bundle absent\n" if !$geo || @{$geo->{'packages'}} != 5;
die "GeoIP bundle must include offline country DB, updater and WHOIS\n"
    unless join(' ',@{$geo->{'packages'}}) eq
           'geoipupdate mmdb-bin geoip-bin geoip-database whois';
for my $pair (@{$geo->{'commands'}}) {
    my ($key,$fallback)=@$pair;
    my $exe=File::Spec->catfile($tmp,$key);
    $config{$key}=$exe;
}
my $quick=optional_dependency_quick_status('geoip');
die "missing GeoIP binaries incorrectly treated as installed\n"
    if $quick->{'command_available'} || @{$quick->{'missing_commands'}}!=4;
my $geo_status=optional_dependency_status('geoip');
die "GeoIP package version inventory failed\n"
    unless $geo_status->{'package_installed'} &&
           $geo_status->{'package_version'} =~ /geoip-database/;
for my $pair (@{$geo->{'commands'}}) {
    my $exe=$config{$pair->[0]};
    open(my $f,'>',$exe) or die $!;
    print {$f} "#!/bin/sh\nexit 0\n";
    close($f);
    chmod 0755,$exe;
}
$quick=optional_dependency_quick_status('geoip');
die "installed GeoIP executable bundle not detected\n"
    unless $quick->{'command_available'} && !@{$quick->{'missing_commands'}};
$geo_status=optional_dependency_status('geoip');
die "installed GeoIP bundle still reported unavailable\n"
    unless $geo_status->{'command_available'} && $geo_status->{'package_installed'};
die "unexpected package in dependency whitelist\n"
    if optional_dependency_spec('apt') || optional_dependency_spec('../../etc/passwd');

my $installer=do {
    open(my $fd,'<','install_dependency.cgi') or die $!;
    local $/; <$fd>;
};
my $worker=do {
    open(my $fd,'<','dependency-worker.pl') or die $!;
    local $/; <$fd>;
};
die "installer must enforce POST, CSRF, dependency ACL and rate limit\n"
    unless $installer =~ /assert_post_and_csrf\(\)/ &&
           $installer =~ /assert_install_dependencies_access\(\)/ &&
           $installer =~ /request_rate_limit\('install_dependency'/;
die "background worker must whitelist packages independently of CGI\n"
    unless $worker =~ /my %allowed=/ &&
           $worker =~ /geoipupdate mmdb-bin geoip-bin geoip-database whois/ &&
           $worker =~ /\@\{\$allowed\{\$dependency\}\}/ &&
           $worker =~ /flock\(\$lock/ &&
           $worker =~ /NEEDRESTART_MODE/;
my $peer=do {
    open(my $fd,'<','edit_peer.cgi') or die $!;
    local $/; <$fd>;
};
die "GeoIP installer link or ACL gate missing on peer details\n"
    unless $peer =~ /optional_dependency_quick_status\('geoip'\)/ &&
           $peer =~ /\$access\{'install_dependencies'\}/ &&
           $peer =~ /direct_link_button\(/ &&
           $peer =~ /dependency => 'geoip'/ &&
           $peer =~ /dependency => 'qrencode'/;
print "dependency tests passed\n";
