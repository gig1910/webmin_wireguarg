#!/usr/local/bin/perl
require './wireguard-lib.pl';
ReadParse();
assert_view_access();
assert_manage_access();
my $name = $in{'name'};
error($text{'error_invalid_name'}) if (!valid_interface_name($name));
my ($cfg, $err) = parse_wireguard_config(conf_path($name));
error($err) if (!$cfg);
error($text{'error_config_changed'}) if (length($in{'config_digest'} || '') && $in{'config_digest'} ne $cfg->{'digest'});
my $peer = get_peer_by_index($cfg, $in{'peer'});
error($text{'error_peer'}) if (!$peer);
my $expected_public = $in{'public_key'} || '';
error($text{'error_config_changed'}) if (length($expected_public) && (get_section_value($peer, 'PublicKey') || '') ne $expected_public);
my $peer_name = peer_display_name($peer, $in{'peer'});
if (($ENV{'REQUEST_METHOD'} || '') eq 'POST' && $in{'confirm'}) {
    assert_post_and_csrf();
    request_rate_limit('delete', 10, 300);
    my $pub = get_section_value($peer, 'PublicKey') || '';
    my $contents = delete_section($cfg, $peer);
    my ($ok, $write_error) = atomic_write_config(conf_path($name), $contents, $cfg->{'digest'});
    error(text('error_write', conf_path($name), $write_error)) if (!$ok);
    my ($active) = get_active_interfaces();
    my ($apply_ok, $out) = (1, '');
    ($apply_ok, $out) = action_apply_interface($name) if ($active->{$name});
    my ($runtime_invalidated, $runtime_invalidate_error) = (0, '');
    if ($apply_ok) {
        my $runtime_path = runtime_snapshot_path();
        $runtime_invalidated = !-e($runtime_path) || unlink($runtime_path);
        $runtime_invalidate_error = $runtime_invalidated ? '' : "$!";
    }
    webmin_log('delete', 'peer', $name, {
        public_key => $pub,
        runtime_cache_invalidated => $runtime_invalidated ? 1 : 0,
    });
    if ($apply_ok) {
        redirect('edit_interface.cgi?name='.urlize($name));
    }
    ui_print_header(undef, $text{'delete_title'}, '', undef, 1, 1);
    print ui_alert_box($apply_ok ? $text{'delete_done'} : $text{'action_failed'}, $apply_ok ? 'success' : 'danger');
    print '<pre>'.html_escape($out || '').'</pre>' if (length($out || ''));
    ui_print_footer('edit_interface.cgi?name='.urlize($name), text('interface_title', $name));
    exit;
}
ui_print_header(undef, $text{'delete_title'}, '', undef, 1, 1);
print ui_alert_box(text('delete_peer_confirm', html_escape($peer_name)), 'danger');
print ui_form_start('delete_peer.cgi', 'post'); print csrf_hidden();
print ui_hidden('name', $name);
print ui_hidden('peer', $in{'peer'});
print ui_hidden('confirm', 1);
print ui_hidden('config_digest', $cfg->{'digest'});
print ui_hidden('public_key', get_section_value($peer, 'PublicKey') || '');
print ui_form_end([ [ 'delete', $text{'peer_delete'} ] ]);
ui_print_footer('edit_peer.cgi?name='.urlize($name).'&peer='.urlize($in{'peer'}), text('peer_title', $peer_name));
