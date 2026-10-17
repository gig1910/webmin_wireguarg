#!/usr/bin/env perl
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempfile);
use lib "$FindBin::Bin/stub";
use lib "$FindBin::Bin/..";
our (%config, %text, %in);
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

my $plain = build_peer_block(\%peer_data, $peer);
my ($rewritten, $rewrite_error) = rewrite_peer_block_preshared_key($plain, $imported, 0);
die "enabled peer rewrite failed: $rewrite_error\n" if (!defined($rewritten));
my @enabled_psk = ($rewritten =~ /^PresharedKey\s*=\s*(.+)$/mg);
die "enabled peer has duplicate/missing PresharedKey\n"
    if (@enabled_psk != 1 || $enabled_psk[0] ne $imported);
die "PresharedKey is not placed after PublicKey\n"
    if ($rewritten !~ /^PublicKey\s*=.*\nPresharedKey\s*=\s*\Q$imported\E$/m);

$peer_data{'disabled'} = 1;
my $disabled_plain = build_peer_block(\%peer_data, $peer);
my ($disabled, $disabled_error) = rewrite_peer_block_preshared_key($disabled_plain, $imported, 1);
die "disabled peer rewrite failed: $disabled_error\n" if (!defined($disabled));
my @disabled_psk = ($disabled =~ /^#PresharedKey\s*=\s*(.+)$/mg);
die "disabled peer has duplicate/missing PresharedKey\n"
    if (@disabled_psk != 1 || $disabled_psk[0] ne $imported);

my ($removed, $remove_error) = rewrite_peer_block_preshared_key($rewritten, '', 0);
die "PresharedKey removal rewrite failed: $remove_error\n" if (!defined($removed));
die "PresharedKey remained after removal\n" if ($removed =~ /^#?PresharedKey\s*=/m);

# Exercise the EXACT function called by save_peer.cgi. Do not set $0:
# MiniServ is allowed to provide its own executable name to Perl.
{
    local $0='miniserv.pl';
    $peer_data{'disabled'}=0;
    $peer_data{'name'}='Laptop After Save';
    my ($saved, $err)=build_peer_block_with_preshared_key(
        \%peer_data, $peer, '', 0, 0
    );
    die "ordinary peer save lost PresharedKey: $err\n"
        if !defined($saved) || $saved !~ /^PresharedKey\s*=\s*\Q$existing\E$/m;
    my @keys=$saved =~ /^\s*PresharedKey\s*=\s*(.*?)\s*$/mg;
    die "PresharedKey duplicated on ordinary save\n" if @keys!=1;

    # Verify that real config replacement/reparse does not lose PSK while
    # other fields (name, endpoint, AllowedIPs) change.
    my $updated=replace_section($cfg,$peer,$saved);
    my ($tmpfh,$tmppath)=tempfile(SUFFIX=>'.conf',UNLINK=>1);
    print {$tmpfh} $updated;
    close($tmpfh);
    my ($updated_cfg,$parse_err)=parse_wireguard_config($tmppath);
    die "saved peer failed round-trip parsing: $parse_err\n" if !$updated_cfg;
    my $updated_peer=$updated_cfg->{'peers'}->[0];
    die "round-trip save lost PresharedKey\n"
        unless (get_section_value($updated_peer,'PresharedKey')||'') eq $existing;
    die "peer name changed incorrectly\n"
        unless peer_display_name($updated_peer,0) eq 'Laptop After Save';
    die "AllowedIPs changed incorrectly\n"
        unless (get_section_value($updated_peer,'AllowedIPs')||'') =~ /10\.66\.66\.2/;

    ($saved,$err)=build_peer_block_with_preshared_key(
        \%peer_data, $peer, $imported, 0, 0
    );
    die "explicit import did not replace PresharedKey: $err\n"
        if !$saved || $saved !~ /^PresharedKey\s*=\s*\Q$imported\E$/m;
    ($saved,$err)=build_peer_block_with_preshared_key(
        \%peer_data, $peer, '', 1, 0
    );
    die "explicit generation failed: $err\n"
        if !$saved || $saved !~ /^PresharedKey\s*=\s*\Q$generated\E$/m;
    ($saved,$err)=build_peer_block_with_preshared_key(
        \%peer_data, $peer, '', 0, 1
    );
    die "explicit removal failed: $err\n"
        if !defined($saved) || $saved =~ /^#?PresharedKey\s*=/m;
    ($saved,$err)=build_peer_block_with_preshared_key(
        \%peer_data, $peer, $imported, 0, 1
    );
    die "simultaneous import+remove must be rejected\n"
        if defined($saved) || !length($err||'');

    # PSK must remain installed even when a peer is disabled, and later
    # re-enabled. Disabled peers are serialized as commented config blocks.
    $peer_data{'disabled'}=1;
    ($saved,$err)=build_peer_block_with_preshared_key(
        \%peer_data, $peer, '', 0, 0
    );
    die "disabling peer lost PSK: $err\n"
        if !$saved || $saved !~ /^#PresharedKey\s*=\s*\Q$existing\E$/m;
    $updated=replace_section($cfg,$peer,$saved);
    open(my $f,'>',$tmppath) or die $!;
    print {$f} $updated;close($f);
    ($updated_cfg,$parse_err)=parse_wireguard_config($tmppath);
    die "disabled peer reparse failed: $parse_err\n" if !$updated_cfg;
    $updated_peer=$updated_cfg->{'peers'}->[0];
    die "disabled peer does not retain parsed PSK\n"
        if !$updated_peer->{'disabled'} ||
          (get_section_value($updated_peer,'PresharedKey')||'') ne $existing;
    $peer_data{'disabled'}=0;
    ($saved,$err)=build_peer_block_with_preshared_key(
        \%peer_data, $updated_peer, '', 0, 0
    );
    die "re-enabled peer lost PSK: $err\n"
        if !$saved || $saved !~ /^PresharedKey\s*=\s*\Q$existing\E$/m;
}

my $save_source=do {
    open(my $fh,'<',"$FindBin::Bin/../save_peer.cgi") or die $!;
    local $/; <$fh>
};
die "save_peer.cgi is not explicitly preserving PresharedKey\n"
    unless $save_source =~ /build_peer_block_with_preshared_key\(/ &&
           $save_source =~ /\$in\{'remove_preshared_key'\}/ &&
           $save_source =~ /error\(\$psk_error\)/;
my $lib_source=do {
    open(my $fh,'<',"$FindBin::Bin/../lib/preshared-key-lib.pl") or die $!;
    local $/; <$fh>
};
die "PSK save depends on CGI executable name\n"
    if $lib_source =~ /\$\s*0\s*[!=~]/ || $lib_source =~ /WG_PSK_ORIGINAL_BUILD_PEER_BLOCK/;

my ($client, $client_error) = build_client_config($cfg, $peer, {});
die "client config failed: $client_error\n" if (!$client);
die "PresharedKey missing from client config\n"
    if ($client !~ /^PresharedKey = \Q$existing\E$/m);

{
    no warnings qw(redefine);
    local *main::ui_table_row = sub { return join(' ', @_); };
    die "PresharedKey value leaked into form helper source\n"
        if (preshared_key_form_rows_for_state(1) =~ /\Q$existing\E/);
}

print "PresharedKey tests passed\n";
