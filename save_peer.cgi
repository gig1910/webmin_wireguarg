#!/usr/local/bin/perl
require './wireguard-lib.pl';
ReadParse();
assert_view_access();
assert_manage_access();

assert_post_and_csrf();
request_rate_limit('manage', 60, 60);
my $name = $in{'name'};
error($text{'error_invalid_name'}) if (!valid_interface_name($name));

my ($cfg, $err) = parse_wireguard_config(conf_path($name));
error(text('error_read', conf_path($name), $err)) if (!$cfg);
error($text{'error_config_changed'})
    if (length($in{'config_digest'} || '') && $in{'config_digest'} ne $cfg->{'digest'});

my $is_new = !defined($in{'peer'}) || $in{'peer'} eq '';
my $old = $is_new ? undef : get_peer_by_index($cfg, $in{'peer'});
error($text{'error_peer'}) if (!$is_new && !$old);
error($text{'error_config_changed'})
    if (!$is_new && length($in{'old_public_key'} || '') &&
        (get_section_value($old, 'PublicKey') || '') ne $in{'old_public_key'});

my $private = $old ? ($old->{'private_key'} || '') : '';
my $public = $old ? (get_section_value($old, 'PublicKey') || '') : '';
if ($in{'generate_key'}) {
    ($private, $err) = generate_private_key();
    error($err) if (!$private);
    ($public, $err) = derive_public_key($private);
    error($err) if (!$public);
}
elsif (length(_trim($in{'private_key'} || ''))) {
    $private = _trim($in{'private_key'});
    ($public, $err) = derive_public_key($private);
    error($err) if (!$public);
}
elsif (!length($private) && length(_trim($in{'public_key'} || ''))) {
    my $candidate = _trim($in{'public_key'});
    my ($ok, $validation_error) = validate_public_key($candidate);
    error($validation_error) if (!$ok);
    $public = $candidate;
}
if (length($private)) {
    ($public, $err) = derive_public_key($private);
    error($err) if (!$public);
}
error($text{'error_peer_key_required'}) if (!length($public));

for (my $i = 0; $i < @{$cfg->{'peers'}}; $i++) {
    next if (!$is_new && $i == $in{'peer'});
    my $other = get_section_value($cfg->{'peers'}->[$i], 'PublicKey') || '';
    error($text{'error_duplicate_peer_key'}) if ($other eq $public);
}

my $client_mtu = _trim($in{'clientmtu'} || '');
error($text{'error_mtu'})
    if (length($client_mtu) && ($client_mtu !~ /^\d+$/ || $client_mtu < 1 || $client_mtu > 65535));
my $keepalive = _trim($in{'keepalive'} || '');
error($text{'error_keepalive'})
    if (length($keepalive) && ($keepalive !~ /^\d+$/ || $keepalive < 0 || $keepalive > 65535));

my @client_addresses = _split_list($in{'clientaddress'});
my ($address_ok, $bad_address) = validate_cidr_list(\@client_addresses);
error(text('error_cidr', $bad_address)) if (@client_addresses && !$address_ok);

my @routes = _split_list($in{'allowed_ips'});
my ($routes_ok, $bad_route) = validate_cidr_list(\@routes);
error(text('error_cidr', $bad_route)) if (@routes && !$routes_ok);

# The tunnel address is the first server-side AllowedIPs entry.  The editor
# presents it separately, but the wg-quick file receives one combined list.
my %seen;
my @server_allowed = grep { length($_) && !$seen{$_}++ } (@client_addresses, @routes);
error($text{'error_allowed_required'}) if (!@server_allowed);

my $conflict = peer_allowed_ip_conflict(
    $cfg,
    \@server_allowed,
    $is_new ? undef : $in{'peer'}
);
if ($conflict) {
    my $peer_name = $conflict->{'peer_name'};
    $peer_name .= ' ('.$text{'peer_disabled'}.')' if ($conflict->{'disabled'});
    error(text(
        'error_allowed_overlap',
        $conflict->{'candidate'},
        $conflict->{'existing'},
        $peer_name
    ));
}

my @client_allowed = _split_list($in{'clientallowedips'});
my ($client_ok, $bad_client) = validate_cidr_list(\@client_allowed);
error(text('error_cidr', $bad_client)) if (@client_allowed && !$client_ok);

my %data = (
    name => _trim($in{'peer_name'}),
    private_key => $private,
    public_key => $public,
    clientaddress => join(', ', @client_addresses),
    allowed_ips => [ join(', ', @server_allowed) ],
    endpoint => _trim($in{'endpoint'}),
    keepalive => $keepalive,
    clientendpoint => _trim($in{'clientendpoint'}),
    clientdns => _trim($in{'clientdns'}),
    clientallowedips => join(', ', @client_allowed),
    clientmtu => $client_mtu,
    disabled => $in{'disabled'} ? 1 : 0,
);

my $block = build_peer_block(\%data, $old);
my $contents = $is_new ? append_peer($cfg, $block) : replace_section($cfg, $old, $block);
my ($write_ok, $write_error) = atomic_write_config(conf_path($name), $contents, $cfg->{'digest'});
error(text('error_write', conf_path($name), $write_error)) if (!$write_ok);

my ($active) = get_active_interfaces();
my ($apply_ok, $apply_output) = (1, '');
if ($active->{$name}) {
    ($apply_ok, $apply_output) = action_apply_interface($name);
}
my ($runtime_invalidated, $runtime_invalidate_error) = (0, '');
if ($apply_ok) {
    my $runtime_path = runtime_snapshot_path();
    $runtime_invalidated = !-e($runtime_path) || unlink($runtime_path);
    $runtime_invalidate_error = $runtime_invalidated ? '' : "$!";
}
webmin_log($is_new ? 'create' : 'modify', 'peer', $name,
    {
        public_key => $public,
        runtime_ok => $apply_ok ? 1 : 0,
        runtime_cache_invalidated => $runtime_invalidated ? 1 : 0,
    });

if ($is_new && $apply_ok) {
    redirect('edit_interface.cgi?name='.urlize($name));
}

my ($new_cfg) = parse_wireguard_config(conf_path($name));
my $new_index = 0;
for (my $i = 0; $i < @{$new_cfg->{'peers'}}; $i++) {
    if ((get_section_value($new_cfg->{'peers'}->[$i], 'PublicKey') || '') eq $public) {
        $new_index = $i;
        last;
    }
}

ui_print_header(undef, $text{'save_title'}, '', undef, 1, 1);
print ui_alert_box($text{'save_done'}, 'success');
print ui_alert_box('<pre>'.html_escape($apply_output).'</pre>', $apply_ok ? 'success' : 'danger')
    if (length($apply_output || ''));
ui_print_footer(
    'edit_peer.cgi?name='.urlize($name).'&peer='.$new_index,
    text('peer_title', peer_display_name($new_cfg->{'peers'}->[$new_index], $new_index))
);
