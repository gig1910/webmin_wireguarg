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
# Reject release version literals only in module-version contract contexts.
# Other semver literals (package-manager fixtures, dependencies) are valid.
opendir(my $dh, 'tests') or die "tests: $!\n";
for my $entry (sort readdir($dh)) {
    next unless $entry =~ /\.(?:pl|py|js|sh)$/;
    my $path = "tests/$entry";
    my $source = slurp($path);
    while ($source =~ /(?:_wg_api=|X-WireGuard-Webmin-API:\s*|build_version=)\s*['"]?(\d+\.\d+\.\d+)/g) {
        die "$path pins module release version $1; derive it from VERSION instead\n";
    }
}
closedir($dh);
print "release version consistency tests passed\n";
