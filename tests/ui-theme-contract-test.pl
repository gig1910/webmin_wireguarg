#!/usr/bin/env perl
use strict; use warnings; use FindBin;
use lib "$FindBin::Bin/stub";
require "$FindBin::Bin/../wireguard-lib.pl";
sub read_text { open my $fh,'<',$_[0] or die "$_[0]: $!"; local $/; my $s=<$fh>; close $fh; return $s; }
my %native=(neutral=>'btn-default',success=>'btn-success',warning=>'btn-warning',danger=>'btn-danger',info=>'btn-primary');
for my $tone (sort keys %native) {
    my $html=wg_ui_button(icon=>'save',label=>'Example',tone=>$tone);
    die "Missing native $native{$tone} for $tone\n" unless index($html,$native{$tone})>=0;
    die "Missing SVG/text for $tone\n" unless $html =~ /<svg/ && $html =~ /<span>Example<\/span>/;
}
# Verify rendered semantic controls, not caller-specific legacy tone arguments.
my %actions=(start=>'btn-success',add=>'btn-success',save=>'btn-success',
    stop=>'btn-warning',restart=>'btn-warning',edit=>'btn-primary',
    delete=>'btn-danger',clear=>'btn-danger');
for my $action (sort keys %actions) {
    my $html=wg_ui_button(icon=>'save',label=>'Action',action=>$action);
    die "Semantic $action renders wrong native theme class\n"
        unless $html =~ /class="[^"]*\b\Q$actions{$action}\E\b/;
}
my $stop=wg_ui_icon_action(icon=>'stop',label=>'Stop',tone=>'warning');
die "Unreadable stop icon\n" unless $stop =~ /text-warning/ &&
    $stop =~ /fill="currentColor"/ && $stop =~ /aria-label="Stop"/;
my $foundation=read_text("$FindBin::Bin/../lib/ui-foundation-lib.pl");
die "Custom CSS overriding native button background\n" if $foundation =~ /wg-ui-btn\{[^}]*background:/;
my $iface=read_text("$FindBin::Bin/../edit_interface.cgi");
my $iface_js=read_text("$FindBin::Bin/../lib/interface-page-ui-lib.pl");
die "Expected independent network/country/endpoint cells\n"
    unless $iface =~ /data-wg-net-icon/ && $iface =~ /data-wg-geoip-country/ &&
      $iface =~ /data-wg-endpoint/ && $iface =~ /interface_peer_allowed'\}, '', '', \$text\{'interface_peer_endpoint/;
die "Icon columns must not be sortable\n"
    unless $iface_js =~ /\['name','state','ip','actions','actions','endpoint'/;
my $index=read_text("$FindBin::Bin/../index.cgi");
die "Dashboard stop action missing\n"
    unless $index =~ /mini_action_form\(\$name, 'stop'/;
die "Installed QR component wrongly offers installation\n"
    unless $index =~ /if \(!\$qr_status->\{'command_available'\}\)/;
my $analytics=read_text("$FindBin::Bin/../analytics.cgi");
die "Storage maintenance must distinguish vacuum from destructive actions\n"
    unless $analytics =~ /wg_ui_panel_start\(\$text\{'ui_storage_maintenance'\}\)/ &&
      $analytics =~ /action=>\$action eq 'vacuum' \? 'restart' : 'delete'/;
# Navigation is always a labelled native theme button outside tables.
die "Network directory still uses an icon-only or misleading WHOIS action\n"
    unless $index =~ /wg_ui_button\(\s*href=>'network_icons\.cgi',icon=>'network'/s &&
           $iface =~ /wg_ui_button\(\s*href=>'network_icons\.cgi',icon=>'network'/s;
my $modal=read_text("$FindBin::Bin/../lib/ui-peer-inspector-lib.pl");
die "Peer inspector dialogs should inherit the native Webmin panel surface\n"
    unless index($foundation,"panel.className='wg-ui-modal-panel panel panel-default'") >= 0 &&
           index($modal,'wg-ui-modal-panel panel panel-default') >= 0;
die "Client config download needs the theme default button style\n"
    unless read_text("$FindBin::Bin/../lib/api-ui-lib.pl") =~ /btn btn-default wg-ui-btn wg-ui-tone-neutral wg-direct-link/;
my $peer_page=read_text("$FindBin::Bin/../edit_peer.cgi");
die "Peer key attention action bypassed shared edit button\n"
    unless $peer_page =~ /wg_ui_button\(type=>'button',icon=>'edit',tone=>'info'/;
for my $lang ('en','ru') {
    my $labels=read_text("$FindBin::Bin/../lang/$lang");
    die "Missing localized modal close text for $lang\n"
        unless $labels =~ /^ui_close=\S.+/m;
}
my (%sections,%fields);
for my $lang ('','ru') {
    my $path="$FindBin::Bin/../config.info".($lang ? ".$lang" : '');
    my %seen;
    for my $line (split /\n/,read_text($path)) {
        next if $line =~ /^\s*(?:#|$)/;
        my ($key,$desc)=split /=/,$line,2;
        die "Duplicate setting $key in $path\n" if $seen{$key}++;
        if($key =~ /^section_/) {
            die "Section $key must have Webmin type 11\n" unless $desc =~ /,11$/;
            $sections{$lang}{$key}=1;
        } else { $fields{$lang}{$key}=1; }
    }
    die "Settings are not grouped into meaningful sections in $path\n"
        unless scalar(keys %{$sections{$lang}})>=8;
}
for my $key (keys %{$fields{''}}) { die "Missing RU $key\n" unless $fields{'ru'}{$key}; }
die "EN/RU section mismatch\n" unless
    join(',',sort keys %{$sections{''}}) eq join(',',sort keys %{$sections{'ru'}});
my $manifest=read_text("$FindBin::Bin/../MANIFEST.wbm");
die "RU settings missing from WBM\n" unless $manifest =~ /^config\.info\.ru$/m;
print "Theme color contract, IP cells and bilingual settings checks passed\n";
