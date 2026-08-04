#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use lib "$FindBin::Bin/stub";
use lib "$FindBin::Bin/..";
our (%config, %text, %in, $WG_PSK_ORIGINAL_BUILD_PEER_BLOCK);
$config{'wg_cmd'} = "$FindBin::Bin/bin/wg";
require "$FindBin::Bin/../wireguard-lib.pl";

my $existing = 'BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=';
my $generated = 'CCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCCC=';
my $imported = 'DDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDDD=';

my ($valid, $validation_error) = validate_preshared_key($existing);
die "valid PresharedKey rejected: $validation_error\n" if (!$valid);
die "short PresharedKey accepted\n" if ((validate_preshared_key('bad'))[0]);
die "invalid base64 PresharedKey accepted\n"
    if ((validate_preshared_key('!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!='))[0]);

my ($new_key, $generate_error) = generate_preshared_key();
die "wg genpsk failed: $generate_error\n" if (!$new_key || $new_key ne $generated);

my ($cfg, $parse_error) = parse_wireguard_config("$FindBin::Bin/sample-wg0.conf");
die $parse_error if (!$cfg);
my $peer = $cfg->{'peers'}->[0];
die "sample PresharedKey was not parsed\n"
    if ((get_section_value($peer, 'PresharedKey') || '') ne $existing);

my ($resolved, $resolve_error) = resolve_submitted_preshared_key($peer, '', 0, 0);
die "blank input did not preserve PresharedKey: $resolve_error\n"
    if (!defined($resolved) || $resolved ne $existing);
($resolved, $resolve_error) = resolve_submitted_preshared_key($peer, $imported, 0, 0);
die "imported PresharedKey was not accepted: $resolve_error\n"
    if (!defined($resolved) || $resolved ne $imported);
($resolved, $resolve_error) = resolve_submitted_preshared_key($peer, '', 1, 0);
die "generated PresharedKey mismatch: $resolve_error\n"
    if (!defined($resolved) || $resolved ne $generated);
($resolved, $resolve_error) = resolve_submitted_preshared_key($peer, '', 0, 1);
die "PresharedKey remove action failed\n"
    if (!defined($resolved) || length($resolved));
($resolved, $resolve_error) = resolve_submitted_preshared_key($peer, $imported, 1, 0);
die "conflicting PresharedKey actions were accepted\n" if (defined($resolved) || !length($resolve_error || ''));

my %peer_data = (
    name => $peer->{'meta'}->{'name'} || '',
    private_key => $peer->{'private_key'} || '',
    public_key => get_section_value($peer, 'PublicKey') || '',
    clientaddress => get_meta_value($peer, 'clientaddress') || '',
    allowed_ips => [ get_section_values($peer, 'AllowedIPs') ],
    endpoint => get_section_value($peer, 'Endpoint') || '',
    keepalive => get_section_value($peer, 'PersistentKeepalive') || '',
    clientendpoint => get_meta_value($peer, 'clientendpoint') || '',
    clientdns => get_meta_value($peer, 'clientdns') || '',
    clientallowedips => get_meta_value($peer, 'clientallowedips') || '',
    clientmtu => get_meta_value($peer, 'clientmtu') || '',
    disabled => 0,
);

my $plain = $WG_PSK_ORIGINAL_BUILD_PEER_BLOCK->(\%peer_data, $peer);
my ($rewritten, $rewrite_error) = rewrite_peer_block_preshared_key($plain, $imported, 0);
die "enabled peer rewrite failed: $rewrite_error\n" if (!defined($rewritten));
my @enabled_psk = ($rewritten =~ /^PresharedKey\s*=\s*(.+)$/mg);
die "enabled peer has duplicate/missing PresharedKey\n"
    if (@enabled_psk != 1 || $enabled_psk[0] ne $imported);
die "PresharedKey is not placed after PublicKey\n"
    if ($rewritten !~ /^PublicKey\s*=.*\nPresharedKey\s*=\s*\Q$imported\E$/m);

$peer_data{'disabled'} = 1;
my $disabled_plain = $WG_PSK_ORIGINAL_BUILD_PEER_BLOCK->(\%peer_data, $peer);
my ($disabled, $disabled_error) = rewrite_peer_block_preshared_key($disabled_plain, $imported, 1);
die "disabled peer rewrite failed: $disabled_error\n" if (!defined($disabled));
my @disabled_psk = ($disabled =~ /^#PresharedKey\s*=\s*(.+)$/mg);
die "disabled peer has duplicate/missing PresharedKey\n"
    if (@disabled_psk != 1 || $disabled_psk[0] ne $imported);

my ($removed, $remove_error) = rewrite_peer_block_preshared_key($rewritten, '', 0);
die "PresharedKey removal rewrite failed: $remove_error\n" if (!defined($removed));
die "PresharedKey remained after removal\n" if ($removed =~ /^#?PresharedKey\s*=/m);

# The process-local build_peer_block wrapper is the save_peer.cgi integration.
# Verify preserve, import, generation and removal without changing save_peer.cgi.
{
    local $0 = 'save_peer.cgi';
    local %in = (preshared_key => '');
    $peer_data{'disabled'} = 0;
    my $saved = build_peer_block(\%peer_data, $peer);
    die "save wrapper did not preserve existing PresharedKey\n"
        if ($saved !~ /^PresharedKey\s*=\s*\Q$existing\E$/m);

    %in = (preshared_key => $imported);
    $saved = build_peer_block(\%peer_data, $peer);
    die "save wrapper did not import PresharedKey\n"
        if ($saved !~ /^PresharedKey\s*=\s*\Q$imported\E$/m);

    %in = (generate_preshared_key => 1);
    $saved = build_peer_block(\%peer_data, $peer);
    die "save wrapper did not generate PresharedKey\n"
        if ($saved !~ /^PresharedKey\s*=\s*\Q$generated\E$/m);

    %in = (remove_preshared_key => 1);
    $saved = build_peer_block(\%peer_data, $peer);
    die "save wrapper did not remove PresharedKey\n"
        if ($saved =~ /^#?PresharedKey\s*=/m);
}

my ($client, $client_error) = build_client_config($cfg, $peer, {});
die "client config failed: $client_error\n" if (!$client);
die "PresharedKey missing from client config\n"
    if ($client !~ /^PresharedKey = \Q$existing\E$/m);

die "PresharedKey value leaked into form helper source\n"
    if (preshared_key_form_rows() =~ /\Q$existing\E/);

print "PresharedKey tests passed\n";
