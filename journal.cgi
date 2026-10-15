#!/usr/local/bin/perl
require './wireguard-lib.pl'; ReadParse(); assert_view_access(); assert_logs_access();
my $name=$in{'name'}||''; error($text{'error_invalid_name'}) if length($name)&&!valid_interface_name($name);
my $lines=int($in{'lines'}||$config{'journal_lines'}||200); $lines=20 if $lines<20; $lines=2000 if $lines>2000;
my $j=command_path('journalctl_cmd','/usr/bin/journalctl'); require_command($j);
my (@service_args,$service_label);
if (length $name) { @service_args=($j,'--no-pager','-n',$lines,'-o','short-iso','-u','wg-quick@'.$name.'.service'); }
else {
 my ($items)=list_configured_interfaces();
 @service_args=($j,'--no-pager','-n',$lines,'-o','short-iso');
 for my $it (@{$items||[]}) { push @service_args, '_SYSTEMD_UNIT=wg-quick@'.$it->{'name'}.'.service'; }
 # With no configured units, use a textual filter instead of an invalid wildcard unit.
 push @service_args, ('-g','wg-quick') if @service_args==5;
}
my ($uok,$uout)=run_command(\@service_args,1,30,200000);
my $kp=length($name)?quotemeta($name):'wireguard|wg[0-9A-Za-z_.-]+';
my ($kok,$kout)=run_command([$j,'--no-pager','-n',$lines,'-o','short-iso','-k','-g',$kp],1,30,200000);
for ($uout,$kout) { $_='' if defined($_)&&$_=~/^-- No entries --\s*$/m; }
ui_print_header(undef,length($name)?text('journal_interface_title',$name):$text{'journal_title'},'',undef,1,1);
print ui_form_start('journal.cgi','get'); print ui_hidden('name',$name) if length$name; print ui_table_start($text{'journal_options'},'width=100%',2); print ui_table_row($text{'journal_lines'},ui_textbox('lines',$lines,8)); print ui_table_end(); print ui_form_end([['show',$text{'journal_refresh'}]]);
my @errs; push @errs,$uout if !$uok && length($uout); push @errs,$kout if !$kok && length($kout);
print ui_alert_box($text{'journal_failed'}.'<br><pre>'.html_escape(join("\n",@errs)).'</pre>','warn') if @errs;
print '<h3>'.html_escape($text{'journal_services'}).'</h3><pre style="white-space:pre-wrap">'.html_escape($uout||$text{'journal_empty'}).'</pre>';
print '<h3>'.html_escape($text{'journal_kernel'}).'</h3><pre style="white-space:pre-wrap">'.html_escape($kout||$text{'journal_empty'}).'</pre>';
ui_print_footer(length($name)?'edit_interface.cgi?name='.urlize($name):'index.cgi',length($name)?text('interface_title',$name):$text{'index_title'});
