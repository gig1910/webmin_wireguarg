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
die "Dashboard stop must be orange\n"
    unless $index =~ /mini_action_form\(\$name, 'stop', \$text\{'interface_stop'\}, 'warning'/;
die "Installed QR component wrongly offers installation\n"
    unless $index =~ /if \(!\$qr_status->\{'command_available'\}\)/;
my $analytics=read_text("$FindBin::Bin/../analytics.cgi");
die "Storage maintenance should have neutral panel and destructive buttons\n"
    unless $analytics =~ /wg_ui_panel_start\(\$text\{'ui_storage_maintenance'\}\)/ &&
      $analytics =~ /tone=>\$action eq 'vacuum' \? 'neutral' : 'danger'/;
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
    die "Expected eight grouped sections in $path\n" unless scalar(keys %{$sections{$lang}})==8;
}
for my $key (keys %{$fields{''}}) { die "Missing RU $key\n" unless $fields{'ru'}{$key}; }
die "EN/RU section mismatch\n" unless
    join(',',sort keys %{$sections{''}}) eq join(',',sort keys %{$sections{'ru'}});
my $manifest=read_text("$FindBin::Bin/../MANIFEST.wbm");
die "RU settings missing from WBM\n" unless $manifest =~ /^config\.info\.ru$/m;
print "Theme color contract, IP cells and bilingual settings checks passed\n";
