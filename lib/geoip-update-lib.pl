=head1 geoip-update-lib.pl

Status and explicit activation of the distribution-provided MaxMind
geoipupdate.timer. Does not own, rewrite, or disable the vendor's units.
Credentials are held only in geoipupdate's own configuration file.

=cut

sub wg_geoip_update_conf_path
{
    my $override=$config{'geoipupdate_conf'} || '';
    return $override if $override =~ m{^/[A-Za-z0-9_/.-]+$} && -f $override;
    for my $path ('/etc/GeoIP.conf','/usr/local/etc/GeoIP.conf') {
        return $path if -f $path;
    }
    return $override if $override =~ m{^/[A-Za-z0-9_/.-]+$};
    return '/etc/GeoIP.conf';
}

sub wg_geoip_update_config_info
{
    my ($path)=@_;
    my %items;
    return {ready=>0,dir=>'',reason=>'missing_config'} if !$path || !-r $path;
    open(my $file,'<',$path) or return {ready=>0,dir=>'',reason=>'missing_config'};
    while (my $line=<$file>) {
        next if $line =~ /^\s*(?:#|$)/;
        if ($line =~ /^\s*(AccountID|LicenseKey|EditionIDs|DatabaseDirectory)\s+(.+?)\s*$/) {
            # Never return AccountID or LicenseKey to CGI, logs or JSON.
            $items{$1}=$2;
        }
    }
    close($file);
    my $account=$items{'AccountID'} || '';
    my $key=$items{'LicenseKey'} || '';
    my $editions=$items{'EditionIDs'} || '';
    my $ready=$account =~ /^\d+$/ &&
       $key =~ /^[A-Za-z0-9_-]{8,}$/ && $key !~ /^(?:YOUR|REPLACE|CHANGEME)/i &&
       $editions =~ /(?:^|\s)GeoLite2-(?:City|Country)(?:\s|$)/;
    my $dir=$items{'DatabaseDirectory'} || '';
    $dir='' if $dir !~ m{^/[A-Za-z0-9_/.-]+$};
    return {ready=>$ready?1:0, dir=>$dir,reason=>$ready?'': 'credentials'};
}

sub wg_geoip_database_paths
{
    my $info=wg_geoip_update_config_info(wg_geoip_update_conf_path());
    my @locations=($config{'geoip_city_db'} || '');
    my @dirs=grep { $_ && -d $_ }
        ($info->{'dir'},'/var/lib/GeoIP','/usr/share/GeoIP');
    for my $dir (@dirs) {
        push(@locations, "$dir/GeoLite2-City.mmdb", "$dir/GeoLite2-Country.mmdb");
    }
    my %seen;
    return grep { $_ && !$seen{$_}++ && -f $_ && -r $_ } @locations;
}

sub wg_geoip_update_status
{
    my $conf=wg_geoip_update_conf_path();
    my $cfg=wg_geoip_update_config_info($conf);
    my $exe=command_path('geoipupdate_cmd','/usr/bin/geoipupdate');
    my $ctl=command_path('systemctl_cmd','/usr/bin/systemctl');
    my @db=wg_geoip_database_paths();
    my ($database,$modified,$age)=('',0,0);
    for my $file (@db) {
        my $mtime=(stat($file))[9] || 0;
        if ($mtime>$modified) {
            $database=$file; $modified=$mtime;
        }
    }
    $age=$modified ? time()-$modified : 0;
    my %status=(
        config_path=>$conf,configured=>$cfg->{'ready'}?1:0,
        command_available=>has_command($exe)?1:0,
        database_path=>$database, database_mtime=>$modified,
        database_age_days=>$modified?int(($age>0?$age:0)/86400):undef,
        stale=>$modified && $age>14*86400?1:0,
        timer_available=>0,timer_enabled=>0,timer_active=>0
    );
    if (has_command($ctl)) {
        my ($ok,$out)=run_command([$ctl,'show','-p','LoadState','--value','geoipupdate.timer'],1,5,256);
        $out =~ s/\s+//g if defined($out);
        if ($ok && ($out||'') eq 'loaded') {
            $status{'timer_available'}=1;
            my ($enable_ok,$enabled)=run_command([$ctl,'is-enabled','geoipupdate.timer'],1,5,256);
            my ($active_ok,$active)=run_command([$ctl,'is-active','geoipupdate.timer'],1,5,256);
            $status{'timer_enabled'}=$enable_ok && ($enabled||'') =~ /^enabled\b/?1:0;
            $status{'timer_active'}=$active_ok && ($active||'') =~ /^active\b/?1:0;
        }
    }
    return \%status;
}

sub wg_geoip_enable_vendor_timer
{
    my $status=wg_geoip_update_status();
    return (0,'geoipupdate credentials are not configured in /etc/GeoIP.conf')
        if !$status->{'configured'};
    return (0,'geoipupdate executable is not installed')
        if !$status->{'command_available'};
    return (0,'Distribution geoipupdate.timer is not installed')
        if !$status->{'timer_available'};
    my $ctl=command_path('systemctl_cmd','/usr/bin/systemctl');
    my ($ok,$out)=run_command([$ctl,'enable','--now','geoipupdate.timer'],0,15,1024);
    return ($ok?1:0,$ok?'geoipupdate.timer enabled':($out||'Unable to enable geoipupdate.timer'));
}

1;
