#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
sub slurp {
    open(my $fh,'<',$_[0]) or die $!;
    local $/;
    return <$fh>;
}
my $ui=slurp("$FindBin::Bin/../analytics.cgi");
my $controller=slurp("$FindBin::Bin/../lib/analytics-page-ui-lib.pl");
die "analytics CGI does not load the isolated controller\n"
    unless $ui =~ m{require './lib/analytics-page-ui-lib.pl'} &&
           $ui =~ /wg_analytics_controller_script\(/;
$ui .= "\n".$controller;  # Verify the composed page and its controller contract.

my $api=slurp("$FindBin::Bin/../analytics_data.cgi");
my $maintenance=slurp("$FindBin::Bin/../analytics_maintenance.cgi");
my $collector=slurp("$FindBin::Bin/../stats-collector.pl");
my $index=slurp("$FindBin::Bin/../index.cgi");
my $interface=slurp("$FindBin::Bin/../edit_interface.cgi");
die "interface CGI must delegate to isolated page controller\n"
    unless $interface =~ m{require './lib/interface-page-ui-lib.pl'} &&
           $interface =~ /wg_interface_page_script\(/;
$interface .= "\n".slurp("$FindBin::Bin/../lib/interface-page-ui-lib.pl");
my $peer_page=slurp("$FindBin::Bin/../edit_peer.cgi");
my $manifest=slurp("$FindBin::Bin/../MANIFEST.wbm");
# Validate the shared component output; CGI checks only assert its use.
use lib "$FindBin::Bin/stub";
require "$FindBin::Bin/../wireguard-lib.pl";
my $tabs_analytics=wg_ui_main_tabs('analytics');
my $tabs_interfaces=wg_ui_main_tabs('interfaces');
die "shared primary navigation not wired\n"
    unless $ui =~ /wg_ui_main_tabs\('analytics'\)/ &&
           $index =~ /wg_ui_main_tabs\('interfaces'\)/;
for my $tabs ($tabs_analytics,$tabs_interfaces) {
    die "shared navigation lacks both destinations\n"
        unless $tabs =~ /href="index\.cgi"/ && $tabs =~ /href="analytics\.cgi"/ &&
               $tabs =~ /data-wg-module-navigation="1"/;
    die "shared navigation must select one tab\n"
        unless scalar(() = $tabs =~ /aria-current="page"/g) == 1;
}
die "selected analytics tab is incorrect\n"
    unless $tabs_analytics =~ /class="active"><a href="analytics\.cgi" aria-current="page"/;
die "selected interfaces tab is incorrect\n"
    unless $tabs_interfaces =~ /class="active"><a href="index\.cgi" aria-current="page"/;
# Match actual form controls instead of matching unrelated option values in JS.
for my $control (qw(interface peer period auto-refresh)) {
    die "analytics filter $control is missing or duplicated\n"
        unless scalar(() = $ui =~ /<select\b[^>]*\bdata-\Q$control\E(?:\s|>)/g) == 1;
}
for my $control (qw(from to)) {
    die "analytics datetime filter $control is missing\n"
        unless $ui =~ /<input\b[^>]*type="datetime-local"[^>]*\bdata-\Q$control\E(?:\s|>)/;
}
my ($period_options)=$ui =~ /<select\b[^>]*\bdata-period\b[^>]*>(.*?)<\/select>/s;
die "period selector missing\n" unless defined $period_options;
my @period_values=($period_options =~ /<option\b[^>]*\bvalue="([^"]+)"/g);
my @expected_periods=qw(21600 86400 604800 month quarter halfyear year custom);
die "analytics period choices differ\n"
    unless join(',',@period_values) eq join(',',@expected_periods);
die "minimum history window shorter than six hours\n" unless $ui =~ /to-from<21600/;
die "calendar periods may overflow at month-end\n"
    unless $ui =~ /d\.setDate\(1\)/ &&
           $ui =~ /Math\.min\(day,new Date\(d\.getFullYear\(\),d\.getMonth\(\)\+1,0\)\.getDate\(\)\)/;
my ($refresh_options)=$ui =~ /<select\b[^>]*\bdata-auto-refresh\b[^>]*>(.*?)<\/select>/s;
die "auto-refresh selector missing\n" unless defined $refresh_options;
my @refresh_values=($refresh_options =~ /<option\b[^>]*\bvalue="([^"]+)"/g);
die "auto refresh must offer off, 10m and 30m only\n"
    unless join(',',@refresh_values) eq '0,600,1800';
die "auto refresh must default to off\n"
    unless $refresh_options =~ /<option\b[^>]*\bvalue="0"[^>]*\bselected\b/;
die "auto refresh must pause for hidden and fixed custom periods\n"
    unless $ui =~ /document\.hidden/ && $ui =~ /period\.value==='custom'/ &&
           $ui =~ /clearTimeout\(autoTimer\)/ &&
           $ui =~ /visibilitychange/ && $ui =~ /pagehide/;
