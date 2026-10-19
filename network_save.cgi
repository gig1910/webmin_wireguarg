#!/usr/local/bin/perl
require './wireguard-lib.pl';
ReadParse();
eval {
    assert_manage_access();
    assert_post_and_csrf();
    request_rate_limit('network_icons',12,60);
    my $payload={
        action=>'set_icon',
        cidr=>$in{'cidr'}||'',
        icon=>$in{'icon'}||'?',
        label=>$in{'label'}||'',
        city=>$in{'city'}||'',
        city_code=>uc($in{'city_code'}||''),
    };
    for my $field (qw(icon label city city_code)) {
        my $value=$payload->{$field};
        next if !defined($value) || utf8::is_utf8($value) || $value !~ /[\x80-\xFF]/;
        require Encode;
        $payload->{$field}=Encode::decode('UTF-8',$value,Encode::FB_CROAK());
    }
    my ($result,$err)=analytics_backend('network_manage',$payload);
    die $err||'Could not save network mapping' unless $result && $result->{'ok'};
    json_response({ok=>JSON::PP::true()});
    1;
} or do {
    my $err=$@||'Could not save network mapping';
    $err =~ s/[\r\n]+/ /g;
    json_response({ok=>JSON::PP::false(),error=>"$err"});
};
