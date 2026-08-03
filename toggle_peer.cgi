#!/usr/local/bin/perl
require './wireguard-lib.pl';
ReadParse();

my $ajax = $in{'ajax'} ? 1 : 0;

sub json_reply
{
    my (%payload) = @_;
    print "Content-type: application/json; Charset=utf-8\n\n";
    print json_encode_utf8(\%payload);
    exit;
}

sub request_error
{
    my ($message) = @_;
    if ($ajax) {
        json_reply(
            ok => JSON::PP::false,
            error => $message,
        );
    }
    error($message);
}

request_error($text{'error_view'}) if (!$access{'view'});
request_error($text{'action_denied'}) if (!$access{'manage'});
eval { assert_post_and_csrf(); request_rate_limit('manage', 60, 60); 1 } or request_error($@ || $text{'action_post'});

my $name = $in{'name'} || '';
request_error($text{'error_invalid_name'}) if (!valid_interface_name($name));

my $path = conf_path($name);
my ($cfg, $parse_error) = parse_wireguard_config($path);
request_error($parse_error || text('error_read', $path, '')) if (!$cfg);
request_error($text{'error_config_changed'})
    if (length($in{'config_digest'} || '') && $in{'config_digest'} ne $cfg->{'digest'});

my $peer = get_peer_by_index($cfg, $in{'peer'});
request_error($text{'error_peer'}) if (!$peer);

my $public_key = get_section_value($peer, 'PublicKey') || '';
request_error($text{'error_config_changed'})
    if (length($in{'old_public_key'} || '') && $public_key ne $in{'old_public_key'});

my %data = (
    name => $peer->{'meta'}->{'name'} || '',
    private_key => $peer->{'private_key'} || '',
    public_key => $public_key,
    clientaddress => get_meta_value($peer, 'clientaddress') || '',
    allowed_ips => [ get_section_values($peer, 'AllowedIPs') ],
    endpoint => get_section_value($peer, 'Endpoint') || '',
    keepalive => get_section_value($peer, 'PersistentKeepalive') || '',
    clientendpoint => get_meta_value($peer, 'clientendpoint') || '',
    clientdns => get_meta_value($peer, 'clientdns') || '',
    clientallowedips => get_meta_value($peer, 'clientallowedips') || '',
    clientmtu => get_meta_value($peer, 'clientmtu') || '',
    disabled => $peer->{'disabled'} ? 0 : 1,
);

my $original_contents = join('', @{$cfg->{'lines'} || []});
my $contents = replace_section($cfg, $peer, build_peer_block(\%data, $peer));
my ($write_ok, $write_error) = atomic_write_config($path, $contents, $cfg->{'digest'});
request_error($write_error) if (!$write_ok);

my $new_digest = sha256_hex($contents);
my ($active, $active_error) = get_active_interfaces();
if (length($active_error || '')) {
    my ($rollback_ok, $rollback_error) = atomic_write_config($path, $original_contents, $new_digest);
    my $message = text('peer_toggle_runtime_check_failed', $active_error);
    $message .= ' '.text('peer_toggle_rollback_failed', $rollback_error) if (!$rollback_ok);
    request_error($message);
}

my $interface_active = $active->{$name} ? 1 : 0;
my ($apply_ok, $apply_output) = (1, '');
if ($interface_active) {
    ($apply_ok, $apply_output) = action_apply_interface($name);
    if (!$apply_ok) {
        my ($rollback_ok, $rollback_error) = atomic_write_config($path, $original_contents, $new_digest);
        my $message = text('peer_toggle_apply_failed', $apply_output || $text{'action_failed'});
        $message .= ' '.text('peer_toggle_rollback_failed', $rollback_error) if (!$rollback_ok);
        request_error($message);
    }
}

# Refresh the shared snapshot before replying. The page already updates the
# configuration state optimistically, then its normal poller immediately reads
# this fresh snapshot instead of waiting for the collector's next interval.
my ($fresh_snapshot, $refresh_error) = refresh_runtime_snapshot(0);

my $action = $data{'disabled'} ? 'disable' : 'enable';
webmin_log($action, 'peer', $name, {
    public_key => $data{'public_key'},
    runtime_refresh_ok => $fresh_snapshot ? 1 : 0,
});

my $message = $data{'disabled'}
    ? $text{'peer_toggle_disabled_done'}
    : $text{'peer_toggle_enabled_done'};
$message .= ' '.$text{'peer_toggle_saved_inactive'} if (!$interface_active);

if ($ajax) {
    json_reply(
        ok => JSON::PP::true,
        disabled => $data{'disabled'} ? JSON::PP::true : JSON::PP::false,
        interface_active => $interface_active ? JSON::PP::true : JSON::PP::false,
        digest => $new_digest,
        message => $message,
        runtime_refreshed => $fresh_snapshot ? JSON::PP::true : JSON::PP::false,
        runtime_refresh_error => $refresh_error || '',
    );
}

ui_print_header(undef, $text{'action_title'}, '', undef, 1, 1);
print ui_alert_box($message, 'success');
print ui_alert_box(html_escape($refresh_error), 'warning') if (!$fresh_snapshot && length($refresh_error || ''));
print '<pre>'.html_escape($apply_output || '').'</pre>' if (length($apply_output || ''));
ui_print_footer('edit_interface.cgi?name='.urlize($name), text('interface_title', $name));
