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
    error($text{'network_icons_invalid'}) if $action !~ /^(?:set_icon|delete_icon|clear_cache)$/;
    my $payload={
        action=>$action,
        cidr=>$in{'cidr'} || '',
        icon=>$in{'icon'} || '?',
        label=>$in{'label'} || '',
        confirm=>$in{'confirm'} || '',
    };
    # Webmin ReadParse can yield UTF-8 octets. Convert only byte values, once,
    # before JSON::PP encodes the request for the Python SQLite backend.
    for my $field (qw(icon label)) {
        my $value = $payload->{$field};
        next if !defined($value) || utf8::is_utf8($value) || $value !~ /[\x80-\xFF]/;
        $payload->{$field} = eval { Encode::decode('UTF-8', $value, Encode::FB_CROAK()) };
        error($text{'network_icons_invalid'}) if $@;
    }
    my ($result,$err)=analytics_backend('network_manage',$payload);
    error($err || $text{'network_icons_invalid'}) if !$result;
    $notice=$text{'network_icons_saved'};
}
    return $notice;
}
1;
