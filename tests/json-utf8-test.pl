#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/stub";
use lib "$FindBin::Bin/..";
our (%config, %text);
require "$FindBin::Bin/../wireguard-lib.pl";

my $raw = "19s \xD0\xBD\xD0\xB0\xD0\xB7\xD0\xB0\xD0\xB4";
my $json = json_encode_utf8({ handshake_text => $raw, count => 19 });
die "UTF-8 was double-encoded: $json\n" if $json =~ /Ã|Ð/;
die "UTF-8 text missing: $json\n" if index($json, $raw) < 0;
die "numeric value became a string: $json\n" if $json !~ /"count":19/;
print "JSON UTF-8 tests passed\n";
