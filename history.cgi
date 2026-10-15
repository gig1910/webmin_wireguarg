#!/usr/local/bin/perl
require './wireguard-lib.pl';
ReadParse();

eval {
    assert_view_access();
    my $name = $in{'name'} || '';
    die $text{'error_invalid_name'} if (!valid_interface_name($name));
    my $peer = $in{'peer'} || '';
    if (length($peer)) {
        my ($valid) = validate_public_key($peer);
        die $text{'error_public_key'} if (!$valid);
    }

    my $now = time();
    my $window = int($config{'stats_live_window'} || 900);
    $window = 60 if ($window < 60);
    $window = 86400 if ($window > 86400);
    my $custom = defined($in{'from'}) || defined($in{'to'});
    my ($from, $to);
    if ($custom) {
        die $text{'peer_usage_error_range'} if (
            !defined($in{'from'}) || !defined($in{'to'}) ||
            $in{'from'} !~ /^\d{1,12}$/ || $in{'to'} !~ /^\d{1,12}$/
        );
        ($from, $to) = (0 + $in{'from'}, 0 + $in{'to'});
        die $text{'peer_usage_error_range'}
            if (!$from || $from >= $to || $to > $now + 60 || $to - $from > 90*86400);
    }
    else {
        ($from, $to) = ($now - $window, $now);
    }

    # Read one extra sample to flag a clipped response rather than reporting
    # an apparently complete aggregate from only its latest 20k observations.
    my $history = read_stats_history($name, $peer, $from, 20001, $to);
    my $truncated = @$history > 20000 ? 1 : 0;
    shift(@$history) if ($truncated);

    my $effective = collector_effective_settings(\%config);
    my $usage = peer_usage_summary($history, $from, $to, $effective->{'stats_refresh_interval'});
    my $retention = $effective->{'stats_history_retention'} < $effective->{'stats_live_retention'}
        ? $effective->{'stats_history_retention'} : $effective->{'stats_live_retention'};
    json_response({
        ok => JSON::PP::true(),
        timestamp => $now, from => $from, to => $to,
        retention => $retention, truncated => $truncated ? JSON::PP::true() : JSON::PP::false(),
        usage => $usage, history => $history,
    });
    1;
} or do {
    my $error = $@ || 'error';
    $error =~ s/\s+$//;
    json_response({ ok => JSON::PP::false(), error => "$error" }, '400 Bad Request');
};
