#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use Time::HiRes qw(time);
require "$FindBin::Bin/../lib/subprocess-lib.pl";

my $program = q{
    use strict;
    use warnings;
    binmode(STDIN);
    binmode(STDOUT);
    binmode(STDERR);
    my $payload = '';
    while (sysread(STDIN, my $chunk, 8192)) { $payload .= $chunk; }
    print STDERR 'E' x 200_000;
    print STDOUT 'O' x 200_000;
    print STDOUT scalar(length($payload));
};
my ($ok, $out, $err, $status) = wg_capture_subprocess(
    [$^X, '-e', $program], 'a' x 200_000,
    timeout => 8, max_stderr => 300_000
);
die "Concurrent input/stdout/stderr handling failed: $err\n"
    unless $ok && $status == 0 &&
           length($out) == 200_006 && length($err) == 200_000 &&
           substr($out, -6) eq '200000';

my $started = time();
($ok, $out, $err) = wg_capture_subprocess(
    [$^X, '-e', 'sleep 5'], '', timeout => 1
);
die "Timeout enforcement failed\n"
    unless !$ok && $err =~ /timeout/ && time() - $started < 3;

($ok, $out, $err) = wg_capture_subprocess(
    [$^X, '-e', q{print 'X' x 100_000}], '',
    timeout => 3, max_stdout => 1024
);
die "Output size limit failed\n" unless !$ok && $err =~ /limit/;

($ok, $out, $err, $status) = wg_capture_subprocess(
    [$^X, '-e', 'exit 17'], '', timeout => 3
);
die "Nonzero exit code lost\n" unless !$ok && ($status >> 8) == 17;

($ok, $out, $err) = wg_capture_subprocess(
    [$^X, '-e', 'exit 0'], 'a' x 200_000,
    timeout => 3
);
die "Premature stdin close broke parent\n" unless $ok;

print "bounded subprocess regression tests passed\n";
