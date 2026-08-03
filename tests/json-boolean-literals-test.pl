#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Find;

my $root = "$FindBin::Bin/..";
my @bad;
find(
    {
        no_chdir => 1,
        wanted => sub {
            return if !-f $_;
            return if $File::Find::name =~ m{/(?:build|dist|\.git)/};
            return if $File::Find::name !~ /\.(?:pl|cgi|pm)$/;
            open(my $fh, '<', $File::Find::name) or die "$File::Find::name: $!\n";
            my $line_no = 0;
            while (my $line = <$fh>) {
                $line_no++;
                next if $line =~ /^\s*#/;
                if ($line =~ /JSON::PP::(?:true|false)(?!\s*\()/) {
                    push @bad, "$File::Find::name:$line_no:$line";
                }
            }
            close($fh);
        },
    },
    $root,
);

die "JSON::PP boolean constants must be called with parentheses:\n@bad" if @bad;
print "JSON boolean literal checks passed\n";
