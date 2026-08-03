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
    ['lib/metrics-lib.pl', "API_BUILD='$version'"],
    ['diagnostic.cgi', "version => '$version'"],
);
for my $check (@checks) {
    my ($path, $needle) = @$check;
    die "$path does not contain release version marker $needle\n"
        if index(slurp($path), $needle) < 0;
}
print "release version consistency tests passed\n";
