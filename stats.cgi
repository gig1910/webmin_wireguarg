#!/usr/local/bin/perl
require './wireguard-lib.pl'; ReadParse();
eval {
    assert_view_access();
    my $name=$in{'name'}; die $text{'error_invalid_name'} if !valid_interface_name($name);
    my ($active,$ae)=get_active_interfaces(); die $ae if $ae; die $text{'status_not_running'} if !$active->{$name};
    my ($dump,$de)=get_interface_dump($name); die $de if !$dump;
    my ($rx,$tx)=(0,0); my @peers; my $selected;
    for my $p (@{$dump->{'peer_list'}||[]}) {
        $rx += $p->{'rx_bytes'}||0; $tx += $p->{'tx_bytes'}||0;
        my (undef,$hs)=handshake_state($p->{'latest_handshake'}||0);
        my $row={ id=>substr(sha256_hex($p->{'public_key'}||''),0,16), public_key=>$p->{'public_key'}||'', rx=>0+($p->{'rx_bytes'}||0), tx=>0+($p->{'tx_bytes'}||0), endpoint=>$p->{'endpoint'}||'', handshake=>0+($p->{'latest_handshake'}||0), handshake_text=>$hs };
        push @peers,$row;
        $selected=$row if length($in{'peer'}||'') && ($p->{'public_key'}||'') eq $in{'peer'};
    }
    if (length($in{'peer'}||'')) { die $text{'error_peer_runtime'} if !$selected; $rx=$selected->{'rx'}; $tx=$selected->{'tx'}; }
    my $now=time(); my $window=int($config{'stats_live_window'}||900); $window=60 if $window<60; $window=86400 if $window>86400;
    my $history=read_stats_history($name,$in{'peer'}||'', $now-$window, 10000);
    json_response({ok=>JSON::PP::true(),sample=>{timestamp=>$now,rx=>0+$rx,tx=>0+$tx},history=>$history,peers=>\@peers,peer=>$selected}); 1;
} or do { my $e=$@||'error'; $e=~s/\s+$//; json_response({ok=>JSON::PP::false(),error=>"$e"},'400 Bad Request'); };
