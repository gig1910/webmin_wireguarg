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
print "dependency tests passed\n";
