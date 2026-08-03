#!/usr/local/bin/perl
require './wireguard-lib.pl';
ReadParse();
assert_view_access();
assert_export_access();

my $name = $in{'name'};
error($text{'error_invalid_name'}) if (!valid_interface_name($name));
my ($cfg, $read_error) = parse_wireguard_config(conf_path($name));
error($read_error) if (!$cfg);
my $peer = get_peer_by_index($cfg, $in{'peer'});
error($text{'error_peer'}) if (!$peer);

my ($runtime) = get_cached_interface_dump($name);
$runtime ||= {};
my ($client, $client_error) = build_client_config($cfg, $peer, $runtime);
error($client_error) if (!$client);

my $peer_name = peer_display_name($peer, $in{'peer'});
ui_print_header(undef, text('client_config_title', $peer_name), '', undef, 1, 1);
print ui_alert_box($text{'client_config_sensitive'}, 'warn');
my $client_warnings = client_config_warnings($cfg, $peer);
print ui_alert_box(join(' ', @$client_warnings), 'warn') if (@$client_warnings);
print '<textarea readonly rows="18" style="width:100%;font-family:monospace;white-space:pre">'.
    html_escape($client).'</textarea>';
print '<p>'.
    direct_link_button(
        'download_client.cgi', $text{'peer_download'},
        { name => $name, peer => $in{'peer'} }, download => 1
    ).' ';
my $qr = command_path('qrencode_cmd', '/usr/bin/qrencode');
if (has_command($qr)) {
    print direct_link_button(
        'peer_qr.cgi', $text{'peer_qr'},
        { name => $name, peer => $in{'peer'} }
    );
}
else {
    print '<small>'.html_escape(text('qr_command_missing', $qr)).'</small>';
}
print '</p>';
ui_print_footer(
    'edit_peer.cgi?name='.urlize($name).'&peer='.urlize($in{'peer'}),
    text('peer_title', $peer_name)
);
