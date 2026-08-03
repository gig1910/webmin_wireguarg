#!/usr/local/bin/perl
require './wireguard-lib.pl'; ReadParse(); assert_view_access(); assert_manage_access();
assert_post_and_csrf();
request_rate_limit('manage', 60, 60);
my $name=$in{'name'}; error($text{'error_invalid_name'}) if (!valid_interface_name($name));
my ($active,$ae)=get_active_interfaces(); error($ae) if ($ae);
my ($operation,$label,@result);
if ($in{'start'}) { error(text('action_already_active',$name)) if ($active->{$name}); $operation='start';$label=$text{'action_start'};@result=action_start_interface($name); }
elsif ($in{'stop'}) { error(text('action_not_active',$name)) if (!$active->{$name}); $operation='stop';$label=$text{'action_stop'};@result=action_stop_interface($name); }
elsif ($in{'apply'}) { error(text('action_not_active',$name)) if (!$active->{$name}); $operation='apply';$label=$text{'action_apply'};@result=action_apply_interface($name); }
elsif ($in{'restart'}) { error(text('action_not_active',$name)) if (!$active->{$name}); $operation='restart';$label=$text{'action_restart'};@result=action_restart_interface($name); }
else { error($text{'action_invalid'}); }
my ($ok,$output,$status,$command)=@result;
webmin_log($operation,'interface',$name,{status=>$status});
ui_print_header(undef,$text{'action_title'},'',undef,1,1);
print ui_alert_box($ok?$text{'action_done'}:$text{'action_failed'},$ok?'success':'danger');
print '<pre>'.html_escape($output||'').'</pre>';
ui_print_footer('edit_interface.cgi?name='.urlize($name),text('interface_title',$name));
