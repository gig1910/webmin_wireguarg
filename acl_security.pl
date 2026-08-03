require 'wireguard-lib.pl';
do '../ui-lib.pl';
sub acl_security_form
{
    my ($access) = @_;
    print ui_table_row($text{'acl_view'}, ui_yesno_radio('view', $access->{'view'}));
    print ui_table_row($text{'acl_manage'}, ui_yesno_radio('manage', $access->{'manage'}));
    print ui_table_row($text{'acl_export_clients'}, ui_yesno_radio('export_clients', $access->{'export_clients'}));
    print ui_table_row($text{'acl_diagnostics'}, ui_yesno_radio('diagnostics', $access->{'diagnostics'}));
    print ui_table_row($text{'acl_logs'}, ui_yesno_radio('logs', $access->{'logs'}));
    print ui_table_row($text{'acl_install_dependencies'}, ui_yesno_radio('install_dependencies', $access->{'install_dependencies'}));
}
sub acl_security_save
{
    my ($access, $in) = @_;
    foreach my $key (qw(view manage export_clients diagnostics logs install_dependencies)) { $access->{$key} = $in->{$key} ? 1 : 0; }
}
