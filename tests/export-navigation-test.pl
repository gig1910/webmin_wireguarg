#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;

sub slurp {
    open(my $fh, '<', $_[0]) or die "$!: $_[0]";
    local $/;
    my $data = <$fh>;
    close($fh);
    return $data;
}

my $client = slurp("$FindBin::Bin/../client_config.cgi");
my $qr = slurp("$FindBin::Bin/../peer_qr.cgi");
my $helper = slurp("$FindBin::Bin/../lib/api-ui-lib.pl");

for my $pair ([ client_config => $client ], [ peer_qr => $qr ]) {
    my ($name, $src) = @$pair;
    die "$name does not render as a Webmin page\n"
        if $src !~ /ui_print_header\(/ || $src !~ /ui_print_footer\(/;
}

die "QR image still uses a document-relative URL\n"
    if $qr !~ /module_script_url\('qr_image\.cgi'/;

die "view-page helper marker is missing\n"
    if $helper !~ /data-wg-module-navigation/;

die "raw download helper marker is missing\n"
    if $helper !~ /data-wg-direct-download/;

print "client export Webmin-shell navigation tests passed\n";
