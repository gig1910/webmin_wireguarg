#!/usr/local/bin/perl
require './wireguard-lib.pl';
ReadParse();
assert_view_access();
assert_manage_access();

my $notice='';
if (($ENV{'REQUEST_METHOD'}||'GET') eq 'POST') {
    assert_post_and_csrf();
    request_rate_limit('network_icons',12,60);
    my $action=$in{'action'} || '';
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
my ($report,$err)=analytics_backend('network_manage',{action=>'list'});
error($err) unless $report;
ui_print_header(undef,$text{'network_icons_title'},'',undef,1,1);
print wg_build_banner();
print '<div class="alert alert-success">'.html_escape($notice).'</div>' if $notice;
print '<p>'.html_escape($text{'network_icons_help'}).'</p>';
print '<h3>'.html_escape($text{'network_icons_manual'}).'</h3>';
print ui_form_start(module_script_url('network_icons.cgi'),'post');
print csrf_hidden();
print ui_hidden('action','set_icon');
print '<div class="wg-network-form">'.
    '<label>'.html_escape($text{'network_icons_prefix'}).' <input name="cidr" required placeholder="203.0.113.0/24" maxlength="64"></label> '.
    '<label>'.html_escape($text{'network_icons_symbol'}).' <input name="icon" value="?" maxlength="8" size="5"></label> '.
    '<label>'.html_escape($text{'network_icons_label'}).' <input name="label" maxlength="100" size="30"></label> '.
    '<button type="submit" class="btn btn-primary">'.html_escape($text{'network_icons_save'}).'</button></div>';
print ui_form_end();
print '<table class="table table-striped table-hover"><thead><tr><th>'.
    html_escape($text{'network_icons_prefix'}).'</th><th>'.html_escape($text{'network_icons_symbol'}).
    '</th><th>'.html_escape($text{'network_icons_label'}).'</th><th>'.
    html_escape($text{'interface_peer_actions'}).'</th></tr></thead><tbody>';
for my $item (@{$report->{'icons'}||[]}) {
    print '<tr><td>'.html_escape($item->{'cidr'}).'</td>'.
        '<td>'.html_escape($item->{'icon'}).'</td>'.
        '<td>'.html_escape($item->{'label'}).'</td><td>';
    print ui_form_start(module_script_url('network_icons.cgi'),'post');
    print csrf_hidden();
    print ui_hidden('action','delete_icon');
    print ui_hidden('cidr',$item->{'cidr'});
    print '<button type="submit" class="btn btn-default">'.
        html_escape($text{'network_icons_delete'}).'</button>';
    print ui_form_end();
    print '</td></tr>';
}
print '</tbody></table>';
print '<h3>'.html_escape($text{'network_icons_cache'}).'</h3>';
print '<p>'.html_escape($text{'network_icons_cache_help'}).'</p>';
print '<table class="table table-striped table-hover"><thead><tr><th>'.
    html_escape($text{'network_icons_prefix'}).'</th><th>'.
    html_escape($text{'network_icons_owner'}).'</th><th>'.
    html_escape($text{'network_icons_country'}).'</th></tr></thead><tbody>';
for my $item (@{$report->{'cache'}||[]}) {
    print '<tr><td>'.html_escape($item->{'cidr'}).'</td><td>'.
        html_escape($item->{'owner'}).'</td><td>'.
        html_escape($item->{'country'}).'</td></tr>';
}
print '</tbody></table>';
print ui_form_start(module_script_url('network_icons.cgi'),'post');
print csrf_hidden();
print ui_hidden('action','clear_cache');
print '<label>'.html_escape($text{'network_icons_confirm'}).' <input name="confirm" maxlength="5" autocomplete="off"></label> ';
print '<button type="submit" class="btn btn-danger">'.html_escape($text{'network_icons_clear'}).'</button>';
print ui_form_end();
print '<style>.wg-network-form{display:flex;gap:10px;align-items:end;flex-wrap:wrap}'.
    '.wg-network-form label{display:inline-flex;flex-direction:column;gap:4px}</style>';
ui_print_footer('index.cgi',$text{'index_title'});
