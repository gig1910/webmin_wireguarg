#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempfile);
use lib "$FindBin::Bin/stub";
require "$FindBin::Bin/../wireguard-lib.pl";

my $button=wg_ui_icon_action(icon=>'history',label=>'История пира',
    href=>'analytics.cgi?peer_id='.('a'x64));
die "History is not a compact labelled icon-only link\n"
    unless $button=~/wg-ui-icon-btn/ && $button=~/aria-label="История пира"/ &&
           $button=~/title="История пира"/ && $button=~/<svg/ &&
           $button!~/>История пира</;
my $action=wg_ui_icon_action(icon=>'globe',label=>'WHOIS / GeoIP',
    attrs=>{'data-wg-ip-inspect'=>3});
die "WHOIS button missing accessibility or index\n"
    unless $action=~/type="button"/ &&
           $action=~/data-wg-ip-inspect="3"/ && $action=~/<svg/;
my $zone=wg_ui_danger_zone('<button>delete</button>','Danger');
die "Danger zone is not collapsed by default\n"
    unless $zone=~/<details/ && $zone=~/<summary>/ && $zone!~/\sopen(?:\s|>)/;

my $foundation=wg_ui_foundation();
die "Shared popup or clipboard handlers missing\n"
    unless $foundation=~/confirmModal/ &&
           $foundation=~/requestSubmit/ &&
           $foundation=~/wgConfirmWord/ &&
           $foundation=~/navigator\.clipboard\.writeText/;
my $inspector=wg_ui_peer_inspector_script('"page-instance"');
die "WHOIS inline dialog missing explicit click, CSRF or scoped root\n"
    unless $inspector=~/data-wg-ip-inspect/ &&
           $inspector=~/wgIpToken/ &&
           $inspector=~/WireGuardTransport\.requestJson/ &&
           $inspector=~/data-wg-interface-page/;
die "IP inspector must reject stale or closed request results\n"
    unless $inspector =~ /request!==controller/ &&
           $inspector =~ /dialog\.hidden/ &&
           $inspector =~ /request\.abort\(\)/ &&
           $inspector =~ /controller\.signal\.aborted/;
die "IP inspector must check required DOM nodes before reading dataset\n"
    unless $inspector =~ /if\(!dialog\|\|!out\|\|!options\)return/;
my $manifest=do {
    open(my $fh,'<',"$FindBin::Bin/../MANIFEST.wbm") or die $!;
    local $/; <$fh>
};
for my $path (qw(lib/ui-foundation-lib.pl lib/ui-peer-inspector-lib.pl)){
    die "UI component missing from WBM: $path\n"
        unless $manifest=~/^\Q$path\E$/m;
}
my $node=qx(command -v node 2>/dev/null);chomp($node);
if($node){
    for my $html ($foundation,$inspector){
        my ($js)=$html=~m{<script>\s*(.*?)\s*</script>}s;
        die "Rendered UI JavaScript missing\n" unless defined $js;
        my ($fh,$path)=tempfile(SUFFIX=>'.js',UNLINK=>1);
        print {$fh} $js; close($fh);
        system($node,'--check',$path)==0 or die "UI JavaScript syntax invalid\n";
    }
}
my $iface=do {open(my $fh,'<',"$FindBin::Bin/../edit_interface.cgi")or die $!;local $/;<$fh>};
die "Peer table is not using the shared on-demand WHOIS/GeoIP inspector\n"
    unless $iface=~/wg_ui_peer_inspector/ && $iface=~/data-wg-ip-inspect/ &&
           index($iface, q{$history_action})>=0;
print "shared UI icons, danger controls and WHOIS dialog tests passed\n";
