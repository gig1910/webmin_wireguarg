=head1 config-lib.pl

Internal module.

=cut

sub _trim
{
    my ($s) = @_;
    $s = '' if (!defined($s));
    $s =~ s/^\s+|\s+$//g;
    return $s;
}

sub _split_list
{
    my ($value) = @_;
    return () if (!defined($value));
    my @out;
    foreach my $part (split(/[\r\n,]+/, $value)) {
        $part = _trim($part);
        push(@out, $part) if (length($part));
    }
    return @out;
}

sub get_section_values
{
    my ($section, $wanted) = @_;
    return () if (!$section);
    return @{$section->{'values'}->{lc($wanted)} || []};
}

sub get_section_value
{
    my ($section, $wanted) = @_;
    my @values = get_section_values($section, $wanted);
    return @values ? $values[-1] : undef;
}

sub get_meta_value
{
    my ($section, $wanted) = @_;
    return undef if (!$section);
    return $section->{'meta'}->{lc($wanted)};
}

sub _parse_section_lines
{
    my ($kind, $lines, $start, $end, $disabled) = @_;
    my $section = {
        'kind' => $kind,
        'start' => $start,
        'end' => $end,
        'disabled' => $disabled ? 1 : 0,
        'raw_lines' => [ @$lines ],
        'values' => {},
        'entries' => [],
        'meta' => {},
        'private_key' => undef,
        'public_key_comment' => undef,
    };

    my $header_seen = 0;
    foreach my $line (@$lines) {
        my $work = $line;
        $work =~ s/\r?\n$//;
        if (!$header_seen && $work =~ /^\s*\[\s*(Interface|Peer)\s*\]\s*(?:#\s*(.*?))?\s*$/i) {
            $header_seen = 1;
            my $name = _trim($2 || '');
            $section->{'meta'}->{'name'} = $name if ($kind eq 'peer' && length($name));
            next;
        }
        if ($work =~ /^\s*#\s*(?:Webmin-Name|Name)\s*[:=]\s*(.*?)\s*$/i) {
            $section->{'meta'}->{'name'} = _trim($1);
            next;
        }
        if ($work =~ /^\s*#\s*(ClientEndpoint|ClientDNS|ClientAllowedIPs|ClientMTU|ClientAddress)\s*[:=]\s*(.*?)\s*$/i) {
            $section->{'meta'}->{lc($1)} = _trim($2);
            next;
        }
        if ($work =~ /^\s*#\s*PrivateKey\s*=\s*(.*?)\s*$/i) {
            $section->{'private_key'} = _trim($1);
            next;
        }
        if ($work =~ /^\s*#\s*PublicKey\s*=\s*(.*?)\s*$/i) {
            $section->{'public_key_comment'} = _trim($1);
            next;
        }
        if ($work =~ /^\s*([A-Za-z][A-Za-z0-9]*)\s*=\s*(.*?)\s*$/) {
            my ($key, $value) = ($1, _trim($2));
            push(@{$section->{'entries'}}, { 'key' => $key, 'value' => $value });
            push(@{$section->{'values'}->{lc($key)}}, $value);
            next;
        }
    }
    if ($kind eq 'interface') {
        my $pk = get_section_value($section, 'PrivateKey');
        $section->{'private_key'} = $pk if (defined($pk) && length($pk));
    }
    return $section;
}

sub parse_wireguard_config
{
    my ($path) = @_;

    # Configuration writes performed by this module are atomic (temporary file +
    # rename), so readers do not need Webmin's process-wide lock-file mechanism.
    # That mechanism can wait on stale locks and made ordinary view pages slow.
    # A non-blocking advisory flock is enough for external tools which honour it;
    # a concurrent atomic rename still leaves this descriptor on a complete file.
    sysopen(my $fh, $path, O_RDONLY) || return (undef, "$!");
    binmode($fh);
    flock($fh, LOCK_SH | LOCK_NB);
    local $/;
    my $contents = <$fh>;
    my $read_error = $!;
    close($fh);
    return (undef, $read_error || 'read failed') if (!defined($contents));

    my @lines = split(/(?<=\n)/, $contents, -1);
    pop(@lines) if (@lines && $lines[-1] eq '');
    my $cfg = {
        'path' => $path,
        'lines' => \@lines,
        'interface' => undef,
        'peers' => [],
        'digest' => sha256_hex($contents),
    };

    # First locate all real sections and disabled peer containers. This lets a
    # "# Name = ..." comment immediately before [Peer] belong to that peer
    # instead of being swallowed by the previous section.
    my @events;
    my $i = 0;
    while ($i < @lines) {
        my $plain = $lines[$i];
        $plain =~ s/\r?\n$//;
        if ($plain =~ /^\s*#\s*Webmin-Disabled-Peer-Begin\s*$/i) {
            my $start = $i;
            my @inner;
            $i++;
            while ($i < @lines) {
                my $p = $lines[$i];
                $p =~ s/\r?\n$//;
                last if ($p =~ /^\s*#\s*Webmin-Disabled-Peer-End\s*$/i);
                my $decoded = $lines[$i];
                $decoded =~ s/^(\s*)#/$1/;
                push(@inner, $decoded);
                $i++;
            }
            return (undef, 'Unclosed disabled peer block') if ($i >= @lines);
            push(@events, {
                'kind' => 'peer', 'header' => $start, 'start' => $start,
                'fixed_end' => $i, 'disabled' => 1, 'decoded' => \@inner,
            });
            $i++;
            next;
        }
        if ($plain =~ /^\s*\[\s*(Interface|Peer)\s*\]/i) {
            my $kind = lc($1);
            my $event_start = $i;
            if ($kind eq 'peer') {
                my $j = $i - 1;
                my $name_line = -1;
                while ($j >= 0) {
                    my $prev = $lines[$j];
                    $prev =~ s/\r?\n$//;
                    last if ($prev !~ /^\s*(?:#.*)?$/);
                    $name_line = $j if ($prev =~ /^\s*#\s*(?:Webmin-Name|Name)\s*[:=]/i);
                    $j--;
                }
                $event_start = $name_line if ($name_line >= 0);
            }
            push(@events, {
                'kind' => $kind, 'header' => $i, 'start' => $event_start,
                'disabled' => 0,
            });
        }
        $i++;
    }

    my $interface_events = scalar(grep { $_->{'kind'} eq 'interface' } @events);
    return (undef, $text{'error_multiple_interfaces'} || 'Multiple [Interface] sections are not supported') if ($interface_events > 1);
    @events = sort { $a->{'start'} <=> $b->{'start'} } @events;
    for (my $eidx = 0; $eidx < @events; $eidx++) {
        my $event = $events[$eidx];
        my $end;
        if (defined($event->{'fixed_end'})) {
            $end = $event->{'fixed_end'};
        }
        else {
            $end = $eidx + 1 < @events ? $events[$eidx + 1]->{'start'} - 1 : $#lines;
        }
        my $section;
        if ($event->{'disabled'}) {
            $section = _parse_section_lines('peer', $event->{'decoded'}, $event->{'start'}, $end, 1);
        }
        else {
            my @section_lines = @lines[$event->{'start'} .. $end];
            $section = _parse_section_lines($event->{'kind'}, \@section_lines, $event->{'start'}, $end, 0);
        }
        if ($event->{'kind'} eq 'interface' && !$cfg->{'interface'}) {
            $cfg->{'interface'} = $section;
        }
        elsif ($event->{'kind'} eq 'peer') {
            push(@{$cfg->{'peers'}}, $section);
        }
    }
    return ($cfg, undef);
}

sub list_configured_interfaces
{
    my $dir = conf_dir();
    return (undef, text('error_conf_dir', $dir)) if (!-d $dir || !-r $dir);
    opendir(my $dh, $dir) || return (undef, text('error_conf_dir', $dir));
    my @names;
    while (my $entry = readdir($dh)) {
        next if ($entry !~ /^([A-Za-z0-9_=+.-]{1,15})\.conf$/);
        my $name = $1;
        my $path = File::Spec->catfile($dir, $entry);
        push(@names, $name) if (-f $path && -r $path);
    }
    closedir($dh);
    my @items;
    foreach my $name (sort @names) {
        my $path = conf_path($name);
        my ($parsed, $err) = parse_wireguard_config($path);
        push(@items, { 'name' => $name, 'path' => $path, 'config' => $parsed, 'error' => $err });
    }
    return (\@items, undef);
}

sub validate_public_key
{
    my ($key) = @_;
    $key = _trim($key);
    return (0, $text{'error_public_key'}) if ($key !~ /^[A-Za-z0-9+\/]{43}=$/);
    my $decoded = eval { MIME::Base64::decode_base64($key) };
    return (0, $text{'error_public_key'}) if (!defined($decoded) || length($decoded) != 32);
    return (1, undef);
}

sub derive_public_key
{
    my ($private_key) = @_;
    $private_key = _trim($private_key);
    return (undef, $text{'error_private_key'}) if (!length($private_key));
    my $wg = command_path('wg_cmd', '/usr/bin/wg');
    return (undef, text('error_command', $wg)) if (!has_command($wg));
    my ($ok, $out, $err) = run_command_stdin([ $wg, 'pubkey' ], $private_key."\n");
    return (undef, $text{'error_private_key'}) if (!$ok);
    $out = _trim($out);
    my ($valid) = validate_public_key($out);
    return (undef, $text{'error_private_key'}) if (!$valid);
    return ($out, undef);
}

sub generate_private_key
{
    my $wg = command_path('wg_cmd', '/usr/bin/wg');
    return (undef, text('error_command', $wg)) if (!has_command($wg));
    my ($ok, $out) = run_command([ $wg, 'genkey' ], 1, 15, 2000);
    return (undef, $text{'error_generate_key'}) if (!$ok);
    $out = _trim($out);
    my ($pub, $err) = derive_public_key($out);
    return (undef, $err) if (!$pub);
    return ($out, undef);
}

sub _backup_dir
{
    return $config{'backup_dir'} || '/var/webmin/wireguard/backups';
}

sub backup_config
{
    my ($path) = @_;
    return undef if (!-f $path);
    my $dir = _backup_dir();
    eval { make_path($dir, { mode => 0700 }) if (!-d $dir); };
    return undef if ($@ || !-d $dir);
    my $stamp = strftime('%Y%m%d-%H%M%S', localtime());
    my $dest = File::Spec->catfile($dir, basename($path).'.'.$stamp.'.'.$$.'-'._secure_random_hex(4).'.bak');
    my $data = read_file_contents($path);
    return undef if (!defined($data));
    sysopen(my $fh, $dest, O_WRONLY|O_CREAT|O_EXCL, 0600) || return undef;
    binmode($fh);
    print {$fh} $data;
    close($fh);
    chmod(0600, $dest);
    my $keep = int($config{'backup_retention'} || 30);
    $keep = 1 if ($keep < 1); $keep = 1000 if ($keep > 1000);
    my $prefix = basename($path).'.';
    if (opendir(my $dh, $dir)) {
        my @backups = map { File::Spec->catfile($dir, $_) }
            grep { /^\Q$prefix\E.*\.bak$/ && -f File::Spec->catfile($dir, $_) } readdir($dh);
        closedir($dh);
        @backups = sort { (stat($b))[9] <=> (stat($a))[9] } @backups;
        if (@backups > $keep) { unlink($_) for @backups[$keep .. $#backups]; }
    }
    return $dest;
}

sub _fsync_handle
{
    my ($fh) = @_;
    return 1 if (!defined(fileno($fh)));
    my $ok = eval { require IO::Handle; $fh->sync(); 1 };
    return 1 if ($ok);
    $ok = eval { POSIX::fsync(fileno($fh)); 1 };
    return $ok ? 1 : 0;
}

sub _validate_config_candidate
{
    my ($path, $contents) = @_;
    my $max = int($config{'max_config_bytes'} || 4194304);
    return (0, text('error_config_too_large', $max)) if (length($contents || '') > $max);
    return (0, $text{'error_config_empty'} || 'Configuration is empty') if (!defined($contents) || $contents !~ /\S/);
    return (0, $text{'error_config_nul'} || 'Configuration contains NUL bytes') if (index($contents, "\0") >= 0);
    return (1, undef);
}

sub _write_exact_unlocked
{
    my ($path, $contents, $validate_config) = @_;
    if ($validate_config) {
        my ($valid, $validation_error) = _validate_config_candidate($path, $contents);
        return (0, $validation_error) if (!$valid);
        return (0, $text{'error_config_symlink'} || 'Refusing to replace a symbolic link') if (-l $path);
    }
    my $dir = dirname($path);
    my $tmp = File::Spec->catfile($dir, '.'.basename($path).'.webmin.'.$$.'-'._secure_random_hex(8).'.tmp');
    sysopen(my $fh, $tmp, O_WRONLY|O_CREAT|O_EXCL, 0600) || return (0, "$!");
    binmode($fh);
    if (!print {$fh} $contents) { my $e = "$!"; close($fh); unlink($tmp); return (0, $e); }
    if (!_fsync_handle($fh)) { my $e = 'fsync failed'; close($fh); unlink($tmp); return (0, $e); }
    if (!close($fh)) { my $e = "$!"; unlink($tmp); return (0, $e); }
    chmod(0600, $tmp) || do { my $e = "$!"; unlink($tmp); return (0, $e); };

    # Parse the exact bytes which are about to replace the live file.  This
    # catches malformed section boundaries and parser regressions before rename.
    if ($validate_config) {
        my ($parsed, $parse_error) = parse_wireguard_config($tmp);
        if (!$parsed || !$parsed->{'interface'}) {
            unlink($tmp);
            return (0, $parse_error || ($text{'error_config_parse_candidate'} || 'Generated configuration cannot be parsed'));
        }
    }

    rename($tmp, $path) || do { my $e = "$!"; unlink($tmp); return (0, $e); };
    chmod(0600, $path) || return (0, "$!");
    if (sysopen(my $dirfh, $dir, O_RDONLY)) { _fsync_handle($dirfh); close($dirfh); }
    return (1, undef);
}

sub atomic_write_config
{
    my ($path, $contents, $expected_digest) = @_;
    my $dir = dirname($path);
    return (0, text('error_conf_dir', $dir)) if (!-d $dir || !-w $dir);
    return (0, $text{'error_config_symlink'} || 'Refusing to edit a symbolic link') if (-l $path);
    lock_file($path);
    if (-f $path && length($expected_digest || '')) {
        my $current = read_file_contents($path);
        if (!defined($current) || sha256_hex($current) ne $expected_digest) {
            unlock_file($path);
            return (0, $text{'error_config_changed'});
        }
    }
    if (-f $path) {
        my $backup = backup_config($path);
        if (!$backup) {
            unlock_file($path);
            return (0, $text{'error_backup'});
        }
    }
    my ($ok, $err) = _write_exact_unlocked($path, $contents, 1);
    unlock_file($path);
    return ($ok, $err);
}

sub _unknown_lines
{
    my ($section, $known_keys, $known_meta) = @_;
    return () if (!$section);
    my %keys = map { lc($_) => 1 } @$known_keys;
    my %meta = map { lc($_) => 1 } @$known_meta;
    my @out;
    my $first = 1;
    foreach my $raw (@{$section->{'raw_lines'} || []}) {
        my $line = $raw;
        $line =~ s/\r?\n$//;
        if ($first && $line =~ /^\s*\[/) { $first = 0; next; }
        $first = 0;
        next if ($line =~ /^\s*([A-Za-z][A-Za-z0-9]*)\s*=/ && $keys{lc($1)});
        next if ($line =~ /^\s*#\s*(PrivateKey|PublicKey)\s*=/i);
        if ($line =~ /^\s*#\s*([A-Za-z][A-Za-z0-9]*)\s*[:=]/ && $meta{lc($1)}) { next; }
        next if ($line =~ /^\s*#\s*(?:Webmin-Name|Name)\s*[:=]/i);
        push(@out, $line) if ($line =~ /\S/);
    }
    return @out;
}

sub _append_values
{
    my ($lines, $key, $values) = @_;
    foreach my $value (@$values) {
        push(@$lines, sprintf('%-20s = %s', $key, $value));
    }
}

sub build_interface_block
{
    my ($data, $old) = @_;
    my @lines = ('[Interface]');
    _append_values(\@lines, 'Address', $data->{'addresses'} || []);
    push(@lines, sprintf('%-20s = %s', 'ListenPort', $data->{'listen_port'})) if (length($data->{'listen_port'} || ''));
    push(@lines, '');
    if (length($data->{'private_key'} || '')) {
        push(@lines, sprintf('%-20s = %s', 'PrivateKey', $data->{'private_key'}));
        push(@lines, sprintf('#%-19s = %s', 'PublicKey', $data->{'public_key'}));
    }
    elsif (length($data->{'public_key'} || '')) {
        push(@lines, sprintf('#%-19s = %s', 'PublicKey', $data->{'public_key'}));
    }
    _append_values(\@lines, 'DNS', $data->{'dns'} || []);
    foreach my $key (qw(MTU Table FwMark SaveConfig)) {
        my $lk = lc($key);
        push(@lines, sprintf('%-20s = %s', $key, $data->{$lk})) if (length($data->{$lk} || ''));
    }
    push(@lines, '') if (@{$data->{'preup'} || []} || @{$data->{'postup'} || []});
    _append_values(\@lines, 'PreUp', $data->{'preup'} || []);
    _append_values(\@lines, 'PostUp', $data->{'postup'} || []);
    push(@lines, '') if (@{$data->{'predown'} || []} || @{$data->{'postdown'} || []});
    _append_values(\@lines, 'PreDown', $data->{'predown'} || []);
    _append_values(\@lines, 'PostDown', $data->{'postdown'} || []);
    push(@lines, '') if (grep { length($data->{$_} || '') } qw(clientendpoint clientdns clientallowedips clientmtu));
    foreach my $pair (
        [ 'ClientEndpoint', 'clientendpoint' ], [ 'ClientDNS', 'clientdns' ],
        [ 'ClientAllowedIPs', 'clientallowedips' ], [ 'ClientMTU', 'clientmtu' ]) {
        push(@lines, '#'.$pair->[0].' = '.$data->{$pair->[1]}) if (length($data->{$pair->[1]} || ''));
    }
    my @unknown = _unknown_lines($old,
        [ qw(Address ListenPort PrivateKey DNS MTU Table FwMark SaveConfig PreUp PostUp PreDown PostDown) ],
        [ qw(ClientEndpoint ClientDNS ClientAllowedIPs ClientMTU) ]);
    if (@unknown) {
        push(@lines, '', '# Preserved custom settings', @unknown);
    }
    push(@lines, '');
    return join("\n", @lines)."\n";
}

sub build_peer_block
{
    my ($data, $old) = @_;
    my $name = $data->{'name'} || '';
    $name =~ s/[\r\n#]+/ /g;
    $name = _trim($name);
    my @lines = ('[Peer]'.(length($name) ? "\t\t#".$name : ''));
    push(@lines, sprintf('%-20s = %s', 'PublicKey', $data->{'public_key'}));
    push(@lines, sprintf('#%-19s = %s', 'PrivateKey', $data->{'private_key'})) if (length($data->{'private_key'} || ''));
    push(@lines, '#ClientAddress = '.$data->{'clientaddress'}) if (length($data->{'clientaddress'} || ''));
    foreach my $pair (
        [ 'ClientEndpoint', 'clientendpoint' ], [ 'ClientDNS', 'clientdns' ],
        [ 'ClientAllowedIPs', 'clientallowedips' ], [ 'ClientMTU', 'clientmtu' ]) {
        push(@lines, '#'.$pair->[0].' = '.$data->{$pair->[1]}) if (length($data->{$pair->[1]} || ''));
    }
    _append_values(\@lines, 'AllowedIPs', $data->{'allowed_ips'} || []);
    push(@lines, sprintf('%-20s = %s', 'Endpoint', $data->{'endpoint'})) if (length($data->{'endpoint'} || ''));
    push(@lines, sprintf('%-20s = %s', 'PersistentKeepalive', $data->{'keepalive'})) if (length($data->{'keepalive'} || ''));
    my @unknown = _unknown_lines($old,
        [ qw(PublicKey AllowedIPs Endpoint PersistentKeepalive) ],
        [ qw(ClientAddress ClientEndpoint ClientDNS ClientAllowedIPs ClientMTU) ]);
    push(@lines, @unknown) if (@unknown);
    push(@lines, '');
    my $plain = join("\n", @lines)."\n";
    if ($data->{'disabled'}) {
        my @encoded = split(/(?<=\n)/, $plain, -1);
        pop(@encoded) if (@encoded && $encoded[-1] eq '');
        @encoded = map { my $x = $_; $x =~ s/^/#/; $x } @encoded;
        return "# Webmin-Disabled-Peer-Begin\n".join('', @encoded)."# Webmin-Disabled-Peer-End\n\n";
    }
    return $plain;
}

sub replace_section
{
    my ($cfg, $section, $replacement) = @_;
    my @lines = @{$cfg->{'lines'}};
    my @new = split(/(?<=\n)/, $replacement, -1);
    pop(@new) if (@new && $new[-1] eq '');
    splice(@lines, $section->{'start'}, $section->{'end'} - $section->{'start'} + 1, @new);
    return join('', @lines);
}

sub append_peer
{
    my ($cfg, $block) = @_;
    my $contents = join('', @{$cfg->{'lines'}});
    $contents .= "\n" if (length($contents) && $contents !~ /\n\z/);
    $contents .= "\n" if ($contents !~ /\n\n\z/);
    return $contents.$block;
}

sub delete_section
{
    my ($cfg, $section) = @_;
    my @lines = @{$cfg->{'lines'}};
    splice(@lines, $section->{'start'}, $section->{'end'} - $section->{'start'} + 1);
    return join('', @lines);
}

sub get_peer_by_index
{
    my ($cfg, $index) = @_;
    return undef if (!defined($index) || $index !~ /^\d+$/);
    return $cfg->{'peers'}->[$index];
}

sub peer_display_name
{
    my ($peer, $index) = @_;
    return $peer->{'meta'}->{'name'} if ($peer && length($peer->{'meta'}->{'name'} || ''));
    my $pub = get_section_value($peer, 'PublicKey') || '';
    return substr($pub, 0, 12).'…' if ($pub);
    return 'Peer '.($index + 1);
}


1;
