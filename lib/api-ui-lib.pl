=head1 api-ui-lib.pl

Internal module.

=cut

sub _json_normalize_utf8
{
    my ($value) = @_;
    return $value if (!defined($value));
    return $value if (blessed($value));
    if (ref($value) eq 'HASH') {
        my %copy;
        foreach my $key (keys(%$value)) {
            my $new_key = _json_normalize_utf8($key);
            $copy{$new_key} = _json_normalize_utf8($value->{$key});
        }
        return \%copy;
    }
    if (ref($value) eq 'ARRAY') {
        return [ map { _json_normalize_utf8($_) } @$value ];
    }
    return $value if (ref($value));
    return $value if (utf8::is_utf8($value) || $value !~ /[\x80-\xFF]/);
    my $decoded = eval { decode('UTF-8', $value, FB_CROAK) };
    return $@ ? $value : $decoded;
}

sub json_encode_utf8
{
    my ($data) = @_;

    # Do not call an unqualified encode_json(). WebminCore exports a function
    # with the same name and, on some Webmin versions, it stringifies
    # JSON::PP boolean objects as "JSON::PP::true/false". A private encoder
    # preserves booleans as native JSON true/false and returns UTF-8 bytes.
    return JSON::PP->new
        ->utf8(1)
        ->allow_nonref(1)
        ->encode(_json_normalize_utf8($data));
}

sub json_response
{
    my ($data, $status) = @_;

    my $encoded = eval { json_encode_utf8($data) };
    if (!defined($encoded) || $@) {
        my $fallback = {
            ok => JSON::PP::false(),
            error => 'JSON serialization failed',
        };
        $encoded = JSON::PP->new->utf8(1)->ascii(1)->allow_nonref(1)->encode($fallback);
    }

    # Authentic Theme may replace non-2xx CGI responses with an HTML error page.
    # API clients need a guaranteed JSON body, so application errors are carried
    # in { ok:false, error:... } while the transport response remains HTTP 200.
    print "Content-Type: application/json; charset=utf-8\r\n";
    print "Cache-Control: no-store, no-cache, must-revalidate\r\n";
    print "Pragma: no-cache\r\n";
    print "X-Content-Type-Options: nosniff\r\n";
    print "X-WireGuard-Webmin-API: 0.2.0\r\n";
    print "Content-Length: ".length($encoded)."\r\n\r\n";
    print $encoded;
}

