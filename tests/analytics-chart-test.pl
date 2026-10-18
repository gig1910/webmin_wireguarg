#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempfile);
my $path="$FindBin::Bin/../analytics.cgi";
open(my $fh,'<',$path) or die $!;
my $source;
{ local $/; $source = <$fh>; }
close($fh);
my $controller_path="$FindBin::Bin/../lib/analytics-page-ui-lib.pl";
open(my $controller_fh,'<',$controller_path) or die $!;
my $controller_source=do {local $/; <$controller_fh>};
close($controller_fh);
my $chart_path="$FindBin::Bin/../lib/chart-ui-lib.pl";
open(my $chart_fh,'<',$chart_path) or die $!;
my $chart_source=do {local $/; <$chart_fh>};
close($chart_fh);
die "analytics page does not load shared chart component"
    unless $source =~ /print wg_chart_ui_script\(\)/;
my $whole_page=$source."\n".$controller_source."\n".$chart_source;
die "SVG chart missing" unless $whole_page =~ /data-chart-svg/ &&
    $whole_page =~ /class="wg-analytics-chart"/;
die "historical graph must use SQLite display intervals" unless $whole_page =~ /data\.bucket_seconds/;
die "SVG line/area TX-above/RX-below rendering missing"
    unless $whole_page =~ /series\('tx',-1\);series\('rx',1\)/ &&
           $whole_page =~ /fill-opacity/ && $whole_page =~ /stroke-width/ &&
           $whole_page =~ /createElementNS\(svgNs/;
die "theme colors lost" unless $whole_page =~ /--primary-color/ &&
    $whole_page =~ /--success-color/;
die "canvas still used" if $whole_page =~ /getContext\('2d'\)/;
die "names not used" unless $whole_page =~ /peerLabel\(p\)/;

# Important: check JavaScript as the browser RECEIVES it, after Perl heredoc
# interpolation. Source-only checks miss escapes such as \n turning into a
# literal JS line break inside quoted strings.
my ($template)=$source =~ /print <<HTML;\n(.*?)\nHTML\n/s;
die "cannot find analytics HTML heredoc" if !defined $template;
our %text;
while ($template =~ /\$text\{'([A-Za-z0-9_]+)'\}/g) {
    $text{$1}=$1;
}
my $apply_button='<button type="button" data-apply="1">Apply</button>';
my $url='/wireguard/analytics_data.cgi';
my $strings='{}';
my $selected_json='""';
my $initial_interface_json='""';
my $generator=eval "sub { return <<HTML;\n$template\nHTML\n}";
die "cannot compile analytics HTML heredoc: $@" if $@ || !$generator;
my $html=$generator->();
require "$FindBin::Bin/../lib/chart-ui-lib.pl";
require "$FindBin::Bin/../lib/analytics-page-ui-lib.pl";
my $script_html=wg_analytics_controller_script($strings,$selected_json,$initial_interface_json);
my ($js)=$script_html =~ m{<script>\n(\(function\(\)\{.*?)</script>}s;
die "rendered analytics JavaScript missing" unless defined $js;
my $node=qx(command -v node 2>/dev/null);
$node =~ s/[\r\n]+\z//; # independent of Perl's record separator ($/)
die "Node.js path is not executable: $node\n" if $node && !-x $node;
if($node) {
    my ($tmp,$name)=tempfile(SUFFIX=>'.js',UNLINK=>1);
    print {$tmp} $js;close $tmp;
    system($node,'--check',$name)==0
        or die "rendered analytics JavaScript syntax invalid";
}
die "rendered chart does not reference labels" unless $html =~ /analytics_graph_rx/;
die "responsive CSS media query lost during template interpolation"
    unless $html =~ /\@media\(max-width:700px\)/;
die "peer edit navigation path validation missing"
    unless $js =~ /pathname\.endsWith\('\/wireguard\/edit_peer\.cgi'\)/;
die "peer link URL must be same-origin"
    unless $js =~ /url\.origin===window\.location\.origin/;

print "rendered analytics chart and peer label tests passed\n";
