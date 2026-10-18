#!/usr/bin/perl
use strict;
use warnings;
use FindBin;
use File::Temp qw(tempdir);
use File::Path qw(make_path);
our %config;
my $root=tempdir(CLEANUP=>1);
my $dir="$root/db";
make_path($dir);
my $config_file="$root/GeoIP.conf";
my $db="$dir/GeoLite2-City.mmdb";
sub write_conf {
    my ($credentials)=@_;
    open(my $f,'>',$config_file) or die $!;
    print {$f} "AccountID 123456\n";
    print {$f} "LicenseKey ".($credentials?'MockLicenseKeyAB123456':'YOUR_LICENSE_KEY_HERE')."\n";
    print {$f} "EditionIDs GeoLite2-City GeoLite2-Country\n";
    print {$f} "DatabaseDirectory $dir\n";
    close($f);
    chmod(0600,$config_file);
}
open(my $db_handle,'>',$db) or die $!;
print {$db_handle} "mmdb placeholder\n";
close($db_handle);
utime(time()-20*86400,time()-20*86400,$db);
write_conf(1);
$config{'geoipupdate_conf'}=$config_file;
$config{'geoipupdate_cmd'}='/mock/geoipupdate';
$config{'systemctl_cmd'}='/mock/systemctl';
my $timer='disabled';
my @calls;
sub command_path { return $config{$_[0]} || $_[1]; }
sub has_command { return $_[0] =~ m{^/mock/(?:systemctl|geoipupdate)$} ? 1 : 0; }
sub run_command {
    my ($args)=@_;
    push(@calls,join(' ',@$args));
    my $query=join(' ',@$args);
    if($query =~ /show -p LoadState --value geoipupdate\.timer$/){
        return (1,'loaded',0,$query);
    }
    if($query =~ /is-enabled geoipupdate\.timer$/){
        return ($timer eq 'enabled'?1:0,$timer,0,$query);
    }
    if($query =~ /is-active geoipupdate\.timer$/){
        return ($timer eq 'enabled'?1:0,$timer eq 'enabled'?'active':'inactive',0,$query);
    }
    if($query =~ /enable --now geoipupdate\.timer$/){
        $timer='enabled';
        return (1,'',0,$query);
    }
    die "Unexpected systemctl action $query";
}
require "$FindBin::Bin/../lib/geoip-update-lib.pl";
my $conf=wg_geoip_update_config_info($config_file);
die "valid MaxMind config incorrectly rejected\n" unless $conf->{'ready'};
die "DatabaseDirectory is ignored\n" unless $conf->{'dir'} eq $dir;
my $bad=wg_geoip_update_status();
die "old local City DB age not detected\n"
    unless $bad->{'stale'} && $bad->{'database_age_days'}>=20 &&
           $bad->{'database_path'} eq $db;
die "disabled timer not detected\n"
    unless $bad->{'timer_available'} && !$bad->{'timer_enabled'} &&
           !$bad->{'timer_active'};
die "credential leak in status\n" if join(' ',values %$bad) =~ /MockLicenseKeyAB123456/;
my @databases=wg_geoip_database_paths();
die "nonstandard geoipupdate DatabaseDirectory ignored\n"
    unless @databases==1 && $databases[0] eq $db;
my ($ok,$message)=wg_geoip_enable_vendor_timer();
die "explicit vendor timer enable failed: $message\n" unless $ok;
die "vendor timer enabled state not reflected\n"
    unless wg_geoip_update_status()->{'timer_active'};
die "duplicated timer service created\n" if grep { /\.service/ } @calls;
utime(time()-86400,time()-86400,$db);
die "newly refreshed City DB marked stale\n"
    if wg_geoip_update_status()->{'stale'};
write_conf(0);
die "placeholder MaxMind key incorrectly accepted\n"
    if wg_geoip_update_status()->{'configured'};
my $calls_before=@calls;
my ($allowed)=wg_geoip_enable_vendor_timer();
die "timer activation without usable credentials was permitted\n" if $allowed;
die "systemctl was invoked on bad credentials\n" if @calls > $calls_before+3;
unlink($db);
die "missing local DB treated as fresh\n"
    if wg_geoip_update_status()->{'database_path'};
my $manifest=do {
    open(my $f,'<',"$FindBin::Bin/../MANIFEST.wbm") or die $!;
    local $/; <$f>
};
die "vendor timer manager missing from module release\n"
    unless $manifest =~ /^lib\/geoip-update-lib\.pl$/m &&
           $manifest =~ /^geoip_timer\.cgi$/m;
my $endpoint=do {
    open(my $f,'<',"$FindBin::Bin/../geoip_timer.cgi") or die $!;
    local $/; <$f>
};
die "GeoIP timer endpoint lacks manage ACL, POST/CSRF or rate limiter\n"
    unless $endpoint =~ /assert_manage_access\(\)/ &&
           $endpoint =~ /assert_post_and_csrf\(\)/ &&
           $endpoint =~ /request_rate_limit\('geoip_timer'/;
my $page=do {
    open(my $f,'<',"$FindBin::Bin/../edit_peer.cgi") or die $!;
    local $/; <$f>
};
die "Peer page missing GeoIP database age and activation button\n"
    unless $page =~ /wg_geoip_update_status\(\)/ &&
           $page =~ /geoip_update_age/ &&
           $page =~ /ui_form_start\('geoip_timer\.cgi','post'\)/;
my $wizard=do {
    open(my $f,'<',"$FindBin::Bin/../geoip_city_setup.cgi") or die $!;
    local $/; <$f>
};
die "City setup wizard missing from distributable module\n"
    unless $manifest =~ /^geoip_city_setup\.cgi$/m;
die "City setup must require authenticated manage access and protected POST\n"
    unless $wizard =~ /assert_manage_access\(\)/ &&
           $wizard =~ /assert_post_and_csrf\(\)/ &&
           $wizard =~ /request_rate_limit\('geoip_city_setup'/;
die "City setup must protect credentials and use vendor config\n"
    unless $wizard =~ /autocomplete="new-password"/ &&
           $wizard =~ /chmod\(0600,\$temp\)/ &&
           $wizard =~ /\(\@editions,'GeoLite2-City'\)/ &&
           $wizard =~ /run_command\(\[\$exe,'-f',\$conf\]/;
print "GeoIP freshness, secure configuration and vendor timer activation tests passed\n";
