#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempfile);
use lib "$FindBin::Bin/stub";
require "$FindBin::Bin/../wireguard-lib.pl";

my $html = wg_ui_foundation();
my ($js) = $html =~ m{<script>\s*(.*?)\s*</script>}s;
die "Cannot extract rendered shared UI script\n" unless defined $js;
my $node = qx(command -v node 2>/dev/null);
chomp($node);
die "Node.js is required to check shared browser behaviors\n" unless $node;
my ($fh,$path) = tempfile(SUFFIX=>'.js',UNLINK=>1);
print {$fh} $js;
close($fh);
system($node, '--check', $path) == 0 or die "Invalid rendered UI JavaScript\n";
system($node, "$FindBin::Bin/ui-behavior-test.js", $path) == 0
    or die "Shared UI browser behavior regression failed\n";
