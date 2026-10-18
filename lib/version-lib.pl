=head1 version-lib.pl

Release and build identity. An installed .wbm.gz contains a unique build.info
written at package build time. Development checkouts have an 'unpackaged' marker.

=cut

our $WIREGUARD_WEBMIN_VERSION = '0.3.0';
our $WG_VERSION_ORIGINAL_RUNTIME_POLL_HTML;

sub wg_build_metadata
{
    my ($path) = @_;
    $path ||= './build.info';
    my %data = (
        build_version => 'unpackaged', git_commit => 'unknown',
        built_at_utc => 'unknown', source_dirty => 'unknown',
    );
    if (open(my $fh, '<', $path)) {
        while (my $line = <$fh>) {
            chomp($line);
            $line =~ s/\r$//;
            next if $line !~ /^(build_version|git_commit|built_at_utc|source_dirty)=([^\r\n]{0,128})$/;
            $data{$1} = $2;
        }
        close($fh);
    }
    my $base = $WIREGUARD_WEBMIN_VERSION;
    if ($data{'build_version'} !~ /^\Q$base\E\+[0-9]{14,23}\.g(?:[a-f0-9]{8,12}|nogit)(?:\.dirty)?$/) {
        $data{'build_version'} = 'unpackaged';
    }
    $data{'git_commit'} = 'unknown'
        if $data{'git_commit'} !~ /^(?:[a-f0-9]{40}|unknown)$/;
    $data{'built_at_utc'} = 'unknown'
        if $data{'built_at_utc'} !~ /^\d{4}-\d\d-\d\dT\d\d:\d\d:\d\dZ$/;
    $data{'source_dirty'} = 'unknown'
        if $data{'source_dirty'} !~ /^(?:0|1|unknown)$/;
    return \%data;
}

sub wg_build_version
{
    my $meta = wg_build_metadata();
    return $meta->{'build_version'} eq 'unpackaged'
        ? $WIREGUARD_WEBMIN_VERSION : $meta->{'build_version'};
}

sub wg_build_banner
{
    my $meta = wg_build_metadata();
    my $version = $meta->{'build_version'};
    my $label = $text{'wg_build_label'} || 'Installed build';
    my $details = $version eq 'unpackaged'
        ? ($text{'wg_build_unstamped'} || 'Source checkout; no installed build identity')
        : $version;
    if ($version ne 'unpackaged') {
        my $commit = $meta->{'git_commit'};
        if ($commit ne 'unknown') {
            $details .= ' · '.($text{'wg_build_commit'} || 'Commit').': '.substr($commit, 0, 12);
        }
        if ($meta->{'built_at_utc'} ne 'unknown') {
            $details .= ' · '.($text{'wg_build_date'} || 'Built').': '.$meta->{'built_at_utc'};
        }
        if ($meta->{'source_dirty'} eq '1') {
            $details .= ' · '.($text{'wg_build_dirty'} || 'Modified source');
        }
    }
    return '<div class="wg-build-identity text-muted" data-wg-build-version="'.
        html_escape($version).'" style="font-size:12px;margin:2px 0 12px 0;">'.
        html_escape($label).': '.html_escape($details).'</div>';
}

if (defined(&runtime_poll_html)) {
    $WG_VERSION_ORIGINAL_RUNTIME_POLL_HTML = \&runtime_poll_html;
    no warnings qw(redefine prototype);
    *runtime_poll_html = sub {
        my $html = $WG_VERSION_ORIGINAL_RUNTIME_POLL_HTML->(@_);
        my $build = wg_build_version();
        $html =~ s/const API_BUILD='[^']*'/const API_BUILD='$build'/;
        return $html;
    };
}

1;
