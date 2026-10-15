#!/usr/local/bin/perl
require './wireguard-lib.pl';
ReadParse();
assert_view_access();
assert_manage_access();
assert_post_and_csrf();
request_rate_limit('manage', 12, 60);

my $action = $in{'action'} || '';
error($text{'analytics_error_action'})
    if ($action !~ /^(?:delete_before|delete_peer|purge|vacuum)$/);
my $confirm = $in{'confirm'} || '';
error($text{'analytics_error_confirm'})
    if ($action ne 'vacuum' && $confirm ne 'DELETE');
my $peer = $in{'peer_id'} || '';
error($text{'analytics_error_peer'})
    if ($action eq 'delete_peer' && $peer !~ /^[a-f0-9]{64}$/);
my $before = $in{'before'} || '';
error($text{'analytics_error_time'})
    if ($action eq 'delete_before' &&
        ($before !~ /^\d{1,12}$/ || $before <= 0 || $before > time()));
my ($result, $err) = analytics_backend('maintain', {
    action => $action, confirm => $confirm, peer_id => $peer, before => $before,
});
error(html_escape($err || $text{'analytics_maintenance_error'})) if (!$result);
webmin_log('maintenance','analytics',$action,{peer_id=>$peer, before=>$before});
ui_print_header(undef,$text{'analytics_maintenance'},'',undef,1,1);
print ui_alert_box(html_escape($text{'analytics_maintenance_done'}), 'success');
if ($result->{'backup'}) {
    print '<p>'.html_escape($text{'analytics_maintenance_help'}).'</p>';
}
ui_print_footer('analytics.cgi',$text{'analytics_title'});
