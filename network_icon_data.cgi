#!/usr/local/bin/perl
require './wireguard-lib.pl';
ReadParse();
eval {
    assert_view_access();
    my $ips=$in{'ips'} || '';
    die "Invalid lookup size" if length($ips)>4096;
    my @ips=grep { length($_) } split(/,/, $ips);
    die "Too many IPs" if @ips>128;
    # Only address literals: no hostnames and no outbound network requests.
    for my $ip (@ips) {
        die "Invalid address" if $ip !~ /^[0-9a-f:.]{2,45}$/i;
    }
    my ($out,$error)=analytics_backend('network_lookup',{ips=>\@ips});
    die $error if !$out;
    json_response($out);
    1;
} or do {
    my $error=$@ || 'Unable to read network icon cache';
    $error =~ s/\s+$//;
    json_response({ok=>JSON::PP::false(),error=>"$error"});
};
