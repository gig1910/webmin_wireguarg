#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempfile);
use JSON::PP ();
use MIME::Base64 ();
our %config;
our ($ip_dom_json,$ip_name_json,$ip_index_json,$ip_csrf_json,$ip_labels_json,$ip_url_json);
require "$FindBin::Bin/../lib/geoip-update-lib.pl";
require "$FindBin::Bin/../lib/peer-ip-info-lib.pl";

my $whois_raw="NetRange: 8.8.8.0 - 8.8.8.255\nNetName: DNS-NET\n".
              "OrgName: Example ISP\norigin: AS12345\ncountry: US\n".
              "OrgAbuseEmail: abuse\@example.net\n";
my @calls;
our $allow_mmdb=0;
sub command_path { return $_[1]; }
sub has_command {
    return 0 if $_[0] =~ /mmdblookup$/ && !$allow_mmdb;
    return 1;
}
sub run_command {
    my ($argv) = @_;
    push @calls, [@$argv];
    if($argv->[0] =~ /whois$/){return (1,$whois_raw,0,'whois');}
    if($argv->[0] =~ /geoiplookup$/){return (1,"GeoIP Country Edition: US, United States\n",0,'geoiplookup');}
    if($argv->[0] =~ /mmdblookup$/){
        return (1,"    \"Serbia\" <utf8_string>\n",0,'mmdblookup');
    }
    die "Unexpected command";
}
my $fields=peer_ip_whois_fields($whois_raw);
die "WHOIS parser omitted org/range/ASN\n" unless @$fields >= 5
    && $fields->[0]{value} =~ /8\.8\.8/;
my $whois=peer_ip_whois('8.8.8.8');
die "WHOIS not queried or fields unavailable\n" unless $whois->{ok}
    && @{$whois->{fields}}>=5 && $whois->{raw} eq $whois_raw;
die "WHOIS argv was not a validated IP argument\n"
    unless @calls==1 && $calls[0][0] eq '/usr/bin/whois'
        && $calls[0][1] eq '8.8.8.8';
my $geo=peer_ip_geoip('8.8.8.8');
die "offline legacy GeoIP unsuccessful\n"
    unless $geo->{ok} && @{$geo->{fields}}==1
        && $geo->{fields}[0]{value} eq "US, United States"
        && $geo->{country_code} eq "US";
die "offline GeoIP executed unexpected command\n"
    unless @calls==2 && $calls[1][0] eq '/usr/bin/geoiplookup';
my ($fh,$fake)=tempfile(SUFFIX=>'.mmdb',UNLINK=>1);
print {$fh} "fake\n"; close($fh);
$allow_mmdb=1;
my $country=peer_ip_mmdb_value($fake,'8.8.8.8','country','names','en');
die "GeoLite2 mmdblookup parsing failed\n" unless $country eq 'Serbia';
die "GeoLite2 subprocess argument layout invalid\n"
    unless $calls[-1][0] eq '/usr/bin/mmdblookup' &&
           $calls[-1][1] eq '--file' && $calls[-1][2] eq $fake &&
           $calls[-1][3] eq '--ip' && $calls[-1][4] eq '8.8.8.8';

sub slurp {
    open(my $f,'<',$_[0]) or die $!;
    local $/;return <$f>;
}
my $cgi=slurp("$FindBin::Bin/../peer_ip_info.cgi");
my $page=slurp("$FindBin::Bin/../edit_peer.cgi");
my $manifest=slurp("$FindBin::Bin/../MANIFEST.wbm");
my $backend=slurp("$FindBin::Bin/../analytics-store.py");
die "IP CGI missing viewer ACL, POST/CSRF or rate limit\n"
    unless $cgi =~ /assert_view_access\(\)/ &&
           $cgi =~ /assert_post_and_csrf\(\)/ &&
           $cgi =~ /request_rate_limit\('peer_ip_info'/;
die "IP must come exclusively from handshake-confirmed SQLite identity\n"
    unless $cgi =~ /sha256_hex\(\$public\)/ &&
           $cgi =~ /analytics_backend\('peer_ip'/ &&
           $cgi =~ /\$record->\{'public'\}/ &&
           $backend =~ /def peer_handshake_ip\(conn, request\)/ &&
           $backend =~ /SELECT handshake,handshake_ip FROM peers WHERE id=\?/;
die "Historical IP query must be bound to a recorded event of the same peer\n"
    unless $cgi =~ /event_at/ && $cgi =~ /event_ip/ &&
           $backend =~ /historical endpoint not recorded for this peer/ &&
           $backend =~ /SELECT 1 FROM events WHERE peer_id=\? AND at=\?/ &&
           $backend =~ /ipaddress\.ip_address\(requested\)/;
die "Never use unverified static endpoint for on-demand WHOIS\n"
    if $cgi =~ /get_section_value\(\$peer,\s*'Endpoint'\)/;
die "Lookup dependencies not shipped\n"
    unless $manifest =~ /^peer_ip_info\.cgi$/m &&
           $manifest =~ /^lib\/peer-ip-info-lib\.pl$/m;
die "Expected on-demand lookup; got automatic background calls\n"
    unless $page =~ /button\.addEventListener\('click',async/ &&
           $page =~ /fetch\(info\.url,\{method:'POST'/ &&
           $page =~ /new URLSearchParams/;
die "Rendered values must use DOM textContent\n"
    unless $page =~ /el\.textContent=String\(text\)/;
my ($template)=$page =~ /print <<IP_LOOKUP_SCRIPT;\n(.*?)\nIP_LOOKUP_SCRIPT\n/s;
die "peer IP script template missing\n" if !defined $template;
$ip_dom_json='"test-panel"'; $ip_name_json='"wg0"';$ip_index_json='"0"';
$ip_csrf_json='"csrf-test"';$ip_labels_json='{}';$ip_url_json='"/wireguard/peer_ip_info.cgi"';
my $generator=eval "sub {return <<IP_LOOKUP_SCRIPT;\n$template\nIP_LOOKUP_SCRIPT\n}";
die "Unable to compile peer IP template: $@" if $@ || !$generator;
my $html=$generator->();
my ($js)=$html =~ m{<script>\n(.*?)</script>}s;
die "Rendered peer IP JS missing\n" if !defined $js;
my $node=qx(command -v node 2>/dev/null);
$node =~ s/[\r\n]+\z//;
if($node){
    my ($tmp,$path)=tempfile(SUFFIX=>'.js',UNLINK=>1);
    print {$tmp} $js;
    close($tmp);
    system($node,'--check',$path)==0 or die "Rendered peer IP JS invalid\n";
}
print "peer WHOIS and local GeoIP security, metadata, JS template tests passed\n";
