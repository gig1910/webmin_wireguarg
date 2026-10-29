#!/usr/local/bin/perl
require './wireguard-lib.pl'; ReadParse(); assert_view_access(); assert_manage_access();
my$name=$in{'name'}||''; my($cfg,$ifc); if(length$name){error($text{'error_invalid_name'})if!valid_interface_name($name);($cfg,my$e)=parse_wireguard_config(conf_path($name));error(text('error_read',conf_path($name),$e))if!$cfg;$ifc=$cfg->{'interface'};}else{$ifc={'values'=>{},'meta'=>{}};}
sub ta{
    my($n,$v,$r)=@_;
    my $validation=$n eq 'addresses' ?
        ' data-wg-validate="cidr-list" data-wg-invalid-message="'.
        html_escape($text{'ui_form_invalid'}).'"' : '';
    return '<textarea name="'.html_escape($n).'" rows="'.$r.'"'.$validation.
        ' style="width:100%">'.html_escape($v||'').'</textarea>';
}
sub visible_hooks { my($ifc,$key)=@_; return grep { !/wg-firewall-hook[.]pl/ } get_section_values($ifc,$key); }
ui_print_header(undef,length$name?text('interface_edit_title',$name):$text{'interface_add_title'},'',undef,1,1); print wg_ui_foundation(); print '<div class="wg-ui">'; print ui_form_start('save_interface.cgi','post'); print csrf_hidden(); print ui_hidden('old_name',$name)if length$name; print ui_hidden('config_digest',$cfg->{'digest'})if$cfg;
print ui_table_start($text{'interface_network_settings'},'width=100%',2); print ui_table_row($text{'interface_name'},length$name?'<b>'.html_escape($name).'</b>':ui_textbox('name','',20)); print ui_table_row($text{'interface_addresses'},ta('addresses',join("\n",get_section_values($ifc,'Address')),3)); print ui_table_row($text{'interface_listen_port'},wg_ui_number_input('listen_port',get_section_value($ifc,'ListenPort')||'',1,65535)); my $host_dns_field = ta('dns',join("\n",get_section_values($ifc,'DNS')),2).'<br><small>'.html_escape($text{'interface_dns_help'}).'</small>';
if (!length(wg_quick_resolvconf_command()) && scalar(get_section_values($ifc,'DNS'))) {
    $host_dns_field .= '<div class="alert alert-warning" style="margin-top:8px">'.html_escape($text{'interface_dns_dependency_missing'}).'</div>';
}
print ui_table_row($text{'interface_dns'},$host_dns_field); print ui_table_row($text{'interface_mtu'},wg_ui_number_input('mtu',get_section_value($ifc,'MTU')||'',1,65535)); print ui_table_row($text{'interface_table'},ui_textbox('table',get_section_value($ifc,'Table')||'',18)); print ui_table_row($text{'interface_fwmark'},ui_textbox('fwmark',get_section_value($ifc,'FwMark')||'',18)); print ui_table_row($text{'interface_saveconfig'},ui_select('saveconfig',get_section_value($ifc,'SaveConfig')||'',[['',$text{'none'}],['true',$text{'yes'}],['false',$text{'no'}]]).'<br><small>'.$text{'saveconfig_help'}.'</small>'); my $ufw_status = wg_firewall_status_warning();
my $fw_enabled = (get_meta_value($ifc,'webminfirewall') || '') eq 'ufw' ? 1 : 0;
my $fw_ui = ui_checkbox('firewall_ufw',1,$text{'interface_firewall_ufw_enabled'},$fw_enabled).
    '<br><small>'.html_escape($text{'interface_firewall_ufw_help'}).'</small>';
$fw_ui .= '<div class="alert alert-warning" style="margin-top:8px">'.
    html_escape($ufw_status).'</div>' if (length($ufw_status));
print ui_table_row($text{'interface_firewall_ufw'},$fw_ui);
print ui_table_end();
print wg_ui_panel_start($text{'interface_advanced_hooks'});
print ui_table_start($text{'interface_advanced_hooks'},'width=100%',2);
for my $h (qw(PreUp PostUp PreDown PostDown)) {
    print ui_table_row($h,ta(lc($h),join("\n",visible_hooks($ifc,$h)),3));
}
print ui_table_end();
print wg_ui_panel_end();
print ui_table_start($text{'key_settings'},'width=100%',2); print ui_table_row($text{'interface_private_key'},html_escape(length($ifc->{'private_key'}||'')?$text{'key_saved'}:$text{'key_missing'})); print ui_table_row($text{'interface_private_key_new'},ui_password('private_key','',48).'<br><small>'.$text{'key_blank_keep'}.'</small>'); print ui_table_row($text{'interface_generate_key'},ui_checkbox('generate_key',1,$text{'interface_generate_key_help'},0)); print ui_table_row($text{'interface_public_key_import'},ui_textbox('public_key',$ifc->{'public_key_comment'}||'',52).'<br><small>'.$text{'key_public_ignored'}.'</small>'); print ui_table_end();
print ui_table_start($text{'interface_qr_settings'},'width=100%',2); print ui_table_row($text{'interface_client_endpoint'},wg_ui_validated_input('clientendpoint',get_meta_value($ifc,'clientendpoint')||'',48,'endpoint',$text{'ui_form_endpoint'})); print ui_table_row($text{'interface_client_dns'},ui_textbox('clientdns',get_meta_value($ifc,'clientdns')||'',48).'<br><small>'.html_escape($text{'interface_client_dns_help'}).'</small>'); print ui_table_row($text{'interface_client_allowed'},wg_ui_validated_input('clientallowedips',get_meta_value($ifc,'clientallowedips')||'',60,'cidr-list',$text{'ui_form_invalid'}).'<br><small>'.$text{'interface_client_allowed_help'}.'</small>'); print ui_table_row($text{'interface_client_mtu'},wg_ui_number_input('clientmtu',get_meta_value($ifc,'clientmtu')||'',1,65535)); print ui_table_end();
print '<div class="wg-ui-button-row"><div class="wg-ui-action-group">'.
    wg_ui_button(type=>'submit',icon=>'save',tone=>'success',
        label=>$text{'save_only'},attrs=>{name=>'save',value=>1});
if (length($name)) {
    print wg_ui_button(type=>'submit',icon=>'check',tone=>'success',
        label=>$text{'save_apply_short'},attrs=>{name=>'save_apply',value=>1});
    print wg_ui_button(type=>'submit',icon=>'refresh',tone=>'warning',
        label=>$text{'save_restart_short'},
        attrs=>{name=>'save_restart',value=>1,
            'data-wg-confirm'=>$text{'confirm_restart'}});
}
else {
    print wg_ui_button(type=>'submit',icon=>'play',tone=>'success',
        label=>$text{'save_start'},attrs=>{name=>'save_start',value=>1});
}
print '</div></div></form></div>';
ui_print_footer(length$name?'edit_interface.cgi?name='.urlize($name):'index.cgi',length$name?text('interface_title',$name):$text{'index_title'});
