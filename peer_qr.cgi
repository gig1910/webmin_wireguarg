#!/usr/local/bin/perl
require './wireguard-lib.pl';
ReadParse();
assert_view_access();
assert_export_access();
my $name = $in{'name'};
error($text{'error_invalid_name'}) if (!valid_interface_name($name));
my ($cfg, $err) = parse_wireguard_config(conf_path($name));
error($err) if (!$cfg);
my $peer = get_peer_by_index($cfg, $in{'peer'});
error($text{'error_peer'}) if (!$peer);
my ($runtime) = get_cached_interface_dump($name);
$runtime ||= {};
my ($client, $client_error) = build_client_config($cfg, $peer, $runtime);
error($client_error) if (!$client);
my $image_url = module_script_url('qr_image.cgi', name => $name, peer => $in{'peer'}, nonce => time());
ui_print_header(undef, text('qr_title', peer_display_name($peer, $in{'peer'})), '', undef, 1, 1);
print '<div style="max-width:1000px;margin:auto;text-align:center"><img src="'.html_escape($image_url).'" alt="'.html_escape($text{'peer_qr'}).'" style="width:480px;max-width:100%;height:auto"></div>';
print ui_alert_box($text{'qr_sensitive'}, 'warn');
my $client_warnings = client_config_warnings($cfg, $peer);
print ui_alert_box(join(' ', @$client_warnings), 'warn') if (@$client_warnings);
print '<p>'.direct_link_button(
    'download_client.cgi', $text{'peer_download'},
    { name => $name, peer => $in{'peer'} }, download => 1
).'</p>';
ui_print_footer('edit_peer.cgi?name='.urlize($name).'&peer='.urlize($in{'peer'}), text('peer_title', peer_display_name($peer, $in{'peer'})));
