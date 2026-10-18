#!/usr/bin/perl
use strict;
use warnings;

sub slurp {
    my ($path) = @_;
    open(my $fh, '<', $path) or die "$path: $!\n";
    local $/; my $data = <$fh>; close($fh); return $data;
}
my $version = slurp('VERSION');
$version =~ s/\s+//g;
die "invalid VERSION\n" if $version !~ /^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$/;
my $info = slurp('module.info');
die "module.info version mismatch\n" if $info !~ /^version=\Q$version\E$/m;
my @checks = (
    ['lib/api-ui-lib.pl', "X-WireGuard-Webmin-API: $version"],
    ['lib/api-ui-lib.pl', "_wg_api'} = '$version"],
    ['lib/version-lib.pl', "WIREGUARD_WEBMIN_VERSION = '$version'"],
);
for my $check (@checks) {
    my ($path, $needle) = @$check;
    die "$path does not contain release version marker $needle\n"
        if index(slurp($path), $needle) < 0;
}
# Test assertions should follow the project version; fixed IP addresses and
# timestamps are fixtures, not version pins. Reject standalone semver literals
# in test source so the next minor bump cannot silently break assertions.
opendir(my $dh, 'tests') or die "tests: $!\n";
for my $entry (sort readdir($dh)) {
    next unless $entry =~ /\.(?:pl|py|js|sh)$/;
    my $path = "tests/$entry";
    my $source = slurp($path);
    while ($source =~ /(?<![\d.])(\d+\.\d+\.\d+)(?![\d.])/g) {
        my $literal = $1;
        die "$path pins release-looking version $literal; derive it from VERSION instead\n";
    }
}
closedir($dh);
print "release version consistency tests passed\n";
