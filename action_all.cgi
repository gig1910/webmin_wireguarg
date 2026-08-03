#!/usr/local/bin/perl
require './wireguard-lib.pl'; ReadParse(); assert_view_access(); assert_manage_access();
assert_post_and_csrf();
request_rate_limit('manage', 60, 60);
error($text{'action_invalid'}) if (!$in{'restart_all'});
my ($active,$err)=get_active_interfaces(); error($err) if ($err);
ui_print_header(undef,$text{'action_restart_all'},'',undef,1,1);
foreach my $name (sort keys %$active) { my ($ok,$out)=action_restart_interface($name); print ui_alert_box(html_escape($name).': '.($ok?$text{'action_done'}:$text{'action_failed'}),$ok?'success':'danger'); print '<pre>'.html_escape($out||'').'</pre>' if (length($out||'')); webmin_log('restart','interface',$name,{}); }
ui_print_footer('index.cgi',$text{'index_title'});
