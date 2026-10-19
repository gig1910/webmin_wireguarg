#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;

# Invoke the production handler directly; no source slicing or eval.
require "$FindBin::Bin/../lib/network-icons-action-lib.pl";

our (%in,%text);
$text{'network_icons_invalid'}='Invalid operation';
$text{'network_icons_saved'}='Saved';
our ($csrf_checks,$write_calls,$rate_calls)=(0,0,0);
our $csrf_valid=0;
our $last_payload;

sub assert_post_and_csrf {
    ++$csrf_checks;
    die "CSRF denied\n" unless ($ENV{'REQUEST_METHOD'}||'GET') eq 'POST' && $csrf_valid;
}
sub request_rate_limit { ++$rate_calls; }
sub analytics_backend {
    my ($method,$payload)=@_;
    ++$write_calls;
    $last_payload={%$payload};
    die "Incorrect backend operation" unless $method eq 'network_manage';
    return ({ok=>1},undef);
}
sub error { die "Request rejected: ".($_[0]||'error')."\n" }

sub run_case {
    my ($method,$params,$allow)=@_;
    local $ENV{'REQUEST_METHOD'}=$method;
    local %in=%$params;
    $csrf_valid=$allow;
    my ($prior_checks,$prior_writes,$prior_rate)=($csrf_checks,$write_calls,$rate_calls);
    my $ok=eval { wg_network_icons_dispatch(); 1 };
    return {
        ok=>$ok,
        error=>$@,
        checks=>$csrf_checks-$prior_checks,
        writes=>$write_calls-$prior_writes,
        rate=>$rate_calls-$prior_rate,
    };
}
my $read_get=run_case('GET',{},0);
die "GET directory view unexpectedly requires CSRF or mutates the cache\n"
    unless $read_get->{ok} && !$read_get->{checks} && !$read_get->{writes};
my $nav=run_case('POST',{navigation=>'1',_wg_api=>'fixture-navigation'},0);
die "Authentic Theme read-only navigation POST was rejected or wrote data\n"
    unless $nav->{ok} && !$nav->{checks} && !$nav->{writes} && !$nav->{rate};
my $blocked=run_case('POST',{action=>'set_icon',cidr=>'203.0.113.0/24'},0);
die "CSRF-less mutation passed or reached the backend\n"
    if $blocked->{ok} || $blocked->{checks}!=1 || $blocked->{writes};
my $get_mutation=run_case('GET',{action=>'clear_cache',confirm=>'CLEAR'},1);
die "Mutation over GET reached backend or skipped POST/CSRF gate\n"
    if $get_mutation->{ok} || $get_mutation->{checks}!=1 || $get_mutation->{writes};
my $accepted=run_case('POST',{
    action=>'set_icon',cidr=>'203.0.113.0/24',icon=>'?',label=>'Sample',
    city=>'Moscow',city_code=>'rumow'
},1);
die "Authorized POST cannot update network icon\n"
    unless $accepted->{ok} && $accepted->{checks}==1 &&
           $accepted->{writes}==1 && $accepted->{rate}==1;
die "Network mutation payload lost CIDR or label\n"
    unless $last_payload->{'action'} eq 'set_icon' &&
           $last_payload->{'cidr'} eq '203.0.113.0/24' &&
           $last_payload->{'label'} eq 'Sample' &&
           $last_payload->{'city'} eq 'Moscow' &&
           $last_payload->{'city_code'} eq 'RUMOW';
my $removed=run_case('POST',{action=>'delete_icon',cidr=>'198.51.100.0/24'},1);
die "Authorized deletion is not dispatched\n"
    unless $removed->{ok} && $removed->{checks}==1 &&
           $removed->{writes}==1 && $last_payload->{'action'} eq 'delete_icon' &&
           $last_payload->{'cidr'} eq '198.51.100.0/24';
my $cleared=run_case('POST',{action=>'clear_cache',confirm=>'CLEAR'},1);
die "Authorized cache clearing is not dispatched with confirmation\n"
    unless $cleared->{ok} && $cleared->{checks}==1 &&
           $cleared->{writes}==1 && $last_payload->{'confirm'} eq 'CLEAR';
my $invalid=run_case('POST',{action=>'evil'},1);
die "Unsupported network mutation reached backend\n"
    if $invalid->{ok} || $invalid->{writes} || $invalid->{checks}!=1 || $invalid->{rate}!=1;

my $refresh=do {
    open(my $fh,'<',"$FindBin::Bin/../network_refresh.cgi") or die $!;
    local $/; <$fh>
};
die "Network refresh endpoint missing from package\n"
    unless do {
        open(my $fh,'<',"$FindBin::Bin/../MANIFEST.wbm") or die $!;
        local $/; my $manifest=<$fh>; $manifest =~ /^network_refresh\.cgi$/m;
    };
die "Network refresh must require ACL, CSRF and rate limiting\n"
    unless $refresh =~ /assert_manage_access\(\)/ &&
           $refresh =~ /assert_post_and_csrf\(\)/ &&
           $refresh =~ /request_rate_limit\('network_refresh'/;
die "Network refresh may only query exact previously observed IPs\n"
    unless $refresh =~ /check_observed_ip/ && $refresh =~ /\$known->\{'known'\}/;
die "Cache refresh must combine WHOIS and GeoIP into one JSON reply\n"
    unless $refresh =~ /peer_ip_whois/ &&
           $refresh =~ /peer_ip_geoip/ &&
           $refresh =~ /json_response/ &&
           $refresh =~ /network_record/;
die "WHOIS and GeoIP preview must never mutate cache before approval\n"
    unless $refresh =~ /my \$commit=/ &&
           $refresh =~ /if \(\$commit && \$whois/ &&
           $refresh =~ /elsif \(\$commit && \$geoip/;
my $client=do {
    open(my $fh,'<',"$FindBin::Bin/../lib/network-icons-ui-lib.pl") or die $!;
    local $/; <$fh>
};
die "Cache UI must preview before approval and update table in place\n"
    unless $client =~ /queryIp\(ip,false,controller\)/ &&
           $client =~ /queryIp\(ip,true,controller\)/ &&
           $client =~ /refreshTable\(\)/ &&
           $client =~ /replaceChildren/;
print "network directory navigation and mutation CSRF regression tests passed\n";
