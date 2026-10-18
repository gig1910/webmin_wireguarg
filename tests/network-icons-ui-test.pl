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
my $peer_ui=read_file("$FindBin::Bin/../lib/peer-activity-ui-lib.pl");
die "peer activity script helper not wired" unless $peer =~ m{require './lib/peer-activity-ui-lib.pl'} &&
    $peer =~ /wg_peer_activity_tabs_script\(/;
$peer .= "\n".$peer_ui;

my $iface=read_file("$FindBin::Bin/../edit_interface.cgi");
die "interface CGI must delegate to isolated page controller\n"
    unless $iface =~ m{require './lib/interface-page-ui-lib.pl'} &&
           $iface =~ /wg_interface_page_script\(/;
$iface .= "\n".read_file("$FindBin::Bin/../lib/interface-page-ui-lib.pl");
my $backend=read_file("$FindBin::Bin/../analytics-store.py");
my $network=read_file("$FindBin::Bin/../network_store.py");
my $api=read_file("$FindBin::Bin/../peer_ip_info.cgi");
my $icons=read_file("$FindBin::Bin/../network_icons.cgi");
my $network_ui=read_file("$FindBin::Bin/../lib/network-icons-ui-lib.pl");
die "network directory UI helper not used by CGI\n"
    unless $icons =~ m{require './lib/network-icons-ui-lib.pl'} &&
           $icons =~ /wg_network_icons_page_script\(json_encode_utf8/;
die "network directory UI missing from WBM\n"
    unless read_file("$FindBin::Bin/../MANIFEST.wbm") =~ /^lib\/network-icons-ui-lib\.pl$/m;
die "network directory editor or flag display lost\n"
    unless $network_ui =~ /data-wg-edit-range/ &&
           $network_ui =~ /data-wg-geoip-codes/ &&
           $network_ui =~ /data-wg-country/;
my $read=read_file("$FindBin::Bin/../network_icon_data.cgi");
my $manifest=read_file("$FindBin::Bin/../MANIFEST.wbm");
die "peer activity UI missing from WBM manifest\n"
    unless $manifest =~ /^lib\/peer-activity-ui-lib\.pl$/m;
my $sort=read_file("$FindBin::Bin/../lib/table-sort-ui-lib.pl");
for my $file (qw(network_icons.cgi network_icon_data.cgi network_store.py)) {
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
    unless $network=~/CREATE TABLE IF NOT EXISTS network_cache/ &&
           $network=~/CREATE TABLE IF NOT EXISTS network_icons/ &&
           $network=~/DELETE FROM network_cache/ &&
           $network=~/INSERT INTO network_icons/;
die "server API must validate IP literals, never resolve hostnames\n"
    unless $read =~ /assert_view_access\(\)/ &&
           $read =~ /Too many IPs/ && $read =~ /analytics_backend\('network_lookup'/;
die "management operation must have manage ACL, CSRF and rate-limit\n"
    unless $icons =~ /assert_manage_access\(\)/ &&
           $icons =~ /assert_post_and_csrf\(\)/ &&
           $icons =~ /request_rate_limit\('network_icons'/;
die "explicit CLEAR confirmation missing\n"
    unless $network=~/get\("confirm"\) != "CLEAR"/;
die "network icon display missing from current endpoint cell\n"
    unless $iface=~/data-wg-net-icon/ &&
           $iface=~/data-wg-endpoint/ &&
           $iface=~/wg-network-icon/ &&
           $iface=~/updateNetworkIcons\(\)/ &&
           $iface=~/network_icon_data\.cgi/;
my $ui_foundation=read_file("$FindBin::Bin/../lib/ui-foundation-lib.pl");
die "network marker style must be shared and absent endpoints must hide it\n"
    unless $ui_foundation=~/\.wg-network-icon/ &&
           $iface=~/icon\.hidden=!address/ &&
           $iface=~/data-wg-net-icon/;
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
my ($template)=$peer=~/(?:print|return) <<PEER_TABS_SCRIPT;\n(.*?)\nPEER_TABS_SCRIPT\n/s;
die "peer tab JS heredoc missing\n" unless defined $template;
our ($js_tabs_id,$js_analytics_url,$js_peer_id,$js_activity_labels,$js_network_cache_url);
$js_tabs_id='"peer-tabs-fixture"';
$js_analytics_url='"/wireguard/analytics_data.cgi"';
$js_peer_id='"'.('a'x64).'"';
$js_activity_labels='{"loading":"Loading","empty":"Empty","events":{}}';
$js_network_cache_url='"/wireguard/network_icon_data.cgi"';
my $generator=eval "sub {return <<PEER_TABS_SCRIPT;\n$template\nPEER_TABS_SCRIPT\n}";
die "peer tab JS template cannot compile: $@" if !$generator || $@;
my $html=$generator->();
my ($js)=$html=~m{<script>\n(.*?)</script>}s;
die "peer tab JS missing\n" if !defined $js;
require "$FindBin::Bin/../lib/network-icons-ui-lib.pl";
my $network_markup=wg_network_icons_page_script(q{"test-network-page"});
my ($network_js)=$network_markup=~m{<script>\s*(.*?)\s*</script>}s;
die "rendered network directory JavaScript missing\n" unless $network_js;
my $node=qx(command -v node 2>/dev/null);
$node =~ s/[\r\n]+\z//;
if($node){
    my ($netfh,$netpath)=tempfile(SUFFIX=>'.js',UNLINK=>1);
    print {$netfh} $network_js;close($netfh);
    system($node,'--check',$netpath)==0 or die "network editor rendered JavaScript invalid\n";
    my ($fh,$path)=tempfile(SUFFIX=>'.js',UNLINK=>1);
    print {$fh} $js;close($fh);
    system($node,'--check',$path)==0 or die "generated peer tabs JS invalid\n";
}
# Unlike direct Node syntax checks of CGI source, evaluate the interpolation
# performed by MiniServ's Perl heredoc. JS regex '$/' is otherwise swallowed by
# Perl's input-record separator and produces a broken endpoint parser.
my ($ip_body)=$iface=~/(    function endpointIp\(value\) \{.*?\n    \})/s;
die "IPv4/IPv6 icon endpoint parser missing\n" if !defined $ip_body;
my $ip_render=eval "sub {return <<NETWORK_IP;\n$ip_body\nNETWORK_IP\n}";
die "IP endpoint interpolation failed: $@\n" if !$ip_render || $@;
my $ip_js=$ip_render->();
if($node){
    my ($fh,$path)=tempfile(SUFFIX=>'.js',UNLINK=>1);
    print {$fh} $ip_js."\n";
    print {$fh} <<'CHECK';
if(endpointIp('8.8.8.8:58142')!=='8.8.8.8')
  throw new Error('IPv4 endpoint regex was destroyed by Perl interpolation');
if(endpointIp('[2001:4860:4860::8888]:443')!=='2001:4860:4860::8888')
  throw new Error('Bracketed IPv6 endpoint was not parsed');
if(endpointIp('10.66.66.1')!=='10.66.66.1')
  throw new Error('Plain IPv4 endpoint was not parsed');
if(endpointIp('2001:4860:4860::8888')!=='2001:4860:4860::8888')
  throw new Error('Bare IPv6 endpoint was not parsed');
if(endpointIp('hostname.example:55822')!=='')
  throw new Error('Network icons must not resolve hostname endpoints');
CHECK
    close($fh);
    system($node,'--check',$path)==0 or die "rendered network icon IP parser syntax invalid\n";
    system($node,$path)==0 or die "rendered network icon IP parser behavior invalid\n";
}
# Test country-code regular expression after the same interpolating heredoc
# expansion used by the CGI. Checking raw Perl source with Node misses '$/'.
my ($country_body)=$iface=~/(    function showNetworkIcons\(\) \{.*?\n    \})/s;
die "GeoIP badge renderer missing\n" unless defined $country_body;
my $country_render=eval "sub { return <<COUNTRY_UI;\n$country_body\nCOUNTRY_UI\n}";
die "GeoIP badge interpolation failed: $@\n" if !$country_render || $@;
my $country_js=$country_render->();
die "GeoIP country regex lost its anchor after Perl interpolation\n"
    unless $country_js =~ m{\^\[A-Za-z\]\{2\}\$/};
if($node){
    my ($fh,$path)=tempfile(SUFFIX=>'.js',UNLINK=>1);
    print {$fh} $country_js."\n";
    close($fh);
    system($node,'--check',$path)==0 or die "rendered GeoIP badge JavaScript invalid\n";
}
print "network badge/cache and peer three-tab UI tests passed\n";
