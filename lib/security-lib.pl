=head1 security-lib.pl

ACL, request integrity, CSRF and operation throttling.

=cut

sub assert_view_access { error($text{'error_view'}) if (!$access{'view'}); }
sub assert_manage_access { error($text{'action_denied'}) if (!$access{'manage'}); }
sub assert_export_access { error($text{'error_export'}) if (!$access{'export_clients'}); }
sub assert_diagnostics_access { error($text{'error_diagnostics'}) if (!$access{'diagnostics'}); }
sub assert_logs_access { error($text{'error_logs'}) if (!$access{'logs'}); }
sub assert_install_dependencies_access { error($text{'error_install_dependencies'}) if (!$access{'install_dependencies'}); }

sub _secure_random_hex
{
    my ($bytes) = @_;
    $bytes ||= 32;
    my $raw = '';
    if (sysopen(my $fh, '/dev/urandom', O_RDONLY)) {
        my $got = sysread($fh, $raw, $bytes);
        close($fh);
        return unpack('H*', $raw) if (defined($got) && $got == $bytes);
    }
    return sha256_hex(join('|', $$, time(), rand(), {}, $ENV{'REMOTE_ADDR'} || ''));
}

sub _state_dir { return $config{'state_dir'} || '/var/webmin/wireguard'; }
sub _csrf_dir { return File::Spec->catdir(_state_dir(), 'csrf'); }
sub _request_identity
{
    my $cookie = $ENV{'HTTP_COOKIE'} || '';
    my ($sid) = $cookie =~ /(?:^|;\s*)(?:sid|session)=([^;]+)/i;
    $sid ||= $ENV{'WEBMIN_SESSION_ID'} || '';
    my $user = $ENV{'REMOTE_USER'} || $remote_user || 'unknown';
    my $addr = $ENV{'REMOTE_ADDR'} || '';
    return sha256_hex(join('|', $user, $sid, $addr));
}

sub csrf_token
{
    my $dir = _csrf_dir();
    eval { make_path($dir, { mode => 0700 }) if (!-d $dir); };
    chmod(0700, $dir) if (-d $dir);
    my $path = File::Spec->catfile($dir, _request_identity().'.token');
    my $token;
    if (sysopen(my $fh, $path, O_RDONLY)) {
        local $/; $token = <$fh>; close($fh);
        $token =~ s/\s+//g if defined($token);
    }
    if (!defined($token) || $token !~ /^[a-f0-9]{64}$/) {
        $token = _secure_random_hex(32);
        my $tmp = $path.'.tmp.'.$$;
        if (sysopen(my $fh, $tmp, O_WRONLY|O_CREAT|O_EXCL, 0600)) {
            print {$fh} $token; close($fh); chmod(0600, $tmp); rename($tmp, $path);
        }
    }
    return $token;
}

sub csrf_hidden { return ui_hidden('_wg_csrf', csrf_token()); }

sub _same_origin_request
{
    my $origin = $ENV{'HTTP_ORIGIN'} || '';
    my $referer = $ENV{'HTTP_REFERER'} || '';
    return 1 if (!$origin && !$referer); # non-browser clients still need token
    my $host = lc($ENV{'HTTP_HOST'} || '');
    return 0 if (!$host);
    foreach my $value (grep { length($_) } ($origin, $referer)) {
        return 0 if ($value !~ m{^https?://([^/]+)}i);
        return 0 if (lc($1) ne $host);
    }
    return 1;
}

sub assert_post_and_csrf
{
    error($text{'action_post'}) if (($ENV{'REQUEST_METHOD'} || '') ne 'POST');
    error($text{'error_csrf'} || 'Request integrity check failed') if (!_same_origin_request());
    my $provided = $in{'_wg_csrf'} || $ENV{'HTTP_X_WG_CSRF'} || '';
    my $expected = csrf_token();
    my $diff = length($provided) ^ length($expected);
    my $length = length($provided) > length($expected) ? length($provided) : length($expected);
    for (my $i=0; $i<$length; $i++) {
        $diff |= ord(substr($provided,$i,1) || "\0") ^ ord(substr($expected,$i,1) || "\0");
    }
    error($text{'error_csrf'} || 'Request integrity check failed') if ($diff != 0);
}

sub request_rate_limit
{
    my ($bucket, $limit, $window) = @_;
    $bucket =~ s/[^A-Za-z0-9_.-]+/_/g;
    $limit ||= 30; $window ||= 60;
    my $dir = File::Spec->catdir(_state_dir(), 'ratelimit');
    eval { make_path($dir, { mode => 0700 }) if (!-d $dir); };
    my $path = File::Spec->catfile($dir, sha256_hex(_request_identity().'|'.$bucket).'.json');
    sysopen(my $fh, $path, O_RDWR|O_CREAT, 0600) || error('Cannot access request limiter');
    flock($fh, LOCK_EX);
    local $/; my $raw = <$fh> || '';
    my $data = eval { decode_json($raw) } || {};
    my $now = time();
    my @hits = grep { $_ > $now-$window } @{$data->{'hits'} || []};
    if (@hits >= $limit) { close($fh); error($text{'error_rate_limit'} || 'Too many requests'); }
    push(@hits, $now);
    seek($fh,0,SEEK_SET); truncate($fh,0); print {$fh} encode_json({hits=>\@hits}); close($fh);
    chmod(0600,$path);
    return 1;
}

1;
