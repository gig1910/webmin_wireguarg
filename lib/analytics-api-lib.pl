=head1 analytics-api-lib.pl

Webmin request adapter for the isolated Python standard-library SQLite backend.

=cut

sub analytics_db_path
{
    return File::Spec->catfile(stats_dir(), 'analytics.sqlite3');
}

sub analytics_backend
{
    my ($action, $request) = @_;
    return (undef, 'Invalid analytics command')
        if ($action !~ /^(?:query|peer_ip|network_record|network_lookup|network_manage|maintain|health)$/);
    my $python = '/usr/bin/python3';
    my $backend = File::Spec->catfile('.', 'analytics-store.py');
    return (undef, 'Python3 or analytics backend unavailable')
        if (!-x $python || !-r $backend);
    my ($ok, $out, $stderr) = run_command_stdin(
        [ $python, $backend, $action, analytics_db_path() ],
        JSON::PP::encode_json($request || {})
    );
    my $reply = eval { JSON::PP::decode_json($out || '') };
    return (undef, $stderr || $out || 'analytics backend failed')
        if (!$ok || !$reply || !$reply->{'ok'});
    return ($reply, undef);
}

1;