sub nice_size_plain
{
    my ($bytes) = @_; $bytes = 0 if !defined($bytes) || $bytes !~ /^\d+(?:\.\d+)?$/;
    my @u = ('B','KiB','MiB','GiB','TiB'); my $i=0;
    while ($bytes >= 1024 && $i < $#u) { $bytes/=1024; $i++; }
    my $v = $i==0 ? sprintf('%.0f',$bytes) : $bytes>=100 ? sprintf('%.0f',$bytes) : $bytes>=10 ? sprintf('%.1f',$bytes) : sprintf('%.2f',$bytes);
    return "$v $u[$i]";
}

sub shorten_text
{
    my ($value,$limit)=@_; $value='' if !defined$value; $limit||=60;
    return $value if length($value)<=$limit;
    return substr($value,0,$limit-3).'...';
}

# Escape text embedded in a single-quoted JavaScript string inside a
# double-quoted HTML attribute. This is intended for short UI messages.
sub js_escape
{
    my ($value) = @_;
    $value = '' if !defined($value);

    # JavaScript string literal escaping.
    $value =~ s/\\/\\\\/g;
    $value =~ s/'/\\'/g;
    $value =~ s/\r/\\r/g;
    $value =~ s/\n/\\n/g;
    $value =~ s/\x{2028}/\\u2028/g;
    $value =~ s/\x{2029}/\\u2029/g;

    # HTML attribute escaping. Do this after JavaScript escaping so the
    # browser decodes entities back to the intended JavaScript source.
    $value =~ s/&/&amp;/g;
    $value =~ s/"/&quot;/g;
    $value =~ s/</&lt;/g;
    $value =~ s/>/&gt;/g;
    return $value;
}

sub diagnostic_jobs_dir
{
    return $ENV{'WIREGUARD_DIAGNOSTIC_DIR'} if (defined($ENV{'WIREGUARD_DIAGNOSTIC_DIR'}) && length($ENV{'WIREGUARD_DIAGNOSTIC_DIR'}));
    return $config{'diagnostic_dir'} || '/var/webmin/wireguard/diagnostics';
}

sub valid_diagnostic_job_id
{
    my ($job_id) = @_;
    return defined($job_id) && $job_id =~ /^[a-f0-9]{64}$/;
}

sub diagnostic_job_dir
{
    my ($job_id) = @_;
    return undef if (!valid_diagnostic_job_id($job_id));
    return File::Spec->catdir(diagnostic_jobs_dir(), $job_id);
}

sub diagnostic_write_json
{
    my ($path, $data) = @_;
    my $encoded = eval { JSON::PP->new->utf8(1)->canonical(1)->encode(_json_normalize_utf8($data)) };
    return (0, $@ || 'JSON encoding failed') if (!defined($encoded) || $@);
    my $tmp = $path.'.'.$$.'.'.int(rand(1000000)).'.tmp';
    sysopen(my $fh, $tmp, O_WRONLY|O_CREAT|O_EXCL, 0600) || return (0, "$!");
    binmode($fh);
    if (!print {$fh} $encoded) { my $error = "$!"; close($fh); unlink($tmp); return (0, $error); }
    if (!close($fh)) { my $error = "$!"; unlink($tmp); return (0, $error); }
    rename($tmp, $path) || do { my $error = "$!"; unlink($tmp); return (0, $error); };
    chmod(0600, $path);
    return (1, undef);
}

sub diagnostic_read_json
{
    my ($path) = @_;
    return undef if (!defined($path) || !-r $path);
    sysopen(my $fh, $path, O_RDONLY) || return undef;
    binmode($fh);
    local $/;
    my $raw = <$fh>;
    close($fh);
    return undef if (!defined($raw) || !length($raw));
    my $data = eval { JSON::PP::decode_json($raw) };
    return ($@ || ref($data) ne 'HASH') ? undef : $data;
}

sub cleanup_diagnostic_jobs
{
    my $base = diagnostic_jobs_dir();
    return if (!-d $base);
    my $retention = int($config{'diagnostic_retention'} || 3600);
    $retention = 300 if ($retention < 300);
    opendir(my $dh, $base) || return;
    my @jobs = grep { valid_diagnostic_job_id($_) && -d File::Spec->catdir($base, $_) } readdir($dh);
    closedir($dh);
    my $now = time();
    foreach my $job_id (@jobs) {
        my $dir = File::Spec->catdir($base, $job_id);
        my $status = diagnostic_read_json(File::Spec->catfile($dir, 'status.json')) || {};
        my $state = $status->{'state'} || '';
        next if ($state eq 'running' || $state eq 'starting');
        my @stat = stat($dir);
        my $updated = $status->{'updated'} || (@stat ? $stat[9] : $now);
        File::Path::remove_tree($dir) if ($now - $updated > $retention);
    }
}

sub module_script_url
{
    my ($script, %params) = @_;
    $script = '' if (!defined($script));
    $script =~ s{^/+}{};

    # init_config() exposes the actual module directory in $module_name.
    # Do not call get_module_name() from this helper: under theme wrappers its
    # caller-sensitive lookup may resolve to the theme instead of this module.
    my $prefix = defined(&get_webprefix) ? (get_webprefix() || '') : '';
    $prefix =~ s{/+$}{};
    my $module = $module_name || 'wireguard';
    $module =~ s{^/+|/+$}{}g;

    # Version every API URL. Authentic Theme keeps module DOM fragments alive
    # across navigation, so an unversioned endpoint can leave old pollers active.
    $params{'_wg_api'} = '0.2.0' if (!exists($params{'_wg_api'}));

    my $url = $prefix.'/'.$module.'/'.$script;
    if (%params) {
        my @query;
        foreach my $key (sort keys(%params)) {
            next if (!defined($params{$key}));
            push(@query, urlize($key).'='.urlize($params{$key}));
        }
        $url .= '?'.join('&', @query) if (@query);
    }
    return $url;
}

sub direct_link_button
{
    my ($script, $label, $params, %opts) = @_;
    $params ||= {};
    my $url = ref($params) eq 'HASH'
        ? module_script_url($script, %$params)
        : $script;
    my $class = 'btn btn-default wg-direct-link';
    $class .= ' '.$opts{'class'} if (defined($opts{'class'}) && length($opts{'class'}));

    # View pages must be ordinary same-origin links. Authentic Theme then loads
    # them through its normal module navigation and keeps the Webmin shell,
    # sidebar and back stack. Forcing window.location.assign() here turns the
    # CGI into a standalone top-level document.
    if (!$opts{'download'}) {
        return '<a href="'.html_escape($url).'" class="'.html_escape($class).'"'.
            ' data-wg-module-navigation="1">'.html_escape($label).'</a>';
    }

    # A download is intentionally a raw response rather than a Webmin page.
    # Keep it out of SPA/clipboard handlers while allowing the browser to
    # process Content-Disposition: attachment normally.
    my $onclick = "if (typeof event !== 'undefined' && event) { event.stopImmediatePropagation(); } window.location.assign(this.href); return false;";
    return '<a href="'.html_escape($url).'" class="'.html_escape($class).'" download'.
        ' data-wg-direct-download="1" onclick="'.html_escape($onclick).'">'.html_escape($label).'</a>';
}

sub mini_action_form
{
    my ($name,$operation,$label,$kind,$confirm)=@_;
    my $class=$kind eq 'danger'?'btn-danger':$kind eq 'warning'?'btn-warning':$kind eq 'success'?'btn-success':'';
    my $ask=length($confirm||'')?' onsubmit="return confirm(\''.js_escape($confirm).'\')"':'';
    return '<form method="post" action="action_interface.cgi" style="display:inline-block;margin:2px"'.$ask.'>'.
      csrf_hidden().'<input type="hidden" name="name" value="'.html_escape($name).'">'.
      '<button type="submit" class="btn '.$class.'" name="'.html_escape($operation).'" value="1">'.html_escape($label).'</button></form>';
}


1;
