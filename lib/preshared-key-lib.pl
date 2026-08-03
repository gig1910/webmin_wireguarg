=head1 preshared-key-lib.pl

PresharedKey validation, generation, configuration rewrite and peer-form UI.

The actual key is never rendered into HTML. Existing values are represented only
by a present/missing status, and a blank input preserves the stored value.

=cut

sub _preshared_key_russian_ui
{
    return (($text{'yes'} || '') eq 'Да' || ($text{'peer_title'} || '') =~ /Пир/);
}

sub preshared_key_text
{
    my ($key) = @_;
    my %en = (
        input => 'New or imported PresharedKey',
        generate => 'Generate a new PresharedKey',
        remove => 'Remove the stored PresharedKey',
        conflict => 'Choose only one PresharedKey action: enter a key, generate one, or remove the stored key.',
        invalid => 'PresharedKey has an invalid WireGuard key format.',
        generate_failed => 'Failed to generate a WireGuard PresharedKey.',
        insert_failed => 'Failed to place PresharedKey into the peer configuration.',
        not_shown => 'The stored value is not displayed.',
    );
    my %ru = (
        input => 'Новый или переносимый PresharedKey',
        generate => 'Сгенерировать новый PresharedKey',
        remove => 'Удалить сохранённый PresharedKey',
        conflict => 'Выберите только одно действие с PresharedKey: ввод ключа, генерацию или удаление сохранённого ключа.',
        invalid => 'PresharedKey имеет неверный формат ключа WireGuard.',
        generate_failed => 'Не удалось сгенерировать PresharedKey WireGuard.',
        insert_failed => 'Не удалось добавить PresharedKey в конфигурацию пира.',
        not_shown => 'Сохранённое значение не отображается.',
    );
    return (_preshared_key_russian_ui() ? $ru{$key} : $en{$key}) || $key;
}

sub validate_preshared_key
{
    my ($key) = @_;
    $key = _trim($key);
    return (0, preshared_key_text('invalid')) if ($key !~ /^[A-Za-z0-9+\/]{43}=$/);
    my $decoded = eval { MIME::Base64::decode_base64($key) };
    return (0, preshared_key_text('invalid'))
        if (!defined($decoded) || length($decoded) != 32);
    return (1, undef);
}

sub generate_preshared_key
{
    my $wg = command_path('wg_cmd', '/usr/bin/wg');
    return (undef, text('error_command', $wg)) if (!has_command($wg));
    my ($ok, $out) = run_command([ $wg, 'genpsk' ], 1, 15, 2000);
    return (undef, preshared_key_text('generate_failed')) if (!$ok);
    $out = _trim($out);
    my ($valid, $error) = validate_preshared_key($out);
    return (undef, $error) if (!$valid);
    return ($out, undef);
}

sub resolve_submitted_preshared_key
{
    my ($old_peer, $input, $generate, $remove) = @_;
    my $existing = $old_peer ? (get_section_value($old_peer, 'PresharedKey') || '') : '';
    $input = _trim($input || '');
    $generate = $generate ? 1 : 0;
    $remove = $remove ? 1 : 0;

    my $actions = (length($input) ? 1 : 0) + $generate + $remove;
    return (undef, preshared_key_text('conflict')) if ($actions > 1);
    return ('', undef) if ($remove);
    if ($generate) {
        return generate_preshared_key();
    }
    if (length($input)) {
        my ($valid, $error) = validate_preshared_key($input);
        return (undef, $error) if (!$valid);
        return ($input, undef);
    }
    return ($existing, undef);
}

sub rewrite_peer_block_preshared_key
{
    my ($block, $preshared_key, $disabled) = @_;
    $block = '' if (!defined($block));
    $preshared_key = _trim($preshared_key || '');

    # build_peer_block() currently preserves PresharedKey as an unknown setting.
    # Remove that preserved line first, then add the resolved value in the
    # canonical position directly after PublicKey.
    $block =~ s/^[ \t]*#?[ \t]*PresharedKey[ \t]*=.*(?:\r?\n|\z)//gmi;
    return ($block, undef) if (!length($preshared_key));

    my $line = sprintf('%-20s = %s', 'PresharedKey', $preshared_key)."\n";
    my $inserted;
    if ($disabled) {
        $inserted = ($block =~ s/(^#[ \t]*PublicKey[ \t]*=.*\r?\n)/$1#$line/mi);
    }
    else {
        $inserted = ($block =~ s/(^[ \t]*PublicKey[ \t]*=.*\r?\n)/$1$line/mi);
    }
    return (undef, preshared_key_text('insert_failed')) if (!$inserted);
    return ($block, undef);
}

sub preshared_key_form_rows
{
    return '' if (!$access{'manage'});
    my $name = $in{'name'} || '';
    return '' if (!valid_interface_name($name));

    my $peer;
    if (defined($in{'peer'}) && $in{'peer'} ne '') {
        my ($cfg) = parse_wireguard_config(conf_path($name));
        $peer = get_peer_by_index($cfg, $in{'peer'}) if ($cfg);
    }
    my $present = $peer && length(get_section_value($peer, 'PresharedKey') || '');
    my $status = $present ? ($text{'key_saved'} || 'Saved') : ($text{'key_missing'} || 'Missing');
    my $blank_help = $text{'key_blank_keep'} || 'Leave blank to keep the existing key.';

    my $html = '';
    $html .= $WG_PSK_ORIGINAL_UI_TABLE_ROW->(
        'PresharedKey',
        html_escape($status).' <small>'.html_escape(preshared_key_text('not_shown')).'</small>'
    );
    $html .= $WG_PSK_ORIGINAL_UI_TABLE_ROW->(
        preshared_key_text('input'),
        '<input type="password" name="preshared_key" size="48" autocomplete="new-password">'.
        '<br><small>'.html_escape($blank_help).'</small>'
    );
    $html .= $WG_PSK_ORIGINAL_UI_TABLE_ROW->(
        preshared_key_text('generate'),
        ui_checkbox('generate_preshared_key', 1, preshared_key_text('generate'), 0)
    );
    if ($present) {
        $html .= $WG_PSK_ORIGINAL_UI_TABLE_ROW->(
            preshared_key_text('remove'),
            ui_checkbox('remove_preshared_key', 1, preshared_key_text('remove'), 0)
        );
    }
    return $html;
}

# edit_peer.cgi already owns the key table. Inject the PSK rows immediately
# after the public-key row without duplicating the large peer editor. A Webmin
# CGI is a separate process, so this scoped wrapper cannot leak into another
# request. Other module pages are unaffected by the exact script/label guard.
our $WG_PSK_ORIGINAL_UI_TABLE_ROW;
if (defined(&ui_table_row)) {
    $WG_PSK_ORIGINAL_UI_TABLE_ROW = \&ui_table_row;
    no warnings qw(redefine prototype);
    *ui_table_row = sub {
        my $html = $WG_PSK_ORIGINAL_UI_TABLE_ROW->(@_);
        my $label = defined($_[0]) ? $_[0] : '';
        if (($0 || '') =~ /(?:^|\/)edit_peer\.cgi$/ &&
            length($text{'peer_public_key'} || '') &&
            $label eq $text{'peer_public_key'}) {
            $html .= preshared_key_form_rows();
        }
        return $html;
    };
}

1;
