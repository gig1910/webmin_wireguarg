#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;

# Keep the intentional execution order in run-tests.sh, but never silently
# omit newly introduced test entry points.
my $root="$FindBin::Bin";
open(my $fh,'<',"$root/run-tests.sh") or die "$root/run-tests.sh: $!\n";
local $/;
my $runner=<$fh>;
close($fh);

opendir(my $dh,$root) or die "$root: $!\n";
my @tests=sort grep { /-test\.(?:pl|py|sh)$/ && -f "$root/$_" } readdir($dh);
closedir($dh);
my %seen;
while ($runner =~ /(?:perl|python3|\.\/)\s+(?:\.\/)?tests\/([\w-]+-test\.(?:pl|py|sh))\b/g) {
    ++$seen{$1};
}
for my $test (@tests) {
    die "Test missing from tests/run-tests.sh: $test\n" unless $seen{$test};
    die "Test listed more than once in tests/run-tests.sh: $test\n"
        unless $seen{$test}==1;
}
for my $test (sort keys %seen) {
    die "Runner references deleted test: $test\n" unless -f "$root/$test";
}
# JS tests deliberately execute from a Perl harness so Node availability and
# browser mocking remain controlled by that harness.
my $js="$root/ui-behavior-test.js";
die "UI behavior JS fixture has no Perl harness\n"
    if -f $js && $runner !~ /perl tests\/ui-behavior-test\.pl/;
print "test runner inventory coverage passed (".scalar(@tests)." entry points)\n";
