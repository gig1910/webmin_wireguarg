#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempfile);
my $path="$FindBin::Bin/../analytics.cgi";
open(my $fh,'<',$path) or die $!;
local $/;my $source=<$fh>;close($fh);
die "HTML chart missing" unless $source =~ /data-chart-bars/ &&
    $source =~ /class="wg-analytics-chart"/;
die "per-bucket aggregation missing" unless $source =~ /totals\[slot\]\.rx\+=/ &&
    $source =~ /totals\[slot\]\.tx\+=/;
die "canvas still used" if $source =~ /getContext\('2d'\)/;
die "names not used" unless $source =~ /peerLabel\(p\)/;
my ($js)=$source=~m{<script>\n\(function\(\)\{(.*?)</script>}s;
die "JavaScript not found" unless defined $js;
$js="(function(){".$js;
$js=~s/const labels=\$strings, initial=\$selected_json;/const labels={}, initial='';/;
die "template placeholders remain" if $js =~ /\$(?:strings|selected_json)\b/;
my $node=qx(command -v node 2>/dev/null);chomp $node;
if($node){
    my ($tmp,$name)=tempfile(SUFFIX=>'.js',UNLINK=>1);
    print {$tmp} $js;close $tmp;
    system($node,'--check',$name)==0 or die "chart JavaScript syntax invalid";
}
print "analytics chart and names tests passed\n";
