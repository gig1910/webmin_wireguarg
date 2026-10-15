#!/usr/local/bin/perl
require './wireguard-lib.pl'; ReadParse(); assert_view_access(); assert_manage_access();
my $name=$in{'name'}; error($text{'error_invalid_name'}) if (!valid_interface_name($name));
my $path=conf_path($name); error(text('error_interface',$name)) if (!-e $path);
if (($ENV{'REQUEST_METHOD'}||'') eq 'POST' && $in{'confirm'}) {
    assert_post_and_csrf();
    request_rate_limit('delete', 10, 300);
    my ($active,$err)=get_active_interfaces(); error($err) if ($err);
    if ($active->{$name}) { my ($ok,$out)=action_stop_interface($name); error('<pre>'.html_escape($out).'</pre>') if (!$ok); }
    lock_file($path); my $backup=backup_config($path); if (!$backup) { unlock_file($path); error($text{'error_backup'}); } my $ok=unlink($path); my $e=$!; unlock_file($path);
    error(text('error_delete',$path,$e)) if (!$ok);
    webmin_log('delete','interface',$name,{});
    ui_print_header(undef,$text{'delete_title'},'',undef,1,1); print ui_alert_box($text{'delete_done'},'success'); ui_print_footer('index.cgi',$text{'index_title'}); exit;
}
ui_print_header(undef,$text{'delete_title'},'',undef,1,1);
print ui_alert_box(text('delete_interface_confirm',html_escape($name)),'danger');
print ui_form_start('delete_interface.cgi','post'); print csrf_hidden(); print ui_hidden('name',$name); print ui_hidden('confirm',1); print ui_form_end([['delete',$text{'interface_delete'}]]);
ui_print_footer('edit_interface.cgi?name='.urlize($name),text('interface_title',$name));
