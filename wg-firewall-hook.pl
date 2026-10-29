#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
require "$FindBin::Bin/lib/firewall-ufw-lib.pl";

my ($action, $name, $port) = @ARGV;
my ($ok, $message) = WebminWireGuardFirewall::manage($action, $name, $port);
if (!$ok) {
    print STDERR "WireGuard/UFW: $message\n";
    exit 1;
}
if ($message =~ /^WARNING:/) {
    print STDERR "WireGuard/UFW: $message\n";
}
else {
    print "$message\n";
}
exit 0;
