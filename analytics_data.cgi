#!/usr/local/bin/perl
require './wireguard-lib.pl';
ReadParse();
eval {
    assert_view_access();
    my $peer = $in{'peer_id'} || '';
    die $text{'analytics_error_peer'} if ($peer && $peer !~ /^[a-f0-9]{64}$/);
    my $from = $in{'from'} || '';
    my $to = $in{'to'} || '';
    die $text{'analytics_error_time'}
        if ($from !~ /^\d{1,12}$/ || $to !~ /^\d{1,12}$/);
    my ($result, $err) = analytics_backend('query', {
        'peer_id' => $peer, 'from' => 0 + $from, 'to' => 0 + $to,
    });
    die $err if (!$result);
    json_response($result);
    1;
} or do {
    my $error = $@ || $text{'analytics_error_time'};
    $error =~ s/\s+$//;
    json_response({ ok => JSON::PP::false(), error => "$error" });
};
