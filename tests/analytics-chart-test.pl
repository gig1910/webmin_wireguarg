#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempfile);
my $path="$FindBin::Bin/../analytics.cgi";
open(my $fh,'<',$path) or die $!;
local $/; my $source=<$fh>; close($fh);
die "HTML chart missing" unless $source =~ /data-chart-bars/ &&
    $source =~ /class="wg-analytics-chart"/;
die "per-bucket aggregation missing" unless $source =~ /totals\[slot\]\.rx\+=/ &&
    $source =~ /totals\[slot\]\.tx\+=/;
die "canvas still used" if $source =~ /getContext\('2d'\)/;
die "names not used" unless $source =~ /peerLabel\(p\)/;

# Important: check JavaScript as the browser RECEIVES it, after Perl heredoc
# interpolation. Source-only checks miss escapes such as \n turning into a
# literal JS line break inside quoted strings.
my ($template)=$source =~ /print <<HTML;\n(.*?)\nHTML\n/s;
die "cannot find analytics HTML heredoc" if !defined $template;
our %text;
while ($template =~ /\$text\{'([A-Za-z0-9_]+)'\}/g) {
    $text{$1}=$1;
}
my $url='/wireguard/analytics_data.cgi';
my $strings='{}';
my $selected_json='""';
my $generator=eval "sub { return <<HTML;\n$template\nHTML\n}";
die "cannot compile analytics HTML heredoc: $@" if $@ || !$generator;
my $html=$generator->();
my ($js)=$html =~ m{<script>\n(\(function\(\)\{.*?)</script>}s;
die "rendered analytics JavaScript missing" unless defined $js;
my $node=qx(command -v node 2>/dev/null); chomp $node;
if($node) {
    my ($tmp,$name)=tempfile(SUFFIX=>'.js',UNLINK=>1);
    print {$tmp} $js;close $tmp;
    system($node,'--check',$name)==0
        or die "rendered analytics JavaScript syntax invalid";
}
die "rendered chart does not reference labels" unless $html =~ /analytics_graph_rx/;
print "rendered analytics chart and peer label tests passed\n";
