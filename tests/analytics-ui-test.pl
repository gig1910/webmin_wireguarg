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
my $api=slurp("$FindBin::Bin/../analytics_data.cgi");
my $maintenance=slurp("$FindBin::Bin/../analytics_maintenance.cgi");
my $collector=slurp("$FindBin::Bin/../stats-collector.pl");
my $index=slurp("$FindBin::Bin/../index.cgi");
my $interface=slurp("$FindBin::Bin/../edit_interface.cgi");
my $peer_page=slurp("$FindBin::Bin/../edit_peer.cgi");
my $manifest=slurp("$FindBin::Bin/../MANIFEST.wbm");
die "analytics tab missing\n" if $ui !~ /nav nav-tabs/ || $index !~ /analytics\.cgi/;
die "date and peer filters missing\n" if $ui !~ /data-peer/ || $ui !~ /data-from/ || $ui !~ /data-to/;
die "analytics entry point missing on interface\n"
    unless $interface =~ /direct_link_button\('analytics\.cgi'/;
die "per-peer analytics link must use public-key fingerprint\n"
    unless $interface =~ /analytics\.cgi\?peer_id=/ &&
           $interface =~ /sha256_hex\(\$public_key\)/;
die "peer detail analytics link missing\n"
    unless $peer_page =~ /direct_link_button\('analytics\.cgi'/ &&
           $peer_page =~ /sha256_hex\(\$public_key\)/;
for my $path (qw(analytics.cgi analytics_data.cgi analytics_maintenance.cgi
                 analytics-store.py lib/analytics-api-lib.pl
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
