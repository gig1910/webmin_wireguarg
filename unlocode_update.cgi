#!/usr/local/bin/perl
require './wireguard-lib.pl';
ReadParse();
assert_manage_access();
assert_post_and_csrf();
request_rate_limit('unlocode_update',3,600);
my $ctl=command_path('systemctl_cmd','/usr/bin/systemctl');
my ($ok,$out)=run_command(
    [$ctl,'start','--no-block','webmin-wireguard-unlocode.service'],0,10,1024);
ui_print_header(undef,$text{'unlocode_update_title'},'',undef,1,1);
print wg_ui_foundation();
print '<div class="wg-ui"><div class="'.($ok?'alert alert-success':'alert alert-warning').'">'.
    html_escape($ok ? $text{'unlocode_update_queued'} :
        ($out||$text{'unlocode_update_failed'})).'</div>';
print wg_ui_button(href=>'network_icons.cgi',icon=>'external',action=>'navigate',
    label=>$text{'back'});
print '</div>';
ui_print_footer();
