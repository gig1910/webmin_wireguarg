# Authenticated network directory mutation handler. Read-only navigation is
# intentionally allowed without an edit action, even when Theme sends POST.
sub wg_network_icons_dispatch {
my $notice='';
# Authentic Theme navigation can arrive as a POST without an edit action.
# Rendering the directory is read-only, regardless of the navigation method.
# An explicit action, however, always requires POST + a valid CSRF token.
my $action=$in{'action'} || '';
if (length($action)) {
    assert_post_and_csrf();
    request_rate_limit('network_icons',12,60);
    if ($action !~ /^(?:set_icon|delete_icon|clear_cache)$/) {
        if (($in{'_wg_ajax'}||'') eq '1') { die $text{'network_icons_invalid'}; }
        error($text{'network_icons_invalid'});
    }
    my $payload={
        action=>$action,
        cidr=>$in{'cidr'} || '',
        icon=>$in{'icon'} || '?',
        label=>$in{'label'} || '',
        city=>$in{'city'} || '',
        city_code=>uc($in{'city_code'} || ''),
        confirm=>$in{'confirm'} || '',
    };
    # Webmin ReadParse can yield UTF-8 octets. Convert only byte values, once,
    # before JSON::PP encodes the request for the Python SQLite backend.
    for my $field (qw(icon label city city_code)) {
        my $value = $payload->{$field};
        next if !defined($value) || utf8::is_utf8($value) || $value !~ /[\x80-\xFF]/;
        $payload->{$field} = eval { Encode::decode('UTF-8', $value, Encode::FB_CROAK()) };
        if ($@) {
            if (($in{'_wg_ajax'}||'') eq '1') { die $text{'network_icons_invalid'}; }
            error($text{'network_icons_invalid'});
        }
    }
    my ($result,$err)=analytics_backend('network_manage',$payload);
    if (!$result || !$result->{'ok'}) {
        my $message=$err || ($result && $result->{'error'}) || $text{'network_icons_invalid'};
        if (($in{'_wg_ajax'}||'') eq '1') { die $message; }
        error($message);
    }
    $notice=$text{'network_icons_saved'};
}
    return $notice;
}
1;
