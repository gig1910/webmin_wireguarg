#!/usr/local/bin/perl
require './wireguard-lib.pl';
use File::Basename qw(dirname);
use File::Path qw(make_path);
use File::Temp qw(tempfile);
ReadParse();
assert_manage_access();
my $status=wg_geoip_update_status();
my $conf=wg_geoip_update_conf_path();
my $notice='';
my $error_message='';
if (($ENV{'REQUEST_METHOD'}||'GET') eq 'POST' && ($in{'geoip_city_apply'}||'') eq '1') {
    assert_post_and_csrf();
    request_rate_limit('geoip_city_setup',3,600);
    my $account=$in{'account_id'}||'';
    my $key=$in{'license_key'}||'';
    if ((!length($account) && length($key)) || (length($account) && !length($key))) {
        $error_message=$text{'geoip_city_pair'};
    }
    elsif (length($account) && ($account !~ /^[0-9]{1,20}$/ ||
             $key !~ /^[A-Za-z0-9_-]{8,128}$/)) {
        $error_message=$text{'geoip_city_invalid'};
    }
    elsif (!$status->{'command_available'}) {
        $error_message=$text{'geoip_city_install_first'};
    }
    else {
        my $existing='';
        if (-f $conf) {
            if (-l $conf || !-r $conf) {
                $error_message=$text{'geoip_city_unsafe_conf'};
            }
            else {
                $existing=read_file_contents($conf);
                $error_message=$text{'geoip_city_unsafe_conf'} unless defined $existing;
            }
        }
        my $ready=wg_geoip_update_config_info($conf);
        if (!$error_message && !length($account) && !$ready->{'ready'}) {
            $error_message=$text{'geoip_city_credentials_required'};
        }
        if (!$error_message) {
            my $output=$existing;
            # Preserve unrelated vendor configuration options.
            my @editions;
            for my $line (split(/\r?\n/,$output)) {
                if ($line =~ /^\s*EditionIDs\s+(.+?)\s*$/) {
                    push @editions,grep { /^[A-Za-z0-9-]{1,64}$/ } split(/\s+/,$1);
                }
            }
            $output =~ s/^\s*EditionIDs\s+[^\r\n]*\r?\n//mg;
            if (length($account)) {
                $output =~ s/^\s*(?:AccountID|LicenseKey)\s+[^\r\n]*\r?\n//mg;
                $output.="\nAccountID $account\nLicenseKey $key\n";
            }
            my %seen;
            @editions=grep { !$seen{$_}++ } (@editions,'GeoLite2-City');
            $output.="\nEditionIDs ".join(' ',@editions)."\n";
            my $dir=dirname($conf);
            if ($conf !~ m{^/[A-Za-z0-9_/.-]+$} || !-d $dir || -l $dir) {
                $error_message=$text{'geoip_city_unsafe_conf'};
            }
            else {
                my ($fh,$temp)=tempfile('.geoip-config-XXXXXXXX',DIR=>$dir,UNLINK=>0);
                chmod(0600,$temp);
                my $written=print {$fh} $output;
                my $closed=close($fh);
                if (!$written || !$closed || !rename($temp,$conf)) {
                    unlink($temp);
                    $error_message=$text{'geoip_city_write_failed'};
                }
                else {
                    # The updater receives no credentials in argv or environment.
                    my $exe=command_path('geoipupdate_cmd','/usr/bin/geoipupdate');
                    my ($ok,$out)=run_command([$exe,'-f',$conf],0,90,4096);
                    if (!$ok) {
                        $error_message=$text{'geoip_city_download_failed'};
                    }
                    else {
                        $notice=$text{'geoip_city_success'};
                        my $ctl=command_path('systemctl_cmd','/usr/bin/systemctl');
                        run_command([$ctl,'enable','--now','geoipupdate.timer'],0,15,512)
                            if has_command($ctl);
                    }
                }
            }
        }
    }
    $status=wg_geoip_update_status();
}
ui_print_header(undef,$text{'geoip_city_title'},'',undef,1,1);
print wg_build_banner();
print wg_ui_foundation();
print '<div class="wg-ui">';
print '<div class="alert alert-danger">'.html_escape($error_message).'</div>' if $error_message;
print '<div class="alert alert-success">'.html_escape($notice).'</div>' if $notice;
print '<p>'.html_escape($text{'geoip_city_explain'}).'</p>';
my @city_dbs=grep { /GeoLite2-City\.mmdb$/ } wg_geoip_database_paths();
my $city_installed=@city_dbs ? 1 : 0;
print '<p>'.html_escape($text{'geoip_city_status'}).': '.
    html_escape($city_installed ? $text{'geoip_city_installed'} :
        ($status->{'configured'}?$text{'geoip_city_ready'}:$text{'geoip_city_unconfigured'})).'</p>';
print '<p class="help-block">'.html_escape($city_dbs[0]).'</p>' if $city_installed;
if (!$status->{'command_available'}) {
    print wg_ui_button(href=>'install_dependency.cgi?dependency=geoip',
        icon=>'download',action=>'navigate',label=>$text{'geoip_install_button'});
}
else {
    print ui_form_start(module_script_url('geoip_city_setup.cgi'),'post');
    print csrf_hidden();
    print ui_hidden('geoip_city_apply','1');
    print '<div class="wg-ui-form-row">'.
        '<label>'.html_escape($text{'geoip_city_account'}).
        ' <input name="account_id" inputmode="numeric" autocomplete="off" maxlength="20"></label> '.
        '<label>'.html_escape($text{'geoip_city_license'}).
        ' <input type="password" name="license_key" autocomplete="new-password" maxlength="128"></label>'.
        '</div>';
    print '<p class="help-block">'.html_escape($text{'geoip_city_existing'}).'</p>' if !$city_installed;
    print wg_ui_button(type=>'submit',icon=>'download',action=>'install',
        label=>$city_installed ? $text{'geoip_city_refresh'} : $text{'geoip_city_submit'});
    print ui_form_end();
}
print wg_ui_button(href=>'network_icons.cgi',icon=>'external',
    action=>'navigate',label=>$text{'unlocode_return'});
print '</div>';
ui_print_footer();
