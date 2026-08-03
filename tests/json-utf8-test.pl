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

my $boolean_json = json_encode_utf8({
    ok => JSON::PP::true(),
    disabled => JSON::PP::false(),
    nested => { active => JSON::PP::true(), stale => JSON::PP::false() },
});
die "JSON true became a string: $boolean_json\n" if $boolean_json =~ /"(?:ok|active)":"/;
die "JSON false became a string: $boolean_json\n" if $boolean_json =~ /"(?:disabled|stale)":"/;
die "JSON boolean class name leaked into output: $boolean_json\n" if $boolean_json =~ /JSON::PP::/;
my $boolean_data = JSON::PP::decode_json($boolean_json);
die "decoded true is false\n" if !$boolean_data->{ok} || !$boolean_data->{nested}->{active};
die "decoded false is true\n" if $boolean_data->{disabled} || $boolean_data->{nested}->{stale};

print "JSON UTF-8 and boolean tests passed\n";
