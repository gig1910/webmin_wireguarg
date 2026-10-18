=head1 preshared-key-lib.pl

PresharedKey validation, generation, configuration rewrite and peer-form UI.

The actual key is never rendered into HTML. An existing value is represented by
a concise installed status and an explicit remove button. Input and generation
controls are shown only while the peer has no PresharedKey.

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
        remove => 'Remove PresharedKey',
        configured => 'Installed',
        input_help => 'Paste a WireGuard PresharedKey in Base64 format, or generate a new one.',
        remove_confirm => 'Remove PresharedKey from this peer? Other edited fields in this form will also be saved.',
        conflict => 'Choose only one PresharedKey action: enter a key, generate one, or remove the stored key.',
        invalid => 'PresharedKey has an invalid WireGuard key format.',
        generate_failed => 'Failed to generate a WireGuard PresharedKey.',
        insert_failed => 'Failed to place PresharedKey into the peer configuration.',
    );
    my %ru = (
        input => 'Новый или переносимый PresharedKey',
        generate => 'Сгенерировать новый PresharedKey',
        remove => 'Удалить PresharedKey',
        configured => 'Установлен',
        input_help => 'Вставьте PresharedKey WireGuard в формате Base64 или сгенерируйте новый.',
        remove_confirm => 'Удалить PresharedKey этого пира? Остальные изменённые поля формы также будут сохранены.',
        conflict => 'Выберите только одно действие с PresharedKey: ввод ключа, генерацию или удаление сохранённого ключа.',
        invalid => 'PresharedKey имеет неверный формат ключа WireGuard.',
        generate_failed => 'Не удалось сгенерировать PresharedKey WireGuard.',
        insert_failed => 'Не удалось добавить PresharedKey в конфигурацию пира.',
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

# Explicitly called by save_peer.cgi. Never infer write semantics from $0:
# under MiniServ the executable name is not guaranteed to be save_peer.cgi.
sub build_peer_block_with_preshared_key
{
    my ($data, $old_peer, $input, $generate, $remove) = @_;
    my ($preshared_key, $error) = resolve_submitted_preshared_key(
        $old_peer, $input, $generate, $remove
    );
    return (undef, $error) if !defined($preshared_key);

    my $block = build_peer_block($data, $old_peer);
    return rewrite_peer_block_preshared_key(
        $block, $preshared_key, $data->{'disabled'}
    );
}

sub preshared_key_form_rows_for_state
{
    my ($present) = @_;
    my $html = '';

    if ($present) {
        my $label=preshared_key_text('configured');
        my $notice='<span class="label label-success">'.
            html_escape($label).'</span>';
        my $remove='<button type="submit" class="wg-ui-icon-btn wg-ui-icon-danger"'.
            ' name="remove_preshared_key" value="1"'.
            ' title="'.html_escape(preshared_key_text('remove')).'"'.
            ' aria-label="'.html_escape(preshared_key_text('remove')).'"'.
            ' data-wg-confirm="'.html_escape(preshared_key_text('remove_confirm')).'">'.
            wg_ui_icon('trash').'</button>';
        return ui_table_row('PresharedKey',
            '<span class="wg-ui-copy">'.$notice.$remove.'</span>');
    }

    $html .= ui_table_row(
        preshared_key_text('input'),
        '<input type="password" name="preshared_key" size="48" autocomplete="new-password">'.
        '<br><small>'.html_escape(preshared_key_text('input_help')).'</small>'
    );
    $html .= ui_table_row(
        preshared_key_text('generate'),
        ui_checkbox('generate_preshared_key', 1, preshared_key_text('generate'), 0)
    );
    return $html;
}


1;
