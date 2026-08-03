#!/usr/local/bin/perl
require './wireguard-lib.pl';
ReadParse();
assert_view_access(); assert_manage_access();
assert_post_and_csrf();
request_rate_limit('manage', 60, 60);
my $old_name = $in{'old_name'} || '';
my $name = length($old_name) ? $old_name : ($in{'name'} || '');
error($text{'error_invalid_name'}) if (!valid_interface_name($name));
my $path = conf_path($name);
error($text{'error_interface_exists'}) if (!length($old_name) && -e $path);
my ($cfg, $ifc);
if (length($old_name)) {
    ($cfg, my $err) = parse_wireguard_config($path);
    error(text('error_read', $path, $err)) if (!$cfg);
    error($text{'error_config_changed'}) if (length($in{'config_digest'} || '') && $in{'config_digest'} ne $cfg->{'digest'});
    $ifc = $cfg->{'interface'};
    error($text{'error_no_interface_section'}) if (!$ifc);
}
my $port = _trim($in{'listen_port'} || '');
error($text{'error_port'}) if (length($port) && ($port !~ /^\d+$/ || $port < 0 || $port > 65535));
my $private = $ifc ? ($ifc->{'private_key'} || '') : '';
my $public = $ifc ? ($ifc->{'public_key_comment'} || '') : '';
if ($in{'generate_key'}) {
    ($private, my $err) = generate_private_key(); error($err) if (!$private);
    ($public, $err) = derive_public_key($private); error($err) if (!$public);
}
elsif (length(_trim($in{'private_key'} || ''))) {
    $private = _trim($in{'private_key'});
    ($public, my $err) = derive_public_key($private); error($err) if (!$public);
}
elsif (length(_trim($in{'public_key'} || ''))) {
    my $candidate = _trim($in{'public_key'});
    my ($ok, $err) = validate_public_key($candidate); error($err) if (!$ok);
    $public = $candidate if (!length($private));
}
if (length($private)) { ($public, my $err) = derive_public_key($private); error($err) if (!$public); }
my $mtu = _trim($in{'mtu'}); error($text{'error_mtu'}) if (length($mtu) && ($mtu !~ /^\d+$/ || $mtu < 1 || $mtu > 65535));
my $client_mtu = _trim($in{'clientmtu'}); error($text{'error_mtu'}) if (length($client_mtu) && ($client_mtu !~ /^\d+$/ || $client_mtu < 1 || $client_mtu > 65535));
my @addresses = _split_list($in{'addresses'});
my ($addr_ok, $bad_addr) = validate_cidr_list(\@addresses);
error(text('error_cidr', $bad_addr)) if (!$addr_ok);
my @client_allowed = _split_list($in{'clientallowedips'});
my ($client_ok, $bad_client) = validate_cidr_list(\@client_allowed);
error(text('error_cidr', $bad_client)) if (@client_allowed && !$client_ok);
my %data = (
    'addresses' => \@addresses, 'listen_port' => $port,
    'private_key' => $private, 'public_key' => $public,
    'dns' => [ _split_list($in{'dns'}) ], 'mtu' => $mtu, 'table' => _trim($in{'table'}),
    'fwmark' => _trim($in{'fwmark'}), 'saveconfig' => _trim($in{'saveconfig'}),
    'preup' => [ grep { length($_) } map { _trim($_) } split(/\r?\n/, $in{'preup'} || '') ],
    'postup' => [ grep { length($_) } map { _trim($_) } split(/\r?\n/, $in{'postup'} || '') ],
    'predown' => [ grep { length($_) } map { _trim($_) } split(/\r?\n/, $in{'predown'} || '') ],
    'postdown' => [ grep { length($_) } map { _trim($_) } split(/\r?\n/, $in{'postdown'} || '') ],
    'clientendpoint' => _trim($in{'clientendpoint'}), 'clientdns' => _trim($in{'clientdns'}),
    'clientallowedips' => join(', ', @client_allowed), 'clientmtu' => $client_mtu,
);
my $block = build_interface_block(\%data, $ifc);
my $contents;
if ($cfg) { $contents = replace_section($cfg, $ifc, $block); }
else { $contents = $block; }
my ($write_ok, $write_err) = atomic_write_config($path, $contents, $cfg ? $cfg->{'digest'} : undef);
error(text('error_write', $path, $write_err)) if (!$write_ok);
my ($active) = get_active_interfaces();
my ($op_ok, $op_out) = (1, '');
if ($in{'save_apply'} && $active->{$name}) { ($op_ok, $op_out) = action_apply_interface($name); }
elsif ($in{'save_restart'} && $active->{$name}) { ($op_ok, $op_out) = action_restart_interface($name); }
elsif ($in{'save_start'}) { ($op_ok, $op_out) = action_start_interface($name); }
webmin_log(length($old_name) ? 'modify' : 'create', 'interface', $name, { 'runtime_ok' => $op_ok ? 1 : 0 });
ui_print_header(undef, $text{'save_title'}, '', undef, 1, 1);
print ui_alert_box($text{'save_done'}, 'success');
print ui_alert_box('<pre>'.html_escape($op_out).'</pre>', $op_ok ? 'success' : 'danger') if (length($op_out));
ui_print_footer('edit_interface.cgi?name='.urlize($name), text('interface_title', $name));
