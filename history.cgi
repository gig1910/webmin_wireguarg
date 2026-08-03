#!/usr/local/bin/perl
require './wireguard-lib.pl';
ReadParse();

eval {
    assert_view_access();
    my $name = $in{'name'} || '';
    die $text{'error_invalid_name'} if (!valid_interface_name($name));
    my $peer = $in{'peer'} || '';
    if (length($peer)) { my ($valid) = validate_public_key($peer); die $text{'error_public_key'} if (!$valid); }

    my $now = time();
    my $window = int($config{'stats_live_window'} || 900);
    $window = 60 if ($window < 60);
    $window = 86400 if ($window > 86400);
    my $history = read_stats_history($name, $peer, $now - $window, 10000);
    json_response({
        'ok' => JSON::PP::true(),
        'timestamp' => $now,
        'history' => $history,
    });
    1;
} or do {
    my $error = $@ || 'error';
    $error =~ s/\s+$//;
    json_response({ 'ok' => JSON::PP::false(), 'error' => "$error" }, '400 Bad Request');
};