die "SVG mirrored graph or theme colors missing"
    unless $ui =~ /series\('tx',-1\);series\('rx',1\)/ &&
           $ui =~ /createElementNS\(svgNs/ && $ui =~ /fill-opacity/ &&
           $ui =~ /--primary-color/ && $ui =~ /--success-color/ &&
           $ui =~ /data-chart-svg/;
# Check actual tab markup and initial accessibility state, independently of
# how the controller names its local variables.
my @tabs=($ui =~ /<a\b([^>]*\bdata-wg-analytics-tab="(?:graph|events)"[^>]*)>/g);
my @panes=($ui =~ /<div\b([^>]*\bdata-wg-analytics-pane="(?:graph|events)"[^>]*)>/g);
die "analytics must have exactly two tabs and panes\n"
    unless @tabs==2 && @panes==2;
for my $name (qw(graph events)) {
    my @matching_tabs=grep { /\bdata-wg-analytics-tab="\Q$name\E"/ } @tabs;
    my @matching_panes=grep { /\bdata-wg-analytics-pane="\Q$name\E"/ } @panes;
    die "analytics $name tab and pane must be unique\n"
        unless @matching_tabs==1 && @matching_panes==1;
    my $expected=$name eq 'graph' ? 'true' : 'false';
    die "analytics $name initial selection is wrong\n"
        unless $matching_tabs[0] =~ /\baria-selected="\Q$expected\E"/;
    die "analytics $name initial visibility is wrong\n"
        unless (($matching_panes[0] =~ /\bhidden(?:\s|$)/) ? 'false' : 'true') eq $expected;
}
die "analytics tab controller does not update accessibility and visibility\n"
    unless $ui =~ /setAttribute\('aria-selected'/ && $ui =~ /pane\.hidden/;
die "event sorting missing"
    unless $ui =~ /data-wg-event-sort-table/ && $ui =~ /eventSort\.apply\(\)/;
die "peer name in selector and event list missing\n"
    if $ui !~ /peerLabel\(p\)/ || $ui !~ /peerData&&peerData\.name/ ||
       $ui !~ /abbreviated/ || $ui !~ /analytics_event_time/;
die "last handshake and confirmed IP missing from analytics\n"
    if $ui !~ /data-last-handshake/ || $ui !~ /data-handshake-ip/;
die "new compact IP event translations missing\n"
    if $ui !~ /analytics_event_endpoint_ip_observed/ ||
       $ui !~ /analytics_event_endpoint_ip_changed/;

die "analytics entry point missing on interface\n"
    unless $interface =~ /wg_ui_button\(href=>'analytics\.cgi\?interface='/;
die "interface analytics link does not select current interface\n"
    unless $interface =~ /urlize\(\$name\)/ && $interface =~ /analytics_interface_link/;
die "analytics interface selector or backend filter missing\n"
    unless $ui =~ /data-interface/ && $ui =~ /searchParams\.set\('interface'/ &&
           $ui =~ /initialInterface/;
die "theme panel sections and history table missing\n"
    unless $ui =~ /panel panel-default wg-analytics-section/ &&
           $ui =~ /table table-striped table-hover/ &&
           $ui =~ /wg_ui_panel_start/ && $ui =~ /ui_storage_maintenance/ &&
           $ui =~ /data-wg-confirm-word/;
die "live peer sorting or updated counter keys missing"
    unless $interface =~ /data-wg-peer-sort-table/ &&
           $interface =~ /WireGuardTableSort\.attach/ &&
           $interface =~ /tableSort\.apply\(\)/ &&
           $interface =~ /sortEpoch/ && $interface =~ /sortBytes/;
die "peer history link lost Webmin navigation\n"
    unless $ui =~ /data-wg-module-navigation/ && $ui =~ /peerData\.peer_url/;

die "per-peer analytics link must use public-key fingerprint\n"
    unless $interface =~ /analytics\.cgi\?peer_id=/ &&
           $interface =~ /sha256_hex\(\$public_key\)/;
die "peer detail analytics link missing\n"
    unless $peer_page =~ /direct_link_button\('analytics\.cgi'/ &&
           $peer_page =~ /sha256_hex\(\$public_key\)/;
for my $path (qw(analytics.cgi analytics_data.cgi analytics_maintenance.cgi
                 analytics-store.py lib/analytics-api-lib.pl
                 lib/analytics-page-ui-lib.pl
                 collector_status.cgi lib/collector-config-lib.pl)) {
    die "analytics or collector component omitted from Webmin package: $path\n"
        unless $manifest =~ /^\Q$path\E$/m;
}
die "backend uses direct SQL in CGI\n" if $api =~ /sqlite3|system\(/;
die "analytics data missing view ACL\n" if $api !~ /assert_view_access/;
die "maintenance missing security gates\n"
    if $maintenance !~ /assert_manage_access/ ||
       $maintenance !~ /assert_post_and_csrf/ ||
       $maintenance !~ /request_rate_limit/;
die "deletion confirmation missing\n" if $maintenance !~ /DELETE/;
die "analytics not connected to collector\n" if $collector !~ /analytics_call\('ingest'/;
die "collector live graph removed\n" if $collector !~ /append_sample\(\$name/;
die "Prometheus export not connected\n" if $collector !~ /analytics_call\('prometheus'/;
my $delete=slurp("$FindBin::Bin/../delete_peer.cgi");
die "peer deletion destroys analytics\n" if $delete =~ /analytics\.sqlite3|analytics-store/;
print "analytics UI security and collector integration checks passed\n";
