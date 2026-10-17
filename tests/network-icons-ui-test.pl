#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempfile);
sub read_file {
    open(my $f,'<',$_[0]) or die "Cannot read $_[0]: $!";
    local $/;return <$f>;
}
my $peer=read_file("$FindBin::Bin/../edit_peer.cgi");
my $iface=read_file("$FindBin::Bin/../edit_interface.cgi");
my $backend=read_file("$FindBin::Bin/../analytics-store.py");
my $api=read_file("$FindBin::Bin/../peer_ip_info.cgi");
my $icons=read_file("$FindBin::Bin/../network_icons.cgi");
my $read=read_file("$FindBin::Bin/../network_icon_data.cgi");
my $manifest=read_file("$FindBin::Bin/../MANIFEST.wbm");
my $sort=read_file("$FindBin::Bin/../lib/table-sort-ui-lib.pl");
for my $file (qw(network_icons.cgi network_icon_data.cgi)) {
    die "$file omitted from module release\n" unless $manifest=~/^\Q$file\E$/m;
}
die "on-demand lookup must cache confirmed WHOIS facts only\n"
    unless $api =~ /analytics_backend\('peer_ip'/ &&
           $api =~ /analytics_backend\('network_record'/ &&
           index($api,"analytics_backend('peer_ip'") <
              index($api,"analytics_backend('network_record'");
my ($ingest_body) = $backend =~ /(^def ingest\(.*?)(?=^def |\z)/ms;
die "ingest function not found\n" if !defined $ingest_body;
die "network cache wrongly tied to peer samples\n"
    if $ingest_body =~ /network_record\(/;
die "network cache and manual assignments not independent\n"
    unless $backend=~/CREATE TABLE IF NOT EXISTS network_cache/ &&
           $backend=~/CREATE TABLE IF NOT EXISTS network_icons/ &&
           $backend=~/DELETE FROM network_cache/ &&
           $backend=~/INSERT INTO network_icons/;
die "server API must validate IP literals, never resolve hostnames\n"
    unless $read =~ /assert_view_access\(\)/ &&
           $read =~ /Too many IPs/ && $read =~ /analytics_backend\('network_lookup'/;
die "management operation must have manage ACL, CSRF and rate-limit\n"
    unless $icons =~ /assert_manage_access\(\)/ &&
           $icons =~ /assert_post_and_csrf\(\)/ &&
           $icons =~ /request_rate_limit\('network_icons'/;
die "explicit CLEAR confirmation missing\n"
    unless $backend=~/get\("confirm"\) != "CLEAR"/;
die "network icon display missing from current endpoint cell\n"
    unless $iface=~/data-wg-net-icon/ &&
           $iface=~/data-wg-endpoint/ &&
           $iface=~/wg-network-icon/ &&
           $iface=~/updateNetworkIcons\(\)/ &&
           $iface=~/network_icon_data\.cgi/;
die "initial badge not question mark in white circle\n"
    unless $iface=~m{wg-network-icon[^'"]*'} || $iface=~/border:1\.6px solid white/;
die "network icon script queries external WHOIS automatically\n"
    if $iface =~ /fetch\([^)]*peer_ip_info/;
die "icons poller not cleaned up on page destroy\n"
    unless $iface=~/if\(networkRequest\)networkRequest\.abort\(\)/;
die "sorter must ignore the icon glyph\n"
    unless $sort=~/cell\.querySelector\('\[data-wg-endpoint\]'\)/;
die "peer tabs not restricted to existing peers\n"
    unless $peer =~ /if \(\$peer\) \{\s+print '<div id=.*wg-peer-detail-tabs/s;
for my $pane (qw(settings usage activity)) {
    die "missing peer $pane tab\n"
        unless $peer =~ /data-wg-peer-tab="\Q$pane\E"/ &&
               $peer =~ /data-wg-peer-pane="\Q$pane\E"/;
}
die "peer consumption chart unexpectedly dropped\n" unless
    $peer =~ /graph_html\(\$name, \$public_key/;
die "peer activity table not scoped by peer fingerprint\n"
    unless $peer =~ /sha256_hex\(\$public_key\)/ &&
           $peer =~ /requestUrl\.searchParams\.set\('peer_id',peerId\)/ &&
           $peer =~ /data-wg-peer-activity-rows/;
die "peer activities not sortable\n"
    unless $peer=~/WireGuardTableSort\.attach/ &&
           $peer=~/if\(sort\)sort\.apply\(\)/;
die "peer tab switch does not set hidden pane state\n"
    unless $peer=~/p\.hidden=p\.dataset\.wgPeerPane!==tab/;
my ($template)=$peer=~/print <<PEER_TABS_SCRIPT;\n(.*?)\nPEER_TABS_SCRIPT\n/s;
die "peer tab JS heredoc missing\n" unless defined $template;
our ($js_tabs_id,$js_analytics_url,$js_peer_id,$js_activity_labels);
$js_tabs_id='"peer-tabs-fixture"';
$js_analytics_url='"/wireguard/analytics_data.cgi"';
$js_peer_id='"'.('a'x64).'"';
$js_activity_labels='{"loading":"Loading","empty":"Empty","events":{}}';
my $generator=eval "sub {return <<PEER_TABS_SCRIPT;\n$template\nPEER_TABS_SCRIPT\n}";
die "peer tab JS template cannot compile: $@" if !$generator || $@;
my $html=$generator->();
my ($js)=$html=~m{<script>\n(.*?)</script>}s;
die "peer tab JS missing\n" if !defined $js;
my $node=qx(command -v node 2>/dev/null);
$node =~ s/[\r\n]+\z//;
if($node){
    my ($fh,$path)=tempfile(SUFFIX=>'.js',UNLINK=>1);
    print {$fh} $js;close($fh);
    system($node,'--check',$path)==0 or die "generated peer tabs JS invalid\n";
}
print "network badge/cache and peer three-tab UI tests passed\n";
