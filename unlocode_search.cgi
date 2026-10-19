#!/usr/local/bin/perl
require './wireguard-lib.pl';
ReadParse();
eval {
    assert_view_access();
    request_rate_limit('unlocode_search',30,60);
    my $term=$in{'term'}||'';
    if (!utf8::is_utf8($term)) {
        require Encode;
        $term=Encode::decode('UTF-8',$term,Encode::FB_CROAK());
    }
    my $country=uc($in{'country'}||'');
    die 'Invalid city search' if length($term)>80 || $term =~ /[\x00-\x1f]/;
    die 'Invalid country filter' if $country ne '' && $country !~ /^[A-Z]{2}$/;
    my ($data,$err)=analytics_backend('network_manage',{
        action=>'search_unlocode',term=>$term,country=>$country
    });
    die $err if !$data;
    json_response($data);
    1;
} or do {
    my $error=$@||'UN/LOCODE search unavailable';
    json_response({ok=>JSON::PP::false(),error=>"$error"});
};
