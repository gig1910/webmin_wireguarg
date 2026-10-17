#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Find qw(find);

my $root = "$FindBin::Bin/..";
my @references;
find({
    no_chdir => 1,
    wanted => sub {
        my $path = $File::Find::name;
        if (-d $path) {
            my $relative=$path;
            $relative =~ s{^\Q$root\E/?}{};
            if ($relative =~ m{^(?:\.git|tests|docs|dist|build|\.idea)(?:/|$)}) {
                $File::Find::prune=1;
            }
            return;
        }
        return unless -f $path && $path =~ /\.(?:cgi|pl|py|js)$/;
        return if $path =~ m{/stats\.cgi$};
        open(my $fh, '<', $path) or die "$path: $!\n";
        while (my $line=<$fh>) {
            push @references, "$path:$.: $line" if $line =~ /\bstats\.cgi\b/;
        }
        close($fh);
    }
}, $root);

die "Legacy stats.cgi still has production callers:\n".join('',@references)
    if @references;
print "legacy stats.cgi has no internal code consumers\n";
